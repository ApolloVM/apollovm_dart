@TestOn('vm')
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Helper to perform intentional cross-type `==` comparisons without
/// triggering `unrelated_type_equality_checks`.
bool _eq(ASTType a, ASTType b) => a == b;

void main() {
  final context = VMScopeContext(ASTBlock(null));

  group('ASTTypeArray basics', () {
    test('static instances names and generics', () {
      expect(ASTTypeArray.instanceOfString.name, equals('List'));
      expect(ASTTypeArray.instanceOfInt.name, equals('List'));
      expect(ASTTypeArray.instanceOfDouble.name, equals('List'));
      expect(ASTTypeArray.instanceOfBool.name, equals('List'));
      expect(ASTTypeArray.instanceOfObject.name, equals('List'));
      expect(ASTTypeArray.instanceOfDynamic.name, equals('List'));

      expect(ASTTypeArray.instanceOfString.generics, hasLength(1));
      expect(
        ASTTypeArray.instanceOfString.elementType,
        equals(ASTTypeString.instance),
      );
      expect(
        ASTTypeArray.instanceOfInt.componentType,
        equals(ASTTypeInt.instance),
      );
    });

    test('toString includes generics', () {
      expect(ASTTypeArray.instanceOfString.toString(), equals('List<String>'));
      expect(ASTTypeArray.instanceOfInt.toString(), equals('List<int>'));
    });

    test('factory returns shared instances for primitives', () {
      expect(
        identical(
          ASTTypeArray(ASTTypeString.instance),
          ASTTypeArray.instanceOfString,
        ),
        isTrue,
      );
      expect(
        identical(
          ASTTypeArray(ASTTypeInt.instance),
          ASTTypeArray.instanceOfInt,
        ),
        isTrue,
      );
      expect(
        identical(
          ASTTypeArray(ASTTypeBool.instance),
          ASTTypeArray.instanceOfBool,
        ),
        isTrue,
      );
    });

    test('fromType maps List<T> to array instances', () {
      expect(
        ASTTypeArray.fromType(List<String>),
        equals(ASTTypeArray.instanceOfString),
      );
      expect(
        ASTTypeArray.fromType(List<int>),
        equals(ASTTypeArray.instanceOfInt),
      );
      expect(
        ASTTypeArray.fromType(List<double>),
        equals(ASTTypeArray.instanceOfDouble),
      );
      expect(
        ASTTypeArray.fromType(List<bool>),
        equals(ASTTypeArray.instanceOfBool),
      );
      expect(
        ASTTypeArray.fromType(List<Object>),
        equals(ASTTypeArray.instanceOfObject),
      );
      expect(
        ASTTypeArray.fromType(List<dynamic>),
        equals(ASTTypeArray.instanceOfDynamic),
      );
      expect(ASTTypeArray.fromType(int), isNull);
    });

    test('withType factory maps element type', () {
      var a = ASTTypeArray<ASTTypeString, String>.withType(String);
      expect(identical(a, ASTTypeArray.instanceOfString), isTrue);
    });

    test('ASTType.fromType resolves array types', () {
      expect(
        ASTType.fromType(List<String>),
        equals(ASTTypeArray.instanceOfString),
      );
    });
  });

  group('ASTTypeArray toValue / toASTValue', () {
    test('toValue from native List', () async {
      ASTValue? v = await ASTTypeArray.instanceOfInt.toValue(context, [
        1,
        2,
        3,
      ]);
      expect(v, isNotNull);
      var list = await v!.getValue(context);
      expect(list, equals([1, 2, 3]));
    });

    test('toValue wraps single value into list', () async {
      ASTValue? v = await ASTTypeArray.instanceOfString.toValue(context, 'x');
      var list = await v!.getValue(context);
      expect(list, equals(['x']));
    });

    test('toValue filters non-matching element types', () async {
      ASTValue? v = await ASTTypeArray.instanceOfInt.toValue(context, [
        1,
        'a',
        2,
      ]);
      var list = await v!.getValue(context);
      expect(list, equals([1, 2]));
    });

    test('toValue null returns null', () async {
      expect(await ASTTypeArray.instanceOfInt.toValue(context, null), isNull);
    });

    test('toASTValue from List', () {
      var v = ASTTypeArray.instanceOfString.toASTValue(['a', 'b']);
      expect(v, isNotNull);
      expect(v!.getValueNoContext(), equals(['a', 'b']));
      expect(ASTTypeArray.instanceOfString.toASTValue(null), isNull);
    });
  });

  group('ASTTypeArray2D / Array3D', () {
    test('fromElementType 2D', () {
      var a2 = ASTTypeArray2D<ASTTypeInt, int>.fromElementType(
        ASTTypeInt.instance,
      );
      expect(a2.name, equals('List'));
      expect(a2.elementType, equals(ASTTypeInt.instance));
      expect(a2.toString(), startsWith('List<List<'));
    });

    test('2D toValue from nested List', () async {
      // Base-typed so `toValue` returns a `FutureOr` (avoids await_only_futures).
      ASTType a2 = ASTTypeArray2D<ASTTypeInt, int>.fromElementType(
        ASTTypeInt.instance,
      );
      ASTValue? v = await a2.toValue(context, [
        [1, 2],
        [3, 4],
      ]);
      expect(v, isNotNull);
      var list = await v!.getValue(context);
      expect(
        list,
        equals([
          [1, 2],
          [3, 4],
        ]),
      );
    });

    test('2D toASTValue', () {
      var a2 = ASTTypeArray2D<ASTTypeString, String>.fromElementType(
        ASTTypeString.instance,
      );
      var v = a2.toASTValue([
        ['a'],
        ['b'],
      ]);
      expect(v, isNotNull);
      expect(a2.toASTValue(null), isNull);
    });

    test('fromElementType 3D', () {
      var a3 = ASTTypeArray3D<ASTTypeInt, int>.fromElementType(
        ASTTypeInt.instance,
      );
      expect(a3.name, equals('List'));
      expect(a3.elementType, equals(ASTTypeInt.instance));
    });

    test('3D toValue from triple-nested List', () async {
      ASTType a3 = ASTTypeArray3D<ASTTypeInt, int>.fromElementType(
        ASTTypeInt.instance,
      );
      ASTValue? v = await a3.toValue(context, [
        [
          [1, 2],
        ],
        [
          [3],
        ],
      ]);
      expect(v, isNotNull);
    });
  });

  group('ASTType.fromNativeValue nested lists', () {
    test('nested list infers a List array type', () {
      var t = ASTType.fromNativeValue(<List<int>>[
        [1],
        [2],
      ]);
      expect(t.name, equals('List'));
      expect(t, isA<ASTTypeArray>());
    });

    test('triple-nested list infers a List array type', () {
      var t = ASTType.fromNativeValue(<List<List<String>>>[
        [
          ['a'],
        ],
      ]);
      expect(t.name, equals('List'));
      expect(t, isA<ASTTypeArray>());
    });

    test('generic list inference', () {
      var t = ASTType.fromNativeValue(<num>[1, 2]);
      expect(t.name, equals('List'));
      expect(t, isA<ASTTypeArray>());
    });
  });

  group('ASTTypeMap', () {
    test('static instances and names', () {
      expect(ASTTypeMap.instanceOfStringOfDynamic.name, equals('Map'));
      expect(
        ASTTypeMap.instanceOfStringOfDynamic.keyType,
        equals(ASTTypeString.instance),
      );
      expect(
        ASTTypeMap.instanceOfStringOfDynamic.valueType,
        equals(ASTTypeDynamic.instance),
      );
      expect(
        ASTTypeMap.instanceOfStringOfString.valueType,
        equals(ASTTypeString.instance),
      );
      expect(
        ASTTypeMap.instanceOfDynamicOfDynamic.keyType,
        equals(ASTTypeDynamic.instance),
      );
    });

    test('toString includes generics', () {
      expect(
        ASTTypeMap.instanceOfStringOfString.toString(),
        equals('Map<String,String>'),
      );
    });

    test('fromType maps Map types', () {
      expect(
        ASTTypeMap.fromType(Map<String, dynamic>),
        equals(ASTTypeMap.instanceOfStringOfDynamic),
      );
      expect(
        ASTTypeMap.fromType(Map<String, String>),
        equals(ASTTypeMap.instanceOfStringOfString),
      );
      expect(
        ASTTypeMap.fromType(Map<dynamic, dynamic>),
        equals(ASTTypeMap.instanceOfDynamicOfDynamic),
      );
      expect(ASTTypeMap.fromType(int), isNull);
    });

    test('ASTType.fromType resolves Map types', () {
      expect(
        ASTType.fromType(Map<String, String>),
        equals(ASTTypeMap.instanceOfStringOfString),
      );
    });

    test('toValue from real Map', () async {
      var v = await ASTTypeMap.instanceOfStringOfString.toValue(context, {
        'a': '1',
        'b': '2',
      });
      expect(v, isNotNull);
      var map = await v!.getValue(context);
      expect(map, equals({'a': '1', 'b': '2'}));
    });

    test('toValue from MapEntry list', () async {
      var v = await ASTTypeMap.instanceOfStringOfString.toValue(context, [
        MapEntry('a', '1'),
        MapEntry('b', '2'),
      ]);
      var map = await v!.getValue(context);
      expect(map, equals({'a': '1', 'b': '2'}));
    });

    test('toValue from flat pair list', () async {
      var v = await ASTTypeMap.instanceOfStringOfString.toValue(context, [
        'a',
        '1',
      ]);
      var map = await v!.getValue(context);
      expect(map, equals({'a': '1'}));
    });

    test('toValue null returns null', () async {
      expect(
        await ASTTypeMap.instanceOfStringOfString.toValue(context, null),
        isNull,
      );
    });

    test('toASTValue', () {
      var v = ASTTypeMap.instanceOfStringOfString.toASTValue({'k': 'v'});
      expect(v, isNotNull);
      expect(ASTTypeMap.instanceOfStringOfString.toASTValue(null), isNull);
    });
  });

  group('ASTTypeFuture', () {
    test('name and toString', () {
      var f = ASTTypeFuture<ASTTypeInt, int>(ASTTypeInt.instance);
      expect(f.name, equals('Future'));
      expect(f.toString(), equals('Future<int>'));
    });

    test('toASTValue wraps a value into a Future', () async {
      var f = ASTTypeFuture<ASTTypeInt, int>(ASTTypeInt.instance);
      var v = f.toASTValue(42);
      expect(v, isNotNull);
      var resolved = await v!.getValueNoContext();
      expect(resolved, equals(42));
      expect(f.toASTValue(null), isNull);
    });

    test('toASTValue wraps an existing Future', () async {
      var f = ASTTypeFuture<ASTTypeInt, int>(ASTTypeInt.instance);
      var v = f.toASTValue(Future<int>.value(7));
      var resolved = await v!.getValueNoContext();
      expect(resolved, equals(7));
    });

    test('toValue from Future', () async {
      var f = ASTTypeFuture<ASTTypeInt, int>(ASTTypeInt.instance);
      var v = f.toValue(context, Future<int>.value(9));
      expect(v, isNotNull);
    });
  });

  group('ASTTypeFunction', () {
    test('name and generics', () {
      var f = ASTTypeFunction(ASTTypeInt.instance, [ASTTypeString.instance]);
      expect(f.name, equals('Function'));
      expect(f.generics, isNotNull);
      expect(f.generics, hasLength(2));
    });

    test('toValue null returns null', () {
      var f = ASTTypeFunction();
      expect(f.toValue(context, null), isNull);
      expect(f.toASTValue(null), isNull);
    });

    test('toValue with non-null throws UnsupportedError', () {
      var f = ASTTypeFunction();
      expect(() => f.toValue(context, 123), throwsUnsupportedError);
      expect(() => f.toASTValue(123), throwsUnsupportedError);
    });
  });

  group('ASTTypeGenericVariable / Wildcard', () {
    test('generic variable name and resolveType', () {
      var g = ASTTypeGenericVariable('T', ASTTypeInt.instance);
      expect(g.name, equals('T'));
      expect(g.variableName, equals('T'));
      expect(g.resolveType(context), equals(ASTTypeInt.instance));
    });

    test('generic variable without type resolves to Object', () {
      var g = ASTTypeGenericVariable('E');
      expect(g.resolveType(context), equals(ASTTypeObject.instance));
    });

    test('generic variable toValue delegates to resolved type', () async {
      var g = ASTTypeGenericVariable('T', ASTTypeInt.instance);
      var v = await g.toValue(context, 5);
      expect(v, isNotNull);
      expect(await v!.getValue(context), equals(5));
    });

    test('wildcard resolveType is Object', () {
      expect(
        ASTTypeGenericWildcard.instance.resolveType(context),
        equals(ASTTypeObject.instance),
      );
      expect(ASTTypeGenericWildcard.instance.name, equals('?'));
    });

    test('acceptsType accepts wildcard argument', () {
      // `acceptsType` returns true when the argument is the wildcard instance.
      var t = ASTType('Custom');
      expect(t.acceptsType(ASTTypeGenericWildcard.instance), isTrue);
    });
  });

  group('ASTTypeObject', () {
    test('toString and acceptsType', () {
      expect(ASTTypeObject.instance.toString(), equals('Object'));
      expect(ASTTypeObject.instance.acceptsType(ASTTypeInt.instance), isTrue);
      expect(
        ASTTypeObject.instance.acceptsType(ASTTypeString.instance),
        isTrue,
      );
    });

    test('toValue from raw value', () async {
      var v = await ASTTypeObject.instance.toValue(context, 'hi');
      expect(v, isNotNull);
      expect(await v!.getValue(context), equals('hi'));
    });

    test('toValue null returns null', () async {
      expect(await ASTTypeObject.instance.toValue(context, null), isNull);
    });

    test('equality and hashCode', () {
      expect(_eq(ASTTypeObject.instance, ASTTypeObject()), isTrue);
      expect(ASTTypeObject.instance.hashCode, equals(ASTTypeObject().hashCode));
    });
  });

  group('ASTTypeDynamic', () {
    test('toString and acceptsType', () {
      expect(ASTTypeDynamic.instance.toString(), equals('dynamic'));
      expect(ASTTypeDynamic.instance.acceptsType(ASTTypeInt.instance), isTrue);
    });

    test('toValue wraps raw value', () async {
      var v = await ASTTypeDynamic.instance.toValue(context, 123);
      expect(v, isNotNull);
      expect(await v.getValue(context), equals(123));
    });
  });

  group('ASTTypeVar', () {
    test('var and final names', () {
      expect(ASTTypeVar.instance.name, equals('var'));
      expect(ASTTypeVar.instance.toString(), equals('var'));
      expect(ASTTypeVar.instanceUnmodifiable.toString(), equals('final'));
      expect(ASTTypeVar.instanceUnmodifiable.unmodifiable, isTrue);
    });

    test('acceptsType always true', () {
      expect(ASTTypeVar.instance.acceptsType(ASTTypeInt.instance), isTrue);
    });

    test('toValue wraps raw value', () async {
      var v = await ASTTypeVar.instance.toValue(context, 'data');
      expect(v, isNotNull);
      expect(await v.getValue(context), equals('data'));
    });

    test('resolveType returns self when no associated node', () async {
      ASTType t = ASTTypeVar();
      expect(await t.resolveType(context), isA<ASTTypeVar>());
    });
  });

  group('ASTTypeNull', () {
    test('toString and acceptsType', () {
      expect(ASTTypeNull.instance.toString(), equals('Null'));
      expect(ASTTypeNull.instance.acceptsType(ASTTypeNull.instance), isTrue);
      expect(ASTTypeNull.instance.acceptsType(ASTTypeInt.instance), isFalse);
    });

    test('toValue returns ASTValueNull', () {
      ASTType nullType = ASTTypeNull.instance;
      var v = nullType.toValue(context, 'anything');
      expect(v, isNotNull);
    });

    test('toASTValue returns null instance', () {
      expect(ASTTypeNull.instance.toASTValue(null), isNotNull);
    });

    test('ASTType.from(null) is Null type', () {
      expect(ASTType.from(null), equals(ASTTypeNull.instance));
    });
  });

  group('ASTTypeVoid', () {
    test('toString and acceptsType', () {
      expect(ASTTypeVoid.instance.toString(), equals('void'));
      expect(ASTTypeVoid.instance.acceptsType(ASTTypeVoid.instance), isTrue);
      expect(ASTTypeVoid.instance.acceptsType(ASTTypeInt.instance), isFalse);
    });

    test('toValue returns void value', () {
      ASTType voidType = ASTTypeVoid.instance;
      expect(voidType.toValue(context, null), isNotNull);
      expect(ASTTypeVoid.instance.toASTValue(null), isNotNull);
    });
  });

  group('ASTTypeConstructorThis', () {
    test('toString and acceptsType', () {
      expect(ASTTypeConstructorThis.instance.toString(), equals('this'));
      expect(
        ASTTypeConstructorThis.instance.acceptsType(ASTTypeInt.instance),
        isTrue,
      );
    });

    test('toValue wraps raw value', () async {
      var v = await ASTTypeConstructorThis.instance.toValue(context, 'self');
      expect(v, isNotNull);
      expect(await v.getValue(context), equals('self'));
    });

    test('resolveType returns self when no associated node', () async {
      ASTType t = ASTTypeConstructorThis.instance;
      expect(await t.resolveType(context), isA<ASTTypeConstructorThis>());
    });
  });

  group('ASTType.from and fromAsync', () {
    test('from ASTType returns same', () {
      expect(ASTType.from(ASTTypeInt.instance), equals(ASTTypeInt.instance));
    });

    test('from native int value', () {
      expect(ASTType.from(5), equals(ASTTypeInt.instance));
    });

    test('fromAsync null', () async {
      expect(await ASTType.fromAsync(null), equals(ASTTypeNull.instance));
    });

    test('fromAsync ASTType returns same', () async {
      expect(
        await ASTType.fromAsync(ASTTypeString.instance),
        equals(ASTTypeString.instance),
      );
    });

    test('fromAsync native value', () async {
      expect(await ASTType.fromAsync('x'), equals(ASTTypeString.instance));
      expect(await ASTType.fromAsync(2.5), equals(ASTTypeDouble.instance));
    });
  });

  group('acceptsType edge cases', () {
    test('generics matching same lengths', () {
      var a = ASTTypeArray.instanceOfInt;
      expect(a.acceptsType(ASTTypeArray.instanceOfInt), isTrue);
    });

    test('different name without superType is rejected', () {
      expect(ASTTypeString.instance.acceptsType(ASTTypeInt.instance), isFalse);
    });

    test('superType chain accepted', () {
      var sub = ASTType('Sub', superType: ASTTypeObject.instance);
      var base = ASTType('Base');
      // `sub` has Object as superType, and Object accepts `base`, so the
      // name-mismatch check passes and (no generics) the result is true.
      expect(base.acceptsType(sub), isTrue);

      // Without a superType, a name mismatch is rejected.
      var noSuper = ASTType('Other');
      expect(base.acceptsType(noSuper), isFalse);
    });

    test('commonType resolves to accepting type', () {
      expect(
        ASTTypeObject.instance.commonType(ASTTypeInt.instance),
        equals(ASTTypeObject.instance),
      );
      expect(
        ASTTypeInt.instance.commonType(ASTTypeInt.instance),
        equals(ASTTypeInt.instance),
      );
      expect(ASTTypeInt.instance.commonType(null), equals(ASTTypeInt.instance));
    });

    test('canCastToType', () {
      expect(ASTTypeInt.instance.canCastToType(ASTTypeObject.instance), isTrue);
      expect(
        ASTTypeObject.instance.canCastToType(ASTTypeInt.instance),
        isFalse,
      );
    });
  });

  group('ASTType generic equality / hashCode', () {
    test('arrays with same component are equal', () {
      var a = ASTTypeArray(ASTTypeInt.instance);
      var b = ASTTypeArray.instanceOfInt;
      expect(_eq(a, b), isTrue);
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different component arrays not equal', () {
      expect(
        _eq(ASTTypeArray.instanceOfInt, ASTTypeArray.instanceOfString),
        isFalse,
      );
    });

    test('hasGenerics / hasSuperType flags', () {
      expect(ASTTypeArray.instanceOfInt.hasGenerics, isTrue);
      expect(ASTTypeInt.instance.hasGenerics, isFalse);
      var t = ASTType('X', superType: ASTTypeObject.instance);
      expect(t.hasSuperType, isTrue);
      expect(ASTTypeInt.instance.hasSuperType, isFalse);
    });
  });

  group('ASTNumType enum', () {
    test('enum values present', () {
      expect(ASTNumType.values, contains(ASTNumType.int));
      expect(ASTNumType.values, contains(ASTNumType.double));
      expect(ASTNumType.values, contains(ASTNumType.num));
      expect(ASTNumType.values, contains(ASTNumType.nan));
    });
  });

  group('ASTTypeNum / Double extra', () {
    test('num accepts num/int/double', () {
      expect(ASTTypeNum.instance.acceptsType(ASTTypeNum.instance), isTrue);
    });

    test('double accepts int', () {
      expect(ASTTypeDouble.instance.acceptsType(ASTTypeInt.instance), isTrue);
      expect(
        ASTTypeDouble.instance.acceptsType(ASTTypeString.instance),
        isFalse,
      );
    });

    test('doubleToString helper', () {
      expect(ASTTypeDouble.doubleToString(0.0), equals('0.0'));
      expect(ASTTypeDouble.doubleToString(5), equals('5.0'));
      expect(ASTTypeDouble.doubleToString(1.5), equals('1.5'));
    });

    test('double equals strict bits', () {
      expect(
        ASTTypeDouble.instance32.equals(ASTTypeDouble.instance64),
        isFalse,
      );
      expect(ASTTypeDouble.instance.equals(ASTTypeDouble.instance32), isTrue);
      expect(
        ASTTypeDouble.instance.equals(ASTTypeDouble.instance32, strict: true),
        isFalse,
      );
    });

    test('equalsStrict extension', () {
      expect(ASTTypeInt.instance.equalsStrict(ASTTypeInt.instance32), isFalse);
      expect(
        ASTTypeString.instance.equalsStrict(ASTTypeString.instance),
        isTrue,
      );
    });
  });
}
