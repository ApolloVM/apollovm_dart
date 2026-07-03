// JSON-RPC 2.0 for the ApolloVM language server, split so the server core stays
// transport-agnostic and web-safe:
//
//   * [LspEndpoint]        — the shared JSON-RPC dispatch (no I/O, no framing).
//   * [MessageLspEndpoint] — decoded-message level, for embedding in a web IDE,
//                            an AI agent, or any in-process host (no `dart:io`).
//   * [StreamLspEndpoint]  — byte streams with LSP `Content-Length` framing, for
//                            stdio or sockets. Uses only `dart:async`/`convert`,
//                            so it too compiles for the web.
//
// Nothing here imports `dart:io`; the stdio wiring lives in the `apollovm lsp` CLI command.
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
typedef RequestHandler =
    FutureOr<Object?> Function(String method, Object? params);

/// Handles an incoming notification (no reply).
typedef NotificationHandler = void Function(String method, Object? params);

/// Transport-agnostic JSON-RPC 2.0 endpoint. Subclasses supply the wire by
/// implementing [writeMessage] and feeding decoded messages to [handleMessage].
abstract class LspEndpoint {
  RequestHandler? onRequest;
  NotificationHandler? onNotification;

  /// Begins consuming input. No-op for push-based endpoints (e.g. web).
  void listen() {}

  /// Completes when the endpoint closes.
  Future<void> get done;

  /// Sends a notification to the peer.
  void sendNotification(String method, Object? params) =>
      writeMessage({'jsonrpc': '2.0', 'method': method, 'params': params});

  /// Writes a fully-formed JSON-RPC message to the wire.
  void writeMessage(Map<String, Object?> message);

  /// Routes one decoded incoming JSON-RPC message.
  Future<void> handleMessage(Object? message) async {
    if (message is! Map<String, Object?>) return;
    final method = message['method'];
    final id = message['id'];

    if (method is! String) {
      // A response to a server->client request; unused for now.
      return;
    }

    if (id == null) {
      // Notification.
      try {
        onNotification?.call(method, message['params']);
      } catch (_) {
        // Notifications must not produce a reply, even on error.
      }
      return;
    }

    // Request: must reply with the same id.
    final handler = onRequest;
    if (handler == null) {
      writeMessage(
        _error(
          id,
          const ResponseError(
            ResponseError.methodNotFound,
            'No request handler',
          ),
        ),
      );
      return;
    }
    try {
      final result = await handler(method, message['params']);
      writeMessage({'jsonrpc': '2.0', 'id': id, 'result': result});
    } on ResponseError catch (e) {
      writeMessage(_error(id, e));
    } catch (e) {
      writeMessage(
        _error(id, ResponseError(ResponseError.internalError, e.toString())),
      );
    }
  }

  Map<String, Object?> _error(Object? id, ResponseError error) => {
    'jsonrpc': '2.0',
    'id': id,
    'error': error.toJson(),
  };
}

/// A message-level endpoint for embedding the server in a host that already
/// exchanges decoded JSON-RPC objects — a web IDE (over `postMessage` / a
/// `MessageChannel`), an AI agent, or an in-process bridge.
///
/// Feed incoming messages with [receive]; outgoing messages are delivered to
/// the `send` callback. No byte framing, no `dart:io`.
class MessageLspEndpoint extends LspEndpoint {
  final void Function(Map<String, Object?> message) _send;
  final Completer<void> _done = Completer<void>();

  MessageLspEndpoint(this._send);

  /// Delivers a decoded JSON-RPC message from the peer to the server.
  void receive(Map<String, Object?> message) {
    handleMessage(message);
  }

  @override
  void writeMessage(Map<String, Object?> message) => _send(message);

  @override
  Future<void> get done => _done.future;

  /// Signals that the peer has disconnected.
  void close() {
    if (!_done.isCompleted) _done.complete();
  }
}

/// A byte-stream endpoint using LSP `Content-Length` framing. Suitable for
/// stdio (see the `apollovm lsp` CLI command) or a socket/WebSocket byte channel.
class StreamLspEndpoint extends LspEndpoint {
  final Stream<List<int>> _input;
  final StreamSink<List<int>> _output;

  final _buffer = <int>[];
  final _done = Completer<void>();

  StreamLspEndpoint(this._input, this._output);

  @override
  Future<void> get done => _done.future;

  @override
  void listen() {
    _input.listen(
      _onData,
      onDone: () {
        if (!_done.isCompleted) _done.complete();
      },
      onError: (Object e) {
        if (!_done.isCompleted) _done.completeError(e);
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
        _buffer.removeRange(0, bodyStart);
        continue;
      }

      if (_buffer.length < bodyStart + contentLength) {
        return; // Body incomplete.
      }

      final bodyBytes = _buffer.sublist(bodyStart, bodyStart + contentLength);
      _buffer.removeRange(0, bodyStart + contentLength);

      Object? decoded;
      try {
        decoded = json.decode(utf8.decode(bodyBytes));
      } catch (_) {
        continue; // Ignore undecodable frames.
      }
      handleMessage(decoded);
    }
  }

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

  @override
  void writeMessage(Map<String, Object?> message) {
    final body = utf8.encode(json.encode(message));
    final header = utf8.encode('Content-Length: ${body.length}\r\n\r\n');
    _output.add(header);
    _output.add(body);
  }
}
