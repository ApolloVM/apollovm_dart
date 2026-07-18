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

  // `s.split(sep)` builds a `List<String>` in two passes: count separators to
  // size the list, then allocate each piece as a fresh String.
  group('Wasm String split', () {
    test('split — piece count', () async {
      await _testWasm(
        "int run() { var s = 'a,b,c'; var p = s.split(','); return p.length; }",
        'run',
        {[]: 3},
      );
    });

    test('split — element access', () async {
      await _testWasm(
        "String run() { var s = 'a,b,c'; var p = s.split(','); return p[0]; }",
        'run',
        {[]: 'a'},
      );
      await _testWasm(
        "String run() { var s = 'a,b,c'; var p = s.split(','); return p[1]; }",
        'run',
        {[]: 'b'},
      );
      await _testWasm(
        "String run() { var s = 'a,b,c'; var p = s.split(','); return p[2]; }",
        'run',
        {[]: 'c'},
      );
    });

    test('split — multi-char separator', () async {
      await _testWasm(
        "int run() { var s = 'axxbxxc'; var p = s.split('xx');"
            " return p.length; }",
        'run',
        {[]: 3},
      );
      await _testWasm(
        "String run() { var s = 'axxbxxc'; var p = s.split('xx');"
            " return p[1]; }",
        'run',
        {[]: 'b'},
      );
    });

    test('split — no separator present yields the whole string', () async {
      await _testWasm(
        "int run() { var s = 'abc'; var p = s.split(','); return p.length; }",
        'run',
        {[]: 1},
      );
      await _testWasm(
        "String run() { var s = 'abc'; var p = s.split(','); return p[0]; }",
        'run',
        {[]: 'abc'},
      );
    });

    test('split — trailing separator yields a trailing empty piece', () async {
      await _testWasm(
        "int run() { var s = 'a,b,'; var p = s.split(','); return p.length; }",
        'run',
        {[]: 3},
      );
      await _testWasm(
        "int run() { var s = 'a,b,'; var p = s.split(',');"
            " var e = p[2]; return e.length; }",
        'run',
        {[]: 0},
      );
    });

    test('split — leading separator yields a leading empty piece', () async {
      await _testWasm(
        "int run() { var s = ',a'; var p = s.split(',');"
            " var e = p[0]; return e.length; }",
        'run',
        {[]: 0},
      );
    });
  });
}
