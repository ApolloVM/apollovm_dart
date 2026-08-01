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

    test('a `&&` null-check promotes for the then-block', () async {
      // `x != null && …` promotes `x` inside the block. The analyzer reads this
      // off `ASTExpressionLogicalAnd`.
      var f = await _analyze(
        '${cls}void run(A? a) { if (a != null && 1 > 0) { a.x; } }',
      );
      expect(_codes(f), isNot(contains('unchecked-nullable-access')));
    });

    test('promotes every variable a `&&` chain null-checks', () async {
      var f = await _analyze(
        '${cls}void run(A? a, A? b) { if (a != null && b != null) { a.x; b.x; } }',
      );
      expect(_codes(f), isNot(contains('unchecked-nullable-access')));
    });

    test('known limitation: promotion does not reach later operands of the '
        'condition itself', () async {
      // `a` is promoted for the *block*, but the condition is analyzed in the
      // enclosing scope, so the `a.x` sitting to the right of the `&&` is
      // still reported. Dart itself would accept this. Pinned so that
      // teaching the analyzer condition-order flow shows up as a change here.
      var f = await _analyze(
        '${cls}void run(A? a) { if (a != null && a.x > 0) { } }',
      );
      expect(_codes(f), contains('unchecked-nullable-access'));
    });

    test('`||` does not promote (either side may be the false one)', () async {
      // Only `&&` guarantees both operands held; `a != null || …` says nothing
      // about `a` inside the block.
      var f = await _analyze(
        '${cls}void run(A? a) { if (a != null || a.x > 0) { } }',
      );
      expect(_codes(f), contains('unchecked-nullable-access'));
    });

    test('`x == null &&` does not promote for the then-block', () async {
      var f = await _analyze(
        '${cls}void run(A? a) { if (a == null && a.x > 0) { } }',
      );
      expect(_codes(f), contains('unchecked-nullable-access'));
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

  group('class members are analyzed', () {
    // `ASTRoot` keeps classes outside `children`, so `root.descendantChildren`
    // never entered a class body: every method, getter and constructor went
    // unanalyzed. The rules below are already covered for top-level functions;
    // these assert they also fire inside a class.
    test('a static method body is analyzed', () async {
      var f = await _analyze(
        'class Foo { static void main(int a, int? b) { var c = a + b; } }',
      );
      expect(_codes(f), contains('unchecked-nullable-operand'));
    });

    test('an instance method body is analyzed', () async {
      var f = await _analyze('class Foo { void run() { int x = null; } }');
      expect(_codes(f), contains('null-to-non-nullable'));
    });

    test('a getter body is analyzed', () async {
      var f = await _analyze(
        'class Foo { int get value { int x = null; return x; } }',
      );
      expect(_codes(f), contains('null-to-non-nullable'));
    });

    test('a constructor body is analyzed', () async {
      var f = await _analyze('class Foo { Foo() { int x = null; } }');
      expect(_codes(f), contains('null-to-non-nullable'));
    });

    test('a clean class produces no findings', () async {
      var f = await _analyze(
        'class Foo { static int run(int? a, int b) { return (a ?? 0) + b; } }',
      );
      expect(f, isEmpty);
    });

    test('a top-level function is still analyzed', () async {
      var f = await _analyze('void run() { int x = null; }');
      expect(_codes(f), contains('null-to-non-nullable'));
    });

    test('a finding is not duplicated by the extra traversal', () async {
      // `analyze` walks root *and* each class; the dedup must keep one finding.
      var f = await _analyze('class Foo { void run() { int x = null; } }');
      expect(f.where((d) => d.code == 'null-to-non-nullable').length, 1);
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
