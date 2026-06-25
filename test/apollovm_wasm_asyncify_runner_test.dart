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
