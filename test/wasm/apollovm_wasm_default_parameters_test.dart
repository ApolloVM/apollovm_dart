@Tags(['wasm', 'dart'])
library;

import 'dart:typed_data';

import 'package:apollovm/apollovm.dart';
import 'package:data_serializer/data_serializer.dart';
import 'package:test/test.dart';

void main() async {
  group('ApolloVM - Wasm Generator (default parameter values)', () {
    test(
      'omitted optional positional default',
      () => _testWasm(
        language: 'dart',
        code: r'''

          int addOff(int x, [int off = 100]) {
            return x + off;
          }

          int run() {
            return addOff(5);
          }

        ''',
        functionName: 'run',
        // off omitted -> default 100 ; 5 + 100 = 105.
        executions: {[]: 105},
      ),
    );

    test(
      'supplied value overrides optional default',
      () => _testWasm(
        language: 'dart',
        code: r'''

          int addOff(int x, [int off = 100]) {
            return x + off;
          }

          int run() {
            return addOff(5, 20);
          }

        ''',
        functionName: 'run',
        // off supplied -> 20 ; 5 + 20 = 25.
        executions: {[]: 25},
      ),
    );

    test(
      'omitted named defaults (all omitted)',
      () => _testWasm(
        language: 'dart',
        code: r'''

          int f({int a = 7, int b = 100}) {
            return a + b;
          }

          int run() {
            return f();
          }

        ''',
        functionName: 'run',
        // a=7 (default), b=100 (default) -> 107.
        executions: {[]: 107},
      ),
    );

    test(
      'one named supplied, the other defaulted',
      () => _testWasm(
        language: 'dart',
        code: r'''

          int f({int a = 7, int b = 100}) {
            return a + b;
          }

          int run() {
            return f(a: 1);
          }

        ''',
        functionName: 'run',
        // a=1 (supplied), b=100 (default) -> 101.
        executions: {[]: 101},
      ),
    );

    test(
      'default value as a constant arithmetic expression',
      () => _testWasm(
        language: 'dart',
        code: r'''

          int g([int k = 2 + 3]) {
            return k;
          }

          int run() {
            return g();
          }

        ''',
        functionName: 'run',
        // k omitted -> default `2 + 3` = 5.
        executions: {[]: 5},
      ),
    );

    test(
      'method call with omitted optional default',
      () => _testWasm(
        language: 'dart',
        code: r'''

          class Calc {
            int base;
            Calc(this.base);
            int addOff(int x, [int off = 100]) {
              return base + x + off;
            }
          }

          int run() {
            var c = Calc(1);
            return c.addOff(5);
          }

        ''',
        functionName: 'run',
        // base=1, x=5, off=default 100 -> 106.
        executions: {[]: 106},
      ),
    );

    test(
      'method call with named default supplied/omitted',
      () => _testWasm(
        language: 'dart',
        code: r'''

          class Calc {
            int base;
            Calc(this.base);
            int combine({int a = 7, int b = 100}) {
              return base + a + b;
            }
          }

          int run() {
            var c = Calc(1);
            return c.combine(a: 2);
          }

        ''',
        functionName: 'run',
        // base=1, a=2 (supplied), b=100 (default) -> 103.
        executions: {[]: 103},
      ),
    );

    // BUG #3: a NON-constant default (here `b = a`, referencing another
    // parameter) cannot be emitted in the caller's scope; the Wasm backend
    // must reject it with a clear StateError instead of silently mis-compiling
    // (the interpreter evaluates defaults in the callee scope).
    test('non-constant default value throws a clear StateError', () async {
      var vm = ApolloVM();
      var loadOK = await vm.loadCodeUnit(
        SourceCodeUnit('dart', r'''

          int g(int a, [int b = a]) {
            return a + b;
          }

          int run() {
            return g(5);
          }

        ''', id: 'test'),
      );
      expect(loadOK, isTrue);

      expect(
        () => vm.generateAllIn<BytesOutput>('wasm'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('non-constant default'), contains('b')),
          ),
        ),
      );
    });
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
