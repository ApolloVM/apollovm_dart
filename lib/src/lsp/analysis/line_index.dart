// Maps between raw string offsets and LSP `(line, character)` positions.
//
// Dart strings are sequences of UTF-16 code units, and string offsets are
// therefore already UTF-16 offsets — exactly what LSP `character` counts — so
// no re-encoding is needed. Line breaks recognised: `\n`, `\r\n`, and lone `\r`.
import '../protocol/protocol.dart';

class LineIndex {
  final String text;

  /// Offset at which each line starts. `_lineStarts[0] == 0`.
  final List<int> _lineStarts;

  LineIndex._(this.text, this._lineStarts);

  factory LineIndex(String text) {
    final starts = <int>[0];
    final len = text.length;
    for (var i = 0; i < len; i++) {
      final c = text.codeUnitAt(i);
      if (c == 0x0a) {
        starts.add(i + 1);
      } else if (c == 0x0d) {
        // `\r\n` is handled by the `\n` branch; a lone `\r` starts a new line.
        if (i + 1 >= len || text.codeUnitAt(i + 1) != 0x0a) {
          starts.add(i + 1);
        }
      }
    }
    return LineIndex._(text, starts);
  }

  int get lineCount => _lineStarts.length;

  /// Converts a UTF-16 [offset] into a [Position].
  Position positionAt(int offset) {
    if (offset <= 0) return const Position(0, 0);
    if (offset > text.length) offset = text.length;

    // Binary search for the greatest line start <= offset.
    var lo = 0, hi = _lineStarts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_lineStarts[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return Position(lo, offset - _lineStarts[lo]);
  }

  /// Converts a [Position] into a UTF-16 offset (clamped to the document).
  int offsetAt(Position position) {
    final line = position.line;
    if (line < 0) return 0;
    if (line >= _lineStarts.length) return text.length;
    final base = _lineStarts[line];
    final lineEnd =
        line + 1 < _lineStarts.length ? _lineStarts[line + 1] : text.length;
    final offset = base + position.character;
    if (offset < base) return base;
    if (offset > lineEnd) return lineEnd;
    return offset;
  }

  /// Builds a [Range] from a `[start, end)` offset pair.
  Range rangeAt(int start, int end) => Range(positionAt(start), positionAt(end));
}
