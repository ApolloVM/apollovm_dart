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

  group('nullable-to-non-nullable', () {
    test(
      'flags a nullable variable assigned to a non-nullable local',
      () async {
        // The `null` *literal* was already caught; a nullable-typed *value* is
        // the same error one step removed.
        var f = await _analyze('void run(int? a) { int x = a; }');
        expect(_codes(f), contains('nullable-to-non-nullable'));
      },
    );

    test('allows it into a nullable / var slot', () async {
      expect(
        _codes(await _analyze('void run(int? a) { int? x = a; }')),
        isNot(contains('nullable-to-non-nullable')),
      );
      expect(
        _codes(await _analyze('void run(int? a) { var x = a; }')),
        isNot(contains('nullable-to-non-nullable')),
      );
    });

    test('a non-nullable source is never flagged', () async {
      var f = await _analyze('void run(int a) { int x = a; }');
      expect(_codes(f), isNot(contains('nullable-to-non-nullable')));
    });

    test('`!` / `??` / a null check suppress it', () async {
      expect(
        _codes(await _analyze('void run(int? a) { int x = a!; }')),
        isNot(contains('nullable-to-non-nullable')),
      );
      expect(
        _codes(await _analyze('void run(int? a) { int x = a ?? 0; }')),
        isNot(contains('nullable-to-non-nullable')),
      );
      expect(
        _codes(
          await _analyze('void run(int? a) { if (a != null) { int x = a; } }'),
        ),
        isNot(contains('nullable-to-non-nullable')),
      );
    });
  });

  group('unchecked-nullable-operand', () {
    test('flags a nullable operand in arithmetic', () async {
      var f = await _analyze(
        'void run(int? a, int b) { int? x = a; int? y = b; '
        'var base = x + (y ?? 0); print(base); }',
      );
      expect(_codes(f), contains('unchecked-nullable-operand'));
    });

    test('flags a nullable operand on either side', () async {
      expect(
        _codes(await _analyze('void run(int? a) { var v = 1 + a; }')),
        contains('unchecked-nullable-operand'),
      );
    });

    test('`!` suppresses it', () async {
      var f = await _analyze(
        'void run(int? a, int b) { int? x = a; int? y = b; '
        'var base = x! + (y ?? 0); print(base); }',
      );
      expect(_codes(f), isNot(contains('unchecked-nullable-operand')));
    });

    test('`??`, `==` and `!=` accept a nullable operand', () async {
      // These operators exist precisely to handle a nullable value.
      expect(
        _codes(await _analyze('void run(int? a) { var v = a ?? 0; }')),
        isNot(contains('unchecked-nullable-operand')),
      );
      expect(
        _codes(await _analyze('void run(int? a) { var v = a == null; }')),
        isNot(contains('unchecked-nullable-operand')),
      );
      expect(
        _codes(await _analyze('void run(int? a) { var v = a != null; }')),
        isNot(contains('unchecked-nullable-operand')),
      );
    });

    test('a null check promotes the variable', () async {
      var f = await _analyze(
        'void run(int? a) { if (a != null) { var v = a + 1; } }',
      );
      expect(_codes(f), isNot(contains('unchecked-nullable-operand')));
    });

    test('a non-nullable operand is never flagged', () async {
      var f = await _analyze('void run(int a, int b) { var v = a + b; }');
      expect(_codes(f), isNot(contains('unchecked-nullable-operand')));
    });
  });
}
