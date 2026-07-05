// A JSON-RPC client for the ApolloVM language server. It correlates responses
// to the requests it sends, streams server-pushed diagnostics, and exposes
// typed convenience wrappers over the LSP requests the server implements.
//
// Like the rest of `apollovm_lsp`, this imports no `dart:io`; it drives any
// [LspEndpoint] — [MessageLspEndpoint] in-process/web, [StreamLspEndpoint] over
// stdio or a socket.
import 'dart:async';

import '../protocol/protocol.dart';
import '../server/server.dart';
import '../transport/json_rpc.dart';

/// Handles a server->client request (rare; e.g. `window/showMessageRequest`).
/// Return the result, or throw [ResponseError]; returning null replies with a
/// null result.
typedef ServerRequestHandler =
    FutureOr<Object?> Function(String method, Object? params);

/// A client for the ApolloVM [LspServer].
///
/// Send requests with the typed helpers ([hover], [definition], [completion],
/// …) or the low-level [sendRequest]/[sendNotification], and listen for
/// server-pushed diagnostics on [diagnostics].
///
/// ```dart
/// final client = LspClient.inProcess();     // client + server, same isolate
/// await client.initialize();
/// client.initialized();
/// client.diagnostics.listen((d) => print('${d.uri}: ${d.diagnostics.length}'));
/// client.didOpen('file:///Foo.dart', source);
/// final hover = await client.hover('file:///Foo.dart', Position(2, 13));
/// ```
///
/// For an out-of-process server, wrap its transport instead:
/// ```dart
/// final client = LspClient(StreamLspEndpoint(proc.stdout, proc.stdin))..start();
/// ```
class LspClient {
  final LspEndpoint _endpoint;

  var _nextId = 1;
  final _pending = <int, Completer<Object?>>{};
  final _diagnostics = StreamController<PublishDiagnosticsParams>.broadcast();
  bool _closed = false;

  /// Optional handler for requests the server sends to the client. When null,
  /// such requests are answered with a `methodNotFound` error.
  ServerRequestHandler? onServerRequest;

  /// Optional sink for every incoming notification, called after built-in
  /// handling (e.g. diagnostics are still delivered to [diagnostics]).
  NotificationHandler? onNotification;

  /// Wraps an existing [endpoint]. Call [start] before exchanging messages so a
  /// stream-based endpoint begins reading; message-based endpoints deliver
  /// incoming messages through their own `receive`.
  LspClient(this._endpoint) {
    _endpoint.onResponse = _onResponse;
    _endpoint.onNotification = _onNotification;
    _endpoint.onRequest = _onRequest;
  }

  /// Creates a client wired to a fresh in-process [LspServer] over a linked pair
  /// of [MessageLspEndpoint]s. Ideal for embedding (web IDE, AI agent) and
  /// tests — no subprocess, no `dart:io`.
  factory LspClient.inProcess() {
    late final MessageLspEndpoint serverEndpoint;
    final clientEndpoint = MessageLspEndpoint(
      (msg) => serverEndpoint.receive(msg),
    );
    serverEndpoint = MessageLspEndpoint((msg) => clientEndpoint.receive(msg));

    LspServer(serverEndpoint).start();
    return LspClient(clientEndpoint)..start();
  }

  /// The underlying transport.
  LspEndpoint get endpoint => _endpoint;

  /// Server-pushed `textDocument/publishDiagnostics` notifications.
  Stream<PublishDiagnosticsParams> get diagnostics => _diagnostics.stream;

  /// Completes when the transport closes.
  Future<void> get done => _endpoint.done;

  /// Begins consuming the transport (no-op for message-based endpoints).
  void start() => _endpoint.listen();

  // --- Low-level JSON-RPC ---

  /// Sends a request and completes with its `result`, or completes with a
  /// [ResponseError] if the server replied with an error.
  Future<Object?> sendRequest(String method, [Object? params]) {
    if (_closed) {
      throw StateError('LspClient is closed');
    }
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _endpoint.writeMessage({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': ?params,
    });
    return completer.future;
  }

  /// Sends a fire-and-forget notification.
  void sendNotification(String method, [Object? params]) {
    _endpoint.sendNotification(method, params);
  }

  // --- Lifecycle ---

  /// Performs the `initialize` handshake and returns the server's capabilities.
  /// Follow with [initialized] once ready.
  Future<InitializeResult> initialize({
    Map<String, Object?>? capabilities,
    String? rootUri,
    Map<String, Object?>? initializationOptions,
  }) async {
    final result = await sendRequest('initialize', {
      'processId': null,
      'capabilities': capabilities ?? const <String, Object?>{},
      'rootUri': ?rootUri,
      'initializationOptions': ?initializationOptions,
    });
    return InitializeResult.fromJson((result as Map).cast<String, Object?>());
  }

  /// Notifies the server the client is ready (sent after [initialize]).
  void initialized() => sendNotification('initialized', const {});

  /// Requests a graceful `shutdown`; pair with [exit].
  Future<void> shutdown() async {
    await sendRequest('shutdown');
  }

  /// Tells the server to `exit`.
  void exit() => sendNotification('exit', null);

  // --- Text document sync ---

  /// Opens [uri] with [text]. Diagnostics arrive on [diagnostics].
  void didOpen(
    String uri,
    String text, {
    String languageId = 'dart',
    int version = 1,
  }) {
    sendNotification('textDocument/didOpen', {
      'textDocument': {
        'uri': uri,
        'languageId': languageId,
        'version': version,
        'text': text,
      },
    });
  }

