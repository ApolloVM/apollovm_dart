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

  // Dart's `String[i]` returns the character at [i] as a length-1 String. Added
  // to the interpreter core (which lacked it) and the Wasm backend so both agree.
  group('Wasm String index (s[i])', () {
    test('first character', () async {
      await _testWasm("String run() { var s = 'abc'; return s[0]; }", 'run', {
        []: 'a',
      });
    });

    test('middle and last characters', () async {
      await _testWasm("String run() { var s = 'hello'; return s[1]; }", 'run', {
        []: 'e',
      });
      await _testWasm("String run() { var s = 'hello'; return s[4]; }", 'run', {
        []: 'o',
      });
    });

    test('index from a variable', () async {
      await _testWasm(
        "String run() { var s = 'hello'; var i = 2; return s[i]; }",
        'run',
        {[]: 'l'},
      );
    });

    test('index from an expression', () async {
      await _testWasm(
        "String run() { var s = 'hello'; return s[1 + 1]; }",
        'run',
        {[]: 'l'},
      );
    });
  });
}
