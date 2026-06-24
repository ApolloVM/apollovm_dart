@TestOn('vm')
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

const _dartSource = r'''
class Foo {
  int x = 10;

  int sum(int a, int b) {
    int r = a + b;
    return r;
  }

  int times(int a, int b) {
    return a * b;
  }
}
''';

const _dartTopLevel = r'''
int add(int a, int b) {
  return a + b;
}
''';

const _javaSource = r'''
class Foo {
  static int sum(int a, int b) {
    int r = a + b;
    return r;
  }

  static int mul(int a, int b) {
    int r = a * b;
    return r;
  }
}
''';

void main() {
  group('ApolloVM construction', () {
    test('default construction and id', () {
      var vm = ApolloVM();
      expect(vm.id, greaterThan(0));
      var vm2 = ApolloVM();
      expect(vm2.id, greaterThan(vm.id));
    });

    test('VERSION is defined', () {
      expect(ApolloVM.VERSION, isNotEmpty);
      expect(ApolloVM.VERSION, matches(RegExp(r'^\d+\.\d+\.\d+$')));
    });

    test('empty VM has no loaded languages', () {
      var vm = ApolloVM();
      expect(vm.loadedCodeLanguages, isEmpty);
    });

    test('toString includes id and loaded languages', () {
      var vm = ApolloVM();
      var s = vm.toString();
      expect(s, contains('ApolloVM'));
      expect(s, contains('loadedCodeLanguages'));
    });
  });

  group('getParser', () {
    test('returns parsers for known languages', () {
      var vm = ApolloVM();
      expect(vm.getParser('dart'), isNotNull);
      expect(vm.getParser('java'), isNotNull);
      expect(vm.getParser('java11'), isNotNull);
      expect(vm.getParser('wasm'), isNotNull);
    });

    test('returns null for unknown language', () {
      var vm = ApolloVM();
      expect(vm.getParser('cobol'), isNull);
    });
  });

  group('createRunner', () {
    test('creates dart and java runners', () {
      var vm = ApolloVM();
      var dartRunner = vm.createRunner('dart');
      expect(dartRunner, isNotNull);
      expect(dartRunner!.language, equals('dart'));

      var javaRunner = vm.createRunner('java11');
      expect(javaRunner, isNotNull);
      expect(javaRunner!.language, equals('java11'));
    });

    test('returns null for unknown language', () {
      var vm = ApolloVM();
      expect(vm.createRunner('cobol'), isNull);
    });

    test('runner toString includes language', () {
      var vm = ApolloVM();
      var runner = vm.createRunner('dart')!;
      expect(runner.toString(), contains('dart'));
    });
  });

  group('SourceCodeUnit', () {
    test('properties: language, id, code', () {
      var cu = SourceCodeUnit('dart', _dartSource, id: 'my_id');
      expect(cu.language, equals('dart'));
      expect(cu.id, equals('my_id'));
      expect(cu.code, equals(_dartSource));
    });

    test('default id is empty', () {
      var cu = SourceCodeUnit('dart', _dartSource);
      expect(cu.id, equals(''));
    });

    test('lines and getLine', () {
      var cu = SourceCodeUnit('dart', 'line1\nline2\nline3', id: 'x');
      expect(cu.lines.length, equals(3));
      expect(cu.getLine(1), equals('line1'));
      expect(cu.getLine(2), equals('line2'));
      expect(cu.getLine(0), isNull);
      expect(cu.getLine(99), isNull);
    });

    test('toString', () {
      var cu = SourceCodeUnit('dart', _dartSource, id: 'x');
      var s = cu.toString();
      expect(s, contains('SourceCodeUnit'));
      expect(s, contains('dart'));
    });

    test('root is null before loading', () {
      var cu = SourceCodeUnit('dart', _dartSource, id: 'x');
      expect(cu.root, isNull);
    });
  });

  group('loadCodeUnit', () {
    test('loads valid Dart source', () async {
      var vm = ApolloVM();
      var ok = await vm.loadCodeUnit(
        SourceCodeUnit('dart', _dartSource, id: 'test'),
      );
      expect(ok, isTrue);
      expect(vm.loadedCodeLanguages, contains('dart'));
    });

    test('loads valid Java source', () async {
      var vm = ApolloVM();
      var ok = await vm.loadCodeUnit(
        SourceCodeUnit('java11', _javaSource, id: 'test'),
      );
      expect(ok, isTrue);
      expect(vm.loadedCodeLanguages, contains('java11'));
    });

    test('loading sets the root on the code unit', () async {
      var vm = ApolloVM();
      var cu = SourceCodeUnit('dart', _dartSource, id: 'test');
      await vm.loadCodeUnit(cu);
      expect(cu.root, isNotNull);
      expect(cu.namespace, isNotNull);
    });

    test('loads multiple code units / languages', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(SourceCodeUnit('dart', _dartSource, id: 'a'));
      await vm.loadCodeUnit(SourceCodeUnit('dart', _dartTopLevel, id: 'b'));
      await vm.loadCodeUnit(SourceCodeUnit('java11', _javaSource, id: 'c'));
      expect(vm.loadedCodeLanguages, containsAll(['dart', 'java11']));
    });

    test(
      'no-parser language with explicit namespace loads as opaque unit',
      () async {
        // With no parser, the unit is stored as-is when a namespace is provided.
        var vm = ApolloVM();
        var ok = await vm.loadCodeUnit(
          SourceCodeUnit(
            'cobol',
            'IDENTIFICATION DIVISION.',
            id: 'x',
            namespace: 'pkg',
          ),
        );
        expect(ok, isTrue);
        expect(vm.loadedCodeLanguages, contains('cobol'));
      },
    );

    test('no-parser language without namespace throws StateError', () async {
      var vm = ApolloVM();
      expect(
        () => vm.loadCodeUnit(
          SourceCodeUnit('cobol', 'IDENTIFICATION DIVISION.', id: 'x'),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('throws SyntaxError on invalid Dart source', () async {
      var vm = ApolloVM();
      expect(
        () => vm.loadCodeUnit(
          SourceCodeUnit('dart', 'class { this is not valid !!! ', id: 'x'),
        ),
        throwsA(isA<SyntaxError>()),
      );
    });
  });

  group('namespaces and class lookup', () {
    test('getLanguageNamespaces and namespaces list', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(SourceCodeUnit('dart', _dartSource, id: 'test'));
      var langNs = vm.getLanguageNamespaces('dart');
      expect(langNs.language, equals('dart'));
      expect(langNs.namespaces, contains(''));
      expect(langNs.classesNames, contains('Foo'));
    });

    test('getNamespace returns CodeNamespace', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(SourceCodeUnit('dart', _dartSource, id: 'test'));
      var ns = vm.getNamespace('dart', '');
      expect(ns, isNotNull);
      expect(ns!.language, equals('dart'));
      expect(ns.classesNames, contains('Foo'));
      expect(ns.containsClass('Foo'), isTrue);
      expect(ns.containsClass('Bar'), isFalse);
    });

    test('getNamespaceWithName finds across languages', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(SourceCodeUnit('dart', _dartSource, id: 'a'));
      await vm.loadCodeUnit(SourceCodeUnit('java11', _javaSource, id: 'b'));
      var nss = vm.getNamespaceWithName('');
      expect(nss.length, equals(2));
    });

    test('getNamespaceWithNameAndClass filters by class', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(SourceCodeUnit('dart', _dartSource, id: 'a'));
      var withFoo = vm.getNamespaceWithNameAndClass('', 'Foo');
      expect(withFoo, isNotEmpty);
      var withBar = vm.getNamespaceWithNameAndClass('', 'Bar');
      expect(withBar, isEmpty);
    });

    test('getNamespaceWithClass with and without language', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(SourceCodeUnit('dart', _dartSource, id: 'a'));
      expect(vm.getNamespaceWithClass('Foo'), isNotEmpty);
      expect(vm.getNamespaceWithClass('Foo', language: 'dart'), isNotEmpty);
      expect(vm.getNamespaceWithClass('Foo', language: 'java11'), isEmpty);
      expect(vm.getNamespaceWithClass('Missing'), isEmpty);
    });

    test('CodeNamespace equality and hashCode', () {
      var a = CodeNamespace('dart', 'x');
      var b = CodeNamespace('dart', 'x');
      var c = CodeNamespace('dart', 'y');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('resolveType resolves loaded class', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(SourceCodeUnit('dart', _dartSource, id: 'a'));
      var type = await vm
          .resolveType('Foo', namespace: '', language: 'dart')
          .asFuture;
      expect(type, isNotNull);
      expect(type!.name, equals('Foo'));
    });
  });

  group('parseLanguageFromFilePathExtension', () {
    test('maps known extensions', () {
      expect(ApolloVM.parseLanguageFromFilePathExtension('a.dart'), 'dart');
      expect(ApolloVM.parseLanguageFromFilePathExtension('a.java'), 'java11');
      expect(ApolloVM.parseLanguageFromFilePathExtension('dart'), 'dart');
      expect(ApolloVM.parseLanguageFromFilePathExtension('java'), 'java11');
    });

    test('defaults to dart for unknown', () {
      expect(ApolloVM.parseLanguageFromFilePathExtension('a.xyz'), 'dart');
    });
  });

  group('execution: Dart', () {
    test('executeClassMethod returns computed value', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(SourceCodeUnit('dart', _dartSource, id: 'a'));
      var runner = vm.createRunner('dart')!;
      var r = await runner.executeClassMethod(
        '',
        'Foo',
        'sum',
        positionalParameters: [3, 4],
      );
      expect(r.getValueNoContext(), equals(7));
    });

    test('executeClassMethod times', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(SourceCodeUnit('dart', _dartSource, id: 'a'));
      var runner = vm.createRunner('dart')!;
      var r = await runner.executeClassMethod(
        '',
        'Foo',
        'times',
        positionalParameters: [6, 7],
      );
      expect(r.getValueNoContext(), equals(42));
    });

    test('executeFunction top-level', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(SourceCodeUnit('dart', _dartTopLevel, id: 'a'));
      var runner = vm.createRunner('dart')!;
      var r = await runner.executeFunction(
        '',
        'add',
        positionalParameters: [10, 5],
      );
      expect(r.getValueNoContext(), equals(15));
    });

    test('runner.getClass returns loaded class', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(SourceCodeUnit('dart', _dartSource, id: 'a'));
      var runner = vm.createRunner('dart')!;
      var clazz = await runner.getClass('Foo');
      expect(clazz, isNotNull);
      expect(clazz!.name, equals('Foo'));
      expect(await runner.getClass('Nope'), isNull);
    });

    test('runner.getClassMethod resolves method', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(SourceCodeUnit('dart', _dartSource, id: 'a'));
      var runner = vm.createRunner('dart')!;
      var method = await runner.getClassMethod('', 'Foo', 'sum', [1, 2]);
      expect(method, isNotNull);
    });

    test('externalPrintFunction can be overridden', () async {
      var vm = ApolloVM();
      const printSrc = r'''
class Foo {
  void hello() {
    print('hi');
  }
}
''';
      await vm.loadCodeUnit(SourceCodeUnit('dart', printSrc, id: 'a'));
      var runner = vm.createRunner('dart')!;
      var captured = [];
      runner.externalPrintFunction = (o) => captured.add(o);
      await runner.executeClassMethod('', 'Foo', 'hello');
      expect(captured, equals(['hi']));
    });
  });

  group('execution: Java', () {
    test('executeClassMethod static sum', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(SourceCodeUnit('java11', _javaSource, id: 'a'));
      var runner = vm.createRunner('java11')!;
      var r = await runner.executeClassMethod(
        '',
        'Foo',
        'sum',
        positionalParameters: [8, 9],
      );
      expect(r.getValueNoContext(), equals(17));
    });

    test('executeClassMethod static mul', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(SourceCodeUnit('java11', _javaSource, id: 'a'));
      var runner = vm.createRunner('java11')!;
      var r = await runner.executeClassMethod(
        '',
        'Foo',
        'mul',
        positionalParameters: [3, 5],
      );
      expect(r.getValueNoContext(), equals(15));
    });
  });

  group('code generation', () {
    test('generateAllCodeIn dart produces reloadable raw source', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(SourceCodeUnit('dart', _dartSource, id: 'test'));

      var codeStorage = vm.generateAllCodeIn('dart');
      var namespaces = await codeStorage.getNamespaces();
      expect(namespaces, contains(''));

      var ids = await codeStorage.getNamespaceCodeUnitsIDs('');
      expect(ids, contains('test'));

      var source = await codeStorage.getNamespaceCodeUnit('', 'test');
      expect(source, isNotNull);
      expect(source, contains('class Foo'));
      expect(source, contains('int sum(int a, int b)'));

      // Round-trip: reload generated source in a fresh VM.
      var vm2 = ApolloVM();
      var ok = await vm2.loadCodeUnit(
        SourceCodeUnit('dart', source!, id: 'test'),
      );
      expect(ok, isTrue);
      var runner = vm2.createRunner('dart')!;
      var r = await runner.executeClassMethod(
        '',
        'Foo',
        'sum',
        positionalParameters: [2, 3],
      );
      expect(r.getValueNoContext(), equals(5));
    });

    test('generateAllCodeIn java11 translates Dart -> Java', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(SourceCodeUnit('dart', _dartSource, id: 'test'));

      var codeStorage = vm.generateAllCodeIn('java11');
      var source = await codeStorage.getNamespaceCodeUnit('', 'test');
      expect(source, isNotNull);
      expect(source, contains('class Foo'));
      expect(source, contains('int sum(int a, int b)'));

      // Round-trip: reload generated Java and run it.
      var vm2 = ApolloVM();
      var ok = await vm2.loadCodeUnit(
        SourceCodeUnit('java11', source!, id: 'test'),
      );
      expect(ok, isTrue);
      var runner = vm2.createRunner('java11')!;
      var r = await runner.executeClassMethod(
        '',
        'Foo',
        'sum',
        positionalParameters: [4, 5],
      );
      expect(r.getValueNoContext(), equals(9));
    });

    test('generateAllCodeIn throws for unsupported language', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(SourceCodeUnit('dart', _dartSource, id: 'test'));
      expect(() => vm.generateAllCodeIn('cobol'), throwsA(isA<StateError>()));
    });

    test(
      'createCodeGenerator via generateAllCodeIn round-trips storage',
      () async {
        var vm = ApolloVM();
        await vm.loadCodeUnit(SourceCodeUnit('dart', _dartSource, id: 'test'));
        // Reuse the storage returned by generateAllCodeIn to confirm it is a
        // valid ApolloSourceCodeStorage and exposes the code-unit accessors.
        var storage = vm.generateAllCodeIn('dart');
        var entries = await storage.allEntries();
        expect(entries.keys, contains(''));
        expect(entries['']!.keys, contains('test'));
      },
    );
  });
}
