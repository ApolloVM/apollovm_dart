import 'dart:typed_data';

import '../../ast/apollovm_ast_toplevel.dart';
import 'package:async_extension/async_extension.dart';

import 'wasm_runtime_generic.dart'
    if (dart.library.js_interop) 'wasm_runtime_web.dart'
    if (dart.library.html) 'wasm_runtime_dart_html.dart'
    if (dart.library.io) 'wasm_runtime_io.dart';

/// A Wasm value type, for host import signatures.
enum WasmValueType { i32, i64, f32, f64 }

/// A host (Dart) function provided to satisfy a Wasm module import.
class WasmHostFunction {
  final List<WasmValueType> params;
  final List<WasmValueType> results;

  /// Invoked with the positional argument values; returns the result value
  /// (or `null` for a void import).
  final Object? Function(List<Object?> args) callback;

  const WasmHostFunction({
    required this.params,
    required this.results,
    required this.callback,
  });
}

/// Host imports to provide at instantiation, keyed by module name then import
/// name (e.g. `{'env': {'print': WasmHostFunction(...)}}`).
typedef WasmHostImports = Map<String, Map<String, WasmHostFunction>>;

/// A WebAssembly (Wasm) Runtime.
abstract class WasmRuntime {
  final Map<String, WasmModule> _loadedModules = {};

  WasmRuntime.base();

  factory WasmRuntime() {
    return createWasmRuntime();
  }

  /// Returns the platform version of the Wasm runtime.
  String get platformVersion;

  /// Ensures that the implementation is booted.
  void ensureBooted();

  /// Last error while booting the implementation.
  /// See [ensureBooted].
  Object? get lastBootError;

  /// Returns true if the WebAssembly (Wasm) Runtime is supported in the platform.
  bool get isSupported;

  /// Returns a loaded Wasm module.
  WasmModule? getModule(String moduleName) {
    return _loadedModules[moduleName];
  }

  /// Loads a Wasm module. [hostImports] provides the host (Dart) functions the
  /// module imports (e.g. `env.print`); only imports actually declared by the
  /// module are wired. When [hostImports] is provided the module is always
  /// instantiated fresh (not served from the cache) so the import closures are
  /// current.
  Future<WasmModule> loadModule(
    String moduleName,
    Uint8List wasmModuleBinary, {
    WasmHostImports? hostImports,
  }) async {
    if (hostImports != null) {
      return _loadedModules[moduleName] = await loadModuleImpl(
        moduleName,
        wasmModuleBinary,
        hostImports: hostImports,
      );
    }
    return _loadedModules[moduleName] ??= await loadModuleImpl(
      moduleName,
      wasmModuleBinary,
    );
  }

  /// Platform specific implementation.
  /// Call [loadModule].
  Future<WasmModule> loadModuleImpl(
    String moduleName,
    Uint8List wasmModuleBinary, {
    WasmHostImports? hostImports,
  });

  /// Removes a Wasm module.
  FutureOr<WasmModule?> removeModule(String moduleName) {
    var module = _loadedModules.remove(moduleName);
    if (module == null) return null;

    return module.dispose().resolveWithValue(module);
  }
}

/// Represents a WebAssembly-exported function with metadata.
///
/// Combines a callable Dart function [function] with information about
/// whether it accepts a variable number of arguments ([varArgs]).
///
/// - [function]: The Dart function mapped from a WebAssembly export.
/// - [varArgs]: Indicates if the function supports variadic arguments
///   (i.e., can be called with a dynamic number of parameters).
///
/// This is typically used when exposing or wrapping WebAssembly functions
/// in Dart, allowing the runtime to handle invocation semantics correctly.
typedef WasmModuleFunction<F extends Function> = ({F function, bool varArgs});

/// A WebAssembly (Wasm) Runtime module
abstract class WasmModule {
  /// The module name.
  final String name;

  WasmModule(this.name);

  /// Returns a copy instance of this module.
  Future<WasmModule> copy({String? name});

  /// Returns a module function mapped to [F].
  WasmModuleFunction<F>? getFunction<F extends Function>(String functionName);

  /// Resolves the returned [value] from a called module function.
  Object? resolveReturnedValue(Object? value, ASTFunctionDeclaration? f);

  /// Returns a view of the module's exported linear memory (named `memory`),
  /// or `null` if the module has no exported memory.
  Uint8List? readMemory() => null;

  /// Invokes an exported function [name] with [args], returning its result.
  /// Used by host imports that call back into the module (e.g. `__alloc`).
  Object? invokeExport(String name, List<Object?> args) =>
      throw UnimplementedError('invokeExport not supported on this platform');

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

  WasmModuleExecutionError(
    this.functionName, {
    this.parameters,
    this.function,
    String? message,
    this.cause,
  }) : super(
         "Error executing Wasm function> $functionName( $parameters )${function != null ? ' -> $function' : ''}",
       );

  @override
  String toString() {
    return 'WasmModuleExecutionError: $message\nCause: $cause';
  }
}
