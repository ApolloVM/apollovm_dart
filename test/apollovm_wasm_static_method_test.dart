library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Compiles [code] to Wasm and runs the `static` method [className].[methodName]
/// (with [args]) on BOTH the AST interpreter and the compiled Wasm module,
/// asserting both produce [expectedPrints]. Exercises static-method compilation
/// (exported as `Class.method`) and `List<Object>` argument marshalling.
Future<void> _testStaticPrints(
  String code,
  String className,
  String methodName,
  List args,
  List<String> expectedPrints,
) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', code, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source");

  // 1) AST interpreter.
  var astRunner = vm.createRunner('dart')!;
  var astOut = <String>[];
  astRunner.externalPrintFunction = (o) => astOut.add('$o');
  await astRunner.executeClassMethod(
    '',
    className,
    methodName,
    positionalParameters: args,
  );
  expect(astOut, equals(expectedPrints), reason: 'interpreter print output');

  await _runWasmAndExpect(vm, '$className.$methodName', args, expectedPrints);
}

/// Compiles [code] to Wasm and runs the `static` method [className].[methodName]
/// (with [args]) on the compiled Wasm module ONLY, asserting [expectedPrints].
/// Used where the AST interpreter and the compiled module legitimately differ
/// (e.g. interpolating a user instance held in a `List<Object>`).
Future<void> _testStaticPrintsWasmOnly(
  String code,
  String className,
  String methodName,
  List args,
  List<String> expectedPrints,
) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', code, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source");
  await _runWasmAndExpect(vm, '$className.$methodName', args, expectedPrints);
}

Future<void> _runWasmAndExpect(
  ApolloVM vm,
  String exportName,
  List args,
  List<String> expectedPrints,
) async {
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

  var vmWasm = ApolloVM();
  await vmWasm.loadCodeUnit(
    BinaryCodeUnit('wasm', compiled!.output(), id: 'test.wasm', namespace: ''),
  );
  var wasmRunner = vmWasm.createRunner('wasm')!;
  var wasmOut = <String>[];
  wasmRunner.externalPrintFunction = (o) => wasmOut.add('$o');
  await wasmRunner.executeFunction('', exportName, positionalParameters: args);
  expect(wasmOut, equals(expectedPrints), reason: 'Wasm print output');
}

void main() {
  group('Wasm: static methods + List<Object> args', () {
    // The motivating program: a `static main(List<Object> args)` that builds an
    // instance and calls an instance method which interpolates `args[0]`.
    const motivating = r'''
      class Foo {
        int id;
        Foo(this.id);
        void show(List<Object> args) {
          print('id: $id ; args: ${args[0]}');
        }
        static void main(List<Object> args) {
          var foo = Foo(123);
          foo.show(args);
        }
      }
    ''';

    test('static main with a String arg element', () async {
      await _testStaticPrints(
        motivating,
        'Foo',
        'main',
        [
          ['hello'],
        ],
        ['id: 123 ; args: hello'],
      );
    });

    test('static main with an int arg element', () async {
      await _testStaticPrints(
        motivating,
        'Foo',
        'main',
        [
          [42],
        ],
        ['id: 123 ; args: 42'],
      );
    });

    test('static main with a double arg element', () async {
      await _testStaticPrints(
        motivating,
        'Foo',
        'main',
        [
          [3.5],
        ],
        ['id: 123 ; args: 3.5'],
      );
    });

    test('static main with a bool arg element', () async {
      await _testStaticPrints(
        motivating,
        'Foo',
        'main',
        [
          [true],
        ],
        ['id: 123 ; args: true'],
      );
    });

    test('static method returning an int (no args)', () async {
      await _testStaticPrints(
        r'''
        class Foo {
          int id;
          Foo(this.id);
          int show(int x) { return id + x; }
          static void run() {
            var foo = Foo(100);
            print(foo.show(23));
          }
        }
        ''',
        'Foo',
        'run',
        const [],
        ['123'],
      );
    });
  });

  group('Wasm: in-code List<Object> boxing', () {
    test(
      'mixed-primitive List<Object> literal indexed in interpolation',
      () async {
        await _testStaticPrints(
          r'''
        class Foo {
          static void demo() {
            List<Object> x = [1, 'two', 3.5, true];
            for (var i = 0; i < 4; i = i + 1) {
              print('x[$i] = ${x[i]}');
            }
          }
        }
        ''',
          'Foo',
          'demo',
          const [],
          ['x[0] = 1', 'x[1] = two', 'x[2] = 3.5', 'x[3] = true'],
        );
      },
    );

    test('boxed instance in List<Object> dispatches toString', () async {
      // The AST interpreter does not invoke `toString()` when interpolating a
      // user instance statically typed `Object`, so this asserts the (correct)
      // Wasm output only.
      await _testStaticPrintsWasmOnly(
        r'''
        class P {
          int v;
          P(this.v);
          String toString() { return 'P($v)'; }
        }
        class Foo {
          static void demo() {
            List<Object> x = [1, 'two', P(9)];
            for (var i = 0; i < 3; i = i + 1) {
              print('x[$i] = ${x[i]}');
            }
          }
        }
        ''',
        'Foo',
        'demo',
        const [],
        ['x[0] = 1', 'x[1] = two', 'x[2] = P(9)'],
      );
    });
  });
}
