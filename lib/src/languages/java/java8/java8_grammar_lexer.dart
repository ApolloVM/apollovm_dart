import 'package:petitparser/petitparser.dart';

abstract class Java8GrammarLexer extends GrammarDefinition {
  Parser token(Object input) {
    if (input is Parser) {
      return input.token().trim(ref(hiddenStuffWhitespace));
    } else if (input is String) {
      return token(input.toParser());
    } else if (input is Function) {
      return token(ref(input));
    }
    throw ArgumentError.value(input, 'invalid token parser');
  }

  Parser<String> identifier() =>
      ref(token, ref(identifierLexicalToken)).map((t) {
        return t is Token ? t.value : '$t';
      });

  // Copyright (c) 2011, the Dart project authors. Please see the AUTHORS file
  // for details. All rights reserved. Use of this source code is governed by a
  // BSD-style license that can be found in the LICENSE file.

  // -----------------------------------------------------------------
  // Keyword definitions.
  // -----------------------------------------------------------------
  Parser breakToken() => ref(token, 'break');

  Parser caseToken() => ref(token, 'case');

  Parser catchToken() => ref(token, 'catch');

  Parser constToken() => ref(token, 'const');

  Parser continueToken() => ref(token, 'continue');

  Parser defaultToken() => ref(token, 'default');

  Parser doToken() => ref(token, 'do');

  Parser elseToken() => ref(token, 'else');

  Parser falseToken() => ref(token, 'false');

  Parser finalToken() => ref(token, 'final');

  Parser finallyToken() => ref(token, 'finally');

  Parser forToken() => ref(token, 'for');

  Parser ifToken() => ref(token, 'if');

  Parser inToken() => ref(token, 'in');

  Parser newToken() => ref(token, 'new');

  Parser nullToken() => ref(token, 'null');

  Parser returnToken() => ref(token, 'return');

  Parser superToken() => ref(token, 'super');

  Parser switchToken() => ref(token, 'switch');

  Parser thisToken() => ref(token, 'this');

  Parser throwToken() => ref(token, 'throw');

  Parser trueToken() => ref(token, 'true');

  Parser tryToken() => ref(token, 'try');

  Parser varToken() => ref(token, 'var');

  Parser voidToken() => ref(token, 'void');

  Parser whileToken() => ref(token, 'while');

  // Pseudo-keywords that should also be valid identifiers.
  Parser abstractToken() => ref(token, 'abstract');

  Parser asToken() => ref(token, 'as');

  Parser assertToken() => ref(token, 'assert');

  Parser classToken() => ref(token, 'class');

  Parser deferredToken() => ref(token, 'deferred');

  Parser exportToken() => ref(token, 'export');

  Parser extendsToken() => ref(token, 'extends');

  Parser factoryToken() => ref(token, 'factory');

  Parser getToken() => ref(token, 'get');

  Parser hideToken() => ref(token, 'hide');

  Parser implementsToken() => ref(token, 'implements');

  Parser importToken() => ref(token, 'import');

  Parser isToken() => ref(token, 'is');

  Parser libraryToken() => ref(token, 'library');

  Parser nativeToken() => ref(token, 'native');

  Parser negateToken() => ref(token, 'negate');

  Parser ofToken() => ref(token, 'of');

  Parser operatorToken() => ref(token, 'operator');

  Parser partToken() => ref(token, 'part');

  Parser setToken() => ref(token, 'set');

  Parser showToken() => ref(token, 'show');

  Parser staticToken() => ref(token, 'static');

  Parser typedefToken() => ref(token, 'typedef');

  Parser<String> identifierLexicalToken() => (ref(identifierStartLexicalToken) &
          ref(identifierPartLexicalToken).star())
      .map((ts) => ts.expand((e) => e is Iterable ? e : [e]).join());

  Parser hexNumberLexicalToken() =>
      string('0x') & ref(hexDigitLexicalToken).plus() |
      string('0X') & ref(hexDigitLexicalToken).plus();

  Parser numberLexicalToken() => ((ref(digitLexicalToken).plus() &
              ref(numberOptFractionalPartLexicalToken) &
              ref(exponentLexicalToken).optional() &
              ref(numberOptIllegalEndLexicalToken)) |
          (char('.') &
              ref(digitLexicalToken).plus() &
              ref(exponentLexicalToken).optional() &
              ref(numberOptIllegalEndLexicalToken)))
      .flatten();

  Parser numberOptFractionalPartLexicalToken() =>
      char('.') & ref(digitLexicalToken).plus() | epsilon();

  Parser numberOptIllegalEndLexicalToken() => epsilon();

//        ref(IDENTIFIER_START).end()
//      | epsilon()
//      ;

  Parser hexDigitLexicalToken() => pattern('0-9a-fA-F');

  Parser identifierStartLexicalToken() =>
      ref(identifierStartNoDollarLexicalToken) | char('\$');

  Parser identifierStartNoDollarLexicalToken() =>
      ref(letterLexicalToken) | char('_');

  Parser identifierPartLexicalToken() =>
      ref(identifierStartLexicalToken) | ref(digitLexicalToken);

  Parser<String> letterLexicalToken() => letter();

  Parser<String> digitLexicalToken() => digit();

  Parser exponentLexicalToken() =>
      pattern('eE') & pattern('+-').optional() & ref(digitLexicalToken).plus();

  Parser stringLexicalToken() => ref(singleLineStringLexicalToken);

  Parser singleLineStringLexicalToken() =>
      char('"') &
          ref(stringContentDoubleQuotedLexicalToken).star() &
          char('"') |
      char("'") & ref(stringContentSingleQuotedLexicalToken).star() & char("'");

  Parser stringContentDoubleQuotedLexicalToken() =>
      pattern('^\\"\n\r') | char('\\') & pattern('\n\r');

  Parser stringContentSingleQuotedLexicalToken() =>
      pattern("^\\'\n\r") | char('\\') & pattern('\n\r');

  Parser newlineLexicalToken() => pattern('\n\r');

  Parser hashbangLexicalToken() =>
      string('#!') &
      pattern('^\n\r').star() &
      ref(newlineLexicalToken).optional();

  // -----------------------------------------------------------------
  // Whitespace and comments.
  // -----------------------------------------------------------------
  Parser hiddenWhitespace() => ref(hiddenStuffWhitespace).plus();

  Parser hiddenStuffWhitespace() =>
      ref(visibleWhitespace) | ref(singleLineComment) | ref(multiLineComment);

  Parser visibleWhitespace() => whitespace();

  Parser singleLineComment() =>
      string('//') &
      ref(newlineLexicalToken).neg().star() &
      ref(newlineLexicalToken).optional();

  Parser multiLineComment() =>
      string('/*') &
      (ref(multiLineComment) | string('*/').neg()).star() &
      string('*/');
}
