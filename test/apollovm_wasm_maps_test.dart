library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Runs [functionName] via the AST interpreter AND the compiled+executed Wasm
/// module and asserts both return [expectedReturn].
Future<void> _testWasmReturn(
  String code,
  String functionName,
  List args,
  Object? expectedReturn,
) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', code, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source");

  var astRunner = vm.createRunner('dart')!;
  var astRet = await astRunner.executeFunction(
    '',
    functionName,
    positionalParameters: args,
  );
  expect(astRet.getValueNoContext(), expectedReturn, reason: 'interpreter');

  var storageWasm = vm.generateAllIn<BytesOutput>('wasm');
  var wasmModules = await storageWasm.allEntries();
  BytesOutput? compiled;
  for (var ns in wasmModules.entries) {
    for (var m in ns.value.entries) {
      compiled ??= m.value;
    }
  }
  expect(compiled, isNotNull, reason: 'No compiled Wasm module');

  var rt = WasmRuntime()..ensureBooted();
  if (!rt.isSupported) {
    fail('Wasm runtime not supported (run `dart run wasm_run:setup`).');
  }

  var vmWasm = ApolloVM();
  await vmWasm.loadCodeUnit(
    BinaryCodeUnit('wasm', compiled!.output(), id: 'test.wasm', namespace: ''),
  );
  var wasmRunner = vmWasm.createRunner('wasm')!;
  var wasmRet = await wasmRunner.executeFunction(
    '',
    functionName,
    positionalParameters: args,
  );
  expect(wasmRet.getValueNoContext(), expectedReturn, reason: 'Wasm');
}

