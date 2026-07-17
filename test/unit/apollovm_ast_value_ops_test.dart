@TestOn('vm')
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Routes intentional cross-type `==` comparisons through [ASTValue] to avoid
/// the `unrelated_type_equality_checks` analyzer warning.
bool _eq(ASTValue a, Object? b) => a == b;

/// Normalizes a [FutureOr] into a [Future] so `await` is always valid.
Future<T> _await<T>(FutureOr<T> v) async => await v;

void main() {
  group('ASTValueDouble operators', () {
    test('+ - * / ~/ % with int and double operands', () {
      var d = ASTValueDouble(6.0);
      expect((d + ASTValueInt(2)).getValueNoContext(), equals(8.0));
      expect((d + ASTValueDouble(1.5)).getValueNoContext(), equals(7.5));
      expect((d - ASTValueInt(1)).getValueNoContext(), equals(5.0));
      expect((d - ASTValueDouble(0.5)).getValueNoContext(), equals(5.5));
      expect((d * ASTValueInt(2)).getValueNoContext(), equals(12.0));
      expect((d * ASTValueDouble(0.5)).getValueNoContext(), equals(3.0));
      expect((d / ASTValueInt(4)).getValueNoContext(), equals(1.5));
      expect((d / ASTValueDouble(2.0)).getValueNoContext(), equals(3.0));
      expect((d ~/ ASTValueInt(4)), isA<ASTValueInt>());
      expect((d ~/ ASTValueInt(4)).getValueNoContext(), equals(1));
      expect((d ~/ ASTValueDouble(2.0)).getValueNoContext(), equals(3));
      expect((d % ASTValueInt(4)).getValueNoContext(), equals(2.0));
      expect((d % ASTValueDouble(2.5)).getValueNoContext(), equals(1.0));
    });

    test('+ with string concatenates', () {
      var r = ASTValueDouble(1.5) + ASTValueString('!');
      expect(r, isA<ASTValueString>());
      expect(r.getValueNoContext(), equals('1.5!'));
    });

    test('unsupported operands throw', () {
      expect(
        () => ASTValueDouble(1.0) + ASTValueBool(true),
        throwsA(isA<UnsupportedValueOperationError>()),
      );
      expect(
        () => ASTValueDouble(1.0) - ASTValueString('x'),
        throwsA(isA<UnsupportedValueOperationError>()),
      );
      expect(
        () => ASTValueDouble(1.0) * ASTValueBool(false),
        throwsA(isA<UnsupportedValueOperationError>()),
      );
      expect(
        () => ASTValueDouble(1.0) / ASTValueString('x'),
        throwsA(isA<UnsupportedValueOperationError>()),
      );
      expect(
        () => ASTValueDouble(1.0) ~/ ASTValueString('x'),
        throwsA(isA<UnsupportedValueOperationError>()),
      );
      expect(
        () => ASTValueDouble(1.0) % ASTValueBool(true),
        throwsA(isA<UnsupportedValueOperationError>()),
      );
    });

    test('toString', () {
      expect(ASTValueDouble(2.5).toString(), equals('(double) 2.5'));
    });
  });

  group('ASTValueInt operators with double operands', () {
    test('- * ~/ % against a double', () {
      var i = ASTValueInt(7);
      expect((i - ASTValueDouble(2.0)).getValueNoContext(), equals(5.0));
      expect((i * ASTValueDouble(2.0)).getValueNoContext(), equals(14.0));
      expect((i ~/ ASTValueDouble(2.0)).getValueNoContext(), equals(3));
      expect((i % ASTValueDouble(4.0)).getValueNoContext(), equals(3.0));
    });

    test('unsupported operands throw for every operator', () {
      var i = ASTValueInt(1);
      expect(
        () => i * ASTValueBool(true),
        throwsA(isA<UnsupportedValueOperationError>()),
      );
      expect(
        () => i / ASTValueBool(true),
        throwsA(isA<UnsupportedValueOperationError>()),
      );
      expect(
        () => i ~/ ASTValueBool(true),
        throwsA(isA<UnsupportedValueOperationError>()),
      );
      expect(
        () => i % ASTValueBool(true),
        throwsA(isA<UnsupportedValueOperationError>()),
      );
    });
  });

  group('ASTValueNum comparisons and equality', () {
    test('>, <, >=, <= against another ASTValueNum', () async {
      expect(await _await(ASTValueInt(5) > ASTValueDouble(3.0)), isTrue);
      expect(await _await(ASTValueDouble(2.0) < ASTValueInt(3)), isTrue);
      expect(await _await(ASTValueInt(5) >= ASTValueInt(5)), isTrue);
      expect(await _await(ASTValueDouble(3.0) <= ASTValueInt(3)), isTrue);
    });

    test('comparisons against non-ASTValue return false', () async {
      expect(await _await(ASTValueInt(5) > 3), isFalse);
      expect(await _await(ASTValueInt(5) < 3), isFalse);
      expect(await _await(ASTValueInt(5) >= 3), isFalse);
      expect(await _await(ASTValueInt(5) <= 3), isFalse);
    });

    test('== between int and same-valued int is true', () {
      expect(_eq(ASTValueInt(5), ASTValueInt(5)), isTrue);
    });

    test(
      '== between numeric values compares by value regardless of int/double',
      () {
        // int accepts double (numeric widening), so equality falls through to a
        // value comparison rather than short-circuiting on the type mismatch.
        expect(_eq(ASTValueInt(5), ASTValueDouble(5.0)), isTrue);
        expect(_eq(ASTValueInt(5), ASTValueDouble(6.0)), isFalse);
      },
    );

    test('equals coerces across numeric values', () async {
      expect(await _await(ASTValueInt(5).equals(ASTValueDouble(5.0))), isTrue);
      expect(await _await(ASTValueDouble(5.0).equals(ASTValueInt(6))), isFalse);
    });

    test('isZero', () {
      expect(ASTValueInt(0).isZero, isTrue);
      expect(ASTValueDouble(0.0).isZero, isTrue);
      expect(ASTValueInt(1).isZero, isFalse);
    });
  });

  group('ASTValueNum.from', () {
    test('from int / double / string', () {
      expect(ASTValueNum.from(3), isA<ASTValueInt>());
      expect(ASTValueNum.from(3.5), isA<ASTValueDouble>());
      expect(ASTValueNum.from('7'), isA<ASTValueInt>());
      expect(ASTValueNum.from('7.5'), isA<ASTValueDouble>());
    });

    test('string with decimal point stays double even when whole', () {
      var v = ASTValueNum.from('7.0');
      expect(v, isA<ASTValueDouble>());
    });

    test('asDouble forces representation', () {
      expect(ASTValueNum.from(4, asDouble: true), isA<ASTValueDouble>());
      expect(ASTValueNum.from(4.9, asDouble: false), isA<ASTValueInt>());
      expect(
        ASTValueNum.from(4.9, asDouble: false).getValueNoContext(),
        equals(4),
      );
    });

    test('negative flag', () {
      expect(
        ASTValueNum.from(5, negative: true).getValueNoContext(),
        equals(-5),
      );
    });

    test('non-parsable input throws', () {
      expect(() => ASTValueNum.from(true), throwsA(isA<StateError>()));
    });
  });

  group('ASTValueBool', () {
    test('TRUE/FALSE singletons', () {
      expect(ASTValueBool.TRUE.getValueNoContext(), isTrue);
      expect(ASTValueBool.FALSE.getValueNoContext(), isFalse);
    });

    test('from bool / num / string', () {
      expect(ASTValueBool.from(true).getValueNoContext(), isTrue);
      expect(ASTValueBool.from(1).getValueNoContext(), isTrue);
      expect(ASTValueBool.from(0).getValueNoContext(), isFalse);
      expect(ASTValueBool.from('true').getValueNoContext(), isTrue);
      expect(ASTValueBool.from('false').getValueNoContext(), isFalse);
    });

    test('from unparsable throws', () {
      expect(() => ASTValueBool.from(<int>[]), throwsA(isA<StateError>()));
    });
  });

  group('ASTValueString comparisons', () {
    test('ordering operators are unsupported', () {
      var s = ASTValueString('a');
      expect(() => s > ASTValueString('b'), throwsA(isA<UnsupportedError>()));
      expect(() => s < ASTValueString('b'), throwsA(isA<UnsupportedError>()));
      expect(() => s >= ASTValueString('b'), throwsA(isA<UnsupportedError>()));
      expect(() => s <= ASTValueString('b'), throwsA(isA<UnsupportedError>()));
    });

    test('toString quotes the value', () {
      expect(ASTValueString('hi').toString(), equals('"hi"'));
    });
  });

  group('ASTValueNull and ASTValueVoid', () {
    test('null equality / hashCode / toString', () async {
      expect(ASTValueNull.instance == ASTValueNull(), isTrue);
      expect(_eq(ASTValueNull.instance, ASTValueInt(0)), isFalse);
      expect(ASTValueNull.instance.hashCode, equals(-1));
      expect(
        await _await(ASTValueNull.instance.equals(ASTValueNull())),
        isTrue,
      );
      expect(
        await _await(ASTValueNull.instance.equals(ASTValueInt(0))),
        isFalse,
      );
      expect(ASTValueNull.instance.toString(), equals('null'));
    });

    test('void equality / hashCode / toString', () async {
      expect(ASTValueVoid.instance == ASTValueVoid(), isTrue);
      expect(_eq(ASTValueVoid.instance, ASTValueInt(0)), isFalse);
      expect(ASTValueVoid.instance.hashCode, equals(-2));
      expect(
        await _await(ASTValueVoid.instance.equals(ASTValueVoid())),
        isTrue,
      );
      expect(
        await _await(ASTValueVoid.instance.equals(ASTValueInt(0))),
        isFalse,
      );
      expect(ASTValueVoid.instance.toString(), equals('void'));
    });
  });

  group('ASTValueObject', () {
    test('wraps an arbitrary object', () {
      var o = Object();
      var v = ASTValueObject(o);
      expect(identical(v.getValueNoContext(), o), isTrue);
      expect(v.type, isA<ASTTypeObject>());
    });
  });
}
