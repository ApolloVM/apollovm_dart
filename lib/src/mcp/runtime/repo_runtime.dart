// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:apollovm/apollovm_lsp.dart' show Analyzer;
import 'package:dart_mcp/server.dart' show Tool;

import '../mcp_config.dart';
import '../repo/repository_adapter.dart';
import '../tools/code_tools.dart';
import '../tools/fs_tools.dart';
import '../tools/git_tools.dart';
import '../tools/search_tools.dart';
import 'lsp_runtime.dart';

/// All workspace/repository tool names (fs + search + code + git), in
/// registration order.
const repoToolNames = <String>[
  ...fsToolNames,
  ...searchToolNames,
  ...codeToolNames,
  ...gitToolNames,
];

/// The [Tool] definitions for every workspace/repository tool.
List<Tool> buildRepoTools() => [
  ...buildFsTools(),
  ...buildSearchTools(),
  ...buildCodeTools(),
  ...buildGitTools(),
];

/// Whether [name] is one of the workspace/repository tools handled by
/// [RepoRuntime].
bool isRepoTool(String name) => repoToolNames.contains(name);

/// Executes the `apollovm.fs.*` / `apollovm.search.*` / `apollovm.code.*` /
/// `apollovm.git.*` tools against a [RepositoryAdapter].
///
/// Unlike the host-pure core/LSP tool functions, this runtime is stateful (it
/// holds the adapter and workspace), so the server routes repo-tool calls here
/// directly rather than through the isolate/`computeTool` path. Expected
/// failures raised as [RepoException] become `{isError: true}` results.
class RepoRuntime {
  final RepositoryAdapter adapter;
  final McpLimits limits;

  /// Language-aware backend for the `apollovm.code.*` tools.
  final LspRuntime _lsp;

  /// Combined-source budget (bytes) for the whole-workspace symbol operations
  /// (`search.symbols`, `code.workspaceSymbols`), which load many files into one
  /// language service. Much larger than the single-source `maxSourceChars` cap,
  /// while still bounding memory so a huge repo fails cleanly instead of OOMing.
  static const _workspaceSourceBudget = 16 * 1024 * 1024;

  RepoRuntime(this.adapter, {this.limits = const McpLimits()})
    : _lsp = LspRuntime(
        limits: limits.copyWith(
          maxSourceChars: limits.maxSourceChars > _workspaceSourceBudget
              ? limits.maxSourceChars
              : _workspaceSourceBudget,
        ),
      );

  /// LSP SymbolKind name → LSP numeric kind, for `search.symbols` filtering.
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

  static String _str(Map<String, Object?> a, String k, [String d = '']) =>
      (a[k] as String?) ?? d;

  static int? _intOrNull(Map<String, Object?> a, String k) {
    final v = a[k];
    return v is num ? v.toInt() : null;
  }

  static int _int(Map<String, Object?> a, String k, [int d = 0]) =>
      _intOrNull(a, k) ?? d;

  static bool _bool(Map<String, Object?> a, String k, [bool d = false]) =>
      (a[k] as bool?) ?? d;

  static List<String> _strList(Map<String, Object?> a, String k) =>
      ((a[k] as List?)?.cast<Object?>() ?? const [])
          .whereType<String>()
          .toList();

  Map<String, Object?> _error(String message) => <String, Object?>{
    'diagnostics': [
      <String, Object?>{'severity': 'error', 'message': message},
    ],
    'isError': true,
  };

  /// Runs the repo tool named [name] with [args], returning its JSON result map.
  Future<Map<String, Object?>> call(
    String name,
    Map<String, Object?> args,
  ) async {
    try {
      return await _dispatch(name, args);
    } on RepoException catch (e) {
      return _error(e.message);
    }
  }

