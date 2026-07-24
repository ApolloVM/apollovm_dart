@TestOn('vm')
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

void main() {
  group('ASTType nullability', () {
    test('asNullable returns a distinct, non-singleton nullable instance', () {
      var base = ASTTypeInt.instance;
      var nullable = base.asNullable();

      expect(base.nullable, isFalse);
      expect(nullable.nullable, isTrue);
      expect(identical(base, nullable), isFalse);
      // The shared singleton is never mutated.
      expect(ASTTypeInt.instance.nullable, isFalse);
    });

    test('asNullable preserves the concrete type', () {
      expect(ASTTypeString.instance.asNullable(), isA<ASTTypeString>());
      expect(ASTTypeInt.instance.asNullable(), isA<ASTTypeInt>());
      var arr = ASTTypeArray(ASTTypeString.instance).asNullable();
      expect(arr, isA<ASTTypeArray>());
      expect(arr.nullable, isTrue);
    });

    test('withoutNullability round-trips', () {
      var n = ASTTypeString.instance.asNullable();
      expect(n.nullable, isTrue);
      expect(n.withoutNullability().nullable, isFalse);
      // Non-nullable withoutNullability returns itself.
      expect(
        identical(
          ASTTypeInt.instance.withoutNullability(),
          ASTTypeInt.instance,
        ),
        isTrue,
      );
    });

    test('equality distinguishes nullable from non-nullable', () {
      expect(
        ASTTypeString.instance.asNullable() == ASTTypeString.instance,
        isFalse,
      );
      expect(
        ASTTypeString.instance.asNullable() ==
            ASTTypeString.instance.asNullable(),
        isTrue,
      );
    });

    group('acceptsAssignment', () {
      test('T? accepts T, T? and Null', () {
        var nullableInt = ASTTypeInt.instance.asNullable();
        expect(nullableInt.acceptsAssignment(ASTTypeInt.instance), isTrue);
        expect(nullableInt.acceptsAssignment(nullableInt), isTrue);
        expect(nullableInt.acceptsAssignment(ASTTypeNull.instance), isTrue);
      });

      test('T (non-nullable) rejects Null', () {
        expect(
          ASTTypeInt.instance.acceptsAssignment(ASTTypeNull.instance),
          isFalse,
        );
      });
    });
  });
}
