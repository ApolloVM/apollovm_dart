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

  group('Dart maps: subscript assignment m[k] = v', () {
    test('add a new key', () async {
      await _testReturn(
        '''
        int f() {
          Map<int,int> m = {1: 10};
          m[2] = 20;
          return m[2];
        }
      ''',
        'f',
        [],
        20,
      );
    });

    test('update an existing key', () async {
      await _testReturn(
        '''
        int f() {
          Map<int,int> m = {1: 10};
          m[1] = 99;
          return m[1];
        }
      ''',
        'f',
        [],
        99,
      );
    });

    test('set with String key', () async {
      await _testReturn(
        '''
        int f() {
          Map<String,int> m = {"a": 1};
          m["b"] = 2;
          return m["b"];
        }
      ''',
        'f',
        [],
        2,
      );
    });

    test('set grows length', () async {
      await _testReturn(
        '''
        int f() {
          Map<int,int> m = {1: 10};
          m[2] = 20;
          m[3] = 30;
          return m.length;
        }
      ''',
        'f',
        [],
        3,
      );
    });

    test('set with a variable key', () async {
      await _testReturn(
        '''
        int f(int k) {
          Map<int,int> m = {1: 10};
          m[k] = 77;
          return m[k];
        }
      ''',
        'f',
        [5],
        77,
      );
    });

    test('set a String value', () async {
      await _testReturn(
        '''
        String f() {
          Map<int,String> m = {1: "a"};
          m[2] = "b";
          return m[2];
        }
      ''',
        'f',
        [],
        'b',
      );
    });

    test('compound += on a key', () async {
      await _testReturn(
        '''
        int f() {
          Map<int,int> m = {1: 10};
          m[1] += 5;
          return m[1];
        }
      ''',
        'f',
        [],
        15,
      );
    });

    test('build a frequency map', () async {
      await _testReturn(
        '''
        int f() {
          Map<String,int> m = {};
          m["x"] = 0;
          m["x"] += 1;
          m["x"] += 1;
          m["x"] += 1;
          return m["x"];
        }
      ''',
        'f',
        [],
        3,
      );
    });
  });

  group('Dart lists: index assignment a[i] = v', () {
    test('assign by index', () async {
      await _testReturn(
        '''
        int f() {
          List<int> a = [1, 2, 3];
          a[1] = 99;
          return a[1];
        }
      ''',
        'f',
        [],
        99,
      );
    });

    test('compound += by index', () async {
      await _testReturn(
        '''
        int f() {
          List<int> a = [1, 2, 3];
          a[0] += 10;
          return a[0];
        }
      ''',
        'f',
        [],
        11,
      );
    });

    test('reverse a list in place', () async {
      await _testReturn(
        '''
        int f() {
          List<int> a = [1, 2, 3, 4, 5];
          a[0] = 5;
          a[1] = 4;
          a[3] = 2;
          a[4] = 1;
          return a[0] + a[4];
        }
      ''',
        'f',
        [],
        6,
      );
    });
  });
}
