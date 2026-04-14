// ignore: deprecated_member_use
import 'dart:html';
import 'dart:typed_data';

import 'package:wasm_interop/wasm_interop.dart' as browser_wasm;

import '../../ast/apollovm_ast_toplevel.dart';
import 'wasm_runtime.dart';

/// [WasmRuntime] implementation for the Browser using `dart:html`.
/// Use `WasmRuntimeWeb` instead.
@Deprecated("Use `WasmRuntimeWeb` instead.")
class WasmRuntimeDartHTML extends WasmRuntime {
  WasmRuntimeDartHTML() : super.base();

  @override
  String get platformVersion =>
      'Browser(dart:html): ${window.navigator.userAgent}';

  @override
  bool get isSupported => true;

  @override
  Future<WasmModuleBrowser> loadModuleImpl(
    String moduleName,
    Uint8List wasmModuleBinary,
  ) async {
    try {
      final moduleInstance = await browser_wasm.Instance.fromBytesAsync(
        wasmModuleBinary,
      );
      return WasmModuleBrowser(moduleName, moduleInstance);
    } catch (e) {
      throw WasmModuleLoadError(
        "Can't load wasm module: $moduleName",
        cause: e,
      );
    }
  }
}

class WasmModuleBrowser extends WasmModule {
  browser_wasm.Instance instance;

  WasmModuleBrowser(super.name, this.instance);

  @override
  Future<WasmModuleBrowser> copy({String? name}) async {
    name ??= this.name;

    var instance2 = await browser_wasm.Instance.fromModuleAsync(
      instance.module,
    );
    return WasmModuleBrowser(name, instance2);
  }

  @override
  WasmModuleFunction<F>? getFunction<F extends Function>(String functionName) {
    var function = instance.functions[functionName]! as F?;
    if (function == null) return null;
    return (function: function, varArgs: true);
  }

  @override
  Object? resolveReturnedValue(Object? value, ASTFunctionDeclaration? f) {
    if (value == null) return null;

    if (browser_wasm.JsBigInt.isJsBigInt(value)) {
      var bigInt = browser_wasm.JsBigInt.toBigInt(value);

      if (bigInt.isValidInt) {
        return bigInt.toInt();
      } else {
        return bigInt;
      }
    }

    return value;
  }

  @override
  String toString() {
    return 'WasmModuleBrowser{name: $name, instance: $instance}';
  }
}

WasmRuntime createWasmRuntime() {
  // ignore: deprecated_member_use_from_same_package
  return WasmRuntimeDartHTML();
}
