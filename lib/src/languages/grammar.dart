import 'package:collection/collection.dart';
import 'package:petitparser/petitparser.dart';

import '../ast/apollovm_ast_expression.dart';

/// Base class for defining a grammar lexer.
abstract class BaseGrammarLexer extends GrammarDefinition {
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

  Parser hiddenStuffWhitespace();

  Parser hiddenWhitespace();

  Parser<String> identifier() =>
      ref1(token, ref0(identifierLexicalToken)).map((t) {
        return t is Token ? t.value : '$t';
      });

  /// A whole-word keyword token for [word]: matches only when [word] is not
  /// immediately followed by an identifier part, so contextual keywords like
  /// `await` are not read inside identifiers such as `awaiter`.
  Parser keywordToken(String word) =>
      (string(word) & ref0(identifierPartLexicalToken).not())
          .map((v) => v[0])
          .trim(ref0(hiddenStuffWhitespace));

  Parser<String> identifierLexicalToken() =>
      (ref0(identifierStartLexicalToken) &
              ref0(identifierPartLexicalToken).star())
          .map((ts) => ts.expand((e) => e is Iterable ? e : [e]).join());

  Parser identifierStartLexicalToken() =>
      ref0(identifierStartNoDollarLexicalToken) | char('\$');

  Parser identifierStartNoDollarLexicalToken() =>
      ref0(letterLexicalToken) | char('_');

  Parser identifierPartLexicalToken() =>
      ref0(identifierStartLexicalToken) | ref0(digitLexicalToken);

  Parser<String> digitLexicalToken() => digit();

  Parser<String> letterLexicalToken() => letter();

  //-- Shared expression/argument parsers --//

  /// A full expression. Declared here so the shared argument/default-value
  /// parsers below can reference it via `ref0(expression)`; each concrete
  /// grammar provides the language-specific implementation.
  Parser<ASTExpression> expression();

  /// The call-site separator between a named/keyword argument's name and its
  /// value. Defaults to `:` (Dart/C#); languages like Kotlin and Python
  /// override this to `=` (guarded against `==`).
  Parser namedArgumentSeparatorParser() => char(':');

  /// A parameter default value: `= <expression>` (used by optional/named
  /// parameters, e.g. `int a = 5`). The `char('=') & char('=').not()` guard
  /// prevents matching the equality operator `==`.
  Parser<ASTExpression> parameterDefaultValue() =>
      ((char('=') & char('=').not()).trim(ref0(hiddenStuffWhitespace)) &
              ref0(expression))
          .map((v) => v[1] as ASTExpression);

  /// Parses a call-site argument list mixing positional and named arguments,
  /// e.g. `1, 2`, `a: 1, b: 2`, `1, b: 2` (separator per
  /// [namedArgumentSeparatorParser]).
  Parser<({List<ASTExpression> positional, Map<String, ASTExpression>? named})>
  callArguments() =>
      (ref0(callArgument) &
              (char(',').trim(ref0(hiddenStuffWhitespace)) & ref0(callArgument))
                  .star() &
              char(',').trim(ref0(hiddenStuffWhitespace)).optional())
          .map((v) {
            var args = <({String? name, ASTExpression expr})>[
              v[0] as ({String? name, ASTExpression expr}),
              ...(v[1] as List).map(
                (e) => (e as List)[1] as ({String? name, ASTExpression expr}),
              ),
            ];

            var positional = <ASTExpression>[];
            Map<String, ASTExpression>? named;

            for (var a in args) {
              final name = a.name;
              if (name != null) {
                (named ??= {})[name] = a.expr;
              } else {
                positional.add(a.expr);
              }
            }

            return (positional: positional, named: named);
          });

  /// A single call argument: either `name<sep> expression` (named) or
  /// `expression` (positional). The name prefix is only matched when an
  /// identifier is immediately followed by [namedArgumentSeparatorParser], so
  /// positional expressions (ternaries `a ? b : c`, equality `a == b`) are not
  /// misparsed.
  Parser<({String? name, ASTExpression expr})> callArgument() =>
      ((identifier().trim() &
                      namedArgumentSeparatorParser().trim(
                        ref0(hiddenStuffWhitespace),
                      ))
                  .optional() &
              ref0(expression))
          .map((v) {
            var nameOpt = v[0] as List?;
            var name = nameOpt != null ? nameOpt[0] as String : null;
            var expr = v[1] as ASTExpression;
            return (name: name, expr: expr);
          });

  //-- Reduce expressions operations --//

