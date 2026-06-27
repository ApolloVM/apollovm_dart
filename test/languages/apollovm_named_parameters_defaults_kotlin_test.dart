// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

@TestOn('vm')
@Tags(['kotlin'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Loads a single Kotlin [source] and runs the top-level [function], returning
/// the resolved native return value.
Future<Object?> runFunction(
  String source,
  String function, {
  List positionalParameters = const [],
  Map? namedParameters,
}) async {
  var vm = ApolloVM();
  var loadOK = await vm.loadCodeUnit(
    SourceCodeUnit('kotlin', source, id: 'test'),
  );
  expect(loadOK, isTrue, reason: "Can't load Kotlin source!");

  var runner = vm.createRunner('kotlin')!;

  var astValue = await runner.executeFunction(
    '',
    function,
    positionalParameters: positionalParameters,
    namedParameters: namedParameters,
  );

  return astValue.getValueNoContext();
}

/// Translates a loaded Kotlin [source] back into Kotlin, returning the single
/// generated source unit (raw, loadable code — not the multi-source wrapper).
Future<String> regenKotlin(String source) async {
  var vm = ApolloVM();
  await vm.loadCodeUnit(SourceCodeUnit('kotlin', source, id: 'test'));

  var codeStorage = vm.generateAllCodeIn('kotlin');

  var buffer = StringBuffer();
  for (var ns in await codeStorage.getNamespaces()) {
    for (var id in await codeStorage.getNamespaceCodeUnitsIDs(ns)) {
      buffer.write(await codeStorage.getNamespaceCodeUnit(ns, id));
    }
  }
  return buffer.toString();
}

void main() {
  group('Kotlin parameter default values', () {
    test('default is used when the argument is omitted', () async {
      var src = r'''
        fun greet(a: Int = 7): Int {
          return a
        }

        fun useDefault(): Int {
          return greet()
        }
      ''';

      expect(await runFunction(src, 'useDefault'), equals(7));
    });

    test('positional argument overrides the default', () async {
      var src = r'''
        fun greet(a: Int = 7): Int {
          return a
        }

        fun overridePositional(): Int {
          return greet(10)
        }
      ''';

      expect(await runFunction(src, 'overridePositional'), equals(10));
    });

    test('named argument overrides the default', () async {
      var src = r'''
        fun greet(a: Int = 7): Int {
          return a
        }

        fun overrideNamed(): Int {
          return greet(a = 10)
        }
      ''';

      expect(await runFunction(src, 'overrideNamed'), equals(10));
    });

    test('multiple parameters mixing defaults and overrides', () async {
      var src = r'''
        fun combine(a: Int = 7, b: Int = 100): Int {
          return a + b
        }

        fun useDefaults(): Int {
          return combine()
        }

        fun overrideFirst(): Int {
          return combine(1)
        }

        fun overrideSecond(): Int {
          return combine(b = 2)
        }
      ''';

      expect(await runFunction(src, 'useDefaults'), equals(107));
      expect(await runFunction(src, 'overrideFirst'), equals(101));
      expect(await runFunction(src, 'overrideSecond'), equals(9));
    });

    test('default value can be an expression', () async {
      var src = r'''
        fun f(a: Int = 2 + 3): Int {
          return a
        }

        fun run(): Int {
          return f()
        }
      ''';

      expect(await runFunction(src, 'run'), equals(5));
    });

    test('default value survives round-trip code generation', () async {
      var src = r'''
        fun greet(a: Int = 7): Int {
          return a
        }

        fun useDefault(): Int {
          return greet()
        }
      ''';

      var regen = await regenKotlin(src);

      // The default value is preserved in the regenerated declaration.
      expect(regen, contains('a: Int = 7'));

      // The regenerated source re-parses and runs to the same result.
      expect(await runFunction(regen, 'useDefault'), equals(7));
    });
  });
}
