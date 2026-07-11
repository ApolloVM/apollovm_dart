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

/// Languages where a statement must end in `;`, so a missing terminator is a
/// real, locatable error (unlike Kotlin's optional `;`, JavaScript's ASI, or
/// Lua/Python which have none).
const _semicolonLanguages = {'dart', 'java', 'java11', 'csharp'};

/// Picks the best error location for [text], given the parser's own
/// [parserPosition]/[parserMessage] (which may be unreliable). [language]
/// enables language-specific recovery (e.g. a missing `;`).
ParseErrorLocation locateParseError(
  String text, {
  int? parserPosition,
  String? parserMessage,
  String? language,
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
  if (structural != null) {
    // A bracket imbalance is the most fundamental structural fault — trust it
    // over any parser position, and describe it (e.g. "'(' is never closed").
    offset = structural.offset;
    hint = structural.hint;
  } else {
    // Brackets balance. Prefer a confidently-located missing statement
    // terminator (reported at the end of the offending value — the editor
    // convention) before trusting the parser's own position.
    final missing = (language != null && _semicolonLanguages.contains(language))
        ? _missingTerminator(text)
        : null;
    if (missing != null) {
      offset = missing.offset;
      hint = missing.hint;
    } else if (parserConcrete) {
      // A concrete parser position; with farthest-failure tracking (Dart) this
      // now lands on or next to the real error (e.g. a bad token mid-line).
      offset = parserPosition;
    } else if (parserPosition != null &&
        parserPosition > 0 &&
        parserPosition <= text.length) {
      offset = parserPosition;
    } else {
      offset = _firstMeaningfulOffset(text);
    }
  }

  final (start, end) = _tokenRange(text, offset);
  return ParseErrorLocation(
    offset: offset,
    rangeStart: start,
    rangeEnd: end,
    hint: hint,
  );
}

/// Finds a likely missing statement terminator (`;`) in [text] for a
/// `;`-required language, returning where the terminator should go (the end of
/// the offending value) and a hint, or null when nothing is confidently found.
///
/// Deliberately conservative — it only fires when a statement clearly ends in a
/// value (identifier, number or string literal) on one line and the next
/// significant token starts a new statement (an identifier or `}`), skipping
/// every continuation shape (operators, `.`, `?`, `:`, `,`, an open bracket, a
/// continuation keyword like `return`, or an annotation). A false negative just
/// falls back to the old behaviour; a false positive would mislocate, so the
/// guards err toward silence.
({int offset, String hint})? _missingTerminator(String text) {
  final n = text.length;
  var i = 0;
  var line = 0;

  int? lastSig; // last significant code unit
  var lastSigOff = -1;
  var lastSigLine = -1;
  var lastWord = '';
  var lastWasAnnotation = false;

  while (i < n) {
    final c = text.codeUnitAt(i);

    if (c == 0x0a) {
      line++;
      i++;
      continue;
    }
    if (c == 0x0d || c == 0x20 || c == 0x09) {
      i++;
      continue;
    }

    // Comments.
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
          if (text.codeUnitAt(i) == 0x0a) line++;
          i++;
        }
        i += 2;
        continue;
      }
    }

    // A string literal counts as a value end.
    if (c == 0x27 || c == 0x22) {
      final end = _skipString(text, i);
      for (var k = i; k < end && k < n; k++) {
        if (text.codeUnitAt(k) == 0x0a) line++;
      }
      lastSig = c;
      lastSigOff = end - 1;
      lastSigLine = line;
      lastWord = '';
      lastWasAnnotation = false;
      i = end;
      continue;
    }

    // A new significant token begins on a later line than the previous one:
    // decide whether a `;` is missing in between.
    if (lastSig != null &&
        line > lastSigLine &&
        _isValueEnd(lastSig) &&
        !lastWasAnnotation &&
        !_continuationKeywords.contains(lastWord) &&
        _isStatementStart(c)) {
      return (offset: lastSigOff, hint: "expected ';'");
    }

    // Advance, recording the new last-significant token.
    if (_isIdentPart(c)) {
      final s = i;
      while (i < n && _isIdentPart(text.codeUnitAt(i))) {
        i++;
      }
      lastWord = text.substring(s, i);
      lastWasAnnotation = s > 0 && text.codeUnitAt(s - 1) == 0x40; // '@'
      lastSig = text.codeUnitAt(i - 1);
      lastSigOff = i - 1;
      lastSigLine = line;
      continue;
    }

    lastSig = c;
    lastSigOff = i;
    lastSigLine = line;
    lastWord = '';
    lastWasAnnotation = false;
    i++;
  }

  return null;
}

/// Keywords that legitimately end a line with more to follow, so a newline after
/// them is not a missing terminator.
const _continuationKeywords = {
  'return',
  'throw',
  'yield',
  'new',
  'await',
  'else',
  'in',
  'is',
  'as',
  'extends',
  'implements',
  'with',
  'on',
  'case',
  'default',
  'do',
  'try',
  'finally',
  'get',
  'set',
  'async',
  'sync',
  'operator',
  'typedef',
};

/// Whether [c] can end a value/expression (identifier char, digit, or a quote
/// standing in for a string literal).
bool _isValueEnd(int c) => _isIdentPart(c) || c == 0x22 || c == 0x27;

/// Whether [c] can start a new statement: an identifier start or a `}` (a value
/// immediately before a closing brace also wants its `;`).
bool _isStatementStart(int c) =>
    (c >= 0x41 && c <= 0x5a) ||
    (c >= 0x61 && c <= 0x7a) ||
    c == 0x5f ||
    c == 0x24 ||
    c == 0x7d;

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
