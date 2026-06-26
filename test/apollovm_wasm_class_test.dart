@Tags(['wasm', 'dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Runs [functionName] via the AST interpreter AND the compiled+executed Wasm
/// module and asserts both return [expectedReturn]. Exercises in-code class
/// instantiation, field access and instance methods on both paths.
Future<void> _testClassReturn(
  String code,
  String functionName,
  List args,
  Object? expectedReturn,
) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', code, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source");

  // 1) AST interpreter.
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

  // 3) Load + run the compiled Wasm.
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

/// Runs [functionName] via the AST interpreter AND the compiled+executed Wasm
/// module and asserts both produce [expectedText] as `print` output (compared
/// as text, since Wasm always stringifies).
Future<void> _testClassPrint(
  String code,
  String functionName,
  List args,
  List<String> expectedText,
) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', code, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source");

  var astRunner = vm.createRunner('dart')!;
  var astOut = [];
  astRunner.externalPrintFunction = (o) => astOut.add('$o');
  await astRunner.executeFunction('', functionName, positionalParameters: args);
  expect(astOut, equals(expectedText), reason: 'interpreter print output');

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
  var wasmOut = [];
  wasmRunner.externalPrintFunction = (o) => wasmOut.add('$o');
  await wasmRunner.executeFunction(
    '',
    functionName,
    positionalParameters: args,
  );
  expect(wasmOut, equals(expectedText), reason: 'Wasm print output');
}

void main() {
  group('Wasm classes: instantiation + methods', () {
    test('constructor + instance method', () async {
      await _testClassReturn(
        '''
        class Point {
          int x;
          int y;
          Point(this.x, this.y);
          int sum() { return x + y; }
        }
        int run() {
          var p = Point(3, 4);
          return p.sum();
        }
        ''',
        'run',
        [],
        7,
      );
    });

    test('field initializer (int y = 10)', () async {
      await _testClassReturn(
        '''
        class C {
          int x;
          int y = 10;
          C(this.x);
          int sum() { return x + y; }
        }
        int run() { var c = C(5); return c.sum(); }
        ''',
        'run',
        [],
        15,
      );
    });

    test('external field read (p.x)', () async {
      await _testClassReturn(
        '''
        class C { int x; int y; C(this.x, this.y); }
        int run() { var c = C(3, 4); return c.x + c.y; }
        ''',
        'run',
        [],
        7,
      );
    });

    test('bare field assignment inside a method', () async {
      await _testClassReturn(
        '''
        class Counter {
          int n;
          Counter(this.n);
          int bump() { n = n + 1; return n; }
        }
        int run() { var c = Counter(41); return c.bump(); }
        ''',
        'run',
        [],
        42,
      );
    });

    test('method with multiple arguments', () async {
      await _testClassReturn(
        '''
        class C {
          int y;
          C(this.y);
          int calc(int a, int b) { return y * a + b; }
        }
        int run() { var c = C(2); return c.calc(10, 3); }
        ''',
        'run',
        [],
        23,
      );
    });

    test('double field + method', () async {
      await _testClassReturn(
        '''
        class C { double d; C(this.d); double half() { return d / 2.0; } }
        double run() { var c = C(7.0); return c.half(); }
        ''',
        'run',
        [],
        3.5,
      );
    });

    test('multiple instances are independent', () async {
      await _testClassReturn(
        '''
        class Box { int v; Box(this.v); int get() { return v; } }
        int run() {
          var a = Box(10);
          var b = Box(20);
          return a.get() + b.get();
        }
        ''',
        'run',
        [],
        30,
      );
    });

    test('method calling another method', () async {
      await _testClassReturn(
        '''
        class C {
          int x;
          C(this.x);
          int doubled() { return x * 2; }
          int quadrupled() { return doubled() + doubled(); }
        }
        int run() { var c = C(5); return c.quadrupled(); }
        ''',
        'run',
        [],
        20,
      );
    });
  });

  group('Wasm classes: print + fields', () {
    test('print a bool field', () async {
      await _testClassPrint(
        '''
        class C { bool flag; C(this.flag); void show() { print(flag); } }
        void run() { var c = C(true); c.show(); }
        ''',
        'run',
        [],
        ['true'],
      );
    });

    test('print an int field', () async {
      await _testClassPrint(
        '''
        class C { int x; C(this.x); void show() { print(x); } }
        void run() { var c = C(42); c.show(); }
        ''',
        'run',
        [],
        ['42'],
      );
    });

    test('interpolate fields', () async {
      await _testClassPrint(
        '''
        class Point {
          int x;
          int y;
          Point(this.x, this.y);
          void describe() { print("(\$x, \$y)"); }
        }
        void run() { var p = Point(3, 4); p.describe(); }
        ''',
        'run',
        [],
        ['(3, 4)'],
      );
    });

    test('String field concatenation', () async {
      await _testClassPrint(
        '''
        class Greeter {
          String name;
          Greeter(this.name);
          void hi() { print("Hi " + name); }
        }
        void run() { var g = Greeter("Bob"); g.hi(); }
        ''',
        'run',
        [],
        ['Hi Bob'],
      );
    });
  });
}
