@TestOn('vm')
@Tags(['dart', 'javascript', 'kotlin'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Loads Dart [source], registers an async `delayMs(ms, v)` external returning a
/// real `Future<int>` (completes with `v` after `ms` ms), runs
/// [className].[method] and returns the resolved value and `print` output.
Future<({Object? value, List output})> _runDart(
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

  runner.externalFunctionMapper!
      .mapExternalFunction2<dynamic, dynamic, Future<int>>(
        ASTTypeFuture(ASTTypeInt.instance),
        'delayMs',
        ASTTypeDynamic.instance,
        'ms',
        ASTTypeDynamic.instance,
        'v',
        (ms, v) =>
            Future.delayed(Duration(milliseconds: ms as int), () => v as int),
      );

  // The entry methods are declared non-static, so provide a (field-less)
  // instance to run them — only `static` methods run without an instance.
  var astValue = await runner.executeClassMethod(
    '',
    className,
    method,
    positionalParameters: [args],
    classInstanceFields: const {},
  );
  return (value: await astValue.getValueNoContext(), output: output);
}

/// Translates Dart [source] into [language], returning all generated source.
Future<String> _translate(String source, String language) async {
  var vm = ApolloVM();
  await vm.loadCodeUnit(SourceCodeUnit('dart', source, id: 'test'));
  var cs = vm.generateAllCodeIn(language);
  var b = StringBuffer();
  for (var ns in await cs.getNamespaces()) {
    for (var id in await cs.getNamespaceCodeUnitsIDs(ns)) {
      b.write(await cs.getNamespaceCodeUnit(ns, id));
    }
  }
  return b.toString();
}

void main() {
  group('Dart async runtime (extra)', () {
    test('await inside a for loop accumulates', () async {
      var r = await _runDart(
        r'''
        class C {
          Future<int> run(List args) async {
            var total = 0;
            for (var i = 1; i <= 3; i = i + 1) {
              var x = await delayMs(1, i);
              total = total + x;
            }
            return total;
          }
        }
      ''',
        'C',
        'run',
      );
      expect(r.value, equals(6)); // 1+2+3
    });

    test('await inside an if branch', () async {
      var r = await _runDart(
        r'''
        class C {
          Future<int> run(List args) async {
            var n = 5;
            if (n > 3) {
              var x = await delayMs(1, 10);
              return x;
            }
            return 0;
          }
        }
      ''',
        'C',
        'run',
      );
      expect(r.value, equals(10));
    });

    test('await in an arithmetic expression', () async {
      var r = await _runDart(
        r'''
        class C {
          Future<int> run(List args) async {
            return await delayMs(1, 5) * 2 + 1;
          }
        }
      ''',
        'C',
        'run',
      );
      expect(r.value, equals(11)); // (5*2)+1
    });

    test('three-level nested async calls', () async {
      var r = await _runDart(
        r'''
        class C {
          Future<int> c(int x) async { var v = await delayMs(1, x); return v; }
          Future<int> b(int x) async { return await c(x) + 1; }
          Future<int> a(int x) async { return await b(x) + 1; }
          Future<int> run(List args) async { return await a(10); }
        }
      ''',
        'C',
        'run',
      );
      expect(r.value, equals(12)); // 10 -> 11 -> 12
    });

    test('futures stored then awaited out of order', () async {
      var r = await _runDart(
        r'''
        class C {
          Future<int> run(List args) async {
            var f = delayMs(20, 7);
            var g = delayMs(2, 3);
            var b = await g;
            var a = await f;
            return a + b;
          }
        }
      ''',
        'C',
        'run',
      );
      expect(r.value, equals(10)); // 7+3
    });

    test('await a void-returning async (no result used)', () async {
      var r = await _runDart(
        r'''
        class C {
          Future<void> step() async {
            await delayMs(1, 1);
          }
          Future<int> run(List args) async {
            await step();
            return 42;
          }
        }
      ''',
        'C',
        'run',
      );
      expect(r.value, equals(42));
    });

    test('print ordering across awaits is deterministic', () async {
      var r = await _runDart(
        r'''
        class C {
          Future<int> run(List args) async {
            print(1);
            await delayMs(1, 0);
            print(2);
            await delayMs(1, 0);
            print(3);
            return 0;
          }
        }
      ''',
        'C',
        'run',
      );
      expect(r.output, equals([1, 2, 3]));
    });
  });

  group('Dart -> JavaScript async translation (extra)', () {
    test('multiple awaits with a loop', () async {
      var js = await _translate(r'''
        class C {
          Future<int> step(int i) async { return i; }
          Future<int> run(List args) async {
            var total = 0;
            for (var i = 0; i < 3; i = i + 1) {
              total = total + await step(i);
            }
            return total;
          }
        }
      ''', 'javascript');
      expect(js, contains('async step('));
      expect(js, contains('async run('));
      expect(js, contains('await '));
      expect(js, contains('for ('));
    });

    test('top-level async functions', () async {
      var js = await _translate(r'''
        Future<int> compute() async { return 5; }
        Future<int> main(List args) async {
          var v = await compute();
          return v;
        }
      ''', 'javascript');
      expect(js, contains('async function compute('));
      expect(js, contains('async function main('));
      expect(js, contains('await '));
    });

    test('await in a return expression', () async {
      var js = await _translate(r'''
        class C {
          Future<int> run(List args) async {
            return await compute(args) + 1;
          }
        }
      ''', 'javascript');
      expect(js, contains('async run('));
      expect(js, contains('await '));
    });

    test('static async method keeps both modifiers', () async {
      var js = await _translate(r'''
        class C {
          static Future<int> run(List args) async {
            return await compute(args);
          }
        }
      ''', 'javascript');
      expect(js, contains('static async run('));
    });
  });

  group('Dart -> Kotlin async translation', () {
    test(
      'async method -> suspend fun, Future<T> -> T, await dropped',
      () async {
        var kt = await _translate(r'''
        class C {
          Future<int> compute(List args) async { return 5; }
          Future<int> run(List args) async {
            var x = await compute(args);
            return x + 1;
          }
        }
      ''', 'kotlin');
        expect(kt, contains('suspend fun compute('));
        expect(kt, contains('suspend fun run('));
        expect(kt, contains('): Int'));
        expect(kt, contains('var x = compute(args)')); // await dropped
        expect(kt, isNot(contains('await')));
        expect(kt, isNot(contains('Future')));
      },
    );

    test('top-level async functions -> suspend fun', () async {
      var kt = await _translate(r'''
        Future<int> compute() async { return 5; }
        Future<int> main(List args) async {
          var v = await compute();
          return v;
        }
      ''', 'kotlin');
      expect(kt, contains('suspend fun compute('));
      expect(kt, contains('suspend fun main('));
    });

    test('async with a loop + await -> suspend fun, await dropped', () async {
      var kt = await _translate(r'''
        class C {
          Future<int> step(int i) async { return i; }
          Future<int> run(List args) async {
            var total = 0;
            for (var i = 0; i < 3; i = i + 1) {
              total = total + await step(i);
            }
            return total;
          }
        }
      ''', 'kotlin');
      expect(kt, contains('suspend fun run('));
      expect(kt, contains('suspend fun step('));
      expect(kt, contains('for ('));
      expect(kt, isNot(contains('await')));
    });

    test('Future<void> async -> suspend fun with no return type', () async {
      var kt = await _translate(r'''
        class C {
          Future<void> ping() async {
            await beat();
          }
        }
      ''', 'kotlin');
      expect(kt, contains('suspend fun ping()'));
      expect(kt, isNot(contains(': Unit'))); // void/Unit return omitted
      expect(kt, isNot(contains('await')));
    });
  });

  group('Dart -> Dart async round-trip (extra)', () {
    test('multiple awaits round-trip', () async {
      var dart = await _translate(r'''
        class C {
          Future<int> run(List args) async {
            var a = await one(args);
            var b = await two(args);
            return a + b;
          }
        }
      ''', 'dart');
      expect(dart, contains(') async {'));
      // two await statements preserved.
      expect('await '.allMatches(dart).length, greaterThanOrEqualTo(2));
    });
  });
}
