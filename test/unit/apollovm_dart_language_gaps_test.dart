@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
// Serialization internals are not re-exported from the public library.
import 'package:apollovm/src/serialization/ast_binary_reader.dart';
import 'package:apollovm/src/serialization/ast_binary_writer.dart';
import 'package:test/test.dart';

/// Dart syntax and core-library gaps closed in 2.36.0: labels, collection
/// `if`/`for`/spread, user operators, generic functions, static and top-level
/// getters, mixins, member chains on calls and literals, core List/Map
/// methods, and interpreter fixes (evaluation order, `toString`, statics).

Future<ApolloVM> _load(String src) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', src, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source");
  return vm;
}

/// Runs `f(args)`: its value and its `print` output.
Future<(Object?, List<String>)> _run(String src, [List args = const []]) async {
  var vm = await _load(src);
  var runner = vm.createRunner('dart')!;
  var out = <String>[];
  runner.externalPrintFunction = (o) => out.add('$o');
  var r = await runner.executeFunction('', 'f', positionalParameters: args);
  return (r.getValueNoContext(), out);
}

Future<Object?> _value(String src, [List args = const []]) async =>
    (await _run(src, args)).$1;

/// The Dart source regenerated from [src], and the value `f(args)` returns
/// when that regenerated source runs.
Future<(String, Object?)> _regenerate(
  String src, [
  List args = const [],
]) async {
  var vm = await _load(src);
  var code = (await vm.generateAllCodeIn('dart').writeAllSources())
      .toString()
      .split('\n')
      .where((l) => !l.startsWith('<<<<'))
      .join('\n');
  return (code, await _value(code, args));
}

/// Encodes [src]'s AST to the binary format and back; `f(args)` must run the
/// same on the decoded AST.
Future<Object?> _binaryRoundTrip(String src, [List args = const []]) async {
  var vm = await _load(src);
  var codeUnit = vm.getLanguageNamespaces('dart').allCodeUnits.first;
  var bytes = ASTBinaryWriter().writeCodeUnit(codeUnit);
  var decoded = const ASTBinaryReader().readCodeUnit(bytes);
  var vm2 = ApolloVM();
  expect(await vm2.loadCodeUnit(decoded), isTrue);
  var r = await vm2
      .createRunner('dart')!
      .executeFunction('', 'f', positionalParameters: args);
  return r.getValueNoContext();
}

