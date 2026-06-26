@Tags(['dart', 'kotlin'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Loads [code], runs [className].[methodName], returns captured `print` output.
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
  // Entry methods are non-static, so run them against a (field-less) instance —
  // only `static` methods run without an instance.
  await runner.executeClassMethod(
    '',
    className,
    methodName,
    classInstanceFields: const {},
  );
  return out;
}

/// Re-generates [language] source from parsed [code] and returns it as text.
Future<String> _regenerate(String language, String code) async {
  var vm = ApolloVM();
  await vm.loadCodeUnit(SourceCodeUnit(language, code, id: 'test'));
  var codeStorage = vm.generateAllCodeIn(language);
  return (await codeStorage.writeAllSources()).toString();
}

void main() {
  group('Object field assignment (write)', () {
    test('Dart — the motivating example runs', () async {
      // `print(user)` with no `toString()` prints the default representation;
      // the point is the code runs (fields assigned through `user.field = …`).
      var out = await _runPrints(
        'dart',
        r'''
        class User {
          int id;
          String name;
        }
        class App {
          void main() {
            var user = new User();
            user.id = 123;
            user.name = "Joe";
            print(user);
          }
        }
      ''',
        'App',
        'main',
      );
      expect(out.single, contains('User{'));
    });

    test('Dart — field assignment persists and supports `+=`', () async {
      var out = await _runPrints(
        'dart',
        r'''
        class User {
          int id;
          String name;
          String toString() { return 'User(#$id, $name)'; }
        }
        class App {
          void main() {
            var user = new User();
            user.id = 123;
            user.name = "Joe";
            print(user);
            user.id += 7;
            print(user.id);
          }
        }
      ''',
        'App',
        'main',
      );
      expect(out, equals(['User(#123, Joe)', '130']));
    });

    test('Java — field assignment + read-back + `+=`', () async {
      var out = await _runPrints(
        'java11',
        r'''
        class User {
          int id;
          String name;
          String toString() { return "User(#" + id + ", " + name + ")"; }
        }
        class App {
          void main() {
            User user = new User();
            user.id = 123;
            user.name = "Joe";
            print(user);
            user.id += 7;
            print(user.id);
          }
        }
      ''',
        'App',
        'main',
      );
      expect(out, equals(['User(#123, Joe)', '130']));
    });

    test('Kotlin — field assignment + read', () async {
      var out = await _runPrints(
        'kotlin',
        r'''
        class User { var id: Int = 0 }
        class App { fun main() { var u = User(); u.id = 5; u.id += 6; print(u.id); } }
      ''',
        'App',
        'main',
      );
      expect(out, equals(['11']));
    });
  });

  group('Object field access (read)', () {
    test('Dart — read obj.field and this.field', () async {
      var out = await _runPrints(
        'dart',
        r'''
        class User {
          int id = 9;
          String name = "bob";
          int self() { return this.id; }
        }
        class App {
          void main() {
            var u = new User();
            print(u.id);
            print(u.name);
            print(u.self());
          }
        }
      ''',
        'App',
        'main',
      );
      expect(out, equals(['9', 'bob', '9']));
    });

    test('Java — read obj.field and this.field', () async {
      var out = await _runPrints(
        'java11',
        r'''
        class User {
          int id = 9;
          String name = "bob";
          int self() { return this.id; }
        }
        class App {
          void main() {
            User u = new User();
            print(u.id);
            print(u.name);
            print(u.self());
          }
        }
      ''',
        'App',
        'main',
      );
      expect(out, equals(['9', 'bob', '9']));
    });

    test('Kotlin — read obj.field', () async {
      var out = await _runPrints(
        'kotlin',
        r'''
        class User { var id: Int = 9 }
        class App { fun main() { var u = User(); print(u.id); } }
      ''',
        'App',
        'main',
      );
      expect(out, equals(['9']));
    });
  });

  group('Source generation round-trip', () {
    test('Dart emits obj.field assignment', () async {
      var src = await _regenerate('dart', r'''
        class User { int id; }
        class App { void main() { var u = new User(); u.id = 1; u.id += 2; print(u.id); } }
      ''');
      expect(src, contains('u.id = 1;'));
      expect(src, contains('u.id += 2;'));
    });

    test('Java emits obj.field assignment', () async {
      var src = await _regenerate('java11', r'''
        class User { int id; }
        class App { void main() { User u = new User(); u.id = 1; u.id += 2; print(u.id); } }
      ''');
      expect(src, contains('u.id = 1;'));
      expect(src, contains('u.id += 2;'));
    });
  });

  group('Constructors that set fields', () {
    test('Dart — `this.` parameters', () async {
      var out = await _runPrints(
        'dart',
        r'''
        class User {
          int id;
          String name;
          User(this.id, this.name);
          String toString() { return 'U#$id<$name>'; }
        }
        class App { void main() { print(new User(123, "Joe")); } }
      ''',
        'App',
        'main',
      );
      expect(out, equals(['U#123<Joe>']));
    });

    test('Dart — `this.` parameters from a top-level main', () async {
      var vm = ApolloVM();
      var ok = await vm.loadCodeUnit(
        SourceCodeUnit('dart', r'''
        class User {
          int id;
          String name;

          User(this.id, this.name);

          String toString() {
            return 'User#$id<$name>';
          }
        }

        void main() {
          var user = new User(123, 'Joe');
          print(user);
        }
      ''', id: 'test'),
      );
      expect(ok, isTrue);
      var runner = vm.createRunner('dart')!;
      var out = <String>[];
      runner.externalPrintFunction = (o) => out.add('$o');
      await runner.executeFunction('', 'main');
      expect(out, equals(['User#123<Joe>']));
    });

    test('Dart — arrow (expression-bodied) methods', () async {
      var vm = ApolloVM();
      var ok = await vm.loadCodeUnit(
        SourceCodeUnit('dart', r'''
        class User {
          int id;
          String name;

          User(this.id, this.name);

          String toString() => 'User#$id<$name>';
        }

        int triple(int a) => a * 3;

        void main() {
          var user = new User(123, 'Joe');
          print(user);
          print(triple(4));
        }
      ''', id: 'test'),
      );
      expect(ok, isTrue);
      var runner = vm.createRunner('dart')!;
      var out = <String>[];
      runner.externalPrintFunction = (o) => out.add('$o');
      await runner.executeFunction('', 'main');
      expect(out, equals(['User#123<Joe>', '12']));
    });

    test('Dart — constructor body assigns fields', () async {
      var out = await _runPrints(
        'dart',
        r'''
        class User {
          int id;
          String name;
          User(int i, String n) { this.id = i; this.name = n; }
          String toString() { return 'U#$id<$name>'; }
        }
        class App { void main() { print(new User(123, "Joe")); } }
      ''',
        'App',
        'main',
      );
      expect(out, equals(['U#123<Joe>']));
    });

    test('Dart — empty-param constructor with body', () async {
      var out = await _runPrints(
        'dart',
        r'''
        class User { int id; String toString() { return 'id=$id'; } User() { this.id = 99; } }
        class App { void main() { print(new User()); } }
      ''',
        'App',
        'main',
      );
      expect(out, equals(['id=99']));
    });

    test('Java — constructor body with param/field shadowing', () async {
      var out = await _runPrints(
        'java11',
        r'''
        class User {
          int id;
          String name;
          User(int id, String name) { this.id = id; this.name = name; }
          String toString() { return "U#" + id + "<" + name + ">"; }
        }
        class App { void main() { print(new User(123, "Joe")); } }
      ''',
        'App',
        'main',
      );
      expect(out, equals(['U#123<Joe>']));
    });

    test('Java — empty-param constructor with body', () async {
      var out = await _runPrints(
        'java11',
        r'''
        class User { int id; String toString() { return "id=" + id; } User() { this.id = 99; } }
        class App { void main() { print(new User()); } }
      ''',
        'App',
        'main',
      );
      expect(out, equals(['id=99']));
    });
  });
}
