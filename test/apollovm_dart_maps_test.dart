library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Runs [functionName] via the Dart AST interpreter and asserts the return.
Future<void> _testReturn(
  String code,
  String functionName,
  List args,
  Object? expectedReturn,
) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', code, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source:\n$code");

  var runner = vm.createRunner('dart')!;
  var ret = await runner.executeFunction(
    '',
    functionName,
    positionalParameters: args,
  );
  expect(ret.getValueNoContext(), expectedReturn);
}

void main() {
  group('Dart maps: typed declarations + literals', () {
    test('Map<int,int> declaration parses and runs', () async {
      await _testReturn(
        '''
        int f() {
          Map<int,int> m = {1: 10, 2: 20};
          return 1;
        }
      ''',
        'f',
        [],
        1,
      );
    });

    test('Map<String,int> declaration', () async {
      await _testReturn(
        '''
        int f() {
          Map<String,int> m = {"a": 1, "b": 2};
          return m.length;
        }
      ''',
        'f',
        [],
        2,
      );
    });

    test('Map<String,List<int>> nested value type', () async {
      await _testReturn(
        '''
        int f() {
          Map<String,List<int>> m = {"a": [1, 2, 3]};
          return m.length;
        }
      ''',
        'f',
        [],
        1,
      );
    });
  });

  group('Dart maps: index read by key', () {
    test('int key', () async {
      await _testReturn(
        '''
        int f() {
          Map<int,int> m = {1: 10, 2: 20, 3: 30};
          return m[2];
        }
      ''',
        'f',
        [],
        20,
      );
    });

    test('String key', () async {
      await _testReturn(
        '''
        int f() {
          Map<String,int> m = {"x": 7, "y": 8};
          return m["y"];
        }
      ''',
        'f',
        [],
        8,
      );
    });

    test('String value', () async {
      await _testReturn(
        '''
        String f() {
          Map<int,String> m = {1: "one", 2: "two"};
          return m[2];
        }
      ''',
        'f',
        [],
        'two',
      );
    });

    test('index with a variable key', () async {
      await _testReturn(
        '''
        int f(int k) {
          Map<int,int> m = {1: 10, 2: 20};
          return m[k];
        }
      ''',
        'f',
        [2],
        20,
      );
    });
  });

  group('Dart maps: getters and methods', () {
    test('.length', () async {
      await _testReturn(
        '''
        int f() {
          Map<int,int> m = {1: 1, 2: 2, 3: 3, 4: 4};
          return m.length;
        }
      ''',
        'f',
        [],
        4,
      );
    });

    test('.isEmpty / .isNotEmpty', () async {
      await _testReturn(
        '''
        bool f() {
          Map<int,int> m = {1: 1};
          return m.isNotEmpty;
        }
      ''',
        'f',
        [],
        true,
      );
    });

    test('.containsKey true', () async {
      await _testReturn(
        '''
        bool f() {
          Map<String,int> m = {"a": 1, "b": 2};
          return m.containsKey("b");
        }
      ''',
        'f',
        [],
        true,
      );
    });

    test('.containsKey false', () async {
      await _testReturn(
        '''
        bool f() {
          Map<String,int> m = {"a": 1};
          return m.containsKey("z");
        }
      ''',
        'f',
        [],
        false,
      );
    });

    test('.containsValue', () async {
      await _testReturn(
        '''
        bool f() {
          Map<String,int> m = {"a": 1, "b": 2};
          return m.containsValue(2);
        }
      ''',
        'f',
        [],
        true,
      );
    });
  });

  group('Dart maps: keys / values iteration', () {
    test('sum keys via for-each', () async {
      await _testReturn(
        '''
        int f() {
          Map<int,int> m = {1: 100, 2: 200, 3: 300};
          int s = 0;
          for (var k in m.keys) {
            s = s + k;
          }
          return s;
        }
      ''',
        'f',
        [],
        6,
      );
    });

    test('sum values via for-each', () async {
      await _testReturn(
        '''
        int f() {
          Map<int,int> m = {1: 100, 2: 200, 3: 300};
          int s = 0;
          for (var v in m.values) {
            s = s + v;
          }
          return s;
        }
      ''',
        'f',
        [],
        600,
      );
    });
  });

  group('Dart maps: parameters', () {
    test('map parameter index read', () async {
      await _testReturn(
        '''
        int f(Map<int,int> m) {
          return m[1];
        }
      ''',
        'f',
        [
          {1: 99},
        ],
        99,
      );
    });

    test('map parameter length', () async {
      await _testReturn(
        '''
        int f(Map<String,int> m) {
          return m.length;
        }
      ''',
        'f',
        [
          {'a': 1, 'b': 2, 'c': 3},
        ],
        3,
      );
    });
  });
}
