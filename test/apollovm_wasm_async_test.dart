@TestOn('vm')
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Compiles [code] to Wasm, executes [functionName] both via the AST
/// interpreter and the compiled+executed Wasm module, and asserts every
/// execution matches the expected result in [executions].
///
/// The Wasm backend executes synchronously, so `async` functions collapse
/// `Future<T>` to `T` and `await` is a value pass-through (see
/// `effectiveReturnType` / `generateASTExpressionAwait` in the Wasm generator).
/// This validates that compute-style async Dart code compiles to Wasm and
/// produces the same result as the AST interpreter.
Future<void> _testWasm(
  String code,
  String functionName,
  Map<List, Object?> executions,
) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', code, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source");

  // 1) AST interpreter (async entry is awaited to a resolved value by execute).
  var astRunner = vm.createRunner('dart')!;
  for (var e in executions.entries) {
    var r = await astRunner.executeFunction(
      '',
      functionName,
      positionalParameters: e.key,
    );
    expect(
      await r.getValueNoContext(),
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
  group('Wasm async/await (synchronous collapse)', () {
    test('async function returning a computed value', () async {
      await _testWasm(
        r'''
        Future<int> calc(int n) async {
          return n * 2;
        }
      ''',
        'calc',
        {
          [21]: 42,
          [0]: 0,
          [5]: 10,
        },
      );
    });

    test('await another async function', () async {
      await _testWasm(
        r'''
        Future<int> dbl(int n) async {
          return n * 2;
        }

        Future<int> calc(int n) async {
          // Explicit type: the Wasm backend can't statically infer `var x` from
          // a function-call result (pre-existing limitation, not async-related).
          int v = await dbl(n);
          return v + 1;
        }
      ''',
        'calc',
        {
          [10]: 21,
          [0]: 1,
        },
      );
    });

    test('await inside an expression', () async {
      await _testWasm(
        r'''
        Future<int> dbl(int n) async {
          return n * 2;
        }

        Future<int> calc(int n) async {
          return await dbl(n) + n;
        }
      ''',
        'calc',
        {
          [10]: 30,
          [3]: 9,
        },
      );
    });

    test('async with a loop body', () async {
      await _testWasm(
        r'''
        Future<int> sumTo(int n) async {
          var total = 0;
          for (var i = 1; i <= n; i = i + 1) {
            total = total + i;
          }
          return total;
        }
      ''',
        'sumTo',
        {
          [5]: 15,
          [10]: 55,
        },
      );
    });
  });
}
