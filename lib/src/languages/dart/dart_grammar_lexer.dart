import 'package:apollovm/apollovm.dart';
import 'package:petitparser/petitparser.dart';

abstract class DartGrammarLexer extends GrammarDefinition {
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

  Parser<ParsedString> stringLexicalToken() =>
      (multiLineRawStringLexicalToken() |
              ref(singleLineRawStringLexicalToken) |
              ref(multiLineStringLexicalToken) |
              ref(singleLineStringLexicalToken))
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
              (ref(stringVariable) |
                      ref(stringExpression) |
                      ref(stringContentSingleQuotedLexicalToken))
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
              (ref(stringVariable) |
                      ref(stringExpression) |
                      ref(stringContentDoubleQuotedLexicalToken))
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
      (string(r'${') & (ref(() => parseExpressionInString())) & char('}'))
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
          ref(newlineLexicalToken).optional())
      .flatten();

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
      return ASTValueStringExpresion(expression!);
    }

    throw StateError("Can't resolve value!");
  }
}
