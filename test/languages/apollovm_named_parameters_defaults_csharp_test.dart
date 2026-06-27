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
  group('C# default parameter values', () {
    test('uses default when argument is omitted', () async {
      var src = r'''
        class Calc {
          int addOffset(int x, int a = 5) {
            return x + a;
          }

          int callWithoutDefault() {
            return addOffset(10);
          }

          int callWithDefault() {
            return addOffset(10, 100);
          }
        }
      ''';

      // Omitted -> uses the default (a = 5): 10 + 5 = 15.
      expect(await runMethod(src, 'Calc', 'callWithoutDefault'), equals(15));
      // Provided -> overrides the default (a = 100): 10 + 100 = 110.
      expect(await runMethod(src, 'Calc', 'callWithDefault'), equals(110));
    });

    test('default does not match equality operator (==)', () async {
      // The `== ` guard ensures the parameter parser does not greedily consume
      // an equality expression as a default value.
      var src = r'''
        class Calc {
          bool eq(int a, int b) {
            return a == b;
          }

          bool run() {
            return eq(3, 3);
          }
        }
      ''';

      expect(await runMethod(src, 'Calc', 'run'), equals(true));
    });

    group('round-trip code generation', () {
      test('regenerates default value and re-runs', () async {
        var src = r'''
        class Calc {
          int addOffset(int x, int a = 5) {
            return x + a;
          }

          int callWithoutDefault() {
            return addOffset(10);
          }
        }
      ''';

        var regen = await regenCSharp(src);

        // The default value survives regeneration (`int a = 5`).
        expect(regen, contains('int a = 5'));

        // The regenerated source re-parses and runs, still using the default.
        expect(
          await runMethod(regen, 'Calc', 'callWithoutDefault'),
          equals(15),
        );
      });
    });
  });
}
