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

  // A user-declared getter (`int get x { ... }`) compiles to a zero-argument
  // instance method; a getter access via a receiver (`c.x`) lowers to a call of
  // it. Inherited getters and overrides resolve through the same superclass-chain
  // method lookup as methods. (Bare getter access inside a method body — `x`
  // resolving to `this.x` — is a separate follow-up: the AST interpreter does
  // not resolve it yet either, so it is out of scope here.)
  group('Wasm getters', () {
    test('getter via receiver', () async {
      await _testWasm(
        'class C { int _x = 5; int get x { return _x; } }'
            ' class M { static int go() { var c = C(); return c.x; } }',
        'M.go',
        {[]: 5},
      );
    });

    test('getter with a computed expression', () async {
      await _testWasm(
        'class C { int _x = 5; int get doubled { return _x * 2; } }'
            ' class M { static int go() { var c = C(); return c.doubled; } }',
        'M.go',
        {[]: 10},
      );
    });

    test('getter used within an expression', () async {
      await _testWasm(
        'class C { int _x = 5; int get x { return _x; } }'
            ' class M { static int go() { var c = C(); return c.x + 3; } }',
        'M.go',
        {[]: 8},
      );
    });

    test('getter read twice in one expression', () async {
      await _testWasm(
        'class C { int get x { return 10; } }'
            ' class M { static int go() { var c = C(); return c.x + c.x; } }',
        'M.go',
        {[]: 20},
      );
    });

    test('`double` getter', () async {
      await _testWasm(
        'class C { double get pi { return 3.14; } }'
            ' class M { static double go() { var c = C(); return c.pi; } }',
        'M.go',
        {[]: 3.14},
      );
    });

    test('`bool` getter', () async {
      await _testWasm(
        'class C { int _n = 0; bool get isZero { return _n == 0; } }'
            ' class M { static bool go() { var c = C(); return c.isZero; } }',
        'M.go',
        {[]: true},
      );
    });

    test('`String` getter', () async {
      await _testWasm(
        'class C { String get greeting { return "hi"; } }'
            ' class M { static String go() { var c = C(); return c.greeting; } }',
        'M.go',
        {[]: 'hi'},
      );
    });

    test('inherited getter', () async {
      await _testWasm(
        'class A { int _x = 7; int get x { return _x; } }'
            ' class B extends A {}'
            ' class M { static int go() { var b = B(); return b.x; } }',
        'M.go',
        {[]: 7},
      );
    });

    test('overridden getter (subclass wins)', () async {
      await _testWasm(
        'class A { int get x { return 1; } }'
            ' class B extends A { int get x { return 2; } }'
            ' class M { static int go() { var b = B(); return b.x; } }',
        'M.go',
        {[]: 2},
      );
    });
  });
}
