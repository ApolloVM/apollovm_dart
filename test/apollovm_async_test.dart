@TestOn('vm')
@Tags(['dart', 'javascript', 'kotlin'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Loads a single Dart [source], registers an async `delayMs(ms, v)` external
/// (returns a real `Future<int>` completing with `v` after `ms` milliseconds),
/// runs [className].[method] and returns the resolved (awaited) value plus the
/// collected `print` output (in completion order).
Future<({Object? value, List output})> runDartAsync(
  String source,
  String className,
  String method, {
  List args = const [],
}) async {
  var vm = ApolloVM();
  var loadOK = await vm.loadCodeUnit(
    SourceCodeUnit('dart', source, id: 'test'),
  );
  expect(loadOK, isTrue, reason: "Can't load Dart source!");

  var runner = vm.createRunner('dart')!;

  var output = [];
  runner.externalPrintFunction = (o) => output.add(o);

  // Param types are `dynamic` so calls with variable (dynamic-typed) arguments
  // resolve the external by signature.
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

  var astValue = await runner.executeClassMethod(
    '',
    className,
    method,
    positionalParameters: [args],
  );

  return (value: await astValue.getValueNoContext(), output: output);
}

void main() {
  group('async/await runtime', () {
    test('await a delayed Future returns its value', () async {
      var r = await runDartAsync(
        r'''
        class Async {
          Future<int> run(List args) async {
            var x = await delayMs(5, 42);
            return x;
          }
        }
      ''',
        'Async',
        'run',
      );

      expect(r.value, equals(42));
    });

    test(
      'real suspension: non-awaited calls complete by delay order',
      () async {
        // `slow(30,1)` and `slow(5,2)` are started but not awaited. With real
        // asynchrony the 5ms call completes (and prints) before the 30ms one,
        // so the print order is [2, 1]. Eager evaluation would print [1, 2].
        var r = await runDartAsync(
          r'''
        class Async {
          Future<int> slow(int ms, int v) async {
            await delayMs(ms, v);
            print(v);
            return v;
          }

          Future<int> run(List args) async {
            var a = slow(30, 1);
            var b = slow(5, 2);
            await a;
            await b;
            return 0;
          }
        }
      ''',
          'Async',
          'run',
        );

        expect(r.output, equals([2, 1]));
      },
    );

    test('await chains across async functions', () async {
      var r = await runDartAsync(
        r'''
        class Async {
          Future<int> twice(int v) async {
            var d = await delayMs(2, v);
            return d + d;
          }

          Future<int> run(List args) async {
            var a = await twice(10);
            var b = await twice(a);
            return b;
          }
        }
      ''',
        'Async',
        'run',
      );

      expect(r.value, equals(40));
    });

    test('top-level async function', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(
        SourceCodeUnit('dart', r'''
          Future<int> compute() async {
            return 10;
          }

          Future<int> main(List args) async {
            var v = await compute();
            return v + 1;
          }
        ''', id: 'test'),
      );

      var runner = vm.createRunner('dart')!;
      var astValue = await runner.executeFunction(
        '',
        'main',
        positionalParameters: [[]],
      );

      expect(await astValue.getValueNoContext(), equals(11));
    });
  });

  group('async/await parsing', () {
    test('`await` does not swallow identifiers like `awaiter`', () async {
      var r = await runDartAsync(
        r'''
        class Async {
          int run(List args) {
            var awaiter = 5;
            return awaiter + 1;
          }
        }
      ''',
        'Async',
        'run',
      );

      expect(r.value, equals(6));
    });
  });

  group('async/await translation', () {
    test('Dart -> Dart round-trip preserves async/await', () async {
      var generated = await _translateDart(r'''
        class Async {
          Future<int> run(List args) async {
            var x = await compute(args);
            return x;
          }
        }
      ''', 'dart');

      expect(generated, contains(') async {'));
      expect(generated, contains('await '));
    });

    test('Dart -> JavaScript emits async function / await', () async {
      var generated = await _translateDart(r'''
        class Async {
          Future<int> run(List args) async {
            var x = await compute(args);
            return x;
          }
        }
      ''', 'javascript');

      expect(generated, contains('async run('));
      expect(generated, contains('await '));
    });

    test('Dart -> Kotlin emits suspend fun and drops await', () async {
      var kt = await _translateDart(r'''
          class Async {
            Future<int> run(List args) async {
              return await compute(args);
            }
          }
        ''', 'kotlin');
      // `async` -> `suspend fun`; `Future<int>` -> `Int`; `await x` -> `x`.
      expect(kt, contains('suspend fun run('));
      expect(kt, contains('): Int'));
      expect(kt, contains('return compute(args)'));
      expect(kt, isNot(contains('await')));
    });
  });
}

/// Translates a loaded Dart [source] into [language] and returns all generated
/// source text.
Future<String> _translateDart(String source, String language) async {
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
