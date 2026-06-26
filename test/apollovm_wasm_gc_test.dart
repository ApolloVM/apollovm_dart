@TestOn('chrome')
@Tags(['wasm', 'wasm-gc'])
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:test/test.dart';

// Minimal binding to the browser's WebAssembly.instantiate.
@JS('WebAssembly.instantiate')
external JSPromise<JSObject> _instantiate(JSArrayBuffer bytes);

@JS('WebAssembly.validate')
external bool _validate(JSArrayBuffer bytes);

/// A hand-encoded minimal **WasmGC** module:
///
/// ```wat
/// (module
///   (type $arr (array (mut i8)))      ;; type 0
///   (type $f (func (result i32)))     ;; type 1
///   (func (type 1) (result i32)
///     i32.const 5
///     array.new_default 0   ;; ref to a 5-element i8 array (defaults to 0)
///     array.len)            ;; -> 5
///   (export "gcLen" (func 0)))
/// ```
///
/// Uses GC opcodes (`array.new_default` = 0xFB 0x07, `array.len` = 0xFB 0x0F)
/// and the GC array type form (0x5E). A non-GC engine rejects this at compile.
final _gcModule = Uint8List.fromList([
  0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, // magic + version
  // Type section (id 1)
  0x01, 0x08, 0x02,
  0x5e, 0x78, 0x01, //   type 0: (array (mut i8))
  0x60, 0x00, 0x01, 0x7f, //   type 1: (func (result i32))
  // Function section (id 3): func 0 -> type 1
  0x03, 0x02, 0x01, 0x01,
  // Export section (id 7): "gcLen" = func 0
  0x07, 0x09, 0x01, 0x05, 0x67, 0x63, 0x4c, 0x65, 0x6e, 0x00, 0x00,
  // Code section (id 10)
  0x0a, 0x0b, 0x01, 0x09, 0x00,
  0x41, 0x05, //   i32.const 5
  0xfb, 0x07, 0x00, //   array.new_default 0
  0xfb, 0x0f, //   array.len
  0x0b, //   end
]);

void main() {
  group('WasmGC capability (Chrome)', () {
    test('Chrome validates a WasmGC module', () {
      var valid = _validate(_gcModule.buffer.toJS);
      expect(
        valid,
        isTrue,
        reason: 'Chrome should validate WasmGC bytecode (v119+).',
      );
    });

    test('Chrome instantiates and runs a WasmGC module (array.len == 5)', () async {
      var result = await _instantiate(_gcModule.buffer.toJS).toDart;
      var instance = result.getProperty('instance'.toJS) as JSObject;
      var exports = instance.getProperty('exports'.toJS) as JSObject;
      var gcLen = exports.getProperty('gcLen'.toJS) as JSFunction;

      var r = gcLen.callAsFunction(null) as JSNumber;
      expect(r.toDartInt, equals(5));

      // Host-interop note: this returns a plain i32 (the array length). Reading
      // the GC array's *contents* back into Dart/JS is opaque without exported
      // accessor functions — which is why P2 should marshal aggregate results
      // through an exported linear memory buffer rather than returning GC refs.
    });
  });
}
