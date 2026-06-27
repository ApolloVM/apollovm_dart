@TestOn('vm')
@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Loads a single Dart [source] and runs the top-level [function], returning
/// the resolved native return value.
Future<Object?> runFunction(
  String source,
  String function, {
  List positionalParameters = const [],
  Map? namedParameters,
}) async {
  var vm = ApolloVM();
  var loadOK = await vm.loadCodeUnit(
    SourceCodeUnit('dart', source, id: 'test'),
  );
  expect(loadOK, isTrue, reason: "Can't load Dart source!");

  var runner = vm.createRunner('dart')!;

  var astValue = await runner.executeFunction(
    '',
    function,
    positionalParameters: positionalParameters,
    namedParameters: namedParameters,
  );

  return astValue.getValueNoContext();
}

/// Translates a loaded Dart [source] back into Dart, returning the single
/// generated source unit (raw, loadable code — not the multi-source wrapper).
Future<String> regenDart(String source) async {
  var vm = ApolloVM();
  await vm.loadCodeUnit(SourceCodeUnit('dart', source, id: 'test'));

  var codeStorage = vm.generateAllCodeIn('dart');

  var buffer = StringBuffer();
  for (var ns in await codeStorage.getNamespaces()) {
    for (var id in await codeStorage.getNamespaceCodeUnitsIDs(ns)) {
      buffer.write(await codeStorage.getNamespaceCodeUnit(ns, id));
    }
  }
  return buffer.toString();
}

