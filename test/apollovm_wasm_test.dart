import 'package:apollovm/apollovm.dart';
import 'package:data_serializer/data_serializer.dart';
import 'package:test/test.dart';

void main() async {
  group('ApolloVM - Wasm Generator', () {
    test(
      'basic 1',
      () => _testWasm(
          language: 'dart',
          code: r'''
      
          void empty() {
            
          }
          
        ''',
          functionName: 'empty',
          parameters: [],
          expecteWasm: {
            'test':
                '0061736D010000000104016000000302010007090105656D70747900000A040102000B',
          }),
    );

    test(
      'basic 2',
      () => _testWasm(
          language: 'dart',
          code: r'''
      
          int add1(int a) {
            int x = a + 10;
            return x;
          }
          
        ''',
          functionName: 'add1',
          parameters: [101],
          expectedResult: 111,
          expecteWasm: {
            'test':
                '0061736D0100000001060160017F017F03020100070801046164643100000A0F010D01017F2000410A6A210120010B',
          }),
    );

    test(
      'basic 3',
      () => _testWasm(
          language: 'dart',
          code: r'''
      
          int add3(int a, int b) {
            int x = a + b + 10;
            return x;
          }
          
        ''',
          functionName: 'add3',
          parameters: [101, 50],
          expectedResult: 161,
          expecteWasm: {
            'test':
                '0061736D0100000001070160027F7F017F03020100070801046164643300000A12011001017F20002001410A6A6A210220020B',
          }),
    );

    test(
      'basic 4',
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
          parameters: [101, 50, 30],
          expectedResult: 146,
          expecteWasm: {
            'test':
                '0061736D0100000001080160037F7F7F017F03020100070801046164643400000A27012503017F017F017F20002001410A6A6A21032002B74102B7A3AA2104200320046B210520050B',
          }),
    );

    test(
      'basic 5',
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
          parameters: [101, 50, 30],
          expectedResult: 21316,
          expecteWasm: {
            'test':
                '0061736D0100000001080160037F7F7F017F03020100070801046164643500000A2A012803017F017F017F20002001410A6A6A21032002B74102B7A3AA2104200320046B2105200520056C0B',
          }),
    );
  });
}

Future<void> _testWasm(
    {required String language,
    required String code,
    required String functionName,
    required List parameters,
    Object? expectedResult,
    Map<String, dynamic>? expecteWasm}) async {
  print('==================================================================');
  print("$language>> $functionName$parameters");

  var vm = ApolloVM();

  var codeUnit = SourceCodeUnit(language, code, id: 'test');

  print(">> Loading code...");

  var loadOK = await vm.loadCodeUnit(codeUnit);

  if (!loadOK) {
    print("Can't load source code in `$language`!");
    return;
  }

  print(">> Running code...");

  var dartRunner = vm.createRunner('dart')!;

  // Map the `print` function in the VM:
  dartRunner.externalPrintFunction = (o) => print("» $o");

  var astValue = await dartRunner.executeFunction('', functionName,
      positionalParameters: parameters);

  var result = astValue.getValueNoContext();
  print('Result: $result');

  expect(result, expectedResult);

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

      expect(wasmBytes, expectedBytes);

      compiledWasm ??= wasm;

      //_saveWasmFile(language, functionName, wasmBytes);
    }
  }

  expect(compiledWasm, isNotNull);

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

    var wasmAstValue = await wasmRunner.executeFunction('', functionName,
        positionalParameters: parameters);

    var wasmResult = wasmAstValue.getValueNoContext();
    print('Wasm Result: $wasmResult');

    expect(wasmResult, expectedResult);
  } else {
    print('** `WasmRuntime` not supported: ${wasmRuntime.platformVersion}');
  }
}

/*
void _saveWasmFile(String language, String functionName, Uint8List wasmBytes) {
  try {
    var fileName = 'apollovm-$language-$functionName-test.wasm';

    var file = File('/tmp/test-wasm/$fileName');
    file.writeAsBytesSync(wasmBytes);

    print('>> SAVED: $file');
  } catch (_) {}
}
*/
