import 'package:apollovm/apollovm_lsp.dart';
import 'package:test/test.dart';

void main() {
  group('DocExtractor', () {
    test('collects contiguous /// line docs', () {
      const src = '/// Line one.\n/// Line two.\nclass Foo {}\n';
      final doc = DocExtractor(src).docFor(src.indexOf('class'));
      expect(doc, 'Line one.\nLine two.');
    });

    test('reads a single-line /** */ block', () {
      const src = '/** Block doc. */\nint x;\n';
      final doc = DocExtractor(src).docFor(src.indexOf('int x'));
      expect(doc, 'Block doc.');
    });

    test('reads a multi-line /** */ block, stripping leading `*`', () {
      const src = '/**\n * Hello.\n * World.\n */\nint y;\n';
      final doc = DocExtractor(src).docFor(src.indexOf('int y'));
      expect(doc, 'Hello.\nWorld.');
    });

    test('reads `#` line comments (Python-style)', () {
      const src = '# A function.\ndef f():\n';
      final doc = DocExtractor(src).docFor(src.indexOf('def'));
      expect(doc, 'A function.');
    });

    test('returns null when there is no doc comment', () {
      const src = 'int z;\n';
      expect(DocExtractor(src).docFor(src.indexOf('int z')), isNull);
    });

    test('returns null when a blank line separates doc from declaration', () {
      const src = '/// Doc.\n\nclass Bar {}\n';
      expect(DocExtractor(src).docFor(src.indexOf('class Bar')), isNull);
    });

    test('returns null for a declaration on the first line', () {
      const src = 'class First {}\n';
      expect(DocExtractor(src).docFor(0), isNull);
    });
  });
}
