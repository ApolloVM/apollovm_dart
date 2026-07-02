// JSON-RPC 2.0 transport over a byte stream, using LSP `Content-Length`
// framing. This layer knows nothing about LSP methods — it only frames,
// decodes, dispatches by kind (request vs notification), and encodes replies.
import 'dart:async';
import 'dart:convert';

/// An error returned in a JSON-RPC response `error` object.
class ResponseError implements Exception {
  final int code;
  final String message;

  const ResponseError(this.code, this.message);

  /// LSP/JSON-RPC well-known codes.
  static const int parseError = -32700;
  static const int invalidRequest = -32600;
  static const int methodNotFound = -32601;
  static const int invalidParams = -32602;
  static const int internalError = -32603;
  static const int requestCancelled = -32800;

  Map<String, Object?> toJson() => {'code': code, 'message': message};

  @override
  String toString() => 'ResponseError($code): $message';
}

/// Handles an incoming request; returns the result or throws [ResponseError].
typedef RequestHandler = FutureOr<Object?> Function(
    String method, Object? params);

/// Handles an incoming notification (no reply).
typedef NotificationHandler = void Function(String method, Object? params);

/// A JSON-RPC connection over LSP `Content-Length`-framed streams.
class LspConnection {
  final Stream<List<int>> _input;
  final StreamSink<List<int>> _output;

  RequestHandler? onRequest;
  NotificationHandler? onNotification;

  final _buffer = <int>[];
  final _completer = Completer<void>();

  LspConnection(this._input, this._output);

  /// Resolves when the input stream closes.
  Future<void> get done => _completer.future;

  /// Begins consuming the input stream.
  void listen() {
    _input.listen(
      _onData,
      onDone: () {
        if (!_completer.isCompleted) _completer.complete();
      },
      onError: (Object e) {
        if (!_completer.isCompleted) _completer.completeError(e);
      },
      cancelOnError: false,
    );
  }

  void _onData(List<int> chunk) {
    _buffer.addAll(chunk);
    _drain();
  }

  /// Parses as many complete frames as the buffer currently holds.
  void _drain() {
    while (true) {
      final headerEnd = _indexOfHeaderEnd();
      if (headerEnd < 0) return; // Headers incomplete.

      final headerBytes = _buffer.sublist(0, headerEnd);
      final contentLength = _parseContentLength(utf8.decode(headerBytes));
      final bodyStart = headerEnd + 4; // past "\r\n\r\n"

      if (contentLength == null) {
        // Malformed header block: drop it and continue.
        _buffer.removeRange(0, bodyStart);
        continue;
      }

      if (_buffer.length < bodyStart + contentLength) return; // Body incomplete.

      final bodyBytes = _buffer.sublist(bodyStart, bodyStart + contentLength);
      _buffer.removeRange(0, bodyStart + contentLength);

      _dispatch(utf8.decode(bodyBytes));
    }
  }

  /// Index of the `\r\n\r\n` header terminator, or -1.
  int _indexOfHeaderEnd() {
    for (var i = 0; i + 3 < _buffer.length; i++) {
      if (_buffer[i] == 0x0d &&
          _buffer[i + 1] == 0x0a &&
          _buffer[i + 2] == 0x0d &&
          _buffer[i + 3] == 0x0a) {
        return i;
      }
    }
    return -1;
  }

  int? _parseContentLength(String headers) {
    for (final line in headers.split('\r\n')) {
      final idx = line.indexOf(':');
      if (idx < 0) continue;
      final name = line.substring(0, idx).trim().toLowerCase();
      if (name == 'content-length') {
        return int.tryParse(line.substring(idx + 1).trim());
      }
    }
    return null;
  }

  void _dispatch(String body) {
    Object? message;
    try {
      message = json.decode(body);
    } catch (_) {
      return; // Ignore undecodable frames.
    }
    if (message is! Map<String, Object?>) return;

    final id = message['id'];
    final method = message['method'];
    final params = message['params'];

    if (method is! String) {
      // A response to a server->client request; unused for now.
      return;
    }

    if (id == null) {
      // Notification.
      try {
        onNotification?.call(method, params);
      } catch (_) {
        // Notifications must not produce a reply, even on error.
      }
      return;
    }

    // Request: must reply with the same id.
    _handleRequest(id, method, params);
  }

  Future<void> _handleRequest(Object? id, String method, Object? params) async {
    final handler = onRequest;
    if (handler == null) {
      _sendError(id, const ResponseError(
          ResponseError.methodNotFound, 'No request handler'));
      return;
    }
    try {
      final result = await handler(method, params);
      _sendResult(id, result);
    } on ResponseError catch (e) {
      _sendError(id, e);
    } catch (e) {
      _sendError(
          id, ResponseError(ResponseError.internalError, e.toString()));
    }
  }

  /// Sends a notification to the client.
  void sendNotification(String method, Object? params) {
    _write({'jsonrpc': '2.0', 'method': method, 'params': params});
  }

  void _sendResult(Object? id, Object? result) {
    _write({'jsonrpc': '2.0', 'id': id, 'result': result});
  }

  void _sendError(Object? id, ResponseError error) {
    _write({'jsonrpc': '2.0', 'id': id, 'error': error.toJson()});
  }

  void _write(Map<String, Object?> message) {
    final body = utf8.encode(json.encode(message));
    final header = utf8.encode('Content-Length: ${body.length}\r\n\r\n');
    _output.add(header);
    _output.add(body);
  }
}
