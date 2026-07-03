// Improves the *position* of parse-error diagnostics.
//
// ApolloVM's grammars are PEG/petitparser-based and, for most structural
// mistakes, report a generic "end of input expected" at offset 0 — technically
// correct but useless in an editor. This locator compensates entirely in the
// LSP layer (the core parser is untouched): it runs a bracket-balance scan over
// the raw source to find the real culprit, and only trusts the parser's own
// position when that position is concrete.

/// The chosen error location: a `[rangeStart, rangeEnd)` span to underline and
/// an optional human hint about the structural cause.
class ParseErrorLocation {
  final int offset;
  final int rangeStart;
  final int rangeEnd;
  final String? hint;

  const ParseErrorLocation({
    required this.offset,
    required this.rangeStart,
    required this.rangeEnd,
    this.hint,
  });
}

/// Picks the best error location for [text], given the parser's own
/// [parserPosition]/[parserMessage] (which may be unreliable).
ParseErrorLocation locateParseError(
  String text, {
  int? parserPosition,
  String? parserMessage,
}) {
  final structural = _bracketImbalance(text);
  final msg = (parserMessage ?? '').toLowerCase();

  // The parser position is trustworthy only when it is concrete: non-zero and
  // not the catch-all "end of input expected" that PEG parsers emit at 0.
  final parserConcrete =
      parserPosition != null &&
      parserPosition > 0 &&
      parserPosition <= text.length &&
      !msg.contains('end of input');

  int offset;
  String? hint;
  if (parserConcrete) {
    offset = parserPosition;
  } else if (structural != null) {
    offset = structural.offset;
    hint = structural.hint;
  } else if (parserPosition != null &&
      parserPosition > 0 &&
      parserPosition <= text.length) {
    offset = parserPosition;
  } else {
    offset = _firstMeaningfulOffset(text);
  }

  final (start, end) = _tokenRange(text, offset);
  return ParseErrorLocation(
    offset: offset,
    rangeStart: start,
    rangeEnd: end,
    hint: hint,
  );
}

/// Scans brackets (`()[]{}`) skipping strings and comments. Returns the first
/// unexpected/mismatched closer, or the outermost unclosed opener at EOF.
({int offset, String hint})? _bracketImbalance(String text) {
  final stack = <({int open, int off})>[];
  const closeOf = {0x28: 0x29, 0x5b: 0x5d, 0x7b: 0x7d}; // ( [ {
  const closers = {0x29, 0x5d, 0x7d}; // ) ] }
  final n = text.length;
  var i = 0;

  while (i < n) {
    final c = text.codeUnitAt(i);

    // Line/block comments.
    if (c == 0x2f && i + 1 < n) {
      final c2 = text.codeUnitAt(i + 1);
      if (c2 == 0x2f) {
        i += 2;
        while (i < n && text.codeUnitAt(i) != 0x0a) {
          i++;
        }
        continue;
      }
      if (c2 == 0x2a) {
        i += 2;
        var depth = 1;
        while (i < n && depth > 0) {
          if (i + 1 < n &&
              text.codeUnitAt(i) == 0x2f &&
              text.codeUnitAt(i + 1) == 0x2a) {
            depth++;
            i += 2;
          } else if (i + 1 < n &&
              text.codeUnitAt(i) == 0x2a &&
              text.codeUnitAt(i + 1) == 0x2f) {
            depth--;
            i += 2;
          } else {
            i++;
          }
        }
        continue;
      }
    }

    // Strings.
    if (c == 0x27 || c == 0x22) {
      i = _skipString(text, i);
      continue;
    }

    if (closeOf.containsKey(c)) {
      stack.add((open: c, off: i));
      i++;
      continue;
    }
    if (closers.contains(c)) {
      if (stack.isEmpty) {
        return (offset: i, hint: "unexpected '${text[i]}'");
      }
      final top = stack.last;
      if (closeOf[top.open] != c) {
        return (offset: i, hint: "mismatched '${text[i]}'");
      }
      stack.removeLast();
      i++;
      continue;
    }
    i++;
  }

  if (stack.isNotEmpty) {
    final o = stack.first;
    return (offset: o.off, hint: "'${text[o.off]}' is never closed");
  }
  return null;
}

/// Skips a string literal starting at [i] (single/double, incl. triple-quoted),
/// returning the index just past it.
int _skipString(String text, int i) {
  final n = text.length;
  final quote = text.codeUnitAt(i);
  if (i + 2 < n &&
      text.codeUnitAt(i + 1) == quote &&
      text.codeUnitAt(i + 2) == quote) {
    i += 3;
    while (i < n) {
      if (text.codeUnitAt(i) == 0x5c) {
        i += 2;
        continue;
      }
      if (i + 2 < n &&
          text.codeUnitAt(i) == quote &&
          text.codeUnitAt(i + 1) == quote &&
          text.codeUnitAt(i + 2) == quote) {
        return i + 3;
      }
      i++;
    }
    return i;
  }
  i++;
  while (i < n) {
    final c = text.codeUnitAt(i);
    if (c == 0x5c) {
      i += 2;
      continue;
    }
    if (c == quote) return i + 1;
    if (c == 0x0a) return i; // Unterminated; stop at newline.
    i++;
  }
  return i;
}

/// The first non-whitespace, non-comment offset, or 0.
int _firstMeaningfulOffset(String text) {
  final n = text.length;
  var i = 0;
  while (i < n) {
    final c = text.codeUnitAt(i);
    if (c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d) {
      i++;
      continue;
    }
    if (c == 0x2f && i + 1 < n) {
      final c2 = text.codeUnitAt(i + 1);
      if (c2 == 0x2f) {
        i += 2;
        while (i < n && text.codeUnitAt(i) != 0x0a) {
          i++;
        }
        continue;
      }
      if (c2 == 0x2a) {
        i += 2;
        while (i + 1 < n &&
            !(text.codeUnitAt(i) == 0x2a && text.codeUnitAt(i + 1) == 0x2f)) {
          i++;
        }
        i += 2;
        continue;
      }
    }
    return i;
  }
  return 0;
}

bool _isIdentPart(int c) =>
    (c >= 0x41 && c <= 0x5a) ||
    (c >= 0x61 && c <= 0x7a) ||
    (c >= 0x30 && c <= 0x39) ||
    c == 0x5f ||
    c == 0x24;

/// A `[start, end)` span covering the token at [offset]: the whole identifier
/// when [offset] sits on one, otherwise a single character (or the last content
/// character at/after end-of-file).
(int, int) _tokenRange(String text, int offset) {
  final n = text.length;
  if (n == 0) return (0, 0);
  if (offset >= n) return (n - 1, n);
  if (offset < 0) offset = 0;

  if (_isIdentPart(text.codeUnitAt(offset))) {
    var start = offset;
    var end = offset + 1;
    while (start > 0 && _isIdentPart(text.codeUnitAt(start - 1))) {
      start--;
    }
    while (end < n && _isIdentPart(text.codeUnitAt(end))) {
      end++;
    }
    return (start, end);
  }
  return (offset, offset + 1);
}
