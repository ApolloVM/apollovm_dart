// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:dart_mcp/server.dart';

/// Canonical git tool names (`apollovm.git.*`).
const gitStatusToolName = 'apollovm.git.status';
const gitDiffToolName = 'apollovm.git.diff';
const gitLogToolName = 'apollovm.git.log';
const gitShowToolName = 'apollovm.git.show';
const gitBlameToolName = 'apollovm.git.blame';
const gitAddToolName = 'apollovm.git.add';
const gitCommitToolName = 'apollovm.git.commit';
const gitCheckoutToolName = 'apollovm.git.checkout';
const gitRestoreToolName = 'apollovm.git.restore';

/// The git tools this server exposes, in registration order.
const gitToolNames = <String>[
  gitStatusToolName,
  gitDiffToolName,
  gitLogToolName,
  gitShowToolName,
  gitBlameToolName,
  gitAddToolName,
  gitCommitToolName,
  gitCheckoutToolName,
  gitRestoreToolName,
];

Schema get _pathSchema =>
    Schema.string(description: 'Path relative to the workspace root.');

/// The [Tool] definitions for the `apollovm.git.*` tools. The mutating tools
/// (add/commit/checkout/restore) are gated behind git-mutation permission.
List<Tool> buildGitTools() => [
  Tool(
    name: gitStatusToolName,
    description:
        'Working-tree status as structured entries. Replaces git status.',
    inputSchema: ObjectSchema(properties: {}),
  ),
  Tool(
    name: gitDiffToolName,
    description:
        'Diff of the working tree, the index (`staged`), or a revision, with an '
        'optional path filter. Replaces git diff.',
    inputSchema: ObjectSchema(
      properties: {
        'rev': Schema.string(description: 'Revision or range (e.g. HEAD~1).'),
        'staged': Schema.bool(
          description: 'Diff the index instead (default false).',
        ),
        'path': _pathSchema,
      },
    ),
  ),
  Tool(
    name: gitLogToolName,
    description:
        'Commit history: hash, author, ISO date and subject. Optional `limit` '
        'and `path`. Replaces git log.',
    inputSchema: ObjectSchema(
      properties: {
        'limit': Schema.int(description: 'Maximum number of commits.'),
        'path': _pathSchema,
      },
    ),
  ),
  Tool(
    name: gitShowToolName,
    description:
        'Show a commit, or a file\'s content at a revision (`rev` + `path`). '
        'Replaces git show.',
    inputSchema: ObjectSchema(
      properties: {
        'rev': Schema.string(
          description: 'Revision to show (e.g. HEAD, a hash).',
        ),
        'path': _pathSchema,
      },
      required: ['rev'],
    ),
  ),
  Tool(
    name: gitBlameToolName,
    description: 'Per-line authorship for a file. Replaces git blame.',
    inputSchema: ObjectSchema(
      properties: {'path': _pathSchema},
      required: ['path'],
    ),
  ),
  Tool(
    name: gitAddToolName,
    description: 'Stage paths (gated). Replaces git add.',
    inputSchema: ObjectSchema(
      properties: {
        'paths': Schema.list(
          description: 'Paths to stage.',
          items: Schema.string(),
        ),
      },
      required: ['paths'],
    ),
  ),
  Tool(
    name: gitCommitToolName,
    description:
        'Commit staged changes (or given paths) (gated). Replaces git commit.',
    inputSchema: ObjectSchema(
      properties: {
        'message': Schema.string(description: 'Commit message.'),
        'paths': Schema.list(
          description: 'Optional paths to commit.',
          items: Schema.string(),
        ),
      },
      required: ['message'],
    ),
  ),
  Tool(
    name: gitCheckoutToolName,
    description: 'Check out a revision/branch (gated). Replaces git checkout.',
    inputSchema: ObjectSchema(
      properties: {
        'rev': Schema.string(description: 'Revision/branch to check out.'),
      },
      required: ['rev'],
    ),
  ),
  Tool(
    name: gitRestoreToolName,
    description:
        'Restore paths in the working tree or index (`staged`) (gated). Replaces '
        'git restore.',
    inputSchema: ObjectSchema(
      properties: {
        'paths': Schema.list(
          description: 'Paths to restore.',
          items: Schema.string(),
        ),
        'staged': Schema.bool(description: 'Restore the index instead.'),
      },
      required: ['paths'],
    ),
  ),
];
