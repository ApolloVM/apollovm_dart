import 'dart:html';
import 'dart:typed_data';

import 'package:wasm_interop/wasm_interop.dart' as browser_wasm;

import 'wasm_runtime.dart';

/// [WasmRuntime] implementation for the Browser.
class WasmRuntimeBrowser extends WasmRuntime {
  WasmRuntimeBrowser() : super.base();

  @override
  String get platformVersion => 'Browser: ${window.navigator.userAgent}';

  @override
  bool get isSupported => true;

  @override
  Future<WasmModuleBrowser> loadModuleImpl(
      String moduleName, Uint8List wasmModuleBinary) async {
    try {
      final moduleInstance =
          await browser_wasm.Instance.fromBytesAsync(wasmModuleBinary);
      return WasmModuleBrowser(moduleName, moduleInstance);
    } catch (e) {
      throw WasmModuleLoadError("Can't load wasm module: $moduleName",
          cause: e);
    }
  }
}

class WasmModuleBrowser extends WasmModule {
  browser_wasm.Instance instance;

  WasmModuleBrowser(super.name, this.instance);

  @override
  Future<WasmModuleBrowser> copy({String? name}) async {
    name ??= this.name;

    var instance2 =
        await browser_wasm.Instance.fromModuleAsync(instance.module);
    return WasmModuleBrowser(name, instance2);
  }

  @override
  F? getFunction<F extends Function>(String functionName) {
    return instance.functions[functionName]! as F?;
  }

  @override
  Object? resolveReturnedValue(Object? value) {
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
  return WasmRuntimeBrowser();
}
