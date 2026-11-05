@Tags(['wasm', 'dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

import 'wasm_runtime_setup.dart';

/// Runs [fn] — `Class.method` for a `static` method — with [args] through the
/// AST interpreter and through the compiled Wasm module, asserting that both
/// print [prints] and return [returns].
Future<void> _check(
  String code,
  String fn,
  List args, {
  List<String> prints = const [],
  Object? returns,
}) async {
  var vm = ApolloVM();
  expect(
    await vm.loadCodeUnit(SourceCodeUnit('dart', code, id: 'test')),
    isTrue,
    reason: "Can't load Dart source",
  );

  var dot = fn.indexOf('.');
  var className = dot < 0 ? '' : fn.substring(0, dot);
  var methodName = dot < 0 ? fn : fn.substring(dot + 1);

  Future<ApolloRunner> run(ApolloRunner runner, String label) async {
    var out = <String>[];
    runner.externalPrintFunction = (o) => out.add('$o');
    var r = className.isEmpty
        ? await runner.executeFunction(
            '',
            methodName,
            positionalParameters: args,
          )
        : await runner.executeClassMethod(
            '',
            className,
            methodName,
            positionalParameters: args,
          );
    expect(out, equals(prints), reason: '$label prints');
    expect(r.getValueNoContext(), returns, reason: '$label return');
    return runner;
  }

  await run(vm.createRunner('dart')!, 'interpreter');

  var modules = await vm.generateAllIn<BytesOutput>('wasm').allEntries();
  var bytes = modules.values.first.values.first.output();
  var vmWasm = ApolloVM();
  expect(
    await vmWasm.loadCodeUnit(
      BinaryCodeUnit('wasm', bytes, id: 'test.wasm', namespace: ''),
    ),
    isTrue,
    reason: 'Compiled Wasm failed to load',
  );
  await run(vmWasm.createRunner('wasm')!, 'Wasm');
}

void main() {
  setUpWasmRuntime();

  group('Wasm async/await', () {
    const doubleIt =
        'class Foo {\n'
        '  static Future<int> doubleIt(int n) async { return n * 2; }\n';

    test('a `var` takes the awaited value of a sibling static', () async {
      await _check(
        '$doubleIt'
            '  static Future<void> main(int x) async {\n'
            '    var a = await doubleIt(x);\n'
            '    var b = await doubleIt(a);\n'
            r"    print('a: $a b: $b');"
            '\n  }\n}',
        'Foo.main',
        [5],
        prints: ['a: 10 b: 20'],
      );
    });

    test('a typed local takes the awaited value', () async {
      await _check(
        '$doubleIt'
            '  static Future<int> main(int x) async {\n'
            '    int a = await doubleIt(x);\n'
            '    return a + 1;\n'
            '  }\n}',
        'Foo.main',
        [4],
        returns: 9,
      );
    });
  });

  group('Wasm nullable values', () {
    test('`int?` parameter: null and a value', () async {
      const src =
          'class A { static int f(int? p) { var x = p ?? 8; return x; } }';
      await _check(src, 'A.f', [null], returns: 8);
      await _check(src, 'A.f', [5], returns: 5);
    });

    test('`String?` parameter with `??`', () async {
      const src =
          'class A { static String f(String? p) { return p ?? "dflt"; } }';
      await _check(src, 'A.f', [null], returns: 'dflt');
      await _check(src, 'A.f', ['v'], returns: 'v');
    });

    test('`??=` assigns only a null target', () async {
      const src =
          'class A { static int f(int? p) { int? t = p; t ??= 3; '
          r'print("t: $t"); return t; } }';
      await _check(src, 'A.f', [null], prints: ['t: 3'], returns: 3);
      await _check(src, 'A.f', [9], prints: ['t: 9'], returns: 9);
    });

    test('a nullable local holds null, then a value', () async {
      await _check(
        r'int f() { int? s = null; print("s: $s"); s = 4; print("s: $s"); '
            'return s ?? 0; }',
        'f',
        [],
        prints: ['s: null', 's: 4'],
        returns: 4,
      );
    });

    test('`?.` and `?[` short-circuit on null', () async {
      const src =
          'int f(List<int>? values, String? label) {\n'
          '  var first = values?[0];\n'
          '  var len = label?.length;\n'
          r"  print('first: $first len: $len upper: ${label?.toUpperCase()}');"
          '\n  return (first ?? -1) + (len ?? 0);\n'
          '}';
      await _check(
        src,
        'f',
        [null, null],
        prints: ['first: null len: null upper: null'],
        returns: -1,
      );
      await _check(
        src,
        'f',
        [
          [10, 20],
          'hey',
        ],
        prints: ['first: 10 len: 3 upper: HEY'],
        returns: 13,
      );
    });

    test('nullable returns', () async {
      await _check('int? f(int a) { if (a > 0) return a; return null; }', 'f', [
        -1,
      ], returns: null);
      await _check(
        'String? f(int a) { if (a > 0) return "pos"; return null; }',
        'f',
        [-1],
        returns: null,
      );
    });

    test(
      '`!` yields the value, and throws a catchable error on null',
      () async {
        await _check(
          'class A {\n'
              '  static int run(int? value) {\n'
              '    var v = value!;\n'
              '    int? missing = null;\n'
              '    try {\n'
              '      var bad = missing!;\n'
              r"      print('unreachable: $bad');"
              '\n    } catch (e) {\n'
              r"      print('threw: $e');"
              '\n    }\n'
              '    return v;\n'
              '  }\n'
              '}',
          'A.run',
          [5],
          prints: [
            'threw: ApolloVMNullPointerException: '
                'Null check operator used on a null value',
          ],
          returns: 5,
        );
      },
    );

    test('a nullable class field walked with `.`, `?.` and `!`', () async {
      await _check(
        'class Node {\n'
            '  String name;\n'
            '  Node? next;\n'
            '  Node(this.name);\n'
            '}\n'
            'class C {\n'
            '  static int run() {\n'
            "    var a = Node('a');\n"
            "    a.next = Node('b');\n"
            r"    print('${a.next.name} ${a.next?.next?.name} ${a.next!.name}');"
            "\n    a.next.name = 'B';\n"
            r"    print('${a.next.name} ${a.next == null} ${a.next?.next == null}');"
            '\n    return 1;\n'
            '  }\n'
            '}',
        'C.run',
        [],
        prints: ['b null b', 'B false true'],
        returns: 1,
      );
    });
  });

  group('Wasm top-level variables', () {
    test('are module globals, initialized once', () async {
      await _check(
        'int counter = 0;\n'
            'final List<String> log = [];\n'
            'int next(String who) {\n'
            '  counter++;\n'
            r"  log.add('$who#$counter');"
            '\n  return counter;\n'
            '}\n'
            'class Foo {\n'
            '  static int main(int times) {\n'
            '    var counter = 1000;\n'
            '    for (var i = 0; i < times; i++) {\n'
            "      next('loop');\n"
            '    }\n'
            r"    print('local: $counter log: $log');"
            "\n    return next('last');\n"
            '  }\n'
            '}',
        'Foo.main',
        [2],
        prints: ['local: 1000 log: [loop#1, loop#2]'],
        returns: 3,
      );
    });
  });

  group('Wasm setters', () {
    test('assignment, compound assignment and a bare setter name', () async {
      await _check(
        'class Counter {\n'
            '  int _n = 0;\n'
            '  int get n => _n;\n'
            '  set n(int v) { _n = v < 0 ? 0 : v; }\n'
            '  void bump() { n = n + 10; }\n'
            '}\n'
            'class Foo {\n'
            '  static int main(int a) {\n'
            '    var c = Counter();\n'
            '    c.n = a;\n'
            '    c.n += 5;\n'
            '    c.bump();\n'
            r"    print('n: ${c.n}');"
            '\n    c.n = -3;\n'
            '    return c.n;\n'
            '  }\n'
            '}',
        'Foo.main',
        [7],
        prints: ['n: 22'],
        returns: 0,
      );
    });
  });

  group('Wasm extensions', () {
    test('methods on int', () async {
      await _check(
        'extension NumExt on int {\n'
            '  int doubled() { return this * 2; }\n'
            '  int increasedBy(int by) { return this + by; }\n'
            '}\n'
            'int f(int a) {\n'
            r"  print('inline: ${a.doubled()}');"
            '\n  return a.increasedBy(1);\n'
            '}',
        'f',
        [21],
        prints: ['inline: 42'],
        returns: 22,
      );
    });

    test('a getter and a method on a class', () async {
      await _check(
        'class Point {\n'
            '  int x;\n'
            '  int y;\n'
            '  Point(this.x, this.y);\n'
            '}\n'
            'extension PointExt on Point {\n'
            '  int get sum { return this.x + this.y; }\n'
            '  Point scaled(int by) { return Point(this.x * by, this.y * by); }\n'
            '}\n'
            'int f(int x, int y) {\n'
            '  var p = Point(x, y);\n'
            '  var s = p.scaled(3);\n'
            '  return s.sum + p.sum;\n'
            '}',
        'f',
        [2, 5],
        returns: 28,
      );
    });

    test('on String, calling built-in methods through `this`', () async {
      await _check(
        'extension Shout on String {\n'
            "  String shout() => this.toUpperCase() + '!';\n"
            '  bool get isLong => this.length > 3;\n'
            '}\n'
            'String f(String s) {\n'
            r"  print('long: ${s.isLong}');"
            '\n  return s.shout();\n'
            '}',
        'f',
        ['hey'],
        prints: ['long: false'],
        returns: 'HEY!',
      );
    });
  });

  group('Wasm records and sets', () {
    test('return, field access, printing and equality', () async {
      await _check(
        r'''
(int, int) minMax(List<int> values) {
  var min = values[0];
  var max = values[0];
  for (var v in values) {
    if (v < min) min = v;
    if (v > max) max = v;
  }
  return (min, max);
}

({String name, int age}) person(String name, int age) {
  return (name: name, age: age);
}

int f(int a, int b) {
  var range = minMax([a, b, 7, -3, 12]);
  var p = person("Ada", 36);
  print('${range.$1} ${range.$2} $range ${p.name} $p');
  print('${(1, x: 2) == (1, x: 2)} ${(a, b) == (b, a)} ${(7,)}');
  var nested = ((1, 2), name: ("n", true));
  print('$nested ${nested == ((1, 2), name: ("n", true))}');
  return range.$2 - range.$1;
}
''',
        'f',
        [10, 2],
        prints: [
          '-3 12 (-3, 12) Ada (age: 36, name: Ada)',
          'true false (7,)',
          '((1, 2), name: (n, true)) true',
        ],
        returns: 15,
      );
    });

    test('a set literal keeps distinct elements in order', () async {
      await _check(
        'int f(int a, int b) {\n'
            '  var pairs = {(a, b), (a, b), (b, a)};\n'
            '  var ints = {3, 1, 3, 2};\n'
            "  var strs = {'a', 'b', 'a'};\n"
            r"  print('$ints $strs ${strs.isEmpty}');"
            '\n  return pairs.length;\n'
            '}',
        'f',
        [10, 2],
        prints: ['{3, 1, 2} {a, b} false'],
        returns: 2,
      );
    });

    test('a record converts to a declared layout', () async {
      await _check(
        r'''
(double, int) f() { return (1, 2); }
(int?, int) g() { return (5, 1); }
int h() {
  var a = f();
  var b = g();
  (double, int) c = (3, 4);
  print('${a.$1 > 0.5} ${b.$1} ${b.$2} ${c.$1 > 2.5} ${a == (1, 2)}');
  return b.$2 + c.$2;
}
''',
        'h',
        [],
        prints: ['true 5 1 true true'],
        returns: 5,
      );
    });

    test('a set of boxed values compares by value', () async {
      await _check(
        r'''
int f() {
  var mixed = {1, 'a', 1, 'a'};
  var objs = <Object>{'x', 'x'};
  return mixed.length * 10 + objs.length;
}
''',
        'f',
        [],
        returns: 21,
      );
    });
  });

  group('Wasm review fixes', () {
    test('an int into a double global or local converts', () async {
      await _check(
        r'''
double scale = 1;
double total = 0;
int f(int x) {
  total = x;
  double local = 2;
  local = x;
  return (scale + total + local) > 8.5 ? 1 : 0;
}
''',
        'f',
        [4],
        returns: 1,
      );
    });

    test('a `bool?` return is a box, null included', () async {
      const src = 'bool? f(int a) { if (a > 0) return a > 5; return null; }';
      await _check(src, 'f', [1], returns: false);
      await _check(src, 'f', [9], returns: true);
      await _check(src, 'f', [-1], returns: null);
    });

    test('a null `String?` in an `Object?` slot stays null', () async {
      await _check(
        r'''
int f() {
  String? s = null;
  Object? o = s;
  print('${o == null} $o');
  return 0;
}
''',
        'f',
        [],
        prints: ['true null'],
        returns: 0,
      );
    });

    test('a field shadows a top-level variable, `++` included', () async {
      await _check(
        r'''
int count = 100;
class C {
  int count = 0;
  int inc() { count++; ++count; count += 1; return count; }
}
int f() {
  var c = C();
  return c.inc() * 1000 + count;
}
''',
        'f',
        [],
        returns: 3100,
      );
    });

    test('a bool literal into an `Object` global is boxed', () async {
      await _check(
        r'''
Object flag = true;
String f() { return 'flag: $flag'; }
''',
        'f',
        [],
        returns: 'flag: true',
      );
    });
  });

  group('Wasm 2.36.0', () {
    test('a catch of a value thrown by a callee', () async {
      const src = r'''
int g(int a) { if (a < 0) throw 'neg'; if (a > 9) throw 99; return a; }
String f(int a) { try { return 'ok ${g(a)}'; } catch (e) { return 'caught $e'; } }
''';
      await _check(src, 'f', [-1], returns: 'caught neg');
      await _check(src, 'f', [10], returns: 'caught 99');
      await _check(src, 'f', [3], returns: 'ok 3');

      const viaLocal = r'''
int g(int a) { if (a < 0) throw 'neg'; return a; }
String f(int a) { try { var r = g(a); return 'ok $r'; } catch (e) { return 'caught $e'; } }
''';
      await _check(viaLocal, 'f', [-1], returns: 'caught neg');
      await _check(viaLocal, 'f', [4], returns: 'ok 4');
    });

    test('a recursive local function', () async {
      await _check(
        'int f(int n) { int fact(int x) { return x <= 1 ? 1 : x * fact(x - 1); } '
            'return fact(n); }',
        'f',
        [5],
        returns: 120,
      );
    });

    test('lists of class instances', () async {
      await _check(
        r'''
class P { int v; P(this.v); String toString() => 'P$v'; }
int f() {
  var l = [P(1), P(2)];
  List<P> m = [P(10)];
  m.add(P(20));
  var t = 0;
  for (var p in l) { t += p.v; }
  for (var p in m) { t += p.v; }
  print('$l');
  return t + l[1].v;
}
''',
        'f',
        [],
        prints: ['[P1, P2]'],
        returns: 35,
      );
    });

    test('static members from outside the class', () async {
      await _check(
        r'''
class C {
  static int n = 5;
  static List<int> xs = [1, 2, 3];
  static int twice(int x) => x * 2;
  static int get three => 3;
}
int f() { C.n = C.n + 1; C.n += 2; return C.n * 100 + C.xs.length * 10 + C.twice(C.three); }
''',
        'f',
        [],
        returns: 836,
      );
    });

    test('number methods', () async {
      await _check(
        r'''
String f(int a, double d) {
  return '${a.toString()} ${a.abs()} ${a.clamp(-2, 2)} ${a.isEven} ${a.isOdd} '
      '${d.toInt()} ${d.round()} ${d.floor()} ${d.ceil()} ${int.parse(' 41 ') + 1} '
      '${(a - 10).abs()}';
}
''',
        'f',
        [-3, -2.5],
        returns: '-3 3 -2 false true -2 -3 -3 -2 42 13',
      );
    });

    test('labels, operators, getters, mixins and member chains', () async {
      await _check(
        r'''
int get two => 2;
mixin M { int m() => 9; }
class V with M {
  int x;
  V(this.x);
  V operator +(V o) => V(x + o.x);
  bool operator <(V o) => x < o.x;
  V twice() => V(x * 2);
}
int f() {
  var n = 0;
  outer: for (var i = 0; i < 3; i++) {
    for (var j = 0; j < 3; j++) {
      if (j == 1) continue outer;
      if (i == 2) break outer;
      n++;
    }
  }
  var v = V(1) + V(2);
  var less = V(1) < V(2) ? 1 : 0;
  return n * 10000 + v.x * 1000 + less * 100 + V(3).twice().x * 10 + V(0).m() - two;
}
''',
        'f',
        [],
        returns: 23167,
      );
    });
  });
}
