# ApolloVM Wasm

Native (Dart VM) WebAssembly execution for [ApolloVM][apollovm].

ApolloVM compiles to Wasm on every platform. *Executing* a module is what needs
an engine: browsers ship one, the Dart VM does not. This package supplies the
VM engine (backed by [`wasm_run`][wasm_run]), and is kept separate so that
`package:apollovm` — used widely just to parse, translate and generate code —
never pulls a native/FFI toolchain into its consumers.

## Usage

```dart
import 'package:apollovm/apollovm.dart';
import 'package:apollovm_wasm/apollovm_wasm.dart';

void main() async {
  registerApolloVMWasmRuntime();

  final runtime = WasmRuntime()..ensureBooted();
  print(runtime.isSupported); // true
}
```

Without this package, `WasmRuntime()` on the Dart VM reports
`isSupported == false`: Wasm still compiles, it just cannot be executed.

The native runtime needs its dynamic library — run `dart run wasm_run:setup`
once.

[apollovm]: https://pub.dev/packages/apollovm
[wasm_run]: https://pub.dev/packages/wasm_run
