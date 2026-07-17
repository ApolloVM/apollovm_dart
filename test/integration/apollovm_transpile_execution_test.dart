@TestOn('vm')
@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// A pure-computation class (branches, ternary, unary and bitwise operators)
/// deliberately kept within the subset that every target language both
/// *generates* and *parses back* — no loops or collection literals, since
/// several grammars can't reparse those (see `apollovm_generator_matrix_test`).
const _dartSource = r'''
class Calc {
  int branches(int a) {
    if (a > 10) { return 1; } else if (a > 5) { return 2; } else { return 3; }
  }

  int ops(int a) {
    var c = a > 1 ? 1 : 0;
    var neg = -a;
    var bits = (a & 3) | (a ^ 1);
    return c + neg + bits;
  }
}
''';

/// Targets whose generated source reparses *and* executes `branches()` back to
/// the same result. Kotlin, Go, Lua and Python are excluded here: their
/// grammars/runners don't yet round-trip this construct set for execution
/// (tracked by the generation-only coverage in the generator matrix test).
const _branchTargets = ['java11', 'javascript', 'typescript', 'csharp'];

/// `ops()` additionally applies unary negation (`-a`) to the parameter. In
/// JavaScript the parameter carries no static type, and the runner rejects
/// unary minus on a `dynamic` value, so JS is excluded from the `ops()` matrix
/// while remaining in [_branchTargets].
const _opsTargets = ['java11', 'typescript', 'csharp'];

/// Loads [source] in [language] and runs [className].[method]([arg]),
/// returning the resolved native value. The method is non-static, so a
/// field-less instance is supplied.
Future<Object?> _runMethod(
  String language,
  String source,
  String className,
  String method,
  int arg,
) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit(language, source, id: 'test'));
  expect(ok, isTrue, reason: '$language: cannot parse source:\n$source');

  var runner = vm.createRunner(language)!;
  var astValue = await runner.executeClassMethod(
    '',
    className,
    method,
    positionalParameters: [arg],
    classInstanceFields: const {},
  );
  return astValue.getValueNoContext();
}

/// Translates a Dart [vm] to [language] and returns the single generated unit.
Future<String> _translate(ApolloVM vm, String language) async {
  var storage = vm.generateAllCodeIn(language);
  await storage.writeAllSources();

  var sources = <String>[];
  for (var ns in await storage.getNamespaces()) {
    for (var id in await storage.getNamespaceCodeUnitsIDs(ns)) {
      sources.add((await storage.getNamespaceCodeUnit(ns, id))!);
    }
  }
  expect(sources, hasLength(1), reason: '$language: expected one code unit');
  return sources.single;
}

void main() {
  group('Transpile Dart then execute in the target language', () {
    late ApolloVM dartVm;

    setUp(() async {
      dartVm = ApolloVM();
      var ok = await dartVm.loadCodeUnit(
        SourceCodeUnit('dart', _dartSource, id: 'test'),
      );
      expect(ok, isTrue);
    });

    // Baseline: the Dart source itself produces the reference results.
    test('Dart baseline computes reference values', () async {
      expect(
        await _runMethod('dart', _dartSource, 'Calc', 'branches', 12),
        equals(1),
      );
      expect(
        await _runMethod('dart', _dartSource, 'Calc', 'branches', 7),
        equals(2),
      );
      expect(
        await _runMethod('dart', _dartSource, 'Calc', 'branches', 3),
        equals(3),
      );
      expect(
        await _runMethod('dart', _dartSource, 'Calc', 'ops', 5),
        equals(1),
      );
    });

    for (var target in _branchTargets) {
      test('$target: translated branches() executes identically', () async {
        var translated = await _translate(dartVm, target);

        for (var input in [12, 7, 3]) {
          var dartResult = await _runMethod(
            'dart',
            _dartSource,
            'Calc',
            'branches',
            input,
          );
          var targetResult = await _runMethod(
            target,
            translated,
            'Calc',
            'branches',
            input,
          );
          expect(
            targetResult,
            equals(dartResult),
            reason: '$target branches($input) diverged from Dart',
          );
        }
      });
    }

    for (var target in _opsTargets) {
      test('$target: translated ops() executes identically', () async {
        var translated = await _translate(dartVm, target);

        for (var input in [5, 2, 0]) {
          var dartResult = await _runMethod(
            'dart',
            _dartSource,
            'Calc',
            'ops',
            input,
          );
          var targetResult = await _runMethod(
            target,
            translated,
            'Calc',
            'ops',
            input,
          );
          expect(
            targetResult,
            equals(dartResult),
            reason: '$target ops($input) diverged from Dart',
          );
        }
      });
    }
  });
}
