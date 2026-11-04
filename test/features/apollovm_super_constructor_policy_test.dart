@Tags(['dart', 'java', 'csharp', 'javascript', 'typescript', 'python'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:apollovm/apollovm_serialization.dart';
import 'package:test/test.dart';

/// How a subclass constructor reaches its superclass constructor when the
/// source doesn't spell it out. The rule differs per language, so it is read
/// from the language the module was parsed from (`ASTRoot.language`):
///
/// - Dart, Java, C#: an implicit `super()` — from a declared constructor
///   without `super(…)`, and from the default constructor of a class that
///   declares none.
/// - JavaScript, TypeScript, Python: a subclass without a constructor
///   *inherits* its parent's, every argument forwarded; one that declares a
///   constructor does not call the parent implicitly.

Future<ApolloVM> _load(String language, String src) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit(language, src, id: 'test'));
  expect(ok, isTrue, reason: "Can't load $language source");
  return vm;
}

Future<Object?> _runVM(ApolloVM vm, String language) async {
  var r = await vm
      .createRunner(language)!
      .executeClassMethod(
        '',
        'M',
        'run',
        positionalParameters: const [[]],
        classInstanceFields: const {},
      );
  return r.getValueNoContext();
}

Future<Object?> _run(String language, String src) async =>
    _runVM(await _load(language, src), language);

