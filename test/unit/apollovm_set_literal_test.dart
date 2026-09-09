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
