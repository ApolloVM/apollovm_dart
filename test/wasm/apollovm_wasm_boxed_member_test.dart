@TestOn('vm')
@Tags(['wasm'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

import 'wasm_runtime_setup.dart';

/// Compiles [src] (Dart) to a Wasm module and returns its bytes.
Future<BytesOutput> _compile(String src) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', src, id: 't'));
  expect(ok, isTrue, reason: 'cannot parse: $src');

  var storage = vm.generateAllIn<BytesOutput>('wasm');
  BytesOutput? compiled;
  for (var ns in (await storage.allEntries()).values) {
    for (var m in ns.values) {
      compiled ??= m;
    }
  }
  expect(compiled, isNotNull, reason: 'no Wasm module generated for: $src');
  return compiled!;
}

/// Compiles then executes [functionName], returning its value. Returns `null`
/// when the platform has no Wasm runtime — the compile assertion above is then
/// the portable guarantee.
Future<Object?> _run(
  String src, {
  String functionName = 'run',
  List args = const [],
}) async {
  var compiled = await _compile(src);

  var vmWasm = ApolloVM();
  var loaded = await vmWasm.loadCodeUnit(
    BinaryCodeUnit('wasm', compiled.output(), id: 't.wasm', namespace: ''),
  );
  expect(loaded, isTrue, reason: 'compiled Wasm failed to load');

  try {
    var r = await vmWasm
        .createRunner('wasm')!
        .executeFunction('', functionName, positionalParameters: args);
    return r.getValueNoContext();
  } on StateError catch (e) {
    if (e.message.contains('not supported on this platform')) return null;
    rethrow;
  }
}

void main() {
  setUpAll(setUpWasmRuntime);

  group('`?.` on a boxed-Object receiver', () {
    // A boxed slot is the only Wasm representation that can hold `null`, so it
    // is the only place `?.` has to short-circuit rather than being vacuous.

    test('`?.length` on a null receiver yields null', () async {
      expect(
        await _run(
          'int run() { var missing = null; var n = missing?.length; '
          'return n ?? -1; }',
        ),
        anyOf(isNull, equals(-1)),
      );
    });

    test('`?.length` on a boxed String yields the length', () async {
      expect(
        await _run(
          "int run() { Object? s = 'hello'; var n = s?.length; "
          'return n ?? -1; }',
        ),
        anyOf(isNull, equals(5)),
      );
    });

    test('`?.isEmpty` on a null receiver yields null', () async {
      expect(
        await _run(
          'int run() { var s = null; var e = s?.isEmpty; '
          'return e == null ? -1 : 0; }',
        ),
        anyOf(isNull, equals(-1)),
      );
    });

    test('a null-aware result feeds `??` and `== null`', () async {
      // The result of `?.` on a boxed slot is itself boxed, which is what makes
      // it usable as a nullable value rather than an unboxed scalar.
      expect(
        await _run('int run() { var m = null; return (m?.length) ?? 42; }'),
        anyOf(isNull, equals(42)),
      );
    });
  });

  group('plain `.` on a boxed-Object receiver', () {
    test('`.length` on a boxed String yields an unboxed int', () async {
      expect(
        await _run("int run() { Object? s = 'hello'; return s.length; }"),
        anyOf(isNull, equals(5)),
      );
    });
  });

  group('known gap (pre-existing)', () {
    // An explicitly-declared `Object?` local initialized from a *concrete*
    // value keeps the initializer's type rather than being boxed, so
    // `Object? s = ''` makes `s` a String slot. `s?.isEmpty` then takes the
    // concrete-String path and stores its i32 boolean into a local sized from
    // the (mis-resolved) declared type of the result, producing a module that
    // compiles but fails Wasm validation.
    //
    // This reproduces byte-identically without the boxed-getter support in this
    // commit, so it is a separate defect in the declaration path — recorded
    // here so a fix has a home rather than being rediscovered.
    test(
      '`Object? s = \'\'; s?.isEmpty` emits an invalid module',
      () async {
        expect(
          await _run(
            "int run() { Object? s = ''; var e = s?.isEmpty; "
            'return e == null ? -1 : 1; }',
          ),
          anyOf(isNull, equals(1)),
        );
      },
      skip:
          'pre-existing: `Object?` local keeps its concrete initializer type, '
          'so the bool result is stored into an i64 slot (invalid module)',
    );
  });

  group('the concrete-slot paths are unchanged', () {
    test('String `.length`', () async {
      expect(
        await _run("int run() { String s = 'hello'; return s.length; }"),
        anyOf(isNull, equals(5)),
      );
    });

    test('List `.length`', () async {
      expect(
        await _run('int run() { var l = [1, 2, 3]; return l.length; }'),
        anyOf(isNull, equals(3)),
      );
    });

    test('nullable String parameter `?.length`', () async {
      // A concrete slot cannot hold Wasm's null, so `?.` here stays vacuous and
      // must keep compiling to the plain unboxed read.
      expect(
        await _run(
          'int run(String? s) { var n = s?.length; return n ?? -1; }',
          args: ['abcd'],
        ),
        anyOf(isNull, equals(4)),
      );
    });
  });
}
