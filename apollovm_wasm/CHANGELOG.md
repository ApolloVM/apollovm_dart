## 1.2.0

- `apollovm: ^2.25.0` (was `^2.0.0`) — this runtime decodes what the `apollovm` Wasm generator
  encodes, and the boxed-`Object` cell layout (`[tag@0][typeId@4][payload@8]`) with its
  `_boxTag*` values is a contract between the two: `wasm_runner.dart` and `wasm_generator.dart`
  each carry a comment saying the constants must match.

  `^2.0.0` let pub pair this runtime with any `apollovm` 2.x, including releases whose box
  encoding it was never built or tested against — a mismatch that surfaces as a wrong value or
  a trap at run time, not as a resolution error. The constraint now tracks the release the
  runtime is cut against; it is widened deliberately, not by default.

  apollovm 2.25.0 is a case in point: it added `?.` on a boxed slot, which emits box reads this
  runtime has to agree with.

- `wasm_run: ^0.2.0+2` (was `^0.2.0+1`) — patch upgrade, no API change.

## 1.1.0

- `wasm_run: ^0.2.0+1` (was `^0.1.0+2`) — a breaking upgrade, absorbed here so that consumers
  keep the same `WasmRuntimeIO` API:

  - **No install step.** `dart run wasm_run:setup` is gone; the SDK's build hooks download the
    native library into `.dart_tool/lib/` during `dart run`/`dart test`/`dart compile`. That
    directory is now searched first, along with `.dart_tool/wasm_run/` (the
    `wasm_run:build_binaries` output) — walking up to every enclosing package root, so a nested
    package finds a library fetched by its workspace.
  - The bindings moved to `flutter_rust_bridge` 2.x, so the symbol that identifies a genuine
    `wasm_run` library changed (`wire_compile_wasm` → `frb_get_rust_content_hash`); validating
    the old one rejected every 0.2 library.
  - `wasm_run` 0.2 initializes its Rust bindings **asynchronously** and no longer finds its own
    library in a pure-Dart app. `WasmRunLibrary.setUp()` is now awaited once, lazily, on the
    first module compile — `ensureBooted()`/`isSupported` stay synchronous, as `WasmRuntime`
    requires, and only probe for the library.
  - `WASM_RUN_DART_DYNAMIC_LIBRARY` (the variable `wasm_run` itself reads) now overrides the
    library path. The older `WASM_RUN_LIB_PATH` is still honored, and is finally read as a
    *path*: it used to be consulted only on platforms with no known library name, and then
    joined with candidate directories as if it were a file name.

- Requires Dart >= 3.10 (build hooks), matching `wasm_run` 0.2.

- **Known issue (macOS on Apple Silicon).** The upstream `aarch64-apple-darwin` 0.2.0 library is
  killed by macOS (`SIGKILL`, *Code Signature Invalid*) when wasmtime executes JIT-compiled Wasm
  inside the JIT Dart VM, i.e. under `dart run`/`dart test`. Compiling and instantiating modules
  is fine. Use `dart test --compiler exe` / `dart compile exe` there; other platforms are
  unaffected. See the README.

## 1.0.0

- Initial release: the native (Dart VM) `WasmRuntime`, extracted from
  `package:apollovm` 2.0.0.

  ApolloVM compiles to Wasm everywhere, but *executing* a module on the Dart VM
  needs a native engine (`wasm_run`), which drags an FFI/Rust toolchain — and
  an old `flutter_rust_bridge` — into every consumer of `apollovm`, even the
  ones that only parse or translate code. That cost now lives here.

  Call `registerApolloVMWasmRuntime()` to install it; `WasmRuntime()` then
  executes on the VM as before.
