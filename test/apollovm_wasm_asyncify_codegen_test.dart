@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Validates the **generator-emitted** Asyncify transform (real suspension):
/// the Wasm generator compiles an `async` function with a single statement-level
/// `await` of an external host call into an unwind/rewind state machine. Here a
/// host-side driver runs that machine against the live `WasmRuntime`, awaiting a
/// real Dart `Future` between unwind and rewind.
///
/// Asyncify control region (must match `WasmModuleContext`):
const _asyState = 8; //  i32: 0=normal, 1=unwound, 2=rewinding
const _asySp = 12; //    i32: frame-stack pointer
const _asyResult = 16; // i64: host writes the awaited value here
const _asyStackBase = 24; // frame stack grows from here

/// Compiles [dartSource] to Wasm bytes.
Future<Uint8List> _compile(String dartSource) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(
    SourceCodeUnit('dart', dartSource, id: 'test'),
  );
  expect(ok, isTrue, reason: "Can't load Dart source");

  var storage = vm.generateAllIn<BytesOutput>('wasm');
  var modules = await storage.allEntries();
  for (var ns in modules.entries) {
    for (var m in ns.value.entries) {
      return m.value.output();
    }
  }
  fail('No compiled Wasm module');
}

/// Drives an Asyncify export to completion. [hostCompute] turns the suspending
/// import's captured args into a real `Future` (the actual async work).
Future<int> _drive(
  WasmRuntime rt,
  Uint8List wasm,
  String importName,
  String functionName,
  List<Object?> args,
  Future<int> Function(List<Object?> importArgs) hostCompute, {
  void Function()? onSuspend,
}) async {
  List<Object?>? pendingArgs;

  var module = await rt.loadModule(
    'asyncify-codegen-$functionName',
    wasm,
    hostImports: {
      'env': {
        // Suspending import: records the args and returns; the generated code
        // then unwinds. The real value is delivered on rewind via memory.
        importName: WasmHostFunction(
          params: const [WasmValueType.i64],
          results: const [],
          callback: (a) {
            pendingArgs = a;
            return null;
          },
        ),
      },
    },
  );

  // Initialize the frame-stack pointer once.
  {
    final mem0 = module.readMemory()!;
    mem0.buffer
        .asByteData(mem0.offsetInBytes, mem0.lengthInBytes)
        .setInt32(_asySp, _asyStackBase, Endian.little);
  }

  while (true) {
    final ret = module.invokeExport(functionName, args) as int;

    final mem = module.readMemory()!;
    final bd = mem.buffer.asByteData(mem.offsetInBytes, mem.lengthInBytes);

    if (bd.getInt32(_asyState, Endian.little) == 1) {
      onSuspend?.call();
      final resolved = await hostCompute(pendingArgs!); // real async gap
      bd.setInt64(_asyResult, resolved, Endian.little);
      bd.setInt32(_asyState, 2, Endian.little); // rewinding
      continue;
    }

    return ret; // completed
  }
}

void main() {
  late WasmRuntime rt;
  setUpAll(() => rt = WasmRuntime()..ensureBooted());

  group('Wasm Asyncify codegen (generated, real suspension)', () {
    test('async fn awaiting an external host call really suspends', () async {
      if (!rt.isSupported) {
        fail('Wasm runtime not supported (run `dart run wasm_run:setup`).');
      }

      // `hostDouble` is NOT a module function => compiled as a suspending host
      // import; the single statement-level await triggers the Asyncify path.
      final wasm = await _compile(r'''
        Future<int> compute(int n) async {
          int v = await hostDouble(n);
          return v + 1;
        }
      ''');

      var suspends = 0;
      var awaited = false;

      final result = await _drive(rt, wasm, 'hostDouble', 'compute', [10], (
        importArgs,
      ) async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        awaited = true;
        return (importArgs[0] as int) * 2; // double the awaited arg
      }, onSuspend: () => suspends++);

      // v = host(10) = 20 ; return v + 1 = 21.
      expect(result, equals(21));
      expect(suspends, equals(1), reason: 'one real suspension');
      expect(awaited, isTrue, reason: 'host awaited a real Future');
    });

    test('pre/post-await locals survive the suspension', () async {
      if (!rt.isSupported) {
        fail('Wasm runtime not supported (run `dart run wasm_run:setup`).');
      }

      // `base` is set before the await and must survive the unwind/rewind.
      final wasm = await _compile(r'''
        Future<int> compute(int n) async {
          int base = n * 100;
          int v = await hostDouble(n);
          return base + v;
        }
      ''');

      final result = await _drive(rt, wasm, 'hostDouble', 'compute', [3], (
        importArgs,
      ) async {
        await Future<void>.delayed(const Duration(milliseconds: 3));
        return (importArgs[0] as int) * 2;
      });

      // base = 300 ; v = 6 ; return 306.
      expect(result, equals(306));
    });

    test(
      'multiple awaits in one function (br_table resume dispatch)',
      () async {
        if (!rt.isSupported) {
          fail('Wasm runtime not supported.');
        }

        // Two sequential awaits => two real suspensions, resumed via br_table.
        final wasm = await _compile(r'''
        Future<int> compute(int n) async {
          int a = await hostDouble(n);
          int b = await hostDouble(a);
          return a + b;
        }
      ''');

        var suspends = 0;
        final result = await _drive(rt, wasm, 'hostDouble', 'compute', [5], (
          importArgs,
        ) async {
          await Future<void>.delayed(const Duration(milliseconds: 2));
          return (importArgs[0] as int) * 2;
        }, onSuspend: () => suspends++);

        // a = 2*5 = 10 ; b = 2*10 = 20 ; return 30.
        expect(result, equals(30));
        expect(suspends, equals(2), reason: 'two real suspensions');
      },
    );

    test('awaits with statements interleaved + locals across each', () async {
      if (!rt.isSupported) {
        fail('Wasm runtime not supported.');
      }

      final wasm = await _compile(r'''
        Future<int> compute(int n) async {
          int base = n * 100;
          int a = await hostDouble(n);
          int mid = base + a;
          int b = await hostDouble(mid);
          return mid + b;
        }
      ''');

      var suspends = 0;
      final result = await _drive(rt, wasm, 'hostDouble', 'compute', [2], (
        importArgs,
      ) async {
        await Future<void>.delayed(const Duration(milliseconds: 2));
        return (importArgs[0] as int) * 2;
      }, onSuspend: () => suspends++);

      // base=200; a=4; mid=204; b=408; return mid+b = 612.
      expect(result, equals(612));
      expect(suspends, equals(2));
    });

    test('two generated computations interleave by host delay', () async {
      if (!rt.isSupported) {
        fail('Wasm runtime not supported (run `dart run wasm_run:setup`).');
      }

      final wasm = await _compile(r'''
        Future<int> compute(int n) async {
          int v = await hostDouble(n);
          return v + 1;
        }
      ''');

      final order = <int>[];

      Future<int> run(int n, int delayMs, int id) =>
          _drive(rt, wasm, 'hostDouble', 'compute', [n], (importArgs) async {
            await Future<void>.delayed(Duration(milliseconds: delayMs));
            order.add(id);
            return (importArgs[0] as int) * 2;
          });

      final results = await Future.wait([run(10, 30, 1), run(20, 5, 2)]);

      expect(results[0], equals(21));
      expect(results[1], equals(41));
      expect(order, equals([2, 1]), reason: 'real concurrent suspension');
    });
  });
}
