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
  'lib/foo.dart':
      'class Greeter {\n'
      '  final String name;\n'
      '  Greeter(this.name);\n'
      '  String greet() => \'Hello, \$name!\';\n'
      '}\n',
  'lib/bar.dart': 'int add(int a, int b) => a + b;\n',
};

void main() {
  group('RepositoryService over LocalRepositoryAdapter (typed, no MCP)', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('apollovm_svc_test_');
      for (final e in _fixture.entries) {
        final f = File('${dir.path}/${e.key}');
        f.parent.createSync(recursive: true);
        f.writeAsStringSync(e.value);
      }
      await _git(dir, ['init']);
      await _git(dir, ['config', 'user.email', 't@t.dev']);
      await _git(dir, ['config', 'user.name', 'Test']);
      await _git(dir, ['add', '.']);
      await _git(dir, ['commit', '-m', 'initial']);
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('typed read/outline/git through the on-disk adapter', () async {
      final repo = RepositoryService(LocalRepositoryAdapter(dir.path));
      addTearDown(repo.close);

      final file = await repo.read('lib/foo.dart', range: LineRange(1, 1));
      expect(file.content, 'class Greeter {');

      final outline = await repo.outline('lib/foo.dart');
      expect(outline.map((s) => s.name), contains('Greeter'));

      final log = await repo.gitLog(limit: 1);
      expect(log.single.subject, 'initial');
    });

    test('path traversal is rejected', () async {
      final repo = RepositoryService(LocalRepositoryAdapter(dir.path));
      addTearDown(repo.close);
      expect(
        () => repo.read('../../etc/passwd'),
        throwsA(isA<RepoException>()),
      );
    });

    test('git mutation gated by RepoConfig.allowGitMutation', () async {
      File('${dir.path}/lib/bar.dart').writeAsStringSync('int add() => 0;\n');

      final readOnly = RepositoryService(LocalRepositoryAdapter(dir.path));
      addTearDown(readOnly.close);
      expect(
        () => readOnly.gitAdd(['lib/bar.dart']),
        throwsA(isA<RepoPermissionException>()),
      );

      final writable = RepositoryService(
        LocalRepositoryAdapter(dir.path),
        config: const RepoConfig(allowGitMutation: true),
      );
      addTearDown(writable.close);
      final r = await writable.gitAdd(['lib/bar.dart']);
      expect(r.ok, isTrue);
    });
  });
}

Future<void> _git(Directory dir, List<String> args) async {
  final r = await Process.run('git', args, workingDirectory: dir.path);
  if (r.exitCode != 0) {
    throw StateError('git ${args.join(' ')} failed: ${r.stderr}');
  }
}
