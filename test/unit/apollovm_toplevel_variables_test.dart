@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:apollovm/apollovm_serialization.dart';
import 'package:test/test.dart';

/// Top-level (module) variables, and the lexical scoping that makes them
/// mean what they mean in Dart: a function sees the module it is declared in,
/// never its caller's locals.

Future<ApolloVM> _load(String src, {String language = 'dart'}) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit(language, src, id: 'test'));
  expect(ok, isTrue, reason: "Can't load $language source");
  return vm;
}

Future<Object?> _runVM(ApolloVM vm, {String language = 'dart'}) async {
  var res = await vm.createRunner(language)!.executeFunction('', 'run');
  return res.getValueNoContext();
}

Future<Object?> _run(String src) async => _runVM(await _load(src));

void main() {
  group('Top-level variables', () {
    test('read and written from a function', () async {
      expect(
        await _run(
          'int gx = 4;\n'
          'int run() { gx = gx + 1; gx++; gx += 10; return gx; }',
        ),
        equals(16),
      );
    });

    test('read and written from static and instance methods', () async {
      expect(
        await _run(
          'int gx = 4;\n'
          'class A { static int f() { return gx * 2; } int g() { gx++; return gx; } }\n'
          'int run() { return A.f() + A().g(); }',
        ),
        equals(13),
      );
    });

    test(
      '`final`, `var`, nullable, and an initializer calling a function',
      () async {
        expect(
          await _run(
            'int dbl(int x) { return x * 2; }\n'
            'final a = 2;\nvar b = a + 1;\nint c = dbl(5);\nint? d;\n'
            'int run() { d ??= 100; return a + b + c + d!; }',
          ),
          equals(115),
        );
      },
    );

    test('a collection is shared, not copied', () async {
      expect(
        await _run(
          'List<int> l = [1, 2];\n'
          'void add(int v) { l.add(v); }\n'
          'int run() { add(3); add(4); return l.length; }',
        ),
        equals(4),
      );
    });

    test('state persists between calls into the same VM', () async {
      var vm = await _load(
        'int count = 0;\nint run() { count++; return count; }',
      );
      expect(await _runVM(vm), equals(1));
      expect(await _runVM(vm), equals(2));
    });

    test('a class method entry point sees them', () async {
      var vm = await _load(
        'int gx = 4;\n'
        'class A { static int f() { return gx * 2; } }',
      );
      var res = await vm.createRunner('dart')!.executeClassMethod('', 'A', 'f');
      expect(res.getValueNoContext(), equals(8));
    });

    test('survives the binary AST and Dart regeneration', () async {
      const src =
          'int gx = 4;\n'
          'class A { static int f() { return gx * 2; } }\n'
          'int run() { gx++; return A.f(); }';

      var vm = await _load(src);
      var image = vm.saveCodeUnitAST(vm.allCodeUnitsAllLanguages().single);
      var vm2 = ApolloVM();
      expect(await vm2.loadCodeUnitAST(image), isTrue);
      expect(await _runVM(vm2), equals(10));

      var code = (await vm
          .generateAllCodeIn('dart')
          .getNamespaceCodeUnit('', 'test'))!;
      expect(await _runVM(await _load(code)), equals(10));
    });
  });

  group('Lexical scope', () {
    test("a function doesn't see its caller's locals", () async {
      var vm = await _load(
        'int f() { return x; }\nint run() { var x = 3; return f(); }',
      );
      await expectLater(_runVM(vm), throwsA(isA<StateError>()));
    });

    for (var call in ['A.f()', 'A().g()']) {
      test("a method doesn't see its caller's locals: $call", () async {
        var vm = await _load(
          'class A { static int f() { return x; } int g() { return x; } }\n'
          'int run() { var x = 3; return $call; }',
        );
        await expectLater(_runVM(vm), throwsA(isA<StateError>()));
      });
    }

    test("a caller's local doesn't shadow the global", () async {
      expect(
        await _run(
          'int x = 1;\nint f() { return x; }\n'
          'int run() { var x = 3; return f() * 10 + x; }',
        ),
        equals(13),
      );
    });

    test("a top-level function doesn't see its caller's `this`", () async {
      var vm = await _load(
        'int g() { return n; }\n'
        'class A { int n = 5; int f() { return g(); } }\n'
        'int run() { return A().f(); }',
      );
      await expectLater(_runVM(vm), throwsA(isA<StateError>()));
    });

    test('a local function still sees its enclosing locals', () async {
      expect(
        await _run(
          'int run() { var x = 3; int f() { return x * 2; } return f(); }',
        ),
        equals(6),
      );
    });

    test('a closure still captures its defining scope', () async {
      expect(
        await _run(
          'int Function() make() { var n = 0; return () { n++; return n; }; }\n'
          'int run() { var c = make(); c(); return c(); }',
        ),
        equals(2),
      );
    });
  });

  test('`var` takes the type of the last call in a chain', () async {
    expect(
      await _run(
        'class B { String s() { return "b"; } }\n'
        'class C { int peek() { return 7; } B b() { return B(); } }\n'
        'int run() { var p = C().peek(); var s = C().b().s(); return p + s.length; }',
      ),
      equals(8),
    );
  });

  group('Imported top-level variables', () {
    Future<ApolloVM> loadModules(String lib, String main) async {
      var vm = ApolloVM();
      expect(
        await vm.loadCodeUnit(SourceCodeUnit('dart', lib, id: 'lib.dart')),
        isTrue,
      );
      expect(
        await vm.loadCodeUnit(SourceCodeUnit('dart', main, id: 'main.dart')),
        isTrue,
      );
      return vm;
    }

    test('read and written by the importer', () async {
      var vm = await loadModules(
        'int gx = 9;',
        "import 'lib.dart';\n"
            'int run() { gx = gx + 1; gx++; return gx; }',
      );
      expect(await _runVM(vm), equals(11));
    });

    test("an imported function uses its own module's variable", () async {
      var vm = await loadModules(
        'int counter = 100;\nint next() { counter++; return counter; }\n'
            'class C { int peek() { return counter; } }',
        "import 'lib.dart';\n"
            'int counter = 0;\n'
            'int run() { next(); next(); var n = next(); var p = C().peek(); '
            'return n * 10000 + p * 10 + counter; }',
      );
      // `next()` and `C.peek()` use lib's `counter`; `run` reads its own.
      expect(await _runVM(vm), equals(103 * 10000 + 103 * 10 + 0));
    });
  });

  group('Generated code', () {
    Future<String> generate(String src, String language) async {
      var vm = await _load(src);
      return (await vm
          .generateAllCodeIn(language)
          .getNamespaceCodeUnit('', 'test'))!;
    }

    test('declared before the functions that use them', () async {
      var lua = await generate('int gx = 4;\nint run() { return gx; }', 'lua');
      expect(
        lua.indexOf('local gx'),
        allOf(isNonNegative, lessThan(lua.indexOf('function run'))),
      );
    });

    test('Python declares the variables a function assigns `global`', () async {
      var py = await generate(
        'int gx = 4;\nint other = 1;\n'
            'int bump() { gx++; return gx; }\n'
            'int peek() { return gx + other; }\n'
            'int shadow() { var gx = 2; gx = gx + 1; return gx; }\n'
            'int run() { bump(); return peek() + shadow(); }',
        'python',
      );
      expect(py, contains('def bump() -> int:\n    global gx\n'));
      expect(py, isNot(contains('def peek() -> int:\n    global')));
      expect(py, isNot(contains('def shadow() -> int:\n    global')));

      var vm = await _load(py, language: 'python');
      expect(await _runVM(vm, language: 'python'), equals(6 + 3));
    });

    test('Python `global` makes a binding an assignment', () async {
      var vm = await _load(
        'count = 0\n\n'
        'def inc():\n    global count\n    count = count + 1\n    count = count + 1\n\n'
        'def run():\n    inc()\n    inc()\n    return count\n',
        language: 'python',
      );
      expect(await _runVM(vm, language: 'python'), equals(4));
    });
  });
}
