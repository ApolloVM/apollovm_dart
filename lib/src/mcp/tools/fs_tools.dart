// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:dart_mcp/server.dart';

/// Canonical filesystem tool names (`apollovm.fs.*`).
const fsReadToolName = 'apollovm.fs.read';
const fsListToolName = 'apollovm.fs.list';
const fsFindToolName = 'apollovm.fs.find';
const fsStatToolName = 'apollovm.fs.stat';
const fsWriteToolName = 'apollovm.fs.write';
const fsEditToolName = 'apollovm.fs.edit';
const fsMkdirToolName = 'apollovm.fs.mkdir';
const fsMoveToolName = 'apollovm.fs.move';
const fsDeleteToolName = 'apollovm.fs.delete';

/// The filesystem tools this server exposes, in registration order.
const fsToolNames = <String>[
  fsReadToolName,
  fsListToolName,
  fsFindToolName,
  fsStatToolName,
  fsWriteToolName,
  fsEditToolName,
  fsMkdirToolName,
  fsMoveToolName,
  fsDeleteToolName,
];

Schema get _pathSchema => Schema.string(
  description: 'File/dir path relative to the workspace root (POSIX `/`).',
);

/// The [Tool] definitions for the `apollovm.fs.*` tools.
List<Tool> buildFsTools() => [
  Tool(
    name: fsReadToolName,
    description:
        'Read a file (optionally a 1-based inclusive line range) and return its '
        'text plus the file\'s total line count. Replaces cat/head/tail/sed -n.',
    inputSchema: ObjectSchema(
      properties: {
        'path': _pathSchema,
        'startLine': Schema.int(description: '1-based first line to read.'),
        'endLine': Schema.int(description: '1-based last line to read.'),
      },
      required: ['path'],
    ),
  ),
  Tool(
    name: fsListToolName,
    description:
        'List a directory. Optional `recursive`, `maxDepth` and `glob` filter. '
        'Replaces ls/tree.',
    inputSchema: ObjectSchema(
      properties: {
        'path': Schema.string(
          description: 'Directory (default: workspace root).',
        ),
        'recursive': Schema.bool(description: 'Descend into subdirectories.'),
        'maxDepth': Schema.int(description: 'Maximum recursion depth.'),
        'glob': Schema.string(description: 'Only include paths matching glob.'),
      },
    ),
  ),
  Tool(
    name: fsFindToolName,
    description:
        'Find files by name/glob pattern under the root. For content search use '
        'apollovm.search.text. Replaces find/fd.',
    inputSchema: ObjectSchema(
      properties: {
        'glob': Schema.string(
          description: 'Glob (e.g. `lib/**/*.dart`); empty matches all files.',
        ),
        'limit': Schema.int(description: 'Maximum number of paths to return.'),
      },
    ),
  ),
  Tool(
    name: fsStatToolName,
    description:
        'File/directory metadata: existence, type, size, line count and mtime. '
        'Replaces stat/wc -l.',
    inputSchema: ObjectSchema(
      properties: {'path': _pathSchema},
      required: ['path'],
    ),
  ),
  Tool(
    name: fsWriteToolName,
    description:
        'Create or overwrite a file with `content` (gated: requires write '
        'permission). Replaces `>` redirection.',
    inputSchema: ObjectSchema(
      properties: {
        'path': _pathSchema,
        'content': Schema.string(description: 'The full new file content.'),
      },
      required: ['path', 'content'],
    ),
  ),
  Tool(
    name: fsEditToolName,
    description:
        'Replace `oldString` with `newString` in a file (gated). Without '
        '`replaceAll`, exactly one occurrence must match. Pass `atLine` (1-based) '
        'as a safety anchor: the edit only applies if `oldString` occurs on that '
        'line, else it is rejected. Replaces sed/patch.',
    inputSchema: ObjectSchema(
      properties: {
        'path': _pathSchema,
        'oldString': Schema.string(description: 'Exact text to replace.'),
        'newString': Schema.string(description: 'Replacement text.'),
        'replaceAll': Schema.bool(
          description: 'Replace every occurrence (default false).',
        ),
        'atLine': Schema.int(
          description: 'Require the match to occur on this 1-based line.',
        ),
      },
      required: ['path', 'oldString', 'newString'],
    ),
  ),
  Tool(
    name: fsMkdirToolName,
    description: 'Create a directory (and parents) (gated). Replaces mkdir -p.',
    inputSchema: ObjectSchema(
      properties: {'path': _pathSchema},
      required: ['path'],
    ),
  ),
  Tool(
    name: fsMoveToolName,
    description: 'Move/rename a file or directory (gated). Replaces mv.',
    inputSchema: ObjectSchema(
      properties: {'from': _pathSchema, 'to': _pathSchema},
      required: ['from', 'to'],
    ),
  ),
  Tool(
    name: fsDeleteToolName,
    description: 'Delete a file or directory (gated). Replaces rm.',
    inputSchema: ObjectSchema(
      properties: {'path': _pathSchema},
      required: ['path'],
    ),
  ),
];
