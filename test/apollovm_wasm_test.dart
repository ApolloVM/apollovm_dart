import 'dart:typed_data';

import 'package:apollovm/apollovm.dart';
import 'package:data_serializer/data_serializer.dart';
import 'package:test/test.dart';

void main() async {
  group('ApolloVM - Wasm Generator', () {
    test(
      'empty',
      () => _testWasm(
          language: 'dart',
          code: r'''
      
          void empty() {
            
          }
          
        ''',
          functionName: 'empty',
          executions: {
            []: null,
          },
          expecteWasm: {
            'test':
                '0061736D010000000104016000000302010007090105656D70747900000A040102000B',
          }),
    );

    test(
      'add1',
      () => _testWasm(
          language: 'dart',
          code: r'''
      
          int add1(int a) {
            int x = a + 10;
            return x;
          }
          
        ''',
          functionName: 'add1',
          executions: {
            [101]: 111,
          },
          expecteWasm: {
            'test':
                '0061736D0100000001060160017E017E03020100070801046164643100000A10010E01017E2000420A7C210120010F0B',
          }),
    );

    test(
      'add3',
      () => _testWasm(
          language: 'dart',
          code: r'''
      
          int add3(int a, int b) {
            int x = a + b + 10;
            return x;
          }
          
        ''',
          functionName: 'add3',
          executions: {
            [101, 50]: 161,
          },
          expecteWasm: {
            'test':
                '0061736D0100000001070160027E7E017E03020100070801046164643300000A13011101017E20002001420A7C7C210220020F0B',
          }),
    );

    test(
      'add4',
      () => _testWasm(
          language: 'dart',
          code: r'''
      
          int add4(int a, int b, int c) {
            int x = a + b + 10;
            int y = c ~/ 2;
            int z = x - y;
            return z;
          }
          
        ''',
          functionName: 'add4',
          executions: {
            [101, 50, 30]: 146,
          },
          expecteWasm: {
            'test':
                '0061736D0100000001080160037E7E7E017E03020100070801046164643400000A28012603017E017E017E20002001420A7C7C21032002B94202B9A3B02104200320047D210520050F0B',
          }),
    );

    test(
      'add5',
      () => _testWasm(
          language: 'dart',
          code: r'''
      
          int add5(int a, int b, int c) {
            int x = a + b + 10;
            int y = c ~/ 2;
            int z = x - y;
            return z * z;
          }
          
        ''',
          functionName: 'add5',
          executions: {
            [101, 50, 30]: 21316,
            [10, 50, 300]: 6400,
          },
          expecteWasm: {
            'test':
                '0061736D0100000001080160037E7E7E017E03020100070801046164643500000A2B012903017E017E017E20002001420A7C7C21032002B94202B9A3B02104200320047D2105200520057E0F0B',
          }),
    );

    test(
      'add6',
      () => _testWasm(
          language: 'dart',
          code: r'''
      
          int add6(int a) {
            if (a > 100) {
              return 1 ;
            } 
            return 0 ;
          }
          
        ''',
          functionName: 'add6',
          executions: {
            [101]: 1,
            [10]: 0,
          },
          expecteWasm: {
            'test':
                '0061736D0100000001060160017E017E03020100070801046164643600000A16011400200042E40055044042010F0B42000F0042000B',
          }),
    );

    test(
      'add7',
      () => _testWasm(
          language: 'dart',
          code: r'''
      
          int add7(int a) {
            if (a > 100) {
              a = a + 100;
            }
            else {
              a = a + 10;
            }
            
            return a ;
          }
          
        ''',
          functionName: 'add7',
          executions: {
            [111]: 211,
            [11]: 21,
          },
          expecteWasm: {
            'test':
                '0061736D0100000001060160017E017E03020100070801046164643700000A20011E00200042E400550440200042E4007C2100052000420A7C21000B20000F0B',
          }),
    );

    test(
      'add8',
      () => _testWasm(
          language: 'dart',
          code: r'''
      
          int add8(int a) {
            if (a > 100) {
              return 1 ;
            } 
            else if ( a == 0 ) {
              return 0 ;
            }
            else {
              return -1 ;
            }
          }
          
        ''',
          functionName: 'add8',
          executions: {
            [101]: 1,
            [0]: 0,
            [10]: -1,
          },
          expecteWasm: {
            'test':
                '0061736D0100000001060160017E017E03020100070801046164643800000A21011F00200042E40055044042010F05200050044042000F05427F0F0B0B0042000B',
          }),
    );

    test(
      'add9',
      () => _testWasm(
          language: 'dart',
          code: r'''
      
          int add9(int a) {
            if (a > 100) {
              return 100 ;
            } 
            else if ( a == 0 ) {
              return 0 ;
            }
            else if ( a == 1 ) {
              return 1 ;
            }
            else {
              return -1 ;
            }
          }
          
        ''',
          functionName: 'add9',
          executions: {
            [101]: 100,
            [0]: 0,
            [1]: 1,
            [10]: -1,
          },
          expecteWasm: {
            'test':
                '0061736D0100000001060160017E017E03020100070801046164643900000A2E012C00200042E40055044042E4000F05200050044042000F052000420151044042010F05427F0F0B0B0B0042000B',
          }),
    );

    test(
      'add10',
      () => _testWasm(
          language: 'dart',
          code: r'''
      
          int add10(int a) {
            if (a > 100) {
              return 1 ;
            } 
            else if ( a == 0 ) {
              return 0 ;
            }
            
            return -11 ;
          }
          
        ''',
          functionName: 'add10',
          executions: {
            [101]: 1,
            [0]: 0,
            [10]: -11,
          },
          expecteWasm: {
            'test':
                '0061736D0100000001060160017E017E0302010007090105616464313000000A20011E00200042E40055044042010F05200050044042000F0B0B42750F0042000B',
          }),
    );

    test(
      'add11',
      () => _testWasm(
          language: 'dart',
          code: r'''
      
          int add11(int a) {
            var x = a + 10;
            return x;
          }
          
        ''',
          functionName: 'add11',
          executions: {
            [101]: 111,
          },
          expecteWasm: {
            'test':
                '0061736D0100000001060160017E017E0302010007090105616464313100000A10010E01017E2000420A7C210120010F0B',
          }),
    );

    test(
      'add12',
      () => _testWasm(
          language: 'dart',
          code: r'''
      
          double add12( int a, int b ) {
            double c = b / 2;
            var sumAC = a + c ;
            return sumAC;
          }
          
        ''',
          functionName: 'add12',
          executions: {
            [100, 31]: 115.5,
          },
          expecteWasm: {
            'test':
                '0061736D0100000001070160027E7E017C0302010007090105616464313200000A1C011A02017C017C2001B94202B9A321022000B92002A0210320030F0B',
          }),
    );

    test(
      'add13',
      () => _testWasm(
          language: 'dart',
          code: r'''
      
          double add13(int a) {
            var x = a + 10 ;
            return x ;
          }
          
        ''',
          functionName: 'add13',
          executions: {
            [100]: 110,
          },
          expecteWasm: {
            'test':
                '0061736D0100000001060160017E017C0302010007090105616464313300000A11010F01017E2000420A7C21012001B90F0B',
          }),
    );

    test(
      'operation1',
      () => _testWasm(
          language: 'dart',
          code: r'''
      
          double operation1( int v, double r, int balance ) {
            var total = v * r ;
          
            if ( total > balance ) {
              return 0;
            }
            
            return total ;
          }
          
        ''',
          functionName: 'operation1',
          executions: {
            [50, 0.33, 1000]: 16.5,
            [50, 30.0, 1000]: 0.0,
            [50, 30.0, 2000]: 1500.0,
            [50, 30, 2000]: 1500.0,
          },
          expecteWasm: {
            'test':
                '0061736D0100000001080160037E7C7E017C03020100070E010A6F7065726174696F6E3100000A1E011C01017C2000B92001A2210320032002B96404404200B90F0B20030F0B',
          }),
    );

    test(
      'operation2',
      () => _testWasm(
          language: 'dart',
          code: r'''
      
          int operation2( int v, double r, int balance ) {
            var total = v * r ;
          
            if ( total > balance ) {
              return 0;
            }
            
            return total ;
          }
          
        ''',
          functionName: 'operation2',
          executions: {
            [50, 0.33, 1000]: 16.0,
            [50, 30.0, 1000]: 0.0,
            [50, 30.0, 2000]: 1500.0,
          },
          expecteWasm: {
            'test':
                '0061736D0100000001080160037E7C7E017E03020100070E010A6F7065726174696F6E3200000A1E011C01017C2000B92001A2210320032002B964044042000F0B2003B00F0B',
          }),
    );

    test(
      'f\$10',
      () => _testWasm(
          language: 'dart',
          code: r'''
      
          int f$10( int a, double b , double c ) {
            var x = a * b;
            var y = x / c ;
            return y ;
          }
          
        ''',
          functionName: 'f\$10',
          executions: {
            [10, 5, 2]: 25,
            [10, 5, 3]: 16,
          },
          expecteWasm: {
            'test':
                '0061736D0100000001080160037E7C7C017E03020100070801046624313000000A1B011902017C017C2000B92001A2210320032002A321042004B00F0B',
          }),
    );

    test(
      'f\$11',
      () => _testWasm(
          language: 'dart',
          code: r'''
      
          double f$11( int a, double b , double c ) {
            var x = a * b;
            var y = x / c ;
            return y ;
          }
          
        ''',
          functionName: 'f\$11',
          executions: {
            [10, 5, 2]: 25,
            [11, 3, 2]: 16.5,
          },
          expecteWasm: {
            'test':
                '0061736D0100000001080160037E7C7C017C03020100070801046624313100000A1A011802017C017C2000B92001A2210320032002A3210420040F0B',
          }),
    );

    test(
      'f\$12',
      () => _testWasm(
          language: 'dart',
          code: r'''
      
          double f$12( int a, double b , double c ) {
            var x = a * b;
            var y = x ~/ c ;
            return y ;
          }
          
        ''',
          functionName: 'f\$12',
          executions: {
            [10, 5, 2]: 25,
            [11, 3, 2]: 16
          },
          expecteWasm: {
            'test':
                '0061736D0100000001080160037E7C7C017C03020100070801046624313200000A1C011A02017C017E2000B92001A2210320032002A3B021042004B90F0B',
          }),
    );
  });
}

