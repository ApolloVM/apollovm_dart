@TestOn('vm')
@Tags(['csharp'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Loads a single C# [source] and runs [method] of [className], returning the
/// resolved native return value.
///
/// C# has no top-level functions, so the code under test lives in a class and
/// is invoked through [ApolloRunner.executeClassMethod].
Future<Object?> runMethod(
  String source,
  String className,
  String method, {
  List positionalParameters = const [],
  Map? namedParameters,
}) async {
  var vm = ApolloVM();
  var loadOK = await vm.loadCodeUnit(
    SourceCodeUnit('csharp', source, id: 'test'),
  );
  expect(loadOK, isTrue, reason: "Can't load C# source!");

  var runner = vm.createRunner('csharp')!;

  var astValue = await runner.executeClassMethod(
    '',
    className,
    method,
    positionalParameters: positionalParameters,
    namedParameters: namedParameters,
    classInstanceFields: const {},
  );

  return astValue.getValueNoContext();
}

/// Translates a loaded C# [source] back into C#, returning the single
/// generated source unit (raw, loadable code — not the multi-source wrapper).
Future<String> regenCSharp(String source) async {
  var vm = ApolloVM();
  await vm.loadCodeUnit(SourceCodeUnit('csharp', source, id: 'test'));

  var codeStorage = vm.generateAllCodeIn('csharp');

  var buffer = StringBuffer();
  for (var ns in await codeStorage.getNamespaces()) {
    for (var id in await codeStorage.getNamespaceCodeUnitsIDs(ns)) {
      buffer.write(await codeStorage.getNamespaceCodeUnit(ns, id));
    }
  }
  return buffer.toString();
}

void main() {
  group('C# named arguments', () {
    test('called by name (order-independent)', () async {
      var src = r'''
        class Calc {
          int sub(int a, int b) {
            return a - b;
          }

          int callForward() {
            return sub(a: 10, b: 3);
          }

          int callReversed() {
            return sub(b: 3, a: 10);
          }
        }
      ''';

      expect(await runMethod(src, 'Calc', 'callForward'), equals(7));
      // Named arguments bind by name regardless of call-site order.
      expect(await runMethod(src, 'Calc', 'callReversed'), equals(7));
    });

    test('mixed positional + named arguments', () async {
      var src = r'''
        class Calc {
          int compute(int base, int factor, int offset) {
            return base * factor + offset;
          }

          int run() {
            return compute(5, offset: 1, factor: 3);
          }
        }
      ''';

      expect(await runMethod(src, 'Calc', 'run'), equals(16));
    });

    test('positional ternary argument is not misparsed as named', () async {
      // `cond ? a : b` as a positional argument must stay a single positional
      // argument: after `cond` the next token is `?` (not `:`), so the
      // `name:` prefix backtracks.
      var src = r'''
        class Calc {
          int pick(int v) {
            return v;
          }

          int run(bool cond) {
            return pick(cond ? 10 : 20);
          }
        }
      ''';

      expect(
        await runMethod(src, 'Calc', 'run', positionalParameters: [true]),
        equals(10),
      );
      expect(
        await runMethod(src, 'Calc', 'run', positionalParameters: [false]),
        equals(20),
      );
    });

    group('round-trip code generation', () {
      test('regenerates named call syntax', () async {
        var src = r'''
        class Calc {
          int withPositional(int x, int y) {
            return x * y;
          }

          int run() {
            return withPositional(4, y: 7);
          }
        }
      ''';

        var regen = await regenCSharp(src);

        // Named argument syntax (`name: value`) is preserved at the call site.
        expect(regen, contains('withPositional(4, y: 7)'));

        // The regenerated source re-parses and runs to the same result.
        expect(await runMethod(regen, 'Calc', 'run'), equals(28));
      });

      test('regenerates reversed named call', () async {
        var src = r'''
        class Calc {
          int sub(int a, int b) {
            return a - b;
          }

          int run() {
            return sub(b: 3, a: 10);
          }
        }
      ''';

        var regen = await regenCSharp(src);
        expect(regen, contains('a: 10'));
        expect(regen, contains('b: 3'));
        expect(await runMethod(regen, 'Calc', 'run'), equals(7));
      });
    });
  });
}
