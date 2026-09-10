// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

// The JSON wire contract between a repository server ([RepositoryRpc]) and a
// browser client ([RemoteRepositoryAdapter]). Web-safe: imports only
// `apollovm_repository.dart` (no dart:io), so a leak would fail the Chrome
// compile. The client<->server round-trip is driven through an in-process
// `MockClient` instead of a real socket.
@Tags(['repository'])
library;

import 'dart:convert';

import 'package:apollovm/apollovm_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const _fixture = <String, String>{
  'lib/foo.dart':
      'class Greeter {\n'
      '  final String name;\n'
      '  Greeter(this.name);\n'
      '}\n',
  'lib/bar.dart': 'int add(int a, int b) => a + b;\n',
  'notes.txt': 'Greeter appears here in plain text too\n',
};

/// A [MockClient] whose `POST /rpc` calls are answered by [rpc], so a
/// [RemoteRepositoryAdapter] can be tested without opening a socket.
http.Client _clientFor(RepositoryRpc rpc) => MockClient((request) async {
  if (request.method != 'POST' || !request.url.path.endsWith('/rpc')) {
    return http.Response('not found', 404);
  }
  final body = jsonDecode(request.body) as Map<String, Object?>;
  final envelope = await rpc.handle(body);
  return http.Response(
    jsonEncode(envelope),
    200,
    headers: {'content-type': 'application/json'},
  );
});

/// An in-memory repository that also answers the git ops, so the client half of
/// the git contract can be driven end to end. Everything it returns is fixed:
/// what is under test is the serialization, not a git implementation.
class _GitRepositoryAdapter extends InMemoryRepositoryAdapter {
  _GitRepositoryAdapter(super.files);

  @override
  RepoCapabilities get capabilities =>
      const RepoCapabilities(canWrite: true, canGitMutate: true);

  @override
  Future<List<GitStatusEntry>> gitStatus() async => const [
    GitStatusEntry(path: 'lib/foo.dart', status: 'M ', staged: true),
    GitStatusEntry(path: 'notes.txt', status: '??', staged: false),
  ];

  @override
  Future<String> gitDiff({
    String? rev,
    bool staged = false,
    String? path,
  }) async => 'diff rev=$rev staged=$staged path=$path';

  @override
  Future<List<GitCommit>> gitLog({int? limit, String? path}) async => [
    GitCommit(
      hash: 'abc123',
      author: 'me',
      date: 'today',
      subject: 'limit=$limit path=$path',
    ),
  ];

  @override
  Future<String> gitShow({required String rev, String? path}) async =>
      'show $rev $path';

  @override
  Future<List<GitBlameLine>> gitBlame(String path) async => [
    GitBlameLine(line: 1, hash: 'abc123', author: 'me', content: path),
  ];

  @override
  Future<GitResult> gitAdd(List<String> paths) async =>
      GitResult(ok: true, output: 'add ${paths.join(',')}');

  @override
  Future<GitResult> gitCommit(String message, {List<String>? paths}) async =>
      GitResult(ok: true, output: 'commit $message ${paths?.join(',')}');

  @override
  Future<GitResult> gitCheckout(String rev) async =>
      GitResult(ok: true, output: 'checkout $rev');

  @override
  Future<GitResult> gitRestore(
    List<String> paths, {
    bool staged = false,
  }) async => GitResult(ok: true, output: 'restore ${paths.length} $staged');
}

/// A [MockClient] that answers every `POST /rpc` with [body] and [status],
/// for the client's transport and protocol error paths.
http.Client _cannedClient(String body, {int status = 200}) =>
    MockClient((_) async => http.Response(body, status));

