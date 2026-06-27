@Tags(['wasm'])
library;

import 'dart:typed_data';

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Runs [code] in [language] via the AST interpreter AND the compiled Wasm
/// module, capturing `print` output, and asserts both equal [expected].
///
/// When [className] is given the entry is a class method (`executeClassMethod`
/// for the interpreter, `Class.method` for Wasm); otherwise it is a top-level
/// function.
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
  // An untyped anonymous-function parameter (`n => n * 2`) is inferred from its
  // body. Lua/Python additionally exercise the "a nested closure's `return`
  // does not make the enclosing void function non-void" fix.
  group('Wasm: anonymous functions with an untyped parameter', () {
    test('C# lambda bound to a Func', () {
      return _testPrints(
        language: 'csharp',
        code: r'''class Foo {
  public static void main(int x) {
    Func twice = n => n * 2;
    Func inc = n => n + 1;
    print("twice: " + twice(x) + " ; inc: " + inc(x));
  }
}''',
        className: 'Foo',
        functionName: 'main',
        args: [5],
        expected: ['twice: 10 ; inc: 6'],
      );
    });

    test('Lua anonymous functions', () {
      return _testPrints(
        language: 'lua',
        code: r'''function main(x)
  local twice = function(n) return n * 2 end
  local inc = function(n) return n + 1 end
  print("twice: " .. twice(x) .. " ; inc: " .. inc(x))
end''',
        functionName: 'main',
        args: [5],
        expected: ['twice: 10 ; inc: 6'],
      );
    });

    test('Python lambdas', () {
      return _testPrints(
        language: 'python',
        code:
            'def main(x):\n'
            '    twice = lambda n: n * 2\n'
            '    inc = lambda n: n + 1\n'
            '    print(twice(x))\n'
            '    print(inc(x))\n',
        functionName: 'main',
        args: [5],
        expected: ['10', '6'],
      );
    });
  });

  // JS/TS parse `let twice = (n) => …` as a named nested function declaration,
  // which is hoisted and called via a direct `call`.
  group('Wasm: named nested function declarations (JS/TS lambdas)', () {
    test('JavaScript arrow functions', () {
      return _testPrints(
        language: 'javascript',
        code: r'''function main(x) {
  let twice = (n) => n * 2;
  let inc = (n) => n + 1;
  print("twice: " + twice(x) + " ; inc: " + inc(x));
}''',
        functionName: 'main',
        args: [5],
        expected: ['twice: 10 ; inc: 6'],
      );
    });

    test('TypeScript arrow functions', () {
      return _testPrints(
        language: 'typescript',
        code: r'''function main(x: number): void {
  let twice = (n: number) => n * 2;
  let inc = (n: number) => n + 1;
  print("twice: " + twice(x) + " ; inc: " + inc(x));
}''',
        functionName: 'main',
        args: [5],
        expected: ['twice: 10 ; inc: 6'],
      );
    });
  });

  // A generic `T` field is represented as a boxed `Object`; a concrete value
  // stored into it is boxed, and read back via box-to-String.
  group('Wasm: generic class field (Box<T>)', () {
    test('Dart Box<int>', () {
      return _testPrints(
        language: 'dart',
        code: r'''class Box<T> {
  T value;
  Box(this.value);
}
void run(int x) {
  var b = Box<int>(x);
  print('box: ${b.value}');
}''',
        functionName: 'run',
        args: [10],
        expected: ['box: 10'],
      );
    });

    test('Java Box<Integer>', () {
      return _testPrints(
        language: 'java11',
        code: r'''class Box<T> {
  T value;
  Box(T value) { this.value = value; }
}
class Foo {
  static public void main(int x) {
    Box<Integer> b = new Box<Integer>(x);
    print("box: " + b.value);
  }
}''',
        className: 'Foo',
        functionName: 'main',
        args: [10],
        expected: ['box: 10'],
      );
    });

    test('TypeScript Box<number>', () {
      return _testPrints(
        language: 'typescript',
        code: r'''class Box<T> {
  value: T;
  constructor(value: T) {
    this.value = value;
  }
}
function run(x: number): void {
  let b: Box<number> = new Box<number>(x);
  print("box: " + b.value);
}''',
        functionName: 'run',
        args: [10],
        expected: ['box: 10'],
      );
    });
  });
}
