// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:convert';
import 'dart:io';

import 'repo_config.dart';
import 'repo_paths.dart';
import 'repository_adapter.dart';

/// A [RepositoryAdapter] backed by a local checkout on disk.
///
/// Filesystem operations use `dart:io`; git operations shell out to the `git`
/// binary via [Process.run] with `workingDirectory` pinned to [root] (arguments
/// are passed as a list, never a shell string, so nothing is interpolated into a
/// shell). Every path is resolved and confined to [root]; anything escaping it
/// raises a [RepoException].
///
/// This is the only `dart:io`-bound adapter, so it lives behind the io-layer
/// export (`apollovm_mcp_io.dart`).
class LocalRepositoryAdapter implements RepositoryAdapter {
  /// The absolute, resolved workspace root. All paths are confined here.
  final String root;

  final RepoConfig config;

  /// Whether the root is a git working tree (detected once at construction).
  final bool _isGitRepo;

  LocalRepositoryAdapter._(this.root, this.config, this._isGitRepo);

  /// Opens the workspace rooted at [path] (which must exist).
  factory LocalRepositoryAdapter(
    String path, {
    RepoConfig config = const RepoConfig(),
  }) {
    final dir = Directory(path);
    if (!dir.existsSync()) {
      throw RepoException('Workspace root does not exist: $path');
    }
    final root = dir.resolveSymbolicLinksSync();
    final isGit =
        Directory('$root/.git').existsSync() || File('$root/.git').existsSync();
    return LocalRepositoryAdapter._(root, config, isGit);
  }

  @override
  RepoCapabilities get capabilities => RepoCapabilities(
    canWrite: true,
    canGitMutate: _isGitRepo,
    supportsGit: _isGitRepo,
  );

  /// Resolves [rel] against [root], guaranteeing the result stays inside it.
  String _resolve(String rel) {
    final norm = normalizeRepoPath(rel); // rejects `..` and absolute paths
    final full = norm.isEmpty ? root : '$root/$norm';
    return full;
  }

  /// The workspace-relative POSIX path for an absolute [full] path under [root].
  String _relativeOf(String full) {
    var p = full.replaceAll('\\', '/');
    final r = root.replaceAll('\\', '/');
    if (p == r) return '';
    if (p.startsWith('$r/')) p = p.substring(r.length + 1);
    return p;
  }

  bool _ignored(String relPath) {
    if (!config.respectGitignore) return false;
    return relPath == '.git' ||
        relPath.startsWith('.git/') ||
        relPath.contains('/.git/');
  }

  // --- Filesystem (read) ---

  @override
  Future<RepoFile> read(String path, {LineRange? range}) async {
    final file = File(_resolve(path));
    if (!file.existsSync()) throw RepoException('File not found: $path');
    final len = file.lengthSync();
    if (len > config.maxFileBytes) {
      throw RepoException(
        'File exceeds maxFileBytes ($len > ${config.maxFileBytes}): $path',
      );
    }
    final content = file.readAsStringSync();
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
    final dir = Directory(_resolve(path));
    if (!dir.existsSync()) throw RepoException('Directory not found: $path');
    final entries = <RepoEntry>[];
    final baseDepth = _resolve(path).split('/').length;
    await for (final ent in dir.list(
      recursive: recursive,
      followLinks: false,
    )) {
      final rel = _relativeOf(ent.path);
      if (_ignored(rel)) continue;
      if (maxDepth != null) {
        final depth = ent.path.split('/').length - baseDepth + 1;
        if (depth > maxDepth) continue;
      }
      final isDir = ent is Directory;
      if (!isDir && !matchesGlob(rel, glob)) continue;
      entries.add(
        RepoEntry(
          path: rel,
          name: rel.split('/').last,
          isDir: isDir,
          size: ent is File ? ent.lengthSync() : null,
        ),
      );
      if (entries.length >= config.maxResults) break;
    }
    entries.sort((a, b) => a.path.compareTo(b.path));
    return entries;
  }

