// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'repo_paths.dart';
import 'repository_adapter.dart';

/// A web-safe, in-memory [RepositoryAdapter] backing tests and browser demos.
///
/// Files live in a `path -> content` map (POSIX-relative paths). It supports the
/// full filesystem + search surface; git is not supported (its methods throw a
/// [RepoException]), matching a workspace with no VCS.
class InMemoryRepositoryAdapter implements RepositoryAdapter {
  final Map<String, String> _files;

  InMemoryRepositoryAdapter([Map<String, String>? files])
    : _files = {
        for (final e in (files ?? const {}).entries)
          normalizeRepoPath(e.key): e.value,
      };

  @override
  RepoCapabilities get capabilities =>
      const RepoCapabilities(canWrite: true, canGitMutate: false);

  String _requireFile(String path) {
    final p = normalizeRepoPath(path);
    final content = _files[p];
    if (content == null) throw RepoException('File not found: $path');
    return content;
  }

  // --- Filesystem (read) ---

  @override
  Future<RepoFile> read(String path, {LineRange? range}) async {
    final content = _requireFile(path);
    final slice = sliceLines(content, range);
    return RepoFile(
      path: normalizeRepoPath(path),
      content: slice.text,
      totalLines: slice.totalLines,
      startLine: range?.start,
      endLine: range == null ? null : (range.end ?? slice.totalLines),
    );
  }

  @override
  Future<List<RepoEntry>> list(
    String path, {
    bool recursive = false,
    int? maxDepth,
    String? glob,
  }) async {
    final prefix = normalizeRepoPath(path);
    final base = prefix.isEmpty ? '' : '$prefix/';
    final dirs = <String>{};
    final entries = <RepoEntry>[];
    for (final filePath in _files.keys) {
      if (base.isNotEmpty && !filePath.startsWith(base)) continue;
      final rest = filePath.substring(base.length);
      if (rest.isEmpty) continue;
      final segs = rest.split('/');
      final depth = segs.length; // 1 == direct child
      if (!recursive && depth > 1) {
        // Only surface the immediate directory.
        final dir = '$base${segs.first}';
        if (dirs.add(dir)) {
          entries.add(RepoEntry(path: dir, name: segs.first, isDir: true));
        }
        continue;
      }
      if (maxDepth != null && depth > maxDepth) continue;
      if (!matchesGlob(filePath, glob)) continue;
      entries.add(
        RepoEntry(
          path: filePath,
          name: segs.last,
          isDir: false,
          size: _files[filePath]!.length,
        ),
      );
    }
    entries.sort((a, b) => a.path.compareTo(b.path));
    return entries;
  }

  @override
  Future<List<String>> find({String? glob, int? limit}) async {
    final matches = _files.keys.where((p) => matchesGlob(p, glob)).toList()
      ..sort();
    return limit != null && matches.length > limit
        ? matches.sublist(0, limit)
        : matches;
  }

  @override
  Future<RepoStat> stat(String path) async {
    final p = normalizeRepoPath(path);
    final content = _files[p];
    if (content != null) {
      return RepoStat(
        path: p,
        exists: true,
        isDir: false,
        size: content.length,
        lineCount: splitLines(content).length,
      );
    }
    // A directory exists if any file is under it.
    final isDir = _files.keys.any((f) => f.startsWith('$p/'));
    return RepoStat(
      path: p,
      exists: isDir,
      isDir: isDir,
      size: 0,
      lineCount: 0,
    );
  }

  // --- Filesystem (write) ---

  @override
  Future<RepoEdit> write(String path, String content) async {
    final p = normalizeRepoPath(path);
    _files[p] = content;
    return RepoEdit(path: p, replacements: 1);
  }

  @override
  Future<RepoEdit> edit(
    String path,
    String oldString,
    String newString, {
    bool replaceAll = false,
    int? atLine,
  }) async {
    final p = normalizeRepoPath(path);
    final content = _requireFile(p);
    final result = applyEdit(
      content,
      oldString,
      newString,
      replaceAll: replaceAll,
      atLine: atLine,
    );
    _files[p] = result.content;
    return RepoEdit(
      path: p,
      replacements: result.replacements,
      appliedAtLine: result.appliedAtLine,
    );
  }

  @override
  Future<void> mkdir(String path) async {
    // Directories are implicit in this store; nothing to do.
    normalizeRepoPath(path);
  }

  @override
  Future<void> move(String from, String to) async {
    final src = normalizeRepoPath(from);
    final dst = normalizeRepoPath(to);
    final content = _files.remove(src);
    if (content != null) {
      _files[dst] = content;
      return;
    }
    // Move a "directory": re-key everything under `src/` to `dst/`.
    final under = _files.keys.where((f) => f.startsWith('$src/')).toList();
    if (under.isEmpty) throw RepoException('Path not found: $from');
    for (final f in under) {
      _files['$dst${f.substring(src.length)}'] = _files.remove(f)!;
    }
  }

  @override
  Future<void> delete(String path) async {
    final p = normalizeRepoPath(path);
    final removed = _files.remove(p) != null;
    if (!removed) {
      // Delete a "directory": drop everything under it.
      final under = _files.keys.where((f) => f.startsWith('$p/')).toList();
      if (under.isEmpty) throw RepoException('Path not found: $path');
      for (final f in under) {
        _files.remove(f);
      }
    }
  }

  // --- Search ---

  @override
  Future<List<TextMatch>> searchText(
    String pattern, {
    String? glob,
    bool ignoreCase = false,
    int context = 0,
    int? limit,
  }) async {
    final re = RegExp(pattern, caseSensitive: !ignoreCase);
    final results = <TextMatch>[];
    final paths = _files.keys.where((p) => matchesGlob(p, glob)).toList()
      ..sort();
    for (final path in paths) {
      final lines = _files[path]!.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final m = re.firstMatch(lines[i]);
        if (m == null) continue;
        results.add(
          TextMatch(
            path: path,
            line: i + 1,
            column: m.start + 1,
            text: lines[i],
            before: context > 0
                ? lines.sublist((i - context).clamp(0, i), i)
                : const [],
            after: context > 0
                ? lines.sublist(
                    (i + 1).clamp(0, lines.length),
                    (i + 1 + context).clamp(0, lines.length),
                  )
                : const [],
          ),
        );
        if (limit != null && results.length >= limit) return results;
      }
    }
    return results;
  }

  // --- Git — unsupported by the in-memory backend ---

  Never _noGit() => throw const RepoException(
    'Git is not available for an in-memory repository.',
  );

  @override
  Future<List<GitStatusEntry>> gitStatus() async => _noGit();
  @override
  Future<String> gitDiff({
    String? rev,
    bool staged = false,
    String? path,
  }) async => _noGit();
  @override
  Future<List<GitCommit>> gitLog({int? limit, String? path}) async => _noGit();
  @override
  Future<String> gitShow({required String rev, String? path}) async => _noGit();
  @override
  Future<List<GitBlameLine>> gitBlame(String path) async => _noGit();
  @override
  Future<GitResult> gitAdd(List<String> paths) async => _noGit();
  @override
  Future<GitResult> gitCommit(String message, {List<String>? paths}) async =>
      _noGit();
  @override
  Future<GitResult> gitCheckout(String rev) async => _noGit();
  @override
  Future<GitResult> gitRestore(
    List<String> paths, {
    bool staged = false,
  }) async => _noGit();
}
