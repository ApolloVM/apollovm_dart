/// Installs the Wasm runtime the current platform needs, before a test uses
/// `WasmRuntime()`.
///
/// The native (VM) engine lives in `package:apollovm_wasm` and must be
/// registered; browsers have one built in, so there it is a no-op. The
/// conditional import keeps `dart:ffi`/`dart:io` out of the browser build.
library;

export 'wasm_runtime_setup_web.dart'
    if (dart.library.io) 'wasm_runtime_setup_vm.dart';
