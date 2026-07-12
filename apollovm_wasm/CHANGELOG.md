## 1.0.0

- Initial release: the native (Dart VM) `WasmRuntime`, extracted from
  `package:apollovm` 2.0.0.

  ApolloVM compiles to Wasm everywhere, but *executing* a module on the Dart VM
  needs a native engine (`wasm_run`), which drags an FFI/Rust toolchain — and
  an old `flutter_rust_bridge` — into every consumer of `apollovm`, even the
  ones that only parse or translate code. That cost now lives here.

  Call `registerApolloVMWasmRuntime()` to install it; `WasmRuntime()` then
  executes on the VM as before.
