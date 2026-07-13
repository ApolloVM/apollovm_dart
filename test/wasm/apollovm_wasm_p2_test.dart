@Tags(['wasm', 'dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

import 'wasm_runtime_setup.dart';

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

/// Like [_testWasmPrint], but for non-String values: the AST interpreter
/// receives the raw object (e.g. the `int` 42) while the Wasm host always
/// receives the stringified form, so both are compared as text against
/// [expectedText].
Future<void> _testWasmPrintText(
  String code,
  String functionName,
  List args,
  List<String> expectedText,
) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', code, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source");

  // 1) AST interpreter (raw objects -> text).
  var astRunner = vm.createRunner('dart')!;
  var astOut = [];
  astRunner.externalPrintFunction = (o) => astOut.add('$o');
  await astRunner.executeFunction('', functionName, positionalParameters: args);
  expect(astOut, equals(expectedText), reason: 'interpreter print output');

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
  wasmRunner.externalPrintFunction = (o) => wasmOut.add('$o');
  await wasmRunner.executeFunction(
    '',
    functionName,
    positionalParameters: args,
  );
  expect(wasmOut, equals(expectedText), reason: 'Wasm print output');
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
  setUpWasmRuntime();

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

  group('Wasm P2: String parameters', () {
    test('echo (param in, param out)', () async {
      await _testWasmReturn(
        '''
        String echo(String s) {
          return s;
        }
      ''',
        'echo',
        ['hello'],
        'hello',
      );

      await _testWasmReturn(
        '''
        String echo(String s) {
          return s;
        }
      ''',
        'echo',
        ['héllo ☃'],
        'héllo ☃',
      );

      await _testWasmReturn(
        '''
        String echo(String s) {
          return s;
        }
      ''',
        'echo',
        [''],
        '',
      );
    });

    test('param + concatenation', () async {
      await _testWasmReturn(
        '''
        String greet(String name) {
          return "hi " + name + "!";
        }
      ''',
        'greet',
        ['Bob'],
        'hi Bob!',
      );
    });

    test('param + interpolation', () async {
      await _testWasmReturn(
        '''
        String tag(String s, int n) {
          return "[\$s:\$n]";
        }
      ''',
        'tag',
        ['x', 7],
        '[x:7]',
      );
    });

    test('print a String parameter', () async {
      await _testWasmPrint(
        '''
        void show(String s) {
          print(s);
          print("got: " + s);
        }
      ''',
        'show',
        ['yo'],
        ['yo', 'got: yo'],
      );
    });
  });

  group('Wasm P2: memory.grow', () {
    test('large allocation grows memory', () async {
      // Bump-and-leak concat in a loop allocates well past the initial reserve
      // (64 KiB), forcing `memory.grow`.
      await _testWasmReturn(
        '''
        String repeat(int n) {
          String s = "";
          for (int i = 0; i < n; i = i + 1) {
            s = s + "0123456789";
          }
          return s;
        }
      ''',
        'repeat',
        [200],
        '0123456789' * 200,
      );
    });
  });

  group('Wasm P2: print(any type)', () {
    test('print int literal', () async {
      await _testWasmPrintText('void run() { print(42); }', 'run', [], ['42']);
    });

    test('print int parameter', () async {
      await _testWasmPrintText(
        'void show(int n) { print(n); }',
        'show',
        [7],
        ['7'],
      );
    });

    test('print double literal', () async {
      await _testWasmPrintText('void run() { print(3.14); }', 'run', [], [
        '3.14',
      ]);
    });

    test('print bool literals', () async {
      await _testWasmPrintText(
        'void run() { print(true); print(false); }',
        'run',
        [],
        ['true', 'false'],
      );
    });

    test('print bool parameter', () async {
      await _testWasmPrintText(
        'void show(bool b) { print(b); }',
        'show',
        [true],
        ['true'],
      );
    });

    test('print null', () async {
      await _testWasmPrintText('void run() { print(null); }', 'run', [], [
        'null',
      ]);
    });

    test('print expression result (int)', () async {
      await _testWasmPrintText(
        'void run() { int a = 20; int b = 22; print(a + b); }',
        'run',
        [],
        ['42'],
      );
    });

    test('interpolate bool', () async {
      await _testWasmPrintText(
        r'void run() { bool b = true; print("flag: $b"); }',
        'run',
        [],
        ['flag: true'],
      );
    });
  });
}
