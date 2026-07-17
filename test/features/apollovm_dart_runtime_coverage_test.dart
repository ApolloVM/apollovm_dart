@TestOn('vm')
@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Loads a single Dart [source] and runs the top-level [function], returning
/// the resolved native return value and the collected `print` output.
///
/// For [executeFunction] each positional argument is passed separately, so
/// inside the Dart code a parameter list `(int a, int b)` is filled by
/// `args[0]`, `args[1]`, ... of [args].
Future<({Object? value, List output})> runFunc(
  String source,
  String function, {
  List args = const [],
  bool math = false,
}) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', source, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source!");

  var runner = vm.createRunner('dart', importCorePackageMath: math)!;
  var output = [];
  runner.externalPrintFunction = (o) => output.add(o);

  var astValue = await runner.executeFunction(
    '',
    function,
    positionalParameters: args,
  );
  return (value: astValue.getValueNoContext(), output: output);
}

/// Loads a single Dart [source] and runs [className].[method], returning the
/// resolved native return value and the collected `print` output.
///
/// [executeClassMethod] takes the method arguments as a single positional
/// [List], so inside the Dart code they are read as `args[0]`, `args[1]`, ...
Future<({Object? value, List output})> runMethod(
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
    classInstanceFields: const {},
  );
  return (value: astValue.getValueNoContext(), output: output);
}

