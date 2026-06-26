// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:petitparser/petitparser.dart';
import '../grammar.dart';

abstract class CSharpGrammarLexer extends BaseGrammarLexer {
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

  // C# uses `readonly` (fields) and `const`; keep `final` as an accepted alias.
  Parser finalToken() => ref1(token, 'final');

  Parser readonlyToken() => ref1(token, 'readonly');

  Parser finallyToken() => ref1(token, 'finally');

  Parser forToken() => ref1(token, 'for');

  // C# uses `foreach (T x in coll)`.
  Parser foreachToken() => ref1(token, 'foreach');

  Parser ifToken() => ref1(token, 'if');

  Parser inToken() => ref1(token, 'in');

  // Whole-word match so identifiers like `newValue` aren't read as `new` + …
  Parser newToken() => (string('new') & ref0(identifierPartLexicalToken).not())
      .map((v) => v[0])
      .trim(ref0(hiddenStuffWhitespace));

  Parser nullToken() => ref1(token, 'null');

  Parser returnToken() => ref1(token, 'return');

  Parser baseToken() => ref1(token, 'base');

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

  Parser classToken() => ref1(token, 'class');

  Parser extendsToken() => ref1(token, 'extends');

  Parser getToken() => ref1(token, 'get');

  Parser implementsToken() => ref1(token, 'implements');

  // C# uses `using` to import namespaces.
  Parser usingToken() => ref1(token, 'using');

  Parser namespaceToken() => ref1(token, 'namespace');

  Parser isToken() => ref1(token, 'is');

  Parser operatorToken() => ref1(token, 'operator');

  Parser setToken() => ref1(token, 'set');

  Parser staticToken() => ref1(token, 'static');

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

  Parser<String> stringLexicalToken() => singleLineStringLexicalToken().trim();

  Parser<String> singleLineStringLexicalToken() =>
      (char('"') &
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
  Parser<R> trimHidden() =>
      trim(CSharpGrammarLexer.hiddenStuffWhitespaceStatic());
}
