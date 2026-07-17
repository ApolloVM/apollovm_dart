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

  // ASCII case conversion: a fresh `[len:i32][utf8]` buffer with each ASCII
  // letter shifted by the case bit (0x20); other bytes copied unchanged.
  group('Wasm String.toUpperCase / toLowerCase (ASCII)', () {
    test('toUpperCase', () async {
      await _testWasm(
        "String run() { var s = 'hello'; return s.toUpperCase(); }",
        'run',
        {[]: 'HELLO'},
      );
    });

    test('toUpperCase keeps non-letters', () async {
      await _testWasm(
        "String run() { var s = 'Hello World 123!'; return s.toUpperCase(); }",
        'run',
        {[]: 'HELLO WORLD 123!'},
      );
    });

    test('toLowerCase', () async {
      await _testWasm(
        "String run() { var s = 'HELLO'; return s.toLowerCase(); }",
        'run',
        {[]: 'hello'},
      );
    });

    test('toLowerCase keeps non-letters', () async {
      await _testWasm(
        "String run() { var s = 'Hello WORLD 9'; return s.toLowerCase(); }",
        'run',
        {[]: 'hello world 9'},
      );
    });

    test('empty string', () async {
      await _testWasm(
        "String run() { var s = ''; return s.toUpperCase(); }",
        'run',
        {[]: ''},
      );
    });

    test('result composes with concatenation', () async {
      await _testWasm(
        "String run() { var s = 'ab'; return s.toUpperCase() + '!'; }",
        'run',
        {[]: 'AB!'},
      );
    });

    test('does not mutate the receiver', () async {
      await _testWasm(
        "String run() { var s = 'abc'; var u = s.toUpperCase(); return s + u; }",
        'run',
        {[]: 'abcABC'},
      );
    });
  });
}
