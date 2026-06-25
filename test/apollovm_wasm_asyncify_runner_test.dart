@TestOn('vm')
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// End-to-end real-suspension `async`/`await` in Wasm THROUGH the normal VM
/// runner: `ApolloRunnerWasm.executeFunction` compiles the async function with
/// the Asyncify transform, then drives its unwind/rewind loop — awaiting a real
/// Dart `Future` produced by a host function registered via
/// `mapWasmAsyncFunction`.

int _asInt(Object? v) => v is BigInt ? v.toInt() : (v as num).toInt();

Future<ApolloRunnerWasm?> _wasmRunner(String dartSource) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(
    SourceCodeUnit('dart', dartSource, id: 'test'),
  );
  expect(ok, isTrue, reason: "Can't load Dart source");

  // Compile to Wasm and reload the bytes as a runnable code unit.
  var storage = vm.generateAllIn<BytesOutput>('wasm');
  var modules = await storage.allEntries();
  BytesOutput? compiled;
  for (var ns in modules.entries) {
    for (var m in ns.value.entries) {
      compiled ??= m.value;
    }
  }
  if (compiled == null) return null;

  var rt = WasmRuntime()..ensureBooted();
  if (!rt.isSupported) return null;

  var vmWasm = ApolloVM();
  await vmWasm.loadCodeUnit(
    BinaryCodeUnit('wasm', compiled.output(), id: 'test.wasm', namespace: ''),
  );
  return vmWasm.createRunner('wasm') as ApolloRunnerWasm;
}

