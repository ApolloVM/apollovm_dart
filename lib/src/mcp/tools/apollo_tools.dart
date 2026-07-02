// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:math' as math;

import 'package:dart_mcp/server.dart';

import '../mcp_config.dart';
import '../runtime/apollo_runtime.dart';
import '../serialize/ast_json.dart';
import '../serialize/symbols.dart';
import '../serialize/types.dart';

/// Canonical tool names.
const parseToolName = 'apollovm.parse';
const executeToolName = 'apollovm.execute';
const translateToolName = 'apollovm.translate';
const astToolName = 'apollovm.ast';
const symbolsToolName = 'apollovm.symbols';
const typesToolName = 'apollovm.types';
const wasmToolName = 'apollovm.wasm';

/// The names of all tools this server exposes, in registration order.
const allToolNames = <String>[
  parseToolName,
  executeToolName,
  translateToolName,
  astToolName,
  symbolsToolName,
  typesToolName,
  wasmToolName,
];

/// The source languages the MCP tools accept (canonical names).
const mcpSupportedLanguages = <String>[
  'dart',
  'java',
  'kotlin',
  'go',
  'csharp',
  'javascript',
  'typescript',
  'lua',
  'python',
  'wasm',
];

final _languageValues = mcpSupportedLanguages.join(', ');

Schema get _languageSchema =>
    Schema.string(description: 'Source language ($_languageValues).');

Schema get _sourceSchema =>
    Schema.string(description: 'The source code to process.');

/// The [Tool] definitions (name, description, JSON input schema) for all seven
/// ApolloVM tools. These schemas are the single source of truth advertised via
/// `tools/list`.
List<Tool> buildTools() => [
  Tool(
    name: parseToolName,
    description:
        'Parse source code and return parse diagnostics plus a summary of the '
        'top-level classes, functions and imports.',
    inputSchema: ObjectSchema(
      properties: {'language': _languageSchema, 'source': _sourceSchema},
      required: ['language', 'source'],
    ),
  ),
  Tool(
    name: executeToolName,
    description:
        'Execute source code (running an entry function, default `main`) and '
        'return the result value, captured console output and diagnostics.',
    inputSchema: ObjectSchema(
      properties: {
        'language': _languageSchema,
        'source': _sourceSchema,
        'function': Schema.string(
          description: 'Entry function name (default `main`).',
        ),
        'className': Schema.string(
          description: 'Optional class owning the entry method.',
        ),
        'args': Schema.list(
          description: 'Positional arguments passed to the entry function.',
        ),
        'timeoutMs': Schema.int(
          description: 'Execution timeout override, in milliseconds.',
        ),
      },
      required: ['language', 'source'],
    ),
  ),
  Tool(
    name: translateToolName,
    description:
        'Translate/transpile source code from one language to another and '
        'return the generated source.',
    inputSchema: ObjectSchema(
      properties: {
        'from': Schema.string(
          description: 'Source language ($_languageValues).',
        ),
        'to': Schema.string(description: 'Target language ($_languageValues).'),
        'source': _sourceSchema,
      },
      required: ['from', 'to', 'source'],
    ),
  ),
  Tool(
    name: astToolName,
    description: 'Parse source code and return its full AST as JSON.',
    inputSchema: ObjectSchema(
      properties: {
        'language': _languageSchema,
        'source': _sourceSchema,
        'maxDepth': Schema.int(
          description: 'Maximum AST tree depth to serialize.',
        ),
      },
      required: ['language', 'source'],
    ),
  ),
  Tool(
    name: symbolsToolName,
    description:
        'Parse source code and return its symbol graph: top-level functions '
        'and classes with their fields, methods and constructors.',
    inputSchema: ObjectSchema(
      properties: {'language': _languageSchema, 'source': _sourceSchema},
      required: ['language', 'source'],
    ),
  ),
  Tool(
    name: typesToolName,
    description:
        'Parse source code and return the deduplicated table of types it '
        'references (classified as class/builtin/unknown).',
    inputSchema: ObjectSchema(
      properties: {'language': _languageSchema, 'source': _sourceSchema},
      required: ['language', 'source'],
    ),
  ),
  Tool(
    name: wasmToolName,
    description:
        'Compile source code to WebAssembly and return each produced module '
        'as base64-encoded bytes.',
    inputSchema: ObjectSchema(
      properties: {'language': _languageSchema, 'source': _sourceSchema},
      required: ['language', 'source'],
    ),
  ),
];

