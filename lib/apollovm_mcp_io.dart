// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

/// Native (`dart:io`) MCP server extras for ApolloVM.
///
/// Re-exports the web-safe [`apollovm_mcp`](apollovm_mcp.dart) surface (server,
/// config, tools) and adds the transports and CLI that need `dart:io`:
///
/// * `serveStdio` — run the server over stdio (the standard local MCP
///   transport).
/// * `HttpSseTransport` — serve over HTTP/SSE for networked use.
/// * `CommandMcp` — the `apollovm mcp …` command group for the CLI.
///
/// Import this on the Dart VM / native. For the web (dart2js / DDC), import
/// `package:apollovm/apollovm_mcp.dart` and drive [ApolloMcpServer] over an
/// in-process `StreamChannel<String>` instead.
library;

export 'apollovm_mcp.dart';
export 'apollovm_repository_io.dart'; // adds the on-disk LocalRepositoryAdapter
export 'src/mcp/cli/mcp_command.dart';
export 'src/mcp/transport/http_sse_transport.dart';
export 'src/mcp/transport/stdio_transport.dart';
