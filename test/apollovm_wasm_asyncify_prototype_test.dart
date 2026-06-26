@TestOn('vm')
@Tags(['wasm'])
library;

import 'dart:typed_data';

import 'package:apollovm/apollovm.dart';
// Internal opcode/byte helpers (same-package import, allowed in this package's
// own tests).
import 'package:apollovm/src/languages/wasm/wasm.dart';
import 'package:test/test.dart';

/// Asyncify real-suspension PROTOTYPE for the ApolloVM Wasm backend.
///
/// WebAssembly has no native async/await, and ApolloVM's Wasm runtime is
/// synchronous. This prototype proves that **real suspension** is achievable
/// with the existing runtime using the Asyncify technique: a running Wasm call
/// unwinds the stack back to the host (saving each frame's live locals to
/// linear memory), the host awaits a real Dart `Future`, then re-invokes the
/// export which rewinds — restoring locals and resuming exactly where it
/// stopped.
///
/// The module below is hand-assembled (two frames, `runner` -> `step`, one
/// suspension point) to demonstrate the mechanism end-to-end against the real
/// `WasmRuntime`. It deliberately simplifies full Binaryen Asyncify:
///   * a single suspension point, so the resume "program counter" is implicit
///     (before/after the one `await`) rather than a per-frame call index;
///   * the unwind/rewind bookkeeping is emitted inline after the suspend call
///     rather than inside imported `asyncify_*` helpers;
///   * a flat, fixed memory layout instead of a growable Asyncify stack.
/// Integrating this into the code generator (general bodies, many awaits,
/// `br_table` resume dispatch, a real frame stack) is the follow-up.

// --- Fixed linear-memory layout (byte offsets in page 0) ---
const _state = 0; //   i32: 0=normal, 1=unwound(suspended), 2=rewinding
const _arg = 8; //     i64: argument handed to the host at the suspend point
const _result = 16; // i64: resolved value written back by the host
const _savedA = 24; // i64: `runner`'s live local across the suspension
const _savedB = 32; // i64: `step`'s live local across the suspension
const _counter = 40; // i32: counts prologue executions (side-effect probe)

