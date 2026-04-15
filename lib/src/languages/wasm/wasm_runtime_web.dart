import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../../ast/apollovm_ast_toplevel.dart';
import 'wasm_runtime.dart';

/// ===== WebAssembly bindings (extension types) =====

@JS('WebAssembly')
external _WebAssembly get _webAssembly;

@JS('WebAssembly')
extension type _WebAssembly(JSObject _) implements JSObject {
  external JSPromise<_WasmInstantiateResult> instantiate(
    JSArrayBuffer bytes, [
    JSAny? imports,
  ]);
}

extension type _WasmInstantiateResult(JSObject _) implements JSObject {
  external _WasmInstance get instance;

  external JSObject get module;
}

@JS('WebAssembly.Instance')
extension type _WasmInstance(JSObject _) implements JSObject {
  external _WasmExports get exports;
}

extension type _WasmExports(JSObject _) implements JSObject {
  JSFunction? function(String name) => this[name] as JSFunction?;

  JSNumber? number(String name) => this[name] as JSNumber?;

  JSObject? memory(String name) => this[name] as JSObject?;
}

@JS('Number')
external JSNumber _jsNumber(JSAny value);

@JS('Number.isInteger')
external bool _jsNumberIsInteger(JSNumber n);

@JS('BigInt')
external JSBigInt _jsBigInt(JSAny value);

extension type JSBigIntX(JSBigInt _) implements JSAny {
  /// JS constructor: BigInt(value)
  factory JSBigIntX.from(JSAny value) => JSBigIntX(_jsBigInt(value));
}

final _maxSafeInteger = JSBigIntX.from(9007199254740991.toJS);
final _minSafeInteger = JSBigIntX.from((-9007199254740991).toJS);

num? _toSafeNumber(JSBigInt o) {
  if (o.greaterThan(_maxSafeInteger).toDart ||
      o.lessThan(_minSafeInteger).toDart) {
    return null;
  }

  var n = _jsNumber(o);

  if (_jsNumberIsInteger(n)) {
    return n.toDartInt;
  } else {
    return n.toDartDouble;
  }
}

/// ===== Runtime =====

class WasmRuntimeWeb extends WasmRuntime {
  WasmRuntimeWeb() : super.base();

  @override
  String get platformVersion =>
      'Browser(web): ${web.window.navigator.userAgent}';

  @override
  void ensureBooted() {}

  @override
  Object? get lastBootError => null;

  @override
  bool get isSupported => true;

  @override
  Future<WasmModuleBrowser> loadModuleImpl(
    String moduleName,
    Uint8List wasmModuleBinary,
  ) async {
    try {
      final buffer = wasmModuleBinary.buffer.toJS;

      final result = await _webAssembly.instantiate(buffer).toDart;

      final instance = result.instance;

      return WasmModuleBrowser._(moduleName, instance);
    } catch (e) {
      throw WasmModuleLoadError(
        "Can't load wasm module: $moduleName",
        cause: e,
      );
    }
  }
}

/// ===== Module =====

class WasmModuleBrowser extends WasmModule {
  final _WasmInstance _instance;

  WasmModuleBrowser._(super.name, this._instance);

  @override
  Future<WasmModuleBrowser> copy({String? name}) async {
    throw UnimplementedError(
      'Copy requires original wasm bytes (not available from Instance)',
    );
  }

  @override
  WasmModuleFunction<F>? getFunction<F extends Function>(String functionName) {
    final exports = _instance.exports;

    final fn = exports.function(functionName);
    if (fn == null) return null;

    Object? function([List? args]) {
      final JSAny? result;
      if (args == null || args.isEmpty) {
        result = fn.callAsFunction(null);
      } else {
        final jsArgs = args.map((Object? e) => e?.jsify()).toList();
        if (jsArgs.isEmpty) {
          result = fn.callAsFunction(null);
        } else if (jsArgs.length == 1) {
          result = fn.callAsFunction(null, jsArgs[0]);
        } else if (jsArgs.length == 2) {
          result = fn.callAsFunction(null, jsArgs[0], jsArgs[1]);
        } else if (jsArgs.length == 3) {
          result = fn.callAsFunction(null, jsArgs[0], jsArgs[1], jsArgs[2]);
        } else if (jsArgs.length == 4) {
          result = fn.callAsFunction(
            null,
            jsArgs[0],
            jsArgs[1],
            jsArgs[2],
            jsArgs[3],
          );
        } else {
          result = fn.applyAsFunction(null, jsArgs.toJS);
        }
      }

      return result.dartify();
    }

    return (function: function as F, varArgs: false);
  }

  @override
  Object? resolveReturnedValue(Object? value, ASTFunctionDeclaration? f) {
    if (value == null) return null;

    var jsAny = value.asJSAny;

    if (jsAny.isA<JSBigInt>()) {
      final jsBig = jsAny as JSBigInt;

      var n = _toSafeNumber(jsBig);
      if (n != null) {
        return n;
      }

      final s = jsBig.toString();
      final big = BigInt.parse(s);
      return big;
    }

    return value;
  }

  @override
  String toString() {
    return 'WasmModuleBrowser{name: $name, instance: $_instance}';
  }
}

WasmRuntime createWasmRuntime() {
  return WasmRuntimeWeb();
}

extension _JSFunctionUtilExtension on JSFunction {
  /// Call this [JSFunction] using the JavaScript `.apply` syntax and returns the
  /// result.
  ///
  /// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Function/apply
  @JS('apply')
  external JSAny? applyAsFunction(JSAny? thisArg, [JSArray<JSAny?> argsArray]);
}

extension _ObjectExtension on Object? {
  /// Returns `true` if this instance is a [JSAny].
  /// Returns `null` if it's an ambiguous Dart/JS type.
  bool? get isJSAny {
    final self = this;
    if (self == null) return false;

    // Ambiguous types:

    if (self is String) {
      // ignore: invalid_runtime_check_with_js_interop_types
      if (self is JSString) {
        return true;
      } else {
        return false;
      }
    }

    if (self is num) {
      // ignore: invalid_runtime_check_with_js_interop_types
      if (self is JSNumber) {
        return true;
      } else {
        return false;
      }
    }

    if (self is bool) {
      // ignore: invalid_runtime_check_with_js_interop_types
      if (self is JSBoolean) {
        return true;
      } else {
        return false;
      }
    }

    if (self is Function) {
      // ignore: invalid_runtime_check_with_js_interop_types
      if (self is JSFunction) {
        return null;
      } else {
        return false;
      }
    }

    if (self is List) {
      // ignore: invalid_runtime_check_with_js_interop_types
      if (self is JSArray || self is JSTypedArray) {
        return null;
      } else {
        return false;
      }
    }

    if (self is Map) {
      // ignore: invalid_runtime_check_with_js_interop_types
      if (self is JSArray || self is JSObject) {
        return null;
      } else {
        return false;
      }
    }

    // ignore: invalid_runtime_check_with_js_interop_types
    return self is JSAny;
  }

  /// Casts an [Object] to a [JSAny], in a graceful manner.
  /// See [isJSAny].
  JSAny? get asJSAny {
    final self = this;
    if (self == null) return null;

    var isJSAny = self.isJSAny;
    if (isJSAny != null) {
      if (isJSAny) {
        return self as JSAny;
      } else {
        return null;
      }
    } else {
      try {
        return self as JSAny;
      } catch (_) {
        return null;
      }
    }
  }
}
