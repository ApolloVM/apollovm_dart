// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:collection/collection.dart' show IterableExtension;
import 'package:dart_mcp/server.dart' show ProtocolVersion;

import '../../../apollovm.dart' show ApolloVM, WasmRuntime;
import '../mcp_config.dart';
import '../runtime/isolate_executor.dart';
import '../tools/apollo_tools.dart';
import '../transport/http_sse_transport.dart';
import '../transport/stdio_transport.dart';

const _json = JsonEncoder.withIndent('  ');

/// The `mcp` command group: run the ApolloVM MCP server and inspect/use its
/// tools from the CLI.
///
/// Subcommands: `serve`, `list`, `call`, `info`, `schema`, `doctor`.
class CommandMcp extends Command<bool> {
  @override
  final String name = 'mcp';

  @override
  final String description =
      'ApolloVM MCP (Model Context Protocol) server and tools.';

  CommandMcp() {
    addSubcommand(CommandMcpServe());
    addSubcommand(CommandMcpList());
    addSubcommand(CommandMcpCall());
    addSubcommand(CommandMcpInfo());
    addSubcommand(CommandMcpSchema());
    addSubcommand(CommandMcpDoctor());
  }

  @override
  bool run() {
    // Invoked as bare `apollovm mcp` (no subcommand): show usage.
    printUsage();
    return true;
  }
}

/// Base for subcommands that accept the shared resource-limit options.
abstract class _McpLimitsCommand extends Command<bool> {
  _McpLimitsCommand() {
    argParser
      ..addOption(
        'timeout-ms',
        help: 'Execution timeout, in milliseconds.',
        defaultsTo: '5000',
      )
      ..addOption(
        'max-output-chars',
        help: 'Maximum captured console output per execution.',
        defaultsTo: '65536',
      )
      ..addOption(
        'max-source-chars',
        help: 'Maximum accepted source size, in characters.',
        defaultsTo: '262144',
      )
      ..addOption(
        'isolate-tools',
        help:
            'Comma-separated tools to run inside a killable isolate\n'
            '(the only way to enforce a hard timeout on runaway code).',
        defaultsTo: 'apollo.execute',
      );
  }

  int _intOption(String name) {
    var raw = argResults![name] as String?;
    var value = raw != null ? int.tryParse(raw.trim()) : null;
    if (value == null) {
      throw StateError("Invalid integer for --$name: $raw");
    }
    return value;
  }

  McpLimits get limits => McpLimits(
    timeoutMs: _intOption('timeout-ms'),
    maxOutputChars: _intOption('max-output-chars'),
    maxSourceChars: _intOption('max-source-chars'),
    isolateTools: (argResults!['isolate-tools'] as String)
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet(),
  );
}

/// `apollovm mcp serve` — run the MCP server over stdio or HTTP/SSE.
class CommandMcpServe extends _McpLimitsCommand {
  @override
  final String description =
      'Run the MCP server over stdio (default) or HTTP/SSE (`--http`).';

  @override
  final String name = 'serve';

  CommandMcpServe() {
    argParser
      ..addOption(
        'http',
        help:
            'Serve over HTTP/SSE on the given port instead of stdio.\n'
            '(omit to use the stdio transport)',
        valueHelp: 'port',
      )
      ..addOption(
        'host',
        help: 'Host/interface to bind for --http.',
        defaultsTo: '127.0.0.1',
      );
  }

  @override
  Future<bool> run() async {
    final limits = this.limits;
    final httpPort = argResults!['http'] as String?;

    if (httpPort != null) {
      final port = int.tryParse(httpPort.trim());
      if (port == null) {
        throw StateError("Invalid port for --http: $httpPort");
      }
      final host = argResults!['host'] as String;

      final transport = HttpSseTransport(limits: limits);
      await transport.start(port: port, host: host);
      stderr.writeln(
        'ApolloVM MCP server (HTTP/SSE) listening on http://$host:$port/sse',
      );
      await Completer<void>().future; // serve until terminated
      return true;
    }

    final server = serveStdio(limits: limits);
    await server.done;
    return true;
  }
}

/// `apollovm mcp list` — list the available MCP tools (JSON).
class CommandMcpList extends Command<bool> {
  @override
  final String description =
      'List the available MCP tools (names, descriptions, input schemas) as JSON.';