/// Builds the prototype module. Function indices: import `env.suspend` = 0,
/// `runner` = 1, `step` = 2. Exports: `runner` and `memory`.
Uint8List _buildModule() {
  // step(i64 x) -> i64 : computes b = x + 7, suspends, resumes to b + result.
  final step = <int>[
    // if (load i32 STATE == 2) { rewind }
    ...Wasm32.i32Const(0), ...Wasm32.i32Load(2, _state),
    ...Wasm32.i32Const(2), Wasm32.i32Equals,
    ...Wasm.ifInstruction(WasmType.voidType),
    // b = SAVED_B
    ...Wasm32.i32Const(0), ...Wasm64.i64Load(3, _savedB), ...Wasm.localSet(1),
    // return b + RESULT  (resume point — after the await)
    ...Wasm.localGet(1),
    ...Wasm32.i32Const(0), ...Wasm64.i64Load(3, _result), Wasm64.i64Add,
    Wasm.functionReturn,
    Wasm.end,
    // --- normal path ---
    // COUNTER += 1  (side effect that must run exactly once)
    ...Wasm32.i32Const(0),
    ...Wasm32.i32Const(0), ...Wasm32.i32Load(2, _counter),
    ...Wasm32.i32Const(1), Wasm32.i32Add,
    ...Wasm32.i32Store(2, _counter),
    // b = x + 7
    ...Wasm.localGet(0), ...Wasm64.i64Const(7), Wasm64.i64Add,
    ...Wasm.localSet(1),
    // ARG = x  (tell the host what to await on)
    ...Wasm32.i32Const(0), ...Wasm.localGet(0), ...Wasm64.i64Store(3, _arg),
    // await: call the host suspend marker
    ...Wasm.localGet(0), ...Wasm.call(0),
    // unwind: SAVED_B = b; STATE = 1; return dummy
    ...Wasm32.i32Const(0), ...Wasm.localGet(1), ...Wasm64.i64Store(3, _savedB),
    ...Wasm32.i32Const(0), ...Wasm32.i32Const(1), ...Wasm32.i32Store(2, _state),
    ...Wasm64.i64Const(0),
    Wasm.end,
  ];

  // runner(i64 x) -> i64 : a = x + 100, calls step, returns a + step-result.
  final runner = <int>[
    // if (load i32 STATE == 2) { rewind }
    ...Wasm32.i32Const(0), ...Wasm32.i32Load(2, _state),
    ...Wasm32.i32Const(2), Wasm32.i32Equals,
    ...Wasm.ifInstruction(WasmType.voidType),
    // a = SAVED_A
    ...Wasm32.i32Const(0), ...Wasm64.i64Load(3, _savedA), ...Wasm.localSet(1),
    // r = step(x)  (step rewinds and returns its resolved result)
    ...Wasm.localGet(0), ...Wasm.call(2), ...Wasm.localSet(2),
    // STATE = 0  (suspension complete)
    ...Wasm32.i32Const(0), ...Wasm32.i32Const(0), ...Wasm32.i32Store(2, _state),
    // return a + r
    ...Wasm.localGet(1), ...Wasm.localGet(2), Wasm64.i64Add,
    Wasm.functionReturn,
    Wasm.end,
    // --- normal path ---
    // a = x + 100
    ...Wasm.localGet(0), ...Wasm64.i64Const(100), Wasm64.i64Add,
    ...Wasm.localSet(1),
    // SAVED_A = a
    ...Wasm32.i32Const(0), ...Wasm.localGet(1), ...Wasm64.i64Store(3, _savedA),
    // r = step(x)
    ...Wasm.localGet(0), ...Wasm.call(2), ...Wasm.localSet(2),
    // if (STATE == 1) { propagate unwind: return dummy }
    ...Wasm32.i32Const(0), ...Wasm32.i32Load(2, _state),
    ...Wasm32.i32Const(1), Wasm32.i32Equals,
    ...Wasm.ifInstruction(WasmType.voidType),
    ...Wasm64.i64Const(0), Wasm.functionReturn,
    Wasm.end,
    // return a + r  (step completed without suspending)
    ...Wasm.localGet(1), ...Wasm.localGet(2), Wasm64.i64Add,
    Wasm.end,
  ];

  // Code-section bodies: local declarations (vec of (count, valtype) groups)
  // followed by the instructions.
  final stepBody = <int>[
    ..._lebU(1), ..._lebU(1), WasmType.i64Type.value, // 1 group: 1 i64 (b)
    ...step,
  ];
  final runnerBody = <int>[
    ..._lebU(1), ..._lebU(2), WasmType.i64Type.value, // 1 group: 2 i64 (a, r)
    ...runner,
  ];

  return _assembleModule(
    types: [
      // type 0: (i64) -> ()   [suspend]
      [Wasm.functionType, ..._lebU(1), WasmType.i64Type.value, 0],
      // type 1: (i64) -> (i64)  [runner, step]
      [
        Wasm.functionType,
        ..._lebU(1),
        WasmType.i64Type.value,
        ..._lebU(1),
        WasmType.i64Type.value,
      ],
    ],
    importSuspendTypeIdx: 0,
    funcTypeIdxs: const [1, 1], // runner, step
    exports: [
      ('runner', Wasm.externalKindFunction, 1),
      ('memory', Wasm.externalKindMemory, 0),
    ],
    bodies: [runnerBody, stepBody],
  );
}

/// Assembles a minimal module: type, import (`env.suspend`), function, memory
/// (1 page, exported), export, and code sections.
Uint8List _assembleModule({
  required List<List<int>> types,
  required int importSuspendTypeIdx,
  required List<int> funcTypeIdxs,
  required List<(String, int, int)> exports,
  required List<List<int>> bodies,
}) {
  final out = <int>[...Wasm.magicModuleHeader, ...Wasm.moduleVersion];

  // Type section.
  out.addAll(_section(Wasm.sectionType, _vec(types)));

  // Import section: env.suspend (function, type index).
  final import = <int>[
    ...Wasm.encodeString('env'),
    ...Wasm.encodeString('suspend'),
    Wasm.externalKindFunction,
    ..._lebU(importSuspendTypeIdx),
  ];
  out.addAll(_section(Wasm.sectionImport, _vec([import])));

  // Function section: type index per defined function.
  out.addAll(
    _section(Wasm.sectionFunction, _vec(funcTypeIdxs.map(_lebU).toList())),
  );

  // Memory section: 1 memory, limits {min: 1} (flags 0x00).
  out.addAll(
    _section(
      Wasm.sectionMemory,
      _vec([
        <int>[0x00, 0x01],
      ]),
    ),
  );

  // Export section.
  final exportEntries = exports
      .map((e) => <int>[...Wasm.encodeString(e.$1), e.$2, ..._lebU(e.$3)])
      .toList();
  out.addAll(_section(Wasm.sectionExport, _vec(exportEntries)));

  // Code section: each body (locals + instructions + trailing `end`) is
  // length-prefixed.
  final codeEntries = bodies
      .map((b) => <int>[..._lebU(b.length), ...b])
      .toList();
  out.addAll(_section(Wasm.sectionCode, _vec(codeEntries)));

  return Uint8List.fromList(out);
}

