@Tags(['wasm', 'dart'])
library;

import 'dart:typed_data';

import 'package:apollovm/apollovm.dart';
import 'package:data_serializer/data_serializer.dart';
import 'package:test/test.dart';

import 'wasm_runtime_setup.dart';

void main() async {
  setUpWasmRuntime();

  group('ApolloVM - Wasm Generator (named arguments)', () {
    test(
      'named args in reverse order',
      () => _testWasm(
        language: 'dart',
        code: r'''

          int sub(int a, int b) {
            return a - b;
          }

          int run() {
            return sub(b: 3, a: 10);
          }

        ''',
        functionName: 'run',
        // 10 - 3 = 7 ; proves binding is by-name, not by call-site order.
        executions: {[]: 7},
      ),
    );

    test(
      'mixed positional + named args',
      () => _testWasm(
        language: 'dart',
        code: r'''

          int compute(int base, int factor) {
            return base * factor;
          }

          int run() {
            return compute(5, factor: 3);
          }

        ''',
        functionName: 'run',
        // 5 * 3 = 15 ; first arg positional, second bound by name.
        executions: {[]: 15},
      ),
    );

    test(
      'named args with 3 params, all reordered',
      () => _testWasm(
        language: 'dart',
        code: r'''

          int combine(int a, int b, int c) {
            return a * 100 + b * 10 + c;
          }

          int run() {
            return combine(c: 3, a: 1, b: 2);
          }

        ''',
        functionName: 'run',
        // a=1, b=2, c=3 -> 123 ; proves each binds to its own parameter.
        executions: {[]: 123},
      ),
    );

    // BUG #2: an int literal bound to an f64 (`double`) NAMED-declared
    // parameter must still be type-converted (i64 -> f64). Before the fix the
    // conversion was keyed by `getParameterByIndex(i)`, which returns null for
    // named-declared slots, so the convert was skipped -> invalid module.
    test(
      'int literal bound to a double named param is converted (function)',
      () => _testWasm(
        language: 'dart',
        code: r'''

          double area(double w, {double h = 1.0}) {
            return w * h;
          }

          double main() {
            return area(3.0, h: 4);
          }

        ''',
        functionName: 'main',
        // h: 4 (int literal) -> converted to 4.0 ; 3.0 * 4.0 = 12.0.
        executions: {[]: 12.0},
      ),
    );

    test(
      'int literal bound to a double named param is converted (method)',
      () => _testWasm(
        language: 'dart',
        code: r'''

          class Rect {
            double scale;
            Rect(this.scale);
            double area(double w, {double h = 1.0}) {
              return scale * w * h;
            }
          }

          double main() {
            var r = Rect(2.0);
            return r.area(3.0, h: 4);
          }

        ''',
        functionName: 'main',
        // scale=2.0, w=3.0, h: 4 -> 4.0 ; 2.0 * 3.0 * 4.0 = 24.0.
        executions: {[]: 24.0},
      ),
    );
  });
}

