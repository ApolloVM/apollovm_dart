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
import 'lsp_tools.dart';

/// Canonical tool names.
const parseToolName = 'apollovm.parse';
const executeToolName = 'apollovm.execute';
const translateToolName = 'apollovm.translate';
const astToolName = 'apollovm.ast';
const symbolsToolName = 'apollovm.symbols';
const typesToolName = 'apollovm.types';
const wasmToolName = 'apollovm.wasm';

/// The names of all tools this server exposes, in registration order: the core
/// VM tools followed by the `apollovm.lsp.*` code-inspection tools.
const allToolNames = <String>[
  parseToolName,
  executeToolName,
  translateToolName,
  astToolName,
  symbolsToolName,
  typesToolName,
  wasmToolName,
  ...lspToolNames,
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

/// Shared `nullSafety` input. On the tools that *load* code it rejects the
/// source outright; on the parse-based tools it adds the findings to
/// `diagnostics`. Defaults to the server's `--null-safety` setting.
Schema get _nullSafetySchema => Schema.bool(
  description:
      'Apply null-safety checks. On tools that load code (execute, translate, '
      'wasm) a null-safety error rejects the source; on the parse-based tools '
      'the findings are added to `diagnostics`. '
      'Defaults to the server `--null-safety` setting.',
);

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
      properties: {
        'language': _languageSchema,
        'source': _sourceSchema,
        'nullSafety': _nullSafetySchema,
      },
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
        'nullSafety': _nullSafetySchema,
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
        'nullSafety': _nullSafetySchema,
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
        'nullSafety': _nullSafetySchema,
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
      properties: {
        'language': _languageSchema,
        'source': _sourceSchema,
        'nullSafety': _nullSafetySchema,
      },
      required: ['language', 'source'],
    ),
  ),
  Tool(
    name: typesToolName,
    description:
        'Parse source code and return the deduplicated table of types it '
        'references (classified as class/builtin/unknown).',
    inputSchema: ObjectSchema(
      properties: {
        'language': _languageSchema,
        'source': _sourceSchema,
        'nullSafety': _nullSafetySchema,
      },
      required: ['language', 'source'],
    ),
  ),
  Tool(
    name: wasmToolName,
    description:
        'Compile source code to WebAssembly and return each produced module '
        'as base64-encoded bytes.',
    inputSchema: ObjectSchema(
      properties: {
        'language': _languageSchema,
        'source': _sourceSchema,
        'nullSafety': _nullSafetySchema,
      },
      required: ['language', 'source'],
    ),
  ),
  ...buildLspTools(),
];

// Client arguments arrive as decoded JSON, so their runtime types are whatever
// the client sent. These coercions never throw a raw `TypeError`: a wrong or
// missing value degrades to the fallback/`null` instead of crashing the tool.

String _str(Map<String, Object?> args, String key, [String fallback = '']) {
  final v = args[key];
  return v is String ? v : fallback;
}

/// Nullable string; a non-string (or missing) value is treated as absent.
String? _strOrNull(Map<String, Object?> args, String key) {
  final v = args[key];
  return v is String ? v : null;
}

/// Nullable int. JSON numbers may decode to `double` (e.g. `1000.0`) and some
/// clients send numbers as strings, so accept `num` and numeric `String`.
int? _intOrNull(Map<String, Object?> args, String key) =>
    mcpCoerceInt(args[key]);

/// Coerces an arbitrary decoded-JSON [value] to `int?` without throwing a
/// `TypeError`. JSON numbers may decode to `double` (e.g. `1000.0`) and some
/// clients send numbers as strings, so `num` and numeric `String` are accepted;
/// anything else (or `null`) yields `null`.
int? mcpCoerceInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

/// Nullable bool, coerced the same defensive way as [_intOrNull].
bool _boolOr(Map<String, Object?> args, String key, bool defaultValue) =>
    mcpCoerceBool(args[key]) ?? defaultValue;

/// Coerces an arbitrary decoded-JSON [value] to `bool?` without throwing a
/// `TypeError`. Some clients send booleans as strings (`"true"`) or as `0`/`1`,
/// so those are accepted; anything else (or `null`) yields `null`.
bool? mcpCoerceBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    switch (value.trim().toLowerCase()) {
      case 'true':
      case '1':
        return true;
      case 'false':
      case '0':
        return false;
    }
  }
  return null;
}

/// A list of arbitrary elements; a non-list (or missing) value yields `const []`.
List<Object?> _listOrEmpty(Map<String, Object?> args, String key) {
  final v = args[key];
  return v is List ? v.cast<Object?>() : const [];
}

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
  if (isLspTool(name)) return computeLspTool(name, args, limits);

  final rt = ApolloRuntime(limits: limits);

  // The server merges its `--null-safety` default into `args` before dispatch
  // (see `ApolloMcpServer._handle`), so a per-call value always wins here and
  // the same read works in-process and inside an isolate.
  final nullSafety = _boolOr(args, 'nullSafety', false);

  switch (name) {
    case parseToolName:
      final o = await rt.parse(
        _str(args, 'language'),
        _str(args, 'source'),
        nullSafety: nullSafety,
      );
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
      final o = await rt.parse(
        _str(args, 'language'),
        _str(args, 'source'),
        nullSafety: nullSafety,
      );
      if (o.root == null) {
        return <String, Object?>{'diagnostics': o.diagnostics, 'isError': true};
      }
      final requested = _intOrNull(args, 'maxDepth') ?? limits.maxAstDepth;
      final depth = math.min(requested, limits.maxAstDepth);
      return <String, Object?>{
        'ast': astNodeToJson(o.root!, maxDepth: depth),
        if (o.diagnostics.isNotEmpty) 'diagnostics': o.diagnostics,
        'isError': false,
      };

    case symbolsToolName:
      final o = await rt.parse(
        _str(args, 'language'),
        _str(args, 'source'),
        nullSafety: nullSafety,
      );
      if (o.root == null) {
        return <String, Object?>{'diagnostics': o.diagnostics, 'isError': true};
      }
      return <String, Object?>{
        'symbols': symbolsToJson(o.root!),
        if (o.diagnostics.isNotEmpty) 'diagnostics': o.diagnostics,
        'isError': false,
      };

    case typesToolName:
      final o = await rt.parse(
        _str(args, 'language'),
        _str(args, 'source'),
        nullSafety: nullSafety,
      );
      if (o.root == null) {
        return <String, Object?>{'diagnostics': o.diagnostics, 'isError': true};
      }
      return <String, Object?>{
        ...typesToJson(o.root!),
        if (o.diagnostics.isNotEmpty) 'diagnostics': o.diagnostics,
        'isError': false,
      };

    case executeToolName:
      final rawArgs = _listOrEmpty(args, 'args');
      final o = await rt.execute(
        _str(args, 'language'),
        _str(args, 'source'),
        function: _str(args, 'function', 'main'),
        className: _strOrNull(args, 'className'),
        args: rawArgs,
        timeoutMs: _intOrNull(args, 'timeoutMs'),
        nullSafety: nullSafety,
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
        nullSafety: nullSafety,
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
        nullSafety: nullSafety,
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
