@Tags(['wasm', 'dart', 'csharp'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Compiles [src] in [language] to Wasm and runs the static [entry] (e.g.
/// `Foo.run`) on BOTH the AST interpreter and the compiled Wasm module,
/// asserting both produce [expected].
Future<void> _bothEqualLang(
  String language,
  String src,
  String entry,
  Object? expected,
) async {
  var dot = entry.indexOf('.');
  var className = entry.substring(0, dot);
  var method = entry.substring(dot + 1);

  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit(language, src, id: 'test'));
  expect(ok, isTrue, reason: "Can't load `$language` source");

  var astRes = await vm
      .createRunner(language)!
      .executeClassMethod('', className, method);
  expect(astRes.getValueNoContext(), expected, reason: 'interpreter');

  var storage = vm.generateAllIn<BytesOutput>('wasm');
  var modules = await storage.allEntries();
  BytesOutput? compiled;
  for (var ns in modules.entries) {
    for (var m in ns.value.entries) {
      compiled ??= m.value;
    }
  }
  expect(compiled, isNotNull, reason: 'No compiled Wasm module');

  var vmWasm = ApolloVM();
  await vmWasm.loadCodeUnit(
    BinaryCodeUnit('wasm', compiled!.output(), id: 'test.wasm', namespace: ''),
  );
  var wasmRes = await vmWasm.createRunner('wasm')!.executeFunction('', entry);
  expect(wasmRes.getValueNoContext(), expected, reason: 'Wasm');
}

/// Compiles [src] (Dart) to Wasm and runs `Main.run` on BOTH the AST
/// interpreter and the compiled Wasm module, asserting both produce
/// [expected]. Enum entries are `const` instances, so this exercises enum
/// instances (entry access, `.index`/`.name`, fields, methods) under Wasm.
Future<void> _bothEqual(String src, Object? expected) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', src, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source");

  var astRes = await vm
      .createRunner('dart')!
      .executeClassMethod('', 'Main', 'run');
  expect(astRes.getValueNoContext(), expected, reason: 'interpreter');

  var storage = vm.generateAllIn<BytesOutput>('wasm');
  var modules = await storage.allEntries();
  BytesOutput? compiled;
  for (var ns in modules.entries) {
    for (var m in ns.value.entries) {
      compiled ??= m.value;
    }
  }
  expect(compiled, isNotNull, reason: 'No compiled Wasm module');

  var vmWasm = ApolloVM();
  await vmWasm.loadCodeUnit(
    BinaryCodeUnit('wasm', compiled!.output(), id: 'test.wasm', namespace: ''),
  );
  var wasmRes = await vmWasm
      .createRunner('wasm')!
      .executeFunction('', 'Main.run');
  expect(wasmRes.getValueNoContext(), expected, reason: 'Wasm');
}

/// Compiles [src] (Dart) and runs the static `Main.run` (no return value) on
/// BOTH the AST interpreter and the compiled Wasm module, asserting both emit
/// [expectedPrints].
///
/// Exercises enum access in a function that ALSO calls `print` / string
/// interpolation: `print` and `int_to_str`/`double_to_str` are registered as
/// host imports, which shifts module function indices. A lazily-generated
/// enum-entry init synth function must bake its constructor call index using the
/// FINAL import count, or it ends up calling a host import instead of the
/// constructor (reading back garbage fields).
Future<void> _bothPrints(String src, List<String> expectedPrints) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', src, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source");

  var astRunner = vm.createRunner('dart')!;
  var astOut = <String>[];
  astRunner.externalPrintFunction = (o) => astOut.add('$o');
  await astRunner.executeClassMethod('', 'Main', 'run');
  expect(astOut, equals(expectedPrints), reason: 'interpreter print output');

  var storage = vm.generateAllIn<BytesOutput>('wasm');
  var modules = await storage.allEntries();
  BytesOutput? compiled;
  for (var ns in modules.entries) {
    for (var m in ns.value.entries) {
      compiled ??= m.value;
    }
  }
  expect(compiled, isNotNull, reason: 'No compiled Wasm module');

  var vmWasm = ApolloVM();
  await vmWasm.loadCodeUnit(
    BinaryCodeUnit('wasm', compiled!.output(), id: 'test.wasm', namespace: ''),
  );
  var wasmRunner = vmWasm.createRunner('wasm')!;
  var wasmOut = <String>[];
  wasmRunner.externalPrintFunction = (o) => wasmOut.add('$o');
  await wasmRunner.executeFunction('', 'Main.run');
  expect(wasmOut, equals(expectedPrints), reason: 'Wasm print output');
}

