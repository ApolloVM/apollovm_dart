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

  // Returning a List/Map across the module boundary: the runner decodes the
  // returned header pointer back into a Dart collection using the function's
  // return type. Guards against regressions in that marshalling.
  group('Wasm aggregate returns', () {
    test('return a List<int>', () async {
      await _testWasm('List<int> run() { return [1, 2, 3]; }', 'run', {
        []: [1, 2, 3],
      });
    });

    test('return a List<int> (arrow)', () async {
      await _testWasm('List<int> run() => [10, 20];', 'run', {
        []: [10, 20],
      });
    });

    test('return a built List', () async {
      await _testWasm(
        'List<int> run() { var l = [1, 2]; l.add(3); return l; }',
        'run',
        {
          []: [1, 2, 3],
        },
      );
    });

    test('return a List<double>', () async {
      await _testWasm('List<double> run() { return [1.5, 2.5]; }', 'run', {
        []: [1.5, 2.5],
      });
    });

    test('return a List<String>', () async {
      await _testWasm("List<String> run() { return ['a', 'b']; }", 'run', {
        []: ['a', 'b'],
      });
    });

    test('return a Map<String, int>', () async {
      await _testWasm(
        "Map<String, int> run() { return {'a': 1, 'b': 2}; }",
        'run',
        {
          []: {'a': 1, 'b': 2},
        },
      );
    });
  });
}
