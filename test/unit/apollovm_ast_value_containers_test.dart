@TestOn('vm')
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Normalizes a [FutureOr] into a [Future] so `await` is always valid
/// regardless of the concrete (possibly synchronous) return type.
Future<T> _await<T>(FutureOr<T> v) async => await v;

VMContext _ctx() => VMScopeContext(ASTBlock(null));

void main() {
  group('ASTValue.from factory', () {
    test('bool/string/int/double/null/void branches', () {
      expect(ASTValue.from(ASTTypeBool.instance, true), isA<ASTValueBool>());
      expect(ASTValue.from(ASTTypeString.instance, 'x'), isA<ASTValueString>());
      expect(ASTValue.from(ASTTypeInt.instance, 7), isA<ASTValueInt>());
      expect(ASTValue.from(ASTTypeDouble.instance, 1.5), isA<ASTValueDouble>());
      expect(ASTValue.from(ASTTypeNull.instance, null), isA<ASTValueNull>());
      expect(ASTValue.from(ASTTypeVoid.instance, null), isA<ASTValueVoid>());
    });

    test('object branch', () {
      var v = ASTValue.from(ASTTypeObject.instance, Object());
      expect(v, isA<ASTValueObject>());
    });
  });

  group('ASTValue.fromValue', () {
    test('null -> ASTValueNull', () {
      expect(ASTValue.fromValue(null), isA<ASTValueNull>());
    });

    test('ASTValue passthrough', () {
      var inner = ASTValueString('hi');
      expect(identical(ASTValue.fromValue(inner), inner), isTrue);
    });

    test('String/int/double/bool', () {
      expect(ASTValue.fromValue('s'), isA<ASTValueString>());
      expect(ASTValue.fromValue(3), isA<ASTValueInt>());
      expect(ASTValue.fromValue(2.5), isA<ASTValueDouble>());
      expect(ASTValue.fromValue(true), isA<ASTValueBool>());
    });

    test('int coerced to double when V == double', () {
      var v = ASTValue.fromValue<double>(4);
      expect(v, isA<ASTValueDouble>());
      expect(v.getValueNoContext(), equals(4.0));
    });

    test('whole double coerced to int when V == int', () {
      var v = ASTValue.fromValue<int>(4.0);
      expect(v, isA<ASTValueInt>());
      expect(v.getValueNoContext(), equals(4));
    });

    test('non-whole double is not narrowed to int', () {
      // A non-whole double can't be represented as an `ASTValue<int>`, so the
      // internal `as ASTValue<int>` narrowing throws rather than silently
      // truncating.
      expect(() => ASTValue.fromValue<int>(4.5), throwsA(isA<TypeError>()));
      // Without a target type, the double is preserved.
      expect(ASTValue.fromValue(4.5), isA<ASTValueDouble>());
    });
  });

  group('ASTValue comparison operators (base)', () {
    test('>, <, >=, <= on numeric static values', () async {
      var a = ASTValueInt(5);
      var b = ASTValueInt(3);
      expect(await _await(a > b), isTrue);
      expect(await _await(b < a), isTrue);
      expect(await _await(a >= ASTValueInt(5)), isTrue);
      expect(await _await(b <= ASTValueInt(3)), isTrue);
    });

    test('comparison with non-ASTValue returns false', () async {
      expect(await _await(ASTValueInt(1) > 'x'), isFalse);
      expect(await _await(ASTValueInt(1) < 'x'), isFalse);
    });

    test('equals across value types', () async {
      expect(await _await(ASTValueInt(5).equals(ASTValueInt(5))), isTrue);
      expect(await _await(ASTValueInt(5).equals(ASTValueInt(6))), isFalse);
      expect(await _await(ASTValueString('a').equals('a')), isFalse);
    });
  });

  group('ASTValueStatic index/key access', () {
    test('readIndex on List', () {
      var v = ASTValueStatic<List>(ASTTypeArray(ASTTypeInt.instance), [10, 20]);
      expect(v.readIndex(_ctx(), 1), equals(20));
    });

    test('readIndex on Map (nth entry value)', () {
      var v = ASTValueStatic<Map>(
        ASTTypeMap(ASTTypeString.instance, ASTTypeInt.instance),
        {'a': 1, 'b': 2},
      );
      expect(v.readIndex(_ctx(), 1), equals(2));
    });

    test('readKey on Map', () {
      var v = ASTValueStatic<Map>(
        ASTTypeMap(ASTTypeString.instance, ASTTypeInt.instance),
        {'a': 1},
      );
      expect(v.readKey(_ctx(), 'a'), equals(1));
    });

    test('readKey on Iterable via numeric key', () {
      var v = ASTValueStatic<List>(ASTTypeArray(ASTTypeInt.instance), [7, 8]);
      expect(v.readKey(_ctx(), '1'), equals(8));
    });

    test('writeIndex mutates List', () {
      var list = [1, 2, 3];
      var v = ASTValueStatic<List>(ASTTypeArray(ASTTypeInt.instance), list);
      v.writeIndex(_ctx(), 0, 99);
      expect(list[0], equals(99));
    });

    test('writeKey mutates Map', () {
      var map = <String, int>{'a': 1};
      var v = ASTValueStatic<Map>(
        ASTTypeMap(ASTTypeString.instance, ASTTypeInt.instance),
        map,
      );
      v.writeKey(_ctx(), 'b', 2);
      expect(map['b'], equals(2));
    });

    test('writeKey on List via numeric key', () {
      var list = [1, 2];
      var v = ASTValueStatic<List>(ASTTypeArray(ASTTypeInt.instance), list);
      v.writeKey(_ctx(), '1', 42);
      expect(list[1], equals(42));
    });

    test('size returns Iterable length', () {
      var v = ASTValueStatic<List>(ASTTypeArray(ASTTypeInt.instance), [
        1,
        2,
        3,
      ]);
      expect(v.size(_ctx()), equals(3));
    });

    test('readIndex on non-collection value throws', () {
      var v = ASTValueInt(5);
      expect(
        () => v.readIndex(_ctx(), 0),
        throwsA(isA<ApolloVMNullPointerException>()),
      );
    });

    test('writeKey on unsupported container throws', () {
      var v = ASTValueStatic<int>(ASTTypeInt.instance, 5);
      expect(
        () => v.writeKey(_ctx(), 'k', 1),
        throwsA(isA<ApolloVMNullPointerException>()),
      );
    });
  });

  group('ASTValueArray', () {
    test('cast<int -> double>', () {
      var a = ASTValueArray(ASTTypeInt.instance, [1, 2, 3]);
      var d = a.cast<ASTTypeDouble, double>(
        componentType: ASTTypeDouble.instance,
      );
      expect(d.value, equals([1.0, 2.0, 3.0]));
    });

    test('equals compares element-wise', () async {
      var a = ASTValueArray(ASTTypeInt.instance, [1, 2]);
      var b = ASTValueArray(ASTTypeInt.instance, [1, 2]);
      var c = ASTValueArray(ASTTypeInt.instance, [1, 3]);
      expect(await _await(a.equals(b)), isTrue);
      expect(await _await(a.equals(c)), isFalse);
      expect(await _await(a.equals(a)), isTrue);
    });
  });

  group('ASTValueArray2D', () {
    test('== and hashCode use deep equality', () {
      var a = ASTValueArray2D(ASTTypeInt.instance, [
        [1, 2],
        [3],
      ]);
      var b = ASTValueArray2D(ASTTypeInt.instance, [
        [1, 2],
        [3],
      ]);
      expect(a == b, isTrue);
      expect(a.hashCode, equals(b.hashCode));
      expect(identical(a, a) && a == a, isTrue);
    });
  });

  group('ASTValueMap', () {
    test('equals compares maps', () async {
      var a = ASTValueMap(ASTTypeString.instance, ASTTypeInt.instance, {
        'a': 1,
      });
      var b = ASTValueMap(ASTTypeString.instance, ASTTypeInt.instance, {
        'a': 1,
      });
      var c = ASTValueMap(ASTTypeString.instance, ASTTypeInt.instance, {
        'a': 2,
      });
      expect(await _await(a.equals(b)), isTrue);
      expect(await _await(a.equals(c)), isFalse);
      expect(await _await(a.equals(a)), isTrue);
    });
  });

  group('ASTValueVar', () {
    test('wraps arbitrary object with var type', () {
      var v = ASTValueVar('anything');
      expect(v.getValueNoContext(), equals('anything'));
      expect(v.type, isA<ASTTypeVar>());
    });
  });

  group('ASTValuesListAsString', () {
    test('getValueNoContext joins values as strings', () async {
      var v = ASTValuesListAsString([
        ASTValueInt(1),
        ASTValueString('-'),
        ASTValueDouble(2.0),
      ]);
      expect(await _await(v.getValueNoContext()), equals('1-2.0'));
    });

    test('getValue and resolve with context', () async {
      var ctx = _ctx();
      var v = ASTValuesListAsString([ASTValueString('a'), ASTValueString('b')]);
      expect(await _await(v.getValue(ctx)), equals('ab'));
      var resolved = await _await(v.resolve(ctx));
      expect(resolved, isA<ASTValueString>());
      expect(await _await(resolved.getValueNoContext()), equals('ab'));
    });
  });

  group('ASTValueStringConcatenation', () {
    test('getValue / getValueNoContext / resolve / toString', () async {
      var ctx = _ctx();
      var v = ASTValueStringConcatenation([
        ASTValueString('foo'),
        ASTValueString('bar'),
      ]);
      expect(await _await(v.getValueNoContext()), equals('foobar'));
      expect(await _await(v.getValue(ctx)), equals('foobar'));

      var resolved = await _await(v.resolve(ctx));
      expect(resolved, isA<ASTValuesListAsString>());
      expect(v.toString(), contains('+'));
    });

    test('getHashcodeValue without context', () async {
      var v = ASTValueStringConcatenation([
        ASTValueString('a'),
        ASTValueString('b'),
      ]);
      expect(await _await(v.getHashcodeValue(null)), equals('ab'));
    });
  });

  group('ASTValueFuture', () {
    test('getValue / getValueNoContext return the wrapped future', () async {
      var v = ASTValueFuture<ASTTypeInt, int>(
        ASTTypeInt.instance,
        Future.value(11),
      );
      expect(await v.getValueNoContext(), equals(11));
      expect(await v.getValue(_ctx()), equals(11));
    });

    test('== / hashCode by identity of wrapped future', () {
      var f = Future.value(1);
      var a = ASTValueFuture<ASTTypeInt, int>(ASTTypeInt.instance, f);
      var b = ASTValueFuture<ASTTypeInt, int>(ASTTypeInt.instance, f);
      expect(a == b, isTrue);
      expect(a.hashCode, equals(f.hashCode));
    });

    test('equals awaits both futures', () async {
      var a = ASTValueFuture<ASTTypeInt, int>(
        ASTTypeInt.instance,
        Future.value(5),
      );
      var b = ASTValueFuture<ASTTypeInt, int>(
        ASTTypeInt.instance,
        Future.value(5),
      );
      var c = ASTValueFuture<ASTTypeInt, int>(
        ASTTypeInt.instance,
        Future.value(6),
      );
      expect(await _await(a.equals(b)), isTrue);
      expect(await _await(a.equals(c)), isFalse);
    });

    test('resolve returns itself', () {
      var v = ASTValueFuture<ASTTypeInt, int>(
        ASTTypeInt.instance,
        Future.value(1),
      );
      expect(identical(v.resolve(_ctx()), v), isTrue);
    });
  });
}
