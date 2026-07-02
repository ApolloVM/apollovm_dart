// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:convert';

import 'package:apollovm/apollovm.dart' show ApolloVM;
import 'package:dart_mcp/server.dart';
import 'package:stream_channel/stream_channel.dart';

import 'mcp_config.dart';
import 'runtime/isolate_executor.dart';
import 'tools/apollo_tools.dart';

/// An MCP server exposing ApolloVM as agent tools over a [StreamChannel].
///
/// Built on the official `dart_mcp` SDK: it speaks MCP (`initialize` /
/// `tools/list` / `tools/call`) over any newline-delimited `StreamChannel`
/// — a stdio channel for local use, or the HTTP/SSE channel adapter for
/// networked use. Each tool runs either in-process or (per [McpLimits.isolateTools])
/// inside a killable isolate for a hard timeout.
final class ApolloMcpServer extends MCPServer with ToolsSupport {
  final McpLimits limits;

  ApolloMcpServer(super.channel, {this.limits = const McpLimits()})
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'apollovm-mcp',
          version: ApolloVM.VERSION,
        ),
        instructions:
            'ApolloVM programmable execution engine. Tools: '
            '${allToolNames.join(', ')}. All operate on inline source strings; '
            'no file or network access is granted to executed code.',
      ) {
    for (final tool in buildTools()) {
      registerTool(tool, (request) => _handle(tool.name, request));
    }
  }

  Future<CallToolResult> _handle(String name, CallToolRequest request) async {
    final args = request.arguments ?? const <String, Object?>{};

    final Map<String, Object?> result;
    if (limits.runsInIsolate(name)) {
      final timeoutMs = (args['timeoutMs'] as int?) ?? limits.timeoutMs;
      result = await runToolInIsolate(
        name,
        args,
        limits,
        Duration(milliseconds: timeoutMs),
      );
    } else {
      result = await computeTool(name, args, limits);
    }

    return CallToolResult(
      content: [TextContent(text: jsonEncode(result))],
      isError: result['isError'] == true,
    );
  }
}
