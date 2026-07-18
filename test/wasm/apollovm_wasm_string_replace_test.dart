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

  // replaceAll / replaceFirst — two passes over `[len][utf8]`: count matches to
  // size the output, then build it (copy `to` for a match, else one byte).
  group('Wasm String replace', () {
    test('replaceAll — single-char pattern', () async {
      await _testWasm(
        "String run() { var s = 'a-b-c'; return s.replaceAll('-', '+'); }",
        'run',
        {[]: 'a+b+c'},
      );
    });

    test('replaceAll — multi-char pattern', () async {
      await _testWasm(
        "String run() { var s = 'axxbxxc'; return s.replaceAll('xx', '-'); }",
        'run',
        {[]: 'a-b-c'},
      );
    });

    test('replaceAll — replacement longer than pattern (grows)', () async {
      await _testWasm(
        "String run() { var s = 'a.b'; return s.replaceAll('.', '__'); }",
        'run',
        {[]: 'a__b'},
      );
    });

    test('replaceAll — replacement shorter than pattern (shrinks)', () async {
      await _testWasm(
        "String run() { var s = 'aXXb'; return s.replaceAll('XX', 'Y'); }",
        'run',
        {[]: 'aYb'},
      );
    });

    test('replaceAll — empty replacement removes matches', () async {
      await _testWasm(
        "String run() { var s = 'a-b-c'; return s.replaceAll('-', ''); }",
        'run',
        {[]: 'abc'},
      );
    });

    test('replaceAll — no match is unchanged', () async {
      await _testWasm(
        "String run() { var s = 'abc'; return s.replaceAll('z', '+'); }",
        'run',
        {[]: 'abc'},
      );
    });

    test('replaceAll — matches at both ends', () async {
      await _testWasm(
        "String run() { var s = '-a-'; return s.replaceAll('-', '+'); }",
        'run',
        {[]: '+a+'},
      );
    });

    test('replaceAll — output length after growth', () async {
      await _testWasm(
        "int run() { var s = 'a-b-c'; var t = s.replaceAll('-', '++');"
            " return t.length; }",
        'run',
        {[]: 7},
      );
    });

    test('replaceFirst — only the first occurrence', () async {
      await _testWasm(
        "String run() { var s = 'a-b-c'; return s.replaceFirst('-', '+'); }",
        'run',
        {[]: 'a+b-c'},
      );
    });

    test('replaceFirst — no match is unchanged', () async {
      await _testWasm(
        "String run() { var s = 'abc'; return s.replaceFirst('z', '+'); }",
        'run',
        {[]: 'abc'},
      );
    });
  });
}
