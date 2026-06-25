library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Loads [code], runs [className].[methodName] and returns the captured `print`
/// output (as text).
Future<List<String>> _runPrints(
  String language,
  String code,
  String className,
  String methodName,
) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit(language, code, id: 'test'));
  expect(ok, isTrue, reason: 'Failed to load $language source');

  var runner = vm.createRunner(language)!;
  var out = <String>[];
  runner.externalPrintFunction = (o) => out.add('$o');
  await runner.executeClassMethod('', className, methodName);
  return out;
}

void main() {
  group('Dart: instantiation + toString()', () {
    test('new User() — default constructor + user toString()', () async {
      var out = await _runPrints('dart', r'''
        class User {
          int id;
          String name;
          String toString() { return '#$id<$name>'; }
        }
        class Main {
          void run() {
            var user = new User();
            print(user);
          }
        }
      ''', 'Main', 'run');
      expect(out, equals(['#null<null>']));
    });

    test('User() without `new`', () async {
      var out = await _runPrints('dart', r'''
        class User {
          int id = 7;
          String name = "bob";
          String toString() { return '#$id<$name>'; }
        }
        class Main {
          void run() { print(User()); }
        }
      ''', 'Main', 'run');
      expect(out, equals(['#7<bob>']));
    });

    test('class without toString() prints the default representation', () async {
      var out = await _runPrints('dart', r'''
        class User { int id = 7; }
        class Main { void run() { print(new User()); } }
      ''', 'Main', 'run');
      expect(out.single, contains('User{'));
    });

    test('`new`-prefixed identifiers stay identifiers', () async {
      var out = await _runPrints('dart', r'''
        class Main {
          void run() {
            var newValue = 5;
            print(newValue);
          }
        }
      ''', 'Main', 'run');
      expect(out, equals(['5']));
    });

    test('declared constructor still works with `new`', () async {
      var out = await _runPrints('dart', r'''
        class Point {
          int x;
          int y;
          Point(this.x, this.y);
          String toString() { return '($x,$y)'; }
        }
        class Main {
          void run() { print(new Point(3, 4)); }
        }
      ''', 'Main', 'run');
      expect(out, equals(['(3,4)']));
    });

    test('instantiate from a top-level function', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(SourceCodeUnit('dart', r'''
        class User { int id = 9; String toString() { return 'U$id'; } }
        void run() { print(new User()); }
      ''', id: 'test'));
      var runner = vm.createRunner('dart')!;
      var out = <String>[];
      runner.externalPrintFunction = (o) => out.add('$o');
      await runner.executeFunction('', 'run');
      expect(out, equals(['U9']));
    });
  });

  group('Java: instantiation + toString()', () {
    test('new User() — default constructor + user toString()', () async {
      var out = await _runPrints('java11', r'''
        class User {
          int id = 7;
          String name = "bob";
          String toString() { return "#" + id + "<" + name + ">"; }
        }
        class Main {
          void run() {
            User user = new User();
            print(user);
          }
        }
      ''', 'Main', 'run');
      expect(out, equals(['#7<bob>']));
    });

    test('`new`-prefixed identifiers stay identifiers', () async {
      var out = await _runPrints('java11', r'''
        class Main {
          void run() {
            int newValue = 5;
            print(newValue);
          }
        }
      ''', 'Main', 'run');
      expect(out, equals(['5']));
    });
  });
}
