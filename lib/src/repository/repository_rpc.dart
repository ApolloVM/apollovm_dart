// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'repository_adapter.dart';
import 'repository_service.dart';

/// A tiny, transport-agnostic JSON layer over a [RepositoryService].
///
/// It maps a plain `{'op': <name>, ...args}` request map to the matching
/// [RepositoryService] method and serializes the result with the value types'
/// existing `toJson()`. It is **web-safe** (no `dart:io`): a server (see
/// `tool/repository_server.dart`) only has to move JSON maps in and out over
/// HTTP, and a `RemoteRepositoryAdapter` on the other side speaks the exact same
/// ops via the [Op] constants below — so the wire contract lives in one place.
///
/// Every call returns a normalized envelope:
///   * success → `{'ok': true, 'result': <object>}`
///   * a reported failure ([RepoException]) → `{'ok': false, 'error': {'type',
///     'message'}}`, with `type` = `RepoPermissionException` or `RepoException`.
///
/// Result shapes (keyed so the client deserializes unambiguously):
///   * scalar value types (`read`/`stat`/`write`/`edit`/`capabilities`/git
///     mutations) → the value's `toJson()` map directly.
///   * `list`/`gitStatus` → `{'entries': [...]}`; `find` → `{'paths': [...]}`;
///     `searchText` → `{'matches': [...]}`; `gitLog` → `{'commits': [...]}`;
///     `gitBlame` → `{'lines': [...]}`; `gitDiff`/`gitShow` → `{'text': ...}`;
///     void ops (`mkdir`/`move`/`delete`) → `{}`.
class RepositoryRpc {
  final RepositoryService service;

  RepositoryRpc(this.service);

  /// Handles a single decoded request map and returns the response envelope.
  /// Never throws for a [RepoException]; unexpected errors surface as a generic
  /// `RepoException`-typed error so a server can always reply with valid JSON.
  Future<Map<String, Object?>> handle(Map<String, Object?> request) async {
    final op = request['op'];
    if (op is! String) {
      return _err('RepoException', "Missing or invalid 'op' field.");
    }
    try {
      final result = await _dispatch(op, request);
      return <String, Object?>{'ok': true, 'result': result};
    } on RepoPermissionException catch (e) {
      return _err('RepoPermissionException', e.message);
    } on RepoException catch (e) {
      return _err('RepoException', e.message);
    } catch (e) {
      return _err('RepoException', e.toString());
    }
  }

