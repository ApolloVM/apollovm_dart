// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:convert';

import 'package:apollovm/apollovm.dart' show ApolloVM;
import 'package:dart_mcp/server.dart';
import 'package:stream_channel/stream_channel.dart';

import '../repository/permission_guard.dart';
import '../repository/repo_config.dart';
import '../repository/repository_adapter.dart';
import 'mcp_config.dart';
import 'runtime/isolate_executor.dart';
import 'runtime/repo_runtime.dart';
import 'tools/apollo_tools.dart';

/// An MCP server exposing ApolloVM as agent tools over a [StreamChannel].
///
/// Built on the official `dart_mcp` SDK: it speaks MCP (`initialize` /
/// `tools/list` / `tools/call`) over any newline-delimited `StreamChannel`
/// — a stdio channel for local use, or the HTTP/SSE channel adapter for
/// networked use. Each tool runs either in-process or (per [McpLimits.isolateTools])
/// inside a killable isolate for a hard timeout.
///
/// When a [RepositoryAdapter] is supplied, the server additionally exposes the
/// workspace/repository tools (`apollovm.fs.*`, `apollovm.search.*`,
/// `apollovm.code.*`, `apollovm.git.*`), letting an agent read, search, navigate
/// and version-control real files instead of shelling out to POSIX. Wrap the
/// adapter in a [PermissionGuard] to enforce a [RepoConfig] (read-only by
/// default). With no adapter, the server stays inline-source-only.
final class ApolloMcpServer extends MCPServer with ToolsSupport {
  final McpLimits limits;

  /// The workspace/repository runtime, present only when an adapter was given.
  final RepoRuntime? _repo;

  /// Server-wide default for the tools' `nullSafety` argument (the
  /// `--null-safety` flag). A per-call argument always overrides it.
  final bool nullSafetyChecks;

  ApolloMcpServer(
    super.channel, {
    this.limits = const McpLimits(),
    this.nullSafetyChecks = false,
    RepositoryAdapter? repository,
    RepoConfig repoConfig = const RepoConfig(),
  }) : _repo = repository == null
           ? null
           : RepoRuntime(
               repository is PermissionGuard
                   ? repository
                   : PermissionGuard(repository, config: repoConfig),
             ),
       super.fromStreamChannel(
         implementation: Implementation(
           name: 'apollovm-mcp',
           version: ApolloVM.VERSION,
         ),
         instructions:
             'ApolloVM programmable execution engine and code-inspection server. '
             'Core tools parse, execute, translate and compile source; the '
             '`apollovm.lsp.*` tools inspect it like an editor (diagnostics, '
             'outline, hover, definition, references, completion and '
             'workspace-wide symbol search). All of those operate on inline '
             'source strings. When a workspace is configured, the '
             '`apollovm.fs.*` / `apollovm.search.*` / `apollovm.code.*` / '
             '`apollovm.git.*` tools operate on real files in the repository '
             '(read-only unless writes/git-mutation are enabled) — prefer them '
             'over POSIX shell commands. Tools: ${allToolNames.join(', ')}'
             '${repository == null ? '' : ', ${repoToolNames.join(', ')}'}. '
             'No file or network access is granted to executed code.',
       ) {
    for (final tool in buildTools()) {
      registerTool(tool, (request) => _handle(tool.name, request));
    }
    if (_repo != null) {
      for (final tool in buildRepoTools()) {
        registerTool(tool, (request) => _handleRepo(tool.name, request));
      }
    }
  }

  Future<CallToolResult> _handle(String name, CallToolRequest request) async {
    final requestArgs = request.arguments ?? const <String, Object?>{};

    // Merge the server default into the args here — this is the one dispatch
    // point shared by the in-process and isolate paths, and `_IsolateJob`
    // carries only `args`/`limits`, so a field on the server would not reach a
    // spawned isolate. Spread last so a per-call value wins.
    final args = <String, Object?>{
      if (nullSafetyChecks) 'nullSafety': true,
      ...requestArgs,
    };

    final Map<String, Object?> result;
    if (limits.runsInIsolate(name)) {
      final timeoutMs = mcpCoerceInt(args['timeoutMs']) ?? limits.timeoutMs;
      result = await runToolInIsolate(
        name,
        args,
        limits,
        Duration(milliseconds: timeoutMs),
      );
    } else {
      result = await computeTool(name, args, limits);
    }

    return _asResult(result);
  }

  /// Handles a workspace/repository tool via the stateful [RepoRuntime]. These
  /// hold live filesystem/git handles, so they run in-process (never in the
  /// isolate path, which is for untrusted executed code).
  Future<CallToolResult> _handleRepo(
    String name,
    CallToolRequest request,
  ) async {
    final args = request.arguments ?? const <String, Object?>{};
    final result = await _repo!.call(name, args);
    return _asResult(result);
  }

  CallToolResult _asResult(Map<String, Object?> result) => CallToolResult(
    content: [TextContent(text: jsonEncode(result))],
    isError: result['isError'] == true,
  );
}
