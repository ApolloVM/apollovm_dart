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

    test('the null literal remains an unsupported Wasm construct', () async {
      // Wasm has no `null` value; assigning a null literal is a clean error,
      // not a silent miscompilation.
      await expectLater(
        _compile('int f(int b) { int? x = null; return x ?? b; }'),
        throwsA(anyOf(isA<UnimplementedError>(), isA<UnsupportedError>())),
      );
    });
  });
}
