@TestOn('vm')
@Tags(['wasm', 'dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

import 'wasm_runtime_setup.dart';

/// Compiles [code] to Wasm and runs [functionName] (a `Class.method` static
/// entry point) through both the AST interpreter and the compiled+executed
/// module, asserting every entry in [executions].
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

  // Inheritance in Wasm: a subclass instance carries its superclass's fields at
  // the same offsets, so a superclass method compiled once works on a subclass
  // instance; method dispatch walks the `extends` chain (override wins, else the
  // inherited method), and `super.m()` starts dispatch at the superclass.
  group('Wasm inheritance', () {
    test('inherited method (implicit `this` call)', () async {
      await _testWasm(
        'class A { int base() { return 9; } }'
            ' class B extends A { int run() { return base(); } }'
            ' class M { static int go() { var b = B(); return b.run(); } }',
        'M.go',
        {[]: 9},
      );
    });

    test('inherited method (via receiver)', () async {
      await _testWasm(
        'class A { int base() { return 7; } }'
            ' class B extends A {}'
            ' class M { static int go() { var b = B(); return b.base(); } }',
        'M.go',
        {[]: 7},
      );
    });

    test('inherited method with arguments', () async {
      await _testWasm(
        'class A { int add(int a, int b) { return a + b; } }'
            ' class B extends A { int run() { return add(3, 4); } }'
            ' class M { static int go() { var b = B(); return b.run(); } }',
        'M.go',
        {[]: 7},
      );
    });

    test('inherited field read', () async {
      await _testWasm(
        'class A { int x = 5; }'
            ' class B extends A { int run() { return x; } }'
            ' class M { static int go() { var b = B(); return b.run(); } }',
        'M.go',
        {[]: 5},
      );
    });

    test('inherited field read via receiver', () async {
      await _testWasm(
        'class A { int x = 5; }'
            ' class B extends A {}'
            ' class M { static int go() { var b = B(); return b.x; } }',
        'M.go',
        {[]: 5},
      );
    });

    test('inherited field write', () async {
      await _testWasm(
        'class A { int x = 5; }'
            ' class B extends A { int run() { x = 20; return x; } }'
            ' class M { static int go() { var b = B(); return b.run(); } }',
        'M.go',
        {[]: 20},
      );
    });

    test('inherited `double` field', () async {
      await _testWasm(
        'class A { double x = 1.5; }'
            ' class B extends A { double run() { return x + 1.0; } }'
            ' class M { static double go() { var b = B(); return b.run(); } }',
        'M.go',
        {[]: 2.5},
      );
    });

    test('own and inherited fields coexist (distinct offsets)', () async {
      await _testWasm(
        'class A { int a = 1; }'
            ' class B extends A { int b = 2; int run() { return a + b; } }'
            ' class M { static int go() { var v = B(); return v.run(); } }',
        'M.go',
        {[]: 3},
      );
    });

    test('override on the subclass wins', () async {
      await _testWasm(
        'class A { int f() { return 1; } }'
            ' class B extends A { int f() { return 2; } int run() { return f(); } }'
            ' class M { static int go() { var b = B(); return b.run(); } }',
        'M.go',
        {[]: 2},
      );
    });

    test('super.method()', () async {
      await _testWasm(
        'class A { int f() { return 10; } }'
            ' class B extends A { int f() { return super.f() + 1; }'
            ' int run() { return f(); } }'
            ' class M { static int go() { var b = B(); return b.run(); } }',
        'M.go',
        {[]: 11},
      );
    });

    test('super.method(args)', () async {
      await _testWasm(
        'class A { int g(int n) { return n * 2; } }'
            ' class B extends A { int g(int n) { return super.g(n) + 1; }'
            ' int run() { return g(5); } }'
            ' class M { static int go() { var b = B(); return b.run(); } }',
        'M.go',
        {[]: 11},
      );
    });

    test('two-level chain (C extends B extends A)', () async {
      await _testWasm(
        'class A { int f() { return 3; } }'
            ' class B extends A {}'
            ' class C extends B { int run() { return f(); } }'
            ' class M { static int go() { var c = C(); return c.run(); } }',
        'M.go',
        {[]: 3},
      );
    });
  });
}
