@TestOn('vm')
@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

Future<List<NullSafetyDiagnostic>> _analyze(String source) async {
  var parser = ApolloVM().getParser<String>('dart')!;
  var result = await parser.parse(SourceCodeUnit('dart', source, id: 't'));
  expect(result.isOK, isTrue, reason: 'cannot parse: $source');
  return NullSafetyAnalyzer().analyze(result.root!);
}

Iterable<String> _codes(List<NullSafetyDiagnostic> f) => f.map((e) => e.code);

void main() {
  group('null-to-non-nullable', () {
    test('flags null assigned to a non-nullable local', () async {
      var f = await _analyze('void run() { int x = null; }');
      expect(_codes(f), contains('null-to-non-nullable'));
    });

    test('allows null assigned to a nullable local', () async {
      var f = await _analyze('void run() { int? x = null; }');
      expect(_codes(f), isNot(contains('null-to-non-nullable')));
    });

    test('allows null assigned to var / dynamic / Object', () async {
      expect(
        _codes(await _analyze('void run() { var x = null; }')),
        isNot(contains('null-to-non-nullable')),
      );
      expect(
        _codes(await _analyze('void run() { dynamic x = null; }')),
        isNot(contains('null-to-non-nullable')),
      );
    });
  });

  group('unchecked nullable access + flow promotion', () {
    const cls = 'class A { int x = 1; int f() { return x; } } ';

    test('flags unconditional member access on a nullable parameter', () async {
      var f = await _analyze('${cls}void run(A? a) { a.x; }');
      expect(_codes(f), contains('unchecked-nullable-access'));
    });

    test('flags unconditional method call on a nullable parameter', () async {
      var f = await _analyze('${cls}void run(A? a) { a.f(); }');
      expect(_codes(f), contains('unchecked-nullable-access'));
    });

    test('promotes inside if (x != null)', () async {
      var f = await _analyze(
        '${cls}void run(A? a) { if (a != null) { a.x; } }',
      );
      expect(_codes(f), isNot(contains('unchecked-nullable-access')));
    });

    test('promotes in else of if (x == null)', () async {
      var f = await _analyze(
        '${cls}void run(A? a) { if (a == null) { return; } else { a.x; } }',
      );
      expect(_codes(f), isNot(contains('unchecked-nullable-access')));
    });

    test('?. suppresses the diagnostic', () async {
      var f = await _analyze('${cls}void run(A? a) { a?.x; }');
      expect(_codes(f), isNot(contains('unchecked-nullable-access')));
    });

    test('! (assertion) suppresses the diagnostic', () async {
      var f = await _analyze('${cls}void run(A? a) { a!.x; }');
      expect(_codes(f), isNot(contains('unchecked-nullable-access')));
    });

    test('non-nullable parameter is never flagged', () async {
      var f = await _analyze('${cls}void run(A a) { a.x; }');
      expect(_codes(f), isNot(contains('unchecked-nullable-access')));
    });
  });
}
