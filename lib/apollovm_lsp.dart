/// ApolloVM Language Server (LSP 3.17) — editor/agent tooling for ApolloVM
/// sources.
///
/// This library is part of the `apollovm` package but kept separate from
/// `package:apollovm/apollovm.dart` so importing the VM does not pull in the
/// language-server surface, and vice-versa.
///
/// It is **web-safe**: nothing here imports `dart:io`, so a browser-based IDE or
/// an AI agent can embed the server directly. Wire it up with:
///
/// * [MessageLspEndpoint] — a host that already exchanges decoded JSON-RPC
///   objects (web `postMessage`/`MessageChannel`, an in-process agent bridge):
///
///   ```dart
///   final endpoint = MessageLspEndpoint((msg) => port.postMessage(msg));
///   final server = LspServer(endpoint);
///   // deliver incoming messages:
///   endpoint.receive(incomingJsonRpcMap);
///   ```
///
/// * [StreamLspEndpoint] — byte streams with `Content-Length` framing (stdio,
///   sockets). The CLI exposes this via `apollovm lsp`.
///
/// To *consume* the server, use [LspClient], which correlates responses, streams
/// diagnostics, and exposes typed helpers ([LspClient.hover],
/// [LspClient.definition], …). [LspClient.inProcess] pairs a client with a fresh
/// server in the same isolate:
///
/// ```dart
/// final client = LspClient.inProcess();
/// await client.initialize();
/// client.didOpen('file:///Foo.dart', source);
/// final hover = await client.hover('file:///Foo.dart', Position(2, 13));
/// ```
library;

export 'src/lsp/analysis/analyzer.dart';
export 'src/lsp/analysis/doc_extractor.dart';
export 'src/lsp/analysis/document_store.dart';
export 'src/lsp/analysis/line_index.dart';
export 'src/lsp/analysis/parse_error_locator.dart';
export 'src/lsp/analysis/symbols.dart';
export 'src/lsp/analysis/token_index.dart';
export 'src/lsp/client/client.dart';
export 'src/lsp/protocol/protocol.dart';
export 'src/lsp/server/server.dart';
export 'src/lsp/transport/json_rpc.dart';
