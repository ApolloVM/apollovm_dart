// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

@TestOn('vm')
@Tags(['repository'])
library;

import 'dart:io';

import 'package:apollovm/apollovm_repository_io.dart';
import 'package:test/test.dart';

const _fixture = <String, String>{
  'lib/a.dart': 'int a = 1;\n',
  'lib/sub/b.dart': 'int b = 2;\n',
  'lib/sub/deep/c.dart': 'int c = 3;\n',
  'notes.txt': 'alpha\nBETA\ngamma\ndelta\nepsilon\n',
};

void main() {
  _fsContract('InMemoryRepositoryAdapter', () async {
    return InMemoryRepositoryAdapter(Map.of(_fixture));
  });

  Directory? tmp;
  _fsContract('LocalRepositoryAdapter', () async {
    tmp = await Directory.systemTemp.createTemp('apollovm_adapter_');
    _materialize(tmp!, _fixture);
    return LocalRepositoryAdapter(tmp!.path);
  }, tearDown: () => tmp?.deleteSync(recursive: true));

  group('InMemoryRepositoryAdapter — git is unsupported', () {
    late RepositoryAdapter a;
    setUp(() => a = InMemoryRepositoryAdapter(Map.of(_fixture)));
    test('capabilities report no git', () {
      expect(a.capabilities.supportsGit, isFalse);
      expect(a.capabilities.canGitMutate, isFalse);
    });
    test('every git operation throws RepoException', () {
      final err = throwsA(isA<RepoException>());
      expect(a.gitStatus(), err);
      expect(a.gitLog(), err);
      expect(a.gitBlame('lib/a.dart'), err);
      expect(a.gitDiff(), err);
      expect(a.gitShow(rev: 'HEAD'), err);
      expect(a.gitAdd(['lib/a.dart']), err);
      expect(a.gitCommit('m'), err);
      expect(a.gitCheckout('HEAD'), err);
      expect(a.gitRestore(['lib/a.dart']), err);
    });
  });

  group('LocalRepositoryAdapter — error paths & caps', () {
    test('opening a non-existent root throws', () {
      expect(
        () => LocalRepositoryAdapter('/no/such/apollovm/workspace'),
        throwsA(isA<RepoException>()),
      );
    });

    test('the file-size cap bounds reads and writes', () async {
      final dir = await Directory.systemTemp.createTemp('apollovm_cap_');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/big.txt').writeAsStringSync('0123456789');
      final a = LocalRepositoryAdapter(
        dir.path,
        config: const RepoConfig(maxFileBytes: 4),
      );
      expect(a.read('big.txt'), throwsA(isA<RepoException>()));
      expect(a.write('new.txt', '0123456789'), throwsA(isA<RepoException>()));
    });

    test('move/delete of a missing path throw', () async {
      final dir = await Directory.systemTemp.createTemp('apollovm_missing_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final a = LocalRepositoryAdapter(dir.path);
      expect(a.move('ghost', 'x'), throwsA(isA<RepoException>()));
      expect(a.delete('ghost'), throwsA(isA<RepoException>()));
    });

    test('list honors maxDepth', () async {
      final dir = await Directory.systemTemp.createTemp('apollovm_depth_');
      addTearDown(() => dir.deleteSync(recursive: true));
      _materialize(dir, _fixture);
      final a = LocalRepositoryAdapter(dir.path);
      final shallow = await a.list('', recursive: true, maxDepth: 1);
      // lib/sub/deep/c.dart (depth 4) must be excluded at maxDepth 1.
      expect(shallow.any((e) => e.path == 'lib/sub/deep/c.dart'), isFalse);
    });
  });

  group('LocalRepositoryAdapter — git read/write + ignores', () {
    late Directory dir;
    late LocalRepositoryAdapter a;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('apollovm_git_adapter_');
      _materialize(dir, _fixture);
      await _git(dir, ['init']);
      await _git(dir, ['config', 'user.email', 't@t.dev']);
      await _git(dir, ['config', 'user.name', 'Test']);
      await _git(dir, ['add', '.']);
      await _git(dir, ['commit', '-m', 'initial']);
      a = LocalRepositoryAdapter(dir.path);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('capabilities detect the git working tree', () {
      expect(a.capabilities.supportsGit, isTrue);
      expect(a.capabilities.canGitMutate, isTrue);
    });

    test('.git is excluded from find/list', () async {
      final found = await a.find();
      expect(found.any((p) => p.startsWith('.git/')), isFalse);
      expect(found, contains('lib/a.dart'));
    });

    test('diff of the working tree and of a path', () async {
      File('${dir.path}/lib/a.dart').writeAsStringSync('int a = 42;\n');
      final all = await a.gitDiff();
      expect(all, contains('int a = 42;'));
      final scoped = await a.gitDiff(path: 'notes.txt');
      expect(scoped, isEmpty); // notes.txt unchanged
    });

    test('show a file at HEAD, and staged diff', () async {
      final shown = await a.gitShow(rev: 'HEAD', path: 'lib/a.dart');
      expect(shown, contains('int a = 1;'));

      File('${dir.path}/lib/a.dart').writeAsStringSync('int a = 9;\n');
      await a.gitAdd(['lib/a.dart']);
      final staged = await a.gitDiff(staged: true);
      expect(staged, contains('int a = 9;'));
    });

    test('commit, checkout and restore round-trip', () async {
      File('${dir.path}/lib/a.dart').writeAsStringSync('int a = 7;\n');
      final commit = await a.gitCommit('change a', paths: ['lib/a.dart']);
      expect(commit.ok, isTrue);
      expect((await a.gitLog(limit: 1)).single.subject, 'change a');

      // Modify then restore from the index/HEAD.
      File('${dir.path}/lib/a.dart').writeAsStringSync('int a = 999;\n');
      final restore = await a.gitRestore(['lib/a.dart']);
      expect(restore.ok, isTrue);
      expect(File('${dir.path}/lib/a.dart').readAsStringSync(), 'int a = 7;\n');

      final checkout = await a.gitCheckout('HEAD');
      expect(checkout.ok, isTrue);
    });

    test('a git failure surfaces as RepoException', () {
      expect(a.gitShow(rev: 'no-such-rev'), throwsA(isA<RepoException>()));
    });
  });
}

/// The backend-agnostic filesystem/search contract.
void _fsContract(
  String label,
  Future<RepositoryAdapter> Function() make, {
  void Function()? tearDown,
}) {
  group('adapter fs/search contract — $label', () {
    late RepositoryAdapter a;
    setUp(() async => a = await make());
    if (tearDown != null) tearDownAll(tearDown);

    test('read to end-of-file with an open-ended range', () async {
      final f = await a.read('notes.txt', range: const LineRange(4));
      expect(f.content, 'delta\nepsilon');
      expect(f.startLine, 4);
      expect(f.endLine, 5);
      expect(f.totalLines, 5);
      expect(f.toJson()['path'], 'notes.txt');
    });

    test('list is non-recursive by default and surfaces subdirs', () async {
      final top = await a.list('');
      final names = top.map((e) => e.name).toSet();
      expect(names, contains('notes.txt'));
      expect(names, contains('lib'));
      expect(top.firstWhere((e) => e.name == 'lib').isDir, isTrue);
      // Nested files are not surfaced without recursion.
      expect(top.any((e) => e.path == 'lib/a.dart'), isFalse);
    });

    test('list recursive with a glob filter', () async {
      final all = await a.list('', recursive: true, glob: 'lib/**/*.dart');
      final files = all.where((e) => !e.isDir).map((e) => e.path).toSet();
      expect(
        files,
        containsAll(['lib/a.dart', 'lib/sub/b.dart', 'lib/sub/deep/c.dart']),
      );
    });

    test('find respects a limit', () async {
      final two = await a.find(glob: '**/*.dart', limit: 2);
      expect(two, hasLength(2));
    });

    test('stat on a file, a directory, and a missing path', () async {
      final file = await a.stat('lib/a.dart');
      expect(file.exists, isTrue);
      expect(file.isDir, isFalse);
      expect(file.lineCount, 1);

      final dir = await a.stat('lib');
      expect(dir.exists, isTrue);
      expect(dir.isDir, isTrue);

      final missing = await a.stat('nope.dart');
      expect(missing.exists, isFalse);
    });

    test('searchText: case-insensitive with context lines', () async {
      final hits = await a.searchText(
        'beta',
        glob: 'notes.txt',
        ignoreCase: true,
        context: 1,
      );
      expect(hits, hasLength(1));
      final m = hits.single;
      expect(m.line, 2);
      expect(m.text, 'BETA');
      expect(m.before, ['alpha']);
      expect(m.after, ['gamma']);
      expect(m.toJson()['before'], ['alpha']);
    });

    test('searchText honors a limit across files', () async {
      final capped = await a.searchText('int', glob: 'lib/**', limit: 2);
      expect(capped, hasLength(2));
    });

    test('write then edit (replaceAll) then read back', () async {
      await a.write('gen.txt', 'x x x\n');
      final edit = await a.edit('gen.txt', 'x', 'y', replaceAll: true);
      expect(edit.replacements, 3);
      expect((await a.read('gen.txt')).content, 'y y y\n');
    });

    test('move a file and move a directory', () async {
      await a.move('notes.txt', 'renamed.txt');
      expect((await a.stat('notes.txt')).exists, isFalse);
      expect((await a.stat('renamed.txt')).exists, isTrue);

      await a.move('lib/sub', 'lib/moved');
      expect((await a.read('lib/moved/b.dart')).content, 'int b = 2;\n');
    });

    test('delete a file and delete a directory tree', () async {
      await a.delete('notes.txt');
      expect((await a.stat('notes.txt')).exists, isFalse);

      await a.delete('lib/sub');
      expect((await a.stat('lib/sub/b.dart')).exists, isFalse);
      expect((await a.stat('lib/a.dart')).exists, isTrue);
    });

    test('reading a missing file throws', () {
      expect(a.read('ghost.dart'), throwsA(isA<RepoException>()));
    });
  });
}

void _materialize(Directory root, Map<String, String> files) {
  for (final e in files.entries) {
    final f = File('${root.path}/${e.key}');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(e.value);
  }
}

Future<void> _git(Directory dir, List<String> args) async {
  final r = await Process.run('git', args, workingDirectory: dir.path);
  if (r.exitCode != 0) {
    throw StateError('git ${args.join(' ')} failed: ${r.stderr}');
  }
}
