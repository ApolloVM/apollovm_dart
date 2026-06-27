// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

@TestOn('vm')
@Tags(['dart', 'kotlin', 'csharp', 'python'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Loads [source] in [fromLang] and translates (regenerates) it into [toLang],
/// returning the single generated source unit for namespace '' / id 'test'.
Future<String> translate(String fromLang, String source, String toLang) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit(fromLang, source, id: 'test'));
  expect(ok, isTrue, reason: "Can't load $fromLang source!");
  var codeUnit = await vm
      .generateAllCodeIn(toLang)
      .getNamespaceCodeUnit('', 'test');
  expect(codeUnit, isNotNull, reason: 'No generated $toLang code unit.');
  return codeUnit!;
}

/// Reloads [source] in [lang] and runs the top-level [function].
Future<Object?> runFunction(
  String lang,
  String source,
  String function, {
  List positionalParameters = const [],
}) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit(lang, source, id: 'test'));
  expect(ok, isTrue, reason: 'Generated $lang source should reload:\n$source');
  var runner = vm.createRunner(lang)!;
  var astValue = await runner.executeFunction(
    '',
    function,
    positionalParameters: positionalParameters,
  );
  return astValue.getValueNoContext();
}

/// Reloads [source] in [lang] and runs [method] of [className].
Future<Object?> runMethod(
  String lang,
  String source,
  String className,
  String method, {
  List positionalParameters = const [],
}) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit(lang, source, id: 'test'));
  expect(ok, isTrue, reason: 'Generated $lang source should reload:\n$source');
  var runner = vm.createRunner(lang)!;
  var astValue = await runner.executeClassMethod(
    '',
    className,
    method,
    positionalParameters: positionalParameters,
    classInstanceFields: const {},
  );
  return astValue.getValueNoContext();
}

