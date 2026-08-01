@TestOn('vm')
@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Normalizes a [FutureOr] into a [Future] so `await` is always valid.
Future<T> _await<T>(FutureOr<T> v) async => await v;

ASTExpression _lit(Object v) => ASTExpressionLiteral(ASTValue.fromValue(v));

/// `ASTExpressionLiteral.toString()` prefixes the value's type, so an expected
/// source form is built from the same rendering rather than hard-coded.
String _s(ASTExpression e) => e.toString();

void main() {
  group('astExpressionOperation() specialization', () {
    test('`??` becomes an ASTExpressionNullCoalesce', () {
      expect(
        astExpressionOperation(
          _lit(1),
          ASTExpressionOperator.nullCoalesce,
          _lit(2),
        ),
        isA<ASTExpressionNullCoalesce>(),
      );
    });

    test('`&&` / `||` become the short-circuit logical nodes', () {
      expect(
        astExpressionOperation(_lit(true), ASTExpressionOperator.and, _lit(1)),
        isA<ASTExpressionLogicalAnd>(),
      );
      expect(
        astExpressionOperation(_lit(true), ASTExpressionOperator.or, _lit(1)),
        isA<ASTExpressionLogicalOr>(),
      );
    });

    test('`x == null` / `x != null` become an ASTExpressionNullCheck', () {
      var eq =
          astExpressionOperation(
                _lit(1),
                ASTExpressionOperator.equals,
                ASTExpressionNullValue(),
              )
              as ASTExpressionNullCheck;
      expect(eq.negated, isFalse);
      expect(eq.nullFirst, isFalse);

      var ne =
          astExpressionOperation(
                _lit(1),
                ASTExpressionOperator.notEquals,
                ASTExpressionNullValue(),
              )
              as ASTExpressionNullCheck;
      expect(ne.negated, isTrue);
    });

    test('`null == x` records nullFirst so the operand order round-trips', () {
      var operand = _lit(1);
      var e =
          astExpressionOperation(
                ASTExpressionNullValue(),
                ASTExpressionOperator.equals,
                operand,
              )
              as ASTExpressionNullCheck;

      expect(e.nullFirst, isTrue);
      expect(e.expression, same(operand));
      expect(_s(e), equals('null == ${_s(operand)}'));
    });

    test('a comparison between two non-null operands is left generic', () {
      var e = astExpressionOperation(
        _lit(1),
        ASTExpressionOperator.equals,
        _lit(2),
      );
      expect(e, isA<ASTExpressionOperation>());
      expect(e, isNot(isA<ASTExpressionNullCheck>()));
    });

    test('arithmetic is left generic', () {
      expect(
        astExpressionOperation(_lit(1), ASTExpressionOperator.add, _lit(2)),
        isA<ASTExpressionOperation>(),
      );
    });
  });

  group('ASTExpressionNullCoalesce', () {
    test('keeps both operands as children', () {
      var a = _lit(1), b = _lit(2);
      var e = ASTExpressionNullCoalesce(a, b);
      expect(e.children, orderedEquals([a, b]));
    });

    test('regenerates its source form', () {
      var a = _lit(1), b = _lit(2);
      expect(
        _s(ASTExpressionNullCoalesce(a, b)),
        equals('${_s(a)} ?? ${_s(b)}'),
      );
    });

    test(
      'resolves to the non-nullable left type unified with the right',
      () async {
        var e = ASTExpressionNullCoalesce(_lit(1), _lit(2));
        expect(await _await(e.resolveType(null)), equals(ASTTypeInt.instance));
      },
    );
  });

  group('ASTExpressionNullCheck', () {
    test('is statically a bool', () async {
      var e = ASTExpressionNullCheck(_lit(1), ASTExpressionNullValue());
      expect(await _await(e.resolveType(null)), same(ASTTypeBool.instance));
    });

    test('retains the null literal as a child, in source order', () {
      var plain = ASTExpressionNullCheck(_lit(1), ASTExpressionNullValue());
      expect(plain.children.last, isA<ASTExpressionNullValue>());
      expect(plain.children, hasLength(2));

      var reversed = ASTExpressionNullCheck(
        _lit(1),
        ASTExpressionNullValue(),
        nullFirst: true,
      );
      expect(reversed.children.first, isA<ASTExpressionNullValue>());
    });

    test('regenerates both operand orders', () {
      var operand = _lit(1);
      expect(
        _s(ASTExpressionNullCheck(operand, ASTExpressionNullValue())),
        equals('${_s(operand)} == null'),
      );
      expect(
        _s(
          ASTExpressionNullCheck(
            operand,
            ASTExpressionNullValue(),
            negated: true,
          ),
        ),
        equals('${_s(operand)} != null'),
      );
    });
  });

  group('ASTExpressionLogical', () {
    test('short-circuit predicates and results', () {
      var and = ASTExpressionLogicalAnd(_lit(true), _lit(true));
      expect(and.operator, equals(ASTExpressionOperator.and));
      expect(and.shortCircuitsOn(false), isTrue);
      expect(and.shortCircuitsOn(true), isFalse);
      expect(and.shortCircuitValue.value, isFalse);

      var or = ASTExpressionLogicalOr(_lit(true), _lit(true));
      expect(or.operator, equals(ASTExpressionOperator.or));
      expect(or.shortCircuitsOn(true), isTrue);
      expect(or.shortCircuitsOn(false), isFalse);
      expect(or.shortCircuitValue.value, isTrue);
    });

    test('is statically a bool', () async {
      expect(
        await _await(
          ASTExpressionLogicalAnd(_lit(true), _lit(true)).resolveType(null),
        ),
        same(ASTTypeBool.instance),
      );
      expect(
        await _await(
          ASTExpressionLogicalOr(_lit(true), _lit(true)).resolveType(null),
        ),
        same(ASTTypeBool.instance),
      );
    });

    test('regenerates its source form', () {
      var a = _lit(1), b = _lit(2);
      expect(_s(ASTExpressionLogicalAnd(a, b)), equals('${_s(a)} && ${_s(b)}'));
      expect(_s(ASTExpressionLogicalOr(a, b)), equals('${_s(a)} || ${_s(b)}'));
    });
  });

  group('ASTExpressionOperation rejects the specialized operators', () {
    test('`??` reports that it is its own node', () {
      var e = ASTExpressionOperation(
        _lit(1),
        ASTExpressionOperator.nullCoalesce,
        _lit(2),
      );
      expect(() => e.resolveType(null), throwsA(isA<StateError>()));
    });

    test('`&&` / `||` still type as bool but must not be evaluated', () {
      // `resolveType` is fine — the result really is a bool. It is `run` that
      // would evaluate both operands eagerly, which is why it throws instead.
      for (var op in [ASTExpressionOperator.and, ASTExpressionOperator.or]) {
        var e = ASTExpressionOperation(_lit(true), op, _lit(true));
        expect(e.resolveType(null), same(ASTTypeBool.instance));
      }
    });
  });
}
