// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

@TestOn('vm')
@Tags(['mcp'])
library;

import 'dart:io';

import 'package:apollovm/apollovm_mcp_io.dart';
import 'package:test/test.dart';

/// The fixture workspace shared by both adapters, so the contract tests prove
/// the tools are backend-agnostic.
const _fixture = <String, String>{
  'lib/foo.dart': '''
class Greeter {
  final String name;
  Greeter(this.name);
  // A mention of Greeter in a comment — must NOT match search.symbols.
  String greet() => 'Hello, \$name!';
}
''',
  'lib/bar.dart': 'int add(int a, int b) => a + b;\n',
  'notes.txt': 'hello world\nfoo bar\nGreeter appears here too\n',
};

RepoRuntime _runtime(RepositoryAdapter adapter, {RepoConfig? config}) =>
    RepoRuntime(PermissionGuard(adapter, config: config ?? const RepoConfig()));

void main() {
  group('repo tools — registration', () {
    test('all repo tools are advertised and built', () {
      final built = buildRepoTools().map((t) => t.name).toSet();
      expect(built, equals(repoToolNames.toSet()));
      for (final n in repoToolNames) {
        expect(isRepoTool(n), isTrue, reason: n);
      }
      expect(isRepoTool('apollovm.parse'), isFalse);
      expect(repoToolNames, contains('apollovm.fs.read'));
      expect(repoToolNames, contains('apollovm.search.symbols'));
      expect(repoToolNames, contains('apollovm.code.outline'));
      expect(repoToolNames, contains('apollovm.git.status'));
    });
  });

  // The shared filesystem/search/code contract, run against each backend.
  _contractTests('InMemoryRepositoryAdapter', () async {
    return InMemoryRepositoryAdapter(Map.of(_fixture));
  });

  Directory? tmp;
  _contractTests('LocalRepositoryAdapter', () async {
    tmp = await Directory.systemTemp.createTemp('apollovm_repo_test_');
    for (final e in _fixture.entries) {
      final f = File('${tmp!.path}/${e.key}');
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(e.value);
    }
    return LocalRepositoryAdapter(tmp!.path);
  }, tearDown: () => tmp?.deleteSync(recursive: true));

  group('git tools (LocalRepositoryAdapter)', () {
    late Directory dir;
    late RepositoryAdapter adapter;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('apollovm_git_test_');
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
      adapter = LocalRepositoryAdapter(dir.path);
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('git.status reports a modified file', () async {
      File('${dir.path}/lib/bar.dart').writeAsStringSync('int add() => 0;\n');
      final r = await _runtime(adapter).call('apollovm.git.status', {});
      expect(r['isError'], isFalse);
      final entries = (r['entries'] as List).cast<Map>();
      expect(entries.any((e) => e['path'] == 'lib/bar.dart'), isTrue);
    });

    test('git.log returns the initial commit', () async {
      final r = await _runtime(adapter).call('apollovm.git.log', {'limit': 5});
      expect(r['isError'], isFalse);
      final commits = (r['commits'] as List).cast<Map>();
      expect(commits, isNotEmpty);
      expect(commits.first['subject'], 'initial');
      expect(commits.first['author'], 'Test');
    });

    test('git.blame attributes lines', () async {
      final r = await _runtime(
        adapter,
      ).call('apollovm.git.blame', {'path': 'lib/bar.dart'});
      expect(r['isError'], isFalse);
      final lines = (r['lines'] as List).cast<Map>();
      expect(lines, isNotEmpty);
      expect(lines.first['author'], 'Test');
    });

    test('git mutation is blocked read-only, allowed when permitted', () async {
      File('${dir.path}/lib/bar.dart').writeAsStringSync('int add() => 0;\n');

      final blocked = await _runtime(adapter).call('apollovm.git.add', {
        'paths': ['lib/bar.dart'],
      });
      expect(blocked['isError'], isTrue);

      final allowed =
          await _runtime(
            adapter,
            config: const RepoConfig(allowGitMutation: true),
          ).call('apollovm.git.add', {
            'paths': ['lib/bar.dart'],
          });
      expect(allowed['isError'], isFalse);
    });
  });

  // The MCP JSON layer for the tools not exercised above: fs mutation, all
  // language-aware code.* navigation, the remaining git.* verbs, and the
  // unknown-tool path — driven over a real git fixture.
  group('MCP layer (RepoRuntime) — remaining tools', () {
    const calc =
        'class Foo {\n'
        '  /// Doubles [x] and adds [y].\n'
        '  static int calc(int x, int y) {\n'
        '    var doubled = x * 2;\n'
        '    return doubled + y;\n'
        '  }\n'
        '\n'
        '  static int run() {\n'
        '    return calc(10, 5);\n'
        '  }\n'
        '}\n';

    late Directory dir;
    late RepositoryAdapter adapter;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('apollovm_mcp_rest_');
      for (final e in {..._fixture, 'lib/calc.dart': calc}.entries) {
        final f = File('${dir.path}/${e.key}');
        f.parent.createSync(recursive: true);
        f.writeAsStringSync(e.value);
      }
      await _git(dir, ['init']);
      await _git(dir, ['config', 'user.email', 't@t.dev']);
      await _git(dir, ['config', 'user.name', 'Test']);
      await _git(dir, ['add', '.']);
      await _git(dir, ['commit', '-m', 'initial']);
      adapter = LocalRepositoryAdapter(dir.path);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    RepoRuntime rw() => _runtime(
      adapter,
      config: const RepoConfig(allowWrite: true, allowGitMutation: true),
    );

    test('fs.list returns directory entries', () async {
      final r = await _runtime(
        adapter,
      ).call('apollovm.fs.list', {'path': 'lib'});
      expect(r['isError'], isFalse);
      final names = (r['entries'] as List).map((e) => (e as Map)['name']);
      expect(names, contains('calc.dart'));
    });

    test('fs.mkdir / move / delete', () async {
      expect(
        (await rw().call('apollovm.fs.mkdir', {'path': 'newdir'}))['ok'],
        isTrue,
      );
      await rw().call('apollovm.fs.write', {
        'path': 'newdir/f.txt',
        'content': 'hi',
      });
      expect(
        (await rw().call('apollovm.fs.move', {
          'from': 'newdir/f.txt',
          'to': 'newdir/g.txt',
        }))['ok'],
        isTrue,
      );
      expect(
        (await rw().call('apollovm.fs.delete', {'path': 'newdir'}))['ok'],
        isTrue,
      );
    });

    test('code.diagnostics / definition / hover / references', () async {
      final diag = await _runtime(
        adapter,
      ).call('apollovm.code.diagnostics', {'path': 'lib/calc.dart'});
      expect(diag['isError'], isFalse);
      expect(diag['ok'], isTrue);

      final def = await _runtime(adapter).call('apollovm.code.definition', {
        'path': 'lib/calc.dart',
        'line': 8,
        'character': 11,
      });
      expect(((def['definition'] as Map)['range'] as Map)['start'], isA<Map>());

      final hover = await _runtime(adapter).call('apollovm.code.hover', {
        'path': 'lib/calc.dart',
        'line': 2,
        'character': 13,
      });
      expect(hover['hover'], isNotNull);

      final refs = await _runtime(adapter).call('apollovm.code.references', {
        'path': 'lib/calc.dart',
        'line': 2,
        'character': 13,
      });
      expect((refs['references'] as List), hasLength(2));
    });

    test('code.workspaceSymbols auto-loads the repo', () async {
      final r = await _runtime(
        adapter,
      ).call('apollovm.code.workspaceSymbols', {'query': 'Foo'});
      expect(r['isError'], isFalse);
      expect(
        (r['symbols'] as List).map((s) => (s as Map)['name']),
        contains('Foo'),
      );
    });

    test('git.diff / show', () async {
      File('${dir.path}/lib/bar.dart').writeAsStringSync('int add() => 0;\n');
      final diff = await _runtime(adapter).call('apollovm.git.diff', {});
      expect(diff['diff'], contains('int add() => 0;'));

      final show = await _runtime(
        adapter,
      ).call('apollovm.git.show', {'rev': 'HEAD', 'path': 'lib/calc.dart'});
      expect(show['content'], contains('static int calc'));
    });

    test('git.commit / checkout / restore', () async {
      File('${dir.path}/lib/bar.dart').writeAsStringSync('int add() => 1;\n');
      final commit = await rw().call('apollovm.git.commit', {
        'message': 'tweak',
        'paths': ['lib/bar.dart'],
      });
      expect(commit['isError'], isFalse);

      File('${dir.path}/lib/bar.dart').writeAsStringSync('int add() => 2;\n');
      final restore = await rw().call('apollovm.git.restore', {
        'paths': ['lib/bar.dart'],
      });
      expect(restore['isError'], isFalse);

      final checkout = await rw().call('apollovm.git.checkout', {
        'rev': 'HEAD',
      });
      expect(checkout['isError'], isFalse);
    });

    test('an unknown repository tool is an error', () async {
      final r = await _runtime(adapter).call('apollovm.fs.bogus', {});
      expect(r['isError'], isTrue);
    });
  });
}

