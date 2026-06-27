// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:petitparser/petitparser.dart';

import '../../ast/apollovm_ast_expression.dart';
import '../../ast/apollovm_ast_value.dart';
import '../grammar.dart';

/// Python 3 grammar lexer: keywords, numbers, string literals (single/double
/// quoted, triple-quoted, raw `r"..."` and `f"..."` f-strings with `{...}`
/// interpolation), whitespace and the synthetic indentation markers.
///
/// Python blocks are indentation-significant. The [PythonGrammarDefinition]
/// does not parse raw source directly: the [ApolloParserPython] first runs an
/// INDENT/DEDENT pre-tokenizer ([PythonIndentationPreprocessor]) that replaces
/// indentation with the control characters [indentChar]/[dedentChar] and ends
/// every logical line with [newlineChar]. The grammar then consumes those
/// markers like braces/semicolons, so real newlines stay hidden whitespace.
abstract class PythonGrammarLexer extends BaseGrammarLexer {
  /// INDENT marker (start of an indented block / suite).
  static const String indentChar = '\u0002';

  /// DEDENT marker (end of an indented block / suite).
  static const String dedentChar = '\u0003';

  /// Logical-line terminator (NEWLINE).
  static const String newlineChar = '\u0004';

  /// All Python reserved words. Used to keep [identifier] from matching
  /// keywords (essential because Python has no keyword/identifier separator).
  static const Set<String> reservedWords = {
    'and',
    'as',
    'assert',
    'async',
    'await',
    'break',
    'class',
    'continue',
    'def',
    'del',
    'elif',
    'else',
    'except',
    'False',
    'finally',
    'for',
    'from',
    'global',
    'if',
    'import',
    'in',
    'is',
    'lambda',
    'None',
    'nonlocal',
    'not',
    'or',
    'pass',
    'raise',
    'return',
    'True',
    'try',
    'while',
    'with',
    'yield',
  };

  // -----------------------------------------------------------------
  // Keyword definitions.
  //
  // Each keyword requires a word boundary (no trailing identifier char), so
  // `in` does not match the prefix of `index` and `is` does not match `island`.
  // -----------------------------------------------------------------
  Parser keyword(String name) =>
      (string(name) & ref0(identifierPartLexicalToken).not())
          .pick(0)
          .trim(ref0(hiddenStuffWhitespace));

  Parser andToken() => ref1(keyword, 'and');

  Parser asToken() => ref1(keyword, 'as');

  Parser asyncToken() => ref1(keyword, 'async');

  Parser awaitToken() => ref1(keyword, 'await');

  Parser breakToken() => ref1(keyword, 'break');

  Parser classToken() => ref1(keyword, 'class');

  Parser continueToken() => ref1(keyword, 'continue');

  Parser defToken() => ref1(keyword, 'def');

  Parser elifToken() => ref1(keyword, 'elif');

  Parser elseToken() => ref1(keyword, 'else');

  Parser exceptToken() => ref1(keyword, 'except');

  Parser falseToken() => ref1(keyword, 'False');

  Parser finallyToken() => ref1(keyword, 'finally');

  Parser forToken() => ref1(keyword, 'for');

  Parser fromToken() => ref1(keyword, 'from');

  Parser ifToken() => ref1(keyword, 'if');

  Parser importToken() => ref1(keyword, 'import');

  Parser inToken() => ref1(keyword, 'in');

  Parser isToken() => ref1(keyword, 'is');

  Parser lambdaToken() => ref1(keyword, 'lambda');

  Parser noneToken() => ref1(keyword, 'None');

  Parser notToken() => ref1(keyword, 'not');

  Parser orToken() => ref1(keyword, 'or');

  Parser passToken() => ref1(keyword, 'pass');

  Parser raiseToken() => ref1(keyword, 'raise');

  Parser returnToken() => ref1(keyword, 'return');

  Parser trueToken() => ref1(keyword, 'True');

  Parser tryToken() => ref1(keyword, 'try');

  Parser whileToken() => ref1(keyword, 'while');

  // -----------------------------------------------------------------
  // Indentation markers (synthetic; produced by the pre-tokenizer).
  // -----------------------------------------------------------------
  Parser indentToken() => char(indentChar).trim(ref0(hiddenStuffWhitespace));

  Parser dedentToken() => char(dedentChar).trim(ref0(hiddenStuffWhitespace));

  Parser newlineToken() => char(newlineChar).trim(ref0(hiddenStuffWhitespace));

  /// Identifier that rejects [reservedWords] (Python keywords can't be names).
  @override
  Parser<String> identifier() => super.identifier().where(
    (id) => !reservedWords.contains(id),
    message: 'reserved word',
  );

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
  //
  // Single/double quoted strings and triple-quoted strings have no
  // interpolation; `f"..."` f-strings support `{ expression }` interpolation
  // (with `{{`/`}}` escapes); `r"..."` raw strings keep backslashes verbatim.
  // -----------------------------------------------------------------

