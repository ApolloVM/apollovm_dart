@TestOn('vm')
@Tags(['wasm', 'dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

import 'wasm_runtime_setup.dart';

/// Compiles [code] to Wasm, executes [functionName] both via the AST
/// interpreter and the compiled+executed Wasm module, asserting every
/// execution in [executions] matches.
Future<void> _testWasm(
  String code,
  String functionName,
  Map<List, Object?> executions,
) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', code, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source");

  var astRunner = vm.createRunner('dart')!;
  for (var e in executions.entries) {
    var r = await astRunner.executeFunction(
      '',
      functionName,
      positionalParameters: e.key,
    );
    expect(
      r.getValueNoContext(),
      e.value,
      reason: 'AST $functionName(${e.key})',
    );
  }

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
  var loadOK = await vmWasm.loadCodeUnit(
    BinaryCodeUnit('wasm', compiled!.output(), id: 'test.wasm', namespace: ''),
  );
  expect(loadOK, isTrue, reason: 'Compiled Wasm failed to load');

  var wasmRunner = vmWasm.createRunner('wasm')!;
  for (var e in executions.entries) {
    var r = await wasmRunner.executeFunction(
      '',
      functionName,
      positionalParameters: e.key,
    );
    expect(
      r.getValueNoContext(),
      e.value,
      reason: 'WASM $functionName(${e.key})',
    );
  }
}

void main() {
  setUpWasmRuntime();

  group('Wasm compound assignment', () {
    test('+= -= *= on int', () async {
      await _testWasm(
        r'''
        int addAssign(int a) {
          int x = a;
          x += 5;
          return x;
        }
      ''',
        'addAssign',
        {
          [10]: 15,
          [0]: 5,
        },
      );

      await _testWasm(
        r'''
        int mulSubAssign(int a) {
          int x = a;
          x *= 3;
          x -= 1;
          return x;
        }
      ''',
        'mulSubAssign',
        {
          [4]: 11,
          [2]: 5,
        },
      );
    });

    test('+= in a loop accumulator', () async {
      await _testWasm(
        r'''
        int sum(int n) {
          int total = 0;
          for (int i = 1; i <= n; i = i + 1) {
            total += i;
          }
          return total;
        }
      ''',
        'sum',
        {
          [4]: 10,
          [1]: 1,
        },
      );
    });
  });

  group('Wasm short-circuit && / ||', () {
    test('&& does not evaluate the right side when left is false', () async {
      // If `&&` were non-short-circuit, `100 ~/ d` with d==0 would trap.
      await _testWasm(
        r'''
        int safeAnd(int a, int d) {
          if (d != 0 && a ~/ d > 1) {
            return 1;
          }
          return 0;
        }
      ''',
        'safeAnd',
        {
          [10, 0]: 0,
          [10, 2]: 1,
          [10, 20]: 0,
        },
      );
    });

    test('|| does not evaluate the right side when left is true', () async {
      await _testWasm(
        r'''
        int safeOr(int a, int d) {
          if (d == 0 || a ~/ d > 1) {
            return 1;
          }
          return 0;
        }
      ''',
        'safeOr',
        {
          [10, 0]: 1,
          [10, 2]: 1,
          [10, 20]: 0,
        },
      );
    });

    test('chained && / || logic values', () async {
      await _testWasm(
        r'''
        int logic(int a, int b) {
          bool r = a > 0 && b > 0 || a < 0;
          if (r) {
            return 1;
          }
          return 0;
        }
      ''',
        'logic',
        {
          [1, 1]: 1,
          [1, 0]: 0,
          [-1, 0]: 1,
          [0, 5]: 0,
        },
      );
    });
  });

  group('Wasm modulo (Dart semantics, incl. negatives)', () {
    test('integer % matches Dart for negative operands', () async {
      await _testWasm(
        r'''
        int mod(int a, int b) {
          return a % b;
        }
      ''',
        'mod',
        {
          [17, 5]: 2,
          [-7, 3]: 2,
          [7, -3]: 1,
          [-7, -3]: 2,
          [0, 4]: 0,
          [9, 10]: 9,
        },
      );
    });

    test('double % matches Dart', () async {
      await _testWasm(
        r'''
        double modD(double a, double b) {
          return a % b;
        }
      ''',
        'modD',
        {
          [5.5, 2.0]: 1.5,
          [-5.5, 2.0]: 0.5,
          [5.5, -2.0]: 1.5,
        },
      );
    });
  });
}
