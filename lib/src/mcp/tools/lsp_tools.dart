// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:dart_mcp/server.dart';

import '../mcp_config.dart';
import '../runtime/lsp_runtime.dart';

/// Canonical LSP tool names (`apollovm.lsp.*`).
const lspDiagnosticsToolName = 'apollovm.lsp.diagnostics';
const lspSymbolsToolName = 'apollovm.lsp.symbols';
const lspHoverToolName = 'apollovm.lsp.hover';
const lspDefinitionToolName = 'apollovm.lsp.definition';
const lspReferencesToolName = 'apollovm.lsp.references';
const lspCompletionToolName = 'apollovm.lsp.completion';
const lspWorkspaceSymbolsToolName = 'apollovm.lsp.workspaceSymbols';

/// The LSP inspection tools this server exposes, in registration order.
const lspToolNames = <String>[
  lspDiagnosticsToolName,
  lspSymbolsToolName,
  lspHoverToolName,
  lspDefinitionToolName,
  lspReferencesToolName,
  lspCompletionToolName,
  lspWorkspaceSymbolsToolName,
];

final _languageValues = LspRuntime.supportedLanguages.join(', ');

Schema get _languageSchema =>
    Schema.string(description: 'Source language ($_languageValues).');

Schema get _sourceSchema =>
    Schema.string(description: 'The source code to inspect.');

Schema get _uriSchema => Schema.string(
  description:
      'Optional document URI (its extension is honored only when it matches '
      'the language; otherwise one is synthesized).',
);

Schema get _lineSchema =>
    Schema.int(description: 'Zero-based line of the cursor position.');

Schema get _characterSchema => Schema.int(
  description: 'Zero-based character (UTF-16) offset within the line.',
);

ObjectSchema _positionalSchema({Map<String, Schema> extra = const {}}) =>
    ObjectSchema(
      properties: {
        'language': _languageSchema,
        'source': _sourceSchema,
        'line': _lineSchema,
        'character': _characterSchema,
        'uri': _uriSchema,
        ...extra,
      },
      required: ['language', 'source', 'line', 'character'],
    );

ObjectSchema _wholeFileSchema() => ObjectSchema(
  properties: {
    'language': _languageSchema,
    'source': _sourceSchema,
    'uri': _uriSchema,
  },
  required: ['language', 'source'],
);

/// The [Tool] definitions for the LSP inspection tools. These are the single
/// source of truth advertised via `tools/list`.
List<Tool> buildLspTools() => [
  Tool(
    name: lspDiagnosticsToolName,
    description:
        'Analyze source code and return its diagnostics (errors/warnings) with '
        'precise LSP line/character ranges.',
    inputSchema: _wholeFileSchema(),
  ),
  Tool(
    name: lspSymbolsToolName,
    description:
        'Return the document outline: a hierarchy of symbols (classes, methods, '
        'fields, enums, functions, variables) with their source ranges.',
    inputSchema: _wholeFileSchema(),
  ),
  Tool(
    name: lspHoverToolName,
    description:
        'Return hover information (signature, type and documentation) for the '
        'symbol at a line/character position.',
    inputSchema: _positionalSchema(),
  ),
  Tool(
    name: lspDefinitionToolName,
    description:
        'Return the declaration location (URI + range) of the symbol at a '
        'line/character position.',
    inputSchema: _positionalSchema(),
  ),
  Tool(
    name: lspReferencesToolName,
    description:
        'Return every reference to the symbol at a line/character position.',
    inputSchema: _positionalSchema(
      extra: {
        'includeDeclaration': Schema.bool(
          description: 'Include the declaration itself (default true).',
        ),
      },
    ),
  ),
  Tool(
    name: lspCompletionToolName,
    description:
        'Return completion proposals (symbols and keywords) at a line/character '
        'position.',
    inputSchema: _positionalSchema(),
  ),
  Tool(
    name: lspWorkspaceSymbolsToolName,
    description:
        'Search declarations matching a query across a set of in-memory files '
        '— codebase-wide symbol lookup.',
    inputSchema: ObjectSchema(
      properties: {
        'query': Schema.string(
          description:
              'Case-insensitive substring to match (empty matches '
              'all).',
        ),
        'files': Schema.list(
          description: 'The files that make up the workspace.',
          items: ObjectSchema(
            properties: {
              'uri': Schema.string(description: 'File URI/path.'),
              'source': _sourceSchema,
              'language': Schema.string(
                description:
                    'Optional language override ($_languageValues); inferred '
                    'from the URI extension when omitted.',
              ),
            },
            required: ['uri', 'source'],
          ),
        ),
      },
      required: ['query', 'files'],
    ),
  ),
];

String _str(Map<String, Object?> args, String key, [String fallback = '']) =>
    (args[key] as String?) ?? fallback;

int _int(Map<String, Object?> args, String key, [int fallback = 0]) {
  final v = args[key];
  return v is num ? v.toInt() : fallback;
}

/// Whether [name] is one of the LSP tools handled by [computeLspTool].
bool isLspTool(String name) => lspToolNames.contains(name);

/// Runs the LSP tool named [name] with [args] and returns its JSON result map
/// (always including an `isError` flag). Pure with respect to the host, so it
/// runs identically in-process or inside a spawned isolate.
Future<Map<String, Object?>> computeLspTool(
  String name,
  Map<String, Object?> args,
  McpLimits limits,
) async {
  final rt = LspRuntime(limits: limits);

  switch (name) {
    case lspDiagnosticsToolName:
      return rt.diagnostics(
        _str(args, 'language'),
        _str(args, 'source'),
        uri: args['uri'] as String?,
      );

    case lspSymbolsToolName:
      return rt.documentSymbols(
        _str(args, 'language'),
        _str(args, 'source'),
        uri: args['uri'] as String?,
      );

    case lspHoverToolName:
      return rt.hover(
        _str(args, 'language'),
        _str(args, 'source'),
        _int(args, 'line'),
        _int(args, 'character'),
        uri: args['uri'] as String?,
      );

    case lspDefinitionToolName:
      return rt.definition(
        _str(args, 'language'),
        _str(args, 'source'),
        _int(args, 'line'),
        _int(args, 'character'),
        uri: args['uri'] as String?,
      );

    case lspReferencesToolName:
      return rt.references(
        _str(args, 'language'),
        _str(args, 'source'),
        _int(args, 'line'),
        _int(args, 'character'),
        includeDeclaration: (args['includeDeclaration'] as bool?) ?? true,
        uri: args['uri'] as String?,
      );

    case lspCompletionToolName:
      return rt.completion(
        _str(args, 'language'),
        _str(args, 'source'),
        _int(args, 'line'),
        _int(args, 'character'),
        uri: args['uri'] as String?,
      );

    case lspWorkspaceSymbolsToolName:
      return rt.workspaceSymbols(
        _str(args, 'query'),
        (args['files'] as List?)?.cast<Object?>() ?? const [],
      );

    default:
      return <String, Object?>{
        'diagnostics': [
          <String, Object?>{
            'severity': 'error',
            'message': 'Unknown LSP tool: $name',
          },
        ],
        'isError': true,
      };
  }
}
