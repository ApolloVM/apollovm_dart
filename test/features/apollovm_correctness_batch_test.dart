@TestOn('vm')
@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

Future<Object?> _runFunc(
  String language,
  String source,
  String function, [
  List args = const [],
]) async {
  var vm = ApolloVM();
  expect(
    await vm.loadCodeUnit(SourceCodeUnit(language, source, id: 'test')),
    isTrue,
    reason: '$language: cannot parse',
  );
  var r = await vm
      .createRunner(language)!
      .executeFunction('', function, positionalParameters: args);
  return r.getValueNoContext();
}

Future<Object?> _runStatic(
  String language,
  String source,
  String className,
  String method,
) async {
  var vm = ApolloVM();
  expect(
    await vm.loadCodeUnit(SourceCodeUnit(language, source, id: 'test')),
    isTrue,
    reason: '$language: cannot parse',
  );
  var r = await vm
      .createRunner(language)!
      .executeClassMethod(
        '',
        className,
        method,
        positionalParameters: const [[]],
        classInstanceFields: const {},
      );
  return r.getValueNoContext();
}

void main() {
  // Guard rails for the per-language `/` semantics. These are DELIBERATELY
  // different and must not be "unified": Dart/JS/TS/Python map `/` to a
  // double-division (`divideAsDouble`), while Java/C#/Go/Kotlin `/` on ints is
  // truncating integer division (`divide`). A single interpreter serves both,
  // so the grammar chooses the operator per language.
  group('Division semantics are per-language (regression guard)', () {
    test('Dart `int / int` yields a double', () async {
      expect(
        await _runFunc('dart', 'double run() { return 7 / 2; }', 'run'),
        equals(3.5),
      );
      expect(
        await _runFunc('dart', 'bool run() { return (7 / 2) == 3.5; }', 'run'),
        isTrue,
      );
    });

    test('Java `int / int` truncates to int', () async {
      expect(
        await _runStatic(
          'java11',
          'class M { static int run() { return 7 / 2; } }',
          'M',
          'run',
        ),
        equals(3),
      );
    });

    test('C# `int / int` truncates to int', () async {
      expect(
        await _runStatic(
          'csharp',
          'class M { static int run() { return 7 / 2; } }',
          'M',
          'run',
        ),
        equals(3),
      );
    });
  });

  // Previously `~/=` (Dart) and `//=` (Python, rewritten to `~/=`) matched the
  // grammar but had no case in `getASTAssignmentOperator`, so the `.map` action
  // threw an uncaught `UnsupportedError` out of `loadCodeUnit`. `%=` had the
  // same shape in JavaScript/TypeScript: listed in the grammar, missing from
  // the enum. `ASTAssignmentOperator` now covers the full set
  // (`%= &= |= ^= <<= >>=` alongside the originals), so all of them parse.
  group('Compound assignment operators', () {
    test('Dart `~/=` parses and truncates', () async {
      expect(
        await _runFunc(
          'dart',
          'int run() { int x = 10; x ~/= 3; return x; }',
          'run',
        ),
        equals(3),
      );
    });

    test('Python `//=` parses and truncates', () async {
      expect(
        await _runFunc(
          'python',
          'def run():\n    x = 10\n    x //= 3\n    return x\n',
          'run',
        ),
        equals(3),
      );
    });

    test('JavaScript `%=` parses and takes the remainder', () async {
      expect(
        await _runFunc(
          'javascript',
          'function run() { var x = 10; x %= 3; return x; }',
          'run',
        ),
        equals(1),
      );
    });

    test('Dart bitwise and shift compound operators', () async {
      expect(
        await _runFunc(
          'dart',
          'int run() { int x = 23; x &= 12; x |= 1; x ^= 2; '
              'x <<= 3; x >>= 1; return x; }',
          'run',
        ),
        // 23&12=4, |1=5, ^2=7, <<3=56, >>1=28.
        equals(28),
      );
    });
  });

  // `Enum.values` used to be built with a `dynamic` element type while its
  // declared type is `List<Enum>`, so assigning it failed the declaration cast.
  group('Enum.values carries the enum element type', () {
    const color = 'enum Color { red, green, blue }\n';

    test('iterating Color.values', () async {
      expect(
        await _runFunc(
          'dart',
          '${color}String run() { var s = ""; '
              'for (var c in Color.values) { s = s + c.name; } return s; }',
          'run',
        ),
        equals('redgreenblue'),
      );
    });

    test('assigning Color.values to a typed List<Color>', () async {
      expect(
        await _runFunc(
          'dart',
          '${color}int run() { List<Color> cs = Color.values; return cs.length; }',
          'run',
        ),
        equals(3),
      );
    });

    test('assigning Color.values to a var', () async {
      expect(
        await _runFunc(
          'dart',
          '${color}int run() { var cs = Color.values; return cs.length; }',
          'run',
        ),
        equals(3),
      );
    });
  });

  // `ASTValue.fromValue<int>(4.5)` used to throw a raw Dart `TypeError` from an
  // internal cast; it now throws a clean `ApolloVMCastException`.
  group('ASTValue.fromValue narrowing', () {
    test('non-whole double to int throws ApolloVMCastException', () {
      expect(
        () => ASTValue.fromValue<int>(4.5),
        throwsA(isA<ApolloVMCastException>()),
      );
    });

    test('whole double to int narrows cleanly', () {
      var v = ASTValue.fromValue<int>(4.0);
      expect(v, isA<ASTValueInt>());
      expect(v.getValueNoContext(), equals(4));
    });
  });
}
