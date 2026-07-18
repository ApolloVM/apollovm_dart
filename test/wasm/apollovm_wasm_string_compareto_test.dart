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

  var storage = vm.generateAllIn<BytesOutput>('wasm');
  BytesOutput? compiled;
  for (var ns in (await storage.allEntries()).values) {
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

  // String.compareTo — lexicographic byte comparison returning -1/0/1, matching
  // the interpreter (which gained `String.compareTo` in the same change).
  group('Wasm String.compareTo', () {
    test('less than', () async {
      await _testWasm(
        "int run() { var s = 'abc'; return s.compareTo('abd'); }",
        'run',
        {[]: -1},
      );
    });

    test('equal', () async {
      await _testWasm(
        "int run() { var s = 'abc'; return s.compareTo('abc'); }",
        'run',
        {[]: 0},
      );
    });

    test('greater than', () async {
      await _testWasm(
        "int run() { var s = 'abd'; return s.compareTo('abc'); }",
        'run',
        {[]: 1},
      );
    });

    test('a prefix sorts before the longer string', () async {
      await _testWasm(
        "int run() { var s = 'ab'; return s.compareTo('abc'); }",
        'run',
        {[]: -1},
      );
      await _testWasm(
        "int run() { var s = 'abc'; return s.compareTo('ab'); }",
        'run',
        {[]: 1},
      );
    });

    test('empty string sorts first', () async {
      await _testWasm(
        "int run() { var s = ''; return s.compareTo('a'); }",
        'run',
        {[]: -1},
      );
      await _testWasm(
        "int run() { var s = ''; return s.compareTo(''); }",
        'run',
        {[]: 0},
      );
    });

    test('first differing byte decides', () async {
      await _testWasm(
        "int run() { var s = 'axz'; return s.compareTo('ayz'); }",
        'run',
        {[]: -1},
      );
    });
  });
}
