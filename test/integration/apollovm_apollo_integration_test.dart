// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

@TestOn('vm')
@Tags(['apollo', 'dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// A pure-computation Apollo class kept within the subset that every target
/// language both generates and reparses+executes — no loops or collection
/// literals (mirrors `apollovm_transpile_execution_test`).
const _apolloSource = r'''
class Calc {
  Int branches(Int a) {
    if a > 10 { return 1 } else if a > 5 { return 2 } else { return 3 }
  }

  Int ops(Int a) {
    var c = a > 1 ? 1 : 0
    var neg = -a
    var bits = (a & 3) | (a ^ 1)
    return c + neg + bits
  }
}
''';

/// Targets whose generated source reparses AND executes `branches()` back to the
/// same value. Apollo generates idiomatic source for every language, so the full
/// matrix is covered here.
const _branchTargets = [
  'dart',
  'apollo',
  'java11',
  'javascript',
  'typescript',
  'csharp',
  'kotlin',
  'go',
  'lua',
  'python',
];

/// `ops()` applies unary negation (`-a`). Where the translated parameter carries
/// no static type (JavaScript, Lua) the runner rejects unary minus on a
/// `dynamic` value, and Python rejects the `num`→`double` cast — so those three
/// are excluded from the `ops()` matrix while remaining in [_branchTargets].
const _opsTargets = [
  'dart',
  'apollo',
  'java11',
  'typescript',
  'csharp',
  'kotlin',
  'go',
];

/// Loads [source] in [language] and runs `Calc.[method]([arg])`.
Future<Object?> _runMethod(
  String language,
  String source,
  String method,
  int arg,
) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit(language, source, id: 'test'));
  expect(ok, isTrue, reason: '$language: cannot parse source:\n$source');

  var runner = vm.createRunner(language)!;
  var astValue = await runner.executeClassMethod(
    '',
    'Calc',
    method,
    positionalParameters: [arg],
    classInstanceFields: const {},
  );
  return astValue.getValueNoContext();
}

/// Translates [vm]'s loaded code to [language] and returns the single unit.
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
  group('Apollo → every language: translate then execute', () {
    late ApolloVM apolloVm;

    setUp(() async {
      apolloVm = ApolloVM();
      var ok = await apolloVm.loadCodeUnit(
        SourceCodeUnit('apollo', _apolloSource, id: 'test'),
      );
      expect(ok, isTrue);
    });

    test('Apollo baseline computes reference values', () async {
      expect(
        await _runMethod('apollo', _apolloSource, 'branches', 12),
        equals(1),
      );
      expect(
        await _runMethod('apollo', _apolloSource, 'branches', 7),
        equals(2),
      );
      expect(
        await _runMethod('apollo', _apolloSource, 'branches', 3),
        equals(3),
      );
      expect(await _runMethod('apollo', _apolloSource, 'ops', 5), equals(1));
    });

    for (var target in _branchTargets) {
      test('$target: translated branches() executes identically', () async {
        var translated = await _translate(apolloVm, target);
        for (var input in [12, 7, 3]) {
          var apolloResult = await _runMethod(
            'apollo',
            _apolloSource,
            'branches',
            input,
          );
          var targetResult = await _runMethod(
            target,
            translated,
            'branches',
            input,
          );
          expect(
            targetResult,
            equals(apolloResult),
            reason: '$target branches($input) diverged from Apollo',
          );
        }
      });
    }

    for (var target in _opsTargets) {
      test('$target: translated ops() executes identically', () async {
        var translated = await _translate(apolloVm, target);
        for (var input in [5, 2, 0]) {
          var apolloResult = await _runMethod(
            'apollo',
            _apolloSource,
            'ops',
            input,
          );
          var targetResult = await _runMethod(target, translated, 'ops', input);
          expect(
            targetResult,
            equals(apolloResult),
            reason: '$target ops($input) diverged from Apollo',
          );
        }
      });
    }
  });

  group('every language → Apollo: translate then execute', () {
    // A portable `classify` in each source language; translating it to Apollo
    // must execute back to the same values, proving Apollo is a full round-trip
    // target (not just a source).
    Future<void> checkIntoApollo(String language, String source) async {
      var vm = ApolloVM();
      var ok = await vm.loadCodeUnit(SourceCodeUnit(language, source, id: 't'));
      expect(ok, isTrue, reason: '$language: cannot parse source');
      var apollo = await _translate(vm, 'apollo');

      for (var input in [-3, 0, 8]) {
        var srcResult = await _runMethod(language, source, 'classify', input);
        var apolloResult = await _runMethod(
          'apollo',
          apollo,
          'classify',
          input,
        );
        expect(
          apolloResult,
          equals(srcResult),
          reason: '$language → Apollo classify($input) diverged',
        );
      }
    }

    test('Dart → Apollo executes identically', () async {
      await checkIntoApollo('dart', r'''
class Calc {
  int classify(int n) {
    if (n < 0) { return 0; } else if (n == 0) { return 1; } else { return 2; }
  }
}
''');
    });

    test('Java → Apollo executes identically', () async {
      await checkIntoApollo('java11', r'''
class Calc {
  int classify(int n) {
    if (n < 0) { return 0; } else if (n == 0) { return 1; } else { return 2; }
  }
}
''');
    });

    test('Go → Apollo executes identically', () async {
      await checkIntoApollo('go', r'''
type Calc struct {
}

func (o *Calc) classify(n int) int {
  if n < 0 {
    return 0
  } else if n == 0 {
    return 1
  }
  return 2
}
''');
    });

    test('Kotlin → Apollo executes identically', () async {
      await checkIntoApollo('kotlin', r'''
class Calc {
  fun classify(n: Int): Int {
    if (n < 0) { return 0 } else if (n == 0) { return 1 } else { return 2 }
  }
}
''');
    });
  });

  group('Apollo cross-module execution', () {
    test('import class + function from other Apollo modules and run', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(
        SourceCodeUnit('apollo', r'''
class User {
  String name
  User(String name) {
    this.name = name
  }
  String greet() {
    return "Hi " + name
  }
}
''', id: 'user.apollo'),
      );
      await vm.loadCodeUnit(
        SourceCodeUnit('apollo', r'''
Int doubled(Int n) {
  return n * 2
}
''', id: 'helpers.apollo'),
      );
      await vm.loadCodeUnit(
        SourceCodeUnit('apollo', r'''
import 'user.apollo' show User
import 'helpers.apollo'

String run() {
  var u = User("bob")
  return u.greet() + " x" + doubled(21)
}
''', id: 'main.apollo'),
      );

      expect(vm.resolve(language: 'apollo'), isEmpty);

      var runner = vm.createRunner('apollo')!;
      var r = await runner.executeFunction('', 'run', positionalParameters: []);
      expect(r.getValueNoContext(), equals('Hi bob x42'));
    });
  });
}
