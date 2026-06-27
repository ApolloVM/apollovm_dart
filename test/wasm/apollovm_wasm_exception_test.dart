@TestOn('vm')
@Tags(['wasm', 'dart'])
library;

import 'dart:typed_data';

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Compiles [code] (Dart) to Wasm, runs [fn] on the real Wasm runtime, and also
/// runs it through the AST interpreter; asserts both agree and match
/// [expected].
Future<void> _check(
  String name,
  String code,
  String fn,
  List args,
  Object? expected,
) async {
  // AST interpreter (source of truth).
  var vmDart = ApolloVM();
  var okDart = await vmDart.loadCodeUnit(SourceCodeUnit('dart', code, id: 't'));
  expect(okDart, isTrue, reason: '[$name] load dart');
  var dartRunner = vmDart.createRunner('dart')!;
  var dartOut = [];
  dartRunner.externalPrintFunction = (o) => dartOut.add(o);
  var dartV = await dartRunner.executeFunction(
    '',
    fn,
    positionalParameters: args,
  );
  expect(
    dartV.getValueNoContext(),
    expected,
    reason: '[$name] interpreter result',
  );

  // Compile to Wasm.
  var vm = ApolloVM();
  await vm.loadCodeUnit(SourceCodeUnit('dart', code, id: 't'));
  var storage = vm.generateAllIn<BytesOutput>('wasm');
  var modules = await storage.allEntries();
  BytesOutput? compiled;
  for (var ns in modules.entries) {
    for (var m in ns.value.entries) {
      compiled ??= m.value;
    }
  }
  expect(compiled, isNotNull, reason: '[$name] compiled wasm');

  var rt = WasmRuntime();
  rt.ensureBooted();
  if (!rt.isSupported) {
    print('** Wasm runtime not supported, skipping run: ${rt.lastBootError}');
    return;
  }

  var vmWasm = ApolloVM();
  Uint8List bytes = compiled!.output();
  var okWasm = await vmWasm.loadCodeUnit(
    BinaryCodeUnit('wasm', bytes, id: 't.wasm', namespace: ''),
  );
  expect(okWasm, isTrue, reason: '[$name] load wasm');
  var runner = vmWasm.createRunner('wasm')!;
  var wasmV = await runner.executeFunction('', fn, positionalParameters: args);
  expect(wasmV.getValueNoContext(), expected, reason: '[$name] wasm result');
}

