// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:apollovm/apollovm_lsp.dart';

import 'permission_guard.dart';
import 'repo_config.dart';
import 'repository_adapter.dart';

/// A high-level, **typed** façade over a [RepositoryAdapter] — the entry point
/// for using ApolloVM's repository features from any Dart host (a web IDE, a
/// desktop editor, an agent, a test), independently of MCP.
///
/// It bundles three things behind one typed API:
///   * the filesystem/search/git operations of the underlying adapter,
///   * a [RepoConfig] enforced by a [PermissionGuard] (read-only by default), and
///   * **language-aware** code navigation (`outline`/`definition`/`references`/
///     `hover`/`diagnostics`/`workspaceSymbols`/`searchSymbols`) powered by
///     ApolloVM's own parsers via an in-process [LspService] — the file contents
///     are read through the adapter, so navigation works on the real workspace.
///
/// Like the rest of the repository library this is web-safe (no `dart:io`); pair
/// it with an `InMemoryRepositoryAdapter` in the browser or a
/// `LocalRepositoryAdapter` on the VM. The MCP `apollovm.fs.*`/`search.*`/
/// `code.*`/`git.*` tools are a thin JSON layer over this same service.
///
/// ```dart
/// final repo = RepositoryService(InMemoryRepositoryAdapter(files));
/// final file = await repo.read('lib/main.dart');
/// final outline = await repo.outline('lib/main.dart');
/// await repo.close();
/// ```
class RepositoryService {
  /// The permission-guarded adapter every operation goes through.
  final RepositoryAdapter adapter;

  LspService? _lsp;

  /// Wraps [adapter] with [config] (via a [PermissionGuard], unless [adapter] is
  /// already one) and exposes it as a typed service.
  RepositoryService(
    RepositoryAdapter adapter, {
    RepoConfig config = const RepoConfig(),
  }) : adapter = adapter is PermissionGuard
           ? adapter
           : PermissionGuard(adapter, config: config);

  /// What the underlying backend (as configured) can and may do.
  RepoCapabilities get capabilities => adapter.capabilities;

  // --- Filesystem / search / git (typed pass-throughs) ---

  Future<RepoFile> read(String path, {LineRange? range}) =>
      adapter.read(path, range: range);

  Future<List<RepoEntry>> list(
    String path, {
    bool recursive = false,
    int? maxDepth,
    String? glob,
  }) =>
      adapter.list(path, recursive: recursive, maxDepth: maxDepth, glob: glob);

  Future<List<String>> find({String? glob, int? limit}) =>
      adapter.find(glob: glob, limit: limit);

  Future<RepoStat> stat(String path) => adapter.stat(path);

  Future<RepoEdit> write(String path, String content) =>
      adapter.write(path, content);

  Future<RepoEdit> edit(
    String path,
    String oldString,
    String newString, {
    bool replaceAll = false,
    int? atLine,
  }) => adapter.edit(
    path,
    oldString,
    newString,
    replaceAll: replaceAll,
    atLine: atLine,
  );

  Future<void> mkdir(String path) => adapter.mkdir(path);

  Future<void> move(String from, String to) => adapter.move(from, to);

  Future<void> delete(String path) => adapter.delete(path);

  Future<List<TextMatch>> searchText(
    String pattern, {
    String? glob,
    bool ignoreCase = false,
    int context = 0,
    int? limit,
  }) => adapter.searchText(
    pattern,
    glob: glob,
    ignoreCase: ignoreCase,
    context: context,
    limit: limit,
  );

  Future<List<GitStatusEntry>> gitStatus() => adapter.gitStatus();

  Future<String> gitDiff({String? rev, bool staged = false, String? path}) =>
      adapter.gitDiff(rev: rev, staged: staged, path: path);

  Future<List<GitCommit>> gitLog({int? limit, String? path}) =>
      adapter.gitLog(limit: limit, path: path);

  Future<String> gitShow({required String rev, String? path}) =>
      adapter.gitShow(rev: rev, path: path);

  Future<List<GitBlameLine>> gitBlame(String path) => adapter.gitBlame(path);

  Future<GitResult> gitAdd(List<String> paths) => adapter.gitAdd(paths);

  Future<GitResult> gitCommit(String message, {List<String>? paths}) =>
      adapter.gitCommit(message, paths: paths);

