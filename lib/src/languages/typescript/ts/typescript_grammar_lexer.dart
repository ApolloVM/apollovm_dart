// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:petitparser/petitparser.dart';

import '../../../ast/apollovm_ast_expression.dart';
import '../../../ast/apollovm_ast_value.dart';
import '../../grammar.dart';

/// TypeScript grammar lexer: keywords, numbers, string literals
/// (single/double quoted + back-tick template literals with `${...}`
/// interpolation), whitespace and comments.
abstract class TypeScriptGrammarLexer extends BaseGrammarLexer {
  // -----------------------------------------------------------------
  // Keyword definitions.
  // -----------------------------------------------------------------
  Parser breakToken() => ref1(token, 'break');

  Parser caseToken() => ref1(token, 'case');

  Parser catchToken() => ref1(token, 'catch');

  Parser classToken() => ref1(token, 'class');

  Parser constToken() => ref1(token, 'const');

  Parser continueToken() => ref1(token, 'continue');

  Parser defaultToken() => ref1(token, 'default');

  Parser doToken() => ref1(token, 'do');

  Parser elseToken() => ref1(token, 'else');

  Parser extendsToken() => ref1(token, 'extends');

  Parser falseToken() => ref1(token, 'false');

  Parser forToken() => ref1(token, 'for');

  Parser fromToken() => ref1(token, 'from');

  Parser functionToken() => ref1(token, 'function');

  Parser ifToken() => ref1(token, 'if');

  Parser importToken() => ref1(token, 'import');

  Parser inToken() => ref1(token, 'in');

  Parser letToken() => ref1(token, 'let');

  Parser newToken() => ref1(token, 'new');

  Parser nullToken() => ref1(token, 'null');

  Parser ofToken() => ref1(token, 'of');

  Parser returnToken() => ref1(token, 'return');

  Parser staticToken() => ref1(token, 'static');

  Parser superToken() => ref1(token, 'super');

  Parser switchToken() => ref1(token, 'switch');

  Parser thisToken() => ref1(token, 'this');

  Parser trueToken() => ref1(token, 'true');

  Parser varToken() => ref1(token, 'var');

  Parser whileToken() => ref1(token, 'while');

  Parser tryToken() => ref1(token, 'try');

  Parser finallyToken() => ref1(token, 'finally');

  Parser throwToken() => ref1(token, 'throw');

  // TypeScript-specific keywords.
  Parser abstractToken() => ref1(token, 'abstract');

  Parser asToken() => ref1(token, 'as');

  Parser enumToken() => ref1(token, 'enum');

  Parser implementsToken() => ref1(token, 'implements');

  Parser interfaceToken() => ref1(token, 'interface');

  Parser privateToken() => ref1(token, 'private');

  Parser protectedToken() => ref1(token, 'protected');

  Parser publicToken() => ref1(token, 'public');

  Parser readonlyToken() => ref1(token, 'readonly');

  Parser typeToken() => ref1(token, 'type');

  // -----------------------------------------------------------------
  // Numbers.
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
  // Strings.
  // -----------------------------------------------------------------

  /// A string literal that resolves to an [ASTValue] of [String].
  ///
  /// Single/double quoted strings have no interpolation; back-tick template
  /// literals support `${ expression }` interpolation.
  Parser<ASTValue<String>> stringLexicalToken() =>
      (ref0(singleQuotedString) |
              ref0(doubleQuotedString) |
              ref0(templateString))
          .trim()
          .cast<ASTValue<String>>();

  /// Hook into the full expression parser, implemented by the grammar, used
  /// inside template literal `${...}` blocks.
  Parser<ASTExpression> parseExpressionInString();

  Parser<ASTValue<String>> singleQuotedString() =>
      (char("'") &
              (ref0(escapeSequence) | pattern("^'\\\n\r").plus().flatten())
                  .star() &
              char("'"))
          .map((v) {
            var content = (v[1] as List).join();
            return ASTValueString(content);
          });

  Parser<ASTValue<String>> doubleQuotedString() =>
      (char('"') &
              (ref0(escapeSequence) | pattern('^"\\\n\r').plus().flatten())
                  .star() &
              char('"'))
          .map((v) {
            var content = (v[1] as List).join();
            return ASTValueString(content);
          });

  Parser<ASTValue<String>> templateString() =>
      (char('`') &
              (ref0(templateExpression) |
                      ref0(escapeSequence) |
                      ref0(templateDollar) |
                      pattern('^`\\\$').plus().flatten())
                  .star() &
              char('`'))
          .map((v) {
            var rawParts = v[1] as List;

            // Merge adjacent literal strings; keep interpolated expressions.
            var parts = <ASTValue<String>>[];
            for (var p in rawParts) {
              if (p is ASTValue<String>) {
                parts.add(p);
              } else {
                // literal `String` chunk
                var s = p as String;
                if (parts.isNotEmpty && parts.last is ASTValueString) {
                  var prev = parts.removeLast() as ASTValueString;
                  parts.add(ASTValueString(prev.value + s));
                } else {
                  parts.add(ASTValueString(s));
                }
              }
            }

            if (parts.isEmpty) return ASTValueString('');
            if (parts.length == 1) return parts.first;
            return ASTValueStringConcatenation(parts);
          });

  Parser<ASTValueStringExpression> templateExpression() =>
      (string('\${') & ref0(parseExpressionInString) & char('}')).map((v) {
        var exp = v[1] as ASTExpression;
        return ASTValueStringExpression(exp);
      });

  /// A `$` inside a template literal that does NOT start an interpolation.
  Parser<String> templateDollar() =>
      (char('\$') & char('{').not()).map((_) => '\$');

  Parser<String> escapeSequence() => (char('\\') & any()).map((v) {
    var c = v[1] as String;
    switch (c) {
      case 'n':
        return '\n';
      case 'r':
        return '\r';
      case 't':
        return '\t';
      case 'b':
        return '\b';
      case 'f':
        return '\f';
      case '0':
        return '\x00';
      default:
        // Includes \\ , \' , \" , \` , \$ , \/ etc.
        return c;
    }
  });

  /// A quoted string returning its raw content (used for import paths).
  Parser<String> stringPathLexicalToken() =>
      ((char("'") & pattern("^'\n\r").star().flatten() & char("'")) |
              (char('"') & pattern('^"\n\r').star().flatten() & char('"')))
          .trim()
          .map((v) => v[1] as String);

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

  static Parser<String> newlineLexicalToken() => pattern('\n\r');

  static Parser singleLineComment() =>
      string('//') &
      ref0(newlineLexicalToken).neg().star() &
      ref0(newlineLexicalToken).optional();

  static Parser multiLineComment() =>
      string('/*') &
      (ref0(multiLineComment) | string('*/').neg()).star() &
      string('*/');
}

extension TrimHiddenStuffWhitespaceParserExtensionTS<R> on Parser<R> {
  Parser<R> trimHidden() =>
      trim(TypeScriptGrammarLexer.hiddenStuffWhitespaceStatic());
}
