import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as pack_path;
import 'package:wasm_run/wasm_run.dart' as wasm_run;

import '../../ast/apollovm_ast_toplevel.dart';
import '../../ast/apollovm_ast_type.dart';
import 'wasm_runtime.dart';

/// [WasmRuntime] implementation for Dart VM.
class WasmRuntimeIO extends WasmRuntime {
  static bool _boot = false;

  static bool _wasmRunDynLibLoaded = false;

  static void boot() {
    if (_boot) return;
    _boot = true;

    var libPath = _wasmRunLibraryFilePath();

    if (libPath == null) {
      throw StateError("Unable to locate the `wasm_run` dynamic library. "
          "You can specify the library path using the environment variable `WASM_RUN_LIB_PATH`.");
    }

    print('** Loading `wasm_run` dynamic library: $libPath');

    var dynLib = DynamicLibrary.open(libPath);

    var ok = dynLib.providesSymbol('wire_compile_wasm');
    if (!ok) {
      throw StateError("Invalid `wasm_run` dynamic library: $libPath");
    }

    _wasmRunDynLibLoaded = true;
  }

  WasmRuntimeIO() : super.base();

  @override
  String get platformVersion => 'Dart: ${Platform.version}';

  @override
  bool get isSupported {
    try {
      boot();
    } catch (e, s) {
      print(e);
      print(s);
    }
    return _wasmRunDynLibLoaded;
  }

  @override
  Future<WasmModuleIO> loadModuleImpl(
      String moduleName, Uint8List wasmModuleBinary) async {
    var module = await _compileModule(wasmModuleBinary);
    var moduleInstance = await module.builder().build();
    return WasmModuleIO(moduleName, module, moduleInstance);
  }

  final Map<String, wasm_run.WasmModule> _compiledModules = {};

  Future<wasm_run.WasmModule> _compileModule(Uint8List wasmModuleBinary) async {
    var binarySignature = _computeBinarySignatureHex(wasmModuleBinary);

    var module = _compiledModules[binarySignature] ??=
        await _compileModuleImpl(wasmModuleBinary);

    return module;
  }

  Future<wasm_run.WasmModule> _compileModuleImpl(Uint8List wasmModuleBinary) {
    boot();
    return wasm_run.compileWasmModule(wasmModuleBinary);
  }

  String _computeBinarySignatureHex(Uint8List wasmModuleBinary) =>
      sha256.convert(wasmModuleBinary).toString();
}

/// [WasmModule] implementation for Dart VM.
class WasmModuleIO extends WasmModule {
  final wasm_run.WasmModule _module;
  wasm_run.WasmInstance instance;

  WasmModuleIO(super.name, this._module, this.instance);

  @override
  Future<WasmModuleIO> copy({String? name}) async {
    name ??= this.name;

    var instance2 = await _module.builder().build();
    return WasmModuleIO(name, _module, instance2);
  }

  @override
  F? getFunction<F extends Function>(String functionName) {
    var f = instance.getFunction(functionName);
    if (f == null) return null;

    return f.inner as F?;
  }

  @override
  void dispose() {
    instance.dispose();
  }

  @override
  Object? resolveReturnedValue(Object? value, ASTFunctionDeclaration? f) {
    if (f?.returnType is ASTTypeVoid) {
      return null;
    }

    return value;
  }
}

WasmRuntime createWasmRuntime() {
  return WasmRuntimeIO();
}

String? _wasmRunLibraryFileName() {
  if (Platform.isMacOS) {
    return 'libwasm_run_dart.dylib';
  } else if (Platform.isWindows) {
    return 'wasm_run_dart.dll';
  } else if (Platform.isLinux) {
    return 'libwasm_run_dart.so';
  }
  return null;
}

String? _wasmRunLibraryFilePath() {
  var libName =
      _wasmRunLibraryFileName() ?? Platform.environment['WASM_RUN_LIB_PATH'];
  if (libName == null || libName.isEmpty) return null;

  var possibleDirs = [
    libName,
    '.',
    '../',
    '../../',
    'lib',
    '../lib',
    '../../lib'
  ];

  for (var dirPath in possibleDirs) {
    var file = File(pack_path.join(dirPath, libName));
    if (file.existsSync()) {
      return pack_path.normalize(file.absolute.path);
    }
  }

  return null;
}
