import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as pack_path;
import 'package:wasm_run/wasm_run.dart' as wasm_run;

import 'package:apollovm/apollovm.dart';

/// [WasmRuntime] implementation for Dart VM.
class WasmRuntimeIO extends WasmRuntime {
  static bool _boot = false;

  static bool _wasmRunDynLibLoaded = false;

  static Object? _lastBootError;

  /// The dynamic library resolved by [boot], or `null` when `wasm_run` is
  /// expected to resolve it on its own (already loaded into the process, or
  /// reachable through its default lookup).
  static String? _wasmRunLibPath;

  static void boot() {
    if (_boot) return;
    _boot = true;

    try {
      var ok = _bootImpl();
      if (ok) {
        _wasmRunDynLibLoaded = true;
      }
    } catch (e) {
      _lastBootError = e;
    }
  }

  /// Symbol exported by every `flutter_rust_bridge` 2.x library: the cheapest
  /// way to tell a real `wasm_run` library from a same-named impostor.
  static const _wasmRunLibrarySymbol = 'frb_get_rust_content_hash';

  static bool _bootImpl() {
    // Already in the process (a Flutter plugin, or a statically linked host).
    if (_processProvidesLibrary()) {
      _wasmRunLibPath = null;
      return true;
    }

    var libPath = _wasmRunLibraryFilePath();

    if (libPath == null) {
      // Last resort: let the OS loader resolve the plain name (system
      // directories, `LD_LIBRARY_PATH`, next to the executable).
      var libName = _wasmRunLibraryFileName();
      if (libName != null && _opensValidLibrary(libName)) {
        print('** Loading `wasm_run` dynamic library by name: $libName');
        _wasmRunLibPath = libName;
        return true;
      }

      throw StateError(
        "Unable to locate the `wasm_run` dynamic library. "
        "It is normally downloaded into `.dart_tool/lib/` by the `wasm_run` "
        "build hook, which the SDK runs on `dart run`/`dart test`/`dart compile` "
        "— check that the build hooks ran. You can also point at a library "
        "explicitly with the environment variable "
        "`WASM_RUN_DART_DYNAMIC_LIBRARY`.",
      );
    }

    print('** Loading `wasm_run` dynamic library: $libPath');

    var dynLib = DynamicLibrary.open(libPath);

    var ok = dynLib.providesSymbol(_wasmRunLibrarySymbol);
    if (!ok) {
      throw StateError("Invalid `wasm_run` dynamic library: $libPath");
    }

    _wasmRunLibPath = libPath;
    return true;
  }

  static bool _processProvidesLibrary() {
    try {
      return DynamicLibrary.process().providesSymbol(_wasmRunLibrarySymbol);
    } catch (_) {
      return false;
    }
  }

  static bool _opensValidLibrary(String path) {
    try {
      return DynamicLibrary.open(path).providesSymbol(_wasmRunLibrarySymbol);
    } catch (_) {
      return false;
    }
  }

  WasmRuntimeIO() : super.base();

  @override
  String get platformVersion => 'Dart: ${Platform.version}';

  @override
  void ensureBooted() {
    boot();
  }

  @override
  Object? get lastBootError => _lastBootError;

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

  /// `wasm_run` 0.2 initializes its Rust bindings asynchronously, so the
  /// library can only be wired up from an `async` entry point — [boot] alone
  /// (which must stay synchronous, per [WasmRuntime.ensureBooted]) is not
  /// enough. Kept as a single future so concurrent loads share one setup.
  static Future<void>? _librarySetUp;

  static Future<void> _ensureLibrarySetUp() =>
      _librarySetUp ??= _setUpLibraryImpl();

  static Future<void> _setUpLibraryImpl() async {
    boot();

    if (!_wasmRunDynLibLoaded) {
      throw StateError(
        "Can't set up the `wasm_run` library: ${_lastBootError ?? 'unknown error'}",
      );
    }

    // Already configured (by the host application), or reachable through
    // `wasm_run`'s own lookup: let it use that. Calling `setUp` with an
    // explicit library after it was configured throws.
    if (await wasm_run.WasmRunLibrary.isReachable()) {
      await wasm_run.WasmRunLibrary.setUp();
      return;
    }

    var libPath = _wasmRunLibPath;
    await wasm_run.WasmRunLibrary.setUp(
      lib: libPath != null ? wasm_run.ExternalLibrary.open(libPath) : null,
    );
  }

  @override
  Future<WasmModuleIO> loadModuleImpl(
    String moduleName,
    Uint8List wasmModuleBinary, {
    WasmHostImports? hostImports,
  }) async {
    var module = await _compileModule(wasmModuleBinary);

    var builder = module.builder();

    // Wire only the imports the module actually declares, from [hostImports].
    if (hostImports != null) {
      for (var imp in module.getImports()) {
        if (imp.kind != wasm_run.WasmExternalKind.function) continue;
        var hostFn = hostImports[imp.module]?[imp.name];
        if (hostFn == null) continue;
        builder.addImport(imp.module, imp.name, _toWasmFunction(hostFn));
      }
    }

    var moduleInstance = await builder.build();
    return WasmModuleIO(moduleName, module, moduleInstance);
  }

