@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Set literals (Dart 2.2): the behaviour the XML corpus can't express —
/// what each target language a set is *translated* to looks like, and the
/// disambiguation from map literals.

Future<ApolloVM> _load(String src) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', src, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source");
  return vm;
}

Future<Object?> _run(String src) async {
  var vm = await _load(src);
  var res = await vm.createRunner('dart')!.executeFunction('', 'run');
  return res.getValueNoContext();
}

Future<String> _generate(String src, String language) async {
  var vm = await _load(src);
  return (await vm.generateAllCodeIn(language).writeAllSources()).toString();
}

void main() {
  group('Set literal semantics', () {
    test('duplicated elements collapse, keeping the first', () async {
      expect(
        await _run('int run() { var s = {1, 2, 2, 1, 3}; return s.length; }'),
        equals(3),
      );
    });

    test('add / remove / contains', () async {
      expect(
        await _run(
          'int run() { var s = {1}; s.add(2); s.add(1); s.remove(1); '
          'return s.length; }',
        ),
        equals(1),
      );
      expect(
        await _run("bool run() { var s = {'a'}; return s.contains('a'); }"),
        isTrue,
      );
    });

    test('for-in iterates the elements', () async {
      expect(
        await _run(
          'int run() { var t = 0; for (var e in {1, 2, 3}) { t = t + e; } '
          'return t; }',
        ),
        equals(6),
      );
    });

    test('an element type is inferred from the elements', () async {
      var vm = await _load('Set<int> run() { return {1, 2}; }');
      var value = await vm.createRunner('dart')!.executeFunction('', 'run');
      expect(await value.resolveType(null), isA<ASTTypeSet>());
    });

    test('a set built from variables infers its type at run time', () async {
      // The elements have no statically resolvable type here, so the literal
      // carries no type and resolves one when it runs.
      expect(
        await _run(
          'int run() { var a = 1; var b = 2; Set<int> s = {a, b, a}; '
          'return s.length; }',
        ),
        equals(2),
      );
    });
  });

  group('Core `Set` members', () {
    test('length / isEmpty / isNotEmpty, as getters and as calls', () async {
      expect(
        await _run('int run() { var s = {1, 2}; return s.length; }'),
        equals(2),
      );
      expect(
        await _run('bool run() { var s = {1}; return s.isEmpty; }'),
        isFalse,
      );
      expect(
        await _run('bool run() { var s = {1}; return s.isNotEmpty; }'),
        isTrue,
      );

      // Java-style call forms of the same three members.
      expect(
        await _run('int run() { var s = {1, 2}; return s.length(); }'),
        equals(2),
      );
      expect(
        await _run('bool run() { var s = {1}; return s.isEmpty(); }'),
        isFalse,
      );
      expect(
        await _run('bool run() { var s = {1}; return s.isNotEmpty(); }'),
        isTrue,
      );
    });

    test('first / last keep the element type', () async {
      expect(
        await _run("String run() { var s = {'a', 'b'}; return s.first; }"),
        equals('a'),
      );
      expect(
        await _run("String run() { var s = {'a', 'b'}; return s.last; }"),
        equals('b'),
      );
    });

    test('addAll and clear', () async {
      expect(
        await _run(
          'int run() { var s = {1}; s.addAll([2, 3, 1]); return s.length; }',
        ),
        equals(3),
      );
      expect(
        await _run('int run() { var s = {1, 2}; s.clear(); return s.length; }'),
        equals(0),
      );
    });

    test('toList and toString', () async {
      expect(
        await _run(
          'int run() { var s = {3, 1}; var l = s.toList(); '
          'return l[0]; }',
        ),
        equals(3),
      );
      expect(
        await _run("String run() { var s = {1, 2}; return s.toString(); }"),
        equals('{1, 2}'),
      );
    });

    test('an unknown member is reported, not silently ignored', () async {
      var vm = await _load('int run() { var s = {1}; return s.nope; }');
      await expectLater(
        vm.createRunner('dart')!.executeFunction('', 'run'),
        throwsA(anything),
      );
    });
  });

  group('Set / map literal disambiguation', () {
    test('`{}` is still an empty map, and `<T>{}` an empty set', () async {
      expect(
        await _run('int run() { var m = {}; return m.length; }'),
        equals(0),
      );
      expect(
        await _run("int run() { var m = {'a': 1}; return m['a']; }"),
        equals(1),
      );
      expect(
        await _run('int run() { var s = <int>{}; s.add(1); return s.length; }'),
        equals(1),
      );
    });

    test('a set survives a Dart round-trip', () async {
      var code = await _generate(
        'int run() { var s = {1, 2}; return s.length; }',
        'dart',
      );
      expect(code, contains('<int>{1, 2}'));

      var source = code
          .split('\n')
          .where((l) => !l.startsWith('<<<<'))
          .join('\n');
      expect(
        await _run(source.replaceAll('  int run()', 'int run()')),
        equals(2),
      );
    });
  });

  group('ASTExpressionSetLiteral node', () {
    ASTExpression lit(Object v) => ASTExpressionLiteral(ASTValue.fromValue(v));

    test(
      'an untyped literal infers its element type from the elements',
      () async {
        var node = ASTExpressionSetLiteral(null, [lit(1), lit(2)]);

        var type = await node.resolveType(null);
        expect(type, isA<ASTTypeSet>());
        expect((type as ASTTypeSet).elementType, isA<ASTTypeInt>());
      },
    );

    test('a declared element type is kept', () async {
      var node = ASTExpressionSetLiteral(ASTTypeString.instance, [lit('a')]);

      var type = await node.resolveType(null);
      expect((type as ASTTypeSet).elementType, same(ASTTypeString.instance));
    });

    test('running it de-duplicates and keeps the first occurrence', () async {
      var node = ASTExpressionSetLiteral(null, [lit(1), lit(2), lit(1)]);
      var context = VMScopeContext(ASTBlock(null));

      var value = await node.run(context, ASTRunStatus());
      expect(await value.getValue(context), equals({1, 2}));
    });

    test(
      'an empty literal runs to an empty set of its declared type',
      () async {
        var node = ASTExpressionSetLiteral(ASTTypeInt.instance, []);
        var context = VMScopeContext(ASTBlock(null));

        var value = await node.run(context, ASTRunStatus());
        expect(await value.getValue(context), isEmpty);
        expect((value.type as ASTTypeSet).elementType, isA<ASTTypeInt>());
      },
    );

    test('it is a simple expression that prints its elements', () {
      var node = ASTExpressionSetLiteral(null, [lit(1), lit(2)]);
      expect(node.isComplex, isFalse);
      // The elements print with their AST value form (`(int) 1`).
      expect(node.toString(), startsWith('{'));
      expect(node.toString(), contains('1'));
      expect(node.toString(), endsWith('}'));
      expect(node.children, hasLength(2));
    });

    test(
      'hashcode value and identifier lookup delegate to the elements',
      () async {
        var node = ASTExpressionSetLiteral(null, [lit(1), lit(2)]);
        expect(await node.getHashcodeValue(null), hasLength(2));
        // No parent node, so nothing resolves through it.
        expect(node.getNodeIdentifier('x'), isNull);
      },
    );
  });

  group('Set literal translation', () {
    // In a class: Java and C# have no top-level functions.
    const src =
        'class C { static Object run() { var s = {1, 2}; '
        'var e = <String>{}; return s; } }';

    test('Java builds a HashSet', () async {
      var code = await _generate(src, 'java11');
      expect(code, contains('new HashSet<int>(){{'));
      expect(code, contains('add(1);'));
    });

    test('Kotlin uses mutableSetOf, with the element type', () async {
      var code = await _generate(src, 'kotlin');
      expect(code, contains('mutableSetOf<Int>(1, 2)'));
      // Kotlin can't infer the element type of an empty set.
      expect(code, contains('mutableSetOf<String>()'));
    });

    test('C# builds a HashSet', () async {
      expect(
        await _generate(src, 'csharp'),
        contains('new HashSet<int>(){1, 2}'),
      );
    });

    test('TypeScript / JavaScript build a Set from the elements', () async {
      expect(
        await _generate(src, 'typescript'),
        contains('new Set<number>([1, 2])'),
      );
      expect(await _generate(src, 'javascript'), contains('new Set([1, 2])'));
    });

    test('Python writes `{…}`, and `set()` when empty', () async {
      var code = await _generate(src, 'python');
      expect(code, contains('{1, 2}'));
      expect(code, contains('set()'));
    });

    test('Go uses the map-to-empty-struct idiom, type included', () async {
      var code = await _generate(
        'class C { static Object run() { Set<int> s = {1, 2}; return s; } }',
        'go',
      );
      expect(code, contains('map[int]struct{}{1: {}, 2: {}}'));
      expect(code, contains('var s map[int]struct{}'));
    });

    test('Lua uses a table as a lookup', () async {
      expect(
        await _generate(src, 'lua'),
        contains('{ [1] = true, [2] = true }'),
      );
    });

    test(
      'Wasm refuses a set literal instead of lowering it to a list',
      () async {
        var vm = await _load(
          'class C { static int run() { var s = {1, 2}; return s.length; } }',
        );
        expect(
          () => vm.generateAllIn<BytesOutput>('wasm').allEntries(),
          throwsA(isA<UnsupportedSyntaxError>()),
        );
      },
    );
  });
}