Future<void> _testWasm({
  required String language,
  required String code,
  required String functionName,
  required Map<List, Object?> executions,
  Map<String, dynamic>? expecteWasm,
}) async {
  print('==================================================================');
  print("$language>> $functionName");

  for (var e in executions.entries) {
    var parameters = e.key;
    var expectedResult = e.value;
    print('  -- $parameters -> $expectedResult');
  }

  var vm = ApolloVM();

  var codeUnit = SourceCodeUnit(language, code, id: 'test');

  print(">> Loading code...");

  var loadOK = await vm.loadCodeUnit(codeUnit);

  if (!loadOK) {
    print("Can't load source code in `$language`!");
    return;
  }

  print('------------------------------------------------------------------');

  print(">> Regenerating `$language` code ...\n");

  var regeneratedCode = await vm.generateAllCodeIn(language).writeAllSources();

  print(regeneratedCode);

  print('------------------------------------------------------------------');

  print(">> Compiling `$language` code to Wasm...");

  var storageWasm = vm.generateAllIn<BytesOutput>('wasm');
  var wasmModules = await storageWasm.allEntries();

  expecteWasm ??= {};

  BytesOutput? compiledWasm;
  Uint8List? expectedWasmBytes;

  for (var namespace in wasmModules.entries) {
    for (var module in namespace.value.entries) {
      var moduleName = module.key;
      var wasm = module.value;
      var wasmBytes = wasm.output();

      var expectedBytes = expecteWasm[moduleName];
      if (expectedBytes is String) {
        expectedBytes = hex.decode(expectedBytes);
      }

      print('<<WASM: ${namespace.key}/$moduleName>>');
      print(wasm);

      print('<<WASM: HEX>>');
      print(hex.encode(wasmBytes));

      print('<<WASM: Bytes>>');
      print(wasmBytes);

      expectedWasmBytes = expectedBytes;

      compiledWasm ??= wasm;
    }
  }

  expect(compiledWasm, isNotNull);

  print('------------------------------------------------------------------');

  {
    print(">> Running code...");

    var dartRunner = vm.createRunner('dart')!;

    // Map the `print` function in the VM:
    dartRunner.externalPrintFunction = (o) => print("» $o");

    for (var e in executions.entries) {
      var parameters = e.key;
      var expectedResult = e.value;

      print('<<<<<<<<<<<<<<<<<<<<<<<<<<<<');
      print('EXECUTE AST> $parameters -> $expectedResult');

      var astValue = await dartRunner.executeFunction(
        '',
        functionName,
        positionalParameters: parameters,
      );

      var result = astValue.getValueNoContext();
      print('Result: $result');

      expect(result, expectedResult);
      print('>>>>>>>>>>>>>>>>>>>>>>>>>>>>');
    }
  }

  print('------------------------------------------------------------------');

  final wasmRuntime = WasmRuntime();

  wasmRuntime.ensureBooted();

  if (wasmRuntime.isSupported) {
    print(">> Running compiled Wasm...");

    var vmWasm = ApolloVM();

    var wasmCodeUnit = BinaryCodeUnit(
      'wasm',
      compiledWasm!.output(),
      id: 'test.wasm',
      namespace: '',
    );

    var loadOK = await vmWasm.loadCodeUnit(wasmCodeUnit);
    expect(loadOK, isTrue);

    var wasmRunner = vmWasm.createRunner('wasm')!;

    // Map the `print` function in the VM:
    wasmRunner.externalPrintFunction = (o) => print("wasm» $o");

    for (var e in executions.entries) {
      var parameters = e.key;
      var expectedResult = e.value;

      print('<<<<<<<<<<<<<<<<<<<<<<<<<<<<');
      print('EXECUTE WASM> $parameters -> $expectedResult');

      ASTValue wasmAstValue;

      try {
        wasmAstValue = await wasmRunner.executeFunction(
          '',
          functionName,
          positionalParameters: parameters,
        );
      } catch (e) {
        print(e);

        var matchOffset = RegExp(
          r'Invalid input WebAssembly code at offset (\d+)',
        ).firstMatch('$e');

        if (matchOffset != null) {
          var offset = int.tryParse(matchOffset.group(1) ?? '');
          if (offset != null) {
            var output = compiledWasm.output();

            var codeBefore = output.sublist(0, offset);
            var codeAfter = output.sublist(offset);

            print('CODE ERROR AT:');
            print(codeBefore);
            print(codeAfter);
          }
        }

        rethrow;
      }

      var wasmResult = wasmAstValue.getValueNoContext();
      print('Wasm Result: $wasmResult');

      expect(wasmResult, expectedResult);
      print('>>>>>>>>>>>>>>>>>>>>>>>>>>>>');
    }
  } else {
    print(
      '** `WasmRuntime` not supported: ${wasmRuntime.platformVersion}\n** [LAST BOOT ERROR]: ${wasmRuntime.lastBootError}',
    );
  }

  var output = compiledWasm?.output();
  print('<< GENERATED WASM: HEX>>\n${hex.encode(output!)}');

  // Only assert exact bytes when an expectation was provided.
  if (expectedWasmBytes != null) {
    print('<< EXPECTED WASM: HEX>>\n${hex.encode(expectedWasmBytes)}');
    expect(output, expectedWasmBytes);
  }
}
