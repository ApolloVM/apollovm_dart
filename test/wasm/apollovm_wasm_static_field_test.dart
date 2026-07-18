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

  // A `Class.method` entry point is a `static` method: the interpreter runs it
  // via `executeClassMethod` (the compiled Wasm exports it under the same
  // `Class.method` name, called with `executeFunction` below).
  var dotAt = functionName.indexOf('.');
  var className = dotAt < 0 ? null : functionName.substring(0, dotAt);
  var methodName = dotAt < 0 ? functionName : functionName.substring(dotAt + 1);

  var astRunner = vm.createRunner('dart')!;
  for (var e in executions.entries) {
    var r = className == null
        ? await astRunner.executeFunction(
            '',
            methodName,
            positionalParameters: e.key,
          )
        : await astRunner.executeClassMethod(
            '',
            className,
            methodName,
            positionalParameters: [e.key],
            classInstanceFields: const {},
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

  // `static` fields compile to typed module globals (seeded with their literal
  // initializer), read/written by a bare reference inside a `static` method.
  group('Wasm static fields', () {
    test('int read', () async {
      await _testWasm(
        'class C { static int c = 7; static int run() { return c; } }',
        'C.run',
        {[]: 7},
      );
    });

    test('double read', () async {
      await _testWasm(
        'class C { static double c = 2.5; static double run() { return c; } }',
        'C.run',
        {[]: 2.5},
      );
    });

    test('bool read/write', () async {
      await _testWasm(
        'class C { static bool on = true;'
            ' static bool run() { on = false; return on; } }',
        'C.run',
        {[]: false},
      );
    });

    test('used in an expression', () async {
      await _testWasm(
        'class C { static int a = 3; static int b = 4;'
            ' static int run() { return a + b; } }',
        'C.run',
        {[]: 7},
      );
    });

    test('write (set)', () async {
      await _testWasm(
        'class C { static int c = 7; static int run() { c = 20; return c; } }',
        'C.run',
        {[]: 20},
      );
    });

    test('compound assignment (`+=`)', () async {
      await _testWasm(
        'class C { static int c = 7; static int run() { c += 5; return c; } }',
        'C.run',
        {[]: 12},
      );
    });

    test('a static field persists across calls', () async {
      await _testWasm(
        'class C {'
            ' static int c = 0;'
            ' static int bump() { c += 1; return c; }'
            ' static int run() { bump(); bump(); return c; } }',
        'C.run',
        {[]: 2},
      );
    });

    test('static fields of two classes have independent storage', () async {
      await _testWasm(
        'class A { static int v = 10; static int run() { return v; } }'
            ' class B { static int v = 20; }',
        'A.run',
        {[]: 10},
      );
    });

    // The static-field globals share the module global space with the enum
    // entry caches; this guards the global-index layout for a module using both.
    test('static fields coexist with an enum', () async {
      await _testWasm(
        'enum Color { red, green, blue }'
            ' class C { static int c = 5;'
            ' static int run() { var g = Color.green; return c + g.index; } }',
        'C.run',
        {[]: 6},
      );
    });
  });
}
