@Tags(['java', 'kotlin', 'go', 'csharp', 'javascript', 'typescript', 'lua'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Parses [code] with the parser for [language] and returns the [ParseResult].
Future<ParseResult<String>> _parse(String language, List<String> lines) async {
  final vm = ApolloVM();
  final code = lines.join('\n');
  final result = await vm
      .getParser<String>(language)!
      .parse(SourceCodeUnit(language, code, id: 'test.$language'));
  return result;
}

void main() {
  // Every ApolloVM grammar's top rule is `compilationUnit().star().trim().end()`,
  // so before farthest-failure tracking a deep structural error collapsed to a
  // generic "end of input expected" at offset 0 (line 1) — see the baseline in
  // the PR description. With tracking enabled the error is reported at the
  // farthest point the grammar actually reached: the offending token itself.
  //
  // Each case is valid in its language except for one invalid token ('@') on a
  // known line; snippets are built from a list so the 1-based error line equals
  // its list index + 1, and the reported offset must be exactly at the token.
  group('parse-error position lands on the real token (farthest failure)', () {
    test('Java 11', () async {
      final lines = [
        'class Foo {', //             1
        '  int compute() {', //       2
        '    int x = 10;', //         3
        '    int y = 20;', //         4
        '    int z = x @ y;', //      5  <-- invalid '@'
        '    return z;', //           6
        '  }', //                     7
        '}', //                       8
      ];
      final r = await _parse('java11', lines);
      expect(r.hasError, isTrue);
      expect(r.errorLineAndColumn![0], equals(5));
      expect(r.errorPosition, equals(lines.join('\n').indexOf('@')));
    });

    test('C#', () async {
      final lines = [
        'class Foo {', //             1
        '  int Compute() {', //       2
        '    int x = 10;', //         3
        '    int y = 20;', //         4
        '    int z = x @ y;', //      5  <-- invalid '@'
        '    return z;', //           6
        '  }', //                     7
        '}', //                       8
      ];
      final r = await _parse('csharp', lines);
      expect(r.hasError, isTrue);
      expect(r.errorLineAndColumn![0], equals(5));
      expect(r.errorPosition, equals(lines.join('\n').indexOf('@')));
    });

    test('JavaScript', () async {
      final lines = [
        'function compute() {', //    1
        '  var x = 10;', //           2
        '  var y = 20;', //           3
        '  var z = x @ y;', //        4  <-- invalid '@'
        '  return z;', //             5
        '}', //                       6
      ];
      final r = await _parse('javascript', lines);
      expect(r.hasError, isTrue);
      expect(r.errorLineAndColumn![0], equals(4));
      expect(r.errorPosition, equals(lines.join('\n').indexOf('@')));
    });

    test('TypeScript', () async {
      final lines = [
        'function compute(): number {', // 1
        '  let x = 10;', //                2
        '  let y = 20;', //                3
        '  let z = x @ y;', //             4  <-- invalid '@'
        '  return z;', //                  5
        '}', //                            6
      ];
      final r = await _parse('typescript', lines);
      expect(r.hasError, isTrue);
      expect(r.errorLineAndColumn![0], equals(4));
      expect(r.errorPosition, equals(lines.join('\n').indexOf('@')));
    });

    test('Kotlin', () async {
      final lines = [
        'fun compute(): Int {', //    1
        '  val x = 10', //            2
        '  val y = 20', //            3
        '  val z = x @ y', //         4  <-- invalid '@'
        '  return z', //              5
        '}', //                       6
      ];
      final r = await _parse('kotlin', lines);
      expect(r.hasError, isTrue);
      expect(r.errorLineAndColumn![0], equals(4));
      expect(r.errorPosition, equals(lines.join('\n').indexOf('@')));
    });

    test('Go', () async {
      final lines = [
        'package main', //            1
        'func compute() int {', //    2
        '  x := 10', //               3
        '  y := 20', //               4
        '  z := x @ y', //            5  <-- invalid '@'
        '  return z', //              6
        '}', //                       7
      ];
      final r = await _parse('go', lines);
      expect(r.hasError, isTrue);
      expect(r.errorLineAndColumn![0], equals(5));
      expect(r.errorPosition, equals(lines.join('\n').indexOf('@')));
    });

    test('Lua', () async {
      final lines = [
        'function compute()', //      1
        '  local x = 10', //          2
        '  local y = 20', //          3
        '  local z = x @ y', //       4  <-- invalid '@'
        '  return z', //              5
        'end', //                     6
      ];
      final r = await _parse('lua', lines);
      expect(r.hasError, isTrue);
      expect(r.errorLineAndColumn![0], equals(4));
      expect(r.errorPosition, equals(lines.join('\n').indexOf('@')));
    });
  });

  group('Python is intentionally excluded (preprocessed coordinates)', () {
    // Python source is rewritten by the indentation preprocessor before the
    // grammar sees it, so tracking is left off (see ApolloParserPython). It
    // still reports the old generic top-of-file position rather than a
    // plausible-but-wrong line in preprocessed space.
    test('reports the generic offset-0 position, not a shifted line', () async {
      final lines = [
        'def compute():', //          1
        '    x = 10', //              2
        '    y = 20', //              3
        r'    z = x $ y', //          4  ('$' is invalid in Python)
        '    return z', //            5
      ];
      final r = await _parse('python', lines);
      expect(r.hasError, isTrue);
      expect(r.errorLineAndColumn![0], equals(1));
    });
  });
}
