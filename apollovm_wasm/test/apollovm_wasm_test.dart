@TestOn('vm')
@Tags(['wasm'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:apollovm_wasm/apollovm_wasm.dart';
import 'package:test/test.dart';

void main() {
  group('registerApolloVMWasmRuntime', () {
    test('the VM has no Wasm engine until this package registers one', () {
      // Must run before any registration: `_provider` is global, so this is
      // the only point at which the un-registered default is observable.
      final unregistered = WasmRuntime()..ensureBooted();

      expect(
        unregistered.isSupported,
        isFalse,
        reason:
            'Core `apollovm` must not ship a VM Wasm engine — that is the '
            'whole point of this package existing.',
      );
      expect(unregistered, isNot(isA<WasmRuntimeIO>()));
    });

    test('registers the native runtime', () {
      registerApolloVMWasmRuntime();

      final runtime = WasmRuntime()..ensureBooted();

      expect(runtime, isA<WasmRuntimeIO>());
      expect(
        runtime.isSupported,
        isTrue,
        reason:
            'The `wasm_run` dynamic library must be present — it is downloaded '
            'by the `wasm_run` build hook (`.dart_tool/lib/`), or pointed at by '
            '`WASM_RUN_DART_DYNAMIC_LIBRARY`. '
            'Boot error: ${runtime.lastBootError}',
      );
    });

    test('is idempotent', () {
      registerApolloVMWasmRuntime();
      registerApolloVMWasmRuntime();

      expect(WasmRuntime(), isA<WasmRuntimeIO>());
    });
  });

  group('end-to-end', () {
    setUp(registerApolloVMWasmRuntime);

    test(
      'compiles Dart to Wasm and executes it on the native runtime',
      () async {
        const code = r'''
        int sumTo(int limit) {
          int sum = 0;
          for (int i = 1; i <= limit; ++i) {
            sum += i;
          }
          return sum;
        }
      ''';

        // Compile: this half is core `apollovm`, and needs nothing from here.
        final vm = ApolloVM();
        expect(
          await vm.loadCodeUnit(SourceCodeUnit('dart', code, id: 'test')),
          isTrue,
        );

        final storage = vm.generateAllIn<BytesOutput>('wasm');
        final modules = await storage.allEntries();
        final compiled = modules.values.first.values.first;

        // Execute: this half is what `apollovm_wasm` makes possible on the VM.
        final wasmVM = ApolloVM();
        final loaded = await wasmVM.loadCodeUnit(
          BinaryCodeUnit(
            'wasm',
            compiled.output(),
            id: 'test.wasm',
            namespace: '',
          ),
        );
        expect(loaded, isTrue);

        final runner = wasmVM.createRunner('wasm')!;

        final result = await runner.executeFunction(
          '',
          'sumTo',
          positionalParameters: [10],
        );

        expect(result.getValueNoContext(), 55);
      },
    );
  });
}
