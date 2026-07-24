@TestOn('vm')
@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Every source language ApolloVM can both parse and generate.
const _languages = [
  'dart',
  'java11',
  'javascript',
  'typescript',
  'kotlin',
  'csharp',
  'python',
  'go',
  'lua',
];

/// Languages that can express `??` — every target except Go, which has neither
/// a null-coalescing operator nor a conditional expression, and which maps a
/// nullable `T?` onto a non-nullable Go `T` that cannot be compared to `nil`.
/// Go reports `??` as an [UnsupportedSyntaxError] rather than emitting Go that
/// does not compile.
final _languagesWithNullCoalesce = _languages.where((l) => l != 'go').toList();

/// A Dart program exercising the full null-safety surface: nullable types,
/// `??`, `??=`, `?.`, `?.method()`, `?[`, postfix `!` (standalone and before
/// access) and cascades (`..` / `?..`).
const _source = r'''
class A {
  int x = 1;
  int add(int d) { x = x + d; return x; }

  int coalesce(int? a, int b) { return a ?? b; }
  int coalesceAssign(int? a, int b) { a ??= b; return a; }
  int? field(A? a) { return a?.x; }
  int? call(A? a) { return a?.add(1); }
  int? index(List<int>? xs) { return xs?[0]; }
  int assertField(A? a) { return a!.x; }
  int assertIndex(List<int>? xs) { return xs![0]; }
  int bang(int? a, int b) { int? v = a ?? b; return v!; }
  A cascade(A a) { a..add(1)..add(2); return a; }

  String? name;
  List<String>? names;
  void Function()? cb;
}
''';

Future<ApolloVM> _load(String src) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', src, id: 'test'));
  expect(ok, isTrue, reason: "can't load Dart source");
  return vm;
}

Future<String> _generate(ApolloVM vm, String language) async {
  var storage = vm.generateAllCodeIn(language);
  await storage.writeAllSources();
  var out = StringBuffer();
  for (var ns in await storage.getNamespaces()) {
    for (var id in await storage.getNamespaceCodeUnitsIDs(ns)) {
      out.write((await storage.getNamespaceCodeUnit(ns, id))!);
    }
  }
  return out.toString();
}

void main() {
  group('null-safety generation', () {
    test(
      'every language generates without error and names the class',
      () async {
        var vm = await _load(_source);
        for (var language in _languagesWithNullCoalesce) {
          var code = await _generate(vm, language);
          expect(code, isNotEmpty, reason: '$language generated nothing');
          expect(
            code,
            contains('A'),
            reason: '$language should name the generated class',
          );
        }
      },
    );

    test(
      'Go reports `??` as unsupported instead of emitting broken Go',
      () async {
        var vm = await _load(_source);
        expect(
          () => _generate(vm, 'go'),
          throwsA(isA<UnsupportedSyntaxError>()),
          reason:
              'Go cannot express `??`, so it must fail loudly rather than emit '
              'source that does not compile',
        );
      },
    );

    test('Go still generates a program with no null-coalescing', () async {
      var vm = await _load(
        'class B { int add(int a, int b) { return a + b; } }',
      );
      var go = await _generate(vm, 'go');
      expect(go, contains('func'));
      expect(go, isNot(contains('??')));
    });

    test('Dart round-trips every operator exactly', () async {
      var vm = await _load(_source);
      var dart = await _generate(vm, 'dart');

      expect(dart, contains('int coalesce(int? a, int b)'));
      expect(dart, contains('return a ?? b;'));
      expect(dart, contains('a ??= b;'));
      expect(dart, contains('return a?.x;'));
      expect(dart, contains('return a?.add(1);'));
      expect(dart, contains('return xs?[0];'));
      expect(dart, contains('return a!.x;'));
      expect(dart, contains('return xs![0];'));
      expect(dart, contains('return v!;'));
      expect(dart, contains('a..add(1)..add(2);'));
      expect(dart, contains('String? name;'));
      expect(dart, contains('List<String>? names;'));
      expect(dart, contains('void Function()? cb;'));
    });

    test('Dart generated source parses back', () async {
      var vm = await _load(_source);
      var dart = await _generate(vm, 'dart');
      var reloaded = ApolloVM();
      var ok = await reloaded.loadCodeUnit(
        SourceCodeUnit('dart', dart, id: 'test'),
      );
      expect(ok, isTrue, reason: 'Dart generated source it cannot parse');
    });

    test('Kotlin emits native null-aware forms (?:, ?., !!)', () async {
      var vm = await _load(_source);
      var kotlin = await _generate(vm, 'kotlin');
      expect(kotlin, contains('a ?: b')); // Elvis, not `??`
      expect(kotlin, contains('a?.x'));
      expect(kotlin, contains('a!!.x'));
      expect(kotlin, contains('Int?')); // nullable type suffix
    });

    test('TypeScript emits native null-aware forms (??, ?., ?.[, !)', () async {
      var vm = await _load(_source);
      var ts = await _generate(vm, 'typescript');
      expect(ts, contains('a ?? b'));
      expect(ts, contains('a?.x'));
      expect(ts, contains('xs?.[0]')); // element access is `?.[`, not `?[`
      expect(ts, contains('a!.x'));
    });

    test('C# emits `??` (native null-coalescing)', () async {
      var vm = await _load(_source);
      var csharp = await _generate(vm, 'csharp');
      expect(csharp, contains('a ?? b'));
    });

    test('no target leaks a literal `??` or `??=` it cannot compile', () async {
      var vm = await _load(_source);
      // Targets that genuinely have the operators keep them.
      const native = {'dart', 'javascript', 'typescript', 'csharp'};

      for (var language in _languagesWithNullCoalesce) {
        var code = await _generate(vm, language);
        if (native.contains(language)) continue;

        expect(
          code,
          isNot(contains('??')),
          reason: '$language has no `??`/`??=` and must desugar them',
        );
      }
    });

    test('Java desugars `??` and `??=` into ternaries', () async {
      var vm = await _load(_source);
      var java = await _generate(vm, 'java11');
      expect(java, contains('(a != null ? a : b)'));
      // `a ??= b` becomes `a = (a != null ? a : b)`.
      expect(java, contains('a = (a != null ? a : b)'));
    });

    test(
      'Python desugars `??` and `??=` into conditional expressions',
      () async {
        var vm = await _load(_source);
        var python = await _generate(vm, 'python');
        expect(python, contains('(a if a is not None else b)'));
        expect(python, contains('a = (a if a is not None else b)'));
      },
    );

    test('Lua desugars `??` with an explicit nil test (not `or`)', () async {
      var vm = await _load(_source);
      var lua = await _generate(vm, 'lua');
      // `a or b` would be wrong: Lua treats `false` as falsy, so a non-nil
      // `false` must NOT fall through to `b`.
      expect(lua, contains('~= nil'));
      expect(lua, isNot(contains('a or b')));
    });

    test('Kotlin lowers `??=` to `t = t ?: v` (it has no `??=`)', () async {
      var vm = await _load(_source);
      var kotlin = await _generate(vm, 'kotlin');
      expect(kotlin, contains('a = a ?: b'));
    });
  });
}