List<int> _section(int id, List<int> payload) => [
  id,
  ..._lebU(payload.length),
  ...payload,
];

List<int> _vec(List<List<int>> items) => [
  ..._lebU(items.length),
  for (final it in items) ...it,
];

List<int> _lebU(int v) {
  final out = <int>[];
  var x = v;
  do {
    var b = x & 0x7f;
    x >>= 7;
    if (x != 0) b |= 0x80;
    out.add(b);
  } while (x != 0);
  return out;
}

/// Drives an Asyncify-style export to completion, awaiting [hostCompute] (a real
/// `Future`) at each suspension point. Returns the export's final result.
/// [onSuspend] fires once per suspension (for observing real interleaving).
Future<int> _runAsyncify(
  WasmModule module,
  int x,
  Future<int> Function(int arg) hostCompute, {
  void Function()? onSuspend,
}) async {
  while (true) {
    final ret = module.invokeExport('runner', [x]) as int;

    final mem = module.readMemory()!;
    final bd = mem.buffer.asByteData(mem.offsetInBytes, mem.lengthInBytes);

    final state = bd.getInt32(_state, Endian.little);
    if (state == 1) {
      // Unwound: the Wasm call returned to the host mid-execution.
      onSuspend?.call();
      final arg = bd.getInt64(_arg, Endian.little);
      final resolved = await hostCompute(arg); // <-- REAL async suspension
      bd.setInt64(_result, resolved, Endian.little);
      bd.setInt32(_state, 2, Endian.little); // rewinding
      continue;
    }

    return ret; // state == 0: completed normally
  }
}

Future<WasmModule> _loadModule(WasmRuntime rt, String name) {
  return rt.loadModule(
    name,
    _buildModule(),
    hostImports: {
      'env': {
        // The suspend marker: the unwind bookkeeping is done inline in Wasm, so
        // the host callback is a no-op (it just has to satisfy the import).
        'suspend': WasmHostFunction(
          params: const [WasmValueType.i64],
          results: const [],
          callback: (args) => null,
        ),
      },
    },
  );
}

int _counterOf(WasmModule m) {
  final mem = m.readMemory()!;
  final bd = mem.buffer.asByteData(mem.offsetInBytes, mem.lengthInBytes);
  return bd.getInt32(_counter, Endian.little);
}

void main() {
  late WasmRuntime rt;

  setUpAll(() {
    rt = WasmRuntime()..ensureBooted();
  });

  group('Wasm Asyncify prototype (real suspension)', () {
    test('suspends to the host, awaits a real Future, and rewinds', () async {
      if (!rt.isSupported) {
        fail('Wasm runtime not supported (run `dart run wasm_run:setup`).');
      }

      final module = await _loadModule(rt, 'asyncify-1');

      var suspends = 0;
      var hostResumedAsync = false;

      final result = await _runAsyncify(module, 10, (arg) async {
        // A genuine async gap: the Wasm stack is unwound while we await.
        await Future<void>.delayed(const Duration(milliseconds: 5));
        hostResumedAsync = true;
        return arg * 2; // host injects 2*arg back into the computation
      }, onSuspend: () => suspends++);

      // a = x+100 = 110 ; b = x+7 = 17 ; host result = 2x = 20.
      // final = a + (b + result) = 110 + 17 + 20 = 147.
      expect(result, equals(147));
      expect(suspends, equals(1), reason: 'exactly one suspension point');
      expect(hostResumedAsync, isTrue, reason: 'host actually awaited');
      // Side-effecting prologue ran exactly once — proving rewind skipped the
      // already-executed code instead of re-running it.
      expect(_counterOf(module), equals(1));
    });

    test('two suspended computations interleave by host delay', () async {
      if (!rt.isSupported) {
        fail('Wasm runtime not supported (run `dart run wasm_run:setup`).');
      }

      // Independent instances => independent linear memory / Asyncify state.
      final m1 = await _loadModule(rt, 'asyncify-slow');
      final m2 = await _loadModule(rt, 'asyncify-fast');

      final completionOrder = <int>[];

      Future<int> drive(WasmModule m, int x, int delayMs, int id) {
        return _runAsyncify(m, x, (arg) async {
          await Future<void>.delayed(Duration(milliseconds: delayMs));
          completionOrder.add(id);
          return arg * 2;
        });
      }

      // Both start (and suspend) before either host Future resolves; the 5ms
      // one resolves first, proving real concurrent suspension.
      final results = await Future.wait([
        drive(m1, 10, 30, 1), // slow
        drive(m2, 20, 5, 2), // fast
      ]);

      expect(results[0], equals(147)); // 4*10 + 107
      expect(results[1], equals(187)); // 4*20 + 107
      expect(completionOrder, equals([2, 1]));
    });
  });
}
