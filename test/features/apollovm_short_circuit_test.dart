@TestOn('vm')
@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Short-circuiting is only observable through a side effect: an operator that
/// wrongly evaluates its right operand still returns the right *value* for
/// every one of these programs. Each test therefore counts calls to `bump()`
/// rather than asserting the result alone.
///
/// This is the defining property of [ASTExpressionNullCoalesce],
/// [ASTExpressionLogicalAnd] and [ASTExpressionLogicalOr] — the reason they are
/// nodes of their own instead of operators on [ASTExpressionOperation], whose
/// evaluation runs both operands before dispatching.
const _cls = r'''
class S {
  int calls = 0;
  bool bump() { calls = calls + 1; return true; }
  int bumpInt() { calls = calls + 1; return 99; }
  bool bumpFalse() { calls = calls + 1; return false; }
  EXPR
}
''';

/// Runs `S.run()` with [body] as its statements and returns its value.
Future<Object?> _run(String body) async {
  var vm = ApolloVM();
  var src = _cls.replaceFirst('EXPR', 'int run() { $body }');
  expect(
    await vm.loadCodeUnit(SourceCodeUnit('dart', src, id: 'test')),
    isTrue,
    reason: 'cannot parse: $src',
  );

  var runner = vm.createRunner('dart')!;
  var r = await runner.executeClassMethod(
    '',
    'S',
    'run',
    positionalParameters: [],
    classInstanceFields: const {},
  );
  return r.getValueNoContext();
}

/// Runs `S.probe()` which returns `calls` after evaluating [expr], so the
/// number of evaluations of the right operand is what is asserted.
Future<int> _calls(String expr) async {
  var vm = ApolloVM();
  var src = _cls.replaceFirst(
    'EXPR',
    'int probe() { var r = $expr; return calls; }',
  );
  expect(
    await vm.loadCodeUnit(SourceCodeUnit('dart', src, id: 'test')),
    isTrue,
    reason: 'cannot parse: $src',
  );

  var runner = vm.createRunner('dart')!;
  var r = await runner.executeClassMethod(
    '',
    'S',
    'probe',
    positionalParameters: [],
    classInstanceFields: const {},
  );
  return r.getValueNoContext() as int;
}

void main() {
  group('the call counter itself works', () {
    // Without these, every "never evaluated" assertion below would pass even if
    // the counter were broken and stuck at 0.
    test('an evaluated operand increments the counter', () async {
      expect(await _calls('bumpInt()'), equals(1));
      expect(await _calls('bump() && bump()'), equals(2));
      expect(await _calls('bumpInt() ?? bumpInt()'), equals(1));
    });
  });

  group('`??` evaluates its right operand only when the left is null', () {
    test('non-null left: right operand is never evaluated', () async {
      expect(await _calls('7 ?? bumpInt()'), equals(0));
    });

    test('null left: right operand is evaluated exactly once', () async {
      expect(await _calls('null ?? bumpInt()'), equals(1));
    });

    test('a chain stops at the first non-null link', () async {
      // `null ?? 5` already yields a non-null value, so the third operand is
      // dead even though the first was null.
      expect(await _calls('null ?? 5 ?? bumpInt()'), equals(0));
      expect(await _calls('null ?? null ?? bumpInt()'), equals(1));
    });
  });

  group('`&&` evaluates its right operand only when the left is true', () {
    test('false left: right operand is never evaluated', () async {
      expect(await _calls('false && bump()'), equals(0));
    });

    test('true left: right operand is evaluated exactly once', () async {
      expect(await _calls('true && bump()'), equals(1));
    });

    test('a false link stops the rest of the chain', () async {
      expect(await _calls('true && bumpFalse() && bump()'), equals(1));
    });
  });

  group('`||` evaluates its right operand only when the left is false', () {
    test('true left: right operand is never evaluated', () async {
      expect(await _calls('true || bump()'), equals(0));
    });

    test('false left: right operand is evaluated exactly once', () async {
      expect(await _calls('false || bump()'), equals(1));
    });

    test('a true link stops the rest of the chain', () async {
      expect(await _calls('false || bump() || bump()'), equals(1));
    });
  });

  group('short-circuiting still produces the right value', () {
    test('`??`', () async {
      expect(await _run('int? a = null; return a ?? 42;'), equals(42));
      expect(await _run('int? a = 7; return a ?? 42;'), equals(7));
    });

    test('`&&` / `||`', () async {
      expect(
        await _run('if (false && true) { return 1; } return 0;'),
        equals(0),
      );
      expect(
        await _run('if (true || false) { return 1; } return 0;'),
        equals(1),
      );
    });
  });

  group('a guarded operand is not evaluated when the receiver is null', () {
    test('`?.` does not call the method on a null receiver', () async {
      // The invocation itself is what must be skipped, so the counter lives on
      // the receiver: a null receiver must leave it untouched.
      var vm = ApolloVM();
      expect(
        await vm.loadCodeUnit(
          SourceCodeUnit('dart', r'''
class B {
  int calls = 0;
  int bump() { calls = calls + 1; return calls; }
}
class S {
  int probe() { B? b = null; var r = b?.bump(); return r ?? -1; }
}
''', id: 'test'),
        ),
        isTrue,
      );

      var r = await vm
          .createRunner('dart')!
          .executeClassMethod(
            '',
            'S',
            'probe',
            positionalParameters: [],
            classInstanceFields: const {},
          );
      expect(r.getValueNoContext(), equals(-1));
    });
  });
}
