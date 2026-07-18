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

  // More String methods (byte ops over `[len][utf8]`, ASCII-exact): trim family,
  // padLeft/padRight.
  group('Wasm String methods (trim/pad)', () {
    test('trim', () async {
      await _testWasm(
        "String run() { var s = '  hi  '; return s.trim(); }",
        'run',
        {[]: 'hi'},
      );
    });

    test('trim — no whitespace is a no-op', () async {
      await _testWasm(
        "String run() { var s = 'hi'; return s.trim(); }",
        'run',
        {[]: 'hi'},
      );
    });

    test('trim — all whitespace yields empty', () async {
      await _testWasm(
        "int run() { var s = '   '; var t = s.trim(); return t.length; }",
        'run',
        {[]: 0},
      );
    });

    test('trim — tabs and newlines', () async {
      await _testWasm(
        "String run() { var s = '\\n\\thi\\n'; return s.trim(); }",
        'run',
        {[]: 'hi'},
      );
    });

    test('trimLeft', () async {
      await _testWasm(
        "String run() { var s = '  hi  '; return s.trimLeft(); }",
        'run',
        {[]: 'hi  '},
      );
    });

    test('trimRight', () async {
      await _testWasm(
        "String run() { var s = '  hi  '; return s.trimRight(); }",
        'run',
        {[]: '  hi'},
      );
    });

    test('padLeft with a fill char', () async {
      await _testWasm(
        "String run() { var s = '42'; return s.padLeft(5, '0'); }",
        'run',
        {[]: '00042'},
      );
    });

    test('padLeft default (space)', () async {
      await _testWasm(
        "String run() { var s = 'x'; return s.padLeft(4); }",
        'run',
        {[]: '   x'},
      );
    });

    test('padRight with a fill char', () async {
      await _testWasm(
        "String run() { var s = '42'; return s.padRight(5, '.'); }",
        'run',
        {[]: '42...'},
      );
    });

    test('padRight default (space)', () async {
      await _testWasm(
        "String run() { var s = 'x'; return s.padRight(3); }",
        'run',
        {[]: 'x  '},
      );
    });

    test('pad — width not greater than length is a copy', () async {
      await _testWasm(
        "String run() { var s = 'hello'; return s.padLeft(3); }",
        'run',
        {[]: 'hello'},
      );
    });
  });
}
