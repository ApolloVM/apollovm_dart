import 'package:apollovm/apollovm.dart';
import 'package:petitparser/petitparser.dart';

abstract class DartGrammarLexer extends GrammarDefinition {
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

  Parser<ParsedString> stringLexicalToken() =>
      (multiLineRawStringLexicalToken() |
              ref0(singleLineRawStringLexicalToken) |
              ref0(multiLineStringLexicalToken) |
              ref0(singleLineStringLexicalToken))
          .trim()
          .cast<ParsedString>();

  Parser<ParsedString> multiLineRawStringLexicalToken() =>
      (multiLineSingleQuotedRawStringLexicalToken() |
              multiLineDoubleQuotedRawStringLexicalToken())
          .cast<ParsedString>();

  Parser<ParsedString> multiLineSingleQuotedRawStringLexicalToken() =>
      (string("r'''") & any().starLazy(string("'''")) & string("'''")).map((v) {
        var l = v[1] as List;
        var s = l.length == 1 ? l[0] : l.join('');
        return ParsedString.literal(s);
      });

  Parser<ParsedString> multiLineDoubleQuotedRawStringLexicalToken() =>
      (string('r"""') & any().starLazy(string('"""')) & string('"""')).map((v) {
        var l = v[1] as List;
        var s = l.length == 1 ? l[0] : l.join('');
        return ParsedString.literal(s);
      });

  Parser<ParsedString> multiLineStringLexicalToken() =>
      (multiLineSingleQuotedStringLexicalToken() |
              multiLineDoubleQuotedStringLexicalToken())
          .cast<ParsedString>();

  Parser<ParsedString> multiLineSingleQuotedStringLexicalToken() =>
      (string("'''") &
              (string(r"\'").map((_) => "'") |
                      stringContentQuotedLexicalTokenEscaped() |
                      any())
                  .starLazy(string("'''")) &
              string("'''"))
          .map((v) {
        var list = v[1] as List;
        var list2 = list
            .map((e) => e is ParsedString ? e : ParsedString.literal(e))
            .toList();
        return list2.length == 1 ? list2[0] : ParsedString.list(list2);
      });

  Parser<ParsedString> multiLineDoubleQuotedStringLexicalToken() =>
      (string('"""') &
              (string(r'\"').map((_) => '"') |
                      stringContentQuotedLexicalTokenEscaped() |
                      any())
                  .starLazy(string('"""')) &
              string('"""'))
          .map((v) {
        var list = v[1] as List;
        var list2 = list
            .map((e) => e is ParsedString ? e : ParsedString.literal(e))
            .toList();
        return list2.length == 1 ? list2[0] : ParsedString.list(list2);
      });

  Parser<ParsedString> singleLineRawStringLexicalToken() =>
      (singleLineRawStringSingleQuotedLexicalToken() |
              singleLineRawStringDoubleQuotedLexicalToken())
          .cast<ParsedString>();

  Parser<ParsedString> singleLineRawStringSingleQuotedLexicalToken() =>
      (string("r'") & pattern("^'").star().flatten() & char("'")).map((v) {
        var s = v[1];
        return ParsedString.literal(s);
      });

  Parser<ParsedString> singleLineRawStringDoubleQuotedLexicalToken() =>
      (string('r"') & pattern('^"').star().flatten() & char('"')).map((v) {
        var s = v[1];
        return ParsedString.literal(s);
      });

  Parser<ParsedString> singleLineStringLexicalToken() =>
      (singleLineStringSingleQuotedLexicalToken() |
              singleLineStringDoubleQuotedLexicalToken())
          .cast<ParsedString>();

  Parser<ParsedString> singleLineStringSingleQuotedLexicalToken() =>
      (char("'") &
              (ref0(stringVariable) |
                      ref0(stringExpression) |
                      ref0(stringContentSingleQuotedLexicalToken))
                  .star() &
              char("'"))
          .map((v) {
        var list = v[1] as List;
        var list2 = list
            .map((e) => e is ParsedString ? e : ParsedString.literal(e))
            .toList();
        return list2.length == 1 ? list2[0] : ParsedString.list(list2);
      });

