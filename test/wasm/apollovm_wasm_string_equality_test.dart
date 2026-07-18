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

  // `String == String` / `String != String` compile to content equality via the
  // `__streq` synth helper (not pointer identity). The result is a bool, so it
  // can be returned directly, used as an `if` condition, or combined logically.
  group('Wasm String equality', () {
    test('== on literals', () async {
      await _testWasm("bool run() { return 'abc' == 'abc'; }", 'run', {
        []: true,
      });
      await _testWasm("bool run() { return 'abc' == 'abd'; }", 'run', {
        []: false,
      });
    });

    test('!= on literals', () async {
      await _testWasm("bool run() { return 'abc' != 'abc'; }", 'run', {
        []: false,
      });
      await _testWasm("bool run() { return 'abc' != 'xyz'; }", 'run', {
        []: true,
      });
    });

    test('== on a variable vs a literal', () async {
      await _testWasm("bool run(String s) { return s == 'yes'; }", 'run', {
        ['yes']: true,
        ['no']: false,
        ['']: false,
      });
    });

    test('!= on a variable vs a literal', () async {
      await _testWasm("bool run(String s) { return s != 'stop'; }", 'run', {
        ['go']: true,
        ['stop']: false,
      });
    });

    test('== on two variables', () async {
      await _testWasm(
        'bool run(String a, String b) { return a == b; }',
        'run',
        {
          ['x', 'x']: true,
          ['x', 'y']: false,
          ['', '']: true,
        },
      );
    });

    test('equality as an if-condition', () async {
      await _testWasm(
        "int run(String s) { if (s == 'ok') { return 1; } return 0; }",
        'run',
        {
          ['ok']: 1,
          ['no']: 0,
        },
      );
    });

    test('empty vs non-empty strings', () async {
      await _testWasm("bool run(String s) { return s == ''; }", 'run', {
        ['']: true,
        ['a']: false,
      });
    });

    test('equality combined with logical AND', () async {
      await _testWasm(
        "bool run(String a, String b) { return a == 'hi' && b == 'yo'; }",
        'run',
        {
          ['hi', 'yo']: true,
          ['hi', 'no']: false,
          ['no', 'yo']: false,
        },
      );
    });
  });
}
