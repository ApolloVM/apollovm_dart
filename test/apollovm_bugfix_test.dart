@TestOn('vm')
@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Loads a single Dart [source] and executes [className].[method] with the
/// given [args], returning the resolved native value and the collected
/// `print` output.
Future<({Object? value, List output})> _runDart(
  String source,
  String className,
  String method, {
  List args = const [],
}) async {
  var vm = ApolloVM();
  var loadOK = await vm.loadCodeUnit(
    SourceCodeUnit('dart', source, id: 'test'),
  );
  expect(loadOK, isTrue, reason: "Can't load Dart source!");

  var runner = vm.createRunner('dart')!;

  var output = [];
  runner.externalPrintFunction = (o) => output.add(o);

  // The entry methods are declared non-static, so provide a (field-less)
  // instance to run them — only `static` methods run without an instance.
  var astValue = await runner.executeClassMethod(
    '',
    className,
    method,
    positionalParameters: [args],
    classInstanceFields: const {},
  );

  return (value: astValue.getValueNoContext(), output: output);
}

void main() {
  // Regression tests for the loop `return` propagation bug: a `return`
  // statement inside a loop body used to be ignored because the loop created a
  // fresh `ASTRunStatus` and never checked it to break out of the iteration.
  group('Loop return propagation', () {
    test('return inside a for-loop', () async {
      var r = await _runDart(
        r'''
        class Foo {
          int findFirst(List<Object> args) {
            for (var i = 0; i < 10; i++) {
              if (i == 3) {
                return i;
              }
            }
            return -1;
          }
        }
      ''',
        'Foo',
        'findFirst',
      );

      expect(r.value, equals(3));
    });

    test('return inside a for-loop stops side effects', () async {
      var r = await _runDart(
        r'''
        class Foo {
          int run(List<Object> args) {
            for (var i = 0; i < 5; i++) {
              print(i);
              if (i == 2) {
                return i;
              }
            }
            return -1;
          }
        }
      ''',
        'Foo',
        'run',
      );

      expect(r.value, equals(2));
      // Must stop printing right after the return (0, 1, 2 only).
      expect(r.output, equals([0, 1, 2]));
    });

    test('return inside a while-loop', () async {
      var r = await _runDart(
        r'''
        class Foo {
          int firstOver(List<Object> args) {
            var i = 0;
            while (i < 100) {
              if (i > 4) {
                return i;
              }
              i = i + 1;
            }
            return -1;
          }
        }
      ''',
        'Foo',
        'firstOver',
      );

      expect(r.value, equals(5));
    });

    test('return inside a for-each loop stops side effects', () async {
      var r = await _runDart(
        r'''
        class Foo {
          int find(List<int> args) {
            for (var e in args) {
              print(e);
              if (e == 20) {
                return e;
              }
            }
            return -1;
          }
        }
      ''',
        'Foo',
        'find',
        args: [10, 20, 30, 40],
      );

      expect(r.value, equals(20));
      expect(r.output, equals([10, 20]));
    });

    test('loop without return still runs to completion', () async {
      var r = await _runDart(
        r'''
        class Foo {
          int sum(List<Object> args) {
            var total = 0;
            for (var i = 1; i <= 4; i++) {
              total = total + i;
            }
            return total;
          }
        }
      ''',
        'Foo',
        'sum',
      );

      expect(r.value, equals(10));
    });
  });

  // Regression tests for the `ASTType` equality operators, which previously
  // (mistakenly) checked `other is ASTTypeInt` for every primitive type,
  // making instances of e.g. `ASTTypeBool` never equal to each other.
  group('ASTType equality', () {
    test('same primitive types are equal', () {
      expect(ASTTypeBool() == ASTTypeBool.instance, isTrue);
      expect(ASTTypeString() == ASTTypeString.instance, isTrue);
      expect(ASTTypeObject() == ASTTypeObject.instance, isTrue);
      expect(ASTTypeInt() == ASTTypeInt.instance, isTrue);
      expect(ASTTypeDouble() == ASTTypeDouble.instance, isTrue);
      expect(ASTTypeNull() == ASTTypeNull.instance, isTrue);
      expect(ASTTypeVoid() == ASTTypeVoid.instance, isTrue);
      expect(ASTTypeVar() == ASTTypeVar(), isTrue);
    });

    test('different primitive types are not equal', () {
      // Compare through `ASTType` references so the equality check is between
      // statically-unrelated runtime types (the actual scenario being tested).
      bool typesEqual(ASTType a, ASTType b) => a == b;

      expect(typesEqual(ASTTypeBool.instance, ASTTypeInt.instance), isFalse);
      expect(typesEqual(ASTTypeString.instance, ASTTypeInt.instance), isFalse);
      expect(typesEqual(ASTTypeObject.instance, ASTTypeInt.instance), isFalse);
      expect(typesEqual(ASTTypeNull.instance, ASTTypeVoid.instance), isFalse);
      expect(typesEqual(ASTTypeDouble.instance, ASTTypeInt.instance), isFalse);
    });

    test('equal types share the same hashCode', () {
      expect(ASTTypeBool().hashCode, equals(ASTTypeBool.instance.hashCode));
      expect(ASTTypeString().hashCode, equals(ASTTypeString.instance.hashCode));
    });
  });

  // Regression test for `ASTTypeMap` building a map from a flat key/value
  // list: the loop used to read from the (empty) target map instead of the
  // input list, producing an empty map.
  group('ASTTypeMap.toValue from flat list', () {
    test('builds a map from alternating key/value entries (length > 2)', () {
      var context = VMScopeContext(ASTBlock(null));
      var astMap = ASTTypeMap.instanceOfStringOfDynamic.toValue(context, [
        'a',
        1,
        'b',
        2,
        'c',
        3,
      ]);

      expect(astMap, isA<ASTValue>());
      expect(
        (astMap as ASTValue).getValueNoContext(),
        equals({'a': 1, 'b': 2, 'c': 3}),
      );
    });

    test('builds a single-entry map from a length-2 list', () {
      var context = VMScopeContext(ASTBlock(null));
      var astMap = ASTTypeMap.instanceOfStringOfDynamic.toValue(context, [
        'x',
        10,
      ]);

      expect((astMap as ASTValue).getValueNoContext(), equals({'x': 10}));
    });
  });

  // Regression test for Java string escaping: backslashes were not escaped,
  // producing invalid Java string literals (e.g. `"a\b"` instead of `"a\\b"`).
  group('Java string escaping', () {
    test('escapes backslashes when translating Dart to Java', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(
        SourceCodeUnit('dart', r'''
          class Foo {
            void main(List<Object> args) {
              var p = 'a\\b';
              print(p);
            }
          }
        ''', id: 'test'),
      );

      var codeStorage = vm.generateAllCodeIn('java11');
      var java = (await codeStorage.writeAllSources()).toString();

      expect(java, contains(r'"a\\b"'));
      expect(java, isNot(contains(r'"a\b"')));
    });
  });

  group('apollovm_utils', () {
    test('toListOfType infers element type', () {
      expect(<dynamic>['a', 'b'].toListOfType() is List<String>, isTrue);
      expect(<dynamic>[1, 2, 3].toListOfType() is List<int>, isTrue);
      expect(<dynamic>[1.1, 2.2].toListOfType() is List<double>, isTrue);
      expect(<dynamic>[true, false].toListOfType() is List<bool>, isTrue);
    });

    test('fractionDigitsFromScientificNotation', () {
      expect((1e-7).fractionDigitsFromScientificNotation(), equals(7));
      expect((100.0).fractionDigitsFromScientificNotation(), equals(0));
      expect((1e21).fractionDigitsFromScientificNotation(), equals(0));
      expect((0.001).fractionDigitsFromScientificNotation(), equals(0));
    });

    test('lookupValue (case sensitive)', () {
      var map = {'Key': 1, 'other': 2};
      expect(map.lookupValue('Key'), equals(1));
      expect(map.lookupValue('key'), isNull);
      expect(map.lookupValue('missing'), isNull);
    });

    test('lookupValue (ignore case)', () {
      var map = {'Key': 1, 'other': 2};
      expect(map.lookupValue('key', ignoreCase: true), equals(1));
      expect(map.lookupValue('OTHER', ignoreCase: true), equals(2));
      expect(map.lookupValue('missing', ignoreCase: true), isNull);
    });
  });
}
