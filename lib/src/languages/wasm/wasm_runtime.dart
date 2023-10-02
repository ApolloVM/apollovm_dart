import 'dart:typed_data';

import 'package:async_extension/async_extension.dart';

import 'wasm_runtime_generic.dart'
    if (dart.library.html) 'wasm_runtime_browser.dart'
// if (dart.library.io) 'wasm_runtime_io.dart'
    ;

/// A WebAssembly (Wasm) Runtime.
abstract class WasmRuntime {
  final Map<String, WasmModule> _loadedModules = {};

  WasmRuntime.base();

  factory WasmRuntime() {
    return createWasmRuntime();
  }

  /// Returns the platform version of the Wasm runtime.
  String get platformVersion;

  /// Returns true if the WebAssembly (Wasm) Runtime is supported in the platform.
  bool get isSupported;

  /// Returns a loaded Wasm module.
  WasmModule? getModule(String moduleName) {
    return _loadedModules[moduleName];
  }

  /// Loads a Wasm module.
  Future<WasmModule> loadModule(
      String moduleName, Uint8List wasmModuleBinary) async {
    return _loadedModules[moduleName] ??=
        await loadModuleImpl(moduleName, wasmModuleBinary);
  }

  /// Platform specific implementation.
  /// Call [loadModule].
  Future<WasmModule> loadModuleImpl(
      String moduleName, Uint8List wasmModuleBinary);

  /// Removes a Wasm module.
  FutureOr<WasmModule?> removeModule(String moduleName) {
    var module = _loadedModules.remove(moduleName);
    if (module == null) return null;

    return module.dispose().resolveWithValue(module);
  }
}

/// A WebAssembly (Wasm) Runtime module
abstract class WasmModule {
  /// The module name.
  final String name;

  WasmModule(this.name);

  /// Returns a copy instance of this module.
  Future<WasmModule> copy({String? name});

  /// Returns a module function mapped to [F].
  F? getFunction<F extends Function>(String functionName);

  /// Resolves the returned [value] from a called module function.
  Object? resolveReturnedValue(Object? value);

  /// Disposes this module instance.
  FutureOr<void> dispose() {}
}

/// [WasmModule] error.
class WasmModuleError extends Error {
  final String message;

  WasmModuleError(this.message);

  @override
  String toString() {
    return 'WasmModuleError: $message';
  }
}

/// Thrown when [WasmModule] fails to load.
class WasmModuleLoadError extends WasmModuleError {
  final Object? cause;

  WasmModuleLoadError(super.message, {this.cause});

  @override
  String toString() {
    return 'WasmModuleLoadError: $message\nCause: $cause';
  }
}

/// Thrown when [WasmModule] execution fails.
class WasmModuleExecutionError extends WasmModuleError {
  final String functionName;
  final List? parameters;
  final Function? function;

  final Object? cause;

  WasmModuleExecutionError(this.functionName,
      {this.parameters, this.function, String? message, this.cause})
      : super(
            "Error executing Wasm function> $functionName( $parameters )${function != null ? ' -> $function' : ''}");

  @override
  String toString() {
    return 'WasmModuleExecutionError: $message\nCause: $cause';
  }
}
