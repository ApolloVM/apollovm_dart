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

  // String methods over the `[len:i32][utf8]` layout — byte-indexed, so exact for
  // ASCII text. The receiver must be a named local (chaining onto a method result
  // is a separate limitation).
  group('Wasm String methods', () {
    test('substring(start, end)', () async {
      await _testWasm(
        "String run() { var s = 'hello'; return s.substring(1, 3); }",
        'run',
        {[]: 'el'},
      );
    });

    test('substring(start) to end', () async {
      await _testWasm(
        "String run() { var s = 'hello'; return s.substring(2); }",
        'run',
        {[]: 'llo'},
      );
    });

    test('substring full and empty slices', () async {
      await _testWasm(
        "String run() { var s = 'hello'; return s.substring(0, 5); }",
        'run',
        {[]: 'hello'},
      );
      await _testWasm(
        "String run() { var s = 'hello'; return s.substring(2, 2); }",
        'run',
        {[]: ''},
      );
    });

    test('substring result length', () async {
      await _testWasm(
        "int run() { var s = 'hello'; var t = s.substring(1, 4);"
            " return t.length; }",
        'run',
        {[]: 3},
      );
    });

    test('codeUnitAt', () async {
      await _testWasm(
        "int run() { var s = 'ABC'; return s.codeUnitAt(0); }",
        'run',
        {[]: 65},
      );
      await _testWasm(
        "int run() { var s = 'ABC'; return s.codeUnitAt(2); }",
        'run',
        {[]: 67},
      );
    });

    test('contains', () async {
      await _testWasm(
        "bool run() { var s = 'hello'; return s.contains('ell'); }",
        'run',
        {[]: true},
      );
    });

    test('contains — absent / pattern longer than string', () async {
      await _testWasm(
        "bool run() { var s = 'hello'; return s.contains('xyz'); }",
        'run',
        {[]: false},
      );
      await _testWasm(
        "bool run() { var s = 'hi'; return s.contains('hello'); }",
        'run',
        {[]: false},
      );
    });

    test('contains used in a condition', () async {
      await _testWasm(
        "int run() { var s = 'hello';"
            " if (s.contains('ell')) { return 1; } return 0; }",
        'run',
        {[]: 1},
      );
    });

    test('indexOf — found', () async {
      await _testWasm(
        "int run() { var s = 'hello'; return s.indexOf('l'); }",
        'run',
        {[]: 2},
      );
      await _testWasm(
        "int run() { var s = 'hello'; return s.indexOf('lo'); }",
        'run',
        {[]: 3},
      );
      await _testWasm(
        "int run() { var s = 'hello'; return s.indexOf('h'); }",
        'run',
        {[]: 0},
      );
    });

    test('indexOf — not found returns -1', () async {
      await _testWasm(
        "int run() { var s = 'hello'; return s.indexOf('z'); }",
        'run',
        {[]: -1},
      );
    });

    test('startsWith', () async {
      await _testWasm(
        "bool run() { var s = 'hello'; return s.startsWith('he'); }",
        'run',
        {[]: true},
      );
      await _testWasm(
        "bool run() { var s = 'hello'; return s.startsWith('lo'); }",
        'run',
        {[]: false},
      );
    });

    test('startsWith — pattern longer than string', () async {
      await _testWasm(
        "bool run() { var s = 'hi'; return s.startsWith('hello'); }",
        'run',
        {[]: false},
      );
    });

    test('endsWith', () async {
      await _testWasm(
        "bool run() { var s = 'hello'; return s.endsWith('lo'); }",
        'run',
        {[]: true},
      );
      await _testWasm(
        "bool run() { var s = 'hello'; return s.endsWith('he'); }",
        'run',
        {[]: false},
      );
    });
  });
}
