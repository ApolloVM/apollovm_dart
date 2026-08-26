@TestOn('vm')
@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Loads a single Dart [source] and runs [className].[method], returning the
/// resolved native return value and the collected `print` output.
Future<({Object? value, List output})> runDart(
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

/// Translates a loaded Dart [source] into [language] and returns the single
/// generated source unit (raw, loadable code — not the multi-source wrapper).
Future<String> translateDart(String source, String language) async {
  var vm = ApolloVM();
  await vm.loadCodeUnit(SourceCodeUnit('dart', source, id: 'test'));

  var codeStorage = vm.generateAllCodeIn(language);

  var buffer = StringBuffer();
  for (var ns in await codeStorage.getNamespaces()) {
    for (var id in await codeStorage.getNamespaceCodeUnitsIDs(ns)) {
      buffer.write(await codeStorage.getNamespaceCodeUnit(ns, id));
    }
  }
  return buffer.toString();
}

void main() {
  group('String methods', () {
    test('case, trim, substring, contains', () async {
      var r = await runDart(
        r'''
        class S {
          void main(List<Object> args) {
            var s = '  Hello World  ';
            var t = s.trim();
            print(t.toUpperCase());
            print(t.toLowerCase());
            print(t.substring(0, 5));
            print(t.contains('World'));
          }
        }
      ''',
        'S',
        'main',
      );

      expect(r.output, equals(['HELLO WORLD', 'hello world', 'Hello', true]));
    });

    test('split, replaceAll, startsWith, endsWith, indexOf', () async {
      var r = await runDart(
        r'''
        class S {
          void main(List<Object> args) {
            var s = 'a,b,c,b';
            print(s.split(','));
            print(s.replaceAll('b', 'X'));
            print(s.startsWith('a'));
            print(s.endsWith('b'));
            print(s.indexOf('b'));
          }
        }
      ''',
        'S',
        'main',
      );

      expect(r.output[0], equals(['a', 'b', 'c', 'b']));
      expect(r.output[1], equals('a,X,c,X'));
      expect(r.output[2], isTrue);
      expect(r.output[3], isTrue);
      expect(r.output[4], equals(2));
    });

    test('padLeft / padRight', () async {
      var r = await runDart(
        r'''
        class S {
          void main(List<Object> args) {
            var a = '5';
            print(a.padLeft(3, '0'));
            print(a.padRight(3, '-'));
          }
        }
      ''',
        'S',
        'main',
      );

      expect(r.output, equals(['005', '5--']));
    });
  });

  group('Number methods', () {
    test('int methods', () async {
      var r = await runDart(
        r'''
        class N {
          void main(List<Object> args) {
            var n = -7;
            var a = 10;
            var b = 20;
            print(n.abs());
            print(n.toDouble());
            print(a.compareTo(b));
          }
        }
      ''',
        'N',
        'main',
      );

      expect(r.output, equals([7, -7.0, -1]));
    });

    test('double methods', () async {
      var r = await runDart(
        r'''
        class N {
          void main(List<Object> args) {
            var d = 3.567;
            print(d.toStringAsFixed(2));
            print(d.round());
            print(d.floor());
            print(d.ceil());
            print(d.truncate());
          }
        }
      ''',
        'N',
        'main',
      );

      expect(r.output, equals(['3.57', 4, 3, 4, 3]));
    });

    test('int parse', () async {
      var r = await runDart(
        r'''
        class N {
          int main(List<Object> args) {
            return int.parse('123') + 1;
          }
        }
      ''',
        'N',
        'main',
      );

      expect(r.value, equals(124));
    });
  });

  group('Math functions', () {
    test('sqrt, pow, abs, max, min', () async {
      var r = await runDart(
        r'''
        import 'dart:math';
        class M {
          void main(List<Object> args) {
            print(sqrt(16));
            print(pow(2, 10));
            print(max(3, 9));
            print(min(3, 9));
          }
        }
      ''',
        'M',
        'main',
        importMath: true,
      );

      expect(r.output, equals([4.0, 1024, 9, 3]));
    });
  });

  group('Control flow', () {
    test('nested if / else-if / else', () async {
      var r = await runDart(
        r'''
        class C {
          String main(List<Object> args) {
            var n = args[0];
            if (n < 0) {
              return 'neg';
            } else if (n == 0) {
              return 'zero';
            } else {
              return 'pos';
            }
          }
        }
      ''',
        'C',
        'main',
        args: [5],
      );

      expect(r.value, equals('pos'));
    });

    test('recursion (factorial)', () async {
      var r = await runDart(
        r'''
        class C {
          int fact(List<Object> args) {
            var n = args[0];
            if (n <= 1) {
              return 1;
            }
            return n * fact([n - 1]);
          }
        }
      ''',
        'C',
        'fact',
        args: [5],
      );

      expect(r.value, equals(120));
    });

    test('while loop accumulation', () async {
      var r = await runDart(
        r'''
        class C {
          int sum(List<Object> args) {
            var i = 0;
            var total = 0;
            while (i < 5) {
              total = total + i;
              i = i + 1;
            }
            return total;
          }
        }
      ''',
        'C',
        'sum',
      );

      expect(r.value, equals(10));
    });
  });

  group('Collections', () {
    test('list operations', () async {
      var r = await runDart(
        r'''
        class L {
          void main(List<Object> args) {
            var list = <int>[1, 2, 3];
            list.add(4);
            print(list.length);
            print(list.first);
            print(list.last);
            print(list.isEmpty);
          }
        }
      ''',
        'L',
        'main',
      );

      expect(r.output, equals([4, 1, 4, false]));
    });
  });

  group('Named constructors', () {
    test('a named constructor is declared, called and translated', () async {
      const source = r'''
class Point {
  int x = 0;
  int y = 0;

  Point(this.x, this.y);
  Point.origin() { x = 0; y = 0; }
  Point.square(int n) { x = n; y = n; }

  int sum() { return x + y; }
}

class Main {
  int run(List args) {
    print(Point(1, 2).sum());
    print(Point.origin().sum());
    print(Point.square(4).sum());
    return 0;
  }
}
''';

      var r = await runDart(source, 'Main', 'run');
      expect(r.output, equals([3, 0, 8]));

      // The declaration and the call both survive regeneration.
      var dart = await translateDart(source, 'dart');
      expect(dart, contains('Point.origin() {'));
      expect(dart, contains('Point.square(int n) {'));
      expect(dart, contains('Point.origin().sum()'));
    });
  });

  group('Translation round-trip', () {
    const source = r'''
      class Calc {
        int sum(List<Object> args) {
          var a = args[0];
          var b = args[1];
          var total = 0;
          for (var i = a; i <= b; i++) {
            total = total + i;
          }
          return total;
        }
      }
    ''';

    test('runs in Dart', () async {
      var r = await runDart(source, 'Calc', 'sum', args: [1, 4]);
      expect(r.value, equals(10));
    });

    test('generates Java with expected structure', () async {
      var java = await translateDart(source, 'java11');
      expect(java, contains('class Calc'));
      expect(java, contains('for ('));
    });

    test('regenerated Dart still loads and runs', () async {
      var dart = await translateDart(source, 'dart');
      expect(dart, contains('class Calc'));

      var vm = ApolloVM();
      var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', dart, id: 'regen'));
      expect(ok, isTrue, reason: 'Regenerated Dart should load');

      var runner = vm.createRunner('dart')!;
      var astValue = await runner.executeClassMethod(
        '',
        'Calc',
        'sum',
        positionalParameters: [
          [1, 4],
        ],
        classInstanceFields: const {},
      );
      expect(astValue.getValueNoContext(), equals(10));
    });
  });
}
