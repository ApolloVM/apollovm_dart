// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:petitparser/petitparser.dart';

import '../dart/dart_grammar_lexer.dart' show ParsedString;
import '../grammar.dart';

export '../dart/dart_grammar_lexer.dart' show ParsedString;

abstract class GoGrammarLexer extends BaseGrammarLexer {
  // -----------------------------------------------------------------
  // Identifiers (reserved words are not valid identifiers in Go, so they are
  // excluded here — otherwise keywords like `case`/`default` at a statement
  // boundary would be consumed as variable names).
  // -----------------------------------------------------------------
  @override
  Parser<String> identifier() =>
      (ref0(reservedWord).not() & ref0(identifierLexicalToken))
          .map((v) => v[1] as String)
          .trim(ref0(hiddenStuffWhitespace));

  Parser reservedWord() =>
      ((string('break') |
                  string('case') |
                  string('continue') |
                  string('default') |
                  string('else') |
                  string('for') |
                  string('func') |
                  string('if') |
                  string('import') |
                  string('interface') |
                  string('map') |
                  string('package') |
                  string('range') |
                  string('return') |
                  string('struct') |
                  string('switch') |
                  string('type') |
                  string('var') |
                  string('nil') |
                  string('true') |
                  string('false')) &
              ref0(identifierPartLexicalToken).not())
          .map((v) => v[0]);

  // -----------------------------------------------------------------
  // Keyword definitions.
  // -----------------------------------------------------------------
  Parser breakToken() => keywordToken('break');

  Parser caseToken() => keywordToken('case');

  Parser continueToken() => keywordToken('continue');

  Parser defaultToken() => keywordToken('default');

  Parser elseToken() => keywordToken('else');

  Parser falseToken() => keywordToken('false');

  Parser forToken() => keywordToken('for');

  Parser funcToken() => keywordToken('func');

  Parser ifToken() => keywordToken('if');

  Parser importToken() => keywordToken('import');

  Parser interfaceToken() => keywordToken('interface');

  Parser mapToken() => keywordToken('map');

  Parser nilToken() => keywordToken('nil');

  Parser packageToken() => keywordToken('package');

  Parser rangeToken() => keywordToken('range');

  Parser returnToken() => keywordToken('return');

  Parser structToken() => keywordToken('struct');

  Parser switchToken() => keywordToken('switch');

  Parser trueToken() => keywordToken('true');

  Parser typeToken() => keywordToken('type');

  Parser varToken() => keywordToken('var');

  // -----------------------------------------------------------------
  // Number tokens.
  // -----------------------------------------------------------------
  Parser hexNumberLexicalToken() =>
      string('0x') & ref0(hexDigitLexicalToken).plus() |
      string('0X') & ref0(hexDigitLexicalToken).plus();

  Parser numberLexicalToken() =>
      ((ref0(digitLexicalToken).plus() &
                  ref0(numberOptFractionalPartLexicalToken) &
                  ref0(exponentLexicalToken).optional() &
                  ref0(numberOptIllegalEndLexicalToken)) |
              (char('.') &
                  ref0(digitLexicalToken).plus() &
                  ref0(exponentLexicalToken).optional() &
                  ref0(numberOptIllegalEndLexicalToken)))
          .flatten();

  Parser numberOptFractionalPartLexicalToken() =>
      char('.') & ref0(digitLexicalToken).plus() | epsilon();

  Parser numberOptIllegalEndLexicalToken() => epsilon();

  Parser hexDigitLexicalToken() => pattern('0-9a-fA-F');

  Parser exponentLexicalToken() =>
      pattern('eE') & pattern('+-').optional() & ref0(digitLexicalToken).plus();

  // -----------------------------------------------------------------
  // String tokens (Go uses double-quoted interpreted strings and backtick raw
  // strings; Go has no string interpolation, so a string is always a single
  // literal, wrapped as a [ParsedString] for shared-grammar compatibility).
  // -----------------------------------------------------------------
  Parser<ParsedString> stringLexicalToken() =>
      (ref0(rawStringLexicalToken) | ref0(interpretedStringLexicalToken))
          .trim()
          .cast<ParsedString>();

  Parser<ParsedString> interpretedStringLexicalToken() =>
      (char('"') &
              (ref0(stringContentDoubleQuotedLexicalToken)).star() &
              char('"'))
          .map((v) {
            var content = (v[1] as List).join();
            return ParsedString.literal(content);
          });

  /// Go raw string literal using back-quotes: `` `...` `` (no escapes).
  Parser<ParsedString> rawStringLexicalToken() =>
      (char('`') & pattern('^`').star().flatten() & char('`')).map((v) {
        return ParsedString.literal(v[1] as String);
      });

  Parser<String> stringContentDoubleQuotedLexicalToken() =>
      (stringContentDoubleQuotedLexicalTokenUnescaped() |
              stringContentQuotedLexicalTokenEscaped())
          .cast<String>();

  Parser<String> stringContentDoubleQuotedLexicalTokenUnescaped() =>
      pattern('^\\"\n\r').plus().flatten();

  Parser<String> stringContentQuotedLexicalTokenEscaped() =>
      (char('\\') &
              (char('n').map((_) => '\n') |
                  char('r').map((_) => '\r') |
                  char('"').map((_) => '"') |
                  char("'").map((_) => "'") |
                  char('t').map((_) => '\t') |
                  char('b').map((_) => '\b') |
                  char('\\').map((_) => '\\')))
          .map((v) {
            return v[1] as String;
          });

  static Parser<String> newlineLexicalToken() => pattern('\n\r');

  // -----------------------------------------------------------------
  // Whitespace and comments.
  // -----------------------------------------------------------------
  @override
  Parser hiddenWhitespace() => ref0(hiddenStuffWhitespace).plus();

  @override
  Parser hiddenStuffWhitespace() => hiddenStuffWhitespaceStatic();

  static Parser hiddenStuffWhitespaceStatic() =>
      ref0(visibleWhitespace) |
      ref0(singleLineComment) |
      ref0(multiLineComment);

  static Parser visibleWhitespace() => whitespace();

  static Parser singleLineComment() =>
      string('//') &
      ref0(newlineLexicalToken).neg().star() &
      ref0(newlineLexicalToken).optional();

  static Parser multiLineComment() =>
      string('/*') &
      (ref0(multiLineComment) | string('*/').neg()).star() &
      string('*/');
}

extension TrimHiddenStuffWhitespaceParserExtension<R> on Parser<R> {
  Parser<R> trimHidden() => trim(GoGrammarLexer.hiddenStuffWhitespaceStatic());
}
