// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'repository_adapter.dart';
import 'repository_rpc.dart';

/// A [RepositoryAdapter] that talks to a remote repository server over HTTP.
///
/// It is the client half of the JSON contract defined by [RepositoryRpc]: each
/// call `POST`s `{'op': ..., ...args}` to `<baseUrl>/rpc` and deserializes the
/// `result` with the value types' `fromJson`. The wire op names come from [Op],
/// so client and server can never drift.
///
/// This is **web-safe** — `package:http` runs in the browser — so a web IDE can
/// browse, edit and run git against a real project served by
/// `tool/repository_server.dart` (see [RepoCapabilities.isRemote], which this
/// adapter always reports true).
///
/// Because [capabilities] is a synchronous getter, construct the adapter with
/// the async [connect] factory, which fetches the server's capabilities once:
///
/// ```dart
/// final adapter = await RemoteRepositoryAdapter.connect('http://127.0.0.1:8090');
/// final repo = RepositoryService(adapter,
///     config: const RepoConfig(allowWrite: true, allowGitMutation: true));
/// ```
class RemoteRepositoryAdapter implements RepositoryAdapter {
  /// The server base URL, e.g. `http://127.0.0.1:8090` (no trailing slash).
  final String baseUrl;

  final http.Client _client;

  /// Whether [_client] was created by us (and so must be closed by [close]).
  final bool _ownsClient;

  RepoCapabilities _capabilities;

  RemoteRepositoryAdapter._(
    this.baseUrl,
    this._client,
    this._ownsClient,
    this._capabilities,
  );

  /// Connects to the repository server at [baseUrl], fetching its capabilities.
  ///
  /// The reported capabilities always have `isRemote: true`, regardless of what
  /// the server sends.
  static Future<RemoteRepositoryAdapter> connect(
    String baseUrl, {
    http.Client? client,
  }) async {
    final normalized = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final httpClient = client ?? http.Client();
    final adapter = RemoteRepositoryAdapter._(
      normalized,
      httpClient,
      client == null,
      const RepoCapabilities(isRemote: true),
    );
    final caps = await adapter._call(Op.capabilities, const {});
    adapter._capabilities = RepoCapabilities.fromJson(_asMap(caps))._asRemote();
    return adapter;
  }

  @override
  RepoCapabilities get capabilities => _capabilities;

  /// Closes the underlying HTTP client (only if this adapter created it).
  void close() {
    if (_ownsClient) _client.close();
  }