void main() {
  group('Wasm Asyncify via ApolloRunnerWasm (real suspension)', () {
    test(
      'executeFunction drives an async fn that awaits a host Future',
      () async {
        var runner = await _wasmRunner(r'''
        Future<int> compute(int n) async {
          int v = await hostDouble(n);
          return v + 1;
        }
      ''');
        if (runner == null) {
          fail('Wasm runtime not supported (run `dart run wasm_run:setup`).');
        }

        var awaited = false;
        runner.mapWasmAsyncFunction('hostDouble', const [WasmValueType.i64], (
          args,
        ) async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          awaited = true;
          return _asInt(args[0]) * 2;
        });

        var r = await runner.executeFunction(
          '',
          'compute',
          positionalParameters: [10],
        );

        expect(r.getValueNoContext(), equals(21)); // host(10)=20; +1 => 21
        expect(awaited, isTrue, reason: 'a real Future was awaited');
      },
    );

    test('locals set before the await survive the suspension', () async {
      var runner = await _wasmRunner(r'''
        Future<int> compute(int n) async {
          int base = n * 100;
          int v = await hostDouble(n);
          return base + v;
        }
      ''');
      if (runner == null) {
        fail('Wasm runtime not supported.');
      }

      runner.mapWasmAsyncFunction('hostDouble', const [WasmValueType.i64], (
        args,
      ) async {
        await Future<void>.delayed(const Duration(milliseconds: 3));
        return _asInt(args[0]) * 2;
      });

      var r = await runner.executeFunction(
        '',
        'compute',
        positionalParameters: [3],
      );

      expect(r.getValueNoContext(), equals(306)); // 300 + 6
    });

    test('multiple awaits of different host functions', () async {
      var runner = await _wasmRunner(r'''
        Future<int> pipeline(int n) async {
          int a = await hostInc(n);
          int b = await hostTriple(a);
          return a + b;
        }
      ''');
      if (runner == null) {
        fail('Wasm runtime not supported.');
      }

      runner.mapWasmAsyncFunction('hostInc', const [WasmValueType.i64], (
        args,
      ) async {
        await Future<void>.delayed(const Duration(milliseconds: 2));
        return _asInt(args[0]) + 1;
      });
      runner.mapWasmAsyncFunction('hostTriple', const [WasmValueType.i64], (
        args,
      ) async {
        await Future<void>.delayed(const Duration(milliseconds: 2));
        return _asInt(args[0]) * 3;
      });

      var r = await runner.executeFunction(
        '',
        'pipeline',
        positionalParameters: [4],
      );

      // a = 4+1 = 5 ; b = 5*3 = 15 ; return 20.
      expect(r.getValueNoContext(), equals(20));
    });

    test('await with a discarded result (statement await)', () async {
      var runner = await _wasmRunner(r'''
        Future<int> compute(int n) async {
          await hostWait(n);
          return n + 1;
        }
      ''');
      if (runner == null) {
        fail('Wasm runtime not supported.');
      }

      var awaited = false;
      runner.mapWasmAsyncFunction('hostWait', const [WasmValueType.i64], (
        args,
      ) async {
        await Future<void>.delayed(const Duration(milliseconds: 3));
        awaited = true;
        return 0; // result is discarded by the function
      });

      var r = await runner.executeFunction(
        '',
        'compute',
        positionalParameters: [7],
      );

      expect(r.getValueNoContext(), equals(8)); // suspends, then n + 1
      expect(awaited, isTrue);
    });

    test('multi-frame: async fn awaits another async module fn', () async {
      // `outer` awaits `inner` (a module async fn) which awaits a host import.
      // The unwind must propagate through both frames and rewind back down.
      var runner = await _wasmRunner(r'''
        Future<int> inner(int n) async {
          int v = await hostDouble(n);
          return v + 1;
        }

        Future<int> outer(int n) async {
          int a = await inner(n);
          return a + 100;
        }
      ''');
      if (runner == null) {
        fail('Wasm runtime not supported.');
      }

      runner.mapWasmAsyncFunction('hostDouble', const [WasmValueType.i64], (
        args,
      ) async {
        await Future<void>.delayed(const Duration(milliseconds: 4));
        return _asInt(args[0]) * 2;
      });

      var r = await runner.executeFunction(
        '',
        'outer',
        positionalParameters: [5],
      );

      // inner(5): host(5)=10, v=10, return 11. outer: a=11, return 111.
      expect(r.getValueNoContext(), equals(111));
    });

    test('multi-frame: three nested async frames (a->b->c->host)', () async {
      var runner = await _wasmRunner(r'''
        Future<int> c(int n) async {
          int v = await hostInc(n);
          return v;
        }

        Future<int> b(int n) async {
          int v = await c(n);
          return v + 10;
        }

        Future<int> a(int n) async {
          int v = await b(n);
          return v + 100;
        }
      ''');
      if (runner == null) {
        fail('Wasm runtime not supported.');
      }

      runner.mapWasmAsyncFunction('hostInc', const [WasmValueType.i64], (
        args,
      ) async {
        await Future<void>.delayed(const Duration(milliseconds: 3));
        return _asInt(args[0]) + 1;
      });

      var r = await runner.executeFunction('', 'a', positionalParameters: [5]);

      // c(5): host(5)=6. b: 6+10=16. a: 16+100=116.
      expect(r.getValueNoContext(), equals(116));
    });

    test('multi-frame: a frame mixing a leaf and an internal await', () async {
      var runner = await _wasmRunner(r'''
        Future<int> inner(int n) async {
          int v = await hostInc(n);
          return v;
        }

        Future<int> outer(int n) async {
          int x = await hostDouble(n);
          int y = await inner(x);
          return x + y;
        }
      ''');
      if (runner == null) {
        fail('Wasm runtime not supported.');
      }

      runner.mapWasmAsyncFunction('hostDouble', const [WasmValueType.i64], (
        args,
      ) async {
        await Future<void>.delayed(const Duration(milliseconds: 2));
        return _asInt(args[0]) * 2;
      });
      runner.mapWasmAsyncFunction('hostInc', const [WasmValueType.i64], (
        args,
      ) async {
        await Future<void>.delayed(const Duration(milliseconds: 2));
        return _asInt(args[0]) + 1;
      });

      var r = await runner.executeFunction(
        '',
        'outer',
        positionalParameters: [5],
      );

      // x = 2*5 = 10 ; inner(10): 10+1 = 11 ; return 10 + 11 = 21.
      expect(r.getValueNoContext(), equals(21));
    });

    test('await inside a while loop (PC state machine)', () async {
      var runner = await _wasmRunner(r'''
        Future<int> sumTo(int n) async {
          int total = 0;
          int i = 1;
          while (i <= n) {
            int x = await hostId(i);
            total = total + x;
            i = i + 1;
          }
          return total;
        }
      ''');
      if (runner == null) {
        fail('Wasm runtime not supported.');
      }

      var suspends = 0;
      runner.mapWasmAsyncFunction('hostId', const [WasmValueType.i64], (
        args,
      ) async {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        suspends++;
        return _asInt(args[0]);
      });

      var r = await runner.executeFunction(
        '',
        'sumTo',
        positionalParameters: [4],
      );

      expect(r.getValueNoContext(), equals(10)); // 1+2+3+4
      expect(suspends, equals(4), reason: 'one suspension per iteration');
    });

    test('internal await inside a while loop (multi-frame + PC)', () async {
      var runner = await _wasmRunner(r'''
        Future<int> dbl(int v) async {
          int r = await hostDouble(v);
          return r;
        }

        Future<int> sumDoubles(int n) async {
          int total = 0;
          int i = 1;
          while (i <= n) {
            int x = await dbl(i);
            total = total + x;
            i = i + 1;
          }
          return total;
        }
      ''');
      if (runner == null) {
        fail('Wasm runtime not supported.');
      }

      runner.mapWasmAsyncFunction('hostDouble', const [WasmValueType.i64], (
        args,
      ) async {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        return _asInt(args[0]) * 2;
      });

      var r = await runner.executeFunction(
        '',
        'sumDoubles',
        positionalParameters: [3],
      );

      // dbl(1)=2, dbl(2)=4, dbl(3)=6 => 12.
      expect(r.getValueNoContext(), equals(12));
    });

    test('await inside a for loop', () async {
      var runner = await _wasmRunner(r'''
        Future<int> sumTo(int n) async {
          int total = 0;
          for (int i = 1; i <= n; i = i + 1) {
            int x = await hostId(i);
            total = total + x;
          }
          return total;
        }
      ''');
      if (runner == null) {
        fail('Wasm runtime not supported.');
      }
      runner.mapWasmAsyncFunction('hostId', const [WasmValueType.i64], (
        args,
      ) async {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        return _asInt(args[0]);
      });

      var r = await runner.executeFunction(
        '',
        'sumTo',
        positionalParameters: [4],
      );
      expect(r.getValueNoContext(), equals(10)); // 1+2+3+4
    });

    test('await inside if/else branches', () async {
      var runner = await _wasmRunner(r'''
        Future<int> pick(int n) async {
          int r = 0;
          if (n > 2) {
            int x = await hostId(n);
            r = x + 100;
          } else {
            int y = await hostId(n);
            r = y + 1;
          }
          return r;
        }
      ''');
      if (runner == null) {
        fail('Wasm runtime not supported.');
      }
      runner.mapWasmAsyncFunction('hostId', const [WasmValueType.i64], (
        args,
      ) async {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        return _asInt(args[0]);
      });

      var hi = await runner.executeFunction(
        '',
        'pick',
        positionalParameters: [5],
      );
      expect(hi.getValueNoContext(), equals(105)); // then: 5 + 100

      var lo = await runner.executeFunction(
        '',
        'pick',
        positionalParameters: [1],
      );
      expect(lo.getValueNoContext(), equals(2)); // else: 1 + 1
    });

    test('return await (leaf and internal)', () async {
      var runner = await _wasmRunner(r'''
        Future<int> inner(int n) async {
          return await hostId(n);
        }
        Future<int> outer(int n) async {
          return await inner(n);
        }
      ''');
      if (runner == null) {
        fail('Wasm runtime not supported.');
      }
      runner.mapWasmAsyncFunction('hostId', const [WasmValueType.i64], (
        args,
      ) async {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        return _asInt(args[0]) + 1;
      });

      var leaf = await runner.executeFunction(
        '',
        'inner',
        positionalParameters: [7],
      );
      expect(leaf.getValueNoContext(), equals(8)); // return await hostId(7)

      var nested = await runner.executeFunction(
        '',
        'outer',
        positionalParameters: [7],
      );
      expect(nested.getValueNoContext(), equals(8)); // return await inner(7)
    });

    test('assignment await inside a loop', () async {
      var runner = await _wasmRunner(r'''
        Future<int> f(int n) async {
          int t = 0;
          int i = 1;
          while (i <= n) {
            t = await hostId(i);
            i = i + 1;
          }
          return t;
        }
      ''');
      if (runner == null) {
        fail('Wasm runtime not supported.');
      }
      runner.mapWasmAsyncFunction('hostId', const [WasmValueType.i64], (
        args,
      ) async {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        return _asInt(args[0]);
      });

      var r = await runner.executeFunction('', 'f', positionalParameters: [3]);
      expect(r.getValueNoContext(), equals(3)); // t = hostId(3)
    });

    test('await in else-if chain', () async {
      var runner = await _wasmRunner(r'''
        Future<int> pick(int n) async {
          int r = 0;
          if (n > 10) {
            int x = await hostId(n);
            r = x + 1000;
          } else if (n > 5) {
            int y = await hostId(n);
            r = y + 100;
          } else {
            int z = await hostId(n);
            r = z + 1;
          }
          return r;
        }
      ''');
      if (runner == null) {
        fail('Wasm runtime not supported.');
      }
      runner.mapWasmAsyncFunction('hostId', const [WasmValueType.i64], (
        args,
      ) async {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        return _asInt(args[0]);
      });

      expect(
        (await runner.executeFunction(
          '',
          'pick',
          positionalParameters: [12],
        )).getValueNoContext(),
        equals(1012),
      );
      expect(
        (await runner.executeFunction(
          '',
          'pick',
          positionalParameters: [7],
        )).getValueNoContext(),
        equals(107),
      );
      expect(
        (await runner.executeFunction(
          '',
          'pick',
          positionalParameters: [2],
        )).getValueNoContext(),
        equals(3),
      );
    });

    test('a non-async Wasm function still runs synchronously', () async {
      var runner = await _wasmRunner(r'''
        int addOne(int n) {
          return n + 1;
        }
      ''');
      if (runner == null) {
        fail('Wasm runtime not supported.');
      }

      var r = await runner.executeFunction(
        '',
        'addOne',
        positionalParameters: [41],
      );

      expect(r.getValueNoContext(), equals(42));
    });
  });
}
