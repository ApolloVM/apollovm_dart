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

    test(
      'searchSymbols reflects an edit on the same service instance',
      () async {
        final writable = RepositoryService(
          InMemoryRepositoryAdapter(Map.of(_fixture)),
          config: const RepoConfig(allowWrite: true),
        );
        addTearDown(writable.close);

        expect(
          await writable.searchSymbols('Greeter', kind: 'class'),
          isNotEmpty,
        );

        await writable.edit(
          'lib/foo.dart',
          'class Greeter',
          'class Salutation',
        );

        // The long-lived service must see the rename, not a stale buffer.
        expect(await writable.searchSymbols('Greeter', kind: 'class'), isEmpty);
        expect(
          await writable.searchSymbols('Salutation', kind: 'class'),
          isNotEmpty,
        );
      },
    );

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

    test('a non-source file has no inferable language', () async {
      expect(() => repo.outline('notes.txt'), throwsA(isA<RepoException>()));
      expect(
        () => repo.diagnostics('notes.txt'),
        throwsA(isA<RepoException>()),
      );
    });

    test('close is idempotent', () async {
      await repo.close();
      await repo.close();
    });
  });

  group('RepositoryService — language-aware navigation', () {
    // A file with documented, cross-referenced members so hover/definition/
    // references resolve to well-known positions.
    const src =
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

    late RepositoryService repo;
    setUp(
      () => repo = RepositoryService(
        InMemoryRepositoryAdapter({'lib/foo.dart': src}),
      ),
    );
    tearDown(() => repo.close());

    test('diagnostics: clean vs broken source', () async {
      expect(await repo.diagnostics('lib/foo.dart'), isEmpty);

      final broken = RepositoryService(
        InMemoryRepositoryAdapter({
          'lib/bad.dart': 'class Foo {\n  int calc( {\n}\n',
        }),
      );
      addTearDown(broken.close);
      final diags = await broken.diagnostics('lib/bad.dart');
      expect(diags, isNotEmpty);
      expect(diags.map((d) => d.toJson()['severity']), contains(1)); // error
    });

    test('hover returns the signature + doc at the method name', () async {
      final hover = await repo.hover('lib/foo.dart', 2, 13);
      expect(hover, isNotNull);
      final value = (hover!.toJson()['contents'] as Map)['value'] as String;
      expect(value, contains('calc'));
      expect(value, contains('Doubles'));
    });

    test('definition resolves a call to its declaration', () async {
      final def = await repo.definition('lib/foo.dart', 8, 11); // call site
      expect(def, isNotNull);
      final start = ((def!.toJson()['range'] as Map)['start'] as Map)['line'];
      expect(start, 2); // declaration line
    });

    test('references find the declaration and the call site', () async {
      final refs = await repo.references('lib/foo.dart', 2, 13);
      expect(refs, hasLength(2));
    });

    test('outline exposes the class and its methods', () async {
      final outline = await repo.outline('lib/foo.dart');
      final foo = outline.firstWhere((s) => s.name == 'Foo');
      expect(foo.children.map((c) => c.name), containsAll(['calc', 'run']));
    });
  });
}
