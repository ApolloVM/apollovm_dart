// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

/// Policy for the repository surface (the `RepositoryAdapter` operations and
/// the `apollovm.fs.*`/`search.*`/`code.*`/`git.*` MCP tools built on it).
///
/// These are the security knobs. They are enforced by the `PermissionGuard`
/// adapter decorator, so they apply uniformly regardless of which
/// `RepositoryAdapter` backs the operations. Everything defaults to the safest
/// posture: **read-only**, with a bounded file size.
class RepoConfig {
  /// Whether mutating filesystem operations (`write`/`edit`/`mkdir`/`move`/
  /// `delete`) are allowed. Off by default.
  final bool allowWrite;

  /// Whether mutating git operations (`add`/`commit`/`checkout`/`restore`) are
  /// allowed. Off by default.
  final bool allowGitMutation;

  /// When true, every `edit` must pin its expected line via `atLine`; an edit
  /// without it is rejected. Guards against wrong-occurrence/stale edits.
  final bool requireLineMatch;

  /// Maximum size (in bytes) of a file the operations will read or write.
  final int maxFileBytes;

  /// Maximum number of results a single `find`/`list`/`searchText` returns.
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