void main() {
  group('RepositoryRpc.handle', () {
    late RepositoryRpc rpc;

    setUp(() {
      rpc = RepositoryRpc(
        RepositoryService(
          InMemoryRepositoryAdapter(Map.of(_fixture)),
          config: const RepoConfig(allowWrite: true),
        ),
      );
    });

    test('read returns a file payload', () async {
      final resp = await rpc.handle({'op': Op.read, 'path': 'lib/bar.dart'});
      expect(resp['ok'], isTrue);
      final result = resp['result'] as Map<String, Object?>;
      expect(result['content'], 'int add(int a, int b) => a + b;\n');
      expect(result['totalLines'], 1);
    });

    test('list returns entries', () async {
      final resp = await rpc.handle({
        'op': Op.list,
        'path': 'lib',
        'recursive': false,
      });
      final entries = (resp['result'] as Map)['entries'] as List;
      expect(
        entries.map((e) => (e as Map)['name']),
        containsAll(['foo.dart', 'bar.dart']),
      );
    });

    test('write then read round-trips content', () async {
      final w = await rpc.handle({
        'op': Op.write,
        'path': 'lib/new.dart',
        'content': 'void main() {}\n',
      });
      expect(w['ok'], isTrue);
      final r = await rpc.handle({'op': Op.read, 'path': 'lib/new.dart'});
      expect((r['result'] as Map)['content'], 'void main() {}\n');
    });

    test('edit replaces a single occurrence', () async {
      final e = await rpc.handle({
        'op': Op.edit,
        'path': 'lib/bar.dart',
        'oldString': 'a + b',
        'newString': 'a - b',
      });
      expect((e['result'] as Map)['replacements'], 1);
    });

    test('searchText finds matches', () async {
      final s = await rpc.handle({'op': Op.searchText, 'pattern': 'Greeter'});
      final matches = (s['result'] as Map)['matches'] as List;
      expect(matches, isNotEmpty);
    });

    test('unknown op is a reported error', () async {
      final resp = await rpc.handle({'op': 'nope'});
      expect(resp['ok'], isFalse);
      expect((resp['error'] as Map)['type'], 'RepoException');
    });

    test('write under a read-only config is a permission error', () async {
      final readOnly = RepositoryRpc(
        RepositoryService(InMemoryRepositoryAdapter(Map.of(_fixture))),
      );
      final resp = await readOnly.handle({
        'op': Op.write,
        'path': 'lib/x.dart',
        'content': 'x',
      });
      expect(resp['ok'], isFalse);
      expect((resp['error'] as Map)['type'], 'RepoPermissionException');
    });
  });

  group('RemoteRepositoryAdapter over the wire', () {
    late RepositoryService remote;

    setUp(() async {
      final rpc = RepositoryRpc(
        RepositoryService(
          InMemoryRepositoryAdapter(Map.of(_fixture)),
          config: const RepoConfig(allowWrite: true),
        ),
      );
      final adapter = await RemoteRepositoryAdapter.connect(
        'http://localhost:9999',
        client: _clientFor(rpc),
      );
      remote = RepositoryService(
        adapter,
        config: const RepoConfig(allowWrite: true),
      );
    });

    test('connect reports remote capabilities', () {
      expect(remote.capabilities.isRemote, isTrue);
      expect(remote.capabilities.canWrite, isTrue);
    });

    test('list + read through the client', () async {
      final entries = await remote.list('lib');
      expect(entries.map((e) => e.name), containsAll(['foo.dart', 'bar.dart']));
      final file = await remote.read('lib/bar.dart');
      expect(file.content, 'int add(int a, int b) => a + b;\n');
    });

    test('write through the client', () async {
      final edit = await remote.write('lib/added.dart', 'void main() {}\n');
      expect(edit.replacements, greaterThanOrEqualTo(0));
      final back = await remote.read('lib/added.dart');
      expect(back.content, 'void main() {}\n');
    });

    test('a permission error propagates as RepoPermissionException', () async {
      final rpc = RepositoryRpc(
        RepositoryService(InMemoryRepositoryAdapter(Map.of(_fixture))),
      );
      final adapter = await RemoteRepositoryAdapter.connect(
        'http://localhost:9999',
        client: _clientFor(rpc),
      );
      final readOnly = RepositoryService(
        adapter,
        config: const RepoConfig(allowWrite: true),
      );
      expect(
        () => readOnly.write('lib/x.dart', 'x'),
        throwsA(isA<RepoPermissionException>()),
      );
    });
  });

  group('RemoteRepositoryAdapter: every filesystem and search op', () {
    late RemoteRepositoryAdapter adapter;

    setUp(() async {
      final rpc = RepositoryRpc(
        RepositoryService(
          InMemoryRepositoryAdapter(Map.of(_fixture)),
          config: const RepoConfig(allowWrite: true),
        ),
      );
      // A trailing slash in the base URL must not double up in `<base>/rpc`.
      adapter = await RemoteRepositoryAdapter.connect(
        'http://localhost:9999/',
        client: _clientFor(rpc),
      );
    });

    test('read with a line range', () async {
      final file = await adapter.read(
        'lib/foo.dart',
        range: const LineRange(1, 2),
      );
      expect(file.path, 'lib/foo.dart');
      expect(file.startLine, 1);
      expect(file.endLine, 2);
    });

    test('list recursively, and find by glob', () async {
      final entries = await adapter.list('', recursive: true, maxDepth: 3);
      expect(entries.map((e) => e.path), contains('lib/foo.dart'));

      final paths = await adapter.find(glob: '**.dart', limit: 10);
      expect(paths, contains('lib/bar.dart'));
    });

    test('stat reports the file', () async {
      final stat = await adapter.stat('lib/bar.dart');
      expect(stat.exists, isTrue);
      expect(stat.isDir, isFalse);
      expect(stat.lineCount, greaterThan(0));
    });

    test('edit replaces text and reports the count', () async {
      final edit = await adapter.edit('lib/bar.dart', 'add', 'sum');
      expect(edit.path, 'lib/bar.dart');
      expect(edit.replacements, 1);
      expect((await adapter.read('lib/bar.dart')).content, contains('sum'));
    });

    test('mkdir, move and delete', () async {
      await adapter.mkdir('lib/sub');
      await adapter.write('lib/sub/a.dart', 'var a = 1;\n');

      await adapter.move('lib/sub/a.dart', 'lib/sub/b.dart');
      expect((await adapter.stat('lib/sub/b.dart')).exists, isTrue);

      await adapter.delete('lib/sub/b.dart');
      expect((await adapter.stat('lib/sub/b.dart')).exists, isFalse);
    });

    test('searchText returns matches with context', () async {
      final matches = await adapter.searchText(
        'Greeter',
        ignoreCase: true,
        context: 1,
        limit: 10,
      );
      expect(matches, isNotEmpty);
      expect(matches.first.text, contains('Greeter'));
    });

    test('close is a no-op for a client it does not own', () {
      expect(adapter.close, returnsNormally);
    });
  });

  group('RemoteRepositoryAdapter: the git ops', () {
    late RemoteRepositoryAdapter adapter;

    setUp(() async {
      final rpc = RepositoryRpc(
        RepositoryService(
          _GitRepositoryAdapter(Map.of(_fixture)),
          config: const RepoConfig(allowWrite: true, allowGitMutation: true),
        ),
      );
      adapter = await RemoteRepositoryAdapter.connect(
        'http://localhost:9999',
        client: _clientFor(rpc),
      );
    });

    test('status, diff, log, show and blame deserialize', () async {
      final status = await adapter.gitStatus();
      expect(status.map((e) => e.path), ['lib/foo.dart', 'notes.txt']);
      expect(status.first.staged, isTrue);

      expect(
        await adapter.gitDiff(rev: 'HEAD', staged: true, path: 'lib'),
        'diff rev=HEAD staged=true path=lib',
      );

      final log = await adapter.gitLog(limit: 5, path: 'lib');
      expect(log.single.hash, 'abc123');
      expect(log.single.subject, 'limit=5 path=lib');

      expect(await adapter.gitShow(rev: 'HEAD', path: 'x'), 'show HEAD x');

      final blame = await adapter.gitBlame('lib/foo.dart');
      expect(blame.single.content, 'lib/foo.dart');
    });

    test('add, commit, checkout and restore deserialize', () async {
      expect((await adapter.gitAdd(['a', 'b'])).output, 'add a,b');
      expect(
        (await adapter.gitCommit('msg', paths: ['a'])).output,
        'commit msg a',
      );
      expect((await adapter.gitCheckout('main')).output, 'checkout main');
      expect(
        (await adapter.gitRestore(['a'], staged: true)).output,
        'restore 1 true',
      );
    });
  });

  group('RemoteRepositoryAdapter: transport and protocol failures', () {
    Future<RemoteRepositoryAdapter> connectWith(http.Client client) =>
        RemoteRepositoryAdapter.connect(
          'http://localhost:9999',
          client: client,
        );

    /// A client that answers the `capabilities` call `connect` makes, then
    /// hands every later call to [next].
    http.Client connectableThen(
      Future<http.Response> Function(http.Request) next,
    ) {
      var first = true;
      return MockClient((request) async {
        if (first) {
          first = false;
          return http.Response(
            jsonEncode({
              'ok': true,
              'result': const RepoCapabilities(canWrite: true).toJson(),
            }),
            200,
          );
        }
        return next(request);
      });
    }

    test('an unreachable server is reported with its URL', () async {
      final adapter = await connectWith(
        connectableThen((_) async => throw Exception('connection refused')),
      );

      await expectLater(
        adapter.stat('a'),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            allOf(contains('unreachable'), contains('http://localhost:9999')),
          ),
        ),
      );
    });

    test('a non-200 response carries the status and the body', () async {
      await expectLater(
        connectWith(_cannedClient('boom', status: 503)),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            allOf(contains('503'), contains('boom')),
          ),
        ),
      );
    });

    test('a body that is not JSON is an invalid response', () async {
      await expectLater(
        connectWith(_cannedClient('<html>nope</html>')),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            contains('Invalid response'),
          ),
        ),
      );
    });

    test('an error envelope becomes the exception it names', () async {
      await expectLater(
        connectWith(
          _cannedClient(
            jsonEncode({
              'ok': false,
              'error': {'type': 'RepoPermissionException', 'message': 'denied'},
            }),
          ),
        ),
        throwsA(isA<RepoPermissionException>()),
      );

      await expectLater(
        connectWith(
          _cannedClient(
            jsonEncode({
              'ok': false,
              'error': {'type': 'RepoException', 'message': 'nope'},
            }),
          ),
        ),
        throwsA(isA<RepoException>()),
      );
    });

    test('a malformed error envelope is still reported', () async {
      await expectLater(
        connectWith(_cannedClient(jsonEncode({'ok': false, 'error': 'oops'}))),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            contains('malformed error'),
          ),
        ),
      );
    });

    test('a result that is not a JSON object is rejected', () async {
      await expectLater(
        connectWith(_cannedClient(jsonEncode({'ok': true, 'result': 42}))),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            contains('Expected a JSON object'),
          ),
        ),
      );
    });
  });

  group('value type fromJson round-trips', () {
    test('every value type survives toJson/fromJson', () {
      const caps = RepoCapabilities(canWrite: true, supportsGit: true);
      expect(RepoCapabilities.fromJson(caps.toJson()).canWrite, isTrue);

      const file = RepoFile(
        path: 'a.dart',
        content: 'x',
        totalLines: 1,
        startLine: 1,
        endLine: 1,
        truncated: true,
      );
      final file2 = RepoFile.fromJson(file.toJson());
      expect(file2.path, 'a.dart');
      expect(file2.startLine, 1);
      expect(file2.truncated, isTrue);

      const entry = RepoEntry(path: 'a', name: 'a', isDir: true, size: 3);
      expect(RepoEntry.fromJson(entry.toJson()).size, 3);

      const stat = RepoStat(
        path: 'a',
        exists: true,
        isDir: false,
        size: 10,
        lineCount: 2,
        modified: '2020-01-01',
      );
      expect(RepoStat.fromJson(stat.toJson()).modified, '2020-01-01');

      const edit = RepoEdit(path: 'a', replacements: 2, appliedAtLine: 5);
      expect(RepoEdit.fromJson(edit.toJson()).appliedAtLine, 5);

      const match = TextMatch(
        path: 'a',
        line: 1,
        column: 2,
        text: 'hi',
        before: ['b'],
        after: ['c'],
      );
      final match2 = TextMatch.fromJson(match.toJson());
      expect(match2.before, ['b']);
      expect(match2.after, ['c']);

      const gitStatus = GitStatusEntry(path: 'a', status: 'M ', staged: true);
      expect(GitStatusEntry.fromJson(gitStatus.toJson()).staged, isTrue);

      const commit = GitCommit(
        hash: 'abc',
        author: 'me',
        date: 'today',
        subject: 'msg',
      );
      expect(GitCommit.fromJson(commit.toJson()).subject, 'msg');

      const blame = GitBlameLine(
        line: 1,
        hash: 'abc',
        author: 'me',
        content: 'x',
      );
      expect(GitBlameLine.fromJson(blame.toJson()).author, 'me');

      const gitResult = GitResult(ok: true, output: 'done');
      expect(GitResult.fromJson(gitResult.toJson()).output, 'done');
    });
  });
}
