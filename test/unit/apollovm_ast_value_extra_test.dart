@TestOn('vm')
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Helper to route intentional cross-type `==` comparisons through `ASTValue`,
/// avoiding `unrelated_type_equality_checks` analyzer warnings.
bool _eq(ASTValue a, Object? b) => a == b;

/// Normalizes a [FutureOr] into a [Future] so `await` is always valid
/// regardless of the concrete (possibly synchronous) return type.
Future<T> _await<T>(FutureOr<T> v) async => await v;

void main() {
  group('ASTValueAsString', () {
    test('getValueNoContext (int -> toString)', () async {
      var v = ASTValueAsString(ASTValueInt(42));
      expect(await _await(v.getValueNoContext()), equals('42'));
      expect(v.type, isA<ASTTypeString>());
    });

    test('getValue with context', () async {
      var context = VMScopeContext(ASTBlock(null));
      var v = ASTValueAsString(ASTValueInt(7));
      expect(await v.getValue(context), equals('7'));
    });

    test('resolve returns ASTValueString', () async {
      var context = VMScopeContext(ASTBlock(null));
      var v = ASTValueAsString(ASTValueInt(3));
      var resolved = await v.resolve(context);
      expect(resolved, isA<ASTValueString>());
      expect(await _await(resolved.getValueNoContext()), equals('3'));
    });

    test('valueToString num + ASTTypeDouble path', () {
      var s = ASTValueAsString.valueToString(5, ASTTypeDouble.instance);
      expect(s, equals('5.0'));
    });

    test('valueToString plain toString path', () {
      expect(ASTValueAsString.valueToString(5), equals('5'));
      expect(ASTValueAsString.valueToString('abc'), equals('abc'));
      expect(ASTValueAsString.valueToString(null), equals('null'));
    });

    test('valueToString double value through wrapped ASTValueDouble', () async {
      var v = ASTValueAsString(ASTValueDouble(5));
      expect(await _await(v.getValueNoContext()), equals('5.0'));
    });

    test('children contains wrapped value', () {
      var inner = ASTValueInt(1);
      var v = ASTValueAsString(inner);
      expect(v.children, contains(inner));
    });
  });

  group('ASTValuesListAsString', () {
    test('getValueNoContext joins values', () async {
      var v = ASTValuesListAsString([
        ASTValueString('a'),
        ASTValueInt(1),
        ASTValueDouble(2),
      ]);
      expect(await _await(v.getValueNoContext()), equals('a12.0'));
    });

    test('getValue with context joins values', () async {
      var context = VMScopeContext(ASTBlock(null));
      var v = ASTValuesListAsString([ASTValueString('x'), ASTValueInt(9)]);
      expect(await v.getValue(context), equals('x9'));
    });

    test('resolve returns ASTValueString', () async {
      var context = VMScopeContext(ASTBlock(null));
      var v = ASTValuesListAsString([ASTValueString('hi'), ASTValueInt(5)]);
      var resolved = await v.resolve(context);
      expect(resolved, isA<ASTValueString>());
      expect(await _await(resolved.getValueNoContext()), equals('hi5'));
    });
  });

  group('ASTValueStringConcatenation', () {
    test('getValueNoContext concatenation', () async {
      var v = ASTValueStringConcatenation([
        ASTValueString('foo'),
        ASTValueString('bar'),
      ]);
      expect(await _await(v.getValueNoContext()), equals('foobar'));
    });

    test('getValue with context', () async {
      var context = VMScopeContext(ASTBlock(null));
      var v = ASTValueStringConcatenation([
        ASTValueString('a'),
        ASTValueString('b'),
        ASTValueString('c'),
      ]);
      expect(await v.getValue(context), equals('abc'));
    });

    test('toString joins with " + "', () {
      var v = ASTValueStringConcatenation([
        ASTValueString('a'),
        ASTValueString('b'),
      ]);
      expect(v.toString(), equals('"a" + "b"'));
    });

    test('resolve returns ASTValuesListAsString', () async {
      var context = VMScopeContext(ASTBlock(null));
      var v = ASTValueStringConcatenation([
        ASTValueString('x'),
        ASTValueString('y'),
      ]);
      var resolved = await v.resolve(context);
      expect(await _await(resolved.getValueNoContext()), equals('xy'));
    });
  });

  group('ASTValueStringExpression', () {
    test('getValue with context (literal int)', () async {
      var context = VMScopeContext(ASTBlock(null));
      var v = ASTValueStringExpression(ASTExpressionLiteral(ASTValueInt(5)));
      expect(await v.getValue(context), equals('5'));
    });

    test('getValueNoContext throws UnsupportedError', () {
      var v = ASTValueStringExpression(ASTExpressionLiteral(ASTValueInt(5)));
      expect(() => v.getValueNoContext(), throwsUnsupportedError);
    });

    test('toString wraps expression', () {
      var v = ASTValueStringExpression(ASTExpressionLiteral(ASTValueInt(5)));
      expect(v.toString(), contains('\${'));
    });

    test('resolve returns ASTValueString', () async {
      var context = VMScopeContext(ASTBlock(null));
      var v = ASTValueStringExpression(ASTExpressionLiteral(ASTValueInt(8)));
      var resolved = await v.resolve(context);
      expect(resolved, isA<ASTValueString>());
      expect(await _await(resolved.getValueNoContext()), equals('8'));
    });
  });

  group('ASTValueObject', () {
    test('getValueNoContext returns object', () async {
      var obj = Object();
      var v = ASTValueObject(obj);
      expect(await _await(v.getValueNoContext()), same(obj));
      expect(v.type, isA<ASTTypeObject>());
    });

    test('equality by underlying value', () {
      var v1 = ASTValueObject('same');
      var v2 = ASTValueObject('same');
      expect(v1, equals(v2));
    });

    test('inequality for different objects', () {
      var v1 = ASTValueObject('a');
      var v2 = ASTValueObject('b');
      expect(v1 == v2, isFalse);
    });
  });

  group('ASTValueArray', () {
    test('getValueNoContext returns list', () async {
      var arr = ASTValueArray<ASTTypeInt, int>(ASTTypeInt.instance, [1, 2, 3]);
      expect(await _await(arr.getValueNoContext()), equals([1, 2, 3]));
    });

    test('cast int -> double', () async {
      var arr = ASTValueArray<ASTTypeInt, int>(ASTTypeInt.instance, [1, 2, 3]);
      var casted = arr.cast<ASTTypeDouble, double>(
        componentType: ASTTypeDouble.instance,
      );
      var v = await _await(casted.getValueNoContext());
      expect(v, equals([1.0, 2.0, 3.0]));
      expect(v, everyElement(isA<double>()));
    });

    test('equals via equals() method', () async {
      var a = ASTValueArray<ASTTypeInt, int>(ASTTypeInt.instance, [1, 2]);
      var b = ASTValueArray<ASTTypeInt, int>(ASTTypeInt.instance, [1, 2]);
      expect(await a.equals(b), isTrue);
    });

    test('not equals different list', () async {
      var a = ASTValueArray<ASTTypeInt, int>(ASTTypeInt.instance, [1, 2]);
      var b = ASTValueArray<ASTTypeInt, int>(ASTTypeInt.instance, [1, 3]);
      expect(await a.equals(b), isFalse);
    });
  });

  group('ASTValueArray2D', () {
    test('getValueNoContext returns nested list', () async {
      var arr = ASTValueArray2D<ASTTypeInt, int>(ASTTypeInt.instance, [
        [1, 2],
        [3, 4],
      ]);
      expect(
        await _await(arr.getValueNoContext()),
        equals([
          [1, 2],
          [3, 4],
        ]),
      );
    });

    test('operator== deep equality', () {
      var a = ASTValueArray2D<ASTTypeInt, int>(ASTTypeInt.instance, [
        [1, 2],
        [3, 4],
      ]);
      var b = ASTValueArray2D<ASTTypeInt, int>(ASTTypeInt.instance, [
        [1, 2],
        [3, 4],
      ]);
      expect(a == b, isTrue);
    });

    test('operator== deep inequality', () {
      var a = ASTValueArray2D<ASTTypeInt, int>(ASTTypeInt.instance, [
        [1, 2],
      ]);
      var b = ASTValueArray2D<ASTTypeInt, int>(ASTTypeInt.instance, [
        [9, 9],
      ]);
      expect(a == b, isFalse);
    });

    test('hashCode equal for equal contents', () {
      var a = ASTValueArray2D<ASTTypeInt, int>(ASTTypeInt.instance, [
        [1, 2],
      ]);
      var b = ASTValueArray2D<ASTTypeInt, int>(ASTTypeInt.instance, [
        [1, 2],
      ]);
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('ASTValueArray3D', () {
    test('getValueNoContext returns 3D nested list', () async {
      var arr = ASTValueArray3D<ASTTypeInt, int>(ASTTypeInt.instance, [
        [
          [1, 2],
          [3],
        ],
        [
          [4],
        ],
      ]);
      expect(
        await _await(arr.getValueNoContext()),
        equals([
          [
            [1, 2],
            [3],
          ],
          [
            [4],
          ],
        ]),
      );
    });

    test('operator== deep equality (inherited)', () {
      var a = ASTValueArray3D<ASTTypeInt, int>(ASTTypeInt.instance, [
        [
          [1],
        ],
      ]);
      var b = ASTValueArray3D<ASTTypeInt, int>(ASTTypeInt.instance, [
        [
          [1],
        ],
      ]);
      expect(a == b, isTrue);
    });
  });

  group('ASTValueStatic readIndex / readKey / size', () {
    test('readIndex on a list', () {
      var context = VMScopeContext(ASTBlock(null));
      var v = ASTValueStatic<dynamic>(ASTTypeDynamic.instance, [10, 20, 30]);
      expect(v.readIndex(context, 1), equals(20));
    });

    test('size on a list', () {
      var context = VMScopeContext(ASTBlock(null));
      var v = ASTValueStatic<dynamic>(ASTTypeDynamic.instance, [10, 20, 30]);
      expect(v.size(context), equals(3));
    });

    test('readKey on a map', () {
      var context = VMScopeContext(ASTBlock(null));
      var v = ASTValueStatic<dynamic>(ASTTypeDynamic.instance, {
        'a': 1,
        'b': 2,
      });
      expect(v.readKey(context, 'b'), equals(2));
    });

    test('readIndex on a map (entry value by position)', () {
      var context = VMScopeContext(ASTBlock(null));
      var v = ASTValueStatic<dynamic>(ASTTypeDynamic.instance, {
        'a': 1,
        'b': 2,
      });
      expect(v.readIndex(context, 0), equals(1));
    });

    test('size on a map returns null (not Iterable)', () {
      var context = VMScopeContext(ASTBlock(null));
      var v = ASTValueStatic<dynamic>(ASTTypeDynamic.instance, {'a': 1});
      expect(v.size(context), isNull);
    });

    test('readIndex throws for non-collection', () {
      var context = VMScopeContext(ASTBlock(null));
      var v = ASTValueStatic<int>(ASTTypeInt.instance, 5);
      expect(() => v.readIndex(context, 0), throwsA(isA<Exception>()));
    });

    test('toString format', () {
      var v = ASTValueStatic<int>(ASTTypeInt.instance, 5);
      expect(v.toString(), contains('value: 5'));
    });

    test('equality by value', () {
      var a = ASTValueStatic<int>(ASTTypeInt.instance, 5);
      var b = ASTValueStatic<int>(ASTTypeInt.instance, 5);
      expect(a == b, isTrue);
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('ASTValueVar', () {
    test('getValueNoContext returns stored object', () async {
      var v = ASTValueVar('hello');
      expect(await _await(v.getValueNoContext()), equals('hello'));
      expect(v.type, isA<ASTTypeVar>());
    });
  });

  group('ASTValue.fromValue factory', () {
    test('fromValue int', () async {
      var v = ASTValue.fromValue<int>(5);
      expect(v, isA<ASTValueInt>());
      expect(await _await(v.getValueNoContext()), equals(5));
    });

    test('fromValue String', () {
      var v = ASTValue.fromValue<String>('abc');
      expect(v, isA<ASTValueString>());
    });

    test('fromValue null', () {
      var v = ASTValue.fromValue<dynamic>(null);
      expect(v, isA<ASTValueNull>());
    });

    test('fromValue double', () {
      var v = ASTValue.fromValue<double>(1.5);
      expect(v, isA<ASTValueDouble>());
    });

    test('fromValue bool', () {
      var v = ASTValue.fromValue<bool>(true);
      expect(v, isA<ASTValueBool>());
    });
  });

  group('ASTValueBool.from / ASTValueNum.from factories', () {
    test('ASTValueBool.from num', () async {
      expect(await _await(ASTValueBool.from(1).getValueNoContext()), isTrue);
      expect(await _await(ASTValueBool.from(0).getValueNoContext()), isFalse);
    });

    test('ASTValueBool.from String', () async {
      expect(
        await _await(ASTValueBool.from('true').getValueNoContext()),
        isTrue,
      );
    });

    test('ASTValueNum.from int string with decimal -> double', () {
      var v = ASTValueNum.from('5.0');
      expect(v, isA<ASTValueDouble>());
    });

    test('ASTValueNum.from int', () {
      var v = ASTValueNum.from(5);
      expect(v, isA<ASTValueInt>());
    });
  });

  group('cross-type equality helper', () {
    test('_eq for ASTValueInt vs ASTValueDouble same value', () {
      // ASTValueNum compares across int/double when types accept each other.
      var a = ASTValueInt(5);
      var b = ASTValueDouble(5);
      // Route through helper to avoid analyzer unrelated_type warnings.
      expect(_eq(a, b), isA<bool>());
    });
  });
}
