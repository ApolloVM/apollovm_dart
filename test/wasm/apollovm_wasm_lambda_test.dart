@Tags(['wasm', 'dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Compiles [code], runs top-level [functionName] via the AST interpreter AND
/// the compiled Wasm module, and asserts both return [expectedReturn].
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
  expect(astRet.getValueNoContext(), expectedReturn, reason: 'interpreter');

  var compiled = await _compile(vm);
  var vmWasm = ApolloVM();
  await vmWasm.loadCodeUnit(
    BinaryCodeUnit('wasm', compiled.output(), id: 'test.wasm', namespace: ''),
  );
  var wasmRunner = vmWasm.createRunner('wasm')!;
  var wasmRet = await wasmRunner.executeFunction(
    '',
    functionName,
    positionalParameters: args,
  );
  expect(wasmRet.getValueNoContext(), expectedReturn, reason: 'Wasm');
}

/// Runs class method [className].[methodName] via the interpreter and Wasm,
/// capturing `print` output from each, asserting both equal [expectedPrints].
Future<void> _testWasmClassPrints(
  String code,
  String className,
  String methodName,
  List args,
  List<String> expectedPrints,
) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', code, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source");

  var astRunner = vm.createRunner('dart')!;
  var astOut = <String>[];
  astRunner.externalPrintFunction = (o) => astOut.add('$o');
  await astRunner.executeClassMethod(
    '',
    className,
    methodName,
    positionalParameters: args,
  );
  expect(astOut, equals(expectedPrints), reason: 'interpreter print output');

  var compiled = await _compile(vm);
  var vmWasm = ApolloVM();
  await vmWasm.loadCodeUnit(
    BinaryCodeUnit('wasm', compiled.output(), id: 'test.wasm', namespace: ''),
  );
  var wasmRunner = vmWasm.createRunner('wasm')!;
  var wasmOut = <String>[];
  wasmRunner.externalPrintFunction = (o) => wasmOut.add('$o');
  await wasmRunner.executeFunction(
    '',
    '$className.$methodName',
    positionalParameters: args,
  );
  expect(wasmOut, equals(expectedPrints), reason: 'Wasm print output');
}

Future<BytesOutput> _compile(ApolloVM vm) async {
  var storageWasm = vm.generateAllIn<BytesOutput>('wasm');
  var wasmModules = await storageWasm.allEntries();
  BytesOutput? compiled;
  for (var ns in wasmModules.entries) {
    for (var m in ns.value.entries) {
      compiled ??= m.value;
    }
  }
  expect(compiled, isNotNull, reason: 'No compiled Wasm module');
  return compiled!;
}

void main() {
  group('Wasm: lambda assigned to a var, called directly', () {
    test('the motivating program', () async {
      await _testWasmClassPrints(
        '''
class Foo {
  static void main(int x) {
    var twice = (int n) => n * 2;
    var inc = (int n) => n + 1;
    print('twice: \${twice(x)} ; inc: \${inc(x)}');
  }
}
''',
        'Foo',
        'main',
        [5],
        ['twice: 10 ; inc: 6'],
      );
    });

    test('single lambda var returns int', () async {
      await _testWasmReturn(
        'int f(int x) { var twice = (int n) => n * 2; return twice(x); }',
        'f',
        [21],
        42,
      );
    });

    test('two lambda vars, combined', () async {
      await _testWasmReturn(
        'int f(int x) { var twice = (int n) => n * 2; '
            'var inc = (int n) => n + 1; return twice(x) + inc(x); }',
        'f',
        [5],
        16,
      );
    });

    test('inferred double return type (n / 2)', () async {
      await _testWasmReturn(
        'double f(int x) { var half = (int n) => n / 2; return half(x); }',
        'f',
        [7],
        3.5,
      );
    });

    test('inferred int return type (~/)', () async {
      await _testWasmReturn(
        'int f(int x) { var h = (int n) => n ~/ 2; return h(x); }',
        'f',
        [7],
        3,
      );
    });
  });

  group('Wasm: lambda as a first-class value (table path preserved)', () {
    test('closure passed to a typed function parameter', () async {
      await _testWasmReturn(
        '''
        int apply(int Function(int) f, int v) => f(v);
        int g(int x) { var inc = (int n) => n + 1; return apply(inc, x); }
        ''',
        'g',
        [5],
        6,
      );
    });

    test('direct + passed-as-value closures coexist', () async {
      await _testWasmReturn(
        '''
        int apply(int Function(int) f, int v) => f(v);
        int g(int x) {
          var d = (int n) => n * 2;
          var p = (int n) => n + 1;
          return d(x) + apply(p, x);
        }
        ''',
        'g',
        [5],
        16,
      );
    });

    test('capturing closure still uses the environment', () async {
      await _testWasmReturn(
        'int f(int x) { int k = 100; var add = (int n) => n + k; return add(x); }',
        'f',
        [5],
        105,
      );
    });
  });

  group('Wasm: direct-closure optimization (no table / no env alloc)', () {
    test('direct-only program emits no function table', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(
        SourceCodeUnit(
          'dart',
          'int f(int x) { var twice = (int n) => n * 2; return twice(x); }',
          id: 'test',
        ),
      );
      var compiled = await _compile(vm);
      var dump = compiled.toString();
      // The closure is called directly: no table dispatch and no heap env.
      expect(
        dump.contains('call_indirect'),
        isFalse,
        reason: 'no call_indirect',
      );
      expect(
        dump.contains('closure env size'),
        isFalse,
        reason: 'no env alloc',
      );
      expect(
        dump.contains('Section: Table'),
        isFalse,
        reason: 'no table section',
      );
      expect(
        dump.contains('direct call closure'),
        isTrue,
        reason: 'direct call',
      );
    });
  });
}
