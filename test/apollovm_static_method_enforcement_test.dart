@Tags(['wasm', 'dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Compiles the loaded code in [vm] to a single Wasm module.
Future<BytesOutput> _compileWasm(ApolloVM vm) async {
  var storage = vm.generateAllIn<BytesOutput>('wasm');
  var modules = await storage.allEntries();
  for (var ns in modules.entries) {
    for (var m in ns.value.entries) {
      return m.value;
    }
  }
  fail('No compiled Wasm module');
}

/// Loads [src] (Dart) and returns an interpreter runner for it.
Future<ApolloRunner> _dartRunner(String src) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', src, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source");
  return vm.createRunner('dart')!;
}

void main() {
  group('Interpreter: only static methods run without an instance', () {
    const src = r'''
      class Foo {
        static int s(int x) { return x + 1; }
        int inst(int x) { return x + 2; }
        int v;
        Foo(this.v);
        int useField() { return v; }
        static int callsInstanceSibling() { return _helper(); }
        int _helper() { return 5; }
      }
    ''';

    test('static method runs with no instance', () async {
      var r = await _dartRunner(src);
      var v = await r.executeClassMethod(
        '',
        'Foo',
        's',
        positionalParameters: [10],
      );
      expect(v.getValueNoContext(), equals(11));
    });

    test('non-static method without an instance throws', () async {
      var r = await _dartRunner(src);
      await expectLater(
        r.executeClassMethod('', 'Foo', 'inst', positionalParameters: [10]),
        throwsA(isA<ApolloVMRuntimeError>()),
      );
    });

    test('non-static method runs when given an instance', () async {
      var r = await _dartRunner(src);
      var v = await r.executeClassMethod(
        '',
        'Foo',
        'inst',
        positionalParameters: [10],
        classInstanceFields: const {},
      );
      expect(v.getValueNoContext(), equals(12));
    });

    test('non-static method reads instance fields when supplied', () async {
      var r = await _dartRunner(src);
      var v = await r.executeClassMethod(
        '',
        'Foo',
        'useField',
        classInstanceFields: {'v': ASTValue.fromValue(7)},
      );
      expect(v.getValueNoContext(), equals(7));
    });

    test('static method calling a non-static sibling throws', () async {
      // Even via an internal (unqualified) call, a non-static method reached
      // without a `this` in context must throw — not silently use a missing
      // instance.
      var r = await _dartRunner(src);
      await expectLater(
        r.executeClassMethod('', 'Foo', 'callsInstanceSibling'),
        throwsA(isA<ApolloVMRuntimeError>()),
      );
    });
  });

  group('Wasm: only static methods are callable without an instance', () {
    const src = r'''
      class Foo {
        static int s(int x) { return x + 1; }
        int inst(int x) { return x + 2; }
      }
    ''';

    Future<ApolloRunner> wasmRunner() async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(SourceCodeUnit('dart', src, id: 'test'));
      var compiled = await _compileWasm(vm);
      var vmWasm = ApolloVM();
      await vmWasm.loadCodeUnit(
        BinaryCodeUnit(
          'wasm',
          compiled.output(),
          id: 'test.wasm',
          namespace: '',
        ),
      );
      return vmWasm.createRunner('wasm')!;
    }

    test('static method runs in the compiled module', () async {
      var r = await wasmRunner();
      var v = await r.executeClassMethod(
        '',
        'Foo',
        's',
        positionalParameters: [41],
      );
      expect(v.getValueNoContext(), equals(42));
    });

    test('non-static method is not callable (clear error)', () async {
      var r = await wasmRunner();
      await expectLater(
        r.executeClassMethod('', 'Foo', 'inst', positionalParameters: [1]),
        throwsA(isA<ApolloVMRuntimeError>()),
      );
    });

    test(
      'supplying an instance is rejected (no instance entry points)',
      () async {
        var r = await wasmRunner();
        await expectLater(
          r.executeClassMethod(
            '',
            'Foo',
            's',
            positionalParameters: [1],
            classInstanceFields: const {},
          ),
          throwsA(isA<ApolloVMRuntimeError>()),
        );
      },
    );
  });

  group('Wasm generation: receiver-less non-static call is rejected', () {
    test(
      'static method calling an instance sibling fails to compile',
      () async {
        var vm = ApolloVM();
        await vm.loadCodeUnit(
          SourceCodeUnit('dart', r'''
          class Foo {
            int v;
            Foo(this.v);
            int helper() { return v; }
            static int run() { return helper(); }
          }
        ''', id: 'test'),
        );
        await expectLater(_compileWasm(vm), throwsA(isA<UnsupportedError>()));
      },
    );
  });
}
