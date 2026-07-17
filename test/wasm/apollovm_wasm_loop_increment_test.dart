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

  var storageWasm = vm.generateAllIn<BytesOutput>('wasm');
  BytesOutput? compiled;
  for (var ns in (await storageWasm.allEntries()).values) {
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

  // Regression: a bare `i++`/`++i`/`i--`/`--i` used as a *statement* inside a
  // `while`/`do-while` body left the operator's value on the operand stack,
  // producing a module that failed Wasm validation ("values remaining on stack
  // at end of block"). `for`-header updates were unaffected (unwound by the
  // loop back-edge). The value is now dropped in statement position.
  group('Wasm loop increment/decrement statements', () {
    test('while + post-increment', () async {
      await _testWasm(
        'int run(int n) { var i = 0; while (i < n) { i++; } return i; }',
        'run',
        {
          [3]: 3,
          [0]: 0,
        },
      );
    });

    test('while + pre-increment', () async {
      await _testWasm(
        'int run(int n) { int i = 0; while (i < n) { ++i; } return i; }',
        'run',
        {
          [4]: 4,
        },
      );
    });

    test('while + post-decrement countdown', () async {
      await _testWasm(
        'int run(int n) { var c = 0; while (n > 0) { n--; c++; } return c; }',
        'run',
        {
          [5]: 5,
        },
      );
    });

    test('while + break/continue with an increment step', () async {
      await _testWasm(
        'int run() { var s = 0; var i = 0;'
            ' while (i < 6) { i++; if (i == 3) { continue; }'
            ' if (i >= 5) { break; } s += i; } return s; }',
        'run',
        {
          []: 7, // i=1 (+1), i=2 (+2), i=3 skip, i=4 (+4), i=5 break -> 7
        },
      );
    });

    test('do-while + post-increment', () async {
      await _testWasm(
        'int run(int n) { var i = 0; do { i++; } while (i < n); return i; }',
        'run',
        {
          [4]: 4,
          [0]: 1, // body runs at least once
        },
      );
    });

    test('increment as an expression still yields its value', () async {
      await _testWasm(
        'int run() { var i = 5; var x = i++; return x * 100 + i; }',
        'run',
        {
          []: 506, // post: x = 5 (old), i = 6
        },
      );
    });
  });
}