  Future<GitResult> gitCheckout(String rev) => adapter.gitCheckout(rev);

  Future<GitResult> gitRestore(List<String> paths, {bool staged = false}) =>
      adapter.gitRestore(paths, staged: staged);

  // --- Language-aware code navigation ---

  /// LSP `SymbolKind` name → numeric kind, for [searchSymbols] filtering.
  static const _kindByName = <String, int>{
    'file': 1,
    'namespace': 3,
    'class': 5,
    'method': 6,
    'property': 7,
    'field': 8,
    'constructor': 9,
    'enum': 10,
    'function': 12,
    'variable': 13,
    'enummember': 22,
  };

  /// The document outline (hierarchical symbols) of [path].
  Future<List<DocumentSymbol>> outline(String path) =>
      _withDoc(path, (lsp, uri) => lsp.documentSymbols(uri));

  /// Parse diagnostics for [path].
  Future<List<Diagnostic>> diagnostics(String path) async {
    final uri = _requireLangUri(path);
    final content = (await adapter.read(path)).content;
    return (await _service()).analyze(uri, content);
  }

  /// Hover info at [line]:[character] (zero-based) in [path].
  Future<Hover?> hover(String path, int line, int character) =>
      _withDoc(path, (lsp, uri) => lsp.hover(uri, Position(line, character)));

  /// The declaration location of the symbol at [line]:[character] in [path].
  Future<Location?> definition(String path, int line, int character) =>
      _withDoc(
        path,
        (lsp, uri) => lsp.definition(uri, Position(line, character)),
      );

  /// References to the symbol at [line]:[character] in [path].
  Future<List<Location>> references(
    String path,
    int line,
    int character, {
    bool includeDeclaration = true,
  }) => _withDoc(
    path,
    (lsp, uri) => lsp.references(
      uri,
      Position(line, character),
      includeDeclaration: includeDeclaration,
    ),
  );

  /// Workspace-wide symbols matching [query], loading every parseable source
  /// file under [glob] (all files when null) through the adapter.
  ///
  /// Uses a fresh, scoped language service per call so the result always
  /// reflects the current file contents and exactly the requested [glob] — never
  /// stale buffers from an earlier query.
  Future<List<WorkspaceSymbol>> workspaceSymbols(
    String query, {
    String? glob,
  }) async {
    final lsp = LspService();
    try {
      final paths = await adapter.find(glob: glob);
      for (final p in paths) {
        final uri = _fileUri(p);
        if (Analyzer.languageOf(uri) == null) continue; // not parseable
        await lsp.analyze(uri, (await adapter.read(p)).content);
      }
      return await lsp.workspaceSymbols(query);
    } finally {
      await lsp.dispose();
    }
  }

  /// Language-aware declaration search: [workspaceSymbols] filtered by an
  /// optional symbol [kind] name (e.g. `class`, `method`, `function`).
  Future<List<WorkspaceSymbol>> searchSymbols(
    String query, {
    String? kind,
    String? glob,
  }) async {
    final all = await workspaceSymbols(query, glob: glob);
    if (kind == null) return all;
    final wanted = _kindByName[kind.toLowerCase()];
    if (wanted == null) return all;
    return all.where((s) => s.kind == wanted).toList();
  }

  /// Releases the internal language service (if any).
  Future<void> close() async {
    await _lsp?.dispose();
    _lsp = null;
  }

  // --- internals ---

  Future<LspService> _service() async => _lsp ??= LspService();

  /// Reads [path], opens it in the language service, and runs [query].
  Future<T> _withDoc<T>(
    String path,
    Future<T> Function(LspService lsp, String uri) query,
  ) async {
    final uri = _requireLangUri(path);
    final content = (await adapter.read(path)).content;
    final lsp = await _service();
    await lsp.analyze(uri, content); // (re)opens the buffer with fresh content
    return query(lsp, uri);
  }

  String _requireLangUri(String path) {
    final uri = _fileUri(path);
    if (Analyzer.languageOf(uri) == null) {
      throw RepoException(
        'Cannot infer a supported language from the file extension: $path',
      );
    }
    return uri;
  }

  String _fileUri(String path) {
    final norm = path.replaceAll('\\', '/');
    return norm.startsWith('/') ? 'file://$norm' : 'file:///$norm';
  }
}
