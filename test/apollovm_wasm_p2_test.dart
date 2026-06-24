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

/// Runs [functionName] via the AST interpreter AND the compiled+executed Wasm
/// module and asserts both return [expectedReturn].
Future<void> _testWasmReturn(
  String code,
  String functionName,
  List args,
  Object? expectedReturn,
) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', code, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source");

  var astRunner = vm.createRunner('dart')!;
  var astRet = await astRunner.executeFunction(
    '',
    functionName,
    positionalParameters: args,
  );
  expect(
    astRet.getValueNoContext(),
    expectedReturn,
    reason: 'interpreter return',
  );

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

  var vmWasm = ApolloVM();
  await vmWasm.loadCodeUnit(
    BinaryCodeUnit('wasm', compiled!.output(), id: 'test.wasm', namespace: ''),
  );
  var wasmRunner = vmWasm.createRunner('wasm')!;
  var wasmRet = await wasmRunner.executeFunction(
    '',
    functionName,
    positionalParameters: args,
  );
  expect(wasmRet.getValueNoContext(), expectedReturn, reason: 'Wasm return');
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

  group('Wasm P2: String-returning functions', () {
    test('return literal', () async {
      await _testWasmReturn(
        '''
        String f() {
          return "hi";
        }
      ''',
        'f',
        [],
        'hi',
      );
    });

    test('return concatenation', () async {
      await _testWasmReturn(
        '''
        String f() {
          return "a" + "b" + "c";
        }
      ''',
        'f',
        [],
        'abc',
      );
    });

    test('return built from a local', () async {
      await _testWasmReturn(
        '''
        String greet() {
          String s = "world";
          return "hello " + s;
        }
      ''',
        'greet',
        [],
        'hello world',
      );
    });

    test('conditional return (int param, String return)', () async {
      await _testWasmReturn(
        '''
        String sign(int a) {
          if (a > 0) {
            return "pos";
          }
          return "non-pos";
        }
      ''',
        'sign',
        [5],
        'pos',
      );

      await _testWasmReturn(
        '''
        String sign(int a) {
          if (a > 0) {
            return "pos";
          }
          return "non-pos";
        }
      ''',
        'sign',
        [-1],
        'non-pos',
      );
    });

    test('return multi-byte UTF-8', () async {
      await _testWasmReturn(
        '''
        String f() {
          return "héllo ☃";
        }
      ''',
        'f',
        [],
        'héllo ☃',
      );
    });
  });

  group('Wasm P2: number-to-string interpolation', () {
    test('int variable interpolation', () async {
      await _testWasmPrint(
        '''
        void run() {
          int n = 5;
          int neg = -7;
          print("n=\$n");
          print("neg=\$neg");
        }
      ''',
        'run',
        [],
        ['n=5', 'neg=-7'],
      );
    });

    test('double variable interpolation (incl. whole value)', () async {
      // `doubleToString` renders whole doubles as "5.0" on both the VM and
      // dart2js, matching the interpreter's variable-interpolation formatting.
      await _testWasmPrint(
        '''
        void run() {
          double d = 1.5;
          double q = 0.25;
          double w = 5.0;
          print("d=\$d");
          print("q=\$q");
          print("w=\$w");
        }
      ''',
        'run',
        [],
        ['d=1.5', 'q=0.25', 'w=5.0'],
      );
    });

    test('expression interpolation', () async {
      await _testWasmPrint(
        '''
        void run() {
          int n = 4;
          double d = 2.5;
          print("sum=\${n + n}");
          print("prod=\${d * 2.5}");
        }
      ''',
        'run',
        [],
        ['sum=8', 'prod=6.25'],
      );
    });

    test('mixed interpolation', () async {
      await _testWasmPrint(
        '''
        void run() {
          int n = 3;
          double d = 2.5;
          String s = "ok";
          print("n=\$n d=\$d s=\$s end");
        }
      ''',
        'run',
        [],
        ['n=3 d=2.5 s=ok end'],
      );
    });

    test('String return with interpolation', () async {
      await _testWasmReturn(
        '''
        String label(int n) {
          return "n=\$n";
        }
      ''',
        'label',
        [42],
        'n=42',
      );
    });
  });
}