void main() {
  group('Wasm throw + catch', () {
    test('typed catch returns thrown int', () async {
      await _check(
        'typed-int',
        r'''
int test() { try { throw 7; } on int catch (e) { return e; } }
''',
        'test',
        [],
        7,
      );
    });

    test('untyped catch returns thrown int', () async {
      await _check(
        'untyped-int',
        r'''
int test() { try { throw 42; } catch (e) { return e; } }
''',
        'test',
        [],
        42,
      );
    });

    test('untyped catch returns thrown double', () async {
      await _check(
        'untyped-double',
        r'''
double test() { try { throw 3.5; } catch (e) { return e; } }
''',
        'test',
        [],
        3.5,
      );
    });

    test('no throw falls through', () async {
      await _check(
        'fallthrough',
        r'''
int test(int x) { try { return x + 1; } catch (e) { return -1; } }
''',
        'test',
        [10],
        11,
      );
    });

    test('multi-catch matches by numeric tower (double accepts int)', () async {
      await _check(
        'multi',
        r'''
int test() {
  try { throw 5; }
  on double catch (e) { return 100; }
  on int catch (e) { return e; }
}
''',
        'test',
        [],
        100,
      );
    });

    test('catch-all clause after a typed clause', () async {
      await _check(
        'catch-all',
        r'''
int test() {
  try { throw 9; }
  on String catch (e) { return 1; }
  catch (e) { return 200; }
}
''',
        'test',
        [],
        200,
      );
    });
  });

  group('Wasm throw inside control flow', () {
    test('throw inside taken if', () async {
      await _check(
        'if-taken',
        r'''
int test(int x) {
  try { if (x < 0) { throw 1; } return 10; } catch (e) { return 99; }
}
''',
        'test',
        [-5],
        99,
      );
    });

    test('throw inside not-taken if', () async {
      await _check(
        'if-not-taken',
        r'''
int test(int x) {
  try { if (x < 0) { throw 1; } return 10; } catch (e) { return 99; }
}
''',
        'test',
        [5],
        10,
      );
    });

    test('throw inside while loop', () async {
      await _check(
        'while',
        r'''
int test(int n) {
  try {
    int i = 0;
    while (i < n) { if (i == 3) { throw 1; } i = i + 1; }
    return 0;
  } catch (e) { return 77; }
}
''',
        'test',
        [10],
        77,
      );
    });

    test('throw inside for loop after accumulating', () async {
      await _check(
        'for',
        r'''
int test() {
  int s = 0;
  try {
    for (int i = 0; i < 5; i = i + 1) { s = s + i; if (i == 4) { throw 1; } }
    return -1;
  } catch (e) { return s; }
}
''',
        'test',
        [],
        10,
      );
    });
  });

  group('Wasm finally', () {
    test('runs on normal completion', () async {
      await _check(
        'fin-normal',
        r'''
int test() { int s = 0; try { s = 1; } finally { s = s + 10; } return s; }
''',
        'test',
        [],
        11,
      );
    });

    test('runs after a caught throw', () async {
      await _check(
        'fin-caught',
        r'''
int test() {
  int s = 0;
  try { throw 1; } catch (e) { s = 5; } finally { s = s + 10; }
  return s;
}
''',
        'test',
        [],
        15,
      );
    });

    test('runs when a return occurs in try', () async {
      await _check(
        'fin-return',
        r'''
int test() { int s = 0; try { return 1; } finally { s = 99; } }
''',
        'test',
        [],
        1,
      );
    });

    test('return inside finally overrides', () async {
      await _check(
        'fin-override',
        r'''
int test() { try { return 1; } finally { return 2; } }
''',
        'test',
        [],
        2,
      );
    });

    test('runs then exception propagates to outer catch', () async {
      await _check(
        'fin-propagate',
        r'''
int test() {
  int s = 0;
  try {
    try { throw 7; } finally { s = 3; }
  } catch (e) { return s + e; }
}
''',
        'test',
        [],
        10,
      );
    });

    test('finally with no catch on the normal path', () async {
      await _check(
        'fin-nocatch',
        r'''
int test(int x) {
  int s = 0;
  try { if (x > 0) { s = 1; } } finally { s = s + 50; }
  return s;
}
''',
        'test',
        [5],
        51,
      );
    });

    // GAP 8: a catch clause with a declared catch-all exception TYPE
    // (`Exception`/`Throwable`/`Error`/`Object`). The Wasm model carries a
    // single thrown value, so a typed catch-all must be treated like an untyped
    // `catch (e)` instead of failing with "Can't handle type: Exception".
    test('typed catch with a catch-all type (on Exception)', () async {
      await _check(
        'typed-catchall',
        r'''
int test(int b) {
  try {
    if (b == 0) { throw 7; }
    return b;
  } on Exception catch (e) {
    return -1;
  }
}
''',
        'test',
        [0],
        -1,
      );
    });
  });

  group('Wasm cross-function propagation', () {
    test('throw from a callee is caught by the caller', () async {
      await _check(
        'xfn-basic',
        r'''
void boom() { throw 1; }
int test() { try { boom(); return 0; } catch (e) { return 42; } }
''',
        'test',
        [],
        42,
      );
    });

    test(
      'thrown value propagates across a call and binds in the catch',
      () async {
        await _check(
          'xfn-value',
          r'''
int boom() { throw 7; }
int test() {
  try { int x = boom(); return x; } on int catch (e) { return e + 1; }
}
''',
          'test',
          [],
          8,
        );
      },
    );

    test('propagation through two stack frames', () async {
      await _check(
        'xfn-deep',
        r'''
void deep() { throw 5; }
void mid() { deep(); }
int test() { try { mid(); return 0; } catch (e) { return 9; } }
''',
        'test',
        [],
        9,
      );
    });

    test('callee returning normally is unaffected', () async {
      await _check(
        'xfn-normal',
        r'''
int give() { return 3; }
int test() {
  try { int x = give(); return x * 10; } catch (e) { return -1; }
}
''',
        'test',
        [],
        30,
      );
    });
  });

  group('Wasm VM-trap catching (integer division by zero)', () {
    test('division by zero is caught', () async {
      await _check(
        'div0',
        r'''
int test() { try { int x = 1 ~/ 0; return x; } catch (e) { return 123; } }
''',
        'test',
        [],
        123,
      );
    });

    test('division by nonzero does not raise', () async {
      await _check(
        'div-ok',
        r'''
int test() { try { int x = 10 ~/ 2; return x; } catch (e) { return -1; } }
''',
        'test',
        [],
        5,
      );
    });

    test('caught division-by-zero binds the message string', () async {
      await _check(
        'div0-msg',
        r'''
String test() {
  try { int x = 5 ~/ 0; return "no"; } catch (e) { return e; }
}
''',
        'test',
        [],
        'Unsupported operation: Infinity or NaN toInt',
      );
    });
  });
}
