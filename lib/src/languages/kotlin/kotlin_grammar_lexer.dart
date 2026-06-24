// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:petitparser/petitparser.dart';

import '../dart/dart_grammar_lexer.dart' show ParsedString;
import '../grammar.dart';

export '../dart/dart_grammar_lexer.dart' show ParsedString;

abstract class KotlinGrammarLexer extends BaseGrammarLexer {
  // -----------------------------------------------------------------
  // Keyword definitions.
  // -----------------------------------------------------------------
  Parser breakToken() => ref1(token, 'break');

  Parser classToken() => ref1(token, 'class');

  Parser constructorToken() => ref1(token, 'constructor');

  Parser continueToken() => ref1(token, 'continue');

  Parser elseToken() => ref1(token, 'else');

  Parser falseToken() => ref1(token, 'false');

  Parser forToken() => ref1(token, 'for');

  Parser funToken() => ref1(token, 'fun');

  Parser ifToken() => ref1(token, 'if');

  Parser importToken() => ref1(token, 'import');

  Parser inToken() => ref1(token, 'in');

  Parser nullToken() => ref1(token, 'null');

  Parser returnToken() => ref1(token, 'return');

  Parser thisToken() => ref1(token, 'this');

  Parser trueToken() => ref1(token, 'true');

  Parser valToken() => ref1(token, 'val');

  Parser varToken() => ref1(token, 'var');

  Parser whileToken() => ref1(token, 'while');

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
  // String tokens (Kotlin uses double-quoted strings with `$` and `${}`
  // template expressions, and `"""` raw multi-line strings).
  // -----------------------------------------------------------------
  Parser<ParsedString> stringLexicalToken() =>
      (ref0(multiLineStringLexicalToken) |
              ref0(singleLineStringLexicalToken))
          .trim()
          .cast<ParsedString>();

  Parser<ParsedString> multiLineStringLexicalToken() =>
      (string('"""') &
              (ref0(stringVariable) |
                      ref0(stringExpression) |
                      any().map((c) => ParsedString.literal(c)))
                  .starLazy(string('"""')) &
              string('"""'))
          .map((v) {
            var list = v[1] as List;
            var list2 = list
                .map((e) => e is ParsedString ? e : ParsedString.literal(e))
                .toList();
            return list2.length == 1 ? list2[0] : ParsedString.list(list2);
          });

  Parser<ParsedString> singleLineStringLexicalToken() =>
      (char('"') &
              (ref0(stringVariable) |
                      ref0(stringExpression) |
                      ref0(stringContentDoubleQuotedLexicalToken))
                  .star() &
              char('"'))
          .map((v) {
            var list = v[1] as List;
            var list2 = list
                .map((e) => e is ParsedString ? e : ParsedString.literal(e))
                .toList();
            return list2.length == 1 ? list2[0] : ParsedString.list(list2);
          });

  Parser<ParsedString> stringVariable() =>
      (char(r'$') & ((char('_') | letter()) & word().star()).flatten()).map((
        v,
      ) {
        return ParsedString.variable(v[1]);
      });

  Parser<ParsedString> parseExpressionInString();

  Parser<ParsedString> stringExpression() =>
      (string(r'${') & (ref0(() => parseExpressionInString())) & char('}')).map(
        (v) {
          return v[1];
        },
      );

  Parser<String> stringContentDoubleQuotedLexicalToken() =>
      (stringContentDoubleQuotedLexicalTokenUnescaped() |
              stringContentQuotedLexicalTokenEscaped())
          .cast<String>();

  Parser<String> stringContentDoubleQuotedLexicalTokenUnescaped() =>
      pattern('^\\"\n\r\$').plus().flatten();

  Parser<String> stringContentQuotedLexicalTokenEscaped() =>
      (char('\\') &
              (char('n').map((_) => '\n') |
                  char('r').map((_) => '\r') |
                  char('"').map((_) => '"') |
                  char("'").map((_) => "'") |
                  char(r'$').map((_) => r'$') |
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
  Parser<R> trimHidden() =>
      trim(KotlinGrammarLexer.hiddenStuffWhitespaceStatic());
}
