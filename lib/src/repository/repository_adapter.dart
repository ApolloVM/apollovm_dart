// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

/// The workspace/repository abstraction behind the `apollovm.fs.*`,
/// `apollovm.search.*`, `apollovm.code.*` and `apollovm.git.*` MCP tools.
///
/// The tools and their [RepoRuntime] never touch `dart:io` or the `git` binary
/// directly — they talk only to a [RepositoryAdapter]. That decoupling lets the
/// exact same tool surface run against:
///   * a local checkout (`LocalRepositoryAdapter`, `dart:io` + `git`),
///   * an in-memory fixture (`InMemoryRepositoryAdapter`, web-safe), or
///   * a remote/web backend (a future `RemoteRepositoryAdapter`), enabling file
///     edits and git commands from the browser.
///
/// This library is **web-safe**: it declares the interface and its plain-data
/// value types only, with no `dart:io` import.
library;

/// What a concrete [RepositoryAdapter] (as configured) is able and permitted to
/// do. Tools consult this to fail cleanly ("not supported / not permitted")
/// instead of throwing when an operation is unavailable.
class RepoCapabilities {
  /// Whether mutating filesystem operations (`write`/`edit`/`mkdir`/`move`/
  /// `delete`) are permitted.
  final bool canWrite;

  /// Whether mutating git operations (`add`/`commit`/`checkout`/…) are permitted.
  final bool canGitMutate;

  /// Whether any git operation (even read-only) is available.
  final bool supportsGit;

  /// Whether the backend is remote (calls cross a network boundary).
  final bool isRemote;

  const RepoCapabilities({
    this.canWrite = false,
    this.canGitMutate = false,
    this.supportsGit = false,
    this.isRemote = false,
  });

  factory RepoCapabilities.fromJson(Map<String, Object?> json) =>
      RepoCapabilities(
        canWrite: json['canWrite'] == true,
        canGitMutate: json['canGitMutate'] == true,
        supportsGit: json['supportsGit'] == true,
        isRemote: json['isRemote'] == true,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'canWrite': canWrite,
    'canGitMutate': canGitMutate,
    'supportsGit': supportsGit,
    'isRemote': isRemote,
  };
}

/// A 1-based, inclusive line range for partial file reads.
class LineRange {
  /// First line to read (1-based, inclusive).
  final int start;

  /// Last line to read (1-based, inclusive); null reads to the end.
  final int? end;

  const LineRange(this.start, [this.end]);
}

/// The content of a file (or a line slice of it).
class RepoFile {
  final String path;
  final String content;

  /// Total number of lines in the whole file (not just the returned slice).
  final int totalLines;

  /// The 1-based start line of the returned slice, or null for a full read.
  final int? startLine;

  /// The 1-based end line of the returned slice, or null for a full read.
  final int? endLine;

  /// Whether [content] was truncated because the file exceeded the size cap.
  final bool truncated;

  const RepoFile({
    required this.path,
    required this.content,
    required this.totalLines,
    this.startLine,
    this.endLine,
    this.truncated = false,
  });

  factory RepoFile.fromJson(Map<String, Object?> json) => RepoFile(
    path: json['path'] as String,
    content: json['content'] as String,
    totalLines: (json['totalLines'] as num).toInt(),
    startLine: (json['startLine'] as num?)?.toInt(),
    endLine: (json['endLine'] as num?)?.toInt(),
    truncated: json['truncated'] == true,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'content': content,
    'totalLines': totalLines,
    if (startLine != null) 'startLine': startLine,
    if (endLine != null) 'endLine': endLine,
    'truncated': truncated,
  };
}

/// A directory entry produced by [RepositoryAdapter.list].
class RepoEntry {
  /// Path relative to the workspace root, using `/` separators.
  final String path;
  final String name;
  final bool isDir;
  final int? size;

  const RepoEntry({
    required this.path,
    required this.name,
    required this.isDir,
    this.size,
  });

  factory RepoEntry.fromJson(Map<String, Object?> json) => RepoEntry(
    path: json['path'] as String,
    name: json['name'] as String,
    isDir: json['isDir'] == true,
    size: (json['size'] as num?)?.toInt(),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'name': name,
    'isDir': isDir,
    if (size != null) 'size': size,
  };
}