void main() {
  group('Wasm maps: int keys — literal + index get', () {
    test('get by constant key', () async {
      await _testWasmReturn(
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

    test('get by variable key', () async {
      await _testWasmReturn(
        '''
        int f(int k) {
          Map<int,int> m = {1: 10, 2: 20, 3: 30};
          return m[k];
        }
      ''',
        'f',
        [3],
        30,
      );
    });

    test('double value', () async {
      await _testWasmReturn(
        '''
        double f() {
          Map<int,double> m = {1: 1.5, 2: 2.5};
          return m[2];
        }
      ''',
        'f',
        [],
        2.5,
      );
    });

    test('String value', () async {
      await _testWasmReturn(
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
  });

  group('Wasm maps: .length / .isEmpty', () {
    test('length', () async {
      await _testWasmReturn(
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

    test('isEmpty on empty map', () async {
      await _testWasmReturn(
        '''
        bool f() {
          Map<int,int> m = {};
          return m.isEmpty;
        }
      ''',
        'f',
        [],
        true,
      );
    });

    test('isNotEmpty', () async {
      await _testWasmReturn(
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
  });

  group('Wasm maps: containsKey', () {
    test('present key', () async {
      await _testWasmReturn(
        '''
        bool f() {
          Map<int,int> m = {1: 10, 2: 20};
          return m.containsKey(2);
        }
      ''',
        'f',
        [],
        true,
      );
    });

    test('absent key', () async {
      await _testWasmReturn(
        '''
        bool f() {
          Map<int,int> m = {1: 10};
          return m.containsKey(9);
        }
      ''',
        'f',
        [],
        false,
      );
    });
  });

  group('Wasm maps: subscript assignment m[k] = v', () {
    test('update existing key', () async {
      await _testWasmReturn(
        '''
        int f() {
          Map<int,int> m = {1: 10, 2: 20};
          m[1] = 99;
          return m[1];
        }
      ''',
        'f',
        [],
        99,
      );
    });

    test('add a new key', () async {
      await _testWasmReturn(
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

    test('set grows the map (triggers realloc)', () async {
      await _testWasmReturn(
        '''
        int f() {
          Map<int,int> m = {1: 10};
          m[2] = 20;
          m[3] = 30;
          m[4] = 40;
          m[5] = 50;
          return m.length;
        }
      ''',
        'f',
        [],
        5,
      );
    });

    test('set from empty literal', () async {
      await _testWasmReturn(
        '''
        int f() {
          Map<int,int> m = {};
          m[5] = 50;
          m[6] = 60;
          return m[6];
        }
      ''',
        'f',
        [],
        60,
      );
    });

    test('set preserves earlier entries after realloc', () async {
      await _testWasmReturn(
        '''
        int f() {
          Map<int,int> m = {1: 11};
          m[2] = 22;
          m[3] = 33;
          m[4] = 44;
          return m[1];
        }
      ''',
        'f',
        [],
        11,
      );
    });

    test('set String value then read back', () async {
      await _testWasmReturn(
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

    test('count occurrences with a map', () async {
      await _testWasmReturn(
        '''
        int f() {
          List<int> data = [1, 2, 2, 3, 2, 1];
          Map<int,int> counts = {};
          for (var x in data) {
            if (counts.containsKey(x)) {
              counts[x] = counts[x] + 1;
            } else {
              counts[x] = 1;
            }
          }
          return counts[2];
        }
      ''',
        'f',
        [],
        3,
      );
    });
  });

  group('Wasm maps: String keys', () {
    test('get by constant String key', () async {
      await _testWasmReturn(
        '''
        int f() {
          Map<String,int> m = {"a": 1, "b": 2, "c": 3};
          return m["b"];
        }
      ''',
        'f',
        [],
        2,
      );
    });

    test('get by String parameter key', () async {
      await _testWasmReturn(
        '''
        int f(String k) {
          Map<String,int> m = {"x": 10, "y": 20};
          return m[k];
        }
      ''',
        'f',
        ['y'],
        20,
      );
    });

    test('String key -> String value', () async {
      await _testWasmReturn(
        '''
        String f() {
          Map<String,String> m = {"hi": "world", "yo": "there"};
          return m["hi"];
        }
      ''',
        'f',
        [],
        'world',
      );
    });

    test('containsKey present / absent', () async {
      await _testWasmReturn(
        '''
        bool f() {
          Map<String,int> m = {"alpha": 1, "beta": 2};
          return m.containsKey("beta");
        }
      ''',
        'f',
        [],
        true,
      );

      await _testWasmReturn(
        '''
        bool f() {
          Map<String,int> m = {"alpha": 1};
          return m.containsKey("gamma");
        }
      ''',
        'f',
        [],
        false,
      );
    });

    test('containsKey rejects a prefix (length-checked)', () async {
      await _testWasmReturn(
        '''
        bool f() {
          Map<String,int> m = {"apple": 1};
          return m.containsKey("app");
        }
      ''',
        'f',
        [],
        false,
      );
    });

    test('set update + append (grows)', () async {
      await _testWasmReturn(
        '''
        int f() {
          Map<String,int> m = {"a": 1};
          m["a"] = 99;
          m["bb"] = 2;
          m["ccc"] = 3;
          m["d"] = 4;
          return m["a"] + m["d"];
        }
      ''',
        'f',
        [],
        103,
      );
    });

    test('set from empty literal', () async {
      await _testWasmReturn(
        '''
        int f() {
          Map<String,int> m = {};
          m["one"] = 1;
          m["two"] = 2;
          return m["two"];
        }
      ''',
        'f',
        [],
        2,
      );
    });

    test('multi-byte UTF-8 keys', () async {
      await _testWasmReturn(
        '''
        int f() {
          Map<String,int> m = {"☃": 1, "héllo": 2, "x": 3};
          return m["héllo"];
        }
      ''',
        'f',
        [],
        2,
      );
    });

    test('word frequency counter', () async {
      await _testWasmReturn(
        '''
        int f() {
          List<String> words = ["a", "b", "a", "c", "a", "b"];
          Map<String,int> freq = {};
          for (var w in words) {
            if (freq.containsKey(w)) {
              freq[w] = freq[w] + 1;
            } else {
              freq[w] = 1;
            }
          }
          return freq["a"];
        }
      ''',
        'f',
        [],
        3,
      );
    });
  });

  group('Wasm maps: .keys / .values iteration', () {
    test('sum keys (int keys)', () async {
      await _testWasmReturn(
        '''
        int f() {
          Map<int,int> m = {1: 10, 2: 20, 3: 30};
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

    test('sum values (int keys)', () async {
      await _testWasmReturn(
        '''
        int f() {
          Map<int,int> m = {1: 10, 2: 20, 3: 30};
          int s = 0;
          for (var v in m.values) {
            s = s + v;
          }
          return s;
        }
      ''',
        'f',
        [],
        60,
      );
    });

    test('values reflect prior sets (incl. grow)', () async {
      await _testWasmReturn(
        '''
        int f() {
          Map<int,int> m = {1: 10};
          m[2] = 20;
          m[3] = 30;
          m[4] = 40;
          int s = 0;
          for (var v in m.values) {
            s = s + v;
          }
          return s;
        }
      ''',
        'f',
        [],
        100,
      );
    });

    test('count keys (String keys)', () async {
      await _testWasmReturn(
        '''
        int f() {
          Map<String,int> m = {"a": 1, "bb": 2, "ccc": 3};
          int c = 0;
          for (var k in m.keys) {
            c = c + 1;
          }
          return c;
        }
      ''',
        'f',
        [],
        3,
      );
    });

    test('sum values (String keys)', () async {
      await _testWasmReturn(
        '''
        int f() {
          Map<String,int> m = {"x": 5, "y": 7, "z": 9};
          int s = 0;
          for (var v in m.values) {
            s = s + v;
          }
          return s;
        }
      ''',
        'f',
        [],
        21,
      );
    });
  });

  group('Wasm maps: parameters', () {
    test('int-keyed map parameter, index read', () async {
      await _testWasmReturn(
        '''
        int f(Map<int,int> m) {
          return m[2];
        }
      ''',
        'f',
        [
          {1: 10, 2: 20, 3: 30},
        ],
        20,
      );
    });

    test('String-keyed map parameter, index read', () async {
      await _testWasmReturn(
        '''
        int f(Map<String,int> m) {
          return m["b"];
        }
      ''',
        'f',
        [
          {'a': 1, 'b': 2},
        ],
        2,
      );
    });

    test('map parameter, sum values via for-each', () async {
      await _testWasmReturn(
        '''
        int f(Map<int,int> m) {
          int s = 0;
          for (var v in m.values) {
            s = s + v;
          }
          return s;
        }
      ''',
        'f',
        [
          {1: 5, 2: 7, 3: 9},
        ],
        21,
      );
    });
  });

  group('Wasm maps: returns', () {
    test('return int->int map literal', () async {
      await _testWasmReturn(
        '''
        Map<int,int> f() {
          return {1: 10, 2: 20, 3: 30};
        }
      ''',
        'f',
        [],
        {1: 10, 2: 20, 3: 30},
      );
    });

    test('return String->int map literal', () async {
      await _testWasmReturn(
        '''
        Map<String,int> f() {
          return {"a": 1, "b": 2};
        }
      ''',
        'f',
        [],
        {'a': 1, 'b': 2},
      );
    });

    test('return int->double map', () async {
      await _testWasmReturn(
        '''
        Map<int,double> f() {
          return {1: 1.5, 2: 2.5};
        }
      ''',
        'f',
        [],
        {1: 1.5, 2: 2.5},
      );
    });

    test('return String->String map', () async {
      await _testWasmReturn(
        '''
        Map<String,String> f() {
          return {"hi": "world", "yo": "there"};
        }
      ''',
        'f',
        [],
        {'hi': 'world', 'yo': 'there'},
      );
    });

    test('build with sets then return', () async {
      await _testWasmReturn(
        '''
        Map<int,int> f() {
          Map<int,int> m = {};
          m[1] = 11;
          m[2] = 22;
          m[3] = 33;
          return m;
        }
      ''',
        'f',
        [],
        {1: 11, 2: 22, 3: 33},
      );
    });

    test('round-trip a map (param in, map out)', () async {
      await _testWasmReturn(
        '''
        Map<int,int> f(Map<int,int> m) {
          return m;
        }
      ''',
        'f',
        [
          {7: 70, 8: 80},
        ],
        {7: 70, 8: 80},
      );
    });
  });
}