void main() {
  group('Dart named parameters', () {
    test('declared and called by name (order-independent)', () async {
      var src = r'''
        int sub({int a, int b}) {
          return a - b;
        }

        int callForward() {
          return sub(a: 10, b: 3);
        }

        int callReversed() {
          return sub(b: 3, a: 10);
        }
      ''';

      expect(await runFunction(src, 'callForward'), equals(7));
      // Named arguments bind by name regardless of call-site order.
      expect(await runFunction(src, 'callReversed'), equals(7));
    });

    test('mixed positional + named parameters', () async {
      var src = r'''
        int compute(int base, {int factor, int offset}) {
          return base * factor + offset;
        }

        int run() {
          return compute(5, offset: 1, factor: 3);
        }
      ''';

      expect(await runFunction(src, 'run'), equals(16));
    });

    test('omitted named argument defaults to null', () async {
      var src = r'''
        int echo({int a}) {
          return a;
        }

        int provided() {
          return echo(a: 5);
        }

        int omitted() {
          return echo();
        }
      ''';

      expect(await runFunction(src, 'provided'), equals(5));
      // An omitted named argument resolves to null (no default-value support).
      expect(await runFunction(src, 'omitted'), isNull);
    });

    test('named arguments passed directly to executeFunction', () async {
      var src = r'''
        int sum({int a, int b}) {
          return a + b;
        }
      ''';

      var r = await runFunction(
        src,
        'sum',
        namedParameters: {'a': 20, 'b': 22},
      );
      expect(r, equals(42));
    });

    test('class method with named parameters', () async {
      var src = r'''
        class Calc {
          int scale(int v, {int by}) {
            return v * by;
          }

          int run() {
            return scale(6, by: 7);
          }
        }
      ''';

      var vm = ApolloVM();
      await vm.loadCodeUnit(SourceCodeUnit('dart', src, id: 'test'));
      var runner = vm.createRunner('dart')!;
      var astValue = await runner.executeClassMethod(
        '',
        'Calc',
        'run',
        positionalParameters: [],
        classInstanceFields: const {},
      );
      expect(astValue.getValueNoContext(), equals(42));
    });

    group('round-trip code generation', () {
      test('regenerates named declaration and named call', () async {
        var src = r'''
        int withPositional(int x, {int y}) {
          return x * y;
        }

        int run() {
          return withPositional(4, y: 7);
        }
      ''';

        var regen = await regenDart(src);

        // Named parameter group keeps the comma after the positional param.
        expect(regen, contains('int withPositional(int x, {int y})'));
        // Named argument syntax is preserved at the call site.
        expect(regen, contains('withPositional(4, y: 7)'));

        // The regenerated source re-parses and runs to the same result.
        expect(await runFunction(regen, 'run'), equals(28));
      });

      test('regenerates named-only declaration', () async {
        var src = r'''
        int add({int a, int b}) {
          return a + b;
        }

        int run() {
          return add(a: 1, b: 2);
        }
      ''';

        var regen = await regenDart(src);
        expect(regen, contains('int add({int a, int b})'));
        expect(await runFunction(regen, 'run'), equals(3));
      });
    });

    group('default values', () {
      test('named parameter defaults are used when omitted', () async {
        var src = r'''
        int greet({int a = 7, int b = 100}) {
          return a + b;
        }
        int useDefaults() { return greet(); }
        int overrideOne() { return greet(a: 1); }
        int overrideBoth() { return greet(b: 2, a: 3); }
      ''';
        expect(await runFunction(src, 'useDefaults'), equals(107));
        expect(await runFunction(src, 'overrideOne'), equals(101));
        expect(await runFunction(src, 'overrideBoth'), equals(5));
      });

      test('optional positional parameter defaults', () async {
        var src = r'''
        int opt(int x, [int y = 9]) {
          return x * y;
        }
        int useDefault() { return opt(2); }
        int given() { return opt(2, 5); }
      ''';
        expect(await runFunction(src, 'useDefault'), equals(18));
        expect(await runFunction(src, 'given'), equals(10));
      });

      test('default value can be an expression', () async {
        var src = r'''
        int f({int a = 2 + 3}) {
          return a;
        }
        int run() { return f(); }
      ''';
        expect(await runFunction(src, 'run'), equals(5));
      });

      test('round-trips default values (named and optional)', () async {
        var src = r'''
        int greet({int a = 7, int b = 100}) {
          return a + b;
        }
        int opt(int x, [int y = 9]) {
          return x * y;
        }
        int run() { return greet() + opt(2); }
      ''';
        var regen = await regenDart(src);
        expect(regen, contains('int greet({int a = 7, int b = 100})'));
        expect(regen, contains('int opt(int x, [int y = 9])'));
        expect(await runFunction(regen, 'run'), equals(125));
      });

      test('constructor parameter defaults', () async {
        var src = r'''
        class Box {
          int w;
          int h;
          Box({this.w = 2, this.h = 3});
          int area() { return w * h; }
        }
        int useDefaults() {
          var b = Box();
          return b.area();
        }
        int override() {
          var b = Box(w: 5);
          return b.area();
        }
      ''';
        expect(await runFunction(src, 'useDefaults'), equals(6));
        expect(await runFunction(src, 'override'), equals(15));
      });
    });

    group('constructors', () {
      test('positional this.field constructor called by name', () async {
        var src = r'''
        class Point {
          int x;
          int y;
          Point(this.x, this.y);
          int sum() { return x + y; }
        }
        int run() {
          var p = Point(y: 20, x: 5);
          return p.sum();
        }
      ''';
        // Any parameter can be passed by name, regardless of order.
        expect(await runFunction(src, 'run'), equals(25));
      });

      test('named-parameter declaration {this.field}', () async {
        var src = r'''
        class Box {
          int w;
          int h;
          Box({this.w, this.h});
          int area() { return w * h; }
        }
        int run() {
          var b = Box(h: 4, w: 3);
          return b.area();
        }
      ''';
        expect(await runFunction(src, 'run'), equals(12));
      });

      test(
        'mixed positional + named typed params with body assignment',
        () async {
          var src = r'''
        class Rect {
          int a;
          int b;
          Rect(int x, {int y}) {
            this.a = x;
            this.b = y;
          }
          int area() { return a * b; }
        }
        int run() {
          var r = Rect(6, y: 7);
          return r.area();
        }
      ''';
          expect(await runFunction(src, 'run'), equals(42));
        },
      );

      test('round-trips named constructor declaration and call', () async {
        var src = r'''
        class Box {
          int w;
          int h;
          Box({this.w, this.h});
          int area() { return w * h; }
        }
        int run() {
          var b = Box(w: 3, h: 4);
          return b.area();
        }
      ''';
        var regen = await regenDart(src);
        expect(regen, contains('Box({this.w, this.h})'));
        expect(regen, contains('Box(w: 3, h: 4)'));
        expect(await runFunction(regen, 'run'), equals(12));
      });
    });

    group('named-argument edge cases', () {
      test('3+ named args supplied fully out of order bind by name', () async {
        var src = r'''
        int combine({int a, int b, int c}) {
          return a * 100 + b * 10 + c;
        }
        int run() {
          return combine(c: 3, a: 1, b: 2);
        }
      ''';
        // Each value binds to its name, not its position: a=1, b=2, c=3.
        expect(await runFunction(src, 'run'), equals(123));
      });

      test('named argument value is a nested call + expression', () async {
        var src = r'''
        int g(int x) {
          return x * x;
        }
        int f({int a}) {
          return a;
        }
        int run() {
          return f(a: g(2) + 1);
        }
      ''';
        // The named value `g(2) + 1` is evaluated as an expression (4 + 1).
        expect(await runFunction(src, 'run'), equals(5));
      });

      test('mixed positional then named, named ones reordered', () async {
        var src = r'''
        int calc(int base, int mul, {int add, int sub}) {
          return base * mul + add - sub;
        }
        int run() {
          return calc(5, 2, sub: 1, add: 3);
        }
      ''';
        // Positional 5,2 bind by position; add/sub bind by name though reversed.
        expect(await runFunction(src, 'run'), equals(12));
      });

      test('ternary positional argument is not misparsed as named', () async {
        // `cond ? 10 : 20` as a positional argument must stay a single
        // positional argument: the `:` belongs to the ternary, not a `name:`
        // separator.
        var src = r'''
        int pick(int v) {
          return v;
        }
        int run(bool cond) {
          return pick(cond ? 10 : 20);
        }
      ''';
        expect(
          await runFunction(src, 'run', positionalParameters: [true]),
          equals(10),
        );
        expect(
          await runFunction(src, 'run', positionalParameters: [false]),
          equals(20),
        );
      });

      // Dart allows named arguments at ANY position in the call's argument list
      // (before, between, or after the positional ones); the positional
      // arguments still fill the positional parameters left-to-right in their
      // own relative order.
      test('named arguments may appear at any position in the call', () async {
        var src = r'''
        int f(int a, int b, {int c}) {
          return a * 100 + b * 10 + c;
        }
        int standard() { return f(1, 2, c: 3); }
        int namedFirst() { return f(c: 3, 1, 2); }
        int interleaved() { return f(1, c: 3, 2); }
      ''';
        // In every case a=1, b=2 (positional order) and c=3 (by name) -> 123.
        expect(await runFunction(src, 'standard'), equals(123));
        expect(await runFunction(src, 'namedFirst'), equals(123));
        expect(await runFunction(src, 'interleaved'), equals(123));
      });

      test(
        'multiple positional args keep order when split by named args',
        () async {
          var src = r'''
        int order(int a, int b, int c, {int tag}) {
          return a * 1000 + b * 100 + c * 10 + tag;
        }
        int run() { return order(1, tag: 9, 2, 3); }
      ''';
          // Positional 1,2,3 -> a,b,c in appearance order despite the named arg
          // sitting between them; tag=9 by name.
          expect(await runFunction(src, 'run'), equals(1239));
        },
      );
    });

    group('default-value edge cases', () {
      test('default value that is a multiplication expression', () async {
        var src = r'''
        int f({int a = 2 * 3}) {
          return a;
        }
        int run() { return f(); }
      ''';
        expect(await runFunction(src, 'run'), equals(6));
      });

      test('multiple defaults, only one supplied', () async {
        var src = r'''
        int f({int a = 1, int b = 2, int c = 3}) {
          return a * 100 + b * 10 + c;
        }
        int run() { return f(b: 9); }
      ''';
        // a and c keep their defaults (1, 3); only b is overridden (9).
        expect(await runFunction(src, 'run'), equals(193));
      });

      test('constructor defaults partially supplied (Box(h: 9))', () async {
        var src = r'''
        class Box {
          int w;
          int h;
          Box({this.w = 2, this.h = 3});
          int area() { return w * h; }
        }
        int run() {
          var b = Box(h: 9);
          return b.area();
        }
      ''';
        // w keeps its default (2); h is overridden (9) -> 18.
        expect(await runFunction(src, 'run'), equals(18));
      });
    });
  });
}