  Future<Map<String, Object?>> _dispatch(
    String name,
    Map<String, Object?> args,
  ) async {
    switch (name) {
      // --- Filesystem ---
      case fsReadToolName:
        final start = _intOrNull(args, 'startLine');
        final range = start == null
            ? null
            : LineRange(start, _intOrNull(args, 'endLine'));
        final f = await adapter.read(_str(args, 'path'), range: range);
        return {...f.toJson(), 'isError': false};

      case fsListToolName:
        final entries = await adapter.list(
          _str(args, 'path'),
          recursive: _bool(args, 'recursive'),
          maxDepth: _intOrNull(args, 'maxDepth'),
          glob: args['glob'] as String?,
        );
        return {
          'entries': entries.map((e) => e.toJson()).toList(),
          'isError': false,
        };

      case fsFindToolName:
        final paths = await adapter.find(
          glob: args['glob'] as String?,
          limit: _intOrNull(args, 'limit'),
        );
        return {'paths': paths, 'count': paths.length, 'isError': false};

      case fsStatToolName:
        final s = await adapter.stat(_str(args, 'path'));
        return {...s.toJson(), 'isError': false};

      case fsWriteToolName:
        final e = await adapter.write(
          _str(args, 'path'),
          _str(args, 'content'),
        );
        return {...e.toJson(), 'isError': false};

      case fsEditToolName:
        final e = await adapter.edit(
          _str(args, 'path'),
          _str(args, 'oldString'),
          _str(args, 'newString'),
          replaceAll: _bool(args, 'replaceAll'),
          atLine: _intOrNull(args, 'atLine'),
        );
        return {...e.toJson(), 'isError': false};

      case fsMkdirToolName:
        await adapter.mkdir(_str(args, 'path'));
        return {'ok': true, 'isError': false};

      case fsMoveToolName:
        await adapter.move(_str(args, 'from'), _str(args, 'to'));
        return {'ok': true, 'isError': false};

      case fsDeleteToolName:
        await adapter.delete(_str(args, 'path'));
        return {'ok': true, 'isError': false};

      // --- Search ---
      case searchTextToolName:
        final hits = await adapter.searchText(
          _str(args, 'pattern'),
          glob: args['glob'] as String?,
          ignoreCase: _bool(args, 'ignoreCase'),
          context: _int(args, 'context'),
          limit: _intOrNull(args, 'limit'),
        );
        return {
          'matches': hits.map((m) => m.toJson()).toList(),
          'count': hits.length,
          'isError': false,
        };

      case searchSymbolsToolName:
        return _searchSymbols(args);

      // --- Code navigation (language-aware) ---
      case codeOutlineToolName:
        return _code(
          args,
          (lang, src, uri) => _lsp.documentSymbols(lang, src, uri: uri),
        );

      case codeDiagnosticsToolName:
        return _code(
          args,
          (lang, src, uri) => _lsp.diagnostics(lang, src, uri: uri),
        );

      case codeDefinitionToolName:
        return _code(
          args,
          (lang, src, uri) => _lsp.definition(
            lang,
            src,
            _int(args, 'line'),
            _int(args, 'character'),
            uri: uri,
          ),
        );

      case codeHoverToolName:
        return _code(
          args,
          (lang, src, uri) => _lsp.hover(
            lang,
            src,
            _int(args, 'line'),
            _int(args, 'character'),
            uri: uri,
          ),
        );

      case codeReferencesToolName:
        return _code(
          args,
          (lang, src, uri) => _lsp.references(
            lang,
            src,
            _int(args, 'line'),
            _int(args, 'character'),
            includeDeclaration: _bool(args, 'includeDeclaration', true),
            uri: uri,
          ),
        );

      case codeWorkspaceSymbolsToolName:
        return _workspaceSymbols(args, kind: null);

      // --- Git ---
      case gitStatusToolName:
        final st = await adapter.gitStatus();
        return {
          'entries': st.map((e) => e.toJson()).toList(),
          'clean': st.isEmpty,
          'isError': false,
        };

      case gitDiffToolName:
        final diff = await adapter.gitDiff(
          rev: args['rev'] as String?,
          staged: _bool(args, 'staged'),
          path: args['path'] as String?,
        );
        return {'diff': diff, 'isError': false};

      case gitLogToolName:
        final log = await adapter.gitLog(
          limit: _intOrNull(args, 'limit'),
          path: args['path'] as String?,
        );
        return {
          'commits': log.map((c) => c.toJson()).toList(),
          'isError': false,
        };

      case gitShowToolName:
        final show = await adapter.gitShow(
          rev: _str(args, 'rev'),
          path: args['path'] as String?,
        );
        return {'content': show, 'isError': false};

      case gitBlameToolName:
        final blame = await adapter.gitBlame(_str(args, 'path'));
        return {
          'lines': blame.map((b) => b.toJson()).toList(),
          'isError': false,
        };

      case gitAddToolName:
        final r = await adapter.gitAdd(_strList(args, 'paths'));
        return {...r.toJson(), 'isError': !r.ok};

      case gitCommitToolName:
        final paths = _strList(args, 'paths');
        final r = await adapter.gitCommit(
          _str(args, 'message'),
          paths: paths.isEmpty ? null : paths,
        );
        return {...r.toJson(), 'isError': !r.ok};

      case gitCheckoutToolName:
        final r = await adapter.gitCheckout(_str(args, 'rev'));
        return {...r.toJson(), 'isError': !r.ok};

      case gitRestoreToolName:
        final r = await adapter.gitRestore(
          _strList(args, 'paths'),
          staged: _bool(args, 'staged'),
        );
        return {...r.toJson(), 'isError': !r.ok};

      default:
        return _error('Unknown repository tool: $name');
    }
  }

  /// Reads the file at `args['path']`, infers its language from the extension,
  /// and runs [query] (an [LspRuntime] call) against its content.
  Future<Map<String, Object?>> _code(
    Map<String, Object?> args,
    Future<Map<String, Object?>> Function(String lang, String src, String uri)
    query,
  ) async {
    final path = _str(args, 'path');
    final uri = _fileUri(path);
    final language = Analyzer.languageOf(uri);
    if (language == null) {
      return _error(
        'Cannot infer a supported language from the file extension: $path',
      );
    }
    final file = await adapter.read(path);
    return query(language, file.content, uri);
  }

  /// Loads the workspace source files matching `args['glob']` and delegates to
  /// [LspRuntime.workspaceSymbols], optionally filtering by symbol [kind].
  Future<Map<String, Object?>> _workspaceSymbols(
    Map<String, Object?> args, {
    required String? kind,
  }) async {
    final glob = args['glob'] as String?;
    final paths = await adapter.find(glob: glob);
    final files = <Map<String, Object?>>[];
    for (final p in paths) {
      final uri = _fileUri(p);
      if (Analyzer.languageOf(uri) == null) continue; // not a parseable source
      final f = await adapter.read(p);
      files.add(<String, Object?>{'uri': uri, 'source': f.content});
    }
    final result = await _lsp.workspaceSymbols(_str(args, 'query'), files);
    if (kind == null || result['isError'] == true) return result;

    final wanted = _kindByName[kind.toLowerCase()];
    if (wanted == null) return result;
    final symbols = (result['symbols'] as List?) ?? const [];
    final filtered = symbols
        .whereType<Map>()
        .where((s) => (s['kind'] as num?)?.toInt() == wanted)
        .toList();
    return {...result, 'symbols': filtered};
  }

  Future<Map<String, Object?>> _searchSymbols(Map<String, Object?> args) =>
      _workspaceSymbols(args, kind: args['kind'] as String?);

  String _fileUri(String path) {
    final norm = path.replaceAll('\\', '/');
    return norm.startsWith('/') ? 'file://$norm' : 'file:///$norm';
  }
}