  /// Replaces the whole content of [uri] with [text] (a full-document change).
  void didChange(String uri, String text, {int? version}) {
    sendNotification('textDocument/didChange', {
      'textDocument': {'uri': uri, 'version': ?version},
      'contentChanges': [
        {'text': text},
      ],
    });
  }

  /// Closes [uri]; the server clears its diagnostics.
  void didClose(String uri) {
    sendNotification('textDocument/didClose', {
      'textDocument': {'uri': uri},
    });
  }

  // --- Language features ---

  /// Hover information at [position] in [uri], or null if none.
  Future<Hover?> hover(String uri, Position position) async {
    final r = await _positional('textDocument/hover', uri, position);
    return r is Map ? Hover.fromJson(r.cast<String, Object?>()) : null;
  }

  /// The declaration location for the symbol at [position], or null.
  Future<Location?> definition(String uri, Position position) async {
    final r = await _positional('textDocument/definition', uri, position);
    if (r is Map) return Location.fromJson(r.cast<String, Object?>());
    if (r is List && r.isNotEmpty) {
      return Location.fromJson((r.first as Map).cast<String, Object?>());
    }
    return null;
  }

  /// The document outline (hierarchical [DocumentSymbol]s) for [uri].
  Future<List<DocumentSymbol>> documentSymbol(String uri) async {
    final r = await sendRequest('textDocument/documentSymbol', {
      'textDocument': {'uri': uri},
    });
    return [
      for (final s in (r as List?) ?? const [])
        DocumentSymbol.fromJson((s as Map).cast<String, Object?>()),
    ];
  }

  /// Completion proposals at [position] in [uri].
  Future<CompletionList> completion(String uri, Position position) async {
    final r = await _positional('textDocument/completion', uri, position);
    if (r is Map) return CompletionList.fromJson(r.cast<String, Object?>());
    if (r is List) {
      return CompletionList(
        items: [
          for (final i in r)
            CompletionItem.fromJson((i as Map).cast<String, Object?>()),
        ],
      );
    }
    return const CompletionList();
  }

  /// All references to the symbol at [position] in [uri].
  Future<List<Location>> references(
    String uri,
    Position position, {
    bool includeDeclaration = true,
  }) async {
    final r = await sendRequest('textDocument/references', {
      'textDocument': {'uri': uri},
      'position': position.toJson(),
      'context': {'includeDeclaration': includeDeclaration},
    });
    return [
      for (final l in (r as List?) ?? const [])
        Location.fromJson((l as Map).cast<String, Object?>()),
    ];
  }

  /// Every occurrence to highlight for the symbol at [position] in [uri].
  Future<List<DocumentHighlight>> documentHighlight(
    String uri,
    Position position,
  ) async {
    final r = await _positional(
      'textDocument/documentHighlight',
      uri,
      position,
    );
    return [
      for (final h in (r as List?) ?? const [])
        DocumentHighlight.fromJson((h as Map).cast<String, Object?>()),
    ];
  }

  /// Checks whether the symbol at [position] can be renamed, returning its range
  /// and current text, or null if it cannot (no identifier under the cursor).
  Future<PrepareRenameResult?> prepareRename(
    String uri,
    Position position,
  ) async {
    final r = await _positional('textDocument/prepareRename', uri, position);
    return r is Map
        ? PrepareRenameResult.fromJson(r.cast<String, Object?>())
        : null;
  }

  /// A [WorkspaceEdit] renaming the symbol at [position] to [newName], or null.
  Future<WorkspaceEdit?> rename(
    String uri,
    Position position,
    String newName,
  ) async {
    final r = await sendRequest('textDocument/rename', {
      'textDocument': {'uri': uri},
      'position': position.toJson(),
      'newName': newName,
    });
    return r is Map ? WorkspaceEdit.fromJson(r.cast<String, Object?>()) : null;
  }

  /// Workspace-wide symbols matching [query] (empty matches all).
  Future<List<WorkspaceSymbol>> workspaceSymbol(String query) async {
    final r = await sendRequest('workspace/symbol', {'query': query});
    return [
      for (final s in (r as List?) ?? const [])
        WorkspaceSymbol.fromJson((s as Map).cast<String, Object?>()),
    ];
  }

  // --- Internals ---

  Future<Object?> _positional(String method, String uri, Position position) =>
      sendRequest(method, {
        'textDocument': {'uri': uri},
        'position': position.toJson(),
      });

  void _onResponse(Map<String, Object?> message) {
    final id = message['id'];
    final key = id is num ? id.toInt() : null;
    final completer = key == null ? null : _pending.remove(key);
    if (completer == null || completer.isCompleted) return;

    final error = message['error'];
    if (error is Map) {
      completer.completeError(
        ResponseError(
          (error['code'] as num?)?.toInt() ?? ResponseError.internalError,
          (error['message'] ?? 'LSP error').toString(),
        ),
      );
    } else {
      completer.complete(message['result']);
    }
  }

  void _onNotification(String method, Object? params) {
    if (method == 'textDocument/publishDiagnostics' && params is Map) {
      if (!_diagnostics.isClosed) {
        _diagnostics.add(
          PublishDiagnosticsParams.fromJson(params.cast<String, Object?>()),
        );
      }
    }
    onNotification?.call(method, params);
  }

  FutureOr<Object?> _onRequest(String method, Object? params) {
    final handler = onServerRequest;
    if (handler == null) {
      throw ResponseError(
        ResponseError.methodNotFound,
        "Client cannot handle request '$method'",
      );
    }
    return handler(method, params);
  }

  /// Releases resources: fails any in-flight requests and closes [diagnostics].
  /// Does not itself send `shutdown`/`exit` — call those first for a clean stop.
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('LspClient disposed'));
      }
    }
    _pending.clear();
    await _diagnostics.close();
  }
}
