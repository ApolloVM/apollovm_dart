import 'package:petitparser/petitparser.dart';

abstract class Java11GrammarLexer extends GrammarDefinition {
  Parser token(Object input) {
    if (input is Parser) {
      return input.token().trim(ref0(hiddenStuffWhitespace));
    } else if (input is String) {
      return token(input.toParser());
    } else if (input is Parser Function()) {
      return token(ref0(input));
    }
    throw ArgumentError.value(input, 'invalid token parser');
  }

  Parser<String> identifier() =>
      ref1(token, ref0(identifierLexicalToken)).map((t) {
        return t is Token ? t.value : '$t';
      });

  // Copyright (c) 2011, the Dart project authors. Please see the AUTHORS file
  // for details. All rights reserved. Use of this source code is governed by a
  // BSD-style license that can be found in the LICENSE file.

  // -----------------------------------------------------------------
  // Keyword definitions.
  // -----------------------------------------------------------------
  Parser breakToken() => ref1(token, 'break');

  Parser caseToken() => ref1(token, 'case');

  Parser catchToken() => ref1(token, 'catch');

  Parser constToken() => ref1(token, 'const');

  Parser continueToken() => ref1(token, 'continue');

  Parser defaultToken() => ref1(token, 'default');

  Parser doToken() => ref1(token, 'do');

  Parser elseToken() => ref1(token, 'else');

  Parser falseToken() => ref1(token, 'false');

  Parser finalToken() => ref1(token, 'final');

  Parser finallyToken() => ref1(token, 'finally');

  Parser forToken() => ref1(token, 'for');

  Parser ifToken() => ref1(token, 'if');

  Parser inToken() => ref1(token, 'in');

  Parser newToken() => ref1(token, 'new');

  Parser nullToken() => ref1(token, 'null');

  Parser returnToken() => ref1(token, 'return');

  Parser superToken() => ref1(token, 'super');

  Parser switchToken() => ref1(token, 'switch');

  Parser thisToken() => ref1(token, 'this');

  Parser throwToken() => ref1(token, 'throw');

  Parser trueToken() => ref1(token, 'true');

  Parser tryToken() => ref1(token, 'try');

  Parser varToken() => ref1(token, 'var');

  Parser voidToken() => ref1(token, 'void');

  Parser whileToken() => ref1(token, 'while');

  // Pseudo-keywords that should also be valid identifiers.
  Parser abstractToken() => ref1(token, 'abstract');

  Parser asToken() => ref1(token, 'as');

  Parser assertToken() => ref1(token, 'assert');

  Parser classToken() => ref1(token, 'class');

  Parser deferredToken() => ref1(token, 'deferred');

  Parser exportToken() => ref1(token, 'export');

  Parser extendsToken() => ref1(token, 'extends');

  Parser factoryToken() => ref1(token, 'factory');

  Parser getToken() => ref1(token, 'get');

  Parser hideToken() => ref1(token, 'hide');

  Parser implementsToken() => ref1(token, 'implements');

  Parser importToken() => ref1(token, 'import');

  Parser isToken() => ref1(token, 'is');

  Parser libraryToken() => ref1(token, 'library');

  Parser nativeToken() => ref1(token, 'native');

  Parser negateToken() => ref1(token, 'negate');

  Parser ofToken() => ref1(token, 'of');

  Parser operatorToken() => ref1(token, 'operator');

  Parser partToken() => ref1(token, 'part');

  Parser setToken() => ref1(token, 'set');

  Parser showToken() => ref1(token, 'show');

  Parser staticToken() => ref1(token, 'static');

  Parser typedefToken() => ref1(token, 'typedef');

  Parser<String> identifierLexicalToken() =>
      (ref0(identifierStartLexicalToken) &
              ref0(identifierPartLexicalToken).star())
          .map((ts) => ts.expand((e) => e is Iterable ? e : [e]).join());

  Parser hexNumberLexicalToken() =>
      string('0x') & ref0(hexDigitLexicalToken).plus() |
      string('0X') & ref0(hexDigitLexicalToken).plus();

  Parser numberLexicalToken() => ((ref0(digitLexicalToken).plus() &
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

  Parser identifierStartLexicalToken() =>
      ref0(identifierStartNoDollarLexicalToken) | char('\$');

  Parser identifierStartNoDollarLexicalToken() =>
      ref0(letterLexicalToken) | char('_');

  Parser identifierPartLexicalToken() =>
      ref0(identifierStartLexicalToken) | ref0(digitLexicalToken);

  Parser<String> letterLexicalToken() => letter();

  Parser<String> digitLexicalToken() => digit();

  Parser exponentLexicalToken() =>
      pattern('eE') & pattern('+-').optional() & ref0(digitLexicalToken).plus();

  Parser<String> stringLexicalToken() => singleLineStringLexicalToken().trim();

  Parser<String> singleLineStringLexicalToken() => (char('"') &
              ref0(stringContentDoubleQuotedLexicalToken).star() &
              char('"'))
          .map((v) {
        var list = v[1] as List;
        return list.length == 1 ? list[0] : list.join('');
      });

  Parser<String> stringContentDoubleQuotedLexicalToken() =>
      (stringContentDoubleQuotedLexicalTokenUnescaped() |
              stringContentQuotedLexicalTokenEscaped())
          .cast<String>();

  Parser<String> stringContentDoubleQuotedLexicalTokenUnescaped() =>
      pattern('^\\"\n\r').plus().flatten();

  Parser<String> stringContentQuotedLexicalTokenEscaped() => (char('\\') &
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
  Parser hiddenWhitespace() => ref0(hiddenStuffWhitespace).plus();

  static Parser hiddenStuffWhitespace() =>
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
  Parser<R> trimHidden() => trim(Java11GrammarLexer.hiddenStuffWhitespace());
}