Future<void> _testWasm(
    {required String language,
    required String code,
    required String functionName,
    required Map<List, Object?> executions,
    Map<String, dynamic>? expecteWasm}) async {
  print('==================================================================');
  print("$language>> $functionName");

  for (var e in executions.entries) {
    var parameters = e.key;
    var expectedResult = e.value;
    print('  -- $parameters -> $expectedResult');
  }

  var vm = ApolloVM();

  var codeUnit = SourceCodeUnit(language, code, id: 'test');

  print(">> Loading code...");

  var loadOK = await vm.loadCodeUnit(codeUnit);

  if (!loadOK) {
    print("Can't load source code in `$language`!");
    return;
  }

  print('------------------------------------------------------------------');

  print(">> Regenerating `$language` code ...\n");

  var regeneratedCode = await vm.generateAllCodeIn(language).writeAllSources();

  print(regeneratedCode);

  print('------------------------------------------------------------------');

  print(">> Compiling `$language` code to Wasm...");

  var storageWasm = vm.generateAllIn<BytesOutput>('wasm');
  var wasmModules = await storageWasm.allEntries();

  expecteWasm ??= {};

  BytesOutput? compiledWasm;
  Uint8List? expectedWasmBytes;

  for (var namespace in wasmModules.entries) {
    for (var module in namespace.value.entries) {
      var moduleName = module.key;
      var wasm = module.value;
      var wasmBytes = wasm.output();

      var expectedBytes = expecteWasm[moduleName];
      if (expectedBytes is String) {
        expectedBytes = hex.decode(expectedBytes);
      }

      print('<<WASM: ${namespace.key}/$moduleName>>');
      print(wasm);

      print('<<WASM: HEX>>');
      print(hex.encode(wasmBytes));

      print('<<WASM: Bytes>>');
      print(wasmBytes);

      // _saveWasmFile(language, functionName, wasmBytes);

      expectedWasmBytes = expectedBytes;

      compiledWasm ??= wasm;
    }
  }

  expect(compiledWasm, isNotNull);

  print('------------------------------------------------------------------');

  {
    print(">> Running code...");

    var dartRunner = vm.createRunner('dart')!;

    // Map the `print` function in the VM:
    dartRunner.externalPrintFunction = (o) => print("» $o");

    for (var e in executions.entries) {
      var parameters = e.key;
      var expectedResult = e.value;

      print('<<<<<<<<<<<<<<<<<<<<<<<<<<<<');
      print('EXECUTE AST> $parameters -> $expectedResult');

      var astValue = await dartRunner.executeFunction('', functionName,
          positionalParameters: parameters);

      var result = astValue.getValueNoContext();
      print('Result: $result');

      expect(result, expectedResult);
      print('>>>>>>>>>>>>>>>>>>>>>>>>>>>>');
    }
  }

  print('------------------------------------------------------------------');

  final wasmRuntime = WasmRuntime();

  if (wasmRuntime.isSupported) {
    print(">> Running compiled Wasm...");

    var vmWasm = ApolloVM();

    var wasmCodeUnit = BinaryCodeUnit('wasm', compiledWasm!.output(),
        id: 'test.wasm', namespace: '');

    var loadOK = await vmWasm.loadCodeUnit(wasmCodeUnit);
    expect(loadOK, isTrue);

    var wasmRunner = vmWasm.createRunner('wasm')!;

    // Map the `print` function in the VM:
    wasmRunner.externalPrintFunction = (o) => print("wasm» $o");

    for (var e in executions.entries) {
      var parameters = e.key;
      var expectedResult = e.value;

      print('<<<<<<<<<<<<<<<<<<<<<<<<<<<<');
      print('EXECUTE WASM> $parameters -> $expectedResult');

      var wasmAstValue = await wasmRunner.executeFunction('', functionName,
          positionalParameters: parameters);

      var wasmResult = wasmAstValue.getValueNoContext();
      print('Wasm Result: $wasmResult');

      expect(wasmResult, expectedResult);
      print('>>>>>>>>>>>>>>>>>>>>>>>>>>>>');
    }
  } else {
    print('** `WasmRuntime` not supported: ${wasmRuntime.platformVersion}');
  }

  expect(expectedWasmBytes, isNotNull, reason: "Null `expectedWasmBytes`");

  print('<< EXPECTED WASM: HEX>>\n${hex.encode(expectedWasmBytes!)}');

  expect(compiledWasm?.output(), expectedWasmBytes);
}

/*
void _saveWasmFile(String language, String functionName, List<int> wasmBytes) {
  try {
    var fileName = 'apollovm-$language-$functionName-test.wasm';

    var file = File('/tmp/test-wasm/$fileName');
    file.writeAsBytesSync(wasmBytes);

    print('>> SAVED: $file');
  } catch (_) {}
}
 */
