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

  group('super fields', () {
    test('super.field reads the inherited instance field', () async {
      expect(
        await _run(
          'dart',
          'class A { int x = 7; }'
              ' class B extends A { int g() { return super.x; } }'
              ' class M { static int run() { var b = B(); return b.g(); } }',
          'M',
          'run',
        ),
        equals(7),
      );
    });

    test('super.field = value writes the inherited instance field', () async {
      expect(
        await _run(
          'dart',
          'class A { int x = 7; }'
              ' class B extends A { int g() { super.x = 20; return x; } }'
              ' class M { static int run() { var b = B(); return b.g(); } }',
          'M',
          'run',
        ),
        equals(20),
      );
    });

    test('super.getter in a class with no superclass errors clearly', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(
        SourceCodeUnit(
          'dart',
          'class A { int get v { return super.v; } }'
              ' class M { static int run() { var a = A(); return a.v; } }',
          id: 'test',
        ),
      );
      await expectLater(
        vm
            .createRunner('dart')!
            .executeClassMethod(
              '',
              'M',
              'run',
              positionalParameters: const [[]],
              classInstanceFields: const {},
            ),
        throwsA(isA<ApolloVMRuntimeError>()),
      );
    });

    test('super.getter dispatches to the parent (overridden) getter', () async {
      expect(
        await _run(
          'dart',
          'class A { int get v { return 1; } }'
              ' class B extends A { int get v { return 2; }'
              ' int g() { return super.v; } }'
              ' class M { static int run() { var b = B(); return b.g(); } }',
          'M',
          'run',
        ),
        equals(1),
      );
    });
  });

  group('Inherited getters', () {
    test('an inherited getter is readable on an instance', () async {
      expect(
        await _run(
          'dart',
          'class A { int _x = 4; int get gx { return _x; } }'
              ' class B extends A {}'
              ' class M { static int run() { var b = B(); return b.gx; } }',
          'M',
          'run',
        ),
        equals(4),
      );
    });

    test('a getter override wins over the inherited getter', () async {
      expect(
        await _run(
          'dart',
          'class A { int get gx { return 1; } }'
              ' class B extends A { int get gx { return 2; } }'
              ' class M { static int run() { var b = B(); return b.gx; } }',
          'M',
          'run',
        ),
        equals(2),
      );
    });
  });

  group('Inherited static fields', () {
    test('a subclass reads an inherited static field (qualified)', () async {
      expect(
        await _run(
          'dart',
          'class A { static int c = 9; }'
              ' class B extends A {}'
              ' class M { static int run() { return B.c; } }',
          'M',
          'run',
        ),
        equals(9),
      );
    });

    test(
      'writing an inherited static field goes to the declaring class',
      () async {
        // `B.c = 20` writes through to `A.c` (static storage is per-declaring
        // class), so reading `A.c` back sees the new value.
        expect(
          await _run(
            'dart',
            'class A { static int c = 9; }'
                ' class B extends A {}'
                ' class M { static int run() { B.c = 20; return A.c; } }',
            'M',
            'run',
          ),
          equals(20),
        );
      },
    );
  });

  group('Constructors with inheritance', () {
    test(
      'a subclass constructor sets an inherited field by bare name',
      () async {
        expect(
          await _run(
            'dart',
            'class A { int x = 0; }'
                ' class B extends A { B(int v) { x = v; } }'
                ' class M { static int run() { var b = B(9); return b.x; } }',
            'M',
            'run',
          ),
          equals(9),
        );
      },
    );

    test('a subclass `this.param` binds an inherited field', () async {
      expect(
        await _run(
          'dart',
          'class A { int x = 0; }'
              ' class B extends A { B(this.x); }'
              ' class M { static int run() { var b = B(13); return b.x; } }',
          'M',
          'run',
        ),
        equals(13),
      );
    });

    test(
      'the default constructor initializes inherited field values',
      () async {
        expect(
          await _run(
            'dart',
            'class A { int x = 42; }'
                ' class B extends A {}'
                ' class M { static int run() { var b = B(); return b.x; } }',
            'M',
            'run',
          ),
          equals(42),
        );
      },
    );
  });

  group('Known limitations', () {
    test(
      'a constructor initializer list (`: super(v)`) does not parse yet',
      () async {
        // Documents a current parser gap: explicit super-constructor calls in an
        // initializer list are not supported. Inherited fields are still set via
        // the constructor body or `this.param`.
        var vm = ApolloVM();
        await expectLater(
          vm.loadCodeUnit(
            SourceCodeUnit(
              'dart',
              'class A { int x = 0; A(int v) { x = v; } }'
                  ' class B extends A { B(int v) : super(v); }',
              id: 'test',
            ),
          ),
          throwsA(isA<SyntaxError>()),
        );
      },
    );
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

    test('JavaScript: inherited method', () async {
      expect(
        await _run(
          'javascript',
          'class A { base() { return 100; } }'
              ' class B extends A { run() { return this.base(); } }',
          'B',
          'run',
        ),
        equals(100),
      );
    });

    test('TypeScript: inherited method', () async {
      expect(
        await _run(
          'typescript',
          'class A { base(): number { return 100; } }'
              ' class B extends A { run(): number { return this.base(); } }',
          'B',
          'run',
        ),
        equals(100),
      );
    });

    test('Python: inherited method', () async {
      expect(
        await _run(
          'python',
          'class A:\n    def base(self):\n        return 100\n'
              'class B(A):\n    def run(self):\n        return self.base()\n',
          'B',
          'run',
        ),
        equals(100),
      );
    });
  });
}
