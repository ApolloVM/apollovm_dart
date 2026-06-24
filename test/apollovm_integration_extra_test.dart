@TestOn('vm')
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Loads a single Dart [source] and runs [className].[method], returning the
/// resolved native return value and the collected `print` output.
///
/// The call arguments [args] are passed as a single positional [List]
/// (matching the VM's `executeClassMethod` convention), so inside the Dart
/// code they are read as `args[0]`, `args[1]`, etc.
Future<({Object? value, List output})> runDart(
  String source,
  String className,
  String method, {
  List args = const [],
}) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', source, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source!");

  var runner = vm.createRunner('dart')!;
  var output = [];
  runner.externalPrintFunction = (o) => output.add(o);

  var astValue = await runner.executeClassMethod(
    '',
    className,
    method,
    positionalParameters: [args],
  );
  return (value: astValue.getValueNoContext(), output: output);
}

/// Translates a loaded Dart [source] into [language], returning the raw,
/// reloadable generated source (concatenation of all generated code units).
Future<String> translateDart(String source, String language) async {
  var vm = ApolloVM();
  await vm.loadCodeUnit(SourceCodeUnit('dart', source, id: 'test'));

  var cs = vm.generateAllCodeIn(language);
  var buf = StringBuffer();
  for (var ns in await cs.getNamespaces()) {
    for (var id in await cs.getNamespaceCodeUnitsIDs(ns)) {
      buf.write(await cs.getNamespaceCodeUnit(ns, id));
    }
  }
  return buf.toString();
}

