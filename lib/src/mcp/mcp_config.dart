// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

/// Resource limits enforced by the ApolloVM MCP server.
///
/// These are the security knobs of the MCP runtime. Timeout is enforced per
/// execution; the source/output caps bound the amount of data a single request
/// can push through the server. Memory is NOT hard-capped by these values
/// (Dart has no per-isolate heap cap) — see the `doc/MCP.md` security notes.
class McpLimits {
  /// Maximum wall-clock time for a single `apollovm.execute` run, in milliseconds.
  ///
  /// Enforced via `Future.timeout`. ApolloVM's executor yields regularly
  /// (`FutureOr`/`resolveMapped`) so the timeout fires promptly; a purely
  /// synchronous non-yielding loop can delay it until the next suspension.
  final int timeoutMs;

  /// Maximum number of characters of captured console (`print`) output kept for
  /// a single execution. Output past this cap is dropped and the result is
  /// flagged `truncated: true`.
  final int maxOutputChars;

  /// Maximum size (in characters) of an accepted `source` input. Larger inputs
  /// are rejected before parsing/execution.
  final int maxSourceChars;

  /// Maximum depth of the serialized AST tree (`apollovm.ast`). Guards against
  /// pathological/deep trees producing huge payloads.
  final int maxAstDepth;

  /// Names of tools that run inside a spawned [Isolate] instead of in-process.
  ///
  /// Isolate execution is the ONLY way to enforce a real wall-clock timeout in
  /// Dart: ApolloVM runs CPU work synchronously (no async yield), so an
  /// in-process `Future.timeout` cannot interrupt a runaway loop, but an
  /// isolate can be `kill()`-ed. `apollovm.execute` (which runs arbitrary user
  /// code) defaults to isolate execution; the pure/bounded tools default to
  /// in-process. Configurable per tool.
  final Set<String> isolateTools;

  const McpLimits({
    this.timeoutMs = 5000,
    this.maxOutputChars = 65536,
    this.maxSourceChars = 262144,
    this.maxAstDepth = 200,
    this.isolateTools = const {'apollovm.execute'},
  });

  /// Whether [toolName] should run inside an isolate.
  bool runsInIsolate(String toolName) => isolateTools.contains(toolName);

  /// Returns a copy of these limits with the given overrides.
  McpLimits copyWith({
    int? timeoutMs,
    int? maxOutputChars,
    int? maxSourceChars,
    int? maxAstDepth,
    Set<String>? isolateTools,
  }) => McpLimits(
    timeoutMs: timeoutMs ?? this.timeoutMs,
    maxOutputChars: maxOutputChars ?? this.maxOutputChars,
    maxSourceChars: maxSourceChars ?? this.maxSourceChars,
    maxAstDepth: maxAstDepth ?? this.maxAstDepth,
    isolateTools: isolateTools ?? this.isolateTools,
  );

  @override
  String toString() =>
      'McpLimits{timeoutMs: $timeoutMs, maxOutputChars: $maxOutputChars, '
      'maxSourceChars: $maxSourceChars, maxAstDepth: $maxAstDepth, '
      'isolateTools: $isolateTools}';
}

/// Policy for the workspace/repository tools (`apollovm.fs.*`,
/// `apollovm.search.*`, `apollovm.code.*`, `apollovm.git.*`).
///
/// These are the security knobs of the repository surface. They are enforced by
/// the `PermissionGuard` adapter decorator, so they apply uniformly regardless
/// of which [RepositoryAdapter] backs the tools. Everything defaults to the
/// safest posture: **read-only**, with a bounded file size.
class RepoConfig {
  /// Whether mutating filesystem tools (`fs.write`/`edit`/`mkdir`/`move`/
  /// `delete`) are allowed. Off by default.
  final bool allowWrite;

  /// Whether mutating git tools (`git.add`/`commit`/`checkout`/`restore`) are
  /// allowed. Off by default.
  final bool allowGitMutation;

  /// When true, every `fs.edit` must pin its expected line via `atLine`; an
  /// edit without it is rejected. Guards against wrong-occurrence/stale edits.
  final bool requireLineMatch;

  /// Maximum size (in bytes) of a file the tools will read or write.
  final int maxFileBytes;

  /// Maximum number of results a single `fs.find`/`fs.list`/`search.*` returns.
  final int maxResults;

  /// Whether directory listing / find / search skip `.git` and (best-effort)
  /// `.gitignore`d paths.
  final bool respectGitignore;

  const RepoConfig({
    this.allowWrite = false,
    this.allowGitMutation = false,
    this.requireLineMatch = false,
    this.maxFileBytes = 5 * 1024 * 1024,
    this.maxResults = 1000,
    this.respectGitignore = true,
  });

  RepoConfig copyWith({
    bool? allowWrite,
    bool? allowGitMutation,
    bool? requireLineMatch,
    int? maxFileBytes,
    int? maxResults,
    bool? respectGitignore,
  }) => RepoConfig(
    allowWrite: allowWrite ?? this.allowWrite,
    allowGitMutation: allowGitMutation ?? this.allowGitMutation,
    requireLineMatch: requireLineMatch ?? this.requireLineMatch,
    maxFileBytes: maxFileBytes ?? this.maxFileBytes,
    maxResults: maxResults ?? this.maxResults,
    respectGitignore: respectGitignore ?? this.respectGitignore,
  );

  @override
  String toString() =>
      'RepoConfig{allowWrite: $allowWrite, allowGitMutation: $allowGitMutation, '
      'requireLineMatch: $requireLineMatch, maxFileBytes: $maxFileBytes, '
      'maxResults: $maxResults, respectGitignore: $respectGitignore}';
}
