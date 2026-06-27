@Tags(['dart', 'javascript', 'typescript', 'csharp', 'python'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Loads [src] in [language], runs `C.run(41)` (an `async` method that
/// `await`s `compute`), and returns the result. The entry method is non-static,
/// so it runs against a (field-less) instance.
Future<Object?> _runAsyncMethod(String language, String src) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit(language, src, id: 'test'));
  expect(ok, isTrue, reason: "Can't load $language source");
  var runner = vm.createRunner(language)!;
  var res = await runner.executeClassMethod(
    '',
    'C',
    'run',
    positionalParameters: [41],
    classInstanceFields: const {},
  );
  return res.getValueNoContext();
}

/// Regenerates the loaded [language] source from [src] as text.
Future<String> _regen(String language, String src, String target) async {
  var vm = ApolloVM();
  await vm.loadCodeUnit(SourceCodeUnit(language, src, id: 'test'));
  var storage = vm.generateAllCodeIn(target);
  return (await storage.writeAllSources()).toString();
}

void main() {
  // Each language declares an `async` method that `await`s another method.
  // ApolloVM parses `async`/`await`, executes via the shared async runtime
  // (`await` unwraps the awaitable), round-trips the source, and translates to
  // Dart (which keeps `async`/`await`).
  const cases = <({String lang, String label, String src})>[
    (
      lang: 'javascript',
      label: 'JavaScript',
      src: r'''
        class C {
          async compute(x) { return x + 1; }
          async run(args) {
            var v = await compute(args);
            return v;
          }
        }
      ''',
    ),
    (
      lang: 'typescript',
      label: 'TypeScript',
      src: r'''
        class C {
          async compute(x: number): Promise<number> { return x + 1; }
          async run(args: number): Promise<number> {
            let v = await compute(args);
            return v;
          }
        }
      ''',
    ),
    (
      lang: 'csharp',
      label: 'C#',
      src: r'''
        class C {
          int compute(int x) { return x + 1; }
          async Task<int> run(int args) {
            var v = await compute(args);
            return v;
          }
        }
      ''',
    ),
    (
      lang: 'python',
      label: 'Python',
      src: '''
class C:
    def compute(self, x):
        return x + 1
    async def run(self, args):
        v = await self.compute(args)
        return v
''',
    ),
  ];

  for (var c in cases) {
    group('${c.label}: async / await', () {
      test('parses + executes (await returns the value)', () async {
        expect(await _runAsyncMethod(c.lang, c.src), equals(42));
      });

      test('round-trips `async`/`await` back to ${c.label}', () async {
        var out = await _regen(c.lang, c.src, c.lang);
        expect(out, contains('async'));
        expect(out, contains('await '));
      });

      test('translates to Dart with `async`/`await`', () async {
        var dart = await _regen(c.lang, c.src, 'dart');
        expect(dart, contains('async'));
        expect(dart, contains('await '));
      });
    });
  }

  group('await keyword boundary', () {
    test('JavaScript: `awaiter` is an identifier, not `await er`', () async {
      var vm = ApolloVM();
      var ok = await vm.loadCodeUnit(
        SourceCodeUnit('javascript', r'''
          class C {
            run(args) {
              var awaiter = args + 1;
              return awaiter;
            }
          }
        ''', id: 'test'),
      );
      expect(ok, isTrue);
      var runner = vm.createRunner('javascript')!;
      var res = await runner.executeClassMethod(
        '',
        'C',
        'run',
        positionalParameters: [41],
        classInstanceFields: const {},
      );
      expect(res.getValueNoContext(), equals(42));
    });
  });

  group('await unwraps the awaitable type', () {
    // Regression: `await` on a method declared to return a named awaitable
    // (`Promise<T>` / `Task<T>` / `Future<T>`) must infer the value type `T`,
    // so assigning the awaited value to an inferred variable does not fail a
    // type cast. (TypeScript `Promise<number>` reproduces this.)
    test('TypeScript Promise<number> awaited into an inferred var', () async {
      expect(
        await _runAsyncMethod('typescript', r'''
          class C {
            async compute(x: number): Promise<number> { return x + 1; }
            async run(args: number): Promise<number> {
              let v = await compute(args);
              return v;
            }
          }
        '''),
        equals(42),
      );
    });
  });
}