/// File/directory metadata produced by [RepositoryAdapter.stat].
class RepoStat {
  final String path;
  final bool exists;
  final bool isDir;
  final int size;
  final int lineCount;

  /// Last-modified time as an ISO-8601 string, when available.
  final String? modified;

  const RepoStat({
    required this.path,
    required this.exists,
    required this.isDir,
    required this.size,
    required this.lineCount,
    this.modified,
  });

  factory RepoStat.fromJson(Map<String, Object?> json) => RepoStat(
    path: json['path'] as String,
    exists: json['exists'] == true,
    isDir: json['isDir'] == true,
    size: (json['size'] as num).toInt(),
    lineCount: (json['lineCount'] as num).toInt(),
    modified: json['modified'] as String?,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'exists': exists,
    'isDir': isDir,
    'size': size,
    'lineCount': lineCount,
    if (modified != null) 'modified': modified,
  };
}

/// The outcome of an [RepositoryAdapter.edit] (or write).
class RepoEdit {
  final String path;

  /// Number of occurrences replaced.
  final int replacements;

  /// The line the anchored edit was applied at (1-based), when `atLine` was used.
  final int? appliedAtLine;

  const RepoEdit({
    required this.path,
    required this.replacements,
    this.appliedAtLine,
  });

  factory RepoEdit.fromJson(Map<String, Object?> json) => RepoEdit(
    path: json['path'] as String,
    replacements: (json['replacements'] as num).toInt(),
    appliedAtLine: (json['appliedAtLine'] as num?)?.toInt(),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'replacements': replacements,
    if (appliedAtLine != null) 'appliedAtLine': appliedAtLine,
  };
}

/// A content-search hit produced by [RepositoryAdapter.searchText].
class TextMatch {
  final String path;

  /// 1-based line number of the match.
  final int line;

  /// 1-based column (character offset) of the match within the line.
  final int column;

  /// The full text of the matching line.
  final String text;

  /// Context lines before/after the match (empty when no context requested).
  final List<String> before;
  final List<String> after;

  const TextMatch({
    required this.path,
    required this.line,
    required this.column,
    required this.text,
    this.before = const [],
    this.after = const [],
  });

  factory TextMatch.fromJson(Map<String, Object?> json) => TextMatch(
    path: json['path'] as String,
    line: (json['line'] as num).toInt(),
    column: (json['column'] as num).toInt(),
    text: json['text'] as String,
    before: (json['before'] as List?)?.cast<String>() ?? const [],
    after: (json['after'] as List?)?.cast<String>() ?? const [],
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'line': line,
    'column': column,
    'text': text,
    if (before.isNotEmpty) 'before': before,
    if (after.isNotEmpty) 'after': after,
  };
}

/// One entry of `git status` (porcelain).
class GitStatusEntry {
  final String path;

  /// Two-character porcelain code (e.g. `M `, `??`, `A `). Index status is the
  /// first char, working-tree status the second.
  final String status;

  /// Whether the change is staged (index column is not space/`?`).
  final bool staged;

  const GitStatusEntry({
    required this.path,
    required this.status,
    required this.staged,
  });

  factory GitStatusEntry.fromJson(Map<String, Object?> json) => GitStatusEntry(
    path: json['path'] as String,
    status: json['status'] as String,
    staged: json['staged'] == true,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'status': status,
    'staged': staged,
  };
}

/// One commit from `git log`.
class GitCommit {
  final String hash;
  final String author;
  final String date;
  final String subject;

  const GitCommit({
    required this.hash,
    required this.author,
    required this.date,
    required this.subject,
  });

  factory GitCommit.fromJson(Map<String, Object?> json) => GitCommit(
    hash: json['hash'] as String,
    author: json['author'] as String,
    date: json['date'] as String,
    subject: json['subject'] as String,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'hash': hash,
    'author': author,
    'date': date,
    'subject': subject,
  };
}

/// One line of `git blame`.
class GitBlameLine {
  final int line;
  final String hash;
  final String author;
  final String content;

  const GitBlameLine({
    required this.line,
    required this.hash,
    required this.author,
    required this.content,
  });

