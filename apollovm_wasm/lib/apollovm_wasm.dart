// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

/// Native (Dart VM) WebAssembly execution for ApolloVM.
///
/// ApolloVM compiles to Wasm on every platform, but *executing* a module needs
/// a Wasm engine. Browsers ship one; the Dart VM does not, so it needs a native
/// engine (`package:wasm_run`, which brings an FFI/Rust toolchain with it).
/// That cost is confined to this package: `package:apollovm` alone never pulls
/// it in.
///
/// Import this package and register the runtime before running Wasm on the VM:
///
/// ```dart
/// import 'package:apollovm/apollovm.dart';
/// import 'package:apollovm_wasm/apollovm_wasm.dart';
///
/// void main() async {
///   registerApolloVMWasmRuntime();
///
///   final runtime = WasmRuntime()..ensureBooted();
///   print(runtime.isSupported); // true
/// }
/// ```
library;

import 'package:apollovm/apollovm.dart';

import 'src/wasm_runtime_io.dart';

export 'src/wasm_runtime_io.dart' show WasmRuntimeIO, WasmModuleIO;

/// Installs the native (Dart VM) [WasmRuntime], so `WasmRuntime()` returns an
/// engine that can execute modules rather than the unsupported default.
///
/// Idempotent: calling it more than once is harmless.
void registerApolloVMWasmRuntime() {
  WasmRuntime.registerProvider(WasmRuntimeIO.new);
}
