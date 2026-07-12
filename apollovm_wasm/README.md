## ApolloVM Wasm


[![pub package](https://img.shields.io/pub/v/apollovm_wasm.svg?logo=dart&logoColor=00b9fc)](https://pub.dartlang.org/packages/apollovm_wasm)
[![Null Safety](https://img.shields.io/badge/null-safety-brightgreen)](https://dart.dev/null-safety)
[![Codecov](https://img.shields.io/codecov/c/github/ApolloVM/apollovm_dart)](https://app.codecov.io/gh/ApolloVM/apollovm_dart)
[![Dart CI](https://github.com/ApolloVM/apollovm_dart/actions/workflows/dart.yml/badge.svg?branch=master)](https://github.com/ApolloVM/apollovm_dart/actions/workflows/dart.yml)
[![GitHub Tag](https://img.shields.io/github/v/tag/ApolloVM/apollovm_dart?logo=git&logoColor=white)](https://github.com/ApolloVM/apollovm_dart/releases)
[![New Commits](https://img.shields.io/github/commits-since/ApolloVM/apollovm_dart/latest?logo=git&logoColor=white)](https://github.com/ApolloVM/apollovm_dart/network)
[![Last Commits](https://img.shields.io/github/last-commit/ApolloVM/apollovm_dart?logo=git&logoColor=white)](https://github.com/ApolloVM/apollovm_dart/commits/master)
[![Pull Requests](https://img.shields.io/github/issues-pr/ApolloVM/apollovm_dart?logo=github&logoColor=white)](https://github.com/ApolloVM/apollovm_dart/pulls)
[![Code size](https://img.shields.io/github/languages/code-size/ApolloVM/apollovm_dart?logo=github&logoColor=white)](https://github.com/ApolloVM/apollovm_dart)
[![License](https://img.shields.io/github/license/ApolloVM/apollovm_dart?logo=open-source-initiative&logoColor=green)](https://github.com/ApolloVM/apollovm_dart/blob/master/LICENSE)

Native (Dart VM) WebAssembly **execution** for [ApolloVM][apollovm_pub].

[ApolloVM][apollovm_pub] compiles its AST to Wasm on the fly, on every platform, without any
third-party toolchain. *Running* a compiled module is what needs an engine: browsers ship one, the
Dart VM does not. This package supplies the VM engine, backed by [`wasm_run`][wasm_run_pub].

-----------------------------

## Why a Separate Package?

The native engine brings an FFI/Rust toolchain with it (`wasm_run` → `flutter_rust_bridge`). Keeping
it here means `package:apollovm` — widely used *only* to parse, translate and generate code — never
drags that cost, nor its dependency constraints, into consumers that never execute Wasm.

|                                  | `apollovm` | `apollovm` + `apollovm_wasm` |
|----------------------------------|:----------:|:----------------------------:|
| Parse / translate / generate     |     ✅      |              ✅               |
| **Compile** to Wasm              |     ✅      |              ✅               |
| **Execute** Wasm in the browser  |     ✅      |              ✅               |
| **Execute** Wasm on the Dart VM  |     ❌      |              ✅               |
| Native / FFI toolchain pulled in |     no     |             yes              |

Without this package, `WasmRuntime()` on the Dart VM reports `isSupported == false`: Wasm still
compiles, it just cannot be executed.

-----------------------------

## Usage

Add both packages:

```yaml
dependencies:
  apollovm: ^2.0.0
  apollovm_wasm: ^1.0.0
```

Install the native library once (it is downloaded, not built):

```shell
dart run wasm_run:setup
```

Register the runtime, and `WasmRuntime()` returns an engine that executes:

```dart
import 'package:apollovm/apollovm.dart';
import 'package:apollovm_wasm/apollovm_wasm.dart';

void main() {
  registerApolloVMWasmRuntime();

  var runtime = WasmRuntime()..ensureBooted();
  print(runtime.isSupported); // true
}
```

### Compiling Dart to Wasm, then executing it

```dart
import 'package:apollovm/apollovm.dart';
import 'package:apollovm_wasm/apollovm_wasm.dart';

void main() async {
  registerApolloVMWasmRuntime();

  // Compile: this half is core `apollovm`.
  var vm = ApolloVM();

  await vm.loadCodeUnit(SourceCodeUnit('dart', r'''
  
    int sumTo(int limit) {
      int sum = 0;
      for (int i = 1; i <= limit; ++i) {
        sum += i;
      }
      return sum;
    }
    
  ''', id: 'test'));

  var storageWasm = vm.generateAllIn<BytesOutput>('wasm');
  var wasmModules = await storageWasm.allEntries();
  var wasmBytes = wasmModules.values.first.values.first.output();

  // Execute: this half is what `apollovm_wasm` makes possible on the VM.
  var wasmVM = ApolloVM();

  await wasmVM.loadCodeUnit(
      BinaryCodeUnit('wasm', wasmBytes, id: 'test.wasm', namespace: ''));

  var runner = wasmVM.createRunner('wasm')!;

  var result =
      await runner.executeFunction('', 'sumTo', positionalParameters: [10]);

  print(result.getValueNoContext()); // 55
}
```

-----------------------------

## WebAssembly GC

The `wasm_run` backend (wasmtime 14 / wasmi 0.31) does **not** implement the WebAssembly GC
proposal. Modules that rely on it run in the browser (Chrome 119+), not on this runtime.

## See Also

- [`apollovm`][apollovm_pub] — the VM itself: parsing, translation, execution and Wasm compilation.
- [`wasm_run`][wasm_run_pub] — the native Wasm engine this package binds to.

[apollovm_pub]: https://pub.dev/packages/apollovm
[wasm_run_pub]: https://pub.dev/packages/wasm_run

## Features and bugs

Please file feature requests and bugs at the [issue tracker][tracker].

[tracker]: https://github.com/ApolloVM/apollovm_dart/issues

## Author

Graciliano M. Passos: [gmpassos@GitHub][github].

[github]: https://github.com/gmpassos

## Sponsor

Don't be shy, show some love, and become our [GitHub Sponsor][github_sponsors].
Your support means the world to us, and it keeps the code caffeinated! ☕✨

Thanks a million! 🚀😄

[github_sponsors]: https://github.com/sponsors/gmpassos

## License

[Apache License - Version 2.0][apache_license]

[apache_license]: https://www.apache.org/licenses/LICENSE-2.0.txt
