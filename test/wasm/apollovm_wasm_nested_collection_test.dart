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

  // A nested collection is stored as an i32 pointer to the inner header, so a
  // `List`/`Map` literal can hold `List`/`Map` elements and chained subscripts
  // (`m[0][1]`) read/write through each level. Nested literals use depth-offset
  // scratch locals so an inner literal doesn't clobber the outer's buffers.
  group('Wasm nested collections', () {
    test('2D list literal + chained read', () async {
      await _testWasm(
        'int run() { var m = [[1, 2], [3, 4]]; return m[0][1]; }',
        'run',
        {[]: 2},
      );
    });

    test('2D list chained read (other cell)', () async {
      await _testWasm(
        'int run() { var m = [[1, 2], [3, 4]]; return m[1][0]; }',
        'run',
        {[]: 3},
      );
    });

    test('nested `double` list', () async {
      await _testWasm(
        'double run() { var m = [[1.5, 2.5]]; return m[0][1]; }',
        'run',
        {[]: 2.5},
      );
    });

    test('3D list chained read', () async {
      await _testWasm(
        'int run() { var m = [[[1, 2], [3, 4]]]; return m[0][1][0]; }',
        'run',
        {[]: 3},
      );
    });

    test('nested map (`m[\'a\'][\'b\']`)', () async {
      await _testWasm(
        "int run() { var m = {'a': {'b': 5}}; return m['a']['b']; }",
        'run',
        {[]: 5},
      );
    });

    test('list of maps', () async {
      await _testWasm(
        "int run() { var m = [{'x': 9}]; return m[0]['x']; }",
        'run',
        {[]: 9},
      );
    });

    test('map of lists', () async {
      await _testWasm(
        "int run() { var m = {'k': [7, 8]}; return m['k'][1]; }",
        'run',
        {[]: 8},
      );
    });

    test('2D list chained write', () async {
      await _testWasm(
        'int run() { var m = [[1, 2], [3, 4]]; m[0][1] = 9; return m[0][1]; }',
        'run',
        {[]: 9},
      );
    });

    test('chained write does not corrupt a sibling', () async {
      await _testWasm(
        'int run() { var m = [[1, 2], [3, 4]]; m[0][1] = 9; return m[1][0]; }',
        'run',
        {[]: 3},
      );
    });

    test('chained compound assignment (`m[0][1] += 5`)', () async {
      await _testWasm(
        'int run() { var m = [[1, 2], [3, 4]]; m[0][1] += 5; return m[0][1]; }',
        'run',
        {[]: 7},
      );
    });

    test('3D list chained write', () async {
      await _testWasm(
        'int run() { var m = [[[1, 2]]]; m[0][0][1] = 20; return m[0][0][1]; }',
        'run',
        {[]: 20},
      );
    });

    test('write through a map into a nested list', () async {
      await _testWasm(
        "int run() { var m = {'k': [7, 8]}; m['k'][1] = 88; return m['k'][1]; }",
        'run',
        {[]: 88},
      );
    });
  });
}