  @override
  Future<List<String>> find({String? glob, int? limit}) async {
    final cap = limit ?? config.maxResults;
    final results = <String>[];
    await for (final ent in Directory(
      root,
    ).list(recursive: true, followLinks: false)) {
      if (ent is! File) continue;
      final rel = _relativeOf(ent.path);
      if (_ignored(rel)) continue;
      if (!matchesGlob(rel, glob)) continue;
      results.add(rel);
      if (results.length >= cap) break;
    }
    results.sort();
    return results;
  }

  @override
  Future<RepoStat> stat(String path) async {
    final full = _resolve(path);
    final type = FileSystemEntity.typeSync(full, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return RepoStat(
        path: normalizeRepoPath(path),
        exists: false,
        isDir: false,
        size: 0,
        lineCount: 0,
      );
    }
    final isDir = type == FileSystemEntityType.directory;
    var size = 0;
    var lineCount = 0;
    String? modified;
    if (!isDir) {
      final file = File(full);
      size = file.lengthSync();
      modified = file.lastModifiedSync().toIso8601String();
      if (size <= config.maxFileBytes) {
        lineCount = splitLines(file.readAsStringSync()).length;
      }
    }
    return RepoStat(
      path: normalizeRepoPath(path),
      exists: true,
      isDir: isDir,
      size: size,
      lineCount: lineCount,
      modified: modified,
    );
  }

  // --- Filesystem (write) ---

  @override
  Future<RepoEdit> write(String path, String content) async {
    if (content.length > config.maxFileBytes) {
      throw RepoException('Content exceeds maxFileBytes: $path');
    }
    final file = File(_resolve(path));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return RepoEdit(path: normalizeRepoPath(path), replacements: 1);
  }

  @override
  Future<RepoEdit> edit(
    String path,
    String oldString,
    String newString, {
    bool replaceAll = false,
    int? atLine,
  }) async {
    final file = File(_resolve(path));
    if (!file.existsSync()) throw RepoException('File not found: $path');
    final content = file.readAsStringSync();
    final result = applyEdit(
      content,
      oldString,
      newString,
      replaceAll: replaceAll,
      atLine: atLine,
    );
    file.writeAsStringSync(result.content);
    return RepoEdit(
      path: normalizeRepoPath(path),
      replacements: result.replacements,
      appliedAtLine: result.appliedAtLine,
    );
  }

  @override
  Future<void> mkdir(String path) async {
    Directory(_resolve(path)).createSync(recursive: true);
  }

  @override
  Future<void> move(String from, String to) async {
    final src = _resolve(from);
    final dst = _resolve(to);
    final type = FileSystemEntity.typeSync(src, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw RepoException('Path not found: $from');
    }
    File(dst).parent.createSync(recursive: true);
    if (type == FileSystemEntityType.directory) {
      Directory(src).renameSync(dst);
    } else {
      File(src).renameSync(dst);
    }
  }

