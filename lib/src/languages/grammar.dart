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

        finalExpressionOp = ASTExpressionOperation(
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

    // Final left-to-right fallback
    while (block.length >= 3) {
      var e1 = block.removeAt(0);
      var op = block.removeAt(0);
      var e2 = block.removeAt(0);
      block.insert(0, ASTExpressionOperation(e1, op, e2));
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
        var exp = ASTExpressionOperation(e1, op, e2);

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