  @override
  final String name = 'list';

  @override
  bool run() {
    final tools = [
      for (final tool in buildTools())
        <String, Object?>{
          'name': tool.name,
          'description': tool.description,
          'inputSchema': tool.inputSchema,
        },
    ];
    print(_json.convert(tools));
    return true;
  }
}

/// `apollovm mcp schema [tool]` — print the JSON input schema(s) for tools.
class CommandMcpSchema extends Command<bool> {
  @override
  final String description =
      'Print the JSON input schema(s) for one tool (argument) or all tools.';

  @override
  final String name = 'schema';

  @override
  bool run() {
    final tools = buildTools();
    final rest = argResults!.rest;

    if (rest.isNotEmpty) {
      final wanted = _normalizeToolName(rest.first);
      final tool = tools.where((t) => t.name == wanted).firstOrNull;
      if (tool == null) {
        throw StateError(
          'Unknown tool: ${rest.first}. Known: ${allToolNames.join(', ')}',
        );
      }
      print(_json.convert(tool.inputSchema));
    } else {
      print(_json.convert({for (final t in tools) t.name: t.inputSchema}));
    }
    return true;
  }
}

/// `apollovm mcp info` — print server metadata and capabilities.
class CommandMcpInfo extends Command<bool> {
  @override
  final String description =
      'Print MCP server info: version, protocol, transports, languages, limits.';

  @override
  final String name = 'info';

  CommandMcpInfo() {
    argParser.addFlag(
      'json',
      help: 'Output as JSON instead of text.',
      negatable: false,
    );
  }

  @override
  bool run() {
    const limits = McpLimits();
    final info = <String, Object?>{
      'server': 'apollovm-mcp',
      'version': ApolloVM.VERSION,
      'protocol': ProtocolVersion.latestSupported.versionString,
      'transports': ['stdio', 'http-sse'],
      'tools': allToolNames,
      'languages': mcpSupportedLanguages,
      'limits': {
        'timeoutMs': limits.timeoutMs,
        'maxOutputChars': limits.maxOutputChars,
        'maxSourceChars': limits.maxSourceChars,
        'isolateTools': limits.isolateTools.toList(),
      },
    };

    if (argResults!['json'] as bool) {
      print(_json.convert(info));
    } else {
      print('server:     ${info['server']} ${info['version']}');
      print('protocol:   ${info['protocol']}');
      print('transports: ${(info['transports'] as List).join(', ')}');
      print('tools:      ${(info['tools'] as List).join(', ')}');
      print('languages:  ${(info['languages'] as List).join(', ')}');
      final l = info['limits'] as Map;
      print(
        'limits:     timeoutMs=${l['timeoutMs']} '
        'maxOutputChars=${l['maxOutputChars']} '
        'maxSourceChars=${l['maxSourceChars']} '
        'isolateTools=${(l['isolateTools'] as List).join(',')}',
      );
    }
    return true;
  }
}

/// `apollovm mcp call <tool>` — invoke one tool once and print its JSON result.
class CommandMcpCall extends _McpLimitsCommand {
  @override
  final String description =
      'Invoke a single MCP tool once and print its JSON result.';

  @override
  final String name = 'call';

  CommandMcpCall() {
    argParser
      ..addOption('language', abbr: 'l', help: 'Source language.')
      ..addOption('source', abbr: 's', help: 'Inline source code.')
      ..addOption(
        'file',
        abbr: 'f',
        help: 'Read source from a file (language inferred from extension).',
      )
      ..addOption('from', help: 'Source language (apollo.translate).')
      ..addOption('to', help: 'Target language (apollo.translate).')
      ..addOption('function', help: 'Entry function (apollo.execute).')
      ..addOption('class-name', help: 'Entry class (apollo.execute).')
      ..addOption(
        'args',
        help: 'JSON array of positional arguments (apollo.execute).',
      );
  }

