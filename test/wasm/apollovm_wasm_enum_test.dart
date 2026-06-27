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
  var wasmRes = await vmWasm
      .createRunner('wasm')!
      .executeFunction('', entry);
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
      await _bothEqual(
        r'''
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
        ''',
        19.6,
      );
    });

    // GAP 7: an enum method taking an enum-TYPED parameter (`Planet p`).
    test('enum method taking an enum-typed parameter', () async {
      await _bothEqual(
        r'''
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
        ''',
        9.8 / 3.7,
      );
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