void main() {
  group('Classes with fields and methods', () {
    test('method reads instance fields and derives a value', () async {
      var r = await runDart(
        r'''
        class Box {
          int width = 4;
          int height = 5;
          int area() { return width * height; }
          int run(List a) { return area() + width; }
        }
      ''',
        'Box',
        'run',
      );

      expect(r.value, equals(24));
    });

    test('field-derived describe() combining several methods', () async {
      var r = await runDart(
        r'''
        class Rect {
          int width = 6;
          int height = 7;
          int area() { return width * height; }
          int perimeter() { return 2 * (width + height); }
          String describe() {
            var a = area();
            var p = perimeter();
            return 'area=$a perim=$p';
          }
        }
      ''',
        'Rect',
        'describe',
      );

      expect(r.value, equals('area=42 perim=26'));
    });

    test('field with default initial value read inside method', () async {
      var r = await runDart(
        r'''
        class Account {
          int balance = 100;
          int withdraw(List a) {
            var amount = a[0];
            return balance - amount;
          }
        }
      ''',
        'Account',
        'withdraw',
        args: [30],
      );

      expect(r.value, equals(70));
    });

    test('method calling another method on same instance', () async {
      var r = await runDart(
        r'''
        class Calc {
          int base = 10;
          int doubled() { return base * 2; }
          int tripled() { return base * 3; }
          int run(List a) { return doubled() + tripled(); }
        }
      ''',
        'Calc',
        'run',
      );

      expect(r.value, equals(50));
    });
  });

  group('Multiple classes and static methods', () {
    test('static method calling another static method', () async {
      var r = await runDart(
        r'''
        class Util {
          static int dbl(int n) { return n * 2; }
          static int quad(int n) { return dbl(dbl(n)); }
        }
        class M { int run(List a) { return Util.quad(3); } }
      ''',
        'M',
        'run',
      );

      expect(r.value, equals(12));
    });

    test('static method of one class calling static of another', () async {
      var r = await runDart(
        r'''
        class A { static int twice(int n) { return n * 2; } }
        class B { static int compute(int n) { return A.twice(n) + 1; } }
        class M { int run(List a) { return B.compute(10); } }
      ''',
        'M',
        'run',
      );

      expect(r.value, equals(21));
    });
  });

  group('String interpolation', () {
    test('multiple variables and an embedded expression', () async {
      var r = await runDart(
        r'''
        class M {
          String run(List a) {
            var name = 'Bob';
            var age = 30;
            return 'Name: $name, Age: $age, Next: ${age + 1}';
          }
        }
      ''',
        'M',
        'run',
      );

      expect(r.value, equals('Name: Bob, Age: 30, Next: 31'));
    });

    test('interpolation with arithmetic of two variables', () async {
      var r = await runDart(
        r'''
        class M {
          String run(List a) {
            var x = 3;
            var y = 4;
            return 'sum: ${x + y}';
          }
        }
      ''',
        'M',
        'run',
      );

      expect(r.value, equals('sum: 7'));
    });
  });

  group('Boolean and logical operators', () {
    test('&&, ||, ! combined', () async {
      var r = await runDart(
        r'''
        class M {
          bool run(List a) {
            var x = true;
            var y = false;
            return (x && !y) || y;
          }
        }
      ''',
        'M',
        'run',
      );

      expect(r.value, isTrue);
    });

    test('logical conditions selecting a branch', () async {
      var r = await runDart(
        r'''
        class M {
          String run(List a) {
            var age = a[0];
            var member = a[1];
            if (age >= 18 && member) { return 'full'; }
            if (age >= 18 || member) { return 'partial'; }
            return 'none';
          }
        }
      ''',
        'M',
        'run',
        args: [16, true],
      );

      expect(r.value, equals('partial'));
    });
  });

  group('If/else returning values (ternary-like)', () {
    test('classify number sign via if/else chain', () async {
      var r = await runDart(
        r'''
        class M {
          String run(List a) {
            var n = a[0];
            if (n < 0) { return 'neg'; }
            else if (n == 0) { return 'zero'; }
            else { return 'pos'; }
          }
        }
      ''',
        'M',
        'run',
        args: [0],
      );

      expect(r.value, equals('zero'));
    });

    test('pick larger of two values', () async {
      var r = await runDart(
        r'''
        class M {
          int run(List a) {
            var x = a[0];
            var y = a[1];
            if (x > y) { return x; }
            return y;
          }
        }
      ''',
        'M',
        'run',
        args: [7, 12],
      );

      expect(r.value, equals(12));
    });
  });

  group('Lists', () {
    test('typed list indexing and add/length', () async {
      var r = await runDart(
        r'''
        class M {
          void run(List a) {
            var l = <int>[10, 20, 30];
            l.add(40);
            print(l[0]);
            print(l[3]);
            print(l.length);
            print(l.first);
            print(l.last);
          }
        }
      ''',
        'M',
        'run',
      );

      expect(r.output, equals([10, 40, 4, 10, 40]));
    });

    test('index loop summing a list', () async {
      var r = await runDart(
        r'''
        class M {
          int run(List a) {
            var l = <int>[5, 10, 15, 20];
            var total = 0;
            for (var i = 0; i < 4; i++) { total = total + l[i]; }
            return total;
          }
        }
      ''',
        'M',
        'run',
      );

      expect(r.value, equals(50));
    });

    test('for-in over typed list', () async {
      var r = await runDart(
        r'''
        class M {
          int run(List a) {
            var l = <int>[1, 2, 3, 4];
            var total = 0;
            for (var x in l) { total = total + x; }
            return total;
          }
        }
      ''',
        'M',
        'run',
      );

      expect(r.value, equals(10));
    });

    test('for-in over string list concatenating', () async {
      var r = await runDart(
        r'''
        class M {
          String run(List a) {
            var l = <String>['a', 'b', 'c'];
            var s = '';
            for (var x in l) { s = s + x; }
            return s;
          }
        }
      ''',
        'M',
        'run',
      );

      expect(r.value, equals('abc'));
    });

    test('for-in over a list held by a dynamic variable', () async {
      // Regression: the iterable resolved to a plain `ASTValueStatic` (not an
      // `ASTValueArray`) when bound to a `dynamic`/`Object` variable, which
      // for-each previously rejected.
      var r = await runDart(
        r'''
        class M {
          int run(List a) {
            dynamic l = <int>[1, 2, 3, 4];
            var total = 0;
            for (var x in l) { total = total + x; }
            return total;
          }
        }
      ''',
        'M',
        'run',
      );

      expect(r.value, equals(10));
    });
  });

  group('Dynamic-typed arithmetic', () {
    // Regression: operators dispatch on the operand's static `ASTValue.type`,
    // so two `dynamic` operands (e.g. untyped parameters) reached the operator
    // methods as `dynamic <op> dynamic` and threw, even though the runtime
    // values were concrete numbers/strings.

    Future<ASTValue> callDynamic(String method, List params) async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(
        SourceCodeUnit('dart', r'''
        class M {
          dynamic add(dynamic a, dynamic b) { return a + b; }
          dynamic sub(dynamic a, dynamic b) { return a - b; }
          dynamic mul(dynamic a, dynamic b) { return a * b; }
          dynamic div(dynamic a, dynamic b) { return a / b; }
          dynamic gt(dynamic a, dynamic b) { return a > b; }
          dynamic eq(dynamic a, dynamic b) { return a == b; }
        }
      ''', id: 'test'),
      );
      var runner = vm.createRunner('dart')!;
      return runner.executeClassMethod(
        '',
        'M',
        method,
        positionalParameters: params,
      );
    }

    test('+ - * on two dynamic int parameters', () async {
      expect((await callDynamic('add', [10, 32])).getValueNoContext(), 42);
      expect((await callDynamic('sub', [10, 3])).getValueNoContext(), 7);
      expect((await callDynamic('mul', [6, 7])).getValueNoContext(), 42);
    });

    test('mixed int/double dynamic operands', () async {
      expect((await callDynamic('add', [10, 2.5])).getValueNoContext(), 12.5);
      expect((await callDynamic('div', [7, 2])).getValueNoContext(), 3.5);
    });

    test('comparison on dynamic operands', () async {
      expect((await callDynamic('gt', [10, 3])).getValueNoContext(), isTrue);
      expect((await callDynamic('eq', [5, 5])).getValueNoContext(), isTrue);
      expect((await callDynamic('eq', [5, 6])).getValueNoContext(), isFalse);
    });

    test('string concatenation on dynamic operands', () async {
      expect(
        (await callDynamic('add', ['foo', 'bar'])).getValueNoContext(),
        equals('foobar'),
      );
    });
  });

  group('Arithmetic and precedence', () {
    test('mixed int/double with parentheses', () async {
      var r = await runDart(
        r'''
        class M {
          double run(List a) {
            var x = 5;
            var y = 2.0;
            return (x + 3) * y - 1;
          }
        }
      ''',
        'M',
        'run',
      );

      expect(r.value, equals(15.0));
    });

    test('negative numbers, precedence and integer division', () async {
      var r = await runDart(
        r'''
        class M {
          int run(List a) {
            return -3 + 4 * 2 - (10 ~/ 3);
          }
        }
      ''',
        'M',
        'run',
      );

      expect(r.value, equals(2));
    });
  });

  group('Core String methods', () {
    test('toUpperCase, substring, replaceAll, contains, split', () async {
      var r = await runDart(
        r'''
        class M {
          void run(List a) {
            var s = 'Hello World';
            print(s.toUpperCase());
            print(s.substring(0, 5));
            print(s.replaceAll('o', '0'));
            print(s.contains('World'));
            print(s.split(' '));
          }
        }
      ''',
        'M',
        'run',
      );

      expect(r.output[0], equals('HELLO WORLD'));
      expect(r.output[1], equals('Hello'));
      expect(r.output[2], equals('Hell0 W0rld'));
      expect(r.output[3], isTrue);
      expect(r.output[4], equals(['Hello', 'World']));
    });
  });

  group('Core num methods', () {
    test('toStringAsFixed, round, floor, abs', () async {
      var r = await runDart(
        r'''
        class M {
          void run(List a) {
            var d = -3.567;
            print(d.toStringAsFixed(2));
            print(d.round());
            print(d.floor());
            print(d.abs());
          }
        }
      ''',
        'M',
        'run',
      );

      expect(r.output, equals(['-3.57', -4, -4, 3.567]));
    });
  });

  group('Translation coverage', () {
    const source = r'''
      class Rect {
        int width = 6;
        int height = 7;
        int area() { return width * height; }
        String describe() {
          var a = area();
          return 'area: $a';
        }
      }
    ''';

    test('runs in Dart producing the described value', () async {
      var r = await runDart(source, 'Rect', 'describe');
      expect(r.value, equals('area: 42'));
    });

    test(
      'Dart -> Java keeps fields, methods and string concatenation',
      () async {
        var java = await translateDart(source, 'java11');
        expect(java, contains('class Rect'));
        expect(java, contains('int width = 6'));
        expect(java, contains('int area()'));
        // Java generator turns interpolation into string concatenation.
        expect(java, contains('"area: " + a'));
      },
    );

    test('Dart -> Dart round-trips and the regenerated source runs', () async {
      var dart = await translateDart(source, 'dart');
      expect(dart, contains('class Rect'));
      expect(dart, contains('int width = 6'));
      // Dart generator preserves interpolation.
      expect(dart, contains(r"'area: $a'"));

      var vm = ApolloVM();
      var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', dart, id: 'regen'));
      expect(ok, isTrue, reason: 'Regenerated Dart should load');

      var runner = vm.createRunner('dart')!;
      var astValue = await runner.executeClassMethod(
        '',
        'Rect',
        'describe',
        positionalParameters: [const []],
      );
      expect(astValue.getValueNoContext(), equals('area: 42'));
    });
  });
}
