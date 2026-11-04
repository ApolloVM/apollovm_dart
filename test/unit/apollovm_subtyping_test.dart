@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:apollovm/apollovm_serialization.dart';
import 'package:test/test.dart';

/// Subtype polymorphism (`A a = B();`), type tests (`is` / `is!`) and casts
/// (`as`): run in Dart, generated for every target, and round-tripped through
/// the binary AST.

const _hierarchy =
    'abstract class Shape { int area(); }\n'
    'class Sq implements Shape { int s; Sq(this.s); int area() { return s * s; } }\n'
    'class A { int v() { return 1; } }\n'
    'class B extends A { int v() { return 2; } int onlyB() { return 20; } }\n'
    'class C extends B { }\n';

Future<ApolloVM> _load(String src) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(
    SourceCodeUnit('dart', '$_hierarchy$src', id: 'test'),
  );
  expect(ok, isTrue, reason: "Can't load Dart source");
  return vm;
}

Future<Object?> _runVM(ApolloVM vm) async {
  var res = await vm.createRunner('dart')!.executeFunction('', 'run');
  return res.getValueNoContext();
}

Future<Object?> _run(String src) async => _runVM(await _load(src));

void main() {
  group('Subtype polymorphism', () {
    test('a subclass instance in a superclass variable, any depth', () async {
      expect(await _run('int run() { A a = B(); return a.v(); }'), equals(2));
      expect(await _run('int run() { A a = C(); return a.v(); }'), equals(2));
    });

    test('an implementer in an interface variable', () async {
      expect(
        await _run('int run() { Shape s = Sq(3); return s.area(); }'),
        equals(9),
      );
    });

    test('parameters, return values, fields and reassignment', () async {
      expect(
        await _run(
          'int f(A a) { return a.v(); }\nint run() { return f(C()); }',
        ),
        equals(2),
      );
      expect(
        await _run('A mk() { return B(); }\nint run() { return mk().v(); }'),
        equals(2),
      );
      expect(
        await _run(
          'class H { A a; H(this.a); }\n'
          'int run() { var h = H(B()); return h.a.v(); }',
        ),
        equals(2),
      );
      expect(
        await _run('int run() { A a = A(); a = B(); return a.v(); }'),
        equals(2),
      );
    });

    test('a supertype is still rejected in a subtype variable', () async {
      var vm = await _load('int run() { B b = A(); return b.v(); }');
      await expectLater(_runVM(vm), throwsA(isA<ApolloVMRuntimeError>()));
    });

    test('`catch` on a superclass type catches a subclass', () async {
      expect(
        await _run(
          'class E { } class E2 extends E { }\n'
          'int run() { try { throw E2(); } on E catch (e) { return 1; } return 0; }',
        ),
        equals(1),
      );
    });
  });

  group('Type tests: is / is!', () {
    const cases = <String, Object?>{
      'A a = C(); return a is B;': true,
      'A a = A(); return a is B;': false,
      'A a = A(); return a is! B;': true,
      'var s = Sq(2); return s is Shape;': true,
      'var x = 1; return x is int;': true,
      'var x = 1; return x is num;': true,
      'var x = 1; return x is double;': false,
      'dynamic x = "a"; return x is String;': true,
      'var x = 3; return x is Object;': true,
      'var x = 3; return x is dynamic;': true,
      'int? x = null; return x is int?;': true,
      'int? x = null; return x is int;': false,
      'int? x = null; return x is Object;': false,
      'var l = [1, 2]; return l is List<int>;': true,
      'var m = {"a": 1}; return m is Map;': true,
    };

    for (var e in cases.entries) {
      test(e.key, () async {
        expect(await _run('bool run() { ${e.key} }'), equals(e.value));
      });
    }

    test('binds tighter than `&&` and looser than `+`', () async {
      expect(
        await _run('bool run() { A a = B(); return a is B && a.v() == 2; }'),
        isTrue,
      );
      expect(
        await _run('bool run() { var x = 1; return x + 2 is int; }'),
        isTrue,
      );
    });

    test('a `?` after the type starts a conditional when it can', () async {
      expect(
        await _run('int run() { A a = B(); return a is B ? 1 : 0; }'),
        equals(1),
      );
      expect(
        await _run('int run() { int? x = 3; return x is int? ? 1 : 0; }'),
        equals(1),
      );
    });

    test('`isEmpty` and `asX` are still identifiers', () async {
      expect(
        await _run(
          'bool run() { var l = [1]; var isX = l.isEmpty; var asY = 2; '
          'return isX || asY != 2; }',
        ),
        isFalse,
      );
    });
  });

  group('Casts: as', () {
    test('a cast to a subclass, inline and into a variable', () async {
      expect(
        await _run('int run() { A a = B(); return (a as B).onlyB(); }'),
        equals(20),
      );
      expect(
        await _run('int run() { A a = C(); B b = a as B; return b.onlyB(); }'),
        equals(20),
      );
    });

    test('a failing cast throws', () async {
      var vm = await _load(
        'int run() { A a = A(); var b = a as B; return 0; }',
      );
      await expectLater(
        _runVM(vm),
        throwsA(
          isA<ApolloVMCastException>().having(
            (e) => e.toString(),
            'message',
            contains("'A' is not a subtype of type 'B'"),
          ),
        ),
      );
    });

    test('a cast from dynamic', () async {
      expect(
        await _run('num run() { dynamic x = 2; return x as num; }'),
        equals(2),
      );
    });
  });

  group('Generation and the binary AST', () {
    const program =
        'int run() {\n'
        '  A a = B();\n'
        '  var x = 1;\n'
        '  if (a is B && x is! String) { return (a as B).onlyB() + x; }\n'
        '  return 0;\n'
        '}\n';

    test('Dart output runs the same', () async {
      var vm = await _load(program);
      var code = (await vm
          .generateAllCodeIn('dart')
          .getNamespaceCodeUnit('', 'test'))!;
      expect(code, contains('(a is B) && (x is! String)'));
      expect(code, contains('(a as B).onlyB()'));

      var vm2 = ApolloVM();
      expect(
        await vm2.loadCodeUnit(SourceCodeUnit('dart', code, id: 'test')),
        isTrue,
      );
      expect(await _runVM(vm2), equals(21));
    });

    test('each target writes its own idiom', () async {
      // In a class: Java has no top-level functions.
      var vm = await _load(
        'class M { static ${program.replaceAll('\n', '\n  ')}}\n',
      );
      Future<String> code(String lang) async =>
          (await vm.generateAllCodeIn(lang).getNamespaceCodeUnit('', 'test'))!;

      expect(await code('java11'), contains('(a instanceof B)'));
      expect(await code('java11'), contains('((B) a).onlyB()'));
      expect(await code('kotlin'), contains('(x !is String)'));
      expect(await code('kotlin'), contains('(a as B).onlyB()'));
      expect(await code('csharp'), contains('(a is B)'));
      expect(await code('csharp'), contains('((B) a).onlyB()'));
      expect(await code('typescript'), contains("typeof x === 'string'"));
      expect(await code('typescript'), contains('(a as B).onlyB()'));
      expect(await code('javascript'), contains('(a instanceof B)'));
      expect(await code('python'), contains('isinstance(a, B)'));
      expect(await code('python'), contains('not isinstance(x, str)'));
    });

    test('Go, Lua and Wasm refuse instead of dropping the test', () async {
      var vm = await _load(program);
      for (var lang in ['go', 'lua']) {
        await expectLater(
          () async =>
              (await vm.generateAllCodeIn(lang).writeAllSources()).toString(),
          throwsA(isA<UnsupportedSyntaxError>()),
          reason: lang,
        );
      }
      await expectLater(
        () => vm.generateAllIn<BytesOutput>('wasm').allEntries(),
        throwsA(isA<UnsupportedSyntaxError>()),
      );
    });

    test('type tests and casts survive an image round-trip', () async {
      var vm = await _load(program);
      var image = vm.saveCodeUnitAST(vm.allCodeUnitsAllLanguages().single);
      var vm2 = ApolloVM();
      expect(await vm2.loadCodeUnitAST(image), isTrue);
      expect(await _runVM(vm2), equals(21));
    });
  });
}