  Parser<ParsedString> singleLineStringDoubleQuotedLexicalToken() =>
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
      (char(r'$') & ((char('_') | letter()) & word().star()).flatten())
          .map((v) {
        return ParsedString.variable(v[1]);
      });

  Parser<ParsedString> parseExpressionInString();

  Parser<ParsedString> stringExpression() =>
      (string(r'${') & (ref0(() => parseExpressionInString())) & char('}'))
          .map((v) {
        return v[1];
      });

  Parser<String> stringContentSingleQuotedLexicalToken() =>
      (stringContentSingleQuotedLexicalTokenUnescaped() |
              stringContentQuotedLexicalTokenEscaped())
          .cast<String>();

  Parser<String> stringContentDoubleQuotedLexicalToken() =>
      (stringContentDoubleQuotedLexicalTokenUnescaped() |
              stringContentQuotedLexicalTokenEscaped())
          .cast<String>();

  Parser<String> stringContentSingleQuotedLexicalTokenUnescaped() =>
      pattern("^\\'\n\r\$").plus().flatten();

  Parser<String> stringContentDoubleQuotedLexicalTokenUnescaped() =>
      pattern('^\\"\n\r\$').plus().flatten();

  Parser<String> stringContentQuotedLexicalTokenEscaped() => (char('\\') &
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

  Parser<String> newlineLexicalToken() => pattern('\n\r');

  Parser<String> hashbangLexicalToken() => (string('#!') &
          pattern('^\n\r').star() &
          ref0(newlineLexicalToken).optional())
      .flatten();

  // -----------------------------------------------------------------
  // Whitespace and comments.
  // -----------------------------------------------------------------
  Parser hiddenWhitespace() => ref0(hiddenStuffWhitespace).plus();

  Parser hiddenStuffWhitespace() =>
      ref0(visibleWhitespace) |
      ref0(singleLineComment) |
      ref0(multiLineComment);

  Parser visibleWhitespace() => whitespace();

  Parser singleLineComment() =>
      string('//') &
      ref0(newlineLexicalToken).neg().star() &
      ref0(newlineLexicalToken).optional();

  Parser multiLineComment() =>
      string('/*') &
      (ref0(multiLineComment) | string('*/').neg()).star() &
      string('*/');
}

class ParsedString {
  String? literalString;

  String? variableName;

  ASTExpression? expression;

  List<ParsedString>? list;

  ParsedString.literal(this.literalString);

  ParsedString.variable(this.variableName);

  ParsedString.expression(this.expression);

  ParsedString.list(this.list);

  bool get isLiteral {
    if (literalString != null) return true;

    if (variableName != null) return false;

    if (list != null) {
      return list!.every((e) => e.isLiteral);
    }

    return false;
  }

  String asLiteral() {
    if (literalString != null) return literalString!;
    if (list != null) {
      return list!.map((e) => e.asLiteral()).join('');
    }
    throw StateError('Not literal!');
  }

  ASTValue<String> asValue() {
    if (literalString != null) {
      return ASTValueString(literalString!);
    } else if (variableName != null) {
      var variable = ASTScopeVariable(variableName!);
      return ASTValueStringVariable(variable);
    } else if (list != null) {
      var list = this.list!;
      if (list.length == 1) {
        return list[0].asValue();
      } else if (list.every((e) => e.isLiteral)) {
        var s = list.map((e) => e.asLiteral()).join();
        return ASTValueString(s);
      } else {
        var values = list.map((e) => e.asValue()).toList();
        return ASTValueStringConcatenation(values);
      }
    } else if (expression != null) {
      return ASTValueStringExpression(expression!);
    }

    throw StateError("Can't resolve value!");
  }
}
