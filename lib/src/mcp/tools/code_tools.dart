// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:dart_mcp/server.dart';

/// Canonical code-navigation tool names (`apollovm.code.*`).
const codeOutlineToolName = 'apollovm.code.outline';
const codeDefinitionToolName = 'apollovm.code.definition';
const codeReferencesToolName = 'apollovm.code.references';
const codeHoverToolName = 'apollovm.code.hover';
const codeDiagnosticsToolName = 'apollovm.code.diagnostics';
const codeWorkspaceSymbolsToolName = 'apollovm.code.workspaceSymbols';

/// The code-navigation tools this server exposes, in registration order.
const codeToolNames = <String>[
  codeOutlineToolName,
  codeDefinitionToolName,
  codeReferencesToolName,
  codeHoverToolName,
  codeDiagnosticsToolName,
  codeWorkspaceSymbolsToolName,
];

Schema get _pathSchema => Schema.string(
  description: 'Source file path relative to the workspace root.',
);
Schema get _lineSchema =>
    Schema.int(description: 'Zero-based line of the cursor position.');
Schema get _charSchema => Schema.int(
  description: 'Zero-based (UTF-16) character offset in the line.',
);

ObjectSchema _positional() => ObjectSchema(
  properties: {
    'path': _pathSchema,
    'line': _lineSchema,
    'character': _charSchema,
  },
  required: ['path', 'line', 'character'],
);

/// The [Tool] definitions for the `apollovm.code.*` tools. These are the
/// language-aware, file-based counterparts of the inline `apollovm.lsp.*` tools:
/// they read the file from the workspace and infer the language from its
/// extension.
List<Tool> buildCodeTools() => [
  Tool(
    name: codeOutlineToolName,
    description:
        'Document outline of a file: hierarchy of classes/methods/fields/enums/'
        'functions/variables with source ranges (language inferred from the '
        'extension).',
    inputSchema: ObjectSchema(
      properties: {'path': _pathSchema},
      required: ['path'],
    ),
  ),
  Tool(
    name: codeDefinitionToolName,
    description:
        'Declaration location (uri + range) of the symbol at a line/character '
        'position in a file.',
    inputSchema: _positional(),
  ),
  Tool(
    name: codeReferencesToolName,
    description:
        'References to the symbol at a line/character position within the file.',
    inputSchema: ObjectSchema(
      properties: {
        'path': _pathSchema,
        'line': _lineSchema,
        'character': _charSchema,
        'includeDeclaration': Schema.bool(
          description: 'Include the declaration itself (default true).',
        ),
      },
      required: ['path', 'line', 'character'],
    ),
  ),
  Tool(
    name: codeHoverToolName,
    description:
        'Hover info (signature, type, documentation) for the symbol at a '
        'line/character position in a file.',
    inputSchema: _positional(),
  ),
  Tool(
    name: codeDiagnosticsToolName,
    description:
        'Parse diagnostics (errors/warnings with precise ranges) for a file.',
    inputSchema: ObjectSchema(
      properties: {'path': _pathSchema},
      required: ['path'],
    ),
  ),
  Tool(
    name: codeWorkspaceSymbolsToolName,
    description:
        'Workspace-wide symbol search that auto-loads the repo\'s source files '
        '(unlike apollovm.lsp.workspaceSymbols, which needs inline sources).',
    inputSchema: ObjectSchema(
      properties: {
        'query': Schema.string(
          description:
              'Case-insensitive substring to match (empty matches all).',
        ),
        'glob': Schema.string(
          description: 'Restrict to source files matching this glob.',
        ),
      },
      required: ['query'],
    ),
  ),
];