  @override
  Future<bool> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      throw StateError('Missing tool name. Usage: apollovm mcp call <tool>');
    }
    final toolName = _normalizeToolName(rest.first);
    if (!allToolNames.contains(toolName)) {
      throw StateError(
        'Unknown tool: ${rest.first}. Known: ${allToolNames.join(', ')}',
      );
    }

    final file = argResults!['file'] as String?;
    final source = await _resolveSource(argResults!['source'] as String?, file);
    final language =
        (argResults!['language'] as String?) ??
        (file != null
            ? ApolloVM.parseLanguageFromFilePathExtension(file)
            : null);

    final args = <String, Object?>{};
    if (toolName == translateToolName) {
      args['from'] = argResults!['from'] ?? language;
      args['to'] = argResults!['to'];
      args['source'] = source;
    } else {
      args['language'] = language;
      args['source'] = source;
      if (toolName == executeToolName) {
        if (argResults!['function'] != null) {
          args['function'] = argResults!['function'];
        }
        if (argResults!['class-name'] != null) {
          args['className'] = argResults!['class-name'];
        }
        final rawArgs = argResults!['args'] as String?;
        if (rawArgs != null) {
          args['args'] = jsonDecode(rawArgs) as List;
        }
      }
    }

    final limits = this.limits;
    final result = limits.runsInIsolate(toolName)
        ? await computeToolIsolated(toolName, args, limits)
        : await computeTool(toolName, args, limits);

    print(_json.convert(result));
    if (result['isError'] == true) exitCode = 1;
    return result['isError'] != true;
  }

  /// Resolves the source string from `--source`, `--file`, or stdin.
  Future<String> _resolveSource(String? inline, String? file) async {
    if (inline != null) return inline;
    if (file != null) return File(file).readAsStringSync();
    // Fall back to stdin (e.g. piped input).
    return await stdin.transform(utf8.decoder).join();
  }
}

/// `apollovm mcp doctor` — check the MCP server and its capabilities.
class CommandMcpDoctor extends Command<bool> {
  @override
  final String description =
      'Check the MCP server environment and report available capabilities.';

  @override
  final String name = 'doctor';

  @override
  Future<bool> run() async {
    var ok = true;

    void report(bool pass, String message, {bool warnOnly = false}) {
      final tag = pass ? 'ok  ' : (warnOnly ? 'warn' : 'FAIL');
      if (!pass && !warnOnly) ok = false;
      print('$tag  $message');
    }

    // Tools register.
    final tools = buildTools();
    report(
      tools.length == allToolNames.length,
      '${tools.length} tools registered',
    );

    const limits = McpLimits();
    const dart = 'int main(List a){ print("ok"); return 1; }';

    final parse = await computeTool(parseToolName, {
      'language': 'dart',
      'source': dart,
    }, limits);
    report(parse['isError'] != true, 'apollo.parse');

    final exec = await computeTool(executeToolName, {
      'language': 'dart',
      'source': dart,
    }, limits);
    report(exec['isError'] != true, 'apollo.execute');

    final translate = await computeTool(translateToolName, {
      'from': 'dart',
      'to': 'python',
      'source': dart,
    }, limits);
    report(translate['isError'] != true, 'apollo.translate');

    final wasm = await computeTool(wasmToolName, {
      'language': 'dart',
      'source': 'int run(int a, int b){ return a + b; }',
    }, limits);
    report(wasm['isError'] != true, 'apollo.wasm (compile)');

    // Optional: the native runtime needed to *run* compiled Wasm.
    try {
      final runtime = _wasmRuntimeSupported();
      report(
        runtime,
        runtime
            ? 'wasm_run native runtime available (apollo.wasm modules are runnable)'
            : 'wasm_run native runtime missing — apollo.wasm still COMPILES; '
                  'running compiled modules needs `dart run wasm_run:setup`',
        warnOnly: !runtime,
      );
    } catch (_) {
      report(
        false,
        'wasm_run native runtime missing — run `dart run wasm_run:setup` to run modules',
        warnOnly: true,
      );
    }

    print(ok ? '\nAll checks passed.' : '\nSome checks failed.');
    return ok;
  }
}

bool _wasmRuntimeSupported() {
  final runtime = WasmRuntime()..ensureBooted();
  return runtime.isSupported;
}

/// Accepts a bare tool name (`execute`) or a fully-qualified one
/// (`apollo.execute`) and returns the canonical `apollo.*` name.
String _normalizeToolName(String name) {
  final n = name.trim();
  return n.startsWith('apollo.') ? n : 'apollo.$n';
}
