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

  // A generic class field (`class Box<T> { T value; }`) is stored boxed (the
  // constructor boxes the value); reading it back at the instantiation type
  // unboxes to the concrete representation (int/double via the numeric path;
  // String/bool/instance by extracting the box payload).
  group('Wasm generic fields', () {
    test('Box<int> round-trips', () async {
      await _testWasm(
        'class Box<T> { T value; Box(this.value); }'
            ' int run() { var b = Box<int>(7); return b.value; }',
        'run',
        {[]: 7},
      );
    });

    test('Box<int> from a parameter', () async {
      await _testWasm(
        'class Box<T> { T value; Box(this.value); }'
            ' int run(int x) { var b = Box<int>(x); return b.value; }',
        'run',
        {
          [7]: 7,
          [42]: 42,
        },
      );
    });

    test('Box<double> round-trips', () async {
      await _testWasm(
        'class Box<T> { T value; Box(this.value); }'
            ' double run() { var b = Box<double>(2.5); return b.value; }',
        'run',
        {[]: 2.5},
      );
    });

    test('Box<String> round-trips', () async {
      await _testWasm(
        'class Box<T> { T value; Box(this.value); }'
            " String run() { var b = Box<String>('hi'); return b.value; }",
        'run',
        {[]: 'hi'},
      );
    });

    test('Box<bool> round-trips', () async {
      await _testWasm(
        'class Box<T> { T value; Box(this.value); }'
            ' bool run() { var b = Box<bool>(true); return b.value; }',
        'run',
        {[]: true},
      );
    });

    test('generic field used in arithmetic', () async {
      await _testWasm(
        'class Box<T> { T value; Box(this.value); }'
            ' int run() { var b = Box<int>(5); return b.value + 10; }',
        'run',
        {[]: 15},
      );
      await _testWasm(
        'class Box<T> { T value; Box(this.value); }'
            ' double run() { var b = Box<double>(1.5); return b.value * 2.0; }',
        'run',
        {[]: 3.0},
      );
    });

    test('two type parameters (Pair<A, B>)', () async {
      await _testWasm(
        'class Pair<A, B> { A a; B b; Pair(this.a, this.b); }'
            ' int run() { var p = Pair<int, int>(3, 4); return p.a + p.b; }',
        'run',
        {[]: 7},
      );
    });

    test('mixed type parameters (Pair<int, String>)', () async {
      await _testWasm(
        'class Pair<A, B> { A a; B b; Pair(this.a, this.b); }'
            " int run() { var p = Pair<int, String>(3, 'x'); return p.a; }",
        'run',
        {[]: 3},
      );
      await _testWasm(
        'class Pair<A, B> { A a; B b; Pair(this.a, this.b); }'
            " String run() { var p = Pair<int, String>(3, 'x'); return p.b; }",
        'run',
        {[]: 'x'},
      );
    });
  });
}
