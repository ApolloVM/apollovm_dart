@TestOn('vm')
@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Loads a single Dart [source] and runs the top-level [function], returning
/// the resolved native return value.
///
/// [executeFunction] passes each element of [args] as a separate positional
/// argument, so a parameter list `(int a, int b)` is filled by `args[0]`,
/// `args[1]`, ...
Future<Object?> runFunc(
  String source,
  String function, [
  List args = const [],
]) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', source, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source!");

  var runner = vm.createRunner('dart')!;
  var astValue = await runner.executeFunction(
    '',
    function,
    positionalParameters: args,
  );
  return astValue.getValueNoContext();
}

/// Loads a single Dart [source], runs the top-level [function] and returns the
/// values captured from `print` calls.
Future<List> runPrint(
  String source,
  String function, [
  List args = const [],
]) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', source, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source!");

  var runner = vm.createRunner('dart')!;
  var output = [];
  runner.externalPrintFunction = output.add;

  await runner.executeFunction('', function, positionalParameters: args);
  return output;
}

/// Loads a single Dart [source] and runs the non-static [className].[method]
/// on a fresh (field-less) instance. [executeClassMethod] takes the method
/// arguments as a single positional [List], read inside the code as `args[0]`.
Future<Object?> runMethod(
  String source,
  String className,
  String method, [
  List args = const [],
]) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', source, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source!");

  var runner = vm.createRunner('dart')!;
  var astValue = await runner.executeClassMethod(
    '',
    className,
    method,
    positionalParameters: [args],
    classInstanceFields: const {},
  );
  return astValue.getValueNoContext();
}

