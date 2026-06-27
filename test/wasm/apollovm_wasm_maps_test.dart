@Tags(['wasm', 'dart'])
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

/// Runs [functionName] (with [args]) via the AST interpreter AND the compiled
/// Wasm module, capturing `print` output from each, and asserts both equal
/// [expectedPrints].
Future<void> _testWasmPrints(
  String code,
  String functionName,
  List args,
  List<String> expectedPrints,
) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', code, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source");

  var astRunner = vm.createRunner('dart')!;
  var astOut = <String>[];
  astRunner.externalPrintFunction = (o) => astOut.add('$o');
  await astRunner.executeFunction('', functionName, positionalParameters: args);
  expect(astOut, equals(expectedPrints), reason: 'interpreter print output');

  var storageWasm = vm.generateAllIn<BytesOutput>('wasm');
  var wasmModules = await storageWasm.allEntries();
  BytesOutput? compiled;
  for (var ns in wasmModules.entries) {
    for (var m in ns.value.entries) {
      compiled ??= m.value;
    }
  }
  expect(compiled, isNotNull, reason: 'No compiled Wasm module');

  var vmWasm = ApolloVM();
  await vmWasm.loadCodeUnit(
    BinaryCodeUnit('wasm', compiled!.output(), id: 'test.wasm', namespace: ''),
  );
  var wasmRunner = vmWasm.createRunner('wasm')!;
  var wasmOut = <String>[];
  wasmRunner.externalPrintFunction = (o) => wasmOut.add('$o');
  await wasmRunner.executeFunction(
    '',
    functionName,
    positionalParameters: args,
  );
  expect(wasmOut, equals(expectedPrints), reason: 'Wasm print output');
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

  group('Wasm maps/lists: compound subscript assignment', () {
    test('map m[k] += v', () async {
      await _testWasmReturn(
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

    test('map m[k] -= / *=', () async {
      await _testWasmReturn(
        '''
        int f() {
          Map<int,int> m = {1: 10};
          m[1] -= 3;
          m[1] *= 4;
          return m[1];
        }
      ''',
        'f',
        [],
        28,
      );
    });

    test('String-keyed map m[k] += v', () async {
      await _testWasmReturn(
        '''
        int f() {
          Map<String,int> m = {"a": 1};
          m["a"] += 9;
          return m["a"];
        }
      ''',
        'f',
        [],
        10,
      );
    });

    test('double-valued map m[k] += v', () async {
      await _testWasmReturn(
        '''
        double f() {
          Map<int,double> m = {1: 1.5};
          m[1] += 2.0;
          return m[1];
        }
      ''',
        'f',
        [],
        3.5,
      );
    });

    test('list a[i] += v', () async {
      await _testWasmReturn(
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

    test('list a[i] *= with variable rhs', () async {
      await _testWasmReturn(
        '''
        int f(int d) {
          List<int> a = [2, 3];
          a[1] *= d;
          return a[1];
        }
      ''',
        'f',
        [4],
        12,
      );
    });

    test('frequency counter using += ', () async {
      await _testWasmReturn(
        '''
        int f() {
          List<String> words = ["a", "b", "a", "a", "b"];
          Map<String,int> m = {};
          for (var w in words) {
            if (m.containsKey(w)) {
              m[w] += 1;
            } else {
              m[w] = 1;
            }
          }
          return m["a"];
        }
      ''',
        'f',
        [],
        3,
      );
    });
  });

  group('Wasm maps: Map/List -> String coercion (print/interpolation)', () {
    test('Map<String,int> interpolated', () async {
      await _testWasmPrints(
        '''
        void f() {
          Map<String,int> m = {'a': 10, 'b': 25, 'c': 90};
          print('Map: \$m');
        }
        ''',
        'f',
        [],
        ['Map: {a: 10, b: 25, c: 90}'],
      );
    });

    test('Map<int,String> interpolated', () async {
      await _testWasmPrints(
        '''
        void f() {
          Map<int,String> m = {1: 'x', 2: 'y'};
          print('\$m');
        }
        ''',
        'f',
        [],
        ['{1: x, 2: y}'],
      );
    });

    test('empty Map interpolated', () async {
      await _testWasmPrints(
        '''
        void f() {
          Map<String,int> m = {};
          print('\$m');
        }
        ''',
        'f',
        [],
        ['{}'],
      );
    });

    test('List<int> interpolated', () async {
      await _testWasmPrints(
        '''
        void f() {
          List<int> l = [10, 20, 30];
          print('List: \$l');
        }
        ''',
        'f',
        [],
        ['List: [10, 20, 30]'],
      );
    });

    test('List<String> interpolated', () async {
      await _testWasmPrints(
        '''
        void f() {
          List<String> l = ['a', 'b'];
          print('\$l');
        }
        ''',
        'f',
        [],
        ['[a, b]'],
      );
    });
  });

  group('Wasm: arithmetic on boxed Object values (List<Object>)', () {
    // A `List<Object>` element is a boxed value; the interpreter treats it
    // dynamically. The Wasm backend must unbox it before arithmetic instead of
    // feeding the box pointer into i64.add / f64.div.
    test('add a boxed Object and an int', () async {
      await _testWasmPrints(
        '''
        void f(List<Object> args) {
          var a = args[0];
          print(a + 5);
        }
        ''',
        'f',
        [
          [10],
        ],
        ['15'],
      );
    });

    test('integer-divide and multiply boxed Objects', () async {
      await _testWasmPrints(
        '''
        void f(List<Object> args) {
          var b = args[0] ~/ 2;
          var c = args[1] * 3;
          print(b);
          print(c);
        }
        ''',
        'f',
        [
          [50, 30],
        ],
        ['25', '90'],
      );
    });

    test('compare a boxed Object', () async {
      await _testWasmPrints(
        '''
        void f(List<Object> args) {
          var c = args[0] * 3;
          if (c > 120) { c = 120; }
          print(c);
        }
        ''',
        'f',
        [
          [50],
        ],
        ['120'],
      );
    });

    test('boxed Object stored into a typed-int Map value', () async {
      await _testWasmPrints(
        '''
        void f(List<Object> args) {
          var a = args[0];
          var m = <String,int>{'a': a};
          print('\$m');
          print('a=\${m['a']}');
        }
        ''',
        'f',
        [
          [10],
        ],
        ['{a: 10}', 'a=10'],
      );
    });
  });

  group('Wasm: the motivating program (boxed args + Map print)', () {
    test('Foo.main', () async {
      const code = '''
class Foo {
  static void main(List<Object> args) {
    var title = args[0];
    var a = args[1];
    var b = args[2] ~/ 2;
    var c = args[3] * 3;

    if (c > 120) {
      c = 120 ;
    }

    var str = 'variables> a: \$a ; b: \$b ; c: \$c' ;
    var sumAB = a + b ;
    var sumABC = a + b + c;

    print(str);
    print(title);
    print(sumAB);
    print(sumABC);

    var map = <String,int>{
    'a': a,
    'b': b,
    'c': c,
    };

    print('Map: \$map');
    print('Map `b`: \${map['b']}');
  }
}
''';
      final args = ['Title', 10, 50, 30];
      final expected = [
        'variables> a: 10 ; b: 25 ; c: 90',
        'Title',
        '35',
        '125',
        'Map: {a: 10, b: 25, c: 90}',
        'Map `b`: 25',
      ];

      var vm = ApolloVM();
      var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', code, id: 'test'));
      expect(ok, isTrue, reason: "Can't load Dart source");

      var astRunner = vm.createRunner('dart')!;
      var astOut = <String>[];
      astRunner.externalPrintFunction = (o) => astOut.add('$o');
      await astRunner.executeClassMethod(
        '',
        'Foo',
        'main',
        positionalParameters: [args],
      );
      expect(astOut, equals(expected), reason: 'interpreter');

      var storageWasm = vm.generateAllIn<BytesOutput>('wasm');
      var wasmModules = await storageWasm.allEntries();
      BytesOutput? compiled;
      for (var ns in wasmModules.entries) {
        for (var m in ns.value.entries) {
          compiled ??= m.value;
        }
      }
      expect(compiled, isNotNull, reason: 'No compiled Wasm module');

      var vmWasm = ApolloVM();
      await vmWasm.loadCodeUnit(
        BinaryCodeUnit(
          'wasm',
          compiled!.output(),
          id: 'test.wasm',
          namespace: '',
        ),
      );
      var wasmRunner = vmWasm.createRunner('wasm')!;
      var wasmOut = <String>[];
      wasmRunner.externalPrintFunction = (o) => wasmOut.add('$o');
      await wasmRunner.executeFunction(
        '',
        'Foo.main',
        positionalParameters: [args],
      );
      expect(wasmOut, equals(expected), reason: 'Wasm');
    });
  });
}