  /// Sends one op to the server and returns the `result` payload, throwing a
  /// [RepoException]/[RepoPermissionException] on a reported error and a plain
  /// [RepoException] on any transport/protocol failure.
  Future<Object?> _call(String op, Map<String, Object?> args) async {
    final body = <String, Object?>{'op': op, ...args};
    http.Response resp;
    try {
      resp = await _client.post(
        Uri.parse('$baseUrl/rpc'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
    } catch (e) {
      throw RepoException('Repository server unreachable ($baseUrl): $e');
    }

    if (resp.statusCode != 200) {
      throw RepoException(
        'Repository server error (${resp.statusCode}): ${resp.body}',
      );
    }

    Object? decoded;
    try {
      decoded = jsonDecode(resp.body);
    } catch (e) {
      throw RepoException('Invalid response from repository server: $e');
    }
    final envelope = _asMap(decoded);

    if (envelope['ok'] == true) return envelope['result'];

    final error = envelope['error'];
    if (error is Map) {
      final message = '${error['message'] ?? 'Repository error'}';
      if (error['type'] == 'RepoPermissionException') {
        throw RepoPermissionException(message);
      }
      throw RepoException(message);
    }
    throw RepoException('Repository server returned a malformed error.');
  }

  Future<Map<String, Object?>> _callMap(
    String op,
    Map<String, Object?> args,
  ) async => _asMap(await _call(op, args));

  // --- Filesystem (read) ---

  @override
  Future<RepoFile> read(String path, {LineRange? range}) async {
    final result = await _callMap(Op.read, {
      'path': path,
      'start': ?range?.start,
      'end': ?range?.end,
    });
    return RepoFile.fromJson(result);
  }

  @override
  Future<List<RepoEntry>> list(
    String path, {
    bool recursive = false,
    int? maxDepth,
    String? glob,
  }) async {
    final result = await _callMap(Op.list, {
      'path': path,
      'recursive': recursive,
      'maxDepth': ?maxDepth,
      'glob': ?glob,
    });
    return _list(result['entries']).map(RepoEntry.fromJson).toList();
  }

  @override
  Future<List<String>> find({String? glob, int? limit}) async {
    final result = await _callMap(Op.find, {'glob': ?glob, 'limit': ?limit});
    return (result['paths'] as List?)?.map((e) => '$e').toList() ??
        const <String>[];
  }

  @override
  Future<RepoStat> stat(String path) async =>
      RepoStat.fromJson(await _callMap(Op.stat, {'path': path}));

  // --- Filesystem (write) ---

  @override
  Future<RepoEdit> write(String path, String content) async =>
      RepoEdit.fromJson(
        await _callMap(Op.write, {'path': path, 'content': content}),
      );

  @override
  Future<RepoEdit> edit(
    String path,
    String oldString,
    String newString, {
    bool replaceAll = false,
    int? atLine,
  }) async => RepoEdit.fromJson(
    await _callMap(Op.edit, {
      'path': path,
      'oldString': oldString,
      'newString': newString,
      'replaceAll': replaceAll,
      'atLine': ?atLine,
    }),
  );

  @override
  Future<void> mkdir(String path) => _call(Op.mkdir, {'path': path});

  @override
  Future<void> move(String from, String to) =>
      _call(Op.move, {'from': from, 'to': to});

  @override
  Future<void> delete(String path) => _call(Op.delete, {'path': path});

  // --- Search ---

  @override
  Future<List<TextMatch>> searchText(
    String pattern, {
    String? glob,
    bool ignoreCase = false,
    int context = 0,
    int? limit,
  }) async {
    final result = await _callMap(Op.searchText, {
      'pattern': pattern,
      'glob': ?glob,
      'ignoreCase': ignoreCase,
      'context': context,
      'limit': ?limit,
    });
    return _list(result['matches']).map(TextMatch.fromJson).toList();
  }

  // --- Git (read) ---

  @override
  Future<List<GitStatusEntry>> gitStatus() async {
    final result = await _callMap(Op.gitStatus, const {});
    return _list(result['entries']).map(GitStatusEntry.fromJson).toList();
  }

  @override
  Future<String> gitDiff({
    String? rev,
    bool staged = false,
    String? path,
  }) async {
    final result = await _callMap(Op.gitDiff, {
      'rev': ?rev,
      'staged': staged,
      'path': ?path,
    });
    return '${result['text'] ?? ''}';
  }

  @override
  Future<List<GitCommit>> gitLog({int? limit, String? path}) async {
    final result = await _callMap(Op.gitLog, {'limit': ?limit, 'path': ?path});
    return _list(result['commits']).map(GitCommit.fromJson).toList();
  }

  @override
  Future<String> gitShow({required String rev, String? path}) async {
    final result = await _callMap(Op.gitShow, {'rev': rev, 'path': ?path});
    return '${result['text'] ?? ''}';
  }

  @override
  Future<List<GitBlameLine>> gitBlame(String path) async {
    final result = await _callMap(Op.gitBlame, {'path': path});
    return _list(result['lines']).map(GitBlameLine.fromJson).toList();
  }

  // --- Git (write) ---

  @override
  Future<GitResult> gitAdd(List<String> paths) async =>
      GitResult.fromJson(await _callMap(Op.gitAdd, {'paths': paths}));

  @override
  Future<GitResult> gitCommit(String message, {List<String>? paths}) async =>
      GitResult.fromJson(
        await _callMap(Op.gitCommit, {'message': message, 'paths': ?paths}),
      );

  @override
  Future<GitResult> gitCheckout(String rev) async =>
      GitResult.fromJson(await _callMap(Op.gitCheckout, {'rev': rev}));

  @override
  Future<GitResult> gitRestore(
    List<String> paths, {
    bool staged = false,
  }) async => GitResult.fromJson(
    await _callMap(Op.gitRestore, {'paths': paths, 'staged': staged}),
  );

  // --- helpers ---

  static Map<String, Object?> _asMap(Object? v) {
    if (v is Map<String, Object?>) return v;
    if (v is Map) return v.cast<String, Object?>();
    throw RepoException('Expected a JSON object from the repository server.');
  }

  static List<Map<String, Object?>> _list(Object? v) {
    if (v is! List) return const [];
    return v.map(_asMap).toList();
  }
}

extension _RemoteCaps on RepoCapabilities {
  RepoCapabilities _asRemote() => RepoCapabilities(
    canWrite: canWrite,
    canGitMutate: canGitMutate,
    supportsGit: supportsGit,
    isRemote: true,
  );
}