  /// A string literal that resolves to an [ASTValue] of [String].
  Parser<ASTValue<String>> stringLexicalToken() =>
      (ref0(fString) |
              ref0(rawString) |
              ref0(tripleString) |
              ref0(regularString))
          .trim()
          .cast<ASTValue<String>>();

  /// Hook into the full expression parser, implemented by the grammar, used
  /// inside f-string `{...}` blocks.
  Parser<ASTExpression> parseExpressionInString();

  // ---- f-strings: f"..." / f'...' with `{ expr }` interpolation ----
  Parser<ASTValue<String>> fString() =>
      ((char('f') | char('F')) & (ref0(fStringDouble) | ref0(fStringSingle)))
          .map((v) => v[1] as ASTValue<String>);

  Parser<ASTValue<String>> fStringDouble() =>
      (char('"') &
              (ref0(fBraceEscape) |
                      ref0(fExpression) |
                      ref0(escapeSequence) |
                      pattern('^"\\{}\n\r').plus().flatten())
                  .star() &
              char('"'))
          .map((v) => _mergeStringParts(v[1] as List));

  Parser<ASTValue<String>> fStringSingle() =>
      (char("'") &
              (ref0(fBraceEscape) |
                      ref0(fExpression) |
                      ref0(escapeSequence) |
                      pattern("^'\\{}\n\r").plus().flatten())
                  .star() &
              char("'"))
          .map((v) => _mergeStringParts(v[1] as List));

  Parser<String> fBraceEscape() =>
      (string('{{').map((_) => '{') | string('}}').map((_) => '}'))
          .cast<String>();

  Parser<ASTValueStringExpression> fExpression() =>
      (char('{') & ref0(parseExpressionInString) & char('}')).map((v) {
        return ASTValueStringExpression(v[1] as ASTExpression);
      });

  // ---- raw strings: r"..." / r'...' ----
  Parser<ASTValue<String>> rawString() =>
      ((char('r') | char('R')) &
              ((char('"') & pattern('^"\n\r').star().flatten() & char('"')) |
                  (char("'") & pattern("^'\n\r").star().flatten() & char("'"))))
          .map((v) {
            var inner = v[1] as List;
            return ASTValueString(inner[1] as String);
          });

  // ---- triple-quoted strings: """...""" / '''...''' ----
  Parser<ASTValue<String>> tripleString() =>
      ((string('"""') &
                  any().starLazy(string('"""')).flatten() &
                  string('"""')) |
              (string("'''") &
                  any().starLazy(string("'''")).flatten() &
                  string("'''")))
          .map((v) {
            var list = v as List;
            return ASTValueString(list[1] as String);
          });

  // ---- regular strings: "..." / '...' ----
  Parser<ASTValue<String>> regularString() =>
      (ref0(singleQuotedString) | ref0(doubleQuotedString))
          .cast<ASTValue<String>>();

  Parser<ASTValue<String>> singleQuotedString() =>
      (char("'") &
              (ref0(escapeSequence) | pattern("^'\\\n\r").plus().flatten())
                  .star() &
              char("'"))
          .map((v) => ASTValueString((v[1] as List).join()));

  Parser<ASTValue<String>> doubleQuotedString() =>
      (char('"') &
              (ref0(escapeSequence) | pattern('^"\\\n\r').plus().flatten())
                  .star() &
              char('"'))
          .map((v) => ASTValueString((v[1] as List).join()));

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
        // Includes \\ , \' , \" , etc.
        return c;
    }
  });

  /// Merges raw f-string parts (literal `String` chunks and interpolated
  /// [ASTValue]s) into a single [ASTValue], mirroring JS template literals.
  static ASTValue<String> _mergeStringParts(List rawParts) {
    var parts = <ASTValue<String>>[];
    for (var p in rawParts) {
      if (p is ASTValue<String>) {
        parts.add(p);
      } else {
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
  }

  /// A quoted string returning its raw content (used for import paths).
  Parser<String> stringPathLexicalToken() =>
      ((char("'") & pattern("^'\n\r").star().flatten() & char("'")) |
              (char('"') & pattern('^"\n\r').star().flatten() & char('"')))
          .trim()
          .map((v) => v[1] as String);

  // -----------------------------------------------------------------
  // Whitespace.
  //
  // Only spaces/tabs and real newlines are hidden whitespace; the synthetic
  // indentation markers ([indentChar]/[dedentChar]/[newlineChar]) are NOT
  // whitespace and are consumed explicitly by the grammar. Comments (`#`) are
  // stripped by the pre-tokenizer, so they never reach the grammar.
  // -----------------------------------------------------------------
  @override
  Parser hiddenWhitespace() => ref0(hiddenStuffWhitespace).plus();

  @override
  Parser hiddenStuffWhitespace() => hiddenStuffWhitespaceStatic();

  static Parser hiddenStuffWhitespaceStatic() => ref0(visibleWhitespace);

  static Parser visibleWhitespace() => pattern(' \t\n\r\f').plus().flatten();
}

extension TrimHiddenStuffWhitespaceParserExtensionPython<R> on Parser<R> {
  Parser<R> trimHidden() =>
      trim(PythonGrammarLexer.hiddenStuffWhitespaceStatic());
}
