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
  group('Kotlin named arguments', () {
    test('called by name (order-independent)', () async {
      var src = r'''
        fun sub(a: Int, b: Int): Int {
          return a - b
        }

        fun callReversed(): Int {
          return sub(b = 3, a = 10)
        }
      ''';

      // Named arguments bind by name regardless of call-site order.
      expect(await runFunction(src, 'callReversed'), equals(7));
    });

    test('mixed positional + named arguments', () async {
      var src = r'''
        fun compute(base: Int, factor: Int): Int {
          return base * factor
        }

        fun run(): Int {
          return compute(5, factor = 3)
        }
      ''';

      expect(await runFunction(src, 'run'), equals(15));
    });

    test('equality operator in positional arg is not a named arg', () async {
      var src = r'''
        fun eq(flag: Boolean): Int {
          if (flag) {
            return 1
          } else {
            return 0
          }
        }

        fun run(): Int {
          val a = 2
          val b = 2
          return eq(a == b)
        }
      ''';

      // `a == b` must be parsed as a single positional argument (equality),
      // not as a named argument `a = (= b)`.
      expect(await runFunction(src, 'run'), equals(1));
    });

    test('round-trip generation preserves named call', () async {
      var src = r'''
        fun sub(a: Int, b: Int): Int {
          return a - b
        }

        fun callReversed(): Int {
          return sub(b = 3, a = 10)
        }
      ''';

      var regen = await regenKotlin(src);

      // Named argument syntax (`name = value`) is preserved at the call site.
      expect(regen, contains('sub(b = 3, a = 10)'));

      // The regenerated source re-parses and runs to the same result.
      expect(await runFunction(regen, 'callReversed'), equals(7));
    });
  });
}