  static wasm_run.ValueTy _toValueTy(WasmValueType t) => switch (t) {
    WasmValueType.i32 => wasm_run.ValueTy.i32,
    WasmValueType.i64 => wasm_run.ValueTy.i64,
    WasmValueType.f32 => wasm_run.ValueTy.f32,
    WasmValueType.f64 => wasm_run.ValueTy.f64,
  };

  static wasm_run.WasmFunction _toWasmFunction(WasmHostFunction hf) {
    var params = hf.params.map(_toValueTy).toList();

    // Adapter matching the import's arity; wasm_run invokes `inner`
    // positionally.
    Function inner = switch (hf.params.length) {
      0 => () => hf.callback(const []),
      1 => (Object? a) => hf.callback([a]),
      2 => (Object? a, Object? b) => hf.callback([a, b]),
      3 => (Object? a, Object? b, Object? c) => hf.callback([a, b, c]),
      _ => throw UnsupportedError(
        'Wasm host import arity ${hf.params.length} not supported',
      ),
    };

    if (hf.results.isEmpty) {
      return wasm_run.WasmFunction.voidReturn(inner, params: params);
    }
    return wasm_run.WasmFunction(
      inner,
      params: params,
      results: hf.results.map(_toValueTy).toList(),
    );
  }

  final Map<String, wasm_run.WasmModule> _compiledModules = {};

  Future<wasm_run.WasmModule> _compileModule(Uint8List wasmModuleBinary) async {
    var binarySignature = _computeBinarySignatureHex(wasmModuleBinary);

    var module = _compiledModules[binarySignature] ??= await _compileModuleImpl(
      wasmModuleBinary,
    );

    return module;
  }

  Future<wasm_run.WasmModule> _compileModuleImpl(
    Uint8List wasmModuleBinary,
  ) async {
    await _ensureLibrarySetUp();
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
  WasmModuleFunction<F>? getFunction<F extends Function>(String functionName) {
    var f = instance.getFunction(functionName);
    if (f == null) return null;

    var function = f.inner as F?;
    if (function == null) return null;

    return (function: function, varArgs: true);
  }

  @override
  Uint8List? readMemory() => instance.getMemory('memory')?.view;

  @override
  Object? invokeExport(String name, List<Object?> args) {
    var f = instance.getFunction(name);
    if (f == null) {
      throw StateError("No exported Wasm function `$name`");
    }
    return Function.apply(f.inner, args);
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

String? _wasmRunLibraryFileName() {
  if (Platform.isMacOS || Platform.isIOS) {
    return 'libwasm_run_dart.dylib';
  } else if (Platform.isWindows) {
    return 'wasm_run_dart.dll';
  } else if (Platform.isLinux || Platform.isAndroid) {
    return 'libwasm_run_dart.so';
  }
  return null;
}

/// The environment variable `wasm_run` itself reads to override the library
/// path. `WASM_RUN_LIB_PATH` is the older ApolloVM-specific name, still
/// honored.
const _libPathEnvVars = ['WASM_RUN_DART_DYNAMIC_LIBRARY', 'WASM_RUN_LIB_PATH'];

String? _wasmRunLibraryFilePath() {
  for (var envVar in _libPathEnvVars) {
    var envPath = Platform.environment[envVar];
    if (envPath != null && envPath.isNotEmpty && File(envPath).existsSync()) {
      return pack_path.normalize(File(envPath).absolute.path);
    }
  }

  var libName = _wasmRunLibraryFileName();
  if (libName == null || libName.isEmpty) return null;

  var possibleDirs = [
    // Where the `wasm_run` build hook (Dart 3.10+) drops the downloaded
    // binary, and where the `wasm_run:build_binaries` CLI writes by default.
    for (var pkgRoot in _packageRoots()) ...[
      pack_path.join(pkgRoot, '.dart_tool', 'lib'),
      pack_path.join(pkgRoot, '.dart_tool', 'wasm_run'),
    ],
    // Next to the executable / working directory (bundled deployments).
    '.',
    '../',
    '../../',
    'lib',
    '../lib',
    '../../lib',
  ];

  for (var dirPath in possibleDirs) {
    var file = File(pack_path.join(dirPath, libName));
    if (file.existsSync()) {
      return pack_path.normalize(file.absolute.path);
    }
  }

  return null;
}

/// Walks up from the current directory and from the running script looking for
/// a Dart package root (a directory holding `.dart_tool/package_config.json`).
List<String> _packageRoots() {
  var roots = <String>[];

  void addRootsFrom(String? from) {
    if (from == null) return;

    var dir = pack_path.normalize(from);

    while (true) {
      if (File(
        pack_path.join(dir, '.dart_tool', 'package_config.json'),
      ).existsSync()) {
        if (!roots.contains(dir)) roots.add(dir);
      }

      var parent = pack_path.dirname(dir);
      if (parent == dir) break;
      dir = parent;
    }
  }

  addRootsFrom(Directory.current.absolute.path);

  var script = Platform.script;
  if (script.isScheme('file')) {
    addRootsFrom(pack_path.dirname(script.toFilePath()));
  }

  return roots;
}