  @override
  Future<void> delete(String path) async {
    final full = _resolve(path);
    final type = FileSystemEntity.typeSync(full, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw RepoException('Path not found: $path');
    }
    if (type == FileSystemEntityType.directory) {
      Directory(full).deleteSync(recursive: true);
    } else {
      File(full).deleteSync();
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
    final cap = limit ?? config.maxResults;
    final results = <TextMatch>[];
    await for (final ent in Directory(
      root,
    ).list(recursive: true, followLinks: false)) {
      if (ent is! File) continue;
      final rel = _relativeOf(ent.path);
      if (_ignored(rel)) continue;
      if (!matchesGlob(rel, glob)) continue;
      if (ent.lengthSync() > config.maxFileBytes) continue;
      List<String> lines;
      try {
        lines = ent.readAsStringSync().split('\n');
      } on FileSystemException {
        continue; // binary/unreadable
      }
      for (var i = 0; i < lines.length; i++) {
        final m = re.firstMatch(lines[i]);
        if (m == null) continue;
        results.add(
          TextMatch(
            path: rel,
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
        if (results.length >= cap) return results;
      }
    }
    return results;
  }

  // --- Git ---

  void _requireGit() {
    if (!_isGitRepo) {
      throw const RepoException('The workspace root is not a git repository.');
    }
  }

  Future<ProcessResult> _git(List<String> args) async {
    _requireGit();
    final result = await Process.run(
      'git',
      args,
      workingDirectory: root,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      final err = (result.stderr as String).trim();
      throw RepoException('git ${args.join(' ')} failed: $err');
    }
    return result;
  }

  @override
  Future<List<GitStatusEntry>> gitStatus() async {
    final out = (await _git(['status', '--porcelain'])).stdout as String;
    final entries = <GitStatusEntry>[];
    for (final line in const LineSplitter().convert(out)) {
      if (line.length < 3) continue;
      final code = line.substring(0, 2);
      final path = line.substring(3);
      entries.add(
        GitStatusEntry(
          path: path,
          status: code,
          staged: code[0] != ' ' && code[0] != '?',
        ),
      );
    }
    return entries;
  }

  @override
  Future<String> gitDiff({
    String? rev,
    bool staged = false,
    String? path,
  }) async {
    final args = <String>['diff', if (staged) '--staged', ?rev];
    if (path != null) args.addAll(['--', normalizeRepoPath(path)]);
    return (await _git(args)).stdout as String;
  }

  @override
  Future<List<GitCommit>> gitLog({int? limit, String? path}) async {
    // Unit-separated fields, record-separated commits, to parse robustly.
    const fmt = '%H%x1f%an%x1f%aI%x1f%s';
    final args = <String>[
      'log',
      '--pretty=format:$fmt',
      if (limit != null) '-n$limit',
      if (path != null) ...['--', normalizeRepoPath(path)],
    ];
    final out = (await _git(args)).stdout as String;
    final commits = <GitCommit>[];
    for (final line in const LineSplitter().convert(out)) {
      if (line.isEmpty) continue;
      final f = line.split('\x1f');
      if (f.length < 4) continue;
      commits.add(
        GitCommit(hash: f[0], author: f[1], date: f[2], subject: f[3]),
      );
    }
    return commits;
  }

  @override
  Future<String> gitShow({required String rev, String? path}) async {
    final target = path != null ? '$rev:${normalizeRepoPath(path)}' : rev;
    return (await _git(['show', target])).stdout as String;
  }

  @override
  Future<List<GitBlameLine>> gitBlame(String path) async {
    final out =
        (await _git([
              'blame',
              '--line-porcelain',
              '--',
              normalizeRepoPath(path),
            ])).stdout
            as String;
    final lines = <GitBlameLine>[];
    final blocks = const LineSplitter().convert(out);
    String hash = '';
    String author = '';
    var lineNo = 0;
    for (final l in blocks) {
      if (RegExp(r'^[0-9a-f]{40} ').hasMatch(l)) {
        final parts = l.split(' ');
        hash = parts[0].substring(0, 8);
        lineNo = int.tryParse(parts[2]) ?? (lineNo + 1);
      } else if (l.startsWith('author ')) {
        author = l.substring('author '.length);
      } else if (l.startsWith('\t')) {
        lines.add(
          GitBlameLine(
            line: lineNo,
            hash: hash,
            author: author,
            content: l.substring(1),
          ),
        );
      }
    }
    return lines;
  }

  @override
  Future<GitResult> gitAdd(List<String> paths) async {
    final r = await _git(['add', '--', ...paths.map(normalizeRepoPath)]);
    return GitResult(ok: true, output: (r.stdout as String).trim());
  }

  @override
  Future<GitResult> gitCommit(String message, {List<String>? paths}) async {
    final r = await _git([
      'commit',
      '-m',
      message,
      if (paths != null) ...['--', ...paths.map(normalizeRepoPath)],
    ]);
    return GitResult(ok: true, output: (r.stdout as String).trim());
  }

  @override
  Future<GitResult> gitCheckout(String rev) async {
    final r = await _git(['checkout', rev]);
    return GitResult(ok: true, output: (r.stderr as String).trim());
  }

  @override
  Future<GitResult> gitRestore(
    List<String> paths, {
    bool staged = false,
  }) async {
    final r = await _git([
      'restore',
      if (staged) '--staged',
      '--',
      ...paths.map(normalizeRepoPath),
    ]);
    return GitResult(ok: true, output: (r.stdout as String).trim());
  }
}
