@TestOn('vm')
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Compares two values through the [ASTValue] `==` operator. Routing through a
/// typed helper keeps the intentional cross-type comparisons (e.g. int vs
/// double) from tripping the `unrelated_type_equality_checks` lint.
bool _valEq(ASTValue a, Object? b) => a == b;

void main() {
  group('ASTValueInt', () {
    test('arithmetic with int', () {
      var a = ASTValueInt(7);
      expect((a + ASTValueInt(3)).getValueNoContext(), equals(10));
      expect((a - ASTValueInt(2)).getValueNoContext(), equals(5));
      expect((a * ASTValueInt(3)).getValueNoContext(), equals(21));
      expect((a ~/ ASTValueInt(2)).getValueNoContext(), equals(3));
      expect((a % ASTValueInt(4)).getValueNoContext(), equals(3));
    });

    test('division always yields double', () {
      var r = ASTValueInt(6) / ASTValueInt(4);
      expect(r, isA<ASTValueDouble>());
      expect(r.getValueNoContext(), equals(1.5));
    });

    test('mixed int/double arithmetic promotes to double', () {
      expect(
        (ASTValueInt(2) + ASTValueDouble(0.5)).getValueNoContext(),
        equals(2.5),
      );
      expect((ASTValueInt(5) * ASTValueDouble(2.0)), isA<ASTValueDouble>());
    });

    test('+ with string concatenates', () {
      var r = ASTValueInt(42) + ASTValueString('!');
      expect(r, isA<ASTValueString>());
      expect(r.getValueNoContext(), equals('42!'));
    });

    test('unsupported operand throws', () {
      expect(
        () => ASTValueInt(1) + ASTValueBool(true),
        throwsA(isA<UnsupportedValueOperationError>()),
      );
      expect(
        () => ASTValueInt(1) - ASTValueString('x'),
        throwsA(isA<UnsupportedValueOperationError>()),
      );
    });

    test('toString', () {
      expect(ASTValueInt(5).toString(), equals('(int) 5'));
    });

    test('negative flag', () {
      var n = ASTValueInt(5, negative: true);
      expect(n.value, equals(-5));
      expect(n.negative, isTrue);
      expect(n.isZero, isFalse);
      expect(ASTValueInt(0).isZero, isTrue);
    });
  });

  group('ASTValueDouble', () {
    test('arithmetic', () {
      var a = ASTValueDouble(2.5);
      expect((a + ASTValueDouble(0.5)).getValueNoContext(), equals(3.0));
      expect((a - ASTValueInt(1)).getValueNoContext(), equals(1.5));
      expect((a * ASTValueInt(2)).getValueNoContext(), equals(5.0));
      expect((a / ASTValueDouble(2.0)).getValueNoContext(), equals(1.25));
      expect((a ~/ ASTValueInt(1)).getValueNoContext(), equals(2));
      expect(
        (ASTValueDouble(5.5) % ASTValueInt(2)).getValueNoContext(),
        equals(1.5),
      );
    });

    test('~/ yields int', () {
      expect(ASTValueDouble(7.9) ~/ ASTValueInt(2), isA<ASTValueInt>());
    });

    test('+ with string concatenates', () {
      expect(
        (ASTValueDouble(1.5) + ASTValueString('x')).getValueNoContext(),
        equals('1.5x'),
      );
    });

    test('toString', () {
      expect(ASTValueDouble(1.5).toString(), equals('(double) 1.5'));
    });
  });

  group('ASTValueNum comparisons & equality', () {
    test('comparison operators', () async {
      expect(await (ASTValueInt(3) > ASTValueInt(2)), isTrue);
      expect(await (ASTValueInt(3) < ASTValueInt(2)), isFalse);
      expect(await (ASTValueInt(3) >= ASTValueInt(3)), isTrue);
      expect(await (ASTValueInt(2) <= ASTValueDouble(2.0)), isTrue);
    });

    test('equality across int/double of same value', () {
      expect(_valEq(ASTValueInt(2), ASTValueDouble(2.0)), isTrue);
      expect(_valEq(ASTValueInt(2), ASTValueInt(3)), isFalse);
      expect(ASTValueInt(2).hashCode, equals(ASTValueInt(2).hashCode));
    });

    test('equals() resolves values', () async {
      expect(await ASTValueInt(5).equals(ASTValueInt(5)), isTrue);
      expect(await ASTValueInt(5).equals(ASTValueDouble(5.0)), isTrue);
      expect(await ASTValueInt(5).equals(ASTValueInt(6)), isFalse);
    });
  });

  group('ASTValueNum.from', () {
    test('parses ints and doubles', () {
      expect(ASTValueNum.from(10), isA<ASTValueInt>());
      expect(ASTValueNum.from(1.5), isA<ASTValueDouble>());
      expect(ASTValueNum.from('7').getValueNoContext(), equals(7));
      expect(ASTValueNum.from('7.5').getValueNoContext(), equals(7.5));
    });

    test('string with decimal/exponent intent becomes double', () {
      expect(ASTValueNum.from('3.0'), isA<ASTValueDouble>());
      expect(ASTValueNum.from('1e3'), isA<ASTValueDouble>());
    });

    test('asDouble forces type', () {
      expect(ASTValueNum.from(4, asDouble: true), isA<ASTValueDouble>());
      expect(ASTValueNum.from(4.7, asDouble: false), isA<ASTValueInt>());
      expect(
        ASTValueNum.from(4.7, asDouble: false).getValueNoContext(),
        equals(4),
      );
    });

    test('invalid input throws', () {
      expect(() => ASTValueNum.from(true), throwsA(isA<StateError>()));
    });
  });

  group('ASTValueBool', () {
    test('from various inputs', () {
      expect(ASTValueBool.from(true).getValueNoContext(), isTrue);
      expect(ASTValueBool.from(0).getValueNoContext(), isFalse);
      expect(ASTValueBool.from(5).getValueNoContext(), isTrue);
      expect(ASTValueBool.from('true').getValueNoContext(), isTrue);
    });

    test('invalid input throws', () {
      expect(() => ASTValueBool.from([]), throwsA(isA<StateError>()));
    });

    test('TRUE/FALSE constants', () {
      expect(ASTValueBool.TRUE.getValueNoContext(), isTrue);
      expect(ASTValueBool.FALSE.getValueNoContext(), isFalse);
    });
  });

  group('ASTValueString', () {
    test('toString quotes the value', () {
      expect(ASTValueString('hi').toString(), equals('"hi"'));
    });

    test('comparison operators throw with the right operator symbol', () {
      var s = ASTValueString('a');
      expect(
        () => s > ASTValueString('b'),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'message',
            contains("'>'"),
          ),
        ),
      );
      expect(
        () => s < ASTValueString('b'),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains("'<'"),
              isNot(contains("non number values: \"a\" >")),
            ),
          ),
        ),
      );
      expect(() => s >= ASTValueString('b'), throwsA(isA<UnsupportedError>()));
      expect(() => s <= ASTValueString('b'), throwsA(isA<UnsupportedError>()));
    });

    test('equality by value', () {
      expect(ASTValueString('x') == ASTValueString('x'), isTrue);
      expect(ASTValueString('x') == ASTValueString('y'), isFalse);
    });
  });

  group('ASTValueNull / ASTValueVoid', () {
    test('null equality and hashCode', () {
      expect(ASTValueNull() == ASTValueNull.instance, isTrue);
      expect(_valEq(ASTValueNull.instance, ASTValueInt(0)), isFalse);
      expect(ASTValueNull.instance.hashCode, equals(-1));
      expect(ASTValueNull.instance.toString(), equals('null'));
    });

    test('void equality and hashCode', () {
      expect(ASTValueVoid() == ASTValueVoid.instance, isTrue);
      expect(_valEq(ASTValueVoid.instance, ASTValueNull.instance), isFalse);
      expect(ASTValueVoid.instance.hashCode, equals(-2));
      expect(ASTValueVoid.instance.toString(), equals('void'));
    });
  });

  group('ASTValueArray', () {
    final context = VMScopeContext(ASTBlock(null));

    test('readIndex and size', () {
      var arr = ASTValueArray<ASTTypeInt, int>(ASTTypeInt.instance, [
        10,
        20,
        30,
      ]);
      expect(arr.readIndex<int>(context, 1), equals(20));
      expect(arr.size(context), equals(3));
      expect(arr.getValueNoContext(), equals([10, 20, 30]));
    });

    test('equals compares element-wise', () async {
      var a = ASTValueArray<ASTTypeInt, int>(ASTTypeInt.instance, [1, 2]);
      var b = ASTValueArray<ASTTypeInt, int>(ASTTypeInt.instance, [1, 2]);
      var c = ASTValueArray<ASTTypeInt, int>(ASTTypeInt.instance, [1, 3]);
      expect(await a.equals(b), isTrue);
      expect(await a.equals(c), isFalse);
    });

    test('cast converts component type', () {
      var ints = ASTValueArray<ASTTypeInt, int>(ASTTypeInt.instance, [1, 2, 3]);
      var doubles = ints.cast<ASTTypeDouble, double>(
        componentType: ASTTypeDouble.instance,
      );
      expect(doubles.getValueNoContext(), equals([1.0, 2.0, 3.0]));
    });
  });

  group('ASTValueStatic readKey', () {
    final context = VMScopeContext(ASTBlock(null));

    test('reads from a map', () {
      var m = ASTValueMap<ASTTypeString, ASTTypeInt, String, int>(
        ASTTypeString.instance,
        ASTTypeInt.instance,
        {'a': 1, 'b': 2},
      );
      expect(m.readKey<int>(context, 'b'), equals(2));
    });
  });
}
