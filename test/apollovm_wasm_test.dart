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
      
          int add(int a, int b) {
            int x = a + b + 10;
            return x;
          }
          
        ''',
          functionName: 'add',
          parameters: [101, 50],
          expectedResult: 161,
          expecteWasm: {
            'test':
                '0061736D0100000001070160027F7F017F030201000707010361646400000A12011001017F20002001410A6A6A210220020B',
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

  var codeUnit = CodeUnit(language, code, 'test');

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
    }
  }
}
