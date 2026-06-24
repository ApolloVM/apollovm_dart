library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Runs [functionName] via the AST interpreter AND via the compiled+executed
/// Wasm module, capturing `print` output from both and asserting they match
/// [expectedOutput].
Future<void> _testWasmPrint(
  String code,
  String functionName,
  List args,
  List<Object?> expectedOutput,
) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', code, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source");

  // 1) AST interpreter.
  var astRunner = vm.createRunner('dart')!;
  var astOut = [];
  astRunner.externalPrintFunction = (o) => astOut.add(o);
  await astRunner.executeFunction('', functionName, positionalParameters: args);
  expect(astOut, equals(expectedOutput), reason: 'interpreter print output');

  // 2) Compile to Wasm.
  var storageWasm = vm.generateAllIn<BytesOutput>('wasm');
  var wasmModules = await storageWasm.allEntries();
  BytesOutput? compiled;
  for (var ns in wasmModules.entries) {
    for (var m in ns.value.entries) {
      compiled ??= m.value;
    }
  }
  expect(compiled, isNotNull, reason: 'No compiled Wasm module');

  var rt = WasmRuntime()..ensureBooted();
  if (!rt.isSupported) {
    fail('Wasm runtime not supported (run `dart run wasm_run:setup`).');
  }

  // 3) Load + run the compiled Wasm, capturing its `print` host import.
  var vmWasm = ApolloVM();
  var loadOK = await vmWasm.loadCodeUnit(
    BinaryCodeUnit('wasm', compiled!.output(), id: 'test.wasm', namespace: ''),
  );
  expect(loadOK, isTrue, reason: 'Compiled Wasm failed to load');

  var wasmRunner = vmWasm.createRunner('wasm')!;
  var wasmOut = [];
  wasmRunner.externalPrintFunction = (o) => wasmOut.add(o);
  await wasmRunner.executeFunction(
    '',
    functionName,
    positionalParameters: args,
  );
  expect(wasmOut, equals(expectedOutput), reason: 'Wasm print output');
}

void main() {
  group('Wasm P2: print(string literal)', () {
    test('single print', () async {
      await _testWasmPrint(
        '''
        void greet() {
          print("hi");
        }
      ''',
        'greet',
        [],
        ['hi'],
      );
    });

    test('multiple prints (literal interning)', () async {
      await _testWasmPrint(
        '''
        void run() {
          print("a");
          print("b");
          print("a");
        }
      ''',
        'run',
        [],
        ['a', 'b', 'a'],
      );
    });

    test('empty and longer strings', () async {
      await _testWasmPrint(
        '''
        void run() {
          print("");
          print("hello world");
        }
      ''',
        'run',
        [],
        ['', 'hello world'],
      );
    });

    test('multi-byte UTF-8', () async {
      await _testWasmPrint(
        '''
        void run() {
          print("héllo • ☃");
        }
      ''',
        'run',
        [],
        ['héllo • ☃'],
      );
    });
  });

  group('Wasm P2: string concatenation', () {
    test('binary +', () async {
      await _testWasmPrint(
        '''
        void run() {
          print("a" + "b");
          print("hi " + "there");
        }
      ''',
        'run',
        [],
        ['ab', 'hi there'],
      );
    });

    test('adjacent string literals', () async {
      await _testWasmPrint(
        '''
        void run() {
          print("x" "y");
        }
      ''',
        'run',
        [],
        ['xy'],
      );
    });

    test('chained +', () async {
      await _testWasmPrint(
        '''
        void run() {
          print("a" + "b" + "c" + "d");
        }
      ''',
        'run',
        [],
        ['abcd'],
      );
    });

    test('concat with empty strings', () async {
      await _testWasmPrint(
        '''
        void run() {
          print("a" + "");
          print("" + "b");
          print("" + "");
        }
      ''',
        'run',
        [],
        ['a', 'b', ''],
      );
    });

    test('multi-byte concat', () async {
      await _testWasmPrint(
        '''
        void run() {
          print("☃" + "x" + "é");
        }
      ''',
        'run',
        [],
        ['☃xé'],
      );
    });

    test('String variable interpolation', () async {
      await _testWasmPrint(
        '''
        void run() {
          String s = "world";
          print("hello " + s);
          print(s + "!");
        }
      ''',
        'run',
        [],
        ['hello world', 'world!'],
      );
    });
  });
}
