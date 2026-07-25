@TestOn('vm')
@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:apollovm/src/apollovm_code_generator.dart';
import 'package:apollovm/src/apollovm_code_storage.dart';
import 'package:test/test.dart';

/// The per-language spelling of the null literal, exercised directly on the
/// generators.
///
/// A generator exposes two null hooks: `generateASTExpressionNullValue` for a
/// `null` *expression*, and `generateASTValueNull` for a resolved `ASTValueNull`
/// *value*. Only the first is reached by generating whole programs, so the
/// second is covered here — the two must agree, or a `null` reaching the value
/// path would be spelled wrong (which is exactly how Lua ended up emitting the
/// undefined global `null`).
const _expected = <String, String>{
  'dart': 'null',
  'java11': 'null',
  'kotlin': 'null',
  'javascript': 'null',
  'typescript': 'null',
  'csharp': 'null',
  'go': 'nil',
  'lua': 'nil',
  'python': 'None',
};

ApolloCodeGenerator _generatorFor(String language) {
  var g = ApolloVM().createCodeGenerator(
    language,
    ApolloSourceCodeStorageMemory(),
  );
  expect(g, isNotNull, reason: 'no code generator for `$language`');
  return g!;
}

void main() {
  group('null literal spelling', () {
    for (var entry in _expected.entries) {
      var language = entry.key;
      var spelling = entry.value;

      test('$language spells the null *expression* `$spelling`', () {
        var out = _generatorFor(
          language,
        ).generateASTExpressionNullValue(ASTExpressionNullValue());
        expect(out.toString(), spelling);
      });

      test('$language spells the null *value* `$spelling`', () {
        var out = _generatorFor(
          language,
        ).generateASTValueNull(ASTValueNull.instance);
        expect(out.toString(), spelling);
      });
    }

    test('an indented null expression carries its indent', () {
      var out = _generatorFor('lua').generateASTExpressionNullValue(
        ASTExpressionNullValue(),
        indent: '    ',
      );
      expect(out.toString(), '    nil');
    });
  });
}
