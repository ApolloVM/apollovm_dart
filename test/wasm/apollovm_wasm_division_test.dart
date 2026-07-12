@Tags(['wasm'])
library;

import 'dart:typed_data';

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

import 'wasm_runtime_setup.dart';

/// Runs [code] in [language] via the AST interpreter AND the compiled Wasm
/// module, capturing `print` output, and asserts both equal [expected].
Future<void> _testPrints({
  required String language,
  required String code,
  String className = '',
  required String functionName,
  required List args,
  required List<String> expected,
}) async {
  var vm = ApolloVM();
  var loadOK = await vm.loadCodeUnit(
    SourceCodeUnit(language, code, id: 'test'),
  );
  expect(loadOK, isTrue, reason: "Can't load `$language` source");

  var astRunner = vm.createRunner(language)!;
  var astOut = <String>[];
  astRunner.externalPrintFunction = (o) => astOut.add('$o');
  if (className.isNotEmpty) {
    await astRunner.executeClassMethod(
      '',
      className,
      functionName,
      positionalParameters: args,
    );
  } else {
    await astRunner.executeFunction(
      '',
      functionName,
      positionalParameters: args,
    );
  }
  expect(astOut, equals(expected), reason: 'interpreter');

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
  if (!wasmRuntime.isSupported) return;

  var vmWasm = ApolloVM();
  await vmWasm.loadCodeUnit(
    BinaryCodeUnit(
      'wasm',
      Uint8List.fromList(compiled!.output()),
      id: 'test.wasm',
      namespace: '',
    ),
  );
  var wasmRunner = vmWasm.createRunner('wasm')!;
  var wasmOut = <String>[];
  wasmRunner.externalPrintFunction = (o) => wasmOut.add('$o');
  var entry = className.isNotEmpty ? '$className.$functionName' : functionName;
  await wasmRunner.executeFunction('', entry, positionalParameters: args);
  expect(wasmOut, equals(expected), reason: 'wasm');
}

void main() {
  setUpWasmRuntime();

  // `/` on integer operands is integer (truncating) division in Java/Kotlin/C#
  // — the expression resolves to `int`. Dart keeps `/` as a double quotient and
  // uses `~/` for integer division.
  group('Wasm: integer division (`/` on ints)', () {
    test('Java 10 / 3 == 3', () {
      return _testPrints(
        language: 'java11',
        code: r'''class Foo {
  static void run(int a, int b) { print("q=" + (a / b)); }
}''',
        className: 'Foo',
        functionName: 'run',
        args: [10, 3],
        expected: ['q=3'],
      );
    });

    test('Kotlin 10 / 3 == 3', () {
      return _testPrints(
        language: 'kotlin',
        code: 'fun run(a: Int, b: Int) { println("q=" + (a / b)) }',
        functionName: 'run',
        args: [10, 3],
        expected: ['q=3'],
      );
    });
  });

  // Integer division by zero raises a catchable exception whose message matches
  // the interpreter, and the in-flight statement (e.g. a `print` building its
  // argument from the quotient) does not run.
  //
  // The message-asserting tests run on the VM only: the *interpreter*'s
  // division-by-zero message differs between the Dart VM and dart2js (e.g.
  // `Infinity or NaN toInt` vs `Infinity.toInt()`), while the Wasm message is
  // fixed — so a dual-run comparison is only stable on the VM.
  group('Wasm: integer division by zero throws', () {
    test('Dart `~/` 0 (Infinity or NaN toInt)', () {
      return _testPrints(
        language: 'dart',
        code: r'''
          void run(int a, int b) {
            try {
              print('q = ${a ~/ b}');
            } catch (e) {
              print('caught: $e');
            }
          }
        ''',
        functionName: 'run',
        args: [10, 0],
        expected: ['caught: Unsupported operation: Infinity or NaN toInt'],
      );
    }, testOn: 'vm');

    test('Java `/` 0 (IntegerDivisionByZeroException)', () {
      return _testPrints(
        language: 'java11',
        code: r'''class Foo {
  static void run(int a, int b) {
    try {
      print("q = " + (a / b));
    } catch (Exception e) {
      print("caught: " + e);
    }
  }
}''',
        className: 'Foo',
        functionName: 'run',
        args: [10, 0],
        expected: ['caught: IntegerDivisionByZeroException'],
      );
    }, testOn: 'vm');

    test('non-zero divisor still prints the quotient', () {
      return _testPrints(
        language: 'java11',
        code: r'''class Foo {
  static void run(int a, int b) {
    try {
      print("q = " + (a / b));
    } catch (Exception e) {
      print("caught: " + e);
    }
  }
}''',
        className: 'Foo',
        functionName: 'run',
        args: [10, 2],
        expected: ['q = 5'],
      );
    });
  });
}