void main() {
  group('Labels', () {
    const src = '''
int f() {
  var n = 0;
  outer: for (var i = 0; i < 3; i++) {
    for (var j = 0; j < 3; j++) {
      if (j == 1) continue outer;
      if (i == 2) break outer;
      n++;
    }
  }
  var w = 0;
  loop: while (true) {
    w++;
    switch (w) {
      case 3:
        break loop;
    }
  }
  return n * 10 + w;
}''';

    test('break/continue a labeled loop, through a switch', () async {
      expect(await _value(src), 23);
    });

    test('Dart output and binary round trip', () async {
      var (code, value) = await _regenerate(src);
      expect(code, contains('outer: for'));
      expect(code, contains('continue outer;'));
      expect(value, 23);
      expect(await _binaryRoundTrip(src), 23);
    });

    test('targets without labels refuse them', () async {
      var vm = await _load(src);
      for (var lang in ['python', 'lua', 'csharp']) {
        expect(
          () => vm.generateAllCodeIn(lang).writeAllSources(),
          throwsA(isA<UnsupportedSyntaxError>()),
          reason: lang,
        );
      }
      var kotlin = (await vm.generateAllCodeIn('kotlin').writeAllSources())
          .toString();
      expect(kotlin, contains('outer@ for'));
      expect(kotlin, contains('continue@outer'));
    });
  });

  group('Collection if / for / spread', () {
    const src = '''
int f(bool b) {
  var xs = [5, 6];
  var l = [1, if (b) 2 else 3, for (var i = 0; i < 2; i++) i * 10, for (var x in xs) x, ...xs, ...?null];
  var s = {1, if (!b) 9, ...[1, 2]};
  print('\$l \$s');
  return l.length;
}''';

    test('expand in order', () async {
      var (value, out) = await _run(src, [true]);
      expect(value, 8);
      expect(out, ['[1, 2, 0, 10, 5, 6, 5, 6] {1, 2}']);
    });

    test('Dart output and binary round trip', () async {
      var (code, value) = await _regenerate(src, [true]);
      expect(code, contains('if (b) 2 else 3'));
      expect(code, contains('...xs'));
      expect(value, 8);
      expect(await _binaryRoundTrip(src, [true]), 8);
    });

    test('other targets refuse them', () async {
      var vm = await _load(src);
      expect(
        () => vm.generateAllCodeIn('javascript').writeAllSources(),
        throwsA(isA<UnsupportedSyntaxError>()),
      );
    });
  });

  group('User operators', () {
    const src = '''
class V {
  int x;
  V(this.x);
  V operator +(V o) => V(x + o.x);
  bool operator <(V o) => x < o.x;
  bool operator ==(Object o) => o is V && o.x == x;
}
String f() {
  var v = V(1) + V(2);
  return '\${v.x} \${V(1) < V(2)} \${V(4) == V(4)} \${V(4) != V(4)}';
}''';

    test('dispatch to the left operand', () async {
      expect(await _value(src), '3 true true false');
    });

    test('Dart output; other targets refuse', () async {
      var (code, value) = await _regenerate(src);
      expect(code, contains('operator+(V o)'));
      expect(value, '3 true true false');
      var vm = await _load(src);
      expect(
        () => vm.generateAllCodeIn('typescript').writeAllSources(),
        throwsA(isA<UnsupportedSyntaxError>()),
      );
    });
  });

  group('Declarations', () {
    test('generic functions and methods', () async {
      expect(
        await _value('''
T first<T>(List<T> l) { return l[0]; }
class Box { R pick<R>(R a, R b) => b; }
int f() { return first<int>([4, 5]) + first([1]) + Box().pick<int>(0, 2); }
'''),
        7,
      );
    });

    test('a generic header tried and dropped erases nothing', () async {
      // `List<String> log` is first tried as a function named `List`: its
      // `<String>` must not erase `String` for later declarations.
      expect(
        await _value('''
final List<String> log = [];
String f() { log.add('a'); return 'x'; }
'''),
        'x',
      );
      expect(
        await _value("String f() { return 'still a String'; }"),
        'still a String',
      );
    });

    test('static and top-level getters', () async {
      const src = '''
int get two => 2;
class C { static int get three => 3; }
int f() { return two + C.three; }''';
      expect(await _value(src), 5);
      var (code, value) = await _regenerate(src);
      expect(code, contains('static int get three'));
      expect(value, 5);
    });

    test('mixins', () async {
      expect(
        await _value('''
mixin Greets { String hello() => 'hi \$name'; String get name => 'm'; }
mixin Counts { int n = 0; void inc() { n++; } }
class A with Greets, Counts { String get name => 'a'; }
String f() { var a = A(); a.inc(); a.inc(); return '\${a.hello()} \${a.n}'; }
'''),
        'hi a 2',
      );
    });

    test('member chains on calls and literals', () async {
      expect(
        await _value('''
class P { int x; P(this.x); P.zero() : x = 0; P twice() => P(x * 2); }
P? g(int a) => a > 0 ? P(a) : null;
String f() {
  return '\${P(3).twice().x} \${P.zero().x} \${g(-1)?.x} \${g(2)?.x} '
      '\${[1, 2, 3].length} \${{1, 2}.length} \${'abc'.length}';
}
'''),
        '6 0 null 2 3 2 3',
      );
    });
  });

  group('Core library', () {
    test('List methods with closures', () async {
      expect(
        await _value('''
String f() {
  var l = [3, 1, 2];
  var s = [...l];
  s.sort();
  var d = [...l];
  d.sort((a, b) => b - a);
  var t = 0;
  l.forEach((x) { t += x; });
  return '\$s \$d \${l.map((x) => x * 2).toList()} \${l.where((x) => x > 1).toList()} '
      '\${l.any((x) => x > 2)} \${l.every((x) => x > 2)} \${l.fold(0, (a, b) => a + b)} '
      '\${l.reduce((a, b) => a * b)} \${l.join('-')} \${l.reversed.toList()} \$t';
}
'''),
        '[1, 2, 3] [3, 2, 1] [6, 2, 4] [3, 2] true false 6 6 3-1-2 [2, 1, 3] 6',
      );
    });

    test('Map forEach / putIfAbsent / entries', () async {
      expect(
        await _value('''
String f() {
  var m = <String, int>{'a': 1};
  m.putIfAbsent('b', () => 2);
  m.putIfAbsent('a', () => 9);
  var t = 0;
  m.forEach((k, v) { t += v; });
  var keys = '';
  for (var e in m.entries) { keys += '\${e.key}=\${e.value};'; }
  return '\$t \$keys';
}
'''),
        '3 a=1;b=2;',
      );
    });

    test('int isEven / isOdd / isNegative', () async {
      expect(
        await _value(
          r"String f(int a) => '${a.isEven} ${a.isOdd} ${a.isNegative}';",
          [-3],
        ),
        'false true true',
      );
    });
  });

  group('Interpreter fixes', () {
    test('a user toString in interpolation and collections', () async {
      var (_, out) = await _run('''
class P { int x; P(this.x); String toString() => 'P(\$x)'; }
void f() { var l = [P(1), P(2)]; print('v: \${l[0]}'); print(l); print(l[1]); }
''');
      expect(out, ['v: P(1)', '[P(1), P(2)]', 'P(2)']);
    });

    test('operands and interpolation run left to right', () async {
      expect(
        await _value('''
class C { int count = 0; int b() { count = 7; return count; } }
int g(List<int> log, int v) { log.add(v); return v; }
String f() {
  var c = C();
  var s = '\${c.b()} \${c.count}';
  var log = <int>[];
  var sum = g(log, 1) + g(log, 2);
  return '\$s \$log \$sum';
}
'''),
        '7 7 [1, 2] 3',
      );
    });

    test('static initializers read concurrently', () async {
      expect(
        await _value('''
class C { static int n = 2 + 3; static String s = 'a' + 'b'; }
String f() => '\${C.n} \${C.s}';
'''),
        '5 ab',
      );
    });

    test('a function stored in a field', () async {
      expect(
        await _value('''
class H { int Function(int) fn; H(this.fn); }
int f() { var h = H((x) => x + 1); return h.fn(4); }
'''),
        5,
      );
    });

    test('`return g()` in a try catches what g throws', () async {
      var (value, out) = await _run('''
int g(int a) { if (a < 0) throw 42; return a; }
int f() { try { return g(-1); } catch (e) { print('e: \$e'); return 1; } }
''');
      expect(value, 1);
      expect(out, ['e: 42']);
    });

    test('a `var` loop variable keeps an instance', () async {
      expect(
        await _value('''
class P { int v; P(this.v); }
int f() { List<P> l = [P(1)]; l.add(P(5)); var t = 0; for (var p in l) { t += p.v; } return t; }
'''),
        6,
      );
    });
  });
}
