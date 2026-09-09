@TestOn('vm')
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// The assignment-operator tables: source symbol → [ASTAssignmentOperator] →
/// the binary operator a compound form lowers to, and back to source.
///
/// Every grammar reads its `x OP= y` through these, and the Wasm backend (plus
/// the targets with no compound form) lowers through
/// `asASTExpressionOperator` — so a wrong entry silently changes what a program
/// computes.

/// Source symbol → operator → the binary operator it applies (`null` for `=`).
const _table = <String, (ASTAssignmentOperator, ASTExpressionOperator?)>{
  '=': (ASTAssignmentOperator.set, null),
  '+=': (ASTAssignmentOperator.sum, ASTExpressionOperator.add),
  '-=': (ASTAssignmentOperator.subtract, ASTExpressionOperator.subtract),
  '*=': (ASTAssignmentOperator.multiply, ASTExpressionOperator.multiply),
  '/=': (ASTAssignmentOperator.divide, ASTExpressionOperator.divide),
  '~/=': (ASTAssignmentOperator.divideAsInt, ASTExpressionOperator.divideAsInt),
  '%=': (ASTAssignmentOperator.remainder, ASTExpressionOperator.remainder),
  '&=': (ASTAssignmentOperator.bitwiseAnd, ASTExpressionOperator.bitwiseAnd),
  '|=': (ASTAssignmentOperator.bitwiseOr, ASTExpressionOperator.bitwiseOr),
  '^=': (ASTAssignmentOperator.bitwiseXor, ASTExpressionOperator.bitwiseXor),
  '<<=': (ASTAssignmentOperator.shiftLeft, ASTExpressionOperator.shiftLeft),
  '>>=': (ASTAssignmentOperator.shiftRight, ASTExpressionOperator.shiftRight),
  '??=': (
    ASTAssignmentOperator.nullCoalesce,
    ASTExpressionOperator.nullCoalesce,
  ),
};

void main() {
  group('ASTAssignmentOperator', () {
    test('every symbol parses to its operator and prints back', () {
      for (var entry in _table.entries) {
        var symbol = entry.key;
        var (op, _) = entry.value;

        expect(
          getASTAssignmentOperator(symbol),
          equals(op),
          reason: '`$symbol` should parse as $op',
        );
        expect(
          getASTAssignmentOperatorText(op),
          equals(symbol),
          reason: '$op should print as `$symbol`',
        );
      }
    });

    test('surrounding whitespace is ignored', () {
      expect(getASTAssignmentOperator('  += '), ASTAssignmentOperator.sum);
    });

    test('every operator covered, and each lowers to its binary form', () {
      // The table is the whole enum: a new operator without an entry fails
      // here rather than going untested.
      expect(
        _table.values.map((e) => e.$1).toSet(),
        equals(ASTAssignmentOperator.values.toSet()),
      );

      for (var entry in _table.entries) {
        var (op, expressionOperator) = entry.value;
        expect(
          op.asASTExpressionOperator,
          equals(expressionOperator),
          reason: '`${entry.key}` should lower to $expressionOperator',
        );
      }

      expect(
        ASTAssignmentOperator.set.asASTExpressionOperator,
        isNull,
        reason: 'a plain assignment applies no operator',
      );
    });

    test('an unknown symbol is refused, not read as `=`', () {
      for (var bogus in ['', '==', '=+', '<<<=', 'x']) {
        expect(
          () => getASTAssignmentOperator(bogus),
          throwsA(isA<UnsupportedError>()),
          reason: '`$bogus` is not an assignment operator',
        );
      }
    });
  });

  group('The direct (`++` / `--`) operators', () {
    test('map to sum/subtract and print back', () {
      expect(getASTAssignmentDirectOperator('++'), ASTAssignmentOperator.sum);
      expect(
        getASTAssignmentDirectOperator(' -- '),
        ASTAssignmentOperator.subtract,
      );

      expect(
        getASTAssignmentDirectOperatorText(ASTAssignmentOperator.sum),
        '++',
      );
      expect(
        getASTAssignmentDirectOperatorText(ASTAssignmentOperator.subtract),
        '--',
      );
    });

    test('anything else is refused, in both directions', () {
      expect(
        () => getASTAssignmentDirectOperator('+='),
        throwsA(isA<UnsupportedError>()),
      );
      expect(
        () =>
            getASTAssignmentDirectOperatorText(ASTAssignmentOperator.multiply),
        throwsA(isA<UnsupportedError>()),
        reason: 'there is no `**` direct form',
      );
    });
  });
}
