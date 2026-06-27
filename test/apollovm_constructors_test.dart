@Tags(['javascript', 'python', 'dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Loads [src] in [language] and runs `Main.run([])`, which instantiates a
/// `Point(10, 32)` and returns `point.sum()` (== 42). Exercises constructors,
/// `this`/`self` field assignment, and instantiation.
Future<Object?> _runMain(String language, String src) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit(language, src, id: 'test'));
  expect(ok, isTrue, reason: "Can't load $language source");
  var runner = vm.createRunner(language)!;
  var res = await runner.executeClassMethod(
    '',
    'Main',
    'run',
    positionalParameters: [const []],
    classInstanceFields: const {},
  );
  return res.getValueNoContext();
}

/// Translates [src] from [language] to Dart, reloads the generated Dart in a
/// fresh VM, and runs `Main.run([])` — proving the constructor and field
/// assignment round-trip across languages.
Future<Object?> _runViaDart(String language, String src) async {
  var vm = ApolloVM();
  await vm.loadCodeUnit(SourceCodeUnit(language, src, id: 'test'));
  var dart = (await vm
      .generateAllCodeIn('dart')
      .getNamespaceCodeUnit('', 'test'))!;

  var vm2 = ApolloVM();
  var ok = await vm2.loadCodeUnit(SourceCodeUnit('dart', dart, id: 'test'));
  expect(ok, isTrue, reason: 'Generated Dart should load:\n$dart');
  var runner = vm2.createRunner('dart')!;
  var res = await runner.executeClassMethod(
    '',
    'Main',
    'run',
    positionalParameters: [const []],
    classInstanceFields: const {},
  );
  return res.getValueNoContext();
}

const _jsSource = r'''
  class Point {
    constructor(x, y) {
      this.x = x;
      this.y = y;
    }
    sum() { return this.x + this.y; }
  }
  class Main {
    run(args) {
      var p = new Point(10, 32);
      return p.sum();
    }
  }
''';

const _pySource = '''
class Point:
    def __init__(self, x, y):
        self.x = x
        self.y = y
    def sum(self):
        return self.x + self.y

class Main:
    def run(self, args):
        p = Point(10, 32)
        return p.sum()
''';

void main() {
  group('JavaScript: constructors & instantiation', () {
    test('`new Foo(...)` constructs, assigns fields, and runs', () async {
      expect(await _runMain('javascript', _jsSource), equals(42));
    });

    test('`Foo(...)` without `new` also constructs', () async {
      var src = _jsSource.replaceFirst('new Point(10, 32)', 'Point(10, 32)');
      expect(await _runMain('javascript', src), equals(42));
    });

    test('round-trips `constructor` and `this.x`', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(
        SourceCodeUnit('javascript', _jsSource, id: 'test'),
      );
      var js = (await vm
          .generateAllCodeIn('javascript')
          .getNamespaceCodeUnit('', 'test'))!;
      expect(js, contains('constructor('));
      expect(js, contains('this.x'));
    });

    test('translates to Dart and runs (constructor round-trips)', () async {
      expect(await _runViaDart('javascript', _jsSource), equals(42));
    });
  });

  group('Python: constructors & instantiation', () {
    test(
      '`__init__` + `self.x = …` + `Foo(...)` constructs and runs',
      () async {
        expect(await _runMain('python', _pySource), equals(42));
      },
    );

    test('round-trips `def __init__(self` and `self.x`', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(SourceCodeUnit('python', _pySource, id: 'test'));
      var py = (await vm
          .generateAllCodeIn('python')
          .getNamespaceCodeUnit('', 'test'))!;
      expect(py, contains('def __init__(self'));
      expect(py, contains('self.x'));
    });

    test('translates to Dart and runs (constructor round-trips)', () async {
      expect(await _runViaDart('python', _pySource), equals(42));
    });
  });
}
