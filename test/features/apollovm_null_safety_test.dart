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
}
