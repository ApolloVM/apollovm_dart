@Tags(['wasm'])
library;

import 'dart:typed_data';

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Compiles [code] to Wasm, runs the exported [functionName] on the native
/// `wasm_run` runtime for each `args -> expected` entry in [executions], and
/// asserts the returned value. Also runs the AST interpreter as a reference.
Future<void> _testWasm({
  required String language,
  required String code,
  required String functionName,
  required Map<List, Object?> executions,
}) async {
  var vm = ApolloVM();
  var loadOK = await vm.loadCodeUnit(SourceCodeUnit(language, code, id: 'test'));
  expect(loadOK, isTrue, reason: "Can't load `$language` source");

  // AST interpreter reference run.
  var astRunner = vm.createRunner(language)!;
  for (var e in executions.entries) {
    var astValue = await astRunner.executeFunction(
      '',
      functionName,
      positionalParameters: e.key,
    );
    expect(astValue.getValueNoContext(), e.value, reason: 'interpreter');
  }

  // Compile to Wasm.
  var storageWasm = vm.generateAllIn<BytesOutput>('wasm');
  var wasmModules = await storageWasm.allEntries();
  BytesOutput? compiled;
  for (var ns in wasmModules.entries) {
    for (var m in ns.value.entries) {
      compiled ??= m.value;
    }
  }
  expect(compiled, isNotNull);

  var wasmRuntime = WasmRuntime();
  wasmRuntime.ensureBooted();
  if (!wasmRuntime.isSupported) return; // No native runtime available.

  var vmWasm = ApolloVM();
  var wasmBytes = Uint8List.fromList(compiled!.output());
  var ok = await vmWasm.loadCodeUnit(
    BinaryCodeUnit('wasm', wasmBytes, id: 'test.wasm', namespace: ''),
  );
  expect(ok, isTrue);

  var wasmRunner = vmWasm.createRunner('wasm')!;
  for (var e in executions.entries) {
    var v = await wasmRunner.executeFunction(
      '',
      functionName,
      positionalParameters: e.key,
    );
    expect(v.getValueNoContext(), e.value, reason: 'wasm');
  }
}

void main() {
  group('Wasm: String + <number> concatenation', () {
    // GAP 2: `String + int`. Dart forbids this syntactically, so it arrives
    // from Kotlin/Java/C#/JS/TS sources.
    test('String + int (Kotlin)', () {
      return _testWasm(
        language: 'kotlin',
        code: r'''
          fun run(n: Int): String {
            return "n=" + n
          }
        ''',
        functionName: 'run',
        executions: {
          [5]: 'n=5',
        },
      );
    });

    test('String + double (Kotlin)', () {
      return _testWasm(
        language: 'kotlin',
        code: r'''
          fun run(): String {
            return "g=" + 9.8
          }
        ''',
        functionName: 'run',
        executions: {[]: 'g=9.8'},
      );
    });
  });
}
