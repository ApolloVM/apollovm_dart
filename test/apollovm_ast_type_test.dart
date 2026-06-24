@TestOn('vm')
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

void main() {
  group('ASTType.fromType', () {
    test('maps Dart types to AST types', () {
      expect(ASTType.fromType(int), equals(ASTTypeInt.instance));
      expect(ASTType.fromType(double), equals(ASTTypeDouble.instance));
      expect(ASTType.fromType(bool), equals(ASTTypeBool.instance));
      expect(ASTType.fromType(String), equals(ASTTypeString.instance));
      expect(ASTType.fromType(Object), equals(ASTTypeObject.instance));
    });

    test('returns null for unknown type', () {
      expect(ASTType.fromType(Duration), isNull);
    });
  });

  group('ASTType.fromNativeValue', () {
    test('infers type from a native value', () {
      expect(ASTType.fromNativeValue(5), equals(ASTTypeInt.instance));
      expect(ASTType.fromNativeValue(2.5), equals(ASTTypeDouble.instance));
      expect(ASTType.fromNativeValue('x'), equals(ASTTypeString.instance));
      expect(ASTType.fromNativeValue(null), equals(ASTTypeNull.instance));
    });

    test('infers array types', () {
      expect(ASTType.fromNativeValue(<String>['a']).name, equals('List'));
      expect(ASTType.fromNativeValue(<int>[1, 2]).name, equals('List'));
    });
  });

  group('toString', () {
    test('primitive type names', () {
      expect(ASTTypeInt.instance.toString(), equals('int'));
      expect(ASTTypeInt(bits: 32).toString(), equals('int(32)'));
      expect(ASTTypeDouble.instance.toString(), equals('double'));
      expect(ASTTypeDouble(bits: 64).toString(), equals('double(64)'));
      expect(ASTTypeNum.instance.toString(), equals('num'));
      expect(ASTTypeBool.instance.toString(), equals('bool'));
      expect(ASTTypeString.instance.toString(), equals('String'));
      expect(ASTTypeObject.instance.toString(), equals('Object'));
      expect(ASTTypeDynamic.instance.toString(), equals('dynamic'));
    });
  });

  group('acceptsType', () {
    test('int only accepts int', () {
      expect(ASTTypeInt.instance.acceptsType(ASTTypeInt.instance), isTrue);
      expect(ASTTypeInt.instance.acceptsType(ASTTypeDouble.instance), isFalse);
    });

    test('num accepts int and double', () {
      expect(ASTTypeNum.instance.acceptsType(ASTTypeInt.instance), isTrue);
      expect(ASTTypeNum.instance.acceptsType(ASTTypeDouble.instance), isTrue);
      expect(ASTTypeNum.instance.acceptsType(ASTTypeString.instance), isFalse);
    });

    test('Object and dynamic accept any type', () {
      expect(ASTTypeObject.instance.acceptsType(ASTTypeInt.instance), isTrue);
      expect(
        ASTTypeDynamic.instance.acceptsType(ASTTypeString.instance),
        isTrue,
      );
    });
  });

  group('toASTValue', () {
    test('int conversion', () {
      expect(
        ASTTypeInt.instance.toASTValue(42)?.getValueNoContext(),
        equals(42),
      );
      expect(
        ASTTypeInt.instance.toASTValue('7')?.getValueNoContext(),
        equals(7),
      );
      expect(ASTTypeInt.instance.toASTValue(null), isNull);
    });

    test('double conversion', () {
      expect(
        ASTTypeDouble.instance.toASTValue(1.5)?.getValueNoContext(),
        equals(1.5),
      );
    });

    test('bool conversion', () {
      expect(
        ASTTypeBool.instance.toASTValue('true')?.getValueNoContext(),
        isTrue,
      );
      expect(ASTTypeBool.instance.toASTValue(null), isNull);
    });

    test('string conversion', () {
      expect(
        ASTTypeString.instance.toASTValue(123)?.getValueNoContext(),
        equals('123'),
      );
    });
  });

  group('toDefaultValue', () {
    final context = VMScopeContext(ASTBlock(null));

    test('default values per type', () async {
      // Call through `ASTType` to use the base `FutureOr<ASTValue?>` signature.
      ASTType intType = ASTTypeInt.instance;
      expect(
        (await intType.toDefaultValue(context))?.getValueNoContext(),
        equals(0),
      );
      expect(
        (await ASTTypeDouble.instance.toDefaultValue(
          context,
        ))?.getValueNoContext(),
        equals(0.0),
      );
      expect(
        (await ASTTypeBool.instance.toDefaultValue(
          context,
        ))?.getValueNoContext(),
        isFalse,
      );
    });
  });

  group('ASTTypeInt.equals with bits', () {
    test('bit-width sensitivity', () {
      expect(ASTTypeInt.instance == ASTTypeInt.instance, isTrue);
      expect(ASTTypeInt.instance32.equals(ASTTypeInt.instance64), isFalse);
      // Unspecified bits are compatible unless strict.
      expect(ASTTypeInt.instance.equals(ASTTypeInt.instance32), isTrue);
      expect(
        ASTTypeInt.instance.equals(ASTTypeInt.instance32, strict: true),
        isFalse,
      );
    });
  });

  group('toValue conversions', () {
    final context = VMScopeContext(ASTBlock(null));

    test('int from double truncates', () async {
      var v = await ASTTypeInt.instance.toValue(context, ASTValueDouble(3.9));
      expect(v?.getValueNoContext(), equals(3));
    });

    test('int from raw string', () async {
      var v = await ASTTypeInt.instance.toValue(context, '15');
      expect(v?.getValueNoContext(), equals(15));
    });
  });
}