void main() {
  group('Enhanced enums', () {
    const planet = '''
enum Planet {
  earth(5.97, 6371), mars(0.642, 3389);
  final double mass;
  final double radius;
  const Planet(this.mass, this.radius);
  double gravity() { return mass / (radius * radius); }
}
''';

    test('entry method computes from constructor fields', () async {
      var g = await runFunc(
        '${planet}double run() { var e = Planet.earth; return e.gravity(); }',
        'run',
      );
      expect(g as double, closeTo(5.97 / (6371 * 6371), 1e-18));
    });

    test('gravity() called directly on entry chain', () async {
      var g = await runFunc(
        '${planet}double run() { return Planet.mars.gravity(); }',
        'run',
      );
      expect(g as double, closeTo(0.642 / (3389 * 3389), 1e-18));
    });

    test('iterate .values summing a constructor field', () async {
      var t = await runFunc(
        '${planet}double run() { double t = 0; '
            'for (var p in Planet.values) { t += p.mass; } return t; }',
        'run',
      );
      expect(t as double, closeTo(5.97 + 0.642, 1e-9));
    });

    test('iterate .values printing .name', () async {
      var out = await runPrint(
        '${planet}void run() { for (var p in Planet.values) { print(p.name); } }',
        'run',
      );
      expect(out, ['earth', 'mars']);
    });

    test('.index / .name / field read via a variable', () async {
      expect(
        await runFunc(
          '${planet}int run() { var m = Planet.mars; return m.index; }',
          'run',
        ),
        1,
      );
      expect(
        await runFunc(
          '${planet}String run() { var e = Planet.earth; return e.name; }',
          'run',
        ),
        'earth',
      );
      expect(
        await runFunc(
          '${planet}double run() { var m = Planet.mars; return m.radius; }',
          'run',
        ),
        3389.0,
      );
    });

    test('enhanced enum entries are identity-equal singletons', () async {
      expect(
        await runFunc(
          '${planet}bool run() { return Planet.earth == Planet.earth; }',
          'run',
        ),
        isTrue,
      );
      expect(
        await runFunc(
          '${planet}bool run() { return Planet.earth == Planet.mars; }',
          'run',
        ),
        isFalse,
      );
    });
  });

  group('Classes', () {
    test('method returning `this` allows chained field read', () async {
      var r = await runFunc(
        'class B { int v = 0; B add(int n) { v = v + n; return this; } } '
            'int run() { var b = B(); var c = b.add(3); return c.v; }',
        'run',
      );
      expect(r, 3);
    });

    test('private field with accessor + mutator methods', () async {
      var r = await runFunc(
        'class C { int _v = 5; int value() { return _v; } '
            'void setV(int n) { _v = n; } } '
            'int run() { var c = C(); c.setV(9); return c.value(); }',
        'run',
      );
      expect(r, 9);
    });

    test('optional positional constructor parameter with default', () async {
      var r = await runFunc(
        'class C { int x; C([this.x = 3]); int get() { return x; } } '
            'int run() { var c = C(); return c.get(); }',
        'run',
      );
      expect(r, 3);
    });

    test('named constructor parameter fills a field', () async {
      var r = await runFunc(
        'class C { int x; C({int a = 0}) { x = a; } int get() { return x; } } '
            'int run() { var c = C(a: 7); return c.get(); }',
        'run',
      );
      expect(r, 7);
    });

    test('mixed-type fields (String / int / var)', () async {
      var r = await runFunc(
        "class P { String name = 'x'; int age = 5; var flag = true; "
            "String desc() { return name; } } "
            "String run() { var p = P(); return p.desc(); }",
        'run',
      );
      expect(r, 'x');
    });

    test('constructor body computes a derived field', () async {
      var r = await runFunc(
        'class Circle { double r; double area; '
            'Circle(double radius) { r = radius; area = 3 * r * r; } '
            'double getArea() { return area; } } '
            'double run() { var c = Circle(2.0); return c.getArea(); }',
        'run',
      );
      expect(r, 12.0);
    });

    test('two instances keep independent state', () async {
      var r = await runFunc(
        'class Counter { int n = 0; void inc() { n = n + 1; } '
            'int get() { return n; } } '
            'int run() { var a = Counter(); var b = Counter(); '
            'a.inc(); a.inc(); b.inc(); return a.get() * 10 + b.get(); }',
        'run',
      );
      expect(r, 21);
    });

    test('instance method result via string interpolation', () async {
      var out = await runPrint(
        r"class Pt { int x; int y; Pt(this.x, this.y); "
            r"String show() { return '($x,$y)'; } } "
            r"void run() { var p = Pt(2, 3); print(p.show()); }",
        'run',
      );
      expect(out, ['(2,3)']);
    });

    test('static method calling sibling static methods', () async {
      var out = await runPrint(
        'class M { static int sq(int n) { return n * n; } '
            'static int sumSq(int a, int b) { return sq(a) + sq(b); } } '
            'void run() { print(M.sumSq(3, 4)); }',
        'run',
      );
      expect(out, [25]);
    });

    test('subclass declares and runs its own method (extends)', () async {
      var r = await runFunc(
        'class A { int f() { return 1; } } '
            'class B extends A { int g() { return 2; } } '
            'int run() { var b = B(); return b.g(); }',
        'run',
      );
      expect(r, 2);
    });

    test('class instance method run via executeClassMethod entry', () async {
      var r = await runMethod(
        'class Box { int w = 3; int h = 4; int area(List a) { return w * h; } }',
        'Box',
        'area',
      );
      expect(r, 12);
    });
  });

  group('Collections (runtime)', () {
    test('list insert at index', () async {
      expect(
        await runFunc(
          'int run() { var l = [1,2,3]; l.insert(0, 9); return l[0]; }',
          'run',
        ),
        9,
      );
    });

    test('list clear then isEmpty', () async {
      expect(
        await runFunc(
          'bool run() { var l = [1,2,3]; l.clear(); return l.isEmpty; }',
          'run',
        ),
        isTrue,
      );
    });

    test('list remove(value) shrinks length', () async {
      expect(
        await runFunc(
          'int run() { var l = [1,2,3]; l.remove(2); return l.length; }',
          'run',
        ),
        2,
      );
    });

    test('list removeAt', () async {
      expect(
        await runFunc(
          'int run() { var l = [1,2,3]; l.removeAt(0); return l[0]; }',
          'run',
        ),
        2,
      );
    });

    test('list addAll', () async {
      expect(
        await runFunc(
          'int run() { var l = [1,2]; l.addAll([3,4]); return l.length; }',
          'run',
        ),
        4,
      );
    });

    test('list sublist', () async {
      expect(
        await runFunc(
          'int run() { var l = [1,2,3,4]; var s = l.sublist(1, 3); '
              'return s.length; }',
          'run',
        ),
        2,
      );
    });

    test('list contains returns false when absent', () async {
      expect(
        await runFunc(
          'bool run() { var l = [1,2,3]; return l.contains(9); }',
          'run',
        ),
        isFalse,
      );
    });

    test('typed generic list literal <int>[]', () async {
      expect(
        await runFunc(
          'int run() { var l = <int>[1,2,3]; return l.length; }',
          'run',
        ),
        3,
      );
    });

    test('map containsKey', () async {
      expect(
        await runFunc(
          "bool run() { var m = {'a':1}; return m.containsKey('a'); }",
          'run',
        ),
        isTrue,
      );
    });

    test('map remove shrinks length', () async {
      expect(
        await runFunc(
          "int run() { var m = {'a':1,'b':2}; m.remove('a'); return m.length; }",
          'run',
        ),
        1,
      );
    });

    test('map isNotEmpty', () async {
      expect(
        await runFunc(
          "bool run() { var m = {'a':1}; return m.isNotEmpty; }",
          'run',
        ),
        isTrue,
      );
    });

    test('typed generic map literal <String,int>{}', () async {
      expect(
        await runFunc(
          "int run() { var m = <String, int>{'a': 1, 'b': 2}; return m.length; }",
          'run',
        ),
        2,
      );
    });

    test('iterate map.keys concatenating', () async {
      expect(
        await runFunc(
          "String run() { var m = {'a':1,'b':2}; var s = ''; "
              "for (var k in m.keys) { s = s + k; } return s; }",
          'run',
        ),
        'ab',
      );
    });
  });

  group('Expressions', () {
    test('compound subtract assignment (-=)', () async {
      expect(
        await runFunc('int run() { int x = 10; x -= 3; return x; }', 'run'),
        7,
      );
    });

    test('nested ternary chain', () async {
      const src =
          'String run(int n) '
          '{ return n < 0 ? "neg" : n == 0 ? "zero" : "pos"; }';
      expect(await runFunc(src, 'run', [-4]), 'neg');
      expect(await runFunc(src, 'run', [0]), 'zero');
      expect(await runFunc(src, 'run', [4]), 'pos');
    });

    test('boolean logic combined through variables', () async {
      expect(
        await runFunc(
          'bool run() { var a = true; var b = false; '
              'var c = a && b; var d = a || b; return c || d; }',
          'run',
        ),
        isTrue,
      );
    });

    test('string interpolation with .length member', () async {
      expect(
        await runFunc(
          r"String run() { var s = 'hello'; return 'len=${s.length}'; }",
          'run',
        ),
        'len=5',
      );
    });

    test('string interpolation with method result', () async {
      expect(
        await runFunc(
          r"String run() { var s = 'hi'; return 'up=${s.toUpperCase()}'; }",
          'run',
        ),
        'up=HI',
      );
    });

    test('num.toString()', () async {
      expect(
        await runFunc(
          "String run() { var n = 42; return n.toString(); }",
          'run',
        ),
        '42',
      );
    });

    test('int.clamp', () async {
      expect(
        await runFunc(
          "int run() { var n = 15; return n.clamp(0, 10); }",
          'run',
        ),
        10,
      );
    });

    test('String codeUnitAt', () async {
      expect(
        await runFunc(
          "int run() { var s = 'ABC'; return s.codeUnitAt(0); }",
          'run',
        ),
        65,
      );
    });

    test('String trimLeft', () async {
      expect(
        await runFunc(
          "String run() { var s = '  x'; return s.trimLeft(); }",
          'run',
        ),
        'x',
      );
    });

    test('String replaceFirst', () async {
      expect(
        await runFunc(
          "String run() { var s = 'aaa'; return s.replaceFirst('a', 'b'); }",
          'run',
        ),
        'baa',
      );
    });

    test('String isEmpty', () async {
      expect(
        await runFunc("bool run() { var s = ''; return s.isEmpty; }", 'run'),
        isTrue,
      );
    });

    test('double.parse', () async {
      expect(
        await runFunc(
          "double run() { return double.parse('3.5') + 0.5; }",
          'run',
        ),
        4.0,
      );
    });
  });

  group('Statements', () {
    test('switch with several int cases', () async {
      const src =
          'int run(int x) { switch (x) { '
          'case 1: { return 100; } case 2: { return 200; } '
          'case 3: { return 300; } default: { return 0; } } }';
      expect(await runFunc(src, 'run', [3]), 300);
      expect(await runFunc(src, 'run', [1]), 100);
    });

    test('switch falls through to default', () async {
      const src =
          'int run(int x) { switch (x) { '
          'case 1: { return 100; } default: { return -1; } } }';
      expect(await runFunc(src, 'run', [9]), -1);
    });

    test('switch on a String', () async {
      const src =
          "String run(String s) { switch (s) { "
          "case 'a': { return 'A'; } case 'b': { return 'B'; } "
          "default: { return '?'; } } }";
      expect(await runFunc(src, 'run', ['b']), 'B');
      expect(await runFunc(src, 'run', ['z']), '?');
    });

    test('while loop with continue skipping evens', () async {
      expect(
        await runFunc(
          'int run() { int i = 0; int s = 0; while (i < 10) { i++; '
              'if (i % 2 == 0) { continue; } s += i; } return s; }',
          'run',
        ),
        25,
      );
    });

    test('do-while with both continue and break', () async {
      expect(
        await runFunc(
          'int run() { int i = 0; int s = 0; do { i++; '
              'if (i == 3) { continue; } if (i > 5) { break; } s += i; } '
              'while (true); return s; }',
          'run',
        ),
        12,
      );
    });

    test('nested for loops', () async {
      expect(
        await runFunc(
          'int run() { int s = 0; for (int i = 0; i < 3; i++) '
              '{ for (int j = 0; j < 3; j++) { s += i * j; } } return s; }',
          'run',
        ),
        9,
      );
    });

    test('unary ! controlling a while condition', () async {
      expect(
        await runFunc(
          'int run() { var done = false; int c = 0; '
              'while (!done) { c++; if (c >= 3) { done = true; } } return c; }',
          'run',
        ),
        3,
      );
    });

    test('return from a deeply nested block', () async {
      const src =
          'int run(int n) { if (n > 0) { if (n > 10) { return 2; } '
          'return 1; } return 0; }';
      expect(await runFunc(src, 'run', [5]), 1);
      expect(await runFunc(src, 'run', [20]), 2);
      expect(await runFunc(src, 'run', [-1]), 0);
    });

    test('local final and const variables', () async {
      expect(
        await runFunc('int run() { final x = 5; return x + 1; }', 'run'),
        6,
      );
      expect(
        await runFunc('int run() { const x = 5; return x + 1; }', 'run'),
        6,
      );
    });

    test('local (nested) function declaration', () async {
      expect(
        await runFunc(
          'int run() { int helper(int x) { return x * 2; } return helper(5); }',
          'run',
        ),
        10,
      );
    });
  });

  group('Exceptions', () {
    test('typed `on String catch`', () async {
      expect(
        await runFunc(
          "int run() { try { throw 'x'; } on String catch (e) { return 5; } }",
          'run',
        ),
        5,
      );
    });

    test('catch with stack trace parameter', () async {
      expect(
        await runFunc(
          "int run() { try { throw 'x'; } catch (e, st) { return 5; } }",
          'run',
        ),
        5,
      );
    });

    test('thrown value is available in catch', () async {
      expect(
        await runFunc(
          "String run() { try { throw 'boom'; } catch (e) { return e.toString(); } }",
          'run',
        ),
        'boom',
      );
    });

    test('rethrow propagates to an outer catch', () async {
      expect(
        await runFunc(
          "int run() { try { try { throw 'x'; } catch (e) { rethrow; } } "
              "catch (e) { return 9; } }",
          'run',
        ),
        9,
      );
    });
  });

  group('Functions and closures', () {
    test('closure returning a closure (block bodies)', () async {
      expect(
        await runFunc(
          'Function outer(int a) { return (int b) { return a + b; }; } '
              'int run() { var f = outer(10); return f(5); }',
          'run',
        ),
        15,
      );
    });

    test('closure mutating a captured variable across calls', () async {
      var out = await runPrint(
        'void run() { int n = 0; var inc = () { n = n + 1; return n; }; '
            'print(inc()); print(inc()); print(inc()); }',
        'run',
      );
      expect(out, [1, 2, 3]);
    });

    test('higher-order factory returning a multiplier', () async {
      var out = await runPrint(
        'Function mult(int f) { return (int x) { return x * f; }; } '
            'void run() { var triple = mult(3); print(triple(4)); }',
        'run',
      );
      expect(out, [12]);
    });

    test('typed function parameter int Function(int)', () async {
      expect(
        await runFunc(
          'int apply(int Function(int) f, int x) { return f(x); } '
              'int run() { return apply((a) => a + 1, 5); }',
          'run',
        ),
        6,
      );
    });

    test('no-argument lambda', () async {
      expect(
        await runFunc('int run() { var f = () => 42; return f(); }', 'run'),
        42,
      );
    });

    test('mutual recursion (isEven / isOdd)', () async {
      const src =
          'bool isEven(int n) { if (n == 0) { return true; } '
          'return isOdd(n - 1); } '
          'bool isOdd(int n) { if (n == 0) { return false; } '
          'return isEven(n - 1); } '
          'bool run() { return isEven(10); }';
      expect(await runFunc(src, 'run'), isTrue);
    });

    test('recursion computing power', () async {
      expect(
        await runFunc(
          'int power(int b, int e) { if (e == 0) { return 1; } '
              'return b * power(b, e - 1); } int run() { return power(2, 8); }',
          'run',
        ),
        256,
      );
    });
  });

  group('Print output', () {
    test('print of int, String, bool and double', () async {
      var out = await runPrint(
        "void run() { print(1); print('two'); print(true); print(3.5); }",
        'run',
      );
      expect(out, [1, 'two', true, 3.5]);
    });

    test('print with interpolated expression', () async {
      var out = await runPrint(
        r"void run() { var n = 3; print('n is $n squared ${n*n}'); }",
        'run',
      );
      expect(out, ['n is 3 squared 9']);
    });

    test('print a list value', () async {
      var out = await runPrint(
        'void run() { var l = [1,2,3]; print(l); }',
        'run',
      );
      expect(out[0], [1, 2, 3]);
    });
  });
}
