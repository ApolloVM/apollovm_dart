@Tags(['wasm'])
library;

import 'dart:typed_data';

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

import 'wasm_runtime_setup.dart';

/// Compiles [code] in [language] to Wasm, runs the exported [functionName] both
/// via the AST interpreter and the compiled Wasm module for each
/// `args -> expected` entry, and asserts both return the expected value.
Future<void> _testWasm({
  required String language,
  required String code,
  required String functionName,
  required Map<List, Object?> executions,
}) async {
  var vm = ApolloVM();
  var loadOK = await vm.loadCodeUnit(
    SourceCodeUnit(language, code, id: 'test'),
  );
  expect(loadOK, isTrue, reason: "Can't load `$language` source");

  var astRunner = vm.createRunner(language)!;
  for (var e in executions.entries) {
    var astValue = await astRunner.executeFunction(
      '',
      functionName,
      positionalParameters: e.key,
    );
    expect(astValue.getValueNoContext(), e.value, reason: 'interpreter');
  }

  var storageWasm = vm.generateAllIn<BytesOutput>('wasm');
  var wasmModules = await storageWasm.allEntries();
  BytesOutput? compiled;
  for (var ns in wasmModules.entries) {
    for (var m in ns.value.entries) {
      compiled ??= m.value;
    }
  }
  expect(compiled, isNotNull);

  var wasmRuntime = WasmRuntime();
  wasmRuntime.ensureBooted();
  if (!wasmRuntime.isSupported) return; // No native runtime available.

  var vmWasm = ApolloVM();
  var ok = await vmWasm.loadCodeUnit(
    BinaryCodeUnit(
      'wasm',
      Uint8List.fromList(compiled!.output()),
      id: 'test.wasm',
      namespace: '',
    ),
  );
  expect(ok, isTrue);

  var wasmRunner = vmWasm.createRunner('wasm')!;
  for (var e in executions.entries) {
    var v = await wasmRunner.executeFunction(
      '',
      functionName,
      positionalParameters: e.key,
    );
    expect(v.getValueNoContext(), e.value, reason: 'wasm');
  }
}

/// Like [_testWasm] but compares captured `print` output (for `void` functions).
Future<void> _testWasmPrints({
  required String language,
  required String code,
  required String functionName,
  required List args,
  required List<String> expected,
}) async {
  var vm = ApolloVM();
  var loadOK = await vm.loadCodeUnit(
    SourceCodeUnit(language, code, id: 'test'),
  );
  expect(loadOK, isTrue, reason: "Can't load `$language` source");

  var astRunner = vm.createRunner(language)!;
  var astOut = <String>[];
  astRunner.externalPrintFunction = (o) => astOut.add('$o');
  await astRunner.executeFunction('', functionName, positionalParameters: args);
  expect(astOut, equals(expected), reason: 'interpreter');

  var storageWasm = vm.generateAllIn<BytesOutput>('wasm');
  var wasmModules = await storageWasm.allEntries();
  BytesOutput? compiled;
  for (var ns in wasmModules.entries) {
    for (var m in ns.value.entries) {
      compiled ??= m.value;
    }
  }
  expect(compiled, isNotNull);

  var wasmRuntime = WasmRuntime();
  wasmRuntime.ensureBooted();
  if (!wasmRuntime.isSupported) return;

  var vmWasm = ApolloVM();
  await vmWasm.loadCodeUnit(
    BinaryCodeUnit(
      'wasm',
      Uint8List.fromList(compiled!.output()),
      id: 'test.wasm',
      namespace: '',
    ),
  );
  var wasmRunner = vmWasm.createRunner('wasm')!;
  var wasmOut = <String>[];
  wasmRunner.externalPrintFunction = (o) => wasmOut.add('$o');
  await wasmRunner.executeFunction(
    '',
    functionName,
    positionalParameters: args,
  );
  expect(wasmOut, equals(expected), reason: 'wasm');
}

