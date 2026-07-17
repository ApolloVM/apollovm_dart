@TestOn('vm')
@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:apollovm/src/core/apollovm_core_base.dart';
import 'package:test/test.dart';

/// Loads a single Dart [source] and runs [className].[method], returning the
/// resolved native return value and the collected `print` output.
Future<({Object? value, List output})> _runDart(
  String source,
  String className,
  String method, {
  List args = const [],
  bool importMath = false,
}) async {
  var vm = ApolloVM();
  var loadOK = await vm.loadCodeUnit(
    SourceCodeUnit('dart', source, id: 'test'),
  );
  expect(loadOK, isTrue, reason: "Can't load Dart source!");

  var runner = vm.createRunner('dart', importCorePackageMath: importMath)!;

  var output = [];
  runner.externalPrintFunction = (o) => output.add(o);

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
  final context = VMScopeContext(ASTBlock(null));
  final sig = ASTFunctionSignature(null, null);

  group('ApolloVMCore.getClass', () {
    test('resolves core classes by name', () {
      expect(
        identical(ApolloVMCore.getClass('String'), CoreClassString.instance),
        isTrue,
      );
      expect(
        identical(ApolloVMCore.getClass('int'), CoreClassInt.instance),
        isTrue,
      );
      expect(
        identical(ApolloVMCore.getClass('Integer'), CoreClassInt.instance),
        isTrue,
      );
      expect(
        identical(ApolloVMCore.getClass('double'), CoreClassDouble.instance),
        isTrue,
      );
      expect(
        identical(ApolloVMCore.getClass('Double'), CoreClassDouble.instance),
        isTrue,
      );
      expect(ApolloVMCore.getClass('Map'), same(CoreClassMap.instance));
    });

    test('resolves List class using the generic type', () {
      expect(
        identical(
          ApolloVMCore.getClass<List<int>>('List'),
          CoreClassList.instanceOfInt,
        ),
        isTrue,
      );
      expect(
        identical(
          ApolloVMCore.getClass<List<String>>('List'),
          CoreClassList.instanceOfString,
        ),
        isTrue,
      );
    });

    test('returns null for unknown class name', () {
      expect(ApolloVMCore.getClass('Foo'), isNull);
      expect(ApolloVMCore.getClass('Duration'), isNull);
    });
  });

  group('CorePackageMath', () {
    final math = CorePackageMath();

    test('package metadata', () {
      expect(math.packageName, equals('dart:math'));
      expect(math.path, equals('dart:math'));
    });

    test('exportedFunctions lists all 14 math functions', () {
      var names = math.exportedFunctions.map((f) => f.name).toList();
      expect(names, hasLength(14));
      expect(
        names,
        containsAll([
          'pow',
          'sqrt',
          'sin',
          'cos',
          'tan',
          'asin',
          'acos',
          'atan',
          'atan2',
          'log',
          'exp',
          'abs',
          'min',
          'max',
        ]),
      );
    });

    test('getFunction resolves each math function by name', () {
      for (var name in [
        'pow',
        'sqrt',
        'sin',
        'cos',
        'tan',
        'asin',
        'acos',
        'atan',
        'atan2',
        'log',
        'exp',
        'abs',
        'min',
        'max',
      ]) {
        var f = math.getFunction(name, sig, context);
        expect(f, isNotNull, reason: 'missing $name');
        expect(f!.name, equals(name));
      }
    });

    test('getFunction throws StateError for unknown function', () {
      expect(() => math.getFunction('unknown', sig, context), throwsStateError);
    });
  });

  group('CoreClassString getters/functions', () {
    final c = CoreClassString.instance;

    test('getGetter resolves length/isEmpty/isNotEmpty', () {
      expect(c.getGetter('length', context), isNotNull);
      expect(c.getGetter('isEmpty', context), isNotNull);
      expect(c.getGetter('isNotEmpty', context), isNotNull);
    });

    test('getGetter throws for unknown getter', () {
      expect(() => c.getGetter('nope', context), throwsStateError);
    });

    test('getFunction resolves all exposed String methods', () {
      for (var name in [
        'contains',
        'toUpperCase',
        'toLowerCase',
        'length',
        'isEmpty',
        'isNotEmpty',
        'substring',
        'indexOf',
        'startsWith',
        'endsWith',
        'trim',
        'split',
        'replaceAll',
        'replaceFirst',
        'trimLeft',
        'trimRight',
        'padLeft',
        'padRight',
        'lastIndexOf',
        'codeUnitAt',
        'valueOf',
        'toString',
      ]) {
        expect(c.getFunction(name, sig, context), isNotNull, reason: name);
      }
    });

    test('getFunction is case-insensitive when requested', () {
      // Case-insensitive lowercases the requested name, so only all-lowercase
      // case labels match (camelCase labels like `toUpperCase` won't).
      expect(
        c.getFunction('CONTAINS', sig, context, caseInsensitive: true),
        isNotNull,
      );
    });

    test('getFunction throws for unknown function', () {
      expect(() => c.getFunction('nope', sig, context), throwsStateError);
    });

    test('resolveValueToString handles null and ASTValue', () {
      expect(c.resolveValueToString(null, context), equals('null'));
      expect(
        c.resolveValueToString(ASTValueString('hi'), context),
        equals('hi'),
      );
      expect(c.resolveValueToString(ASTValueInt(42), context), equals('42'));
    });
  });

  group('CoreClassInt getters/functions', () {
    final c = CoreClassInt.instance;

    test('getGetter sign', () {
      expect(c.getGetter('sign', context), isNotNull);
      expect(() => c.getGetter('bad', context), throwsStateError);
    });

    test('getFunction resolves int methods', () {
      for (var name in [
        'parseInt',
        'parse',
        'tryParse',
        'valueOf',
        'compareTo',
        'abs',
        'sign',
        'clamp',
        'remainder',
        'toRadixString',
        'toDouble',
        'toString',
      ]) {
        expect(c.getFunction(name, sig, context), isNotNull, reason: name);
      }
    });

    test('getFunction throws for unknown', () {
      expect(() => c.getFunction('nope', sig, context), throwsStateError);
    });
  });

  group('CoreClassDouble getters/functions', () {
    final c = CoreClassDouble.instance;

    test('getGetter sign', () {
      expect(c.getGetter('sign', context), isNotNull);
      expect(() => c.getGetter('bad', context), throwsStateError);
    });

    test('getFunction resolves double methods', () {
      for (var name in [
        'parseDouble',
        'parse',
        'tryParse',
        'valueOf',
        'compareTo',
        'abs',
        'sign',
        'clamp',
        'remainder',
        'toStringAsFixed',
        'toStringAsExponential',
        'toStringAsPrecision',
        'toInt',
        'round',
        'floor',
        'ceil',
        'truncate',
        'toString',
      ]) {
        expect(c.getFunction(name, sig, context), isNotNull, reason: name);
      }
    });

    test('getFunction throws for unknown', () {
      expect(() => c.getFunction('nope', sig, context), throwsStateError);
    });
  });

  group('CoreClassList', () {
    test('fromType maps List<T> to shared instances', () {
      expect(
        identical(
          CoreClassList.fromType(List<String>),
          CoreClassList.instanceOfString,
        ),
        isTrue,
      );
      expect(
        identical(
          CoreClassList.fromType(List<int>),
          CoreClassList.instanceOfInt,
        ),
        isTrue,
      );
      expect(
        identical(
          CoreClassList.fromType(List<double>),
          CoreClassList.instanceOfDouble,
        ),
        isTrue,
      );
      expect(
        identical(
          CoreClassList.fromType(List<bool>),
          CoreClassList.instanceOfBool,
        ),
        isTrue,
      );
      expect(
        identical(
          CoreClassList.fromType(List<Object>),
          CoreClassList.instanceOfObject,
        ),
        isTrue,
      );
      expect(
        identical(
          CoreClassList.fromType(List<dynamic>),
          CoreClassList.instanceOfDynamic,
        ),
        isTrue,
      );
    });

    test('fromType returns null for non-List types', () {
      expect(CoreClassList.fromType(int), isNull);
      expect(CoreClassList.fromType(String), isNull);
    });

    test('getGetter resolves list properties', () {
      final c = CoreClassList.instanceOfObject;
      for (var name in ['length', 'isEmpty', 'isNotEmpty', 'first', 'last']) {
        expect(c.getGetter(name, context), isNotNull, reason: name);
      }
      expect(() => c.getGetter('bad', context), throwsStateError);
    });

    test('getFunction resolves list methods', () {
      final c = CoreClassList.instanceOfObject;
      for (var name in [
        'add',
        'addAll',
        'remove',
        'removeAt',
        'contains',
        'length',
        'isEmpty',
        'isNotEmpty',
        'clear',
        'indexOf',
        'insert',
        'first',
        'last',
        'sublist',
        'valueOf',
        'toString',
      ]) {
        expect(c.getFunction(name, sig, context), isNotNull, reason: name);
      }
      expect(() => c.getFunction('nope', sig, context), throwsStateError);
    });

    test('resolveValueToList handles null and values', () {
      final c = CoreClassList.instanceOfObject;
      expect(c.resolveValueToList(null, context), equals([]));
      expect(c.resolveValueToList(ASTValueString('x'), context), equals(['x']));
    });

    test('unsupported ASTClass surface throws UnimplementedError', () {
      final c = CoreClassList.instanceOfObject;
      expect(() => c.fields, throwsUnimplementedError);
      expect(() => c.fieldsNames, throwsUnimplementedError);
      expect(c.constructors, isEmpty);
      expect(c.constructorsNames, isEmpty);
      expect(c.getConstructor('', null, context), isNull);
    });
  });

  group('CoreClassMap', () {
    final c = CoreClassMap.instance;

    test('getGetter resolves map properties', () {
      for (var name in ['length', 'isEmpty', 'isNotEmpty', 'keys', 'values']) {
        expect(c.getGetter(name, context), isNotNull, reason: name);
      }
      expect(() => c.getGetter('bad', context), throwsStateError);
    });

    test('getFunction resolves map methods', () {
      for (var name in [
        'containsKey',
        'containsValue',
        'remove',
        'clear',
        'length',
        'isEmpty',
        'isNotEmpty',
        'toString',
      ]) {
        expect(c.getFunction(name, sig, context), isNotNull, reason: name);
      }
      expect(() => c.getFunction('nope', sig, context), throwsStateError);
    });

    test('unsupported ASTClass surface throws UnimplementedError', () {
      expect(() => c.fields, throwsUnimplementedError);
      expect(() => c.fieldsNames, throwsUnimplementedError);
      expect(c.constructors, isEmpty);
      expect(c.constructorsNames, isEmpty);
      expect(c.getConstructor('', null, context), isNull);
    });
  });

  group('Core functions executed via VM (native bodies)', () {
    test('dart:math functions', () async {
      var r = await _runDart(
        r'''
        import 'dart:math';
        class M {
          void main(List<Object> args) {
            print(sqrt(16));
            print(pow(2, 10));
            print(max(3, 9));
            print(min(3, 9));
            print(abs(-5));
            print(log(1));
            print(exp(0));
            print(atan2(0, 1));
          }
        }
        ''',
        'M',
        'main',
        importMath: true,
      );
      expect(r.output, equals([4.0, 1024, 9, 3, 5, 0.0, 1.0, 0.0]));
    });

    test('String instance methods', () async {
      var r = await _runDart(
        r'''
        class S {
          void main(List<Object> args) {
            var s = ' Hello World ';
            var cs = 'a,b,c';
            var h = 'hello';
            print(s.trim().toUpperCase());
            print(s.trim().toLowerCase());
            print(s.contains('World'));
            print(cs.split(','));
            print(h.substring(1, 3));
            print(h.replaceAll('l', 'L'));
            print(h.startsWith('he'));
            print(h.endsWith('lo'));
            print(h.indexOf('l'));
            print(h.length);
          }
        }
        ''',
        'S',
        'main',
      );
      expect(r.output[0], equals('HELLO WORLD'));
      expect(r.output[1], equals('hello world'));
      expect(r.output[2], isTrue);
      expect(r.output[3], equals(['a', 'b', 'c']));
      expect(r.output[4], equals('el'));
      expect(r.output[5], equals('heLLo'));
      expect(r.output[6], isTrue);
      expect(r.output[7], isTrue);
      expect(r.output[8], equals(2));
      expect(r.output[9], equals(5));
    });

    test('List instance methods', () async {
      var r = await _runDart(
        r'''
        class L {
          void main(List<Object> args) {
            var l = [1, 2, 3];
            l.add(4);
            print(l.length);
            print(l.contains(2));
            print(l.indexOf(3));
            print(l.first);
            print(l.last);
            print(l.isEmpty);
            print(l.sublist(1, 3));
          }
        }
        ''',
        'L',
        'main',
      );
      expect(r.output[0], equals(4));
      expect(r.output[1], isTrue);
      expect(r.output[2], equals(2));
      expect(r.output[3], equals(1));
      expect(r.output[4], equals(4));
      expect(r.output[5], isFalse);
      expect(r.output[6], equals([2, 3]));
    });

    test('int/double instance methods', () async {
      var r = await _runDart(
        r'''
        class N {
          void main(List<Object> args) {
            print((-7).abs());
            print((3).compareTo(5));
            print((10).toRadixString(16));
            print((3.14).round());
            print((3.14).floor());
            print((3.14).ceil());
            print((3.99).truncate());
            print((2.5).toInt());
            print((3.14159).toStringAsFixed(2));
          }
        }
        ''',
        'N',
        'main',
      );
      expect(r.output[0], equals(7));
      expect(r.output[1], equals(-1));
      expect(r.output[2], equals('a'));
      expect(r.output[3], equals(3));
      expect(r.output[4], equals(3));
      expect(r.output[5], equals(4));
      expect(r.output[6], equals(3));
      expect(r.output[7], equals(2));
      expect(r.output[8], equals('3.14'));
    });
  });

  group('ASTType extra coverage', () {
    test('ASTType.from resolves ASTValue and native values', () {
      expect(ASTType.from(ASTValueInt(3)), equals(ASTTypeInt.instance));
      expect(ASTType.from('str'), equals(ASTTypeString.instance));
      expect(ASTType.from(2.5), equals(ASTTypeDouble.instance));
      // `fromNativeValue` has no `bool` branch, so a raw bool falls through to
      // `dynamic`.
      expect(ASTType.from(true), equals(ASTTypeDynamic.instance));
    });

    test('ASTType base constructor with generics/superType', () {
      var g = ASTType(
        'Wrapper',
        generics: [ASTTypeInt.instance],
        superType: ASTTypeObject.instance,
      );
      expect(g.name, equals('Wrapper'));
      expect(g.hasGenerics, isTrue);
      expect(g.hasSuperType, isTrue);
      expect(g.toString(), equals('Wrapper<int>'));
    });

    test('acceptsType generic erasure', () {
      var raw = ASTType('Box');
      var typed = ASTType('Box', generics: [ASTTypeInt.instance]);
      expect(raw.acceptsType(typed), isTrue);
      expect(typed.acceptsType(raw), isTrue);
    });

    test('acceptsType with mismatched generic lengths is false', () {
      var a = ASTType('Box', generics: [ASTTypeInt.instance]);
      var b = ASTType(
        'Box',
        generics: [ASTTypeInt.instance, ASTTypeString.instance],
      );
      expect(a.acceptsType(b), isFalse);
    });

    test('ASTTypeInterface has no children', () {
      var i = ASTTypeInterface('MyInterface');
      expect(i.name, equals('MyInterface'));
      expect(i.children, isEmpty);
    });

    test('ASTTypeMap.acceptsType with dynamic wildcard', () {
      var typed = ASTTypeMap<ASTTypeString, ASTTypeInt, String, int>(
        ASTTypeString.instance,
        ASTTypeInt.instance,
      );
      expect(typed.acceptsType(ASTTypeMap.instanceOfDynamicOfDynamic), isTrue);
    });

    test('ASTTypeFunction.acceptsType accepts any function type', () {
      var f1 = ASTTypeFunction(ASTTypeInt.instance);
      var f2 = ASTTypeFunction(ASTTypeString.instance);
      expect(f1.acceptsType(f2), isTrue);
      expect(f1.acceptsType(ASTTypeInt.instance), isFalse);
    });

    test('ASTTypeFuture.futureValueType', () {
      var f = ASTTypeFuture<ASTTypeString, String>(ASTTypeString.instance);
      expect(f.futureValueType, equals(ASTTypeString.instance));
    });

    test('doubleToString scientific notation handling', () {
      expect(ASTTypeDouble.doubleToString(1e-7), contains('e'));
      expect(
        ASTTypeDouble.doubleToString(1e-7, allowScientificNotation: false),
        isNot(contains('e')),
      );
    });

    test('ASTTypeNum toASTValue produces int or double', () {
      expect(ASTTypeNum.instance.toASTValue(3)?.getValueNoContext(), equals(3));
      expect(
        ASTTypeNum.instance.toASTValue(2.5)?.getValueNoContext(),
        equals(2.5),
      );
      expect(ASTTypeNum.instance.toASTValue(null), isNull);
    });

    test('ASTTypeBool toValue from ASTValue and raw', () async {
      var v = await ASTTypeBool.instance.toValue(context, 'true');
      expect(v?.getValueNoContext(), isTrue);
      // `parseBool` treats unrecognized strings as `false` rather than null.
      var v2 = await ASTTypeBool.instance.toValue(context, 'notabool');
      expect(v2?.getValueNoContext(), isFalse);
    });

    test('ASTType.fromType returns null then array/map fallbacks', () {
      expect(ASTType.fromType(dynamic), equals(ASTTypeDynamic.instance));
      expect(
        ASTType.fromType(Map<String, dynamic>),
        equals(ASTTypeMap.instanceOfStringOfDynamic),
      );
    });
  });
}