void main() {
  // ----------------------------------------------------------------------
  // Named arguments at the call site, translated across languages. Each
  // language renders the binding with its own separator:
  //   Dart/C#:  name: value      Kotlin: name = value      Python: name=value
  // ----------------------------------------------------------------------
  group('named-call translation', () {
    const dartNamedCall = r'''
      int sub(int a, int b) {
        return a - b;
      }
      int run() {
        return sub(b: 3, a: 10);
      }
    ''';

    test('Dart -> Kotlin renders `name = value` and round-trips', () async {
      var kotlin = await translate('dart', dartNamedCall, 'kotlin');
      // Kotlin uses `=` as the named-argument separator.
      expect(kotlin, contains('sub(b = 3, a = 10)'));
      // The translated source reloads and computes the same result (10 - 3).
      expect(await runFunction('kotlin', kotlin, 'run'), equals(7));
    });

    test('Dart -> Python renders `name=value` and round-trips', () async {
      var python = await translate('dart', dartNamedCall, 'python');
      // Python uses `=` (no spaces) as the keyword-argument separator.
      expect(python, contains('sub(b=3, a=10)'));
      expect(await runFunction('python', python, 'run'), equals(7));
    });

    test('Dart -> C# renders `name: value` and round-trips', () async {
      // C# has no top-level functions, so the code under test lives in a class.
      const dartClass = r'''
        class Calc {
          int sub(int a, int b) {
            return a - b;
          }
          int run() {
            return sub(b: 3, a: 10);
          }
        }
      ''';
      var csharp = await translate('dart', dartClass, 'csharp');
      // C# uses `:` as the named-argument separator.
      expect(csharp, contains('sub(b: 3, a: 10)'));
      expect(await runMethod('csharp', csharp, 'Calc', 'run'), equals(7));
    });
  });

  // ----------------------------------------------------------------------
  // Default parameter values translated across languages. Each language keeps
  // the `= value` (Dart/Kotlin/C#) / `=value` (Python) default in the
  // declaration, and an omitted argument still resolves to the default.
  // ----------------------------------------------------------------------
  group('default-value translation', () {
    test('Dart -> Kotlin keeps default and runs with it', () async {
      // A Dart named-default declaration renders as `a: Int = 5` in Kotlin.
      const dartDefault = r'''
        int f(int a = 5) {
          return a;
        }
        int run() {
          return f();
        }
      ''';
      var kotlin = await translate('dart', dartDefault, 'kotlin');
      // The ` = 5` default survives translation into Kotlin.
      expect(kotlin, contains('a: Int = 5'));
      expect(await runFunction('kotlin', kotlin, 'run'), equals(5));
    });

    test('Dart -> C# keeps `int a = 5` default and runs with it', () async {
      const dartClass = r'''
        class Calc {
          int addOffset(int x, int a = 5) {
            return x + a;
          }
          int run() {
            return addOffset(10);
          }
        }
      ''';
      var csharp = await translate('dart', dartClass, 'csharp');
      // The C# default declaration `int a = 5` survives translation.
      expect(csharp, contains('int a = 5'));
      // Omitted argument -> default (5): 10 + 5 = 15.
      expect(await runMethod('csharp', csharp, 'Calc', 'run'), equals(15));
    });

    test('Kotlin -> Dart keeps default and runs with it', () async {
      const kotlin = r'''
        fun greet(a: Int = 7, b: Int = 100): Int {
          return a + b
        }
        fun run(): Int {
          return greet(b = 2)
        }
      ''';
      var dart = await translate('kotlin', kotlin, 'dart');
      // Defaults survive into Dart as `int a = 7` / `int b = 100`.
      expect(dart, contains('int a = 7'));
      expect(dart, contains('int b = 100'));
      // a keeps its default (7); b overridden by name (2) -> 9.
      expect(await runFunction('dart', dart, 'run'), equals(9));
    });

    test(
      'C# default + named call -> Kotlin / Dart / Python all round-trip',
      () async {
        const csharp = r'''
          class Calc {
            int foo(int a = 5, int b = 1) {
              return a + b;
            }
            int run() {
              return foo(b: 2, a: 10);
            }
          }
        ''';

        var kotlin = await translate('csharp', csharp, 'kotlin');
        expect(kotlin, contains('a: Int = 5'));
        expect(kotlin, contains('foo(b = 2, a = 10)'));
        expect(await runMethod('kotlin', kotlin, 'Calc', 'run'), equals(12));

        var dart = await translate('csharp', csharp, 'dart');
        expect(dart, contains('int a = 5'));
        expect(dart, contains('foo(b: 2, a: 10)'));
        expect(await runMethod('dart', dart, 'Calc', 'run'), equals(12));

        var python = await translate('csharp', csharp, 'python');
        expect(python, contains('a: int=5'));
        expect(python, contains('foo(b=2, a=10)'));
        expect(await runMethod('python', python, 'Calc', 'run'), equals(12));
      },
    );
  });

  // ----------------------------------------------------------------------
  // Dart's named/optional parameter GROUPS (`{...}` / `[...]`) have no syntax in
  // the target languages, so they are flattened into a normal positional
  // parameter list (keeping defaults). These previously regressed (Python
  // dropped the group entirely; Kotlin lost the comma) — now fixed.
  // ----------------------------------------------------------------------
  group('parameter groups flatten when translated', () {
    test(
      'Dart named-param group {int a = 5} -> Python keeps the parameter',
      () async {
        const dart = r'''
          int f({int a = 5}) {
            return a;
          }
          int run() {
            return f();
          }
        ''';
        var python = await translate('dart', dart, 'python');
        // The named-group parameter is kept (Python annotates the type): the
        // default `=5` survives and the function reloads and runs.
        expect(python, contains('a: int=5'));
        expect(await runFunction('python', python, 'run'), equals(5));
      },
    );

    test(
      'Dart optional-positional [int y = 3] -> Kotlin keeps the separator',
      () async {
        const dart = r'''
          int g(int x, [int y = 3]) {
            return x + y;
          }
          int run() {
            return g(10);
          }
        ''';
        var kotlin = await translate('dart', dart, 'kotlin');
        expect(kotlin, contains('x: Int, y: Int = 3'));
        expect(await runFunction('kotlin', kotlin, 'run'), equals(13));
      },
    );
  });
}