void main() {
  group('Wasm: enum entries as const instances', () {
    const color = 'enum Color { red, green, blue }\n';

    test('entry .index (ordinal)', () async {
      await _bothEqual(
        '${color}class Main { static int run() { var c = Color.blue; return c.index; } }',
        2,
      );
    });

    test('entry .name', () async {
      await _bothEqual(
        '${color}class Main { static String run() { var c = Color.green; return c.name; } }',
        'green',
      );
    });

    test('Color.values length (for-in)', () async {
      await _bothEqual(
        '${color}class Main { static int run() { var n = 0; '
        'for (var c in Color.values) { n = n + 1; } return n; } }',
        3,
      );
    });
  });

  group('Wasm: rich enum (constructor args, fields, methods)', () {
    const planet = '''
enum Planet {
  earth(5.97, 6371), mars(0.642, 3389);
  final double mass;
  final double radius;
  const Planet(this.mass, this.radius);
  double gravity() { return mass / (radius * radius); }
}
''';

    test('entry field from a constructor arg', () async {
      await _bothEqual(
        '${planet}class Main { static double run() { var e = Planet.earth; return e.mass; } }',
        5.97,
      );
    });

    test('method call on an entry', () async {
      // Note: the Wasm backend resolves an enum-entry access but does not yet
      // chain a method call directly on it (`Planet.earth.gravity()`); bind the
      // entry to a variable first. The interpreter handles either form.
      await _bothEqual(
        '${planet}class Main { static double run() { var e = Planet.earth; return e.gravity(); } }',
        5.97 / (6371 * 6371),
      );
    });

    test('rich entry .index', () async {
      await _bothEqual(
        '${planet}class Main { static int run() { var m = Planet.mars; return m.index; } }',
        1,
      );
    });

    // GAP 7: an enum method that uses a field.
    test('enum method using a field', () async {
      await _bothEqual(r'''
        enum Planet {
          earth(9.8), mars(3.7);
          final double gravity;
          const Planet(this.gravity);
          double mult(double m) { return gravity * m; }
        }
        class Main {
          static double run() {
            var e = Planet.earth;
            return e.mult(2.0);
          }
        }
        ''', 19.6);
    });

    // GAP 7: an enum method taking an enum-TYPED parameter (`Planet p`).
    test('enum method taking an enum-typed parameter', () async {
      await _bothEqual(r'''
        enum Planet {
          earth(9.8), mars(3.7);
          final double gravity;
          const Planet(this.gravity);
          double ratio(Planet p) { return gravity / p.gravity; }
        }
        class Main {
          static double run() {
            var e = Planet.earth;
            var m = Planet.mars;
            return e.ratio(m);
          }
        }
        ''', 9.8 / 3.7);
    });
  });

  group('Wasm: rich enum fields/methods printed (host-import index)', () {
    // Regression: an enum's fields/methods accessed in a function that ALSO
    // calls `print` (registering `print`/`*_to_str` host imports) used to read
    // garbage, because the enum-entry init synth baked a stale constructor call
    // index that the later-registered imports shifted onto a host import.
    const planet = '''
enum Planet {
  earth(9.8), mars(3.7);
  final double gravity;
  const Planet(this.gravity);
  double mult(double m) => gravity * m;
  double ratio(Planet p) => gravity / p.gravity;
}
''';

    // The exact motivating program. Restricted to the VM: the irrational
    // `9.8 / 3.7` ratio renders slightly differently under dart2js's
    // `double_to_str` than the interpreter (an orthogonal double-formatting
    // concern), so the cross-platform cases below use round values.
    test('the motivating program', () async {
      await _bothPrints(
        '${planet}class Main { static void run() {\n'
        '  var earth = Planet.earth;\n'
        '  var mars = Planet.mars;\n'
        "  print('earth.gravity: \${earth.gravity}');\n"
        "  print('mars.index: \${mars.index} ; mars.name: \${mars.name}');\n"
        "  print('earth.mult(2): \${earth.mult(2)}');\n"
        "  print('earth / mars: \${earth.ratio(mars)}');\n"
        '} }',
        [
          'earth.gravity: 9.8',
          'mars.index: 1 ; mars.name: mars',
          'earth.mult(2): 19.6',
          'earth / mars: ${9.8 / 3.7}',
        ],
      );
    }, testOn: 'vm');

    test('print an enum double field directly', () async {
      await _bothPrints(
        '${planet}class Main { static void run() {\n'
        '  var e = Planet.earth;\n'
        '  print(e.gravity);\n'
        '} }',
        ['9.8'],
      );
    });

    test('print an enum method result', () async {
      // 9.8 * 2 = 19.6 — a non-whole double that renders identically on the VM
      // and dart2js (whole doubles like `37.0` print as `37` under dart2js).
      await _bothPrints(
        '${planet}class Main { static void run() {\n'
        '  var e = Planet.earth;\n'
        '  print(e.mult(2.0));\n'
        '} }',
        ['19.6'],
      );
    });

    test('print enum .index and .name together', () async {
      await _bothPrints(
        '${planet}class Main { static void run() {\n'
        '  var e = Planet.mars;\n'
        "  print('\${e.index}/\${e.name}');\n"
        '} }',
        ['1/mars'],
      );
    });

    // VM-only: `ratio` returns a whole/irrational double whose string form
    // differs under dart2js (an orthogonal double-formatting concern). The
    // enum-typed-parameter path is also covered cross-platform by the
    // value-comparing `enum method taking an enum-typed parameter` test above.
    test('print enum-typed-parameter method result', () async {
      await _bothPrints(
        '${planet}class Main { static void run() {\n'
        '  var e = Planet.earth;\n'
        '  var m = Planet.mars;\n'
        '  print(e.ratio(m));\n'
        '} }',
        ['${9.8 / 3.7}'],
      );
    }, testOn: 'vm');
  });

  group('Wasm: switch on an enum', () {
    // `switch` on an enum is compiled by reducing the scrutinee and each case
    // entry to their ordinal (`.index`) and comparing as ints.
    test('switch on an enum scrutinee', () async {
      await _bothEqual(r'''
        enum Color { red, green, blue }
        class Main {
          static int run() {
            var c = Color.green;
            switch (c) {
              case Color.red: return 1;
              case Color.green: return 2;
              default: return 9;
            }
          }
        }
        ''', 2);
    });

    test('enum switch matches the last entry explicitly', () async {
      await _bothEqual(r'''
        enum Color { red, green, blue }
        class Main {
          static int run() {
            var c = Color.blue;
            switch (c) {
              case Color.red: return 1;
              case Color.green: return 2;
              case Color.blue: return 3;
              default: return 9;
            }
          }
        }
        ''', 3);
    });

    test('enum switch falls to default', () async {
      await _bothEqual(r'''
        enum Color { red, green, blue }
        class Main {
          static int run() {
            var c = Color.blue;
            switch (c) {
              case Color.red: return 1;
              case Color.green: return 2;
              default: return 99;
            }
          }
        }
        ''', 99);
    });

    test('enum switch returns a String', () async {
      await _bothEqual(r'''
        enum Color { red, green, blue }
        class Main {
          static String run() {
            var c = Color.green;
            switch (c) {
              case Color.red: return 'R';
              case Color.green: return 'G';
              default: return '?';
            }
          }
        }
        ''', 'G');
    });

    test('enum switch over a rich enum entry', () async {
      await _bothEqual(r'''
        enum Planet {
          earth(9.8), mars(3.7);
          final double gravity;
          const Planet(this.gravity);
        }
        class Main {
          static double run() {
            var p = Planet.mars;
            switch (p) {
              case Planet.earth: return 1.0;
              case Planet.mars: return 2.0;
              default: return 0.0;
            }
          }
        }
        ''', 2.0);
    });
  });

  group('Wasm: C# enum .value (explicit values)', () {
    // GAP 9: an explicit-value (C#) enum entry exposes its declared integer via
    // `.value`.
    test('C# enum .value', () async {
      await _bothEqualLang(
        'csharp',
        r'''
        enum Level { Low = 1, Medium = 5, High = 10 }
        class Foo {
          public static int run() {
            var m = Level.Medium;
            return m.value;
          }
        }
        ''',
        'Foo.run',
        5,
      );
    });
  });
}