void main() {
  group('Implicit super() — Dart', () {
    test('from a declared constructor', () async {
      expect(
        await _run(
          'dart',
          'class A { int x = 0; A() { x = 5; } }'
              ' class B extends A { int y = 0; B() { y = x + 1; } }'
              ' class M { static int run() { var b = B(); return b.x * 10 + b.y; } }',
        ),
        equals(56),
        reason: 'the superclass body runs before the subclass body',
      );
    });

    test('from the default constructor, through every level', () async {
      expect(
        await _run(
          'dart',
          'class A { String log = ""; A() { log = log + "A"; } }'
              ' class B extends A { B() { log = log + "B"; } }'
              ' class C extends B { }'
              ' class M { static String run() { var c = C(); return c.log; } }',
        ),
        equals('AB'),
      );
    });

    test('passes super parameters to the superclass constructor', () async {
      expect(
        await _run(
          'dart',
          'class A { int x; int doubled = 0; A(this.x) { doubled = x * 2; } }'
              ' class B extends A { B(super.x); }'
              ' class M { static int run() { var b = B(4); return b.doubled; } }',
        ),
        equals(8),
      );
    });

    test('not when a `super(…)` or `this(…)` already delegates', () async {
      expect(
        await _run(
          'dart',
          'class A { int n = 0; A() { n = n + 1; } A.other() { n = n + 10; } }'
              ' class B extends A { B() : super.other(); B.r() : this(); }'
              ' class M { static int run() { var b = B(); var c = B.r(); '
              'return b.n * 100 + c.n; } }',
        ),
        equals(1010),
        reason: 'each superclass constructor runs exactly once',
      );
    });

    test('a superclass constructor that needs arguments is an error', () async {
      var vm = await _load(
        'dart',
        'class A { int x; A(this.x); }'
            ' class B extends A { B(); }'
            ' class M { static int run() { B(); return 0; } }',
      );
      await expectLater(
        _runVM(vm, 'dart'),
        throwsA(
          isA<ApolloVMRuntimeError>().having(
            (e) => e.toString(),
            'message',
            contains('(implicit)'),
          ),
        ),
      );
    });

    test('an initializing formal for an inherited field still works', () async {
      // `B(this.x)` names an inherited field (Dart would want `super.x`); the
      // superclass's default constructor takes no `x`, so it stays field-only.
      expect(
        await _run(
          'dart',
          'class A { int x = 0; }'
              ' class B extends A { B(this.x); }'
              ' class M { static int run() { var b = B(13); return b.x; } }',
        ),
        equals(13),
      );
    });

    test('an inherited-field formal before a super parameter', () async {
      // `this.x` names an inherited field (ApolloVM reads it as `super.x`);
      // only `y` is a parameter of A, so only `y` is passed to it.
      expect(
        await _run(
          'dart',
          'class A { int x = 0; int y; A(this.y); }'
              ' class B extends A { B(this.x, super.y); }'
              ' class M { static int run() { var b = B(1, 2); return b.x * 10 + b.y; } }',
        ),
        equals(12),
      );
    });

    test('the language survives the binary AST', () async {
      var vm = await _load(
        'dart',
        'class A { int x = 0; A() { x = 5; } } class B extends A { B(); }'
            ' class M { static int run() { var b = B(); return b.x; } }',
      );
      var image = vm.saveCodeUnitAST(vm.allCodeUnitsAllLanguages().single);

      var vm2 = ApolloVM();
      expect(await vm2.loadCodeUnitAST(image), isTrue);
      expect(vm2.allCodeUnitsAllLanguages().single.root!.language, 'dart');
      expect(await _runVM(vm2, 'dart'), equals(5));
    });
  });

  group('Implicit super() — Java and C#', () {
    test('Java: declared and default constructors', () async {
      for (var b in [
        'class B extends A { B() { } }',
        'class B extends A { }',
      ]) {
        expect(
          await _run(
            'java11',
            'class A { int x = 0; A() { x = 5; } } $b'
                ' class M { static int run(Object[] a) { B b = new B(); return b.x; } }',
          ),
          equals(5),
          reason: b,
        );
      }
    });

    test('C#: declared and default constructors', () async {
      for (var b in ['class B : A { public B() { } }', 'class B : A { }']) {
        expect(
          await _run(
            'csharp',
            'class A { public int x = 0; public A() { x = 5; } } $b'
                ' class M { public static int run(object[] a) { B b = new B(); return b.x; } }',
          ),
          equals(5),
          reason: b,
        );
      }
    });
  });

  group('Explicit super(…) / this(…) statements — Java, JavaScript', () {
    test(
      'Java: `super(v);` delegates, with no implicit `super()` too',
      () async {
        expect(
          await _run(
            'java11',
            'class A { int x = 0; int n = 0; A(int v) { x = v; n = n + 1; } }'
                ' class B extends A { int y = 0; B(int v) { super(v + 1); y = x * 2; } }'
                ' class M { static int run(Object[] a) { B b = new B(4); '
                'return b.x * 100 + b.y * 10 + b.n; } }',
          ),
          equals(5 * 100 + 10 * 10 + 1),
        );
      },
    );

    test('Java: `this(…);` redirects', () async {
      expect(
        await _run(
          'java11',
          'class A { int x = 0; A(int v) { x = v; } A() { this(9); } }'
              ' class M { static int run(Object[] a) { A o = new A(); return o.x; } }',
        ),
        equals(9),
      );
    });

    test('JavaScript: `super(v)` in a declared constructor', () async {
      expect(
        await _run(
          'javascript',
          'class A { constructor(v) { this.x = v; } }'
              ' class B extends A { constructor(v) { super(v); this.y = 1; } }'
              ' class M { static run(a) { var b = new B(7); return b.x + b.y; } }',
        ),
        equals(8),
      );
    });

    test('Java: the statement is written back unchanged', () async {
      var vm = await _load(
        'java11',
        'class A { int x = 0; A(int v) { x = v; } }'
            ' class B extends A { B(int v) { super(v); } }',
      );
      var code = (await vm.generateAllCodeIn('java11').writeAllSources())
          .toString();
      expect(code, contains('super(v);'));
    });
  });

  group('Inherited constructors — JavaScript, TypeScript, Python', () {
    test(
      'JavaScript: a subclass without a constructor takes the parent one',
      () async {
        expect(
          await _run(
            'javascript',
            'class A { constructor(v) { this.x = v; } } class B extends A { }'
                ' class C extends B { }'
                ' class M { static run(a) { var c = new C(7); return c.x; } }',
          ),
          equals(7),
          reason: 'inherited through two levels',
        );
      },
    );

    test(
      'TypeScript: a subclass without a constructor takes the parent one',
      () async {
        expect(
          await _run(
            'typescript',
            'class A { x: number; constructor(v: number) { this.x = v; } }'
                ' class B extends A { }'
                ' class M { static run(a: any): number { let b = new B(7); return b.x; } }',
          ),
          equals(7),
        );
      },
    );

    test(
      'Python: a subclass without `__init__` takes the parent one',
      () async {
        expect(
          await _run(
            'python',
            'class A:\n'
                '    def __init__(self, v):\n'
                '        self.x = v\n\n'
                'class B(A):\n'
                '    def f(self):\n'
                '        return 1\n\n'
                'class M:\n'
                '    def run(self, a):\n'
                '        b = B(7)\n'
                '        return b.x\n',
          ),
          equals(7),
        );
      },
    );

    test(
      'Python: a declared `__init__` does not call the parent one',
      () async {
        // A.__init__ never runs, so the instance has no `x` at all.
        var vm = await _load(
          'python',
          'class A:\n'
              '    def __init__(self):\n'
              '        self.x = 5\n\n'
              'class B(A):\n'
              '    def __init__(self):\n'
              '        self.y = 1\n\n'
              'class M:\n'
              '    def run(self, a):\n'
              '        b = B()\n'
              '        return b.x\n',
        );
        await expectLater(
          _runVM(vm, 'python'),
          throwsA(
            isA<ApolloVMRuntimeError>().having(
              (e) => e.toString(),
              'message',
              contains('getter[x]'),
            ),
          ),
        );
      },
    );

    test(
      'JavaScript: no implicit super() from a declared constructor',
      () async {
        // JS requires an explicit `super(…)`; ApolloVM doesn't call the parent
        // behind the program's back.
        expect(
          await _run(
            'javascript',
            'class A { constructor() { this.x = 5; } }'
                ' class B extends A { constructor() { this.y = 1; } }'
                ' class M { static run(a) { var b = new B(); return b.y; } }',
          ),
          equals(1),
        );
      },
    );
  });

  group('The policy table', () {
    test('maps each language to its rule', () {
      const implicit = ASTSuperConstructorPolicy.implicitSuperCall;
      const inherit = ASTSuperConstructorPolicy.inheritConstructors;
      const none = ASTSuperConstructorPolicy.none;
      expect(
        {
          for (var l in [
            'dart',
            'java11',
            'csharp',
            'javascript',
            'typescript',
            'python',
            'kotlin',
            'go',
            'lua',
            null,
          ])
            l: ASTSuperConstructorPolicy.forLanguage(l),
        },
        equals({
          'dart': implicit,
          'java11': implicit,
          'csharp': implicit,
          'javascript': inherit,
          'typescript': inherit,
          'python': inherit,
          'kotlin': none,
          'go': none,
          'lua': none,
          null: none,
        }),
      );
    });
  });
}
