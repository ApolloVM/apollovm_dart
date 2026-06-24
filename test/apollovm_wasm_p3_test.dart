library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Runs [functionName] via the AST interpreter AND the compiled+executed Wasm
/// module and asserts both return [expectedReturn].
Future<void> _testWasmReturn(
  String code,
  String functionName,
  List args,
  Object? expectedReturn,
) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', code, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source");

  var astRunner = vm.createRunner('dart')!;
  var astRet = await astRunner.executeFunction(
    '',
    functionName,
    positionalParameters: args,
  );
  expect(astRet.getValueNoContext(), expectedReturn, reason: 'interpreter');

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
  var wasmRet = await wasmRunner.executeFunction(
    '',
    functionName,
    positionalParameters: args,
  );
  expect(wasmRet.getValueNoContext(), expectedReturn, reason: 'Wasm');
}

void main() {
  group('Wasm P3: list indexing + length', () {
    test('index with constant', () async {
      await _testWasmReturn(
        '''
        int third() {
          List<int> a = [10, 20, 30];
          return a[2];
        }
      ''',
        'third',
        [],
        30,
      );
    });

    test('index with variable', () async {
      await _testWasmReturn(
        '''
        int getAt(int i) {
          List<int> a = [10, 20, 30];
          return a[i];
        }
      ''',
        'getAt',
        [1],
        20,
      );
    });

    test('length', () async {
      await _testWasmReturn(
        '''
        int len() {
          List<int> a = [5, 6, 7, 8];
          return a.length;
        }
      ''',
        'len',
        [],
        4,
      );
    });

    test('double element index', () async {
      await _testWasmReturn(
        '''
        double at(int i) {
          List<double> a = [1.5, 2.5, 3.5];
          return a[i];
        }
      ''',
        'at',
        [1],
        2.5,
      );
    });
  });

  group('Wasm P3: for-each', () {
    test('sum int list', () async {
      await _testWasmReturn(
        '''
        int sum() {
          List<int> a = [1, 2, 3, 4];
          int s = 0;
          for (var e in a) {
            s = s + e;
          }
          return s;
        }
      ''',
        'sum',
        [],
        10,
      );
    });

    test('sum double list', () async {
      await _testWasmReturn(
        '''
        double dsum() {
          List<double> a = [1.5, 2.5, 3.0];
          double s = 0.0;
          for (var e in a) {
            s = s + e;
          }
          return s;
        }
      ''',
        'dsum',
        [],
        7.0,
      );
    });

    test('for-each with early return', () async {
      await _testWasmReturn(
        '''
        int firstOver(int t) {
          List<int> a = [5, 10, 15, 20];
          for (var e in a) {
            if (e > t) {
              return e;
            }
          }
          return -1;
        }
      ''',
        'firstOver',
        [9],
        10,
      );
    });

    test('count matching (for-each + condition)', () async {
      await _testWasmReturn(
        '''
        int countEven() {
          List<int> a = [1, 2, 3, 4, 5, 6];
          int c = 0;
          for (var e in a) {
            if (e % 2 == 0) {
              c = c + 1;
            }
          }
          return c;
        }
      ''',
        'countEven',
        [],
        3,
      );
    });
  });
}