void main() {
  group('Arithmetic', () {
    test('modulo (%)', () async {
      expect((await runFunc('int run() { return 17 % 5; }', 'run')).value, 2);
    });

    test('integer division (~/)', () async {
      expect((await runFunc('int run() { return 17 ~/ 5; }', 'run')).value, 3);
    });

    test('double division (/) promotes to double', () async {
      expect(
        (await runFunc('double run() { return 7 / 2; }', 'run')).value,
        3.5,
      );
    });

    test('mixed int/double promotion', () async {
      var r = await runFunc(
        'double run() { var x = 5; var y = 2.0; return (x + 3) * y - 1; }',
        'run',
      );
      expect(r.value, 15.0);
    });

    test('unary minus', () async {
      expect(
        (await runFunc('int run() { var i = 5; return -i; }', 'run')).value,
        -5,
      );
    });

    test('operator precedence with parentheses and ~/', () async {
      var r = await runFunc(
        'int run() { return -3 + 4 * 2 - (10 ~/ 3); }',
        'run',
      );
      expect(r.value, 2);
    });

    test('pre-increment (++i)', () async {
      expect(
        (await runFunc('int run() { int i = 5; return ++i; }', 'run')).value,
        6,
      );
    });

    test('post-increment (i++)', () async {
      var r = await runFunc(
        'int run() { int i = 5; int a = i++; return a * 100 + i; }',
        'run',
      );
      expect(r.value, 506);
    });

    test('pre-decrement (--i)', () async {
      expect(
        (await runFunc('int run() { int i = 5; return --i; }', 'run')).value,
        4,
      );
    });

    test('post-decrement (i--)', () async {
      var r = await runFunc(
        'int run() { int i = 5; int a = i--; return a * 100 + i; }',
        'run',
      );
      expect(r.value, 504);
    });

    test('compound assignment (+= and *=)', () async {
      var r = await runFunc(
        'int run() { int x = 10; x += 5; x *= 3; return x; }',
        'run',
      );
      expect(r.value, 45);
    });
  });

  group('Bitwise operators', () {
    test('& | ^ << >> ~ combined', () async {
      var r = await runFunc(
        'int run() { return (12 & 10) + (12 | 10) + (12 ^ 10) + (1 << 4) + (32 >> 2) + (~5); }',
        'run',
      );
      expect(r.value, 46);
    });
  });

  group('Comparisons and boolean logic', () {
    test('!=', () async {
      expect(
        (await runFunc('bool run() { return 3 != 4; }', 'run')).value,
        true,
      );
    });

    test('<=', () async {
      expect(
        (await runFunc('bool run() { return 3 <= 3; }', 'run')).value,
        true,
      );
    });

    test('logical negation (!)', () async {
      expect(
        (await runFunc('bool run() { return !false; }', 'run')).value,
        true,
      );
    });

    test('&&, ||, ! combined with short-circuit', () async {
      var r = await runFunc(
        'bool run() { var t = true; var f = false; return (t && !f) || f; }',
        'run',
      );
      expect(r.value, true);
    });

    test('boolean condition selecting a branch', () async {
      var r = await runFunc(
        r'''
        String run(int age, bool member) {
          if (age >= 18 && member) { return 'full'; }
          if (age >= 18 || member) { return 'partial'; }
          return 'none';
        }
        ''',
        'run',
        args: [16, true],
      );
      expect(r.value, 'partial');
    });
  });

  group('Ternary conditional', () {
    test('a > 0 ? 1 : -1', () async {
      expect(
        (await runFunc(
          'int run(int a) { return a > 0 ? 1 : -1; }',
          'run',
          args: [5],
        )).value,
        1,
      );
      expect(
        (await runFunc(
          'int run(int a) { return a > 0 ? 1 : -1; }',
          'run',
          args: [-5],
        )).value,
        -1,
      );
    });
  });

  group('Loops', () {
    test('C-style for loop', () async {
      var r = await runFunc(
        'int run() { int s = 0; for (int i = 0; i < 5; i++) { s += i; } return s; }',
        'run',
      );
      expect(r.value, 10);
    });

    test('while loop', () async {
      var r = await runFunc(
        'int run() { int i = 0; int s = 0; while (i < 5) { s += i; i++; } return s; }',
        'run',
      );
      expect(r.value, 10);
    });

    test('do/while loop', () async {
      var r = await runFunc(
        'int run() { int i = 0; int s = 0; do { s += i; i++; } while (i < 5); return s; }',
        'run',
      );
      expect(r.value, 10);
    });

    test('for-in over a list', () async {
      var r = await runFunc(
        'int run() { var l = [1, 2, 3, 4]; int s = 0; for (var x in l) { s += x; } return s; }',
        'run',
      );
      expect(r.value, 10);
    });

    test('break', () async {
      var r = await runFunc(
        'int run() { int s = 0; for (int i = 0; i < 10; i++) { if (i == 3) { break; } s += i; } return s; }',
        'run',
      );
      expect(r.value, 3);
    });

    test('continue', () async {
      var r = await runFunc(
        'int run() { int s = 0; for (int i = 0; i < 5; i++) { if (i == 2) { continue; } s += i; } return s; }',
        'run',
      );
      expect(r.value, 8);
    });

    test('switch/case with default', () async {
      var r = await runFunc(
        r'''
        int run(int x) {
          switch (x) {
            case 1: { return 10; }
            case 2: { return 20; }
            default: { return 0; }
          }
        }
        ''',
        'run',
        args: [2],
      );
      expect(r.value, 20);
    });
  });

  group('Branches', () {
    test('if / else if / else', () async {
      var src = r'''
        String run(int n) {
          if (n < 0) { return 'neg'; }
          else if (n == 0) { return 'zero'; }
          else { return 'pos'; }
        }
        ''';
      expect((await runFunc(src, 'run', args: [-1])).value, 'neg');
      expect((await runFunc(src, 'run', args: [0])).value, 'zero');
      expect((await runFunc(src, 'run', args: [7])).value, 'pos');
    });
  });

  group('Strings', () {
    test('interpolation with variable and embedded expression', () async {
      var r = await runFunc(
        r"String run() { var a = 2; var b = 3; return '$a and ${a + b}'; }",
        'run',
      );
      expect(r.value, '2 and 5');
    });

    test('concatenation', () async {
      expect(
        (await runFunc(
          "String run() { return 'a' + 'b' + 'c'; }",
          'run',
        )).value,
        'abc',
      );
    });

    test('toUpperCase / toLowerCase / length', () async {
      var r = await runFunc(r'''
        void run() {
          var s = 'Hello';
          print(s.toUpperCase());
          print(s.toLowerCase());
          print(s.length);
        }
        ''', 'run');
      expect(r.output, ['HELLO', 'hello', 5]);
    });

    test('trim', () async {
      expect(
        (await runFunc(
          "String run() { var s = '  x  '; return s.trim(); }",
          'run',
        )).value,
        'x',
      );
    });

    test('substring', () async {
      expect(
        (await runFunc(
          "String run() { var s = 'hello'; return s.substring(1, 3); }",
          'run',
        )).value,
        'el',
      );
    });

    test('contains', () async {
      expect(
        (await runFunc(
          "bool run() { var s = 'hello'; return s.contains('ell'); }",
          'run',
        )).value,
        true,
      );
    });

    test('startsWith / endsWith / indexOf', () async {
      var r = await runFunc(r'''
        void run() {
          var s = 'a,b,c,b';
          print(s.startsWith('a'));
          print(s.endsWith('b'));
          print(s.indexOf('b'));
        }
        ''', 'run');
      expect(r.output, [true, true, 2]);
    });

    test('split', () async {
      var r = await runFunc(
        "void run() { var s = 'a,b,c'; print(s.split(',')); }",
        'run',
      );
      expect(r.output[0], ['a', 'b', 'c']);
    });

    test('replaceAll', () async {
      expect(
        (await runFunc(
          "String run() { var s = 'aaa'; return s.replaceAll('a', 'b'); }",
          'run',
        )).value,
        'bbb',
      );
    });
  });

  group('Numbers', () {
    test('int.abs / toDouble / compareTo', () async {
      var r = await runFunc(r'''
        void run() {
          var n = -7;
          print(n.abs());
          print(n.toDouble());
          var a = 10;
          var b = 20;
          print(a.compareTo(b));
        }
        ''', 'run');
      expect(r.output, [7, -7.0, -1]);
    });

    test('double toStringAsFixed / round / floor / ceil', () async {
      var r = await runFunc(r'''
        void run() {
          var d = 3.567;
          print(d.toStringAsFixed(2));
          print(d.round());
          print(d.floor());
          print(d.ceil());
        }
        ''', 'run');
      expect(r.output, ['3.57', 4, 3, 4]);
    });

    test('int.parse', () async {
      expect(
        (await runFunc(
          "int run() { return int.parse('123') + 1; }",
          'run',
        )).value,
        124,
      );
    });
  });

  group('Collections', () {
    test('list literal, index read/write and length', () async {
      var r = await runFunc(
        'int run() { var l = [1, 2, 3]; l[0] = 9; l.add(4); return l[0] + l.length; }',
        'run',
      );
      expect(r.value, 13);
    });

    test('list first / last / isEmpty / contains / indexOf', () async {
      var r = await runFunc(r'''
        void run() {
          var l = [1, 2, 3];
          print(l.first);
          print(l.last);
          print(l.isEmpty);
          print(l.contains(2));
          print(l.indexOf(3));
        }
        ''', 'run');
      expect(r.output, [1, 3, false, true, 2]);
    });

    test('index loop summing a list', () async {
      var r = await runFunc(
        'int run() { var l = [5, 10, 15, 20]; int t = 0; for (var i = 0; i < 4; i++) { t += l[i]; } return t; }',
        'run',
      );
      expect(r.value, 50);
    });

    test('map literal, key read/write and length', () async {
      var r = await runFunc(
        "int run() { var m = {'a': 1, 'b': 2}; m['c'] = 3; return m['a'] + m['c'] + m.length; }",
        'run',
      );
      expect(r.value, 7);
    });

    test('iterate map keys and values', () async {
      var r = await runFunc(r'''
        int run() {
          var m = {'a': 1, 'b': 2};
          int s = 0;
          for (var v in m.values) { s += v; }
          return s;
        }
        ''', 'run');
      expect(r.value, 3);
    });
  });

  group('Lambdas and closures', () {
    test('lambda assigned to a var and called', () async {
      expect(
        (await runFunc(
          'int run() { var f = (int x) => x * 2; return f(5); }',
          'run',
        )).value,
        10,
      );
    });

    test('closure capturing an outer variable', () async {
      var r = await runFunc(
        'int run() { int n = 10; var f = (int x) => x + n; return f(5); }',
        'run',
      );
      expect(r.value, 15);
    });

    test('higher-order: function passed as an argument', () async {
      var r = await runFunc(
        'int apply(Function f, int x) { return f(x); } int run() { return apply((a) => a * 2, 5); }',
        'run',
      );
      expect(r.value, 10);
    });

    test('function returning a function (closure over param)', () async {
      var r = await runFunc(
        'Function makeAdder(int n) { return (x) => x + n; } int run() { var add10 = makeAdder(10); return add10(5); }',
        'run',
      );
      expect(r.value, 15);
    });

    test('concrete function-type return (int Function(int))', () async {
      var r = await runFunc(
        'int Function(int) makeAdder(int n) { return (int x) => x + n; } int run() { var add = makeAdder(100); return add(5); }',
        'run',
      );
      expect(r.value, 105);
    });
  });

  group('Recursion', () {
    test('factorial', () async {
      var r = await runFunc(
        'int fact(int n) { if (n <= 1) { return 1; } return n * fact(n - 1); } int run() { return fact(5); }',
        'run',
      );
      expect(r.value, 120);
    });

    test('fibonacci', () async {
      var r = await runFunc(
        'int fib(int n) { if (n < 2) { return n; } return fib(n - 1) + fib(n - 2); } int run() { return fib(10); }',
        'run',
      );
      expect(r.value, 55);
    });
  });

  group('Exceptions', () {
    test('try / catch / finally with throw', () async {
      var r = await runFunc(
        r'''
        String run(int x) {
          try {
            if (x < 0) { throw 'negative'; }
            return 'ok';
          } catch (e) {
            return 'caught';
          } finally {
            print('done');
          }
        }
        ''',
        'run',
        args: [-1],
      );
      expect(r.value, 'caught');
      expect(r.output, ['done']);
    });

    test('try succeeds and still runs finally', () async {
      var r = await runFunc(
        r'''
        String run(int x) {
          try {
            if (x < 0) { throw 'negative'; }
            return 'ok';
          } catch (e) {
            return 'caught';
          } finally {
            print('done');
          }
        }
        ''',
        'run',
        args: [5],
      );
      expect(r.value, 'ok');
      expect(r.output, ['done']);
    });
  });

  group('Classes', () {
    test('constructor with this.x shorthand and instance method', () async {
      var r = await runFunc(
        'class P { int x; P(this.x); int get() { return x; } } int run() { var p = P(7); return p.get(); }',
        'run',
      );
      expect(r.value, 7);
    });

    test('constructor body computing a field', () async {
      var r = await runFunc(
        'class P { int x; P(int a) { x = a * 2; } int get() { return x; } } int run() { var p = P(5); return p.get(); }',
        'run',
      );
      expect(r.value, 10);
    });

    test('var (untyped) field', () async {
      var r = await runFunc(
        'class C { var x = 5; int get() { return x; } } int run() { var c = C(); return c.get(); }',
        'run',
      );
      expect(r.value, 5);
    });

    test('method calling another method via this', () async {
      var r = await runFunc(
        'class C { int a() { return 3; } int b() { return this.a() * 2; } } int run() { var c = C(); return c.b(); }',
        'run',
      );
      expect(r.value, 6);
    });

    test('static method calling another static method', () async {
      var r = await runFunc(
        'class U { static int dbl(int n) { return n * 2; } static int quad(int n) { return dbl(dbl(n)); } } int run() { return U.quad(3); }',
        'run',
      );
      expect(r.value, 12);
    });

    test('class fields via executeClassMethod entry point', () async {
      var r = await runMethod(
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
      expect(r.value, 24);
    });

    test(
      'describe() combining methods and interpolation (class method)',
      () async {
        var r = await runMethod(
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
        expect(r.value, 'area=42 perim=26');
      },
    );
  });

  group('Enums', () {
    test('enum value .index via a variable', () async {
      var r = await runFunc(
        'enum Color { red, green, blue } int run() { var b = Color.green; return b.index; }',
        'run',
      );
      expect(r.value, 1);
    });

    test('enum value .name via a variable', () async {
      var r = await runFunc(
        'enum Color { red, green, blue } String run() { var b = Color.blue; return b.name; }',
        'run',
      );
      expect(r.value, 'blue');
    });

    test('summing indices of several enum values', () async {
      var r = await runFunc(r'''
        enum Color { red, green, blue }
        int run() {
          var a = Color.red;
          var b = Color.green;
          var c = Color.blue;
          int total = a.index + b.index + c.index;
          if (b.index == 1) { total = total + 100; }
          return total;
        }
        ''', 'run');
      expect(r.value, 103);
    });
  });

  group('Parameters', () {
    test('multiple positional parameters', () async {
      expect(
        (await runFunc(
          'int f(int a, int b, int c) { return a + b + c; } int run() { return f(1, 2, 3); }',
          'run',
        )).value,
        6,
      );
    });

    test('default parameter value used when omitted', () async {
      expect(
        (await runFunc(
          'int f(int a = 5) { return a; } int run() { return f(); }',
          'run',
        )).value,
        5,
      );
    });

    test('default parameter value overridden', () async {
      expect(
        (await runFunc(
          'int f(int a = 5) { return a; } int run() { return f(9); }',
          'run',
        )).value,
        9,
      );
    });

    test('named arguments at the call site', () async {
      expect(
        (await runFunc(
          'int sub(int a, int b) { return a - b; } int run() { return sub(b: 3, a: 10); }',
          'run',
        )).value,
        7,
      );
    });

    test('named parameters with braces and defaults', () async {
      expect(
        (await runFunc(
          'int f({int a = 1, int b = 2}) { return a * 10 + b; } int run() { return f(b: 5, a: 3); }',
          'run',
        )).value,
        35,
      );
    });

    test('executeFunction passes separate positional args', () async {
      expect(
        (await runFunc(
          'int add(int a, int b) { return a + b; }',
          'add',
          args: [10, 32],
        )).value,
        42,
      );
    });
  });

  group('Math library', () {
    test('sqrt / pow / max / min', () async {
      var r = await runFunc(
        r'''
        import 'dart:math';
        void run() {
          print(sqrt(16));
          print(pow(2, 10));
          print(max(3, 9));
          print(min(3, 9));
        }
        ''',
        'run',
        math: true,
      );
      expect(r.output, [4.0, 1024, 9, 3]);
    });
  });
}
