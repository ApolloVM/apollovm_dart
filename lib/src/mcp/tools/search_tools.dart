// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:dart_mcp/server.dart';

/// Canonical search tool names (`apollovm.search.*`).
const searchTextToolName = 'apollovm.search.text';
const searchSymbolsToolName = 'apollovm.search.symbols';

/// The search tools this server exposes, in registration order.
const searchToolNames = <String>[searchTextToolName, searchSymbolsToolName];

/// The [Tool] definitions for the `apollovm.search.*` tools.
List<Tool> buildSearchTools() => [
  Tool(
    name: searchTextToolName,
    description:
        'Search file contents by regular expression across the workspace. '
        'Returns hits as {path, line, column, text, before/after context}. '
        'Replaces grep -rn / ripgrep.',
    inputSchema: ObjectSchema(
      properties: {
        'pattern': Schema.string(description: 'Regular expression to match.'),
        'glob': Schema.string(
          description: 'Restrict to files matching this glob.',
        ),
        'ignoreCase': Schema.bool(
          description: 'Case-insensitive (default false).',
        ),
        'context': Schema.int(
          description: 'Lines of surrounding context to include.',
        ),
        'limit': Schema.int(description: 'Maximum number of hits to return.'),
      },
      required: ['pattern'],
    ),
  ),
  Tool(
    name: searchSymbolsToolName,
    description:
        'Language-aware declaration search: find classes/functions/methods/'
        'fields/enums/variables by name using ApolloVM\'s parsers (no false '
        'positives from comments or strings). Optional `kind` filter. Beats grep '
        'for finding definitions.',
    inputSchema: ObjectSchema(
      properties: {
        'query': Schema.string(
          description: 'Case-insensitive substring of the symbol name.',
        ),
        'kind': Schema.string(
          description:
              'Optional symbol kind filter (e.g. class, method, function, '
              'field, enum, variable).',
        ),
        'glob': Schema.string(
          description: 'Restrict to source files matching this glob.',
        ),
      },
      required: ['query'],
    ),
  ),
];
