@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:apollovm/apollovm_serialization.dart';
// The registry is internal; the codec choice is what keeps old images readable.
import 'package:apollovm/src/serialization/ast_binary_registry.dart';
import 'package:apollovm/src/serialization/ast_binary_tags.dart';
import 'package:test/test.dart';

/// The Dart constructor kinds beyond the plain unnamed one: named
/// constructors, initializer lists (field initializers, `assert`, `super(…)`,
/// `this(…)` redirects) and `factory` constructors — run, generated back to
/// Dart, round-tripped through the binary AST, and refused by the targets that
/// can't express them.

Future<ApolloVM> _load(String src) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', src, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source");
  return vm;
}

Future<Object?> _runVM(ApolloVM vm) async {
  var res = await vm.createRunner('dart')!.executeFunction('', 'run');
  return res.getValueNoContext();
}

Future<Object?> _run(String src) async => _runVM(await _load(src));

Future<String> _dartOf(ApolloVM vm) async =>
    (await vm.generateAllCodeIn('dart').writeAllSources()).toString();

/// Generates Dart from [src], reloads it in a fresh VM and runs it there.
Future<Object?> _runRegenerated(String src) async {
  var code = (await (await _load(src))
      .generateAllCodeIn('dart')
      .getNamespaceCodeUnit('', 'test'))!;
  var vm2 = ApolloVM();
  var ok = await vm2.loadCodeUnit(SourceCodeUnit('dart', code, id: 'test'));
  expect(ok, isTrue, reason: 'Generated Dart should load:\n$code');
  return _runVM(vm2);
}

/// Saves [src] as a binary AST image, loads it in a fresh VM and runs it.
Future<Object?> _runFromImage(String src) async {
  var vm = await _load(src);
  var image = vm.saveCodeUnitAST(vm.allCodeUnitsAllLanguages().single);
  var vm2 = ApolloVM();
  expect(await vm2.loadCodeUnitAST(image), isTrue);
  return _runVM(vm2);
}

ASTClassConstructorDeclaration _ctor(ApolloVM vm, String cls, String name) {
  var clazz = vm.allCodeUnitsAllLanguages().single.root!.getClass(cls)!;
  return clazz.getConstructorWithName(name)!.firstFunction;
}

// One program per feature, reused by the run / generate / image tests.

const _named =
    'class P {\n'
    '  int x;\n'
    '  int y;\n'
    '  P(this.x, this.y);\n'
    '  P.origin() : x = 0, y = 0;\n'
    '  P.diagonal(int v) : this(v, v);\n'
    '  P.fromX(this.x, {int y = 5}) { this.y = y; }\n'
    '  int sum() { return this.x + this.y; }\n'
    '}\n'
    'int run() {\n'
    '  var a = P.origin();\n'
    '  var b = P.diagonal(3);\n'
    '  var c = P.fromX(1);\n'
    '  var d = P.fromX(1, y: 2);\n'
    '  return a.sum() + b.sum() * 10 + c.sum() * 100 + d.sum() * 1000;\n'
    '}\n';

const _namedResult = 0 + 60 + 600 + 3000;

const _initializers =
    'class R {\n'
    '  final int w;\n'
    '  final int h;\n'
    '  final int area;\n'
    '  R(int w, int h) : assert(w > 0), w = w, this.h = h, area = w * h;\n'
    '}\n'
    'int run() { var r = R(3, 4); return r.area + r.w + r.h; }\n';

const _super =
    'class A {\n'
    '  String log = "";\n'
    '  int x = 0;\n'
    '  A(int v) { this.x = v * 10; this.log = this.log + "A"; }\n'
    '  A.named(int v) : x = v { this.log = this.log + "a"; }\n'
    '}\n'
    'class B extends A {\n'
    '  int y;\n'
    '  B(int v) : y = v, super(v + 1) { this.log = this.log + "B"; }\n'
    '  B.alt(int v) : y = 0, super.named(v) { this.log = this.log + "b"; }\n'
    '}\n'
    'String run() {\n'
    '  var b = B(2);\n'
    '  var c = B.alt(5);\n'
    '  return "\${b.x},\${b.y},\${b.log};\${c.x},\${c.y},\${c.log}";\n'
    '}\n';

