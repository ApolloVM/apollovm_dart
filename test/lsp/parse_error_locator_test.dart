import 'package:apollovm/apollovm_lsp.dart';
import 'package:test/test.dart';

void main() {
  group('locateParseError (unit)', () {
    test('points at the outermost unclosed opener', () {
      const src = 'int sum(int a, int b {\n  return a;\n}\n';
      // Parser is unreliable here (offset 0 / "end of input expected").
      final loc = locateParseError(
        src,
        parserPosition: 0,
        parserMessage: 'end of input expected',
      );
      expect(loc.rangeStart, src.indexOf('('));
      expect(loc.hint, contains("'(' is never closed"));
    });

    test('points at the unclosed class body brace when a `}` is missing', () {
      const src = 'class A {\n  int x;\n  int f() {\n    return x;\n}\n';
      final loc = locateParseError(
        src,
        parserPosition: 0,
        parserMessage: 'end of input expected',
      );
      expect(loc.rangeStart, src.indexOf('{'));
      expect(loc.hint, contains('never closed'));
    });

    test('flags an unexpected extra closer', () {
      const src = 'int f() {\n  return 1;\n}}\n';
      final loc = locateParseError(
        src,
        parserPosition: 0,
        parserMessage: 'end of input expected',
      );
      expect(loc.rangeStart, src.lastIndexOf('}'));
      expect(loc.hint, contains("unexpected '}'"));
    });

    test('flags a mismatched closer', () {
      const src = 'foo(a]';
      final loc = locateParseError(
        src,
        parserPosition: 0,
        parserMessage: 'end of input expected',
      );
      expect(loc.rangeStart, src.indexOf(']'));
      expect(loc.hint, contains("mismatched ']'"));
    });

    test('ignores brackets inside strings and comments', () {
      const src = 'var s = "a ( b [ c { d";\n// ) ] }\nint x;\n';
      // Brackets are all inside a string/comment, so nothing is unbalanced.
      final loc = locateParseError(
        src,
        parserPosition: 0,
        parserMessage: 'end of input expected',
      );
      // Falls back to the first meaningful token, not a spurious bracket.
      expect(loc.hint, isNull);
      expect(loc.rangeStart, src.indexOf('var'));
    });

    test('trusts a concrete parser position when brackets are balanced', () {
      const src = 'int x = 3y;';
      final loc = locateParseError(
        src,
        parserPosition: 8,
        parserMessage: 'digit expected',
      );
      expect(loc.offset, 8);
      expect(loc.hint, isNull);
    });

    test('snaps the range to the whole identifier at the offset', () {
      const src = 'return foobar;';
      final loc = locateParseError(
        src,
        parserPosition: 9,
        parserMessage: 'something expected',
      );
      // Offset 9 is inside `foobar`; the range should cover it fully.
      expect(src.substring(loc.rangeStart, loc.rangeEnd), 'foobar');
    });

    test('ignores brackets inside triple-quoted strings', () {
      const src = "var s = '''( [ {''';\nint x;\n";
      final loc = locateParseError(
        src,
        parserPosition: 0,
        parserMessage: 'end of input expected',
      );
      expect(loc.hint, isNull);
    });

    test('skips leading comments when falling back to first token', () {
      const src = '// a comment\n/* block */\nvalue;\n';
      final loc = locateParseError(
        src,
        parserPosition: 0,
        parserMessage: 'end of input expected',
      );
      expect(loc.rangeStart, src.indexOf('value'));
    });

    test('uses a non-zero parser position when brackets are balanced but the '
        'message is generic', () {
      const src = 'int a; int b; garbage';
      final loc = locateParseError(
        src,
        parserPosition: 7,
        parserMessage: 'end of input expected',
      );
      expect(loc.offset, 7);
    });

    test('handles a position at end-of-input', () {
      const src = 'abc';
      final loc = locateParseError(
        src,
        parserPosition: 3,
        parserMessage: 'x expected',
      );
      expect(loc.rangeStart, 2);
      expect(loc.rangeEnd, 3);
    });

    test('empty source yields a zero-width range', () {
      final loc = locateParseError('', parserPosition: 0, parserMessage: '');
      expect(loc.rangeStart, 0);
      expect(loc.rangeEnd, 0);
    });
  });

  group('parse-error diagnostics (integration)', () {
    final analyzer = Analyzer();

    test('an unclosed "(" no longer reports at 0:0', () async {
      const src = 'int sum(int a, int b {\n  return a;\n}\n';
      final unit = await analyzer.analyze('file:///bad.dart', src);
      expect(unit.ast, isNull);
      final d = unit.diagnostics.single;
      // Lands on the `(` (line 0), not the top of file with a 1-char range.
      final expected = unit.lineIndex.positionAt(src.indexOf('('));
      expect(d.range.start.line, expected.line);
      expect(d.range.start.character, expected.character);
      expect(d.message, contains('never closed'));
    });
  });
}
