// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import '../../apollovm_base.dart';
import '../../apollovm_parser.dart';
import 'python_grammar.dart';
import 'python_grammar_lexer.dart';

/// Python implementation of an [ApolloParser].
///
/// Python blocks are indentation-significant, which petitparser cannot express
/// directly. So before handing the source to the grammar, [parse] runs the
/// [PythonIndentationPreprocessor] to convert indentation into the explicit
/// INDENT/DEDENT/NEWLINE markers the grammar consumes (see [PythonGrammarLexer]).
class ApolloParserPython extends ApolloSourceCodeParser {
  static final ApolloParserPython instance = ApolloParserPython();

  ApolloParserPython() : super(PythonGrammarDefinition());

  @override
  String get language => 'python';

  @override
  bool acceptsLanguage(String language) {
    language = language.toLowerCase().trim();
    if (this.language == language || language == 'py') {
      return true;
    }
    return false;
  }

  @override
  Future<ParseResult<String>> parse(CodeUnit<String> codeUnit) {
    check(codeUnit);

    var preprocessed = PythonIndentationPreprocessor.process(codeUnit.code);

    var transformed = SourceCodeUnit(
      codeUnit.language,
      preprocessed,
      id: codeUnit.id,
      namespace: codeUnit.namespace,
    );

    return super.parse(transformed);
  }
}

/// A single logical line: its indentation width and its (comment-stripped,
/// continuation-joined) text.
class _LogicalLine {
  final int indent;
  final String text;

  _LogicalLine(this.indent, this.text);
}

/// Converts Python's indentation-based block structure into explicit markers.
///
/// Emits [PythonGrammarLexer.indentChar] / [PythonGrammarLexer.dedentChar] at
/// block boundaries and terminates every logical line with
/// [PythonGrammarLexer.newlineChar], mirroring the INDENT/DEDENT/NEWLINE tokens
/// of CPython's tokenizer. Implicit (open `(`/`[`/`{`) and explicit (trailing
/// `\`) line continuations are joined; blank and comment-only lines are
/// dropped; `#` comments are stripped; string literals (including triple-quoted
/// and `f`/`r`-prefixed) are kept verbatim and never scanned for markers.
class PythonIndentationPreprocessor {
  static const String _indent = PythonGrammarLexer.indentChar;
  static const String _dedent = PythonGrammarLexer.dedentChar;
  static const String _newline = PythonGrammarLexer.newlineChar;

  static String process(String source) {
    var logicalLines = _scanLogicalLines(source);

    // Dedent by the common minimum indentation, so a uniformly-indented block
    // (e.g. an indented heredoc embedded in another language) parses the same
    // as a flush-left one.
    var baseIndent = logicalLines.isEmpty
        ? 0
        : logicalLines.map((l) => l.indent).reduce((a, b) => a < b ? a : b);

    var out = StringBuffer();
    var indentStack = <int>[0];

    for (var line in logicalLines) {
      var ind = line.indent - baseIndent;

      if (ind > indentStack.last) {
        indentStack.add(ind);
        out.write(_indent);
      } else if (ind < indentStack.last) {
        while (indentStack.length > 1 && ind < indentStack.last) {
          indentStack.removeLast();
          out.write(_dedent);
        }
      }

      out.write(line.text);
      out.write(_newline);
      out.write('\n');
    }

    while (indentStack.length > 1) {
      indentStack.removeLast();
      out.write(_dedent);
    }

    return out.toString();
  }

  static List<_LogicalLine> _scanLogicalLines(String source) {
    var src = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    var lines = <_LogicalLine>[];
    var i = 0;
    var n = src.length;

    while (i < n) {
      // Measure indentation at the start of the logical line (tabs → 8 stops).
      var indent = 0;
      while (i < n) {
        var c = src[i];
        if (c == ' ') {
          indent += 1;
          i++;
        } else if (c == '\t') {
          indent += 8 - (indent % 8);
          i++;
        } else {
          break;
        }
      }

      var content = StringBuffer();
      var bracketDepth = 0;

      while (i < n) {
        var c = src[i];

        if (c == '\n') {
          if (bracketDepth > 0) {
            // Implicit continuation: fold the newline (and the next line's
            // leading whitespace) into a single separating space.
            content.write(' ');
            i++;
            while (i < n && (src[i] == ' ' || src[i] == '\t')) {
              i++;
            }
            continue;
          }
          i++; // End of logical line.
          break;
        }

        if (c == '#') {
          // Comment: skip to end of the physical line (handled above).
          while (i < n && src[i] != '\n') {
            i++;
          }
          continue;
        }

        if (c == '\\' && i + 1 < n && src[i + 1] == '\n') {
          // Explicit line continuation.
          content.write(' ');
          i += 2;
          while (i < n && (src[i] == ' ' || src[i] == '\t')) {
            i++;
          }
          continue;
        }

        if (c == "'" || c == '"') {
          var start = i;
          i = _scanString(src, i);
          content.write(src.substring(start, i));
          continue;
        }

        if (c == '(' || c == '[' || c == '{') {
          bracketDepth++;
        } else if (c == ')' || c == ']' || c == '}') {
          if (bracketDepth > 0) bracketDepth--;
        }

        content.write(c);
        i++;
      }

      var text = content.toString().trimRight();
      if (text.isEmpty) continue; // Blank or comment-only line.

      lines.add(_LogicalLine(indent, text));
    }

    return lines;
  }

  /// Scans a string literal starting at the opening quote [i]; returns the
  /// index just past the closing quote. Handles triple-quoted strings and
  /// backslash escapes (prefixes like `r`/`f` are ordinary chars before [i]).
  static int _scanString(String src, int i) {
    var n = src.length;
    var quote = src[i];

    var isTriple = i + 2 < n && src[i + 1] == quote && src[i + 2] == quote;

    if (isTriple) {
      i += 3;
      while (i < n) {
        if (src[i] == '\\') {
          i += 2;
          continue;
        }
        if (src[i] == quote &&
            i + 2 < n &&
            src[i + 1] == quote &&
            src[i + 2] == quote) {
          return i + 3;
        }
        if (src[i] == quote && i + 2 == n && src[i + 1] == quote) {
          return n; // Closing triple quote at end of source.
        }
        i++;
      }
      return n;
    }

    i += 1;
    while (i < n) {
      var c = src[i];
      if (c == '\\') {
        i += 2;
        continue;
      }
      if (c == quote) return i + 1;
      if (c == '\n') return i; // Unterminated single-line string.
      i++;
    }
    return n;
  }
}
