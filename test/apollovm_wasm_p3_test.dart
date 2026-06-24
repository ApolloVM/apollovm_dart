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

  group('Wasm P3: growable list (.add)', () {
    test('add then length', () async {
      await _testWasmReturn(
        '''
        int build() {
          List<int> a = [1, 2];
          a.add(3);
          a.add(4);
          return a.length;
        }
      ''',
        'build',
        [],
        4,
      );
    });

    test('add then index (triggers realloc)', () async {
      // Starts with capacity 3; each add past capacity reallocates+copies.
      await _testWasmReturn(
        '''
        int grow() {
          List<int> a = [10, 20, 30];
          a.add(40);
          a.add(50);
          return a[4];
        }
      ''',
        'grow',
        [],
        50,
      );
    });

    test('add preserves earlier elements after realloc', () async {
      await _testWasmReturn(
        '''
        int first() {
          List<int> a = [7];
          a.add(8);
          a.add(9);
          a.add(10);
          return a[0];
        }
      ''',
        'first',
        [],
        7,
      );
    });

    test('add to empty growable list', () async {
      await _testWasmReturn(
        '''
        int fromEmpty() {
          List<int> a = [];
          a.add(100);
          a.add(200);
          return a[1];
        }
      ''',
        'fromEmpty',
        [],
        200,
      );
    });

    test('add then sum via for-each', () async {
      await _testWasmReturn(
        '''
        int total() {
          List<int> a = [1, 2];
          a.add(3);
          a.add(4);
          int s = 0;
          for (var e in a) {
            s = s + e;
          }
          return s;
        }
      ''',
        'total',
        [],
        10,
      );
    });

    test('add doubles', () async {
      await _testWasmReturn(
        '''
        double dgrow() {
          List<double> a = [1.5];
          a.add(2.5);
          a.add(3.0);
          return a[1] + a[2];
        }
      ''',
        'dgrow',
        [],
        5.5,
      );
    });
  });

  group('Wasm P3: list getters (first/last/isEmpty)', () {
    test('first and last', () async {
      await _testWasmReturn(
        '''
        int firstLast() {
          List<int> a = [11, 22, 33];
          return a.first + a.last;
        }
      ''',
        'firstLast',
        [],
        44,
      );
    });

    test('last after add', () async {
      await _testWasmReturn(
        '''
        int lastAdded() {
          List<int> a = [1, 2];
          a.add(99);
          return a.last;
        }
      ''',
        'lastAdded',
        [],
        99,
      );
    });

    test('isEmpty on empty list', () async {
      await _testWasmReturn(
        '''
        bool empty() {
          List<int> a = [];
          return a.isEmpty;
        }
      ''',
        'empty',
        [],
        true,
      );
    });

    test('isEmpty on non-empty list', () async {
      await _testWasmReturn(
        '''
        bool empty() {
          List<int> a = [1];
          return a.isEmpty;
        }
      ''',
        'empty',
        [],
        false,
      );
    });

    test('isNotEmpty after add to empty', () async {
      await _testWasmReturn(
        '''
        bool notEmpty() {
          List<int> a = [];
          a.add(5);
          return a.isNotEmpty;
        }
      ''',
        'notEmpty',
        [],
        true,
      );
    });

    test('first double', () async {
      await _testWasmReturn(
        '''
        double firstD() {
          List<double> a = [1.5, 2.5];
          return a.first;
        }
      ''',
        'firstD',
        [],
        1.5,
      );
    });
  });
}
