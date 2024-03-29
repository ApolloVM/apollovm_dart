import 'dart:typed_data';

import '../../ast/apollovm_ast_toplevel.dart';
import 'wasm_runtime.dart';

class WasmRuntimeGeneric extends WasmRuntime {
  WasmRuntimeGeneric() : super.base();

  @override
  String get platformVersion => '?';

  @override
  bool get isSupported => false;

  @override
  Future<WasmModuleGeneric> loadModuleImpl(
      String moduleName, Uint8List wasmModuleBinary) async {
    return WasmModuleGeneric(moduleName);
  }
}

class WasmModuleGeneric extends WasmModule {
  WasmModuleGeneric(super.name);

  @override
  Future<WasmModuleGeneric> copy({String? name}) async {
    name ??= this.name;
    return WasmModuleGeneric(name);
  }

  @override
  F? getFunction<F extends Function>(String functionName) => null;

  @override
  Object? resolveReturnedValue(Object? value, ASTFunctionDeclaration? f) =>
      value;
}

WasmRuntime createWasmRuntime() {
  return WasmRuntimeGeneric();
}