  Future<Object?> _dispatch(String op, Map<String, Object?> r) async {
    switch (op) {
      case Op.capabilities:
        return service.capabilities.toJson();

      case Op.read:
        final range = _range(r);
        final file = await service.read(_str(r, 'path'), range: range);
        return file.toJson();

      case Op.list:
        final entries = await service.list(
          _str(r, 'path', ''),
          recursive: _bool(r, 'recursive'),
          maxDepth: _int(r, 'maxDepth'),
          glob: _strOrNull(r, 'glob'),
        );
        return {'entries': entries.map((e) => e.toJson()).toList()};

      case Op.find:
        final paths = await service.find(
          glob: _strOrNull(r, 'glob'),
          limit: _int(r, 'limit'),
        );
        return {'paths': paths};

      case Op.stat:
        return (await service.stat(_str(r, 'path'))).toJson();

      case Op.write:
        return (await service.write(
          _str(r, 'path'),
          _str(r, 'content'),
        )).toJson();

      case Op.edit:
        final edit = await service.edit(
          _str(r, 'path'),
          _str(r, 'oldString'),
          _str(r, 'newString'),
          replaceAll: _bool(r, 'replaceAll'),
          atLine: _int(r, 'atLine'),
        );
        return edit.toJson();

      case Op.mkdir:
        await service.mkdir(_str(r, 'path'));
        return const <String, Object?>{};

      case Op.move:
        await service.move(_str(r, 'from'), _str(r, 'to'));
        return const <String, Object?>{};

      case Op.delete:
        await service.delete(_str(r, 'path'));
        return const <String, Object?>{};

      case Op.searchText:
        final matches = await service.searchText(
          _str(r, 'pattern'),
          glob: _strOrNull(r, 'glob'),
          ignoreCase: _bool(r, 'ignoreCase'),
          context: _int(r, 'context') ?? 0,
          limit: _int(r, 'limit'),
        );
        return {'matches': matches.map((m) => m.toJson()).toList()};

      case Op.gitStatus:
        final entries = await service.gitStatus();
        return {'entries': entries.map((e) => e.toJson()).toList()};

      case Op.gitDiff:
        final diff = await service.gitDiff(
          rev: _strOrNull(r, 'rev'),
          staged: _bool(r, 'staged'),
          path: _strOrNull(r, 'path'),
        );
        return {'text': diff};

      case Op.gitLog:
        final commits = await service.gitLog(
          limit: _int(r, 'limit'),
          path: _strOrNull(r, 'path'),
        );
        return {'commits': commits.map((c) => c.toJson()).toList()};

      case Op.gitShow:
        final text = await service.gitShow(
          rev: _str(r, 'rev'),
          path: _strOrNull(r, 'path'),
        );
        return {'text': text};

      case Op.gitBlame:
        final lines = await service.gitBlame(_str(r, 'path'));
        return {'lines': lines.map((l) => l.toJson()).toList()};

      case Op.gitAdd:
        return (await service.gitAdd(_strList(r, 'paths'))).toJson();

      case Op.gitCommit:
        return (await service.gitCommit(
          _str(r, 'message'),
          paths: _strListOrNull(r, 'paths'),
        )).toJson();

      case Op.gitCheckout:
        return (await service.gitCheckout(_str(r, 'rev'))).toJson();

      case Op.gitRestore:
        return (await service.gitRestore(
          _strList(r, 'paths'),
          staged: _bool(r, 'staged'),
        )).toJson();

      default:
        throw RepoException('Unknown op: $op');
    }
  }

  static Map<String, Object?> _err(String type, String message) =>
      <String, Object?>{
        'ok': false,
        'error': {'type': type, 'message': message},
      };

  // --- argument coercion ---

  static LineRange? _range(Map<String, Object?> r) {
    final start = _int(r, 'start');
    if (start == null) return null;
    return LineRange(start, _int(r, 'end'));
  }

  static String _str(Map<String, Object?> r, String key, [String? fallback]) {
    final v = r[key];
    if (v is String) return v;
    if (v == null && fallback != null) return fallback;
    throw RepoException("Missing or invalid string arg '$key'.");
  }

  static String? _strOrNull(Map<String, Object?> r, String key) {
    final v = r[key];
    return v is String ? v : null;
  }

  static bool _bool(Map<String, Object?> r, String key) => r[key] == true;

  static int? _int(Map<String, Object?> r, String key) {
    final v = r[key];
    return v is num ? v.toInt() : null;
  }

  static List<String> _strList(Map<String, Object?> r, String key) =>
      _strListOrNull(r, key) ?? const <String>[];

  static List<String>? _strListOrNull(Map<String, Object?> r, String key) {
    final v = r[key];
    if (v is List) return v.map((e) => '$e').toList();
    return null;
  }
}

/// The op names shared by [RepositoryRpc] (server) and `RemoteRepositoryAdapter`
/// (client) — one source of truth for the wire contract.
abstract final class Op {
  static const capabilities = 'capabilities';
  static const read = 'read';
  static const list = 'list';
  static const find = 'find';
  static const stat = 'stat';
  static const write = 'write';
  static const edit = 'edit';
  static const mkdir = 'mkdir';
  static const move = 'move';
  static const delete = 'delete';
  static const searchText = 'searchText';
  static const gitStatus = 'gitStatus';
  static const gitDiff = 'gitDiff';
  static const gitLog = 'gitLog';
  static const gitShow = 'gitShow';
  static const gitBlame = 'gitBlame';
  static const gitAdd = 'gitAdd';
  static const gitCommit = 'gitCommit';
  static const gitCheckout = 'gitCheckout';
  static const gitRestore = 'gitRestore';
}
