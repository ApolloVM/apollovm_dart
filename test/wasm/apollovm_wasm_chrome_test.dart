@TestOn('chrome')
@Tags(['wasm', 'wasm-chrome', 'dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Parity harness that runs in the browser: loads Dart source, executes
/// [functionName] via the AST interpreter AND via the Wasm module compiled and
/// run through ApolloVM's web runtime (the browser's own `WebAssembly` engine),
/// asserting both match. This proves the current linear-memory Wasm output is
/// accepted and executed by Chrome's engine.
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
  expect(rt.isSupported, isTrue, reason: 'Browser WasmRuntime unsupported');

  var vmWasm = ApolloVM();
  var loadOK = await vmWasm.loadCodeUnit(
    BinaryCodeUnit('wasm', compiled!.output(), id: 'test.wasm', namespace: ''),
  );
  expect(loadOK, isTrue, reason: 'Compiled Wasm failed to load in Chrome');

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
      reason: 'CHROME-WASM $functionName(${e.key})',
    );
  }
}

void main() {
  group('Chrome linear-memory Wasm parity', () {
    test('int arithmetic', () async {
      await _testWasm(
        r'''
        int calc(int a, int b) {
          int x = a + b * 2;
          return x - 1;
        }
      ''',
        'calc',
        {
          [3, 4]: 10,
          [10, 0]: 9,
        },
      );
    });

    test('while loop with accumulator and return', () async {
      await _testWasm(
        r'''
        int sumTo(int n) {
          int total = 0;
          int i = 1;
          while (i <= n) {
            total = total + i;
            i = i + 1;
          }
          return total;
        }
      ''',
        'sumTo',
        {
          [4]: 10,
          [1]: 1,
          [0]: 0,
        },
      );
    });
  });
}
