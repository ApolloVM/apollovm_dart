// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:apollovm/apollovm_lsp.dart' show DiagnosticSeverity;
import 'package:dart_mcp/server.dart' show Tool;

import '../../repository/repository_adapter.dart';
import '../../repository/repository_service.dart';
import '../tools/code_tools.dart';
import '../tools/fs_tools.dart';
import '../tools/git_tools.dart';
import '../tools/search_tools.dart';

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

/// The **MCP JSON layer** over a [RepositoryService]: it maps the
/// `apollovm.fs.*` / `apollovm.search.*` / `apollovm.code.*` / `apollovm.git.*`
/// tool calls to typed service methods and serializes the results to JSON.
///
/// All the actual behavior (permission enforcement, path confinement,
/// language-aware navigation) lives in [RepositoryService], which non-MCP hosts
/// (a web IDE, an editor) can use directly. Expected failures raised as
/// [RepoException] become `{isError: true}` results.
class RepoRuntime {
  final RepositoryService service;

  /// Wraps [adapter] (already permission-guarded by the server) in a
  /// [RepositoryService].
  RepoRuntime(RepositoryAdapter adapter) : service = RepositoryService(adapter);

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
        final f = await service.read(_str(args, 'path'), range: range);
        return {...f.toJson(), 'isError': false};

      case fsListToolName:
        final entries = await service.list(
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
        final paths = await service.find(
          glob: args['glob'] as String?,
          limit: _intOrNull(args, 'limit'),
        );
        return {'paths': paths, 'count': paths.length, 'isError': false};

      case fsStatToolName:
        final s = await service.stat(_str(args, 'path'));
        return {...s.toJson(), 'isError': false};

      case fsWriteToolName:
        final e = await service.write(
          _str(args, 'path'),
          _str(args, 'content'),
        );
        return {...e.toJson(), 'isError': false};

      case fsEditToolName:
        final e = await service.edit(
          _str(args, 'path'),
          _str(args, 'oldString'),
          _str(args, 'newString'),
          replaceAll: _bool(args, 'replaceAll'),
          atLine: _intOrNull(args, 'atLine'),
        );
        return {...e.toJson(), 'isError': false};

      case fsMkdirToolName:
        await service.mkdir(_str(args, 'path'));
        return {'ok': true, 'isError': false};

      case fsMoveToolName:
        await service.move(_str(args, 'from'), _str(args, 'to'));
        return {'ok': true, 'isError': false};

      case fsDeleteToolName:
        await service.delete(_str(args, 'path'));
        return {'ok': true, 'isError': false};

      // --- Search ---
      case searchTextToolName:
        final hits = await service.searchText(
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
        final symbols = await service.searchSymbols(
          _str(args, 'query'),
          kind: args['kind'] as String?,
          glob: args['glob'] as String?,
        );
        return {
          'symbols': symbols.map((s) => s.toJson()).toList(),
          'count': symbols.length,
          'isError': false,
        };

      // --- Code navigation (language-aware) ---
      case codeOutlineToolName:
        final symbols = await service.outline(_str(args, 'path'));
        return {
          'symbols': symbols.map((s) => s.toJson()).toList(),
          'isError': false,
        };

      case codeDiagnosticsToolName:
        final diags = await service.diagnostics(_str(args, 'path'));
        return {
          'diagnostics': diags.map((d) => d.toJson()).toList(),
          'ok': diags.every((d) => d.severity != DiagnosticSeverity.error),
          'isError': false,
        };

      case codeDefinitionToolName:
        final def = await service.definition(
          _str(args, 'path'),
          _int(args, 'line'),
          _int(args, 'character'),
        );
        return {'definition': def?.toJson(), 'isError': false};

      case codeHoverToolName:
        final hover = await service.hover(
          _str(args, 'path'),
          _int(args, 'line'),
          _int(args, 'character'),
        );
        return {'hover': hover?.toJson(), 'isError': false};

      case codeReferencesToolName:
        final refs = await service.references(
          _str(args, 'path'),
          _int(args, 'line'),
          _int(args, 'character'),
          includeDeclaration: _bool(args, 'includeDeclaration', true),
        );
        return {
          'references': refs.map((l) => l.toJson()).toList(),
          'isError': false,
        };

      case codeWorkspaceSymbolsToolName:
        final symbols = await service.workspaceSymbols(
          _str(args, 'query'),
          glob: args['glob'] as String?,
        );
        return {
          'symbols': symbols.map((s) => s.toJson()).toList(),
          'count': symbols.length,
          'isError': false,
        };

      // --- Git ---
      case gitStatusToolName:
        final st = await service.gitStatus();
        return {
          'entries': st.map((e) => e.toJson()).toList(),
          'clean': st.isEmpty,
          'isError': false,
        };

      case gitDiffToolName:
        final diff = await service.gitDiff(
          rev: args['rev'] as String?,
          staged: _bool(args, 'staged'),
          path: args['path'] as String?,
        );
        return {'diff': diff, 'isError': false};

      case gitLogToolName:
        final log = await service.gitLog(
          limit: _intOrNull(args, 'limit'),
          path: args['path'] as String?,
        );
        return {
          'commits': log.map((c) => c.toJson()).toList(),
          'isError': false,
        };

      case gitShowToolName:
        final show = await service.gitShow(
          rev: _str(args, 'rev'),
          path: args['path'] as String?,
        );
        return {'content': show, 'isError': false};

      case gitBlameToolName:
        final blame = await service.gitBlame(_str(args, 'path'));
        return {
          'lines': blame.map((b) => b.toJson()).toList(),
          'isError': false,
        };

      case gitAddToolName:
        final r = await service.gitAdd(_strList(args, 'paths'));
        return {...r.toJson(), 'isError': !r.ok};

      case gitCommitToolName:
        final paths = _strList(args, 'paths');
        final r = await service.gitCommit(
          _str(args, 'message'),
          paths: paths.isEmpty ? null : paths,
        );
        return {...r.toJson(), 'isError': !r.ok};

      case gitCheckoutToolName:
        final r = await service.gitCheckout(_str(args, 'rev'));
        return {...r.toJson(), 'isError': !r.ok};

      case gitRestoreToolName:
        final r = await service.gitRestore(
          _strList(args, 'paths'),
          staged: _bool(args, 'staged'),
        );
        return {...r.toJson(), 'isError': !r.ok};

      default:
        return _error('Unknown repository tool: $name');
    }
  }
}
