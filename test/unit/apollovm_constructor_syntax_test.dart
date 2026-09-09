@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:apollovm/apollovm_serialization.dart';
import 'package:test/test.dart';

/// Primary constructors (Dart 3.13) and private named parameters (Dart 3.12):
/// the cases the XML corpus can't express — a *refused* call site, and what the
/// desugared class looks like from the outside.

Future<ApolloVM> _load(String src) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', src, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source");
  return vm;
}

Future<Object?> _run(String src) async {
  var vm = await _load(src);
  var res = await vm.createRunner('dart')!.executeFunction('', 'run');
  return res.getValueNoContext();
}

void main() {
  group('Primary constructors', () {
    test('`final` and `var` parameters declare the fields', () async {
      expect(
        await _run(
          'class P(final int x, var int y) {}\n'
          'int run() { var p = P(1, 2); p.y = 10; return p.x + p.y; }',
        ),
        equals(11),
      );
    });

    test('a header-only class needs no body', () async {
      expect(
        await _run(
          'class P(final int x);\nint run() { var p = P(7); return p.x; }',
        ),
        equals(7),
      );
    });

    test('an untyped declaring parameter gets a dynamic field', () async {
      expect(
        await _run(
          'class P(var v);\nString run() { var p = P("s"); return p.v; }',
        ),
        equals('s'),
      );
    });

    test('named and optional-positional groups, with defaults', () async {
      expect(
        await _run(
          "class P(final int x, [final int y = 9]) {}\n"
          'int run() { var p = P(1); return p.x + p.y; }',
        ),
        equals(10),
      );
      expect(
        await _run(
          "class P({required final int x, final String tag = 't'}) {}\n"
          "String run() { var p = P(x: 2); return '\${p.x}\${p.tag}'; }",
        ),
        equals('2t'),
      );
    });

    test('a parameter without `var`/`final` declares no field', () async {
      var vm = await _load('class P(final int x, int ignored) {}');
      var clazz = vm.allCodeUnitsAllLanguages().single.root!.getClass('P')!;
      expect(clazz.fieldsNames, equals(['x']));
    });

    test('coexists with a body, `extends` and `implements`', () async {
      expect(
        await _run(
          'abstract class Base { int base(); }\n'
          'class P(final int x) implements Base {\n'
          '  int base() { return 2; }\n'
          '  int twice() { return this.x * 2; }\n'
          '}\n'
          'int run() { var p = P(4); return p.twice() + p.base(); }',
        ),
        equals(10),
      );
    });

    test('a plain class declaration still parses', () async {
      expect(
        await _run(
          'class A { int x = 1; }\nint run() { var a = A(); return a.x; }',
        ),
        equals(1),
      );
    });

    test('the desugared form round-trips through the binary AST', () async {
      var vm = await _load(
        'class P(final int x, var int y) { int sum() { return this.x + this.y; } }\n'
        'int run() { var p = P(3, 4); return p.sum(); }',
      );

      var image = vm.saveCodeUnitAST(vm.allCodeUnitsAllLanguages().single);

      var vm2 = ApolloVM();
      expect(await vm2.loadCodeUnitAST(image), isTrue);
      var res = await vm2.createRunner('dart')!.executeFunction('', 'run');
      expect(res.getValueNoContext(), equals(7));
    });
  });

  group('The private → public name rule', () {
    String? publicOf(String name) =>
        ASTConstructorParameterDeclaration.publicNameOfPrivate(name);

    test('a private name loses its leading underscore', () {
      expect(publicOf('_x'), equals('x'));
      expect(publicOf('_someName'), equals('someName'));
      expect(publicOf(r'_$a'), equals(r'$a'));
    });

    test('a name with no public form is left alone', () {
      expect(publicOf('x'), isNull, reason: 'already public');
      expect(publicOf('__x'), isNull, reason: 'still private');
      expect(publicOf('_'), isNull, reason: 'nothing left');
      expect(publicOf('_1'), isNull, reason: 'would start with a digit');
    });

    test('a parameter with no public form keeps its private name', () async {
      expect(
        await _run(
          'class P { final int _1; P({required this._1}); int get v => this._1; }\n'
          'int run() { var p = P(_1: 8); return p.v; }',
        ),
        equals(8),
      );
    });
  });

  group('Private named parameters', () {
    const point =
        'class Point {\n'
        '  final int _x;\n'
        '  Point({required this._x});\n'
        '  int get x => this._x;\n'
        '}\n';

    test('the caller passes the public name', () async {
      expect(
        await _run('${point}int run() { var p = Point(x: 5); return p.x; }'),
        equals(5),
      );
    });

    test('the private name is not a call-site name', () async {
      var vm = await _load(
        '${point}int run() { var p = Point(_x: 5); return p.x; }',
      );
      await expectLater(
        vm.createRunner('dart')!.executeFunction('', 'run'),
        throwsA(isA<ApolloVMRuntimeError>()),
      );
    });

    test('a positional initializing formal keeps its name', () async {
      expect(
        await _run(
          'class P { final int _x; P(this._x); int get x => this._x; }\n'
          'int run() { var p = P(4); return p.x; }',
        ),
        equals(4),
      );
    });

    test('`__x` and `_` have no public name, so they are left alone', () async {
      expect(
        await _run(
          'class P { final int __x; P({required this.__x}); '
          'int get x => this.__x; }\n'
          'int run() { var p = P(__x: 3); return p.x; }',
        ),
        equals(3),
      );
    });

    test('the declaration keeps `this._x` when generating Dart', () async {
      var vm = await _load(point);
      var code = (await vm.generateAllCodeIn('dart').writeAllSources())
          .toString();
      expect(code, contains('Point({required this._x});'));
    });

    test('the rename survives the binary AST', () async {
      var vm = await _load(
        '${point}int run() { var p = Point(x: 6); return p.x; }',
      );
      var image = vm.saveCodeUnitAST(vm.allCodeUnitsAllLanguages().single);

      var vm2 = ApolloVM();
      expect(await vm2.loadCodeUnitAST(image), isTrue);
      var res = await vm2.createRunner('dart')!.executeFunction('', 'run');
      expect(res.getValueNoContext(), equals(6));
    });
  });
}