  ASTExpression computeFinalExpression(List all) {
    // Split expression into logical blocks
    // separated by `&&` and `||` operators:
    var blocks = all
        .splitBefore(
          (e) =>
              e == ASTExpressionOperator.and || e == ASTExpressionOperator.or,
        )
        .toList();

    // Resolve blocks with logical operators
    ASTExpression? finalExpressionOp;

    for (var i = 0; i < blocks.length; ++i) {
      final block = blocks[i];

      ASTExpressionOperator? blockOp;
      final first = block.first;

      if (first == ASTExpressionOperator.and ||
          first == ASTExpressionOperator.or) {
        block.removeAt(0);
        blockOp = first;
        assert(finalExpressionOp != null);
      }

      var expressionOp = reduceExpressionBlock(block);

      if (finalExpressionOp == null) {
        finalExpressionOp = expressionOp;
      } else {
        if (blockOp == null) {
          throw StateError('Missing logical operator between blocks');
        }

        finalExpressionOp = astExpressionOperation(
          finalExpressionOp,
          blockOp,
          expressionOp,
        );
      }
    }

    return finalExpressionOp!;
  }

  ASTExpression reduceExpressionBlock(List block) {
    // Precedence levels
    _reduceOps(block, {
      ASTExpressionOperator.multiply,
      ASTExpressionOperator.divide,
      ASTExpressionOperator.divideAsInt,
      ASTExpressionOperator.divideAsDouble,
      ASTExpressionOperator.remainder,
    });

    _reduceOps(block, {
      ASTExpressionOperator.add,
      ASTExpressionOperator.subtract,
    });

    // Bitwise precedence (tighter than comparisons): shift, then AND, XOR, OR.
    _reduceOps(block, {
      ASTExpressionOperator.shiftLeft,
      ASTExpressionOperator.shiftRight,
    });

    _reduceOps(block, {ASTExpressionOperator.bitwiseAnd});
    _reduceOps(block, {ASTExpressionOperator.bitwiseXor});
    _reduceOps(block, {ASTExpressionOperator.bitwiseOr});

    // Relational, then equality (looser than the bitwise operators).
    _reduceOps(block, {
      ASTExpressionOperator.greater,
      ASTExpressionOperator.greaterOrEq,
      ASTExpressionOperator.lower,
      ASTExpressionOperator.lowerOrEq,
    });
    _reduceOps(block, {
      ASTExpressionOperator.equals,
      ASTExpressionOperator.notEquals,
    });

    // Logical AND, then OR.
    _reduceOps(block, {ASTExpressionOperator.and});
    _reduceOps(block, {ASTExpressionOperator.or});

    // Null-coalescing (`??`) is the loosest binary operator.
    _reduceOps(block, {ASTExpressionOperator.nullCoalesce});

    // Final left-to-right fallback
    while (block.length >= 3) {
      var e1 = block.removeAt(0);
      var op = block.removeAt(0);
      var e2 = block.removeAt(0);
      block.insert(0, astExpressionOperation(e1, op, e2));
    }

    return block.single as ASTExpression;
  }

  void _reduceOps(List block, Set<ASTExpressionOperator> ops) {
    // Walk through the list treating it as:
    // [expr, op, expr, op, expr, ...]
    // So we advance by 2 each time when no reduction happens.
    var i = 0;

    // We need at least 3 elements to form: e1 op e2
    while (i < block.length - 2) {
      var e1 = block[i]; // left operand
      var op = _opAt(block, i + 1); // operator (if valid)
      var e2 = block[i + 2]; // right operand

      // If the operator matches the current precedence group
      // (e.g. *, /, % OR +, -), we reduce this triplet
      if (op != null && ops.contains(op)) {
        var exp = astExpressionOperation(e1, op, e2);

        // Replace [e1, op, e2] with the resulting expression
        // Important: always remove at the same index (i),
        // because the list shifts left after each removal.
        block
          ..removeAt(i) // removes e1
          ..removeAt(i) // removes op (now at index i)
          ..removeAt(i) // removes e2 (now at index i)
          ..insert(i, exp); // insert reduced expression in place

        // Do NOT advance `i` here:
        // the new expression at index `i` may combine again
        // with the next operator of the same precedence.
      } else {
        // Skip to the next operator position
        i += 2;
      }
    }
  }

  ASTExpressionOperator? _opAt(List block, int i) {
    var e = block[i];
    return e is ASTExpressionOperator ? e : null;
  }
}
