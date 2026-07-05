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
/// definition, references, completion and workspace-wide symbol search) — all
/// over stdio or HTTP/SSE, with a configurable security model (per-tool isolate
/// execution, timeout, and input/output limits).
library;

export 'src/mcp/apollo_mcp_server.dart';
export 'src/mcp/cli/mcp_command.dart';
export 'src/mcp/mcp_config.dart';
export 'src/mcp/runtime/isolate_executor.dart'
    show computeToolIsolated, runToolInIsolate;
export 'src/mcp/runtime/lsp_runtime.dart' show LspRuntime;
export 'src/mcp/tools/apollo_tools.dart' show allToolNames, computeTool;
export 'src/mcp/tools/lsp_tools.dart'
    show buildLspTools, computeLspTool, isLspTool, lspToolNames;
export 'src/mcp/transport/http_sse_transport.dart';
export 'src/mcp/transport/stdio_transport.dart';
