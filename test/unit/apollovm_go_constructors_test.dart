@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

Future<ApolloVM> _load(String language, String src) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit(language, src, id: 'test'));
  expect(ok, isTrue, reason: "Can't load $language source");
  return vm;
}

Future<String> _generateGo(ApolloVM vm) async {
  var storage = vm.generateAllCodeIn('go');
  await storage.writeAllSources();
  for (var ns in await storage.getNamespaces()) {
    for (var id in await storage.getNamespaceCodeUnitsIDs(ns)) {
      return (await storage.getNamespaceCodeUnit(ns, id))!;
    }
  }
  throw StateError('no generated source');
}

/// Go has no classes: a class is a `type X struct` plus receiver methods and a
/// `func NewX(...) *X` factory. None of that could previously be parsed back.
const _goSource = '''
package main

type Point struct {
  x int
  y int
}

func NewPoint(x int, y int) *Point {
  o := &Point{}
  o.x = x
  o.y = y
  return o
}

func (o *Point) sum() int {
  return o.x + o.y
}

func run() int {
  p := NewPoint(40, 2)
  return p.sum()
}
''';

void main() {
  group('Go constructors', () {
    test('a factory and its `&T{}` composite literal parse', () async {
      var vm = await _load('go', _goSource);
      var point = vm.getLanguageNamespaces('go').getClass('Point');
      expect(point, isNotNull);
      expect(point!.constructors, isNotEmpty);
    });

    test('a factory runs, binding `o` to the instance', () async {
      var vm = await _load('go', _goSource);
      var result = await vm.createRunner('go')!.executeFunction('', 'run');
      expect(result.getValueNoContext(), equals(42));
    });

    test('a struct literal with fields is not supported', () async {
      // Only the zero-valued `&T{}` form is parsed.
      expect(
        () => _load(
          'go',
          'package main\n\ntype P struct {\n  x int\n}\n\n'
              'func NewP() *P {\n  o := &P{x: 1}\n  return o\n}\n',
        ),
        throwsA(anything),
      );
    });
  });

  group('Go code generation', () {
    test('every struct gets a factory, and instantiation calls it', () async {
      var vm = await _load(
        'dart',
        'class Point { int x; Point(int x) { this.x = x; } int get2() { return this.x; } }\n'
            'class Foo { int test() { var p = Point(7); return p.get2(); } }',
      );

      var go = await _generateGo(vm);

      expect(go, contains('func NewPoint(x int) *Point {'));
      // A field-less struct still gets a factory, so `NewFoo()` always exists.
      expect(go, contains('func NewFoo() *Foo {'));
      // Go has no `new`: instantiation goes through the factory.
      expect(go, contains('p := NewPoint(7)'));
      expect(go, isNot(contains('p := Point(7)')));
    });

    test(
      'a parameter shadowing a field is not rewritten to `o.field`',
      () async {
        var vm = await _load(
          'dart',
          'class Point { int x; Point(int x) { this.x = x; } }',
        );

        var go = await _generateGo(vm);

        expect(go, contains('o.x = x'));
        expect(
          go,
          isNot(contains('o.x = o.x')),
          reason: 'the constructor parameter `x` shadows the field `x`',
        );
      },
    );

    test('generated Go parses back and runs', () async {
      var vm = await _load(
        'dart',
        'class Point { int x; int y; Point(int x, int y) { this.x = x; this.y = y; }\n'
            '  int sum() { return this.x + this.y; } }\n'
            'class Foo { int test(int a) { var p = Point(a, 2); return p.sum(); } }',
      );

      var go = await _generateGo(vm);

      var reloaded = await _load('go', go);
      var result = await reloaded
          .createRunner('go')!
          .executeClassMethod(
            '',
            'Foo',
            'test',
            positionalParameters: [40],
            classInstanceFields: const {},
          );
      expect(result.getValueNoContext(), equals(42));
    });
  });
}
