import 'package:apollovm/apollovm_lsp.dart';
import 'package:test/test.dart';

void main() {
  group('LineIndex', () {
    test('maps offsets to positions across lines', () {
      final idx = LineIndex('abc\ndef\nghi');
      expect(idx.positionAt(0).toString(), '0:0');
      expect(idx.positionAt(2).toString(), '0:2');
      expect(idx.positionAt(4).toString(), '1:0');
      expect(idx.positionAt(8).toString(), '2:0');
      expect(idx.positionAt(10).toString(), '2:2');
    });

    test('round-trips position <-> offset', () {
      const text = 'one two\nthree\n\nfour';
      final idx = LineIndex(text);
      for (var o = 0; o <= text.length; o++) {
        expect(idx.offsetAt(idx.positionAt(o)), o, reason: 'offset $o');
      }
    });

    test('handles CRLF and lone CR line breaks', () {
      final idx = LineIndex('a\r\nb\rc');
      expect(idx.lineCount, 3);
      expect(idx.positionAt(3).toString(), '1:0'); // 'b'
      expect(idx.positionAt(5).toString(), '2:0'); // 'c'
    });

    test('clamps out-of-range offsets', () {
      final idx = LineIndex('abc');
      expect(idx.positionAt(-5).toString(), '0:0');
      expect(idx.positionAt(999).toString(), '0:3');
    });
  });
}
