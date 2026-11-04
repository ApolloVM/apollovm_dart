@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:apollovm/apollovm_serialization.dart';
import 'package:test/test.dart';

/// Reading a getter by its bare name inside a class or extension member
/// (`return value;`, not just `this.value`).

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

void main() {
  group('Bare getter reads', () {
    test('from a method and from another getter', () async {
      expect(
        await _run(
          'class C { int _v = 3; int get value => _v; '
          'int twice() { return value * 2; } int get dbl => value * 2; }\n'
          'int run() { var c = C(); return c.twice() + c.dbl * 10; }',
        ),
        equals(66),
      );
    });

    test('an inherited getter', () async {
      expect(
        await _run(
          'class A { int get value => 4; }\n'
          'class B extends A { int f() { return value + 1; } }\n'
          'int run() { var b = B(); return b.f(); }',
        ),
        equals(5),
      );
    });

    test('the getter runs on the receiver, overrides included', () async {
      expect(
        await _run(
          'class A { int get value => 1; int f() { return value; } }\n'
          'class B extends A { int get value => 2; }\n'
          'int run() { var b = B(); return b.f(); }',
        ),
        equals(2),
      );
    });

    test('a local or a parameter of the same name shadows it', () async {
      expect(
        await _run(
          'class C { int get value => 3; '
          'int f() { var value = 10; return value; } int g(int value) { return value; } }\n'
          'int run() { var c = C(); return c.f() + c.g(7); }',
        ),
        equals(17),
      );
    });

    test('it wins over a top-level function of the same name', () async {
      expect(
        await _run(
          'int value() { return 99; }\n'
          'class C { int get value => 3; int f() { return value; } }\n'
          'int run() { var c = C(); return c.f(); }',
        ),
        equals(3),
      );
    });

    test('with a setter, in a compound assignment', () async {
      expect(
        await _run(
          'class C { int _v = 1; int get v => _v; set v(int x) { _v = x; } '
          'int f() { v = v + 5; return v; } }\n'
          'int run() { var c = C(); return c.f(); }',
        ),
        equals(6),
      );
    });

    test('`v++` / `v--` go through the setter, not a temporary', () async {
      expect(
        await _run(
          'class A { int _v = 0; int get v => _v; set v(int n) { _v = n; } '
          'void inc() { v++; } void dec() { --v; } }\n'
          'int run() { var a = A(); a.inc(); a.inc(); a.inc(); a.dec(); return a.v; }',
        ),
        equals(2),
      );
    });

    test('`v++` on a getter without a setter is an error', () async {
      var vm = await _load(
        'class A { int get v => 1; void inc() { v++; } }\n'
        'int run() { var a = A(); a.inc(); return 0; }',
      );
      await expectLater(
        _runVM(vm),
        throwsA(
          isA<ApolloVMRuntimeError>().having(
            (e) => e.toString(),
            'message',
            contains('no setter'),
          ),
        ),
      );
    });

    test('`i++` on a local and on a field still works', () async {
      expect(
        await _run(
          'class A { int n = 0; int f() { for (var i = 0; i < 3; i++) { n++; } return n; } }\n'
          'int run() { var a = A(); return a.f(); }',
        ),
        equals(3),
      );
    });

    test('one extension member reads another', () async {
      expect(
        await _run(
          'extension E on int { int get dbl => this * 2; int quad() { return dbl * 2; } }\n'
          'int run() { var n = 3; return n.quad(); }',
        ),
        equals(12),
      );
    });

    test('an unknown name is still an error', () async {
      var vm = await _load(
        'class C { int f() { return nope; } }\nint run() { var c = C(); return c.f(); }',
      );
      await expectLater(_runVM(vm), throwsA(isA<StateError>()));
    });

    test('survives the binary AST and Dart regeneration', () async {
      const src =
          'class C { int _v = 3; int get value => _v; int twice() { return value * 2; } }\n'
          'int run() { var c = C(); return c.twice(); }';

      var vm = await _load(src);
      var image = vm.saveCodeUnitAST(vm.allCodeUnitsAllLanguages().single);
      var vm2 = ApolloVM();
      expect(await vm2.loadCodeUnitAST(image), isTrue);
      expect(await _runVM(vm2), equals(6));

      var code = (await vm
          .generateAllCodeIn('dart')
          .getNamespaceCodeUnit('', 'test'))!;
      expect(await _runVM(await _load(code)), equals(6));
    });
  });
}
