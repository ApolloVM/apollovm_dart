// A batteries-included, in-process language service over the ApolloVM
// `LspServer` — no transport, no socket, no JSON-RPC handshake to run by hand.
//
// This is the highest-level entry point for embedding ApolloVM's language
// features directly in an application: a web app (compiled to JS), an AI agent,
// a test, or any Dart host. Like the rest of `apollovm_lsp` it imports no
// `dart:io`, so it runs unchanged in the browser.
//
// It wraps an in-process [LspClient]/[LspServer] pair (linked by decoded-message
// endpoints, so nothing is ever serialized to bytes), runs the
// `initialize`/`initialized` handshake for you, and tracks open documents and
// their versions — leaving a small, typed, document-oriented API.
import 'dart:async';

import '../analysis/analyzer.dart';
import '../client/client.dart';
import '../protocol/protocol.dart';

/// An in-process ApolloVM language service.
///
/// ```dart
/// final lsp = LspService();
///
/// // One-shot: analyze a buffer and get its diagnostics.
/// final errors = await lsp.analyze('file:///Foo.dart', source);
///
/// // Or open once and issue many queries as the buffer changes.
/// lsp.open('file:///Foo.dart', source);
/// final hover = await lsp.hover('file:///Foo.dart', Position(2, 13));
/// lsp.change('file:///Foo.dart', edited);
///
/// await lsp.dispose();
/// ```
///
/// Every query resolves against the current in-memory buffer, so results never
/// observe a stale document. Diagnostics are also pushed to [diagnostics] as the
/// server (re)analyzes.
class LspService {
  final LspClient _client;
  final bool _ownsClient;
  final Map<String, int> _versions = {};
  late final Future<InitializeResult> _ready;

  LspService._(this._client, this._ownsClient) {
    _ready = _handshake();
  }

  /// Creates a service backed by a fresh in-process server — no transport, no
  /// `dart:io`. The `initialize` handshake runs lazily; await [ready] (or any
  /// query) to observe the server's [InitializeResult].
  factory LspService() => LspService._(LspClient.inProcess(), true);

  /// Wraps an existing [client] (e.g. one connected to a remote server over a
  /// [StreamLspEndpoint]) with the same document-tracking convenience. The
  /// caller retains ownership: [dispose] will not dispose [client].
  factory LspService.wrap(LspClient client) => LspService._(client, false);

  Future<InitializeResult> _handshake() async {
    final result = await _client.initialize();
    _client.initialized();
    return result;
  }

  /// Completes with the server's capabilities once the handshake finishes.
  Future<InitializeResult> get ready => _ready;

  /// Server-pushed diagnostics, published as documents are (re)analyzed.
  Stream<PublishDiagnosticsParams> get diagnostics => _client.diagnostics;

  /// The underlying client, for advanced use (custom requests, lifecycle).
  LspClient get client => _client;

  /// Whether [uri] is currently open in the service.
  bool isOpen(String uri) => _versions.containsKey(uri);

  // --- Document management ---

  /// Opens [uri] with [text]. [languageId] defaults to the language inferred
  /// from the URI extension (falling back to `dart`).
  void open(String uri, String text, {String? languageId}) {
    _versions[uri] = 1;
    _client.didOpen(
      uri,
      text,
      languageId: languageId ?? Analyzer.languageOf(uri) ?? 'dart',
      version: 1,
    );
  }

  /// Replaces the whole content of an open [uri] with [text].
  void change(String uri, String text) {
    final version = (_versions[uri] ?? 0) + 1;
    _versions[uri] = version;
    _client.didChange(uri, text, version: version);
  }

  /// Closes [uri]; the server clears its diagnostics.
  void close(String uri) {
    _versions.remove(uri);
    _client.didClose(uri);
  }

  /// Sets the buffer for [uri] to [text] (opening it if new, otherwise
  /// changing it) and returns the diagnostics from the resulting analysis.
  ///
  /// The convenient one-call entry point for "check this code":
  /// ```dart
  /// final errors = await lsp.analyze('file:///Foo.dart', source);
  /// ```
  Future<List<Diagnostic>> analyze(
    String uri,
    String text, {
    String? languageId,
  }) async {
    await _ready;
    // Subscribe before mutating so the resulting publish is never missed.
    final next = _client.diagnostics.firstWhere((d) => d.uri == uri);
    if (isOpen(uri)) {
      change(uri, text);
    } else {
      open(uri, text, languageId: languageId);
    }
    return (await next).diagnostics;
  }

  // --- Language features ---

  /// Hover information at [position] in [uri], or null.
  Future<Hover?> hover(String uri, Position position) async {
    await _ready;
    return _client.hover(uri, position);
  }

  /// The declaration location for the symbol at [position], or null.
  Future<Location?> definition(String uri, Position position) async {
    await _ready;
    return _client.definition(uri, position);
  }

  /// The document outline (hierarchical [DocumentSymbol]s) for [uri].
  Future<List<DocumentSymbol>> documentSymbols(String uri) async {
    await _ready;
    return _client.documentSymbol(uri);
  }

  /// Completion proposals at [position] in [uri].
  Future<CompletionList> completion(String uri, Position position) async {
    await _ready;
    return _client.completion(uri, position);
  }

  /// All references to the symbol at [position] in [uri].
  Future<List<Location>> references(
    String uri,
    Position position, {
    bool includeDeclaration = true,
  }) async {
    await _ready;
    return _client.references(
      uri,
      position,
      includeDeclaration: includeDeclaration,
    );
  }

  /// Occurrences to highlight for the symbol at [position] in [uri].
  Future<List<DocumentHighlight>> documentHighlight(
    String uri,
    Position position,
  ) async {
    await _ready;
    return _client.documentHighlight(uri, position);
  }

  /// Whether the symbol at [position] can be renamed (its range + placeholder),
  /// or null.
  Future<PrepareRenameResult?> prepareRename(
    String uri,
    Position position,
  ) async {
    await _ready;
    return _client.prepareRename(uri, position);
  }

  /// A [WorkspaceEdit] renaming the symbol at [position] to [newName], or null.
  Future<WorkspaceEdit?> rename(
    String uri,
    Position position,
    String newName,
  ) async {
    await _ready;
    return _client.rename(uri, position, newName);
  }

  /// Workspace-wide symbols matching [query] (empty matches all open docs).
  Future<List<WorkspaceSymbol>> workspaceSymbols(String query) async {
    await _ready;
    return _client.workspaceSymbol(query);
  }

  /// Shuts the service down. When this service created its own server (the
  /// default), the underlying client is disposed too.
  Future<void> dispose() async {
    _versions.clear();
    if (_ownsClient) {
      await _client.shutdown().catchError((_) {});
      _client.exit();
      await _client.dispose();
    }
  }
}
