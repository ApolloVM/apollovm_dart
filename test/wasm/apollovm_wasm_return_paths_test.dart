@TestOn('vm')
@Tags(['wasm', 'dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

import 'wasm_runtime_setup.dart';

/// Compiles [code] to Wasm and runs top-level [fn] on BOTH the AST interpreter
/// and the compiled+executed Wasm module, asserting every `args -> expected`
/// pair in [executions] matches on both backends.
///
/// These cases exercise functions whose body ENDS with a control construct
/// (`switch` / `if` / `while`) that returns on every path — frequently preceded
/// by a `var` declaration. Such a body ends with a block's `end` (reachable to
/// the Wasm validator), so the compiler must emit a trailing `unreachable` +
/// default; a residual virtual-stack entry from the preceding declaration must
/// not suppress it.
Future<void> _testWasm(
  String code,
  String fn,
  Map<List, Object?> executions,
) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', code, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source");

  // 1) AST interpreter (reference).
  var astRunner = vm.createRunner('dart')!;
  for (var e in executions.entries) {
    var r = await astRunner.executeFunction(
      '',
      fn,
      positionalParameters: e.key,
    );
    expect(r.getValueNoContext(), e.value, reason: 'AST $fn(${e.key})');
  }

  // 2) Compile to Wasm.
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
    fail('Wasm runtime not supported (`wasm_run` native library unavailable).');
  }

  // 3) Load + execute the compiled Wasm.
  var vmWasm = ApolloVM();
  var loadOK = await vmWasm.loadCodeUnit(
    BinaryCodeUnit('wasm', compiled!.output(), id: 'test.wasm', namespace: ''),
  );
  expect(loadOK, isTrue, reason: 'Compiled Wasm failed to load');

  var wasmRunner = vmWasm.createRunner('wasm')!;
  for (var e in executions.entries) {
    var r = await wasmRunner.executeFunction(
      '',
      fn,
      positionalParameters: e.key,
    );
    expect(r.getValueNoContext(), e.value, reason: 'WASM $fn(${e.key})');
  }
}

void main() {
  setUpWasmRuntime();

  group('Wasm: control flow as the terminating statement', () {
    test('switch as last statement (scrutinee is the parameter)', () {
      return _testWasm(
        r'''
        int run(int x) {
          switch (x) {
            case 1: return 10;
            case 2: return 20;
            default: return 99;
          }
        }
        ''',
        'run',
        {
          [1]: 10,
          [2]: 20,
          [7]: 99,
        },
      );
    });

    test('switch as last statement preceded by a var declaration', () {
      return _testWasm(
        r'''
        int run(int y) {
          var x = y + 1;
          switch (x) {
            case 6: return 60;
            default: return 0;
          }
        }
        ''',
        'run',
        {
          [5]: 60,
          [1]: 0,
        },
      );
    });

    test('switch as last statement after several var declarations', () {
      return _testWasm(
        r'''
        int run(int y) {
          var a = y;
          var b = a * 2;
          var c = b + 1;
          switch (c) {
            case 11: return 111;
            case 21: return 211;
            default: return -1;
          }
        }
        ''',
        'run',
        {
          [5]: 111,
          [10]: 211,
          [0]: -1,
        },
      );
    });

    test('if/else (both branches return) as last statement after var decl', () {
      return _testWasm(
        r'''
        int run(int y) {
          var x = y;
          if (x > 0) { return 1; } else { return 2; }
        }
        ''',
        'run',
        {
          [5]: 1,
          [-3]: 2,
        },
      );
    });

    test('while(true){ return } as last statement after var decl', () {
      return _testWasm(
        r'''
        int run(int y) {
          var x = y;
          while (true) { return x + 1; }
        }
        ''',
        'run',
        {
          [5]: 6,
        },
      );
    });

    test('double return via if/else after a var declaration', () {
      return _testWasm(
        r'''
        double run(double y) {
          var x = y;
          if (x > 0.0) { return x * 2.0; } else { return 0.0; }
        }
        ''',
        'run',
        {
          [2.5]: 5.0,
          [-1.0]: 0.0,
        },
      );
    });

    test('String return via switch after a var declaration', () {
      return _testWasm(
        r'''
        String run(int code) {
          var c = code;
          switch (c) {
            case 1: return 'one';
            case 2: return 'two';
            default: return 'many';
          }
        }
        ''',
        'run',
        {
          [1]: 'one',
          [2]: 'two',
          [9]: 'many',
        },
      );
    });

    test('nested if inside switch, all paths return, after var decl', () {
      return _testWasm(
        r'''
        int run(int y) {
          var x = y;
          switch (x) {
            case 1:
              if (x > 0) { return 100; } else { return 101; }
            default:
              return 9;
          }
        }
        ''',
        'run',
        {
          [1]: 100,
          [5]: 9,
        },
      );
    });
  });
}
