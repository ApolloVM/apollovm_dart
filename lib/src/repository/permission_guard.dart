// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'repo_config.dart';
import 'repository_adapter.dart';

/// A [RepositoryAdapter] decorator that enforces a [RepoConfig] over any inner
/// adapter, so the security policy holds regardless of the backend.
///
/// It gates mutating operations behind [RepoConfig.allowWrite] /
/// [RepoConfig.allowGitMutation], enforces [RepoConfig.requireLineMatch] for
/// anchored edits, and clamps [capabilities] to what the config permits. Reads
/// pass straight through; the size/result caps in [RepoConfig] are applied by
/// the concrete adapter (which knows how to bound its own I/O).
class PermissionGuard implements RepositoryAdapter {
  final RepositoryAdapter inner;
  final RepoConfig config;

  PermissionGuard(this.inner, {this.config = const RepoConfig()});

  @override
  RepoCapabilities get capabilities {
    final c = inner.capabilities;
    return RepoCapabilities(
      canWrite: c.canWrite && config.allowWrite,
      canGitMutate: c.canGitMutate && config.allowGitMutation,
      supportsGit: c.supportsGit,
      isRemote: c.isRemote,
    );
  }

  void _requireWrite() {
    if (!config.allowWrite) {
      throw const RepoPermissionException(
        'Filesystem writes are disabled (start the server with --allow-write).',
      );
    }
  }

  void _requireGitMutation() {
    if (!config.allowGitMutation) {
      throw const RepoPermissionException(
        'Git mutations are disabled (start the server with --allow-git-write).',
      );
    }
  }

  // --- Filesystem (read) — pass through ---

  @override
  Future<RepoFile> read(String path, {LineRange? range}) =>
      inner.read(path, range: range);

  @override
  Future<List<RepoEntry>> list(
    String path, {
    bool recursive = false,
    int? maxDepth,
    String? glob,
  }) => inner.list(path, recursive: recursive, maxDepth: maxDepth, glob: glob);

  @override
  Future<List<String>> find({String? glob, int? limit}) =>
      inner.find(glob: glob, limit: limit);

  @override
  Future<RepoStat> stat(String path) => inner.stat(path);

  // --- Filesystem (write) — gated ---

  @override
  Future<RepoEdit> write(String path, String content) {
    _requireWrite();
    return inner.write(path, content);
  }

  @override
  Future<RepoEdit> edit(
    String path,
    String oldString,
    String newString, {
    bool replaceAll = false,
    int? atLine,
  }) {
    _requireWrite();
    if (config.requireLineMatch && atLine == null) {
      throw const RepoPermissionException(
        'This server requires every edit to pin its line via `atLine`.',
      );
    }
    return inner.edit(
      path,
      oldString,
      newString,
      replaceAll: replaceAll,
      atLine: atLine,
    );
  }

  @override
  Future<void> mkdir(String path) {
    _requireWrite();
    return inner.mkdir(path);
  }

  @override
  Future<void> move(String from, String to) {
    _requireWrite();
    return inner.move(from, to);
  }

  @override
  Future<void> delete(String path) {
    _requireWrite();
    return inner.delete(path);
  }

  // --- Search — pass through ---

  @override
  Future<List<TextMatch>> searchText(
    String pattern, {
    String? glob,
    bool ignoreCase = false,
    int context = 0,
    int? limit,
  }) => inner.searchText(
    pattern,
    glob: glob,
    ignoreCase: ignoreCase,
    context: context,
    limit: limit,
  );

  // --- Git (read) — pass through ---

  @override
  Future<List<GitStatusEntry>> gitStatus() => inner.gitStatus();

  @override
  Future<String> gitDiff({String? rev, bool staged = false, String? path}) =>
      inner.gitDiff(rev: rev, staged: staged, path: path);

  @override
  Future<List<GitCommit>> gitLog({int? limit, String? path}) =>
      inner.gitLog(limit: limit, path: path);

  @override
  Future<String> gitShow({required String rev, String? path}) =>
      inner.gitShow(rev: rev, path: path);

  @override
  Future<List<GitBlameLine>> gitBlame(String path) => inner.gitBlame(path);

  // --- Git (write) — gated ---

  @override
  Future<GitResult> gitAdd(List<String> paths) {
    _requireGitMutation();
    return inner.gitAdd(paths);
  }

  @override
  Future<GitResult> gitCommit(String message, {List<String>? paths}) {
    _requireGitMutation();
    return inner.gitCommit(message, paths: paths);
  }

  @override
  Future<GitResult> gitCheckout(String rev) {
    _requireGitMutation();
    return inner.gitCheckout(rev);
  }

  @override
  Future<GitResult> gitRestore(List<String> paths, {bool staged = false}) {
    _requireGitMutation();
    return inner.gitRestore(paths, staged: staged);
  }
}
