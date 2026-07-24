@TestOn('vm')
@Tags(['wasm'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Compiles [src] (Dart) to a Wasm module and returns its bytes. Fails the test
/// if the null-safety construct cannot be lowered to Wasm.
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

/// Compiles then, when a Wasm runtime is available on this platform (e.g. under
/// the `wasm-chrome` tag), also executes [functionName] and returns its value.
/// On platforms without a Wasm runtime the execution is skipped and `null` is
/// returned — the compilation assertion above is the portable guarantee.
Future<Object?> _compileAndMaybeRun(
  String src,
  String functionName,
  List args,
) async {
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
    // No Wasm runtime on this platform — codegen already verified above.
    if (e.message.contains('not supported on this platform')) return null;
    rethrow;
  }
}

void main() {
  group('Wasm null-safety codegen (non-null numeric domain)', () {
    test('null-assertion (x!) compiles and is a no-op', () async {
      var r = await _compileAndMaybeRun(
        'int f(int a) { int? x = a; return x!; }',
        'f',
        [7],
      );
      if (r != null) expect(r, 7);
    });

    test('null-coalescing (a ?? b) compiles to its left operand', () async {
      var r = await _compileAndMaybeRun(
        'int f(int a, int b) { int? x = a; return x ?? b; }',
        'f',
        [3, 9],
      );
      if (r != null) expect(r, 3);
    });

    test('nullable-typed parameters/locals compile', () async {
      // Exercises `int?` in parameter, local and return positions.
      await _compile('int f(int? a, int b) { int? x = a ?? b; return x!; }');
    });

    test('null-aware field access (a?.x) compiles', () async {
      await _compile('class A { int x = 5; } int f(A a) { return a?.x; }');
    });

    test('a null literal in a concrete numeric slot is a clean error', () async {
      // `int` is i64 in Wasm and has no encoding for `null`, so this is an
      // explicit unsupported-construct error — not a silent miscompilation, and
      // not a module that fails to validate.
      await expectLater(
        _compile('int f(int b) { int? x = null; return x ?? b; }'),
        throwsA(isA<UnsupportedSyntaxError>()),
      );
    });

    test('a null literal in a String slot is a clean error', () async {
      await expectLater(
        _compile('int f() { String? s = null; return 0; }'),
        throwsA(isA<UnsupportedSyntaxError>()),
      );
    });
  });

  // `null` *is* representable in the boxed-`Object` domain: it is the box
  // pointer 0 (it needs no cell, and the heap never allocates at address 0).
  group('Wasm null in the boxed-Object domain', () {
    test('a null literal compiles in a `var` / `Object?` slot', () async {
      await _compile('int f(int n) { var a = n > 0 ? 1 : null; return 0; }');
      await _compile('Object? f() { return null; }');
    });

    test('a `null` arm in a ternary boxes the other arm', () async {
      // Both arms must agree on the block's result type, so the `int` arm is
      // boxed rather than left as an i64 (which would not validate).
      var whenNull = await _compileAndMaybeRun(
        'Object? f(int n) { return n > 0 ? 1 : null; }',
        'f',
        [0],
      );
      expect(whenNull, isNull);

      var whenValue = await _compileAndMaybeRun(
        'Object? f(int n) { return n > 0 ? 1 : null; }',
        'f',
        [5],
      );
      if (whenValue != null) expect(whenValue, 1);
    });

    test('`== null` distinguishes the null box from a value', () async {
      const src =
          'int f(int n) { Object? a = n > 0 ? 1 : null; '
          'if (a == null) { return -1; } return 1; }';

      var isNullCase = await _compileAndMaybeRun(src, 'f', [0]);
      if (isNullCase != null) expect(isNullCase, -1);

      var notNullCase = await _compileAndMaybeRun(src, 'f', [5]);
      if (notNullCase != null) expect(notNullCase, 1);
    });

    test('`??` falls back when the boxed left operand is null', () async {
      // In the *numeric* domain `a ?? b` still yields `a` (a number is never
      // null); a boxed operand is tested against the null box.
      const src =
          'Object? f(int n) { Object? a = n > 0 ? 1 : null; return a ?? 99; }';

      var fellBack = await _compileAndMaybeRun(src, 'f', [0]);
      if (fellBack != null) expect(fellBack, 99);

      var kept = await _compileAndMaybeRun(src, 'f', [5]);
      if (kept != null) expect(kept, 1);
    });
  });
}
