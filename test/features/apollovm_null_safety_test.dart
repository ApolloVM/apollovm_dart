@TestOn('vm')
@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

Future<Object?> _run(
  String source, {
  String fn = 'run',
  List args = const [],
}) async {
  var vm = ApolloVM();
  expect(
    await vm.loadCodeUnit(SourceCodeUnit('dart', source, id: 'test')),
    isTrue,
    reason: 'cannot parse: $source',
  );
  var r = await vm
      .createRunner('dart')!
      .executeFunction('', fn, positionalParameters: args);
  return r.getValueNoContext();
}

Future<String> _regen(String source) async {
  var vm = ApolloVM();
  expect(
    await vm.loadCodeUnit(SourceCodeUnit('dart', source, id: 'test')),
    isTrue,
    reason: 'cannot parse: $source',
  );
  var all = await vm.generateAllCodeIn('dart').writeAllSources();
  return all.toString();
}

void main() {
  group('null-coalescing (??)', () {
    test('short-circuits on non-null / null', () async {
      expect(await _run('int run() { int? a = null; return a ?? 42; }'), 42);
      expect(await _run('int run() { int? a = 7; return a ?? 42; }'), 7);
      expect(
        await _run(
          'int run() { int? a = null; int? b = null; return a ?? b ?? 9; }',
        ),
        9,
      );
    });

    test('precedence: ?? binds looser than == (as ternary base)', () async {
      // `(a ?? 1) == 1 ? 100 : 200`
      expect(
        await _run(
          'int run() { int? a = null; return a ?? 1 == 1 ? 100 : 200; }',
        ),
        100,
      );
    });

    test('Dart round-trip', () async {
      expect(
        await _regen('int run() { int? a = null; return a ?? 42; }'),
        contains('a ?? 42'),
      );
    });
  });

  group('null-coalescing assignment (??=)', () {
    test('assigns only when null', () async {
      expect(await _run('int run() { int? a = null; a ??= 5; return a; }'), 5);
      expect(await _run('int run() { int? a = 3; a ??= 5; return a; }'), 3);
    });

    test('Dart round-trip', () async {
      expect(
        await _regen('int run() { int? a = null; a ??= 5; return a; }'),
        contains('a ??= 5'),
      );
    });
  });

  group('null-aware access (?.)', () {
    test('getter short-circuits on null receiver', () async {
      expect(
        await _run(
          'class A { int x = 5; } int? run() { A? a = null; return a?.x; }',
        ),
        isNull,
      );
      expect(
        await _run(
          'class A { int x = 5; } int? run() { A a = A(); return a?.x; }',
        ),
        5,
      );
    });

    test('method invocation short-circuits on null receiver', () async {
      expect(
        await _run(
          'class A { int f() { return 9; } } int? run() { A? a = null; return a?.f(); }',
        ),
        isNull,
      );
      expect(
        await _run(
          'class A { int f() { return 9; } } int? run() { A a = A(); return a?.f(); }',
        ),
        9,
      );
    });

    test('Dart round-trip', () async {
      expect(
        await _regen(
          'class A { int x = 5; } int? run() { A? a = null; return a?.x; }',
        ),
        contains('a?.x'),
      );
    });
  });

  group('null-aware index (?[ ])', () {
    test('short-circuits on null receiver', () async {
      expect(
        await _run('int? run() { List<int>? xs = null; return xs?[0]; }'),
        isNull,
      );
      expect(
        await _run('int? run() { List<int> xs = [7, 8]; return xs?[1]; }'),
        8,
      );
    });

    test('Dart round-trip', () async {
      expect(
        await _regen('int? run() { List<int>? xs = null; return xs?[0]; }'),
        contains('xs?[0]'),
      );
    });
  });

  group('null-assertion (!)', () {
    test('returns the value when non-null', () async {
      expect(await _run('int run() { int? a = 5; return a!; }'), 5);
    });

    test('throws on null', () async {
      expect(
        () async => await _run('int run() { int? a = null; return a!; }'),
        throwsA(isA<ApolloVMNullPointerException>()),
      );
    });

    test('Dart round-trip', () async {
      expect(
        await _regen('int run() { int? a = 5; return a!; }'),
        contains('a!'),
      );
    });
  });

  group('assertion-then-access (! before . / [ )', () {
    test('member access on asserted receiver', () async {
      expect(
        await _run(
          'class A { int x = 5; } int run() { A? a = A(); return a!.x; }',
        ),
        5,
      );
      expect(
        () async => await _run(
          'class A { int x = 5; } int run() { A? a = null; return a!.x; }',
        ),
        throwsA(isA<ApolloVMNullPointerException>()),
      );
    });

    test('method call on asserted receiver', () async {
      expect(
        await _run(
          'class A { int f() { return 9; } } int run() { A? a = A(); return a!.f(); }',
        ),
        9,
      );
    });

    test('index on asserted receiver', () async {
      expect(
        await _run('int run() { List<int>? xs = [7, 8]; return xs![1]; }'),
        8,
      );
      expect(
        () async =>
            await _run('int run() { List<int>? xs = null; return xs![0]; }'),
        throwsA(isA<ApolloVMNullPointerException>()),
      );
    });

    test('Dart round-trip', () async {
      expect(
        await _regen(
          'class A { int x = 5; } int run() { A? a = A(); return a!.x; }',
        ),
        contains('a!.x'),
      );
      expect(
        await _regen('int run() { List<int>? xs = [7]; return xs![0]; }'),
        contains('xs![0]'),
      );
    });
  });

  group('cascades (.. / ?..)', () {
    const cls = 'class B { int n = 0; void add(int x) { n = n + x; } } ';

    test('runs each section against the receiver, returns receiver', () async {
      expect(
        await _run(
          '${cls}int run() { B b = B(); b..add(2)..add(3); return b.n; }',
        ),
        5,
      );
    });

    test('null-aware cascade short-circuits on null receiver', () async {
      expect(
        await _run(
          '${cls}int? run() { B? b = null; b?..add(2); return b?.n; }',
        ),
        isNull,
      );
    });

    test('Dart round-trip', () async {
      expect(
        await _regen(
          '${cls}int run() { B b = B(); b..add(2)..add(3); return b.n; }',
        ),
        contains('b..add(2)..add(3)'),
      );
      expect(
        await _regen(
          '${cls}int? run() { B? b = null; b?..add(2)..add(3); return b?.n; }',
        ),
        contains('b?..add(2)..add(3)'),
      );
    });
  });

  group('nullable types', () {
    test(
      'round-trip preserves ? on simple / collection / function types',
      () async {
        var out = await _regen(
          'class C { List<String>? xs; void Function()? cb; String? Function(int) fmt; }',
        );
        expect(out, contains('List<String>?'));
        expect(out, contains('void Function()?'));
        expect(out, contains('String? Function(int)'));
      },
    );

    test('nullable variable accepts null and its underlying type', () async {
      expect(await _run('int run() { int? a = null; a = 5; return a; }'), 5);
    });
  });

  group('nullable parameters accept a non-null argument', () {
    // Argument passing is an assignment, so a `T?` parameter must accept a `T`.
    // `String?` used to be rejected ("parameters signature not compatible")
    // because `ASTTypeString` compares `nullable` in `==`, while the numeric
    // types only appeared to work because `StrictType` ignores it.
    test('String? accepts a String', () async {
      expect(
        await _run("String run(String? s) { return s ?? 'x'; }", args: ['hi']),
        'hi',
      );
    });

    test('String? still accepts null', () async {
      expect(
        await _run("String run(String? s) { return s ?? 'x'; }", args: [null]),
        'x',
      );
    });

    test('int? / double? / List<int>? accept non-null arguments', () async {
      expect(await _run('int run(int? a) { return a ?? 1; }', args: [7]), 7);
      expect(
        await _run('double run(double? d) { return d ?? 1.5; }', args: [2.5]),
        2.5,
      );
      expect(
        await _run(
          'int run(List<int>? xs) { return xs?[0] ?? -1; }',
          args: [
            [3, 4],
          ],
        ),
        3,
      );
    });

    test('multiple nullable parameters, all non-null', () async {
      expect(
        await _run(
          "String run(String? s, int? p) { return '\$s/\$p'; }",
          args: ['hi', 9],
        ),
        'hi/9',
      );
    });
  });

  group('null-aware access stored in a local', () {
    // A short-circuited `?.` / `?[` evaluates to null, so the expression's
    // static type must be nullable — otherwise a `var` / `int?` declaration
    // rejects that null at declaration time.
    test('?. getter into `var` and into `int?`', () async {
      expect(
        await _run(
          'int run() { String? s = null; var v = s?.length; return v ?? -1; }',
        ),
        -1,
      );
      expect(
        await _run(
          'int run() { String? s = null; int? v = s?.length; return v ?? -1; }',
        ),
        -1,
      );
      expect(
        await _run(
          "int run() { String? s = 'abcd'; var v = s?.length; return v ?? -1; }",
        ),
        4,
      );
    });

    test('?. on a user class into a local', () async {
      expect(
        await _run(
          'class A { int x = 5; } '
          'int run() { A? a = null; var v = a?.x; return v ?? -1; }',
        ),
        -1,
      );
      expect(
        await _run(
          'class A { int x = 5; } '
          'int run() { A a = A(); var v = a?.x; return v ?? -1; }',
        ),
        5,
      );
    });

    test('?. method invocation into a local', () async {
      expect(
        await _run(
          "int run() { String? s = null; String? v = s?.toUpperCase(); "
          'return v == null ? -1 : 0; }',
        ),
        -1,
      );
    });

    test('?[ index into `var`', () async {
      expect(
        await _run(
          'int run() { List<int>? xs = null; var v = xs?[0]; return v ?? -1; }',
        ),
        -1,
      );
      expect(
        await _run(
          'int run() { List<int>? xs = [7, 8]; var v = xs?[1]; return v ?? -1; }',
        ),
        8,
      );
    });
  });

  group('member-access chains', () {
    const cls =
        'class C { int v = 3; C? next; void link(C n) { next = n; } '
        'C mk() { var n = C(); n.v = 9; return n; } } ';

    test('plain chain reads at depth 2 and 3', () async {
      expect(
        await _run(
          '${cls}int run() { var a = C(); var b = C(); b.v = 7; a.link(b); '
          'return a.next.v; }',
        ),
        7,
      );
      expect(
        await _run(
          '${cls}int run() { var a = C(); var b = C(); var d = C(); d.v = 7; '
          'b.link(d); a.link(b); return a.next.next.v; }',
        ),
        7,
      );
    });

    test('null-aware chain short-circuits at the first null link', () async {
      expect(
        await _run(
          '${cls}int run() { var a = C(); return a.next?.next?.v ?? -1; }',
        ),
        -1,
      );
    });

    test('`this.field.member` chain', () async {
      expect(
        await _run(
          '${cls}class K { C c = C(); int read() { return this.c.v; } } '
          'int run() { return K().read(); }',
        ),
        3,
      );
    });

    test('method call inside a chain', () async {
      expect(
        await _run('${cls}int run() { var a = C(); return a.mk().v; }'),
        9,
      );
      expect(
        await _run(
          '${cls}int run() { var a = C(); var b = C(); a.link(b); '
          'return a.next.mk().v; }',
        ),
        9,
      );
    });

    test('`!` inside a chain asserts the preceding link', () async {
      expect(
        await _run(
          '${cls}int run() { var a = C(); var b = C(); a.link(b); '
          'return a.next!.v; }',
        ),
        3,
      );
    });

    test('chained field write', () async {
      expect(
        await _run(
          '${cls}int run() { var a = C(); var b = C(); a.link(b); '
          'a.next.v = 42; return a.next.v; }',
        ),
        42,
      );
    });

    test('chain in an argument and in arithmetic', () async {
      expect(
        await _run(
          '${cls}int add(int x) { return x + 1; } '
          'int run() { var a = C(); var b = C(); a.link(b); '
          'return add(a.next.v) + a.next.v * 2; }',
        ),
        10,
      );
    });

    test('Dart round-trip keeps the chain', () async {
      var out = await _regen(
        '${cls}int run() { var a = C(); return a.next?.v ?? -1; }',
      );
      expect(out, contains('a.next?.v'));
    });

    test('single-segment access is unchanged', () async {
      expect(await _run('${cls}int run() { var a = C(); return a.v; }'), 3);
      expect(
        await _run('${cls}int run() { var a = C(); a.v = 8; return a.v; }'),
        8,
      );
    });

    test('parenthesized receiver: (a).v, (a)?.v, (a.next)?.v', () async {
      // Only `(expr).method()` used to parse; a *field* read off a group, and
      // any `?.` after one, did not.
      expect(await _run('${cls}int run() { var a = C(); return (a).v; }'), 3);
      expect(
        await _run('${cls}int run() { var a = C(); return (a)?.v ?? -1; }'),
        3,
      );
      expect(
        await _run(
          '${cls}int run() { var a = C(); return (a.next)?.v ?? -1; }',
        ),
        -1,
      );
      // A call followed by a field access — the group-invocation rule chains
      // only further calls, so this needs its own rule.
      expect(
        await _run('${cls}int run() { var a = C(); return (a).mk().v; }'),
        9,
      );
      // The existing group-invocation path still works.
      expect(
        await _run(
          '${cls}int run() { var a = C(); var m = (a).mk(); return m.v; }',
        ),
        9,
      );
    });
  });

  group('`== null` / `!= null` against a typed operand', () {
    // `ASTValue.equals` used to read the other operand through `_getValue`,
    // which casts it to *this* value's `T` — so `x == null` evaluated
    // `null as FutureOr<int>` and threw instead of returning false. Only the
    // reversed `null == x` worked, because `ASTValueNull.equals` type-tests.
    test('a non-null typed local compares false against null', () async {
      expect(
        await _run(
          'int run() { int? a = 1; if (a == null) { return -1; } return 1; }',
        ),
        1,
      );
      expect(
        await _run(
          'int run() { Object? a = 1; if (a == null) { return -1; } return 1; }',
        ),
        1,
      );
      expect(
        await _run(
          "int run() { String s = 'x'; if (s == null) { return -1; } return 1; }",
        ),
        1,
      );
    });

    test('a null local compares true against null', () async {
      expect(
        await _run(
          'int run() { Object? a = null; if (a == null) { return -1; } return 1; }',
        ),
        -1,
      );
    });

    test('a nullable parameter compares both ways', () async {
      const src = 'int run(int? a) { if (a == null) { return -1; } return 1; }';
      expect(await _run(src, args: [1]), 1);
      expect(await _run(src, args: [null]), -1);
    });

    test('`!=` mirrors `==`', () async {
      const src = 'int run(int? a) { if (a != null) { return 1; } return -1; }';
      expect(await _run(src, args: [1]), 1);
      expect(await _run(src, args: [null]), -1);
    });

    test('the reversed form still works', () async {
      expect(
        await _run(
          'int run() { int? a = 1; if (null == a) { return -1; } return 1; }',
        ),
        1,
      );
    });

    test('comparing different types is false, not an error', () async {
      expect(
        await _run(
          "int run() { int a = 1; if (a == 'x') { return -1; } return 1; }",
        ),
        1,
      );
    });
  });
}