/// The filesystem/search/code tests, parameterized over an adapter [make]r.
void _contractTests(
  String label,
  Future<RepositoryAdapter> Function() make, {
  void Function()? tearDown,
}) {
  group('repo tools contract — $label', () {
    late RepositoryAdapter adapter;

    setUp(() async => adapter = await make());
    if (tearDown != null) tearDownAll(tearDown);

    test('fs.read returns a line range and the total line count', () async {
      final r = await _runtime(adapter).call('apollovm.fs.read', {
        'path': 'lib/foo.dart',
        'startLine': 1,
        'endLine': 1,
      });
      expect(r['isError'], isFalse);
      expect(r['content'], 'class Greeter {');
      expect(r['totalLines'], greaterThan(3));
    });

    test('fs.find matches a glob', () async {
      final r = await _runtime(
        adapter,
      ).call('apollovm.fs.find', {'glob': 'lib/**/*.dart'});
      final paths = (r['paths'] as List).cast<String>();
      expect(paths, containsAll(['lib/bar.dart', 'lib/foo.dart']));
      expect(paths, isNot(contains('notes.txt')));
    });

    test('fs.stat reports metadata', () async {
      final r = await _runtime(
        adapter,
      ).call('apollovm.fs.stat', {'path': 'lib/bar.dart'});
      expect(r['exists'], isTrue);
      expect(r['isDir'], isFalse);
      expect(r['lineCount'], 1);
    });

    test('path traversal is rejected', () async {
      final r = await _runtime(
        adapter,
      ).call('apollovm.fs.read', {'path': '../../etc/passwd'});
      expect(r['isError'], isTrue);
    });

    test('search.text finds content hits with file:line', () async {
      final r = await _runtime(
        adapter,
      ).call('apollovm.search.text', {'pattern': 'Greeter', 'glob': 'lib/**'});
      final matches = (r['matches'] as List).cast<Map>();
      // The class line AND the comment line both match a raw text search.
      expect(matches.length, greaterThanOrEqualTo(2));
      expect(matches.first['path'], 'lib/foo.dart');
      expect(matches.first['line'], 1);
    });

    test('search.symbols is language-aware: only the declaration', () async {
      final r = await _runtime(
        adapter,
      ).call('apollovm.search.symbols', {'query': 'Greeter', 'kind': 'class'});
      expect(r['isError'], isFalse);
      final symbols = (r['symbols'] as List).cast<Map>();
      // The class declaration is found; the comment mention in foo.dart and the
      // text in notes.txt are NOT (they are not symbols).
      expect(symbols, isNotEmpty);
      expect(symbols.every((s) => s['kind'] == 5), isTrue);
      expect(symbols.any((s) => s['name'] == 'Greeter'), isTrue);
    });

    test('code.outline lists the class (language-aware)', () async {
      final r = await _runtime(
        adapter,
      ).call('apollovm.code.outline', {'path': 'lib/foo.dart'});
      expect(r['isError'], isFalse);
      final names = (r['symbols'] as List)
          .cast<Map>()
          .map((s) => s['name'])
          .toList();
      expect(names, contains('Greeter'));
    });

    test('writes are blocked read-only, allowed when permitted', () async {
      final blocked = await _runtime(
        adapter,
      ).call('apollovm.fs.write', {'path': 'new.txt', 'content': 'hi'});
      expect(blocked['isError'], isTrue);

      final ok = await _runtime(
        adapter,
        config: const RepoConfig(allowWrite: true),
      ).call('apollovm.fs.write', {'path': 'new.txt', 'content': 'hi'});
      expect(ok['isError'], isFalse);
    });

    test('fs.edit honors the atLine anchor', () async {
      const writable = RepoConfig(allowWrite: true);

      // Correct anchor applies.
      final good = await _runtime(adapter, config: writable).call(
        'apollovm.fs.edit',
        {
          'path': 'lib/bar.dart',
          'oldString': 'add',
          'newString': 'sum',
          'atLine': 1,
        },
      );
      expect(good['isError'], isFalse);
      expect(good['appliedAtLine'], 1);

      // Wrong anchor is refused.
      final bad = await _runtime(adapter, config: writable).call(
        'apollovm.fs.edit',
        {
          'path': 'lib/bar.dart',
          'oldString': 'sum',
          'newString': 'x',
          'atLine': 99,
        },
      );
      expect(bad['isError'], isTrue);

      // requireLineMatch forbids an edit with no atLine.
      final noAnchor =
          await _runtime(
            adapter,
            config: const RepoConfig(allowWrite: true, requireLineMatch: true),
          ).call('apollovm.fs.edit', {
            'path': 'lib/bar.dart',
            'oldString': 'sum',
            'newString': 'x',
          });
      expect(noAnchor['isError'], isTrue);
    });
  });
}

Future<void> _git(Directory dir, List<String> args) async {
  final r = await Process.run('git', args, workingDirectory: dir.path);
  if (r.exitCode != 0) {
    throw StateError('git ${args.join(' ')} failed: ${r.stderr}');
  }
}
