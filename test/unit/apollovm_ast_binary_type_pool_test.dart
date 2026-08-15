library;

import 'package:apollovm/apollovm.dart';
// Serialization internals are not re-exported from the public library.
import 'package:apollovm/src/serialization/ast_binary_pool.dart';
import 'package:apollovm/src/serialization/ast_binary_type_pool.dart';
import 'package:test/test.dart';

/// Interns [types], encodes both pools, decodes them back, and returns the
/// decoded types in the same order — the exact path a real file takes.
List<ASTType> _roundTrip(List<ASTType> types) {
  var strings = ASTStringPoolWriter();
  var pool = ASTTypePoolWriter(strings);

  var indexes = types.map(pool.intern).toList();

  var stringsBytes = strings.encode();
  var typesBytes = pool.encode();

  var stringsIn = ASTStringPoolReader.decode(stringsBytes);
  var typesIn = ASTTypePoolReader.decode(typesBytes, stringsIn);

  return indexes.map((i) => typesIn[i]).toList();
}

ASTType _one(ASTType t) => _roundTrip([t]).single;

void main() {
  group('well-known types keep their identity', () {
    // Identity is load-bearing, not an optimization:
    // `ASTConstructorParameterDeclaration.resolveNode` compares its parameter
    // type against `ASTTypeConstructorThis.instance` with `identical`.
    final singletons = <String, ASTType>{
      'int': ASTTypeInt.instance,
      'int32': ASTTypeInt.instance32,
      'int64': ASTTypeInt.instance64,
      'double': ASTTypeDouble.instance,
      'double32': ASTTypeDouble.instance32,
      'double64': ASTTypeDouble.instance64,
      'num': ASTTypeNum.instance,
      'bool': ASTTypeBool.instance,
      'String': ASTTypeString.instance,
      'Object': ASTTypeObject.instance,
      'dynamic': ASTTypeDynamic.instance,
      'Null': ASTTypeNull.instance,
      'void': ASTTypeVoid.instance,
      'var': ASTTypeVar.instance,
      'var unmodifiable': ASTTypeVar.instanceUnmodifiable,
      'constructor this': ASTTypeConstructorThis.instance,
      'generic wildcard': ASTTypeGenericWildcard.instance,
      'List<String>': ASTTypeArray.instanceOfString,
      'List<int>': ASTTypeArray.instanceOfInt,
      'List<double>': ASTTypeArray.instanceOfDouble,
      'List<bool>': ASTTypeArray.instanceOfBool,
      'List<Object>': ASTTypeArray.instanceOfObject,
      'List<dynamic>': ASTTypeArray.instanceOfDynamic,
      'Map<String,dynamic>': ASTTypeMap.instanceOfStringOfDynamic,
      'Map<String,String>': ASTTypeMap.instanceOfStringOfString,
      'Map<dynamic,dynamic>': ASTTypeMap.instanceOfDynamicOfDynamic,
    };

    for (var e in singletons.entries) {
      test(e.key, () {
        expect(identical(_one(e.value), e.value), isTrue);
      });
    }

    test('all of them at once, indices stay aligned', () {
      var input = singletons.values.toList();
      var output = _roundTrip(input);

      expect(output.length, equals(input.length));
      for (var i = 0; i < input.length; ++i) {
        expect(
          identical(output[i], input[i]),
          isTrue,
          reason: 'index $i (${input[i]}) lost its identity',
        );
      }
    });
  });

  group('structural types', () {
    test('named type', () {
      var t = _one(ASTType('Foo'));
      expect(t.name, equals('Foo'));
      expect(t.runtimeType, equals(ASTType('x').runtimeType));
    });

    test('generics and super type', () {
      var t = _one(
        ASTType(
          'Wrapper',
          generics: [ASTTypeInt.instance, ASTType('Bar')],
          superType: ASTType('Base'),
        ),
      );

      expect(t.name, equals('Wrapper'));
      expect(t.generics!.length, equals(2));
      expect(identical(t.generics![0], ASTTypeInt.instance), isTrue);
      expect(t.generics![1].name, equals('Bar'));
      expect(t.superType!.name, equals('Base'));
    });

    test('an empty generics list is distinct from a null one', () {
      // `List` and `List<>` are not the same thing to the generators, so the
      // null/empty distinction has to survive.
      expect(_one(ASTType('A', generics: [])).generics, isEmpty);
      expect(_one(ASTType('A')).generics, isNull);
    });

    test('array of a user type', () {
      var t = _one(ASTTypeArray(ASTType('Foo'))) as ASTTypeArray;
      expect(t.name, equals('List'));
      expect(t.componentType.name, equals('Foo'));
    });

    test('2D and 3D arrays rebuild through the same factory', () {
      // Widened to `ASTType` exactly as the grammars do (`v[4] as ASTType`);
      // passing the narrow singleton type directly does not infer.
      ASTType elementInt = ASTTypeInt.instance;
      ASTType elementString = ASTTypeString.instance;

      var t2 = _one(ASTTypeArray2D.fromElementType(elementInt));
      expect(t2, isA<ASTTypeArray2D>());
      expect(
        ((t2 as ASTTypeArray).componentType as ASTTypeArray).componentType,
        equals(ASTTypeInt.instance),
      );

      var t3 = _one(ASTTypeArray3D.fromElementType(elementString));
      expect(t3, isA<ASTTypeArray3D>());
    });

    test('map of user types', () {
      var t = _one(ASTTypeMap(ASTType('K'), ASTType('V'))) as ASTTypeMap;
      expect(t.keyType.name, equals('K'));
      expect(t.valueType.name, equals('V'));
    });

    test('future', () {
      var t = _one(ASTTypeFuture(ASTType('Foo'))) as ASTTypeFuture;
      expect(t.futureValueType.name, equals('Foo'));
    });

    test('function type keeps its whole signature', () {
      var t =
          _one(
                ASTTypeFunction(ASTTypeInt.instance, [
                  ASTTypeString.instance,
                  ASTType('Foo'),
                ]),
              )
              as ASTTypeFunction;

      expect(t.generics!.length, equals(3));
      expect(identical(t.generics![0], ASTTypeInt.instance), isTrue);
      expect(identical(t.generics![1], ASTTypeString.instance), isTrue);
      expect(t.generics![2].name, equals('Foo'));
    });

    test('function type with no return type', () {
      var t = _one(ASTTypeFunction(null, [ASTTypeInt.instance]));
      expect(t, isA<ASTTypeFunction>());
      expect(t.generics!.length, equals(1));
    });

    test('int and double bit widths', () {
      expect((_one(ASTTypeInt(bits: 16)) as ASTTypeInt).bits, equals(16));
      expect(
        (_one(ASTTypeDouble(bits: 128)) as ASTTypeDouble).bits,
        equals(128),
      );
    });

    test('generic variable with and without a bound', () {
      var bare = _one(ASTTypeGenericVariable('T')) as ASTTypeGenericVariable;
      expect(bare.variableName, equals('T'));
      expect(bare.type, isNull);

      var bound =
          _one(ASTTypeGenericVariable('T', ASTType('Base')))
              as ASTTypeGenericVariable;
      expect(bound.variableName, equals('T'));
      expect(bound.type!.name, equals('Base'));
    });

    test('interface type keeps its class and super interface', () {
      var t =
          _one(ASTTypeInterface('Iface', superInterface: ASTType('Base')))
              as ASTTypeInterface;
      expect(t.name, equals('Iface'));
      expect(t.superType!.name, equals('Base'));
    });

    test('annotations survive with their parameters', () {
      var t = _one(
        ASTType(
          'Foo',
          annotations: [
            ASTAnnotation('Deprecated', {
              'message': ASTAnnotationParameter('message', 'use Bar', true),
            }),
            ASTAnnotation('Marker'),
          ],
        ),
      );

      expect(t.annotations!.length, equals(2));
      var first = t.annotations![0];
      expect(first.name, equals('Deprecated'));
      expect(first.parameters!['message']!.value, equals('use Bar'));
      expect(first.parameters!['message']!.defaultParameter, isTrue);
      expect(t.annotations![1].name, equals('Marker'));
      expect(t.annotations![1].parameters, isNull);
    });
  });

  group('nullability', () {
    test(
      'a nullable type is a distinct entry, and the singleton is untouched',
      () {
        var nullableInt = ASTTypeInt.instance.asNullable(true);
        var output = _roundTrip([ASTTypeInt.instance, nullableInt]);

        expect(identical(output[0], ASTTypeInt.instance), isTrue);
        expect(output[1].nullable, isTrue);
        expect(output[1], isA<ASTTypeInt>());
        expect(identical(output[1], ASTTypeInt.instance), isFalse);

        // The shared singleton must not have been mutated on the way through.
        expect(ASTTypeInt.instance.nullable, isFalse);
      },
    );

    test('nullable user type', () {
      var t = _one(ASTType('Foo').asNullable(true));
      expect(t.name, equals('Foo'));
      expect(t.nullable, isTrue);
    });

    test('nullable and non-nullable forms are not collapsed', () {
      var out = _roundTrip([ASTType('Foo'), ASTType('Foo').asNullable(true)]);
      expect(out[0].nullable, isFalse);
      expect(out[1].nullable, isTrue);
    });
  });

  group('pooling', () {
    test('equal types are interned once', () {
      var strings = ASTStringPoolWriter();
      var pool = ASTTypePoolWriter(strings);

      var a = pool.intern(ASTType('Foo'));
      var b = pool.intern(ASTType('Foo'));
      var c = pool.intern(ASTTypeInt.instance);
      var d = pool.intern(ASTTypeInt.instance);

      expect(a, equals(b));
      expect(c, equals(d));
      expect(pool.length, equals(2));
    });

    test('decoded uses of one type share an instance', () {
      var out = _roundTrip([ASTType('Foo'), ASTType('Foo')]);
      expect(identical(out[0], out[1]), isTrue);
    });

    test('components are always interned before the type that uses them', () {
      // Front-to-back decoding depends on every reference pointing backwards.
      var strings = ASTStringPoolWriter();
      var pool = ASTTypePoolWriter(strings);

      pool.intern(ASTTypeMap(ASTType('K'), ASTTypeArray(ASTType('V'))));

      // K, V, List<V>, Map<K, List<V>>
      expect(pool.length, equals(4));
    });

    test('deeply nested types round trip', () {
      var t = ASTTypeMap(
        ASTTypeString.instance,
        ASTTypeArray(ASTTypeMap(ASTType('A'), ASTTypeFuture(ASTType('B')))),
      );

      var out = _one(t) as ASTTypeMap;
      expect(identical(out.keyType, ASTTypeString.instance), isTrue);

      var inner = (out.valueType as ASTTypeArray).componentType as ASTTypeMap;
      expect(inner.keyType.name, equals('A'));
      expect((inner.valueType as ASTTypeFuture).futureValueType.name, 'B');
    });
  });
}
