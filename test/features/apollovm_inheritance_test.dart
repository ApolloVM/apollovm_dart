@TestOn('vm')
@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

Future<Object?> _run(
  String language,
  String source,
  String className,
  String method,
) async {
  var vm = ApolloVM();
  expect(
    await vm.loadCodeUnit(SourceCodeUnit(language, source, id: 'test')),
    isTrue,
    reason: '$language: cannot parse',
  );
  var r = await vm
      .createRunner(language)!
      .executeClassMethod(
        '',
        className,
        method,
        positionalParameters: const [[]],
        classInstanceFields: const {},
      );
  return r.getValueNoContext();
}

void main() {
  group('Inherited methods', () {
    test('a subclass calls an inherited method by bare name', () async {
      expect(
        await _run(
          'dart',
          'class A { int base() { return 1; } }'
              ' class B extends A { int run() { return base() + 2; } }',
          'B',
          'run',
        ),
        equals(3),
      );
    });

    test('an inherited method is callable on an instance', () async {
      expect(
        await _run(
          'dart',
          'class A { int base() { return 5; } }'
              ' class B extends A {}'
              ' class M { static int run() { var b = B(); return b.base(); } }',
          'M',
          'run',
        ),
        equals(5),
      );
    });

    test('a method override wins over the inherited method', () async {
      expect(
        await _run(
          'dart',
          'class A { int f() { return 1; } }'
              ' class B extends A { int f() { return 2; } }'
              ' class M { static int run() { var b = B(); return b.f(); } }',
          'M',
          'run',
        ),
        equals(2),
      );
    });

    test('a method inherited across two levels', () async {
      expect(
        await _run(
          'dart',
          'class A { int base() { return 9; } }'
              ' class B extends A {}'
              ' class C extends B {}'
              ' class M { static int run() { var c = C(); return c.base(); } }',
          'M',
          'run',
        ),
        equals(9),
      );
    });
  });

  group('Inherited fields', () {
    test('a subclass reads an inherited field', () async {
      expect(
        await _run(
          'dart',
          'class A { int x = 7; }'
              ' class B extends A { int run() { return x; } }',
          'B',
          'run',
        ),
        equals(7),
      );
    });

    test('a subclass writes an inherited field', () async {
      expect(
        await _run(
          'dart',
          'class A { int x = 7; }'
              ' class B extends A { int run() { x = x + 3; return x; } }',
          'B',
          'run',
        ),
        equals(10),
      );
    });

    test('inherited and own fields coexist', () async {
      expect(
        await _run(
          'dart',
          'class A { int a = 1; }'
              ' class B extends A { int b = 2; int run() { return a + b; } }',
          'B',
          'run',
        ),
        equals(3),
      );
    });
  });

  group('super', () {
    test('super.method() calls the overridden parent method', () async {
      expect(
        await _run(
          'dart',
          'class A { int f() { return 10; } }'
              ' class B extends A { int f() { return super.f() + 5; }'
              ' int run() { return f(); } }',
          'B',
          'run',
        ),
        equals(15),
      );
    });

    test('super in a class with no superclass errors clearly', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(
        SourceCodeUnit(
          'dart',
          'class A { int f() { return super.f(); } int run() { return f(); } }',
          id: 'test',
        ),
      );
      await expectLater(
        vm
            .createRunner('dart')!
            .executeClassMethod(
              '',
              'A',
              'run',
              positionalParameters: const [[]],
              classInstanceFields: const {},
            ),
        throwsA(isA<ApolloVMRuntimeError>()),
      );
    });

    test('super resolves relative to the textual class (multi-level)', () async {
      // C inherits B.f; B.f's `super` is A.f (not C's parent B), so the result
      // is A.f() + 10 = 11.
      expect(
        await _run(
          'dart',
          'class A { int f() { return 1; } }'
              ' class B extends A { int f() { return super.f() + 10; } }'
              ' class C extends B {'
              ' static int run() { var c = C(); return c.f(); } }',
          'C',
          'run',
        ),
        equals(11),
      );
    });
  });

  group('Cross-language inheritance', () {
    test('Java: inherited method + override', () async {
      expect(
        await _run(
          'java11',
          'class A { int f() { return 1; } int base() { return 100; } }'
              ' class B extends A { int f() { return 2; }'
              ' int run() { return f() + base(); } }',
          'B',
          'run',
        ),
        equals(102),
      );
    });

    test('C#: inherited field', () async {
      expect(
        await _run(
          'csharp',
          'class A { int x = 7; }'
              ' class B : A { int run() { return x + 1; } }',
          'B',
          'run',
        ),
        equals(8),
      );
    });
  });
}
