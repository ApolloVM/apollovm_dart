@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Generation-only coverage for constructs whose per-language *output* cannot
/// be pinned by the round-trip harness in `test/tests_definitions/`.
///
/// The harness re-parses and re-executes every generated source, which is the
/// stronger check — but it can only cover targets whose own grammar parses what
/// their generator emits. Java's `assert c : m;`, Python's `assert c, m`,
/// C#'s `Debug.Assert` and Kotlin's `assert(c) { m }` are correct for those
/// languages' real toolchains, yet ApolloVM neither parses them back nor
/// provides `Debug`/`assert` as VM builtins. Same for the Kotlin and Lua
/// compound-assignment lowering: no other grammar accepts `&=` to begin with.
///
/// So these assert on the emitted text directly.

Future<String> _generate(String dartSource, String language) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(
    SourceCodeUnit('dart', dartSource, id: 'test'),
  );
  expect(ok, isTrue, reason: "Can't load Dart source");

  var storage = vm.generateAllCodeIn(language);
  await storage.writeAllSources();

  var out = StringBuffer();
  for (var ns in await storage.getNamespaces()) {
    for (var id in await storage.getNamespaceCodeUnitsIDs(ns)) {
      out.writeln(await storage.getNamespaceCodeUnit(ns, id));
    }
  }
  return out.toString();
}

const _assertSource = r'''
class Checks {
  static void run(int n) {
    assert(n >= 0);
    assert(n < 10, 'too big');
  }
}
''';

const _compoundSource = r'''
class Bits {
  static int run(int n) {
    var a = n;
    a %= 7;
    a &= 12;
    a |= 1;
    a ^= 2;
    a <<= 3;
    a >>= 1;
    return a;
  }
}
''';

void main() {
  group('assert emission', () {
    // Each entry: the target language, the bare form, and the form with a
    // message.
    const cases = <String, (String, String)>{
      'dart': ('assert(n >= 0);', "assert(n < 10, 'too big');"),
      'java11': ('assert n >= 0;', 'assert n < 10 : "too big";'),
      'python': ('assert n >= 0', "assert n < 10, 'too big'"),
      'kotlin': ('assert(n >= 0)', 'assert(n < 10) { "too big" }'),
      'csharp': ('Debug.Assert(n >= 0);', 'Debug.Assert(n < 10, "too big");'),
      // Lua's `assert(v, message)` is a built-in, so no `;`.
      'lua': ('assert(n >= 0)', 'assert(n < 10, "too big")'),
      // No throwing `assert` exists: lowered to an explicit check.
      'javascript': (
        "if (!(n >= 0)) throw 'Assertion failed';",
        "if (!(n < 10)) throw 'too big';",
      ),
      'typescript': (
        "if (!(n >= 0)) throw 'Assertion failed';",
        "if (!(n < 10)) throw 'too big';",
      ),
    };

    for (var entry in cases.entries) {
      var language = entry.key;
      var (bare, withMessage) = entry.value;

      test('$language emits its own idiom', () async {
        var code = await _generate(_assertSource, language);
        expect(
          code,
          contains(bare),
          reason: 'bare assert in $language:\n$code',
        );
        expect(
          code,
          contains(withMessage),
          reason: 'assert with message in $language:\n$code',
        );
      });
    }

    test('go has no assert: lowered to a check plus panic', () async {
      var code = await _generate(_assertSource, 'go');
      expect(code, contains('if !(n >= 0) {'));
      expect(code, contains('panic("Assertion failed")'));
      expect(code, contains('if !(n < 10) {'));
      expect(code, contains('panic("too big")'));
    });
  });

  group('compound assignment emission', () {
    test('targets with the compound form keep it', () async {
      for (var language in ['dart', 'java11', 'csharp', 'javascript']) {
        var code = await _generate(_compoundSource, language);
        for (var op in ['a %= 7', 'a &= 12', 'a |= 1', 'a <<= 3', 'a >>= 1']) {
          expect(code, contains(op), reason: '$op in $language:\n$code');
        }
      }
    });

    test('kotlin lowers bitwise/shift to its infix functions', () async {
      var code = await _generate(_compoundSource, 'kotlin');

      // Kotlin *does* have `%=`.
      expect(code, contains('a %= 7'));

      // It has no compound form for the bitwise/shift operators.
      expect(code, contains('a = a and 12'));
      expect(code, contains('a = a or 1'));
      expect(code, contains('a = a xor 2'));
      expect(code, contains('a = a shl 3'));
      expect(code, contains('a = a shr 1'));
    });

    test('lua has no compound assignment at all', () async {
      var code = await _generate(_compoundSource, 'lua');

      expect(code, contains('a = a % 7'));
      expect(code, contains('a = a & 12'));
      expect(code, contains('a = a | 1'));
      expect(code, contains('a = a ~ 2'));
      expect(code, contains('a = a << 3'));
      expect(code, contains('a = a >> 1'));

      // Regression: the generator used to emit `a += 1`, which is not Lua.
      expect(code, isNot(contains('+=')));
      expect(code, isNot(contains('&=')));
    });
  });
}
