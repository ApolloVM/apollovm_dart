@TestOn('vm')
@Tags(['wasm', 'dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

import 'wasm_runtime_setup.dart';

/// Compiles [code] to Wasm and runs [functionName] through both the AST
/// interpreter and the compiled+executed module, asserting every entry in
/// [executions].
Future<void> _testWasm(
  String code,
  String functionName,
  Map<List, Object?> executions,
) async {
  var vm = ApolloVM();
  expect(
    await vm.loadCodeUnit(SourceCodeUnit('dart', code, id: 'test')),
    isTrue,
    reason: "Can't load Dart source",
  );

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
  BytesOutput? compiled;
  for (var ns in (await storageWasm.allEntries()).values) {
    for (var m in ns.values) {
      compiled ??= m;
    }
  }
  expect(compiled, isNotNull, reason: 'No compiled Wasm module');

  var vmWasm = ApolloVM();
  expect(
    await vmWasm.loadCodeUnit(
      BinaryCodeUnit(
        'wasm',
        compiled!.output(),
        id: 'test.wasm',
        namespace: '',
      ),
    ),
    isTrue,
    reason: 'Compiled Wasm failed to load',
  );
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

  // A String is stored as `[len:i32][utf8]`; `.length`/`.isEmpty`/`.isNotEmpty`
  // read the header length word (ASCII byte count == Dart code-unit count).
  group('Wasm String .length / .isEmpty / .isNotEmpty', () {
    test('.length of a non-empty string', () async {
      await _testWasm(
        "int run() { var s = 'hello'; return s.length; }",
        'run',
        {[]: 5},
      );
    });

    test('.length of an empty string', () async {
      await _testWasm("int run() { var s = ''; return s.length; }", 'run', {
        []: 0,
      });
    });

    test('.length used inside an arithmetic expression', () async {
      await _testWasm(
        "int run() { var s = 'abc'; return s.length + 1; }",
        'run',
        {[]: 4},
      );
    });

    test('.isEmpty', () async {
      await _testWasm(
        "bool run(int n) { var s = n > 0 ? 'x' : ''; return s.isEmpty; }",
        'run',
        {
          [1]: false,
          [0]: true,
        },
      );
    });

    test('.isNotEmpty', () async {
      await _testWasm(
        "bool run() { var s = 'hi'; return s.isNotEmpty; }",
        'run',
        {[]: true},
      );
    });
  });
}