const _superResult = '30,2,AB;5,0,ab';

const _factory =
    'class Shape {\n'
    '  String kind;\n'
    '  Shape._(this.kind);\n'
    '  factory Shape(String k) {\n'
    '    if (k == "") return Shape._("none");\n'
    '    return Shape._(k);\n'
    '  }\n'
    '  factory Shape.square() => Shape._("square");\n'
    '}\n'
    'String run() {\n'
    '  var a = Shape("");\n'
    '  var b = Shape("circle");\n'
    '  var c = Shape.square();\n'
    '  return a.kind + "," + b.kind + "," + c.kind;\n'
    '}\n';

const _factoryResult = 'none,circle,square';

void main() {
  group('Named constructors', () {
    test('initializer, redirect and body forms all run', () async {
      expect(await _run(_named), equals(_namedResult));
    });

    test(
      '`new` and `const` prefixes, and a call chained on the result',
      () async {
        expect(
          await _run(
            'class C { int v; C.of(this.v); const C.two() : v = 2; '
            'int inc() { return this.v + 1; } }\n'
            'int run() { var a = new C.of(1); var b = const C.two(); '
            'return a.v + b.v + C.of(10).inc(); }',
          ),
          equals(1 + 2 + 11),
        );
      },
    );

    test('named parameters', () async {
      expect(
        await _run(
          'class C { int a; int b; C.make({required this.a, this.b = 7}); }\n'
          'int run() { var c = C.make(a: 1); var d = C.make(b: 2, a: 3); '
          'return c.a + c.b + d.a * 10 + d.b * 100; }',
        ),
        equals(1 + 7 + 30 + 200),
      );
    });

    test('a private named constructor, called from a static method', () async {
      expect(
        await _run(
          'class C { int v; C._(this.v); static C make() { return C._(4); } }\n'
          'int run() { return C.make().v; }',
        ),
        equals(4),
      );
    });

    test('static methods still resolve next to named constructors', () async {
      expect(
        await _run(
          'class C { int v; C.of(this.v); static int twice(int n) { return n * 2; } }\n'
          'int run() { return C.twice(C.of(3).v); }',
        ),
        equals(6),
      );
    });

    test('declaring only named constructors removes the unnamed one', () async {
      var vm = await _load(
        'class C { int v = 0; C.zero(); }\nint run() { var c = C(); return c.v; }',
      );
      await expectLater(_runVM(vm), throwsA(isA<ApolloVMRuntimeError>()));
    });

    test('an unknown named constructor is an error', () async {
      var vm = await _load(
        'class C { C.zero(); }\nint run() { var c = C.one(); return 0; }',
      );
      await expectLater(_runVM(vm), throwsA(isA<ApolloVMRuntimeError>()));
    });
  });

  group('Initializer lists', () {
    test('field initializers, `this.x = …` and `assert`', () async {
      expect(await _run(_initializers), equals(12 + 3 + 4));
    });

    test('the body runs after the initializer list', () async {
      expect(
        await _run(
          'class C { int a; int b = 0; C(int v) : a = v { this.b = this.a * 2; } }\n'
          'int run() { var c = C(5); return c.b; }',
        ),
        equals(10),
      );
    });

    test('a failing `assert` stops the construction', () async {
      var vm = await _load(
        'class C { int a; C(int v) : assert(v > 0, "must be positive"), a = v; }\n'
        'int run() { var c = C(0); return c.a; }',
      );
      await expectLater(
        _runVM(vm),
        throwsA(
          isA<ApolloVMThrownException>().having(
            (e) => e.toString(),
            'message',
            contains('must be positive'),
          ),
        ),
      );
    });
  });

  group('Superclass constructors', () {
    test(
      '`super(…)` and `super.named(…)` run the superclass body first',
      () async {
        expect(await _run(_super), equals(_superResult));
      },
    );

    test('three levels run top-down', () async {
      expect(
        await _run(
          'class A { String log = ""; A() { this.log = this.log + "A"; } }\n'
          'class B extends A { B() : super() { this.log = this.log + "B"; } }\n'
          'class C extends B { C() : super() { this.log = this.log + "C"; } }\n'
          'String run() { var c = C(); return c.log; }',
        ),
        equals('ABC'),
      );
    });

    test('named arguments to `super`', () async {
      expect(
        await _run(
          'class A { int x; int y; A({required this.x, this.y = 1}); }\n'
          'class B extends A { B(int v) : super(x: v); }\n'
          'int run() { var b = B(4); return b.x * 10 + b.y; }',
        ),
        equals(41),
      );
    });

    test(
      'super parameters are passed to an explicit `super.named(…)`',
      () async {
        expect(
          await _run(
            'class A { int x; int z = 0; A.scaled(this.x, int k) { this.z = this.x * k; } }\n'
            'class B extends A { B(super.x) : super.scaled(3); }\n'
            'int run() { var b = B(2); return b.x * 10 + b.z; }',
          ),
          equals(26),
        );
      },
    );

    test('an omitted optional super parameter leaves the superclass default', () async {
      expect(
        await _run(
          'class A { int x; A({this.x = 5}); }\n'
          'class B extends A { B({super.x}) : super(); }\n'
          'int run() { var b = B(); var c = B(x: 2); return b.x * 10 + c.x; }',
        ),
        equals(52),
      );
      expect(
        await _run(
          'class A { int x; A([this.x = 5]); }\n'
          'class B extends A { B([super.x]) : super(); }\n'
          'int run() { var b = B(); var c = B(2); return b.x * 10 + c.x; }',
        ),
        equals(52),
      );
      // A default of the subclass's own wins over the superclass one.
      expect(
        await _run(
          'class A { int x; A({this.x = 5}); }\n'
          'class B extends A { B({super.x = 7}) : super(); }\n'
          'int run() { var b = B(); return b.x; }',
        ),
        equals(7),
      );
    });

    test(
      'a super parameter naming a superclass parameter adds no field',
      () async {
        var vm = await _load(
          'class A { int y = 0; A(int v) { this.y = v * 2; } }\n'
          'class B extends A { B(super.v) : super(); }\n'
          'int run() { var b = B(4); return b.y; }\n'
          'B make() { return B(4); }',
        );
        expect(await _runVM(vm), equals(8));

        var b = await vm.createRunner('dart')!.executeFunction('', 'make');
        var fields = (b.getValueNoContext() as VMObject).getFieldsValues();
        expect(fields.keys, isNot(contains('v')));
        expect(fields.keys, contains('y'));
      },
    );

    test('a missing superclass constructor is an error', () async {
      var vm = await _load(
        'class A { A.only(); }\nclass B extends A { B() : super.other(); }\n'
        'int run() { B(); return 0; }',
      );
      await expectLater(_runVM(vm), throwsA(isA<ApolloVMRuntimeError>()));
    });

    test(
      'a superclass with no declared constructor accepts `super()`',
      () async {
        expect(
          await _run(
            'class A { int x = 3; }\nclass B extends A { B() : super(); }\n'
            'int run() { var b = B(); return b.x; }',
          ),
          equals(3),
        );
      },
    );
  });

  group('Redirecting constructors', () {
    test('`this(…)` and `this.named(…)` delegate, bodies included', () async {
      expect(
        await _run(
          'class C {\n'
          '  int v; int calls = 0;\n'
          '  C(this.v) { this.calls = this.calls + 1; }\n'
          '  C.one() : this(1);\n'
          '  C.again() : this.one();\n'
          '}\n'
          'int run() { var c = C.again(); return c.v * 10 + c.calls; }',
        ),
        equals(11),
      );
    });

    test('a redirect cycle is an error, not a stack overflow', () async {
      var vm = await _load(
        'class C { C.a() : this.b(); C.b() : this.a(); }\n'
        'int run() { C.a(); return 0; }',
      );
      await expectLater(
        _runVM(vm),
        throwsA(
          isA<ApolloVMRuntimeError>().having(
            (e) => e.toString(),
            'message',
            contains('redirects to itself'),
          ),
        ),
      );
    });

    test('a redirect with other initializers or a body is an error', () async {
      // An *empty* body (`{ }`) can't be told apart from `;` once parsed, so
      // only a body with statements is caught.
      for (var ctor in [
        'C.r() : x = 1, this(2);',
        'C.r() : this(2) { this.x = 3; }',
      ]) {
        var vm = await _load(
          'class C { int x = 0; C(this.x); $ctor }\nint run() { C.r(); return 0; }',
        );
        await expectLater(
          _runVM(vm),
          throwsA(isA<ApolloVMRuntimeError>()),
          reason: ctor,
        );
      }
    });

    test('a redirect to a factory is an error', () async {
      var vm = await _load(
        'class C { C._(); factory C.f() { return C._(); } C.g() : this.f(); }\n'
        'int run() { C.g(); return 0; }',
      );
      await expectLater(_runVM(vm), throwsA(isA<ApolloVMRuntimeError>()));
    });
  });

  group('Factory constructors', () {
    test('unnamed, named and arrow-bodied factories', () async {
      expect(await _run(_factory), equals(_factoryResult));
    });

    test('a factory can return an existing instance', () async {
      expect(
        await _run(
          'class C {\n'
          '  static int made = 0;\n'
          '  int id;\n'
          '  C._(this.id) { C.made = C.made + 1; }\n'
          '  factory C.reuse(C c) { return c; }\n'
          '}\n'
          'int run() { var a = C._(9); var b = C.reuse(a); return b.id * 10 + C.made; }',
        ),
        equals(91),
      );
    });

    test('a factory that returns nothing is an error', () async {
      var vm = await _load(
        'class C { C._(); factory C() { var x = 1; } }\nint run() { C(); return 0; }',
      );
      await expectLater(_runVM(vm), throwsA(isA<ApolloVMRuntimeError>()));
    });

    test('an untyped arrow method is not read as a constructor', () async {
      // Only a factory takes `=>`: the constructor rule doesn't check the
      // class name, so a generative `=>` form silently turned this method into
      // a second constructor. An untyped method doesn't parse at all (the
      // optional return type swallows its name), so it must stay an error.
      var vm = ApolloVM();
      await expectLater(
        vm.loadCodeUnit(
          SourceCodeUnit(
            'dart',
            'class A { int v = 1; A(); describe() => "d"; }',
            id: 'test',
          ),
        ),
        throwsA(isA<SyntaxError>()),
      );

      // Typed, it is an ordinary method.
      expect(
        await _run(
          'class A { int v = 1; A(); String describe() => "d"; }\n'
          'String run() { var a = A(); return a.describe(); }',
        ),
        equals('d'),
      );
    });

    test(
      '`factory` is a whole word: `factoryReset()` is still a method',
      () async {
        expect(
          await _run(
            'class C { int v = 1; int factoryReset() { return 0; } }\n'
            'int run() { return C().factoryReset(); }',
          ),
          equals(0),
        );
      },
    );
  });

  group('Dart generation', () {
    test('every form is written back as declared', () async {
      var code = await _dartOf(
        await _load(
          '$_named\n$_initializers'.replaceAll('int run()', 'int r()'),
        ),
      );
      expect(code, contains('P.origin() : x = 0, y = 0;'));
      expect(code, contains('P.diagonal(int v) : this(v, v);'));
      expect(code, contains('P.fromX(this.x, {int y = 5}) {'));
      expect(code, contains('assert(w > 0), w = w, h = h, area = w * h;'));

      code = await _dartOf(await _load(_super));
      expect(code, contains(': y = v, super(v + 1) {'));
      expect(code, contains(': y = 0, super.named(v) {'));

      code = await _dartOf(await _load(_factory));
      expect(code, contains('factory Shape(String k) {'));
      expect(code, contains('factory Shape.square() {'));
    });

    test('the generated Dart runs the same', () async {
      expect(await _runRegenerated(_named), equals(_namedResult));
      expect(await _runRegenerated(_initializers), equals(19));
      expect(await _runRegenerated(_super), equals(_superResult));
      expect(await _runRegenerated(_factory), equals(_factoryResult));
    });
  });

  group('Binary AST', () {
    test('every form survives an image round-trip', () async {
      expect(await _runFromImage(_named), equals(_namedResult));
      expect(await _runFromImage(_initializers), equals(19));
      expect(await _runFromImage(_super), equals(_superResult));
      expect(await _runFromImage(_factory), equals(_factoryResult));
    });

    test('a plain constructor keeps its original encoding', () async {
      var vm = await _load(_named);
      var plain = _ctor(vm, 'P', '');
      var withBody = _ctor(vm, 'P', 'fromX');
      var withInitializers = _ctor(vm, 'P', 'origin');

      expect(
        ASTCodecRegistry.codecFor(plain).tag,
        equals(ASTNodeTag.classConstructorDeclaration),
      );
      // A named constructor without an initializer list needs no new data.
      expect(
        ASTCodecRegistry.codecFor(withBody).tag,
        equals(ASTNodeTag.classConstructorDeclaration),
      );
      expect(
        ASTCodecRegistry.codecFor(withInitializers).tag,
        equals(ASTNodeTag.classConstructorDeclarationExtended),
      );
      // The per-type cache must not hand the plain codec to the next one.
      expect(
        ASTCodecRegistry.codecFor(plain).tag,
        equals(ASTNodeTag.classConstructorDeclaration),
      );

      var factory = _ctor(await _load(_factory), 'Shape', 'square');
      expect(
        ASTCodecRegistry.codecFor(factory).tag,
        equals(ASTNodeTag.classConstructorDeclarationExtended),
      );
    });
  });

  group('Other targets', () {
    const targets = [
      'java11',
      'kotlin',
      'csharp',
      'go',
      'javascript',
      'typescript',
      'python',
      'lua',
    ];

    for (var (label, src) in [
      ('a named constructor', 'class C { int v; C.of(this.v); }'),
      ('an initializer list', 'class C { int v; C(int x) : v = x; }'),
      ('a factory', 'class C { C._(); factory C() { return C._(); } }'),
    ]) {
      test('refuse $label instead of dropping it', () async {
        var vm = await _load(src);
        for (var lang in targets) {
          await expectLater(
            () async =>
                (await vm.generateAllCodeIn(lang).writeAllSources()).toString(),
            throwsA(isA<UnsupportedSyntaxError>()),
            reason: lang,
          );
        }
      });
    }

    test('the Wasm compiler refuses them too', () async {
      // Compilation only — no Wasm runtime is needed to see the refusal.
      for (var src in [
        'class C { int v; C.of(this.v); }\nint run() { return 1; }',
        'class C { int v; C(int x) : v = x; }\nint run() { return 1; }',
        'class C { C._(); factory C() { return C._(); } }\nint run() { return 1; }',
      ]) {
        var vm = await _load(src);
        await expectLater(
          () => vm.generateAllIn<BytesOutput>('wasm').allEntries(),
          throwsA(isA<UnsupportedSyntaxError>()),
          reason: src,
        );
      }

      var plain = await _load(
        'class C { int v; C(this.v); }\nint run() { var c = C(2); return c.v; }',
      );
      var modules = await plain.generateAllIn<BytesOutput>('wasm').allEntries();
      expect(modules, isNotEmpty);
    });

    test('a plain class still translates', () async {
      var vm = await _load('class C { int v; C(this.v); }');
      for (var lang in targets) {
        var code = (await vm.generateAllCodeIn(lang).writeAllSources())
            .toString();
        expect(code, contains('C'), reason: lang);
      }
    });
  });
}
