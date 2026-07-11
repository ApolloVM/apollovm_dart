@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Parses [code] as Dart and returns the (failed) [ParseResult].
Future<ParseResult<String>> _parseDart(String code) async {
  var vm = ApolloVM();
  var result = await vm
      .getParser<String>('dart')!
      .parse(SourceCodeUnit('dart', code, id: 'test.dart'));
  return result;
}

/// Parses [code] with the parser for [language] and returns the [ParseResult].
Future<ParseResult<String>> _parse(String language, String code) async {
  var vm = ApolloVM();
  var result = await vm
      .getParser<String>(language)!
      .parse(SourceCodeUnit(language, code, id: 'test.$language'));
  return result;
}

void main() {
  // Before this feature every structural error collapsed to petitparser's
  // top-level "end of input expected" at offset 0 (line 1). The Dart parser now
  // re-parses on failure with a farthest-failure tracker and reports the error
  // at the deepest point the grammar actually reached — on/adjacent to the real
  // mistake. Each snippet is built from a list of lines so the 1-based line of
  // the real error equals its list index + 1.
  group('Dart parse-error position (farthest failure)', () {
    test('missing ";" is reported at the next token, not line 1', () async {
      final lines = [
        'int main() {', //         1
        '  var a = 1;', //         2
        '  var b = 2;', //         3
        '  var c = a + b', //      4  <-- missing ';'
        '  return c;', //          5  <-- reported here (";" expected before it)
        '}', //                    6
      ];
      final code = lines.join('\n');

      final result = await _parseDart(code);

      expect(result.hasError, isTrue);
      expect(result.errorLineAndColumn, isNotNull);
      expect(result.errorLineAndColumn![0], equals(5));
      expect(result.errorLineAndColumn![0], isNot(equals(1)));
      expect(result.errorPosition, equals(code.indexOf('return')));
      expect(result.errorMessage, contains(';'));
    });

    test('an invalid token mid-expression is reported at that token', () async {
      final lines = [
        'int compute() {', //     1
        '  var x = 10;', //       2
        '  var y = 20;', //       3
        '  var z = x @ y;', //    4  <-- invalid '@'
        '  return z;', //         5
        '}', //                   6
      ];
      final code = lines.join('\n');

      final result = await _parseDart(code);

      expect(result.hasError, isTrue);
      expect(result.errorLineAndColumn![0], equals(4));
      expect(result.errorPosition, equals(code.indexOf('@')));
    });

    test('garbage inside a class body is reported at that member', () async {
      final lines = [
        'class Foo {', //            1
        '  int x = 1;', //           2
        '  int y = 2;', //           3
        '  %%%', //                  4  <-- garbage
        '  int sum() => x + y;', //  5
        '}', //                      6
      ];
      final code = lines.join('\n');

      final result = await _parseDart(code);

      expect(result.hasError, isTrue);
      expect(result.errorLineAndColumn![0], equals(4));
      expect(result.errorPosition, equals(code.indexOf('%')));
    });

    test('errorMessageExtended points its caret at the real line', () async {
      final code = ['int f() {', '  return 1 2;', '}'].join('\n');

      final result = await _parseDart(code);

      expect(result.hasError, isTrue);
      // The offending line 2 (not line 1) is quoted with a caret.
      expect(result.errorLineAndColumn![0], equals(2));
      expect(result.errorMessageExtended, contains('return 1 2;'));
    });
  });

  group('Scope: only Dart tracks farthest failure (for now)', () {
    // The exact same broken source, fed to a language whose parser has not
    // opted in, still reports the old top-of-file position — proving the change
    // is gated to Dart and did not alter the shared behavior of other parsers.
    final code = [
      'int compute() {',
      '  var x = 10;',
      '  var y = 20;',
      '  var z = x @ y;',
      '  return z;',
      '}',
    ].join('\n');

    test('Dart reports the real line', () async {
      final result = await _parse('dart', code);
      expect(result.hasError, isTrue);
      expect(result.errorLineAndColumn![0], equals(4));
    });

    test('Java (not opted in) is unchanged: reports line 1', () async {
      final result = await _parse('java11', code);
      expect(result.hasError, isTrue);
      expect(result.errorLineAndColumn![0], equals(1));
    });
  });
}
