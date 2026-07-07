// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

/// MCP (Model Context Protocol) server for ApolloVM.
///
/// Exposes ApolloVM's parse / execute / translate / compile capabilities to AI
/// agents as MCP tools (`apollovm.parse`, `apollovm.execute`,
/// `apollovm.translate`, `apollovm.ast`, `apollovm.symbols`, `apollovm.types`,
/// `apollovm.wasm`), plus a set of `apollovm.lsp.*` tools that let an agent
/// inspect code the way an editor does (diagnostics, outline, hover,
/// definition, references, completion and workspace-wide symbol search).
///
/// This library is **web-safe**: it imports no `dart:io` and no `dart:isolate`,
/// so a browser IDE or an embedded agent can run the server and all tools
/// in-process. Construct an [ApolloMcpServer] on any `StreamChannel<String>`.
/// On native, tools flagged by [McpLimits.isolateTools] run in a killable
/// isolate for a hard timeout; on the web they run in-process with a
/// cooperative timeout (see `isolate_executor.dart`).
///
/// The native-only transports and CLI (stdio, HTTP/SSE, the `mcp` command)
/// live in `package:apollovm/apollovm_mcp_io.dart`, which requires `dart:io`.
library;

export 'src/mcp/apollo_mcp_server.dart';
export 'src/mcp/mcp_config.dart';
export 'src/mcp/repo/in_memory_repository_adapter.dart';
export 'src/mcp/repo/permission_guard.dart';
export 'src/mcp/repo/repository_adapter.dart';
export 'src/mcp/runtime/isolate_executor.dart'
    show computeToolIsolated, runToolInIsolate;
export 'src/mcp/runtime/lsp_runtime.dart' show LspRuntime;
export 'src/mcp/runtime/repo_runtime.dart'
    show RepoRuntime, buildRepoTools, isRepoTool, repoToolNames;
export 'src/mcp/tools/apollo_tools.dart' show allToolNames, computeTool;
export 'src/mcp/tools/lsp_tools.dart'
    show buildLspTools, computeLspTool, isLspTool, lspToolNames;