void main() {
  setUpWasmRuntime();

  // A plain `num` (TypeScript / JavaScript `number`) has no fixed width; the VM
  // treats integer-valued numbers as `int`, so the Wasm backend represents
  // `num` as i64. These exercise the paths that previously rejected `num`.
  group('Wasm: TypeScript `number` (num) arithmetic & coercion', () {
    test('num arithmetic returns int', () {
      return _testWasm(
        language: 'typescript',
        code: r'''
          function run(a: number, b: number): number {
            return a + b;
          }
        ''',
        functionName: 'run',
        executions: {
          [10, 20]: 30,
        },
      );
    });

    test('num coerced to String (interpolation / concat)', () {
      return _testWasm(
        language: 'typescript',
        code: r'''
          function run(a: number, b: number): string {
            return "sum=" + (a + b);
          }
        ''',
        functionName: 'run',
        executions: {
          [10, 20]: 'sum=30',
        },
      );
    });

    test('switch on a num scrutinee', () {
      return _testWasm(
        language: 'typescript',
        code: r'''
          function run(n: number): number {
            switch (n) {
              case 1:
                return 10;
              case 2:
                return 20;
              default:
                return 30;
            }
          }
        ''',
        functionName: 'run',
        executions: {
          [1]: 10,
          [2]: 20,
          [9]: 30,
        },
      );
    });
  });

  // A scalar `Object`/`dynamic` parameter is passed as a host-allocated box (so
  // the module reads a real box, not a raw scalar). This covers untyped
  // parameters from JavaScript/Python and an explicit Dart `dynamic` parameter.
  group('Wasm: scalar dynamic/Object parameter marshalling', () {
    test('Dart `dynamic` parameter arithmetic', () {
      return _testWasm(
        language: 'dart',
        code: r'''
          int run(dynamic a, dynamic b) {
            return a + b;
          }
        ''',
        functionName: 'run',
        executions: {
          [10, 20]: 30,
        },
      );
    });

    test('JavaScript untyped parameters (print)', () {
      return _testWasmPrints(
        language: 'javascript',
        code: r'''
          function run(a, b) {
            print(a + b);
          }
        ''',
        functionName: 'run',
        args: [10, 20],
        expected: ['30'],
      );
    });

    test('JavaScript switch on an untyped (dynamic) parameter (print)', () {
      return _testWasmPrints(
        language: 'javascript',
        code: r'''
          function run(n) {
            switch (n) {
              case 1:
                print("one");
                break;
              case 2:
                print("two");
                break;
              default:
                print("many");
            }
          }
        ''',
        functionName: 'run',
        args: [2],
        expected: ['two'],
      );
    });

    test('Python untyped parameters (print)', () {
      return _testWasmPrints(
        language: 'python',
        code: 'def run(a, b):\n    print(a + b)\n',
        functionName: 'run',
        args: [10, 20],
        expected: ['30'],
      );
    });
  });

  // Operations whose operands are boxed `Object`/`dynamic` values.
  group('Wasm: operations on boxed dynamic values', () {
    test('a + b with both operands boxed (var result refined to int)', () {
      // `a` and `b` are boxed `List<Object>` elements; the sum is an i64 and the
      // unresolved `var s` is refined to it.
      return _testWasm(
        language: 'dart',
        code: r'''
          int run(List<Object> args) {
            var a = args[0];
            var b = args[1];
            var s = a + b;
            return s;
          }
        ''',
        functionName: 'run',
        executions: {
          [
            [10, 20],
          ]: 30,
        },
      );
    });

    test('equality-to-zero on a boxed dynamic parameter', () {
      // `b == 0` uses the `i64.eqz` fast path, which must unbox `b` first.
      return _testWasmPrints(
        language: 'javascript',
        code: r'''
          function run(b) {
            if (b == 0) {
              print("zero");
            } else {
              print("nonzero");
            }
          }
        ''',
        functionName: 'run',
        args: [0],
        expected: ['zero'],
      );
    });
  });

  // A boxed `dynamic`/`Object` switch scrutinee is unboxed to a concrete i64 so
  // it can drive the int branch table.
  group('Wasm: switch on a boxed dynamic/Object scrutinee', () {
    test('switch on a List<Object> element', () {
      return _testWasm(
        language: 'dart',
        code: r'''
          String run(List<Object> args) {
            switch (args[0]) {
              case 1:
                return 'one';
              case 2:
                return 'two';
              default:
                return 'many';
            }
          }
        ''',
        functionName: 'run',
        executions: {
          [
            [1],
          ]: 'one',
          [
            [2],
          ]: 'two',
          [
            [7],
          ]: 'many',
        },
      );
    });
  });
}
