// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:petitparser/petitparser.dart';

import '../dart/dart_grammar_lexer.dart' show ParsedString;
import '../grammar.dart';

export '../dart/dart_grammar_lexer.dart' show ParsedString;

abstract class LuaGrammarLexer extends BaseGrammarLexer {
  /// All Lua reserved words. Used to keep [identifier] from matching keywords
  /// (essential because Lua blocks are delimited by keywords like `end`).
  static const Set<String> reservedWords = {
    'and',
    'break',
    'do',
    'else',
    'elseif',
    'end',
    'false',
    'for',
    'function',
    'goto',
    'if',
    'in',
    'local',
    'nil',
    'not',
    'or',
    'repeat',
    'return',
    'then',
    'true',
    'until',
    'while',
  };

  // -----------------------------------------------------------------
  // Keyword definitions.
  //
  // Each keyword requires a word boundary (no trailing identifier char), so
  // `end` does not match the prefix of `endValue` and `or` does not match
  // `order`.
  // -----------------------------------------------------------------
  Parser keyword(String name) =>
      (string(name) & ref0(identifierPartLexicalToken).not())
          .pick(0)
          .trim(ref0(hiddenStuffWhitespace));

  Parser andToken() => ref1(keyword, 'and');

  Parser breakToken() => ref1(keyword, 'break');

  Parser doToken() => ref1(keyword, 'do');

  Parser elseToken() => ref1(keyword, 'else');

  Parser elseifToken() => ref1(keyword, 'elseif');

  Parser endToken() => ref1(keyword, 'end');

  Parser falseToken() => ref1(keyword, 'false');

  Parser forToken() => ref1(keyword, 'for');

  Parser functionToken() => ref1(keyword, 'function');

  Parser ifToken() => ref1(keyword, 'if');

  Parser inToken() => ref1(keyword, 'in');

  Parser localToken() => ref1(keyword, 'local');

  Parser nilToken() => ref1(keyword, 'nil');

  Parser notToken() => ref1(keyword, 'not');

  Parser orToken() => ref1(keyword, 'or');

  Parser repeatToken() => ref1(keyword, 'repeat');

  Parser returnToken() => ref1(keyword, 'return');

  Parser thenToken() => ref1(keyword, 'then');

  Parser trueToken() => ref1(keyword, 'true');

  Parser untilToken() => ref1(keyword, 'until');

  Parser whileToken() => ref1(keyword, 'while');

  /// Identifier that rejects [reservedWords].
  @override
  Parser<String> identifier() => super.identifier().where(
    (id) => !reservedWords.contains(id),
    message: 'reserved word',
  );

  // -----------------------------------------------------------------
  // Number tokens.
  // -----------------------------------------------------------------
  Parser hexNumberLexicalToken() =>
      string('0x') & ref0(hexDigitLexicalToken).plus() |
      string('0X') & ref0(hexDigitLexicalToken).plus();

  Parser numberLexicalToken() =>
      ((ref0(digitLexicalToken).plus() &
                  ref0(numberOptFractionalPartLexicalToken) &
                  ref0(exponentLexicalToken).optional()) |
              (char('.') &
                  ref0(digitLexicalToken).plus() &
                  ref0(exponentLexicalToken).optional()))
          .flatten();

  Parser numberOptFractionalPartLexicalToken() =>
      char('.') & ref0(digitLexicalToken).plus() | epsilon();

  Parser hexDigitLexicalToken() => pattern('0-9a-fA-F');

  Parser exponentLexicalToken() =>
      pattern('eE') & pattern('+-').optional() & ref0(digitLexicalToken).plus();

  // -----------------------------------------------------------------
  // String tokens.
  //
  // Lua strings are `"..."`, `'...'`, and long `[[ ... ]]` strings. Unlike
  // Kotlin, Lua has no string interpolation, so every string is a literal.
  // -----------------------------------------------------------------
  Parser<ParsedString> stringLexicalToken() =>
      (ref0(longStringLexicalToken) |
              ref0(doubleQuotedStringLexicalToken) |
              ref0(singleQuotedStringLexicalToken))
          .trim()
          .cast<ParsedString>();

  Parser<ParsedString> doubleQuotedStringLexicalToken() =>
      (char('"') & ref0(stringContentDoubleQuoted).star() & char('"')).map((v) {
        var content = (v[1] as List).join();
        return ParsedString.literal(content);
      });

  Parser<ParsedString> singleQuotedStringLexicalToken() =>
      (char("'") & ref0(stringContentSingleQuoted).star() & char("'")).map((v) {
        var content = (v[1] as List).join();
        return ParsedString.literal(content);
      });

  Parser<ParsedString> longStringLexicalToken() =>
      (string('[[') & any().starLazy(string(']]')).flatten() & string(']]'))
          .map((v) {
            var content = v[1] as String;
            // Lua: a newline immediately after the opening `[[` is dropped.
            if (content.startsWith('\n')) {
              content = content.substring(1);
            } else if (content.startsWith('\r\n')) {
              content = content.substring(2);
            }
            return ParsedString.literal(content);
          });

  Parser<String> stringContentDoubleQuoted() =>
      (stringContentEscaped() | pattern('^\\"\n\r').plus().flatten())
          .cast<String>();

  Parser<String> stringContentSingleQuoted() =>
      (stringContentEscaped() | pattern("^\\'\n\r").plus().flatten())
          .cast<String>();

  Parser<String> stringContentEscaped() =>
      (char('\\') &
              (char('n').map((_) => '\n') |
                  char('r').map((_) => '\r') |
                  char('t').map((_) => '\t') |
                  char('a').map((_) => '\x07') |
                  char('b').map((_) => '\b') |
                  char('f').map((_) => '\f') |
                  char('v').map((_) => '\x0B') |
                  char('"').map((_) => '"') |
                  char("'").map((_) => "'") |
                  char('\\').map((_) => '\\')))
          .map((v) {
            return v[1] as String;
          });

  static Parser<String> newlineLexicalToken() => pattern('\n\r');

  // -----------------------------------------------------------------
  // Whitespace and comments.
  //
  // Lua uses `--` line comments and `--[[ ... ]]` block comments.
  // -----------------------------------------------------------------
  @override
  Parser hiddenWhitespace() => ref0(hiddenStuffWhitespace).plus();

  @override
  Parser hiddenStuffWhitespace() => hiddenStuffWhitespaceStatic();

  static Parser hiddenStuffWhitespaceStatic() =>
      ref0(visibleWhitespace) |
      ref0(multiLineComment) |
      ref0(singleLineComment);

  static Parser visibleWhitespace() => whitespace();

  // `--[[ ... ]]` must be matched before the `--` line comment.
  static Parser multiLineComment() =>
      string('--[[') & any().starLazy(string(']]')) & string(']]');

  static Parser singleLineComment() =>
      string('--') &
      ref0(newlineLexicalToken).neg().star() &
      ref0(newlineLexicalToken).optional();
}

extension TrimHiddenStuffWhitespaceParserExtension<R> on Parser<R> {
  Parser<R> trimHidden() => trim(LuaGrammarLexer.hiddenStuffWhitespaceStatic());
}
