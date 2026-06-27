@Tags(['wasm', 'dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Compiles [code] to Wasm, runs top-level [functionName] on BOTH the AST
/// interpreter and the compiled Wasm module, and asserts both produce
/// [expectedPrints] (compared as text).
Future<void> _testWasmPrints(
  String code,
  String functionName,
  List<String> expectedPrints,
) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', code, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source");

  // 1) AST interpreter.
  var astRunner = vm.createRunner('dart')!;
  var astOut = <String>[];
  astRunner.externalPrintFunction = (o) => astOut.add('$o');
  await astRunner.executeFunction('', functionName);
  expect(astOut, equals(expectedPrints), reason: 'interpreter print output');

  // 2) Compile to Wasm.
  var storageWasm = vm.generateAllIn<BytesOutput>('wasm');
  var wasmModules = await storageWasm.allEntries();
  BytesOutput? compiled;
  for (var ns in wasmModules.entries) {
    for (var m in ns.value.entries) {
      compiled ??= m.value;
    }
  }
  expect(compiled, isNotNull, reason: 'No compiled Wasm module');

  var rt = WasmRuntime()..ensureBooted();
  if (!rt.isSupported) {
    fail('Wasm runtime not supported (run `dart run wasm_run:setup`).');
  }

  // 3) Run the compiled Wasm.
  var vmWasm = ApolloVM();
  await vmWasm.loadCodeUnit(
    BinaryCodeUnit('wasm', compiled!.output(), id: 'test.wasm', namespace: ''),
  );
  var wasmRunner = vmWasm.createRunner('wasm')!;
  var wasmOut = <String>[];
  wasmRunner.externalPrintFunction = (o) => wasmOut.add('$o');
  await wasmRunner.executeFunction('', functionName);
  expect(wasmOut, equals(expectedPrints), reason: 'Wasm print output');
}

void main() {
  group('Wasm: object fields + default constructor + toString', () {
    test('the motivating program', () async {
      await _testWasmPrints(
        r'''
        class User {
          int id;
          String name;
          String toString() { return 'User#$id<$name>'; }
        }
        void main() {
          var user = new User();
          user.id = 123;
          user.name = 'Joe';
          print(user);
          var id2 = user.id * 1000;
          print(id2);
        }
      ''',
        'main',
        ['User#123<Joe>', '123000'],
      );
    });

    test('default constructor + external field read/write', () async {
      await _testWasmPrints(
        r'''
        class Point { int x; int y; }
        void main() {
          var p = new Point();
          p.x = 3;
          p.y = 4;
          print(p.x + p.y);
        }
      ''',
        'main',
        ['7'],
      );
    });

    test('compound assignment on a field', () async {
      await _testWasmPrints(
        r'''
        class Counter { int n; }
        void main() {
          var c = new Counter();
          c.n = 10;
          c.n += 5;
          print(c.n);
        }
      ''',
        'main',
        ['15'],
      );
    });

    test('constructor with `this.` parameters', () async {
      await _testWasmPrints(
        r'''
        class Point {
          int x;
          int y;
          Point(this.x, this.y);
          String toString() { return '($x,$y)'; }
        }
        void main() {
          var p = new Point(3, 4);
          print(p);
          print(p.x * p.y);
        }
      ''',
        'main',
        ['(3,4)', '12'],
      );
    });

    test('constructor body assigns fields', () async {
      await _testWasmPrints(
        r'''
        class Box {
          int v;
          Box(int initial) { this.v = initial * 2; }
          String toString() { return 'Box($v)'; }
        }
        void main() {
          var b = new Box(21);
          print(b);
        }
      ''',
        'main',
        ['Box(42)'],
      );
    });

    test('arrow (expression-bodied) toString + method', () async {
      await _testWasmPrints(
        r'''
        class User {
          int id;
          String name;
          User(this.id, this.name);
          String toString() => 'User#$id<$name>';
        }
        void main() {
          var user = new User(123, 'Joe');
          print(user);
        }
      ''',
        'main',
        ['User#123<Joe>'],
      );
    });

    test('String field through toString', () async {
      await _testWasmPrints(
        r'''
        class Greeter {
          String name;
          String toString() { return 'Hi ' + name; }
        }
        void main() {
          var g = new Greeter();
          g.name = 'Bob';
          print(g);
        }
      ''',
        'main',
        ['Hi Bob'],
      );
    });

    // GAP 4: a generic class with a type-parameter field instantiated as
    // `Box<int>`. The type parameter `T` is erased to `dynamic`, so the field is
    // a boxed (i32) slot, but storing an `int` (i64) into it does not box the
    // value — producing an i32/i64 width mismatch. A robust fix needs box-on
    // -store / unbox-on-read for `dynamic`/`Object` fields holding primitives.
    test('generic Box<int> field round-trips', () async {
      await _testWasmPrints(
        r'''
        class Box<T> {
          T value;
          Box(this.value);
        }
        void main() {
          var b = Box<int>(7);
          print(b.value);
        }
      ''',
        'main',
        ['7'],
      );
    }, skip: 'BUG/GAP 4: a generic (type-parameter -> `dynamic`) field holding a '
        'primitive int is not boxed on store, causing an i32/i64 width '
        'mismatch in Wasm.');
  });
}