String _str(Map<String, Object?> args, String key, [String fallback = '']) =>
    (args[key] as String?) ?? fallback;

/// Runs the tool named [name] with [args] and returns its JSON result map.
///
/// The returned map always contains an `isError` flag. This function is pure
/// with respect to the host (no shared state), so it can run either in-process
/// or inside a spawned isolate (see `runtime/isolate_executor.dart`).
Future<Map<String, Object?>> computeTool(
  String name,
  Map<String, Object?> args,
  McpLimits limits,
) async {
  final rt = ApolloRuntime(limits: limits);

  switch (name) {
    case parseToolName:
      final o = await rt.parse(_str(args, 'language'), _str(args, 'source'));
      final root = o.root;
      return <String, Object?>{
        'ok': root != null,
        'diagnostics': o.diagnostics,
        if (root != null)
          'summary': <String, Object?>{
            'namespace': root.namespace,
            'classes': root.classesNames,
            'functions': root.functions.map((f) => f.name).toList(),
            'imports': root.imports.map((i) => i.path).toList(),
          },
        'isError': root == null,
      };

    case astToolName:
      final o = await rt.parse(_str(args, 'language'), _str(args, 'source'));
      if (o.root == null) {
        return <String, Object?>{'diagnostics': o.diagnostics, 'isError': true};
      }
      final requested = (args['maxDepth'] as int?) ?? limits.maxAstDepth;
      final depth = math.min(requested, limits.maxAstDepth);
      return <String, Object?>{
        'ast': astNodeToJson(o.root!, maxDepth: depth),
        'isError': false,
      };

    case symbolsToolName:
      final o = await rt.parse(_str(args, 'language'), _str(args, 'source'));
      if (o.root == null) {
        return <String, Object?>{'diagnostics': o.diagnostics, 'isError': true};
      }
      return <String, Object?>{
        'symbols': symbolsToJson(o.root!),
        'isError': false,
      };

    case typesToolName:
      final o = await rt.parse(_str(args, 'language'), _str(args, 'source'));
      if (o.root == null) {
        return <String, Object?>{'diagnostics': o.diagnostics, 'isError': true};
      }
      return <String, Object?>{...typesToJson(o.root!), 'isError': false};

    case executeToolName:
      final rawArgs = (args['args'] as List?)?.cast<Object?>() ?? const [];
      final o = await rt.execute(
        _str(args, 'language'),
        _str(args, 'source'),
        function: _str(args, 'function', 'main'),
        className: args['className'] as String?,
        args: rawArgs,
        timeoutMs: args['timeoutMs'] as int?,
      );
      return <String, Object?>{
        'result': o.result,
        'hasResult': o.hasResult,
        'output': o.output,
        'truncated': o.truncated,
        'diagnostics': o.diagnostics,
        'isError': o.diagnostics.isNotEmpty,
      };

    case translateToolName:
      final o = await rt.translate(
        _str(args, 'from'),
        _str(args, 'to'),
        _str(args, 'source'),
      );
      return <String, Object?>{
        'generated': o.generated,
        'diagnostics': o.diagnostics,
        'isError': o.generated == null,
      };

    case wasmToolName:
      final o = await rt.compileWasm(
        _str(args, 'language'),
        _str(args, 'source'),
      );
      return <String, Object?>{
        'modules': o.modules,
        'diagnostics': o.diagnostics,
        'isError': o.modules == null,
      };

    default:
      return <String, Object?>{
        'diagnostics': [
          <String, Object?>{
            'severity': 'error',
            'message': 'Unknown tool: $name',
          },
        ],
        'isError': true,
      };
  }
}
