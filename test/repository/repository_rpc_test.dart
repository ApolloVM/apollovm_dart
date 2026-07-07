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
