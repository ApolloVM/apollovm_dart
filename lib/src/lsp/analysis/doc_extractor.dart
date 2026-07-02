// Recovers documentation comments from raw source. ApolloVM discards comments
// during parsing (they are consumed as whitespace), so hover documentation must
// be read back from the original text, immediately above a declaration.
//
// Supported forms directly above the declaration (no blank line between):
//   /// line doc      (Dart/C#/… )       # line doc   (Python/…)
//   /** block doc */
class DocExtractor {
  final String text;
  final List<int> _lineStarts;

  DocExtractor._(this.text, this._lineStarts);

  factory DocExtractor(String text) {
    final starts = <int>[0];
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0a) starts.add(i + 1);
    }
    return DocExtractor._(text, starts);
  }

  /// Returns the doc comment ending immediately above the declaration that
  /// starts at [declStart], or null if there is none.
  String? docFor(int declStart) {
    final declLine = _lineOf(declStart);
    if (declLine <= 0) return null;

    // Collect contiguous line-doc comments (`///` or leading `#`) upward.
    final lineDocs = <String>[];
    var line = declLine - 1;
    while (line >= 0) {
      final content = _lineText(line).trim();
      if (content.startsWith('///')) {
        lineDocs.add(content.substring(3).trimLeft());
      } else if (content.startsWith('#')) {
        lineDocs.add(content.substring(1).trimLeft());
      } else {
        break;
      }
      line--;
    }
    if (lineDocs.isNotEmpty) {
      return lineDocs.reversed.join('\n').trim();
    }

    // Otherwise look for a block comment `/** ... */` ending just above.
    final block = _blockDocAbove(declLine);
    if (block != null) return block;

    return null;
  }

  String? _blockDocAbove(int declLine) {
    // The line above must end a block comment.
    var line = declLine - 1;
    // Skip a single blank line is NOT allowed (docs must be adjacent).
    if (line < 0) return null;
    final upper = _lineText(line).trimRight();
    if (!upper.endsWith('*/')) return null;

    final collected = <String>[];
    // Walk up until the line that opens the block.
    while (line >= 0) {
      final content = _lineText(line);
      collected.add(content);
      if (content.trimLeft().startsWith('/*')) break;
      line--;
    }
    if (line < 0) return null;

    final raw = collected.reversed.join('\n');
    if (!raw.trimLeft().startsWith('/**')) return null;

    // Strip the comment delimiters and leading `*`.
    final cleaned = <String>[];
    for (var l in raw.split('\n')) {
      l = l.trim();
      if (l.startsWith('/**')) l = l.substring(3);
      if (l.endsWith('*/')) l = l.substring(0, l.length - 2);
      l = l.trim();
      if (l.startsWith('*')) l = l.substring(1).trimLeft();
      cleaned.add(l);
    }
    return cleaned.join('\n').trim();
  }

  int _lineOf(int offset) {
    var lo = 0, hi = _lineStarts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_lineStarts[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  String _lineText(int line) {
    final start = _lineStarts[line];
    final end = line + 1 < _lineStarts.length
        ? _lineStarts[line + 1] - 1
        : text.length;
    if (start >= text.length) return '';
    return text.substring(start, end < start ? start : end);
  }
}
