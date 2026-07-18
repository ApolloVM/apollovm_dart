@TestOn('vm')
@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

Future<Object?> _run(String source) async {
  var vm = ApolloVM();
  expect(
    await vm.loadCodeUnit(SourceCodeUnit('dart', source, id: 'test')),
    isTrue,
    reason: 'cannot parse',
  );
  var r = await vm
      .createRunner('dart')!
      .executeFunction('', 'run', positionalParameters: const []);
  return r.getValueNoContext();
}

void main() {
  group('Nested index read', () {
    test('nested list m[0][1]', () async {
      expect(
        await _run('int run() { var m = [[1, 2], [3, 4]]; return m[0][1]; }'),
        equals(2),
      );
    });

    test('nested list m[1][0]', () async {
      expect(
        await _run('int run() { var m = [[1, 2], [3, 4]]; return m[1][0]; }'),
        equals(3),
      );
    });

    test('map of list m[key][i]', () async {
      expect(
        await _run("int run() { var m = {'a': [10, 20]}; return m['a'][1]; }"),
        equals(20),
      );
    });

    test('nested map m[a][b]', () async {
      expect(
        await _run(
          "int run() { var m = {'a': {'b': 7}}; return m['a']['b']; }",
        ),
        equals(7),
      );
    });

    test('triple-nested m[0][0][0]', () async {
      expect(
        await _run('int run() { var m = [[[5]]]; return m[0][0][0]; }'),
        equals(5),
      );
    });

    test('nested access inside a larger expression', () async {
      expect(
        await _run(
          'int run() { var m = [[1, 2], [3, 4]]; return m[0][1] + m[1][0]; }',
        ),
        equals(5),
      );
    });
  });

  group('Nested index write', () {
    test('nested list m[0][1] = v', () async {
      expect(
        await _run(
          'int run() { var m = [[1, 2], [3, 4]]; m[0][1] = 9; return m[0][1]; }',
        ),
        equals(9),
      );
    });

    test('nested list compound m[1][0] += v', () async {
      expect(
        await _run(
          'int run() { var m = [[1, 2], [3, 4]];'
          ' m[1][0] += 5; return m[1][0]; }',
        ),
        equals(8),
      );
    });

    test('nested map m[a][b] = v', () async {
      expect(
        await _run(
          "int run() { var m = {'a': {'b': 7}};"
          " m['a']['b'] = 99; return m['a']['b']; }",
        ),
        equals(99),
      );
    });

    test('map of list write m[key][i] = v', () async {
      expect(
        await _run(
          "int run() { var m = {'a': [10, 20]};"
          " m['a'][0] = 1; return m['a'][0]; }",
        ),
        equals(1),
      );
    });

    test('triple-nested write m[0][0][0] = v', () async {
      expect(
        await _run(
          'int run() { var m = [[[5]]]; m[0][0][0] = 8; return m[0][0][0]; }',
        ),
        equals(8),
      );
    });
  });

  group('Single index (regression guard)', () {
    test('list read/write unchanged', () async {
      expect(
        await _run('int run() { var a = [5, 6, 7]; a[1] = 60; return a[1]; }'),
        equals(60),
      );
    });

    test('map read/write and compound unchanged', () async {
      expect(
        await _run(
          "int run() { var m = {'k': 1}; m['k'] = 42; return m['k']; }",
        ),
        equals(42),
      );
      expect(
        await _run(
          "int run() { var m = {'k': 1}; m['k'] += 5; return m['k']; }",
        ),
        equals(6),
      );
    });
  });

  group('Nested index generation', () {
    test('a nested access/assignment emits chained `[..]`', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(
        SourceCodeUnit(
          'dart',
          'int run() { var m = [[1, 2]]; m[0][1] = 9; return m[0][1]; }',
          id: 'test',
        ),
      );
      var storage = vm.generateAllCodeIn('dart');
      var buf = StringBuffer();
      for (var ns in await storage.getNamespaces()) {
        for (var id in await storage.getNamespaceCodeUnitsIDs(ns)) {
          buf.write(await storage.getNamespaceCodeUnit(ns, id));
        }
      }
      var generated = buf.toString();
      expect(generated, contains('m[0][1] = 9'));
      expect(generated, contains('return m[0][1]'));
    });
  });
}
