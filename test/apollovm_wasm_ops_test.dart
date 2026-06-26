@TestOn('vm')
@Tags(['wasm', 'dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Compiles [code] to Wasm, executes [functionName] both via the AST
/// interpreter and the compiled+executed Wasm module, and asserts every
/// execution matches the expected result in [executions].
Future<void> _testWasm(
  String code,
  String functionName,
  Map<List, Object?> executions,
) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', code, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source");

  // 1) AST interpreter.
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
    fail(
      'Wasm runtime not supported — cannot validate compiled bytes '
      '(run `dart run wasm_run:setup`).',
    );
  }

  // 3) Load + execute the compiled Wasm.
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
  group('Wasm OPS: modulo', () {
    test('integer remainder (non-negative)', () async {
      await _testWasm(
        r'''
        int mod(int a, int b) {
          return a % b;
        }
      ''',
        'mod',
        {
          [17, 5]: 2,
          [20, 4]: 0,
          [9, 10]: 9,
        },
      );
    });
  });

  group('Wasm OPS: logical && / ||', () {
    test('logical AND with bool locals', () async {
      await _testWasm(
        r'''
        int land(int a, int b) {
          bool x = a > 5;
          bool y = b > 5;
          if (x && y) {
            return 1;
          }
          return 0;
        }
      ''',
        'land',
        {
          [6, 6]: 1,
          [6, 1]: 0,
          [1, 6]: 0,
        },
      );
    });

    test('logical OR', () async {
      await _testWasm(
        r'''
        int lor(int a) {
          bool x = a > 5 || a < 2;
          if (x) {
            return 1;
          }
          return 0;
        }
      ''',
        'lor',
        {
          [6]: 1,
          [1]: 1,
          [4]: 0,
        },
      );
    });
  });

  group('Wasm OPS: logical negation !', () {
    test('not on a bool', () async {
      await _testWasm(
        r'''
        int neg(int a) {
          bool x = a > 5;
          if (!x) {
            return 1;
          }
          return 0;
        }
      ''',
        'neg',
        {
          [1]: 1,
          [6]: 0,
        },
      );
    });
  });

  group('Wasm OPS: unary minus', () {
    test('negate int', () async {
      await _testWasm(
        r'''
        int negI(int a) {
          return -a;
        }
      ''',
        'negI',
        {
          [5]: -5,
          [-3]: 3,
          [0]: 0,
        },
      );
    });

    test('negate double', () async {
      await _testWasm(
        r'''
        double negD(double a) {
          return -a;
        }
      ''',
        'negD',
        {
          [2.5]: -2.5,
          [-4.0]: 4.0,
        },
      );
    });
  });

  group('Wasm integration (loops + calls + logic + modulo)', () {
    test(
      'prime counting: while loop + function call + % + comparisons',
      () async {
        await _testWasm(
          r'''
        int isPrime(int n) {
          if (n < 2) {
            return 0;
          }
          int i = 2;
          while (i < n) {
            if (n % i == 0) {
              return 0;
            }
            i = i + 1;
          }
          return 1;
        }

        int countPrimes(int max) {
          int count = 0;
          int k = 2;
          while (k <= max) {
            if (isPrime(k) > 0) {
              count = count + 1;
            }
            k = k + 1;
          }
          return count;
        }
      ''',
          'countPrimes',
          {
            [10]: 4,
            [20]: 8,
            [1]: 0,
          },
        );
      },
    );

    test('for loop + function call + logical AND', () async {
      await _testWasm(
        r'''
        int sq(int x) {
          return x * x;
        }

        int sumSquaresMiddle(int n) {
          int total = 0;
          for (int i = 1; i <= n; i = i + 1) {
            if (i > 1 && i < n) {
              total = total + sq(i);
            }
          }
          return total;
        }
      ''',
        'sumSquaresMiddle',
        {
          [5]: 29,
          [3]: 4,
          [2]: 0,
        },
      );
    });
  });

  group('Wasm OPS: bool literals', () {
    test('true/false literals in conditions', () async {
      await _testWasm(
        r'''
        int useTrue(int a) {
          bool b = true;
          if (b) {
            return 1;
          }
          return 0;
        }
      ''',
        'useTrue',
        {
          [0]: 1,
        },
      );

      await _testWasm(
        r'''
        int useFalse(int a) {
          bool b = false;
          if (b) {
            return 1;
          }
          return 0;
        }
      ''',
        'useFalse',
        {
          [0]: 0,
        },
      );
    });
  });

  group('Wasm OPS: bitwise', () {
    test('& | ^ << >> and unary ~', () async {
      await _testWasm(
        r'''
        int bitOps(int a, int b) {
          int r = a & b;
          r = r + (a | b);
          r = r + (a ^ b);
          r = r + (a << 2);
          r = r + (a >> 1);
          r = r + (~a);
          return r;
        }
      ''',
        'bitOps',
        {
          // a=12 (1100), b=10 (1010): 8 + 14 + 6 + 48 + 6 + (-13) = 69
          [12, 10]: 69,
          // a=6 (0110), b=3 (0011): 2 + 7 + 5 + 24 + 3 + (-7) = 34
          [6, 3]: 34,
        },
      );
    });
  });

  group('Wasm control flow: do-while / break / continue / switch', () {
    test('do-while runs body at least once', () async {
      await _testWasm(
        r'''
        int dw(int n) {
          int sum = 0;
          int i = 0;
          do {
            sum = sum + i;
            i = i + 1;
          } while (i < n);
          return sum;
        }
      ''',
        'dw',
        {
          [3]: 3, // 0+1+2
          [1]: 0, // body once with i=0
          [0]: 0, // still runs once
        },
      );
    });

    test('break and continue in a for loop', () async {
      await _testWasm(
        r'''
        int bc(int n) {
          int sum = 0;
          for (int i = 0; i < n; i++) {
            if (i == 2) { continue; }
            if (i == 5) { break; }
            sum = sum + i;
          }
          return sum;
        }
      ''',
        'bc',
        {
          [10]: 8, // 0+1+3+4 (skip 2, stop at 5)
          [2]: 1, // 0 + (skip 1? no) -> i=0 sum0, i=1 sum1
        },
      );
    });

    test('switch with default', () async {
      await _testWasm(
        r'''
        int sw(int x) {
          int r = 0;
          switch (x) {
            case 1: { r = 10; break; }
            case 2: { r = 20; break; }
            default: { r = 99; break; }
          }
          return r;
        }
      ''',
        'sw',
        {
          [1]: 10,
          [2]: 20,
          [7]: 99,
        },
      );
    });

    test('switch fall-through', () async {
      await _testWasm(
        r'''
        int fall(int x) {
          int r = 0;
          switch (x) {
            case 1: { r = r + 1; }
            case 2: { r = r + 2; break; }
            case 3: { r = r + 3; }
            default: { r = r + 100; }
          }
          return r;
        }
      ''',
        'fall',
        {
          [1]: 3, // 1 -> falls into 2 -> break
          [2]: 2,
          [3]: 103, // 3 -> falls into default
          [9]: 100,
        },
      );
    });
  });
}
