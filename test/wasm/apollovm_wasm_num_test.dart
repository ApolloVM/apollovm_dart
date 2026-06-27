@Tags(['wasm'])
library;

import 'dart:typed_data';

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

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

void main() {
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
