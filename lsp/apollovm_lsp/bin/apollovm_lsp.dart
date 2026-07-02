// Entrypoint for the ApolloVM language server. Speaks LSP (JSON-RPC 2.0 with
// `Content-Length` framing) over stdin/stdout.
import 'dart:io';

import 'package:apollovm_lsp/src/server/server.dart';
import 'package:apollovm_lsp/src/transport/json_rpc.dart';

Future<void> main(List<String> args) async {
  // LSP clients speak binary framing on stdout; disable any line translation.
  stdout.encoding = SystemEncoding();

  final connection = LspConnection(stdin, stdout);
  final server = LspServer(connection);
  server.start();

  await server.done;
  exitCode = server.cleanExit ? 0 : 1;
}