  factory GitBlameLine.fromJson(Map<String, Object?> json) => GitBlameLine(
    line: (json['line'] as num).toInt(),
    hash: json['hash'] as String,
    author: json['author'] as String,
    content: json['content'] as String,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'line': line,
    'hash': hash,
    'author': author,
    'content': content,
  };
}

/// The result of a mutating git command.
class GitResult {
  final bool ok;
  final String output;

  const GitResult({required this.ok, this.output = ''});

  factory GitResult.fromJson(Map<String, Object?> json) => GitResult(
    ok: json['ok'] == true,
    output: (json['output'] as String?) ?? '',
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'ok': ok,
    'output': output,
  };
}

/// Raised by a [RepositoryAdapter] for an expected, reportable failure — a
/// missing file, a path that escapes the workspace root, a rejected line anchor,
/// or a git error. [RepoRuntime] turns these into `{isError: true}` tool
/// results rather than letting them crash the server.
class RepoException implements Exception {
  final String message;
  const RepoException(this.message);
  @override
  String toString() => 'RepoException: $message';
}

/// Raised when an operation is not permitted by the adapter's capabilities /
/// [RepoConfig] (e.g. a write while read-only). A subtype of [RepoException] so
/// callers can distinguish "forbidden" from "failed".
class RepoPermissionException extends RepoException {
  const RepoPermissionException(super.message);
  @override
  String toString() => 'RepoPermissionException: $message';
}

/// A pluggable backend for the workspace/repository MCP tools.
///
/// All `path` arguments are workspace-relative (POSIX `/` separators). Concrete
/// adapters resolve and confine them to their root and throw a [RepoException]
/// (or [RepoPermissionException]) on any invalid or forbidden access.
abstract interface class RepositoryAdapter {
  /// What this adapter can/‌may do, so tools can report unsupported operations
  /// cleanly.
  RepoCapabilities get capabilities;

  // --- Filesystem (read) ---

  /// Reads [path], optionally only the lines in [range].
  Future<RepoFile> read(String path, {LineRange? range});

  /// Lists the directory at [path]. When [recursive], descends up to [maxDepth]
  /// levels; [glob] filters entries by name/path pattern.
  Future<List<RepoEntry>> list(
    String path, {
    bool recursive = false,
    int? maxDepth,
    String? glob,
  });

  /// Finds files whose workspace-relative path matches [glob] (returns up to
  /// [limit] paths).
  Future<List<String>> find({String? glob, int? limit});

  /// Metadata for [path] (never throws for a missing path — returns
  /// `exists: false`).
  Future<RepoStat> stat(String path);

  // --- Filesystem (write; gated by [capabilities.canWrite]) ---

  /// Creates or overwrites [path] with [content].
  Future<RepoEdit> write(String path, String content);

  /// Replaces [oldString] with [newString] in [path]. When [replaceAll] is
  /// false exactly one occurrence must match. When [atLine] is given, the match
  /// must occur on that 1-based line or the edit is rejected.
  Future<RepoEdit> edit(
    String path,
    String oldString,
    String newString, {
    bool replaceAll = false,
    int? atLine,
  });

  /// Creates the directory [path] (and any missing parents).
  Future<void> mkdir(String path);

  /// Moves/renames [from] to [to].
  Future<void> move(String from, String to);

  /// Deletes the file or directory [path].
  Future<void> delete(String path);

  // --- Search ---

  /// Searches file contents for [pattern] (a regular expression). [glob] limits
  /// which files are searched; [context] lines of surrounding text are attached.
  Future<List<TextMatch>> searchText(
    String pattern, {
    String? glob,
    bool ignoreCase = false,
    int context = 0,
    int? limit,
  });

  // --- Git (read) ---

  Future<List<GitStatusEntry>> gitStatus();

  Future<String> gitDiff({String? rev, bool staged = false, String? path});

  Future<List<GitCommit>> gitLog({int? limit, String? path});

  Future<String> gitShow({required String rev, String? path});

  Future<List<GitBlameLine>> gitBlame(String path);

  // --- Git (write; gated by [capabilities.canGitMutate]) ---

  Future<GitResult> gitAdd(List<String> paths);

  Future<GitResult> gitCommit(String message, {List<String>? paths});

  Future<GitResult> gitCheckout(String rev);

  Future<GitResult> gitRestore(List<String> paths, {bool staged = false});
}
