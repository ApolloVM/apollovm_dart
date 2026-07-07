// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

// Cross-platform (VM + browser): the repository features are a standalone,
// web-safe library — no MCP, no dart:io. This test imports ONLY
// `apollovm_repository.dart`; a dart:io leak would fail the Chrome compile.
@Tags(['repository'])
library;

import 'package:apollovm/apollovm_repository.dart';
import 'package:test/test.dart';

const _fixture = <String, String>{
  'lib/foo.dart':
      'class Greeter {\n'
      '  final String name;\n'
      '  Greeter(this.name);\n'
      '  String greet() => \'Hello, \$name!\';\n'
      '}\n',
  'lib/bar.dart': 'int add(int a, int b) => a + b;\n',
  'notes.txt': 'Greeter appears here in plain text too\n',
};

void main() {
  group('RepositoryService (standalone, web-safe)', () {
    late RepositoryService repo;

    setUp(
      () =>
          repo = RepositoryService(InMemoryRepositoryAdapter(Map.of(_fixture))),
    );
    tearDown(() => repo.close());

    test('typed filesystem read', () async {
      final file = await repo.read('lib/bar.dart');
      expect(file, isA<RepoFile>());
      expect(file.content, 'int add(int a, int b) => a + b;\n');
      expect(file.totalLines, 1);
    });

    test('typed find + stat', () async {
      expect(await repo.find(glob: 'lib/**/*.dart'), hasLength(2));
      final stat = await repo.stat('lib/foo.dart');
      expect(stat.exists, isTrue);
      expect(stat.isDir, isFalse);
    });

    test('typed searchText returns TextMatch objects', () async {
      final hits = await repo.searchText('Greeter', glob: 'lib/**');
      expect(hits, isNotEmpty);
      expect(hits.first, isA<TextMatch>());
      expect(hits.first.path, 'lib/foo.dart');
      expect(hits.first.line, 1);
    });

    test('language-aware outline returns DocumentSymbols', () async {
      final symbols = await repo.outline('lib/foo.dart');
      expect(symbols.map((s) => s.name), contains('Greeter'));
    });

    test(
      'language-aware searchSymbols filters by kind (not comments/text)',
      () async {
        final classes = await repo.searchSymbols('Greeter', kind: 'class');
        expect(classes, isNotEmpty);
        expect(
          classes.every((s) => s.kind == 5),
          isTrue,
        ); // SymbolKind.class == 5
        expect(classes.any((s) => s.name == 'Greeter'), isTrue);

        // Filtering by an unrelated kind excludes the class.
        final methods = await repo.searchSymbols('Greeter', kind: 'method');
        expect(methods.any((s) => s.name == 'Greeter' && s.kind == 5), isFalse);
      },
    );

    test('searchSymbols reflects an edit on the same service instance', () async {
      final writable = RepositoryService(
        InMemoryRepositoryAdapter(Map.of(_fixture)),
        config: const RepoConfig(allowWrite: true),
      );
      addTearDown(writable.close);

      expect(await writable.searchSymbols('Greeter', kind: 'class'), isNotEmpty);

      await writable.edit('lib/foo.dart', 'class Greeter', 'class Salutation');

      // The long-lived service must see the rename, not a stale buffer.
      expect(await writable.searchSymbols('Greeter', kind: 'class'), isEmpty);
      expect(
        await writable.searchSymbols('Salutation', kind: 'class'),
        isNotEmpty,
      );
    });

    test('writes are read-only by default, allowed via RepoConfig', () async {
      expect(repo.capabilities.canWrite, isFalse);
      expect(
        () => repo.write('x.txt', 'hi'),
        throwsA(isA<RepoPermissionException>()),
      );

      final writable = RepositoryService(
        InMemoryRepositoryAdapter(Map.of(_fixture)),
        config: const RepoConfig(allowWrite: true),
      );
      expect(writable.capabilities.canWrite, isTrue);
      final edit = await writable.write('x.txt', 'hi');
      expect(edit.path, 'x.txt');
      await writable.close();
    });
  });
}
