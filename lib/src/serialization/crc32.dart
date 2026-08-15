// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:typed_data';

/// CRC-32 (IEEE 802.3, reflected, polynomial `0xEDB88320`).
///
/// Used by the binary AST format to detect accidental corruption — a truncated
/// write, bit rot, a mangled transfer. It is **not** a security primitive:
/// anyone able to modify a file can recompute its CRC. Tamper-evidence needs a
/// signature made with a key the attacker does not have (`ASTBinarySigner`).
///
/// Every intermediate is masked to 32 bits, so results are identical on the
/// Dart VM and under `dart2js` (where `int` is a JavaScript double).
class Crc32 {
  Crc32._();

  /// The initial CRC accumulator, for use with [update].
  static const int initial = 0xFFFFFFFF;

  static final Uint32List _table = _buildTable();

  static Uint32List _buildTable() {
    var table = Uint32List(256);
    for (var i = 0; i < 256; ++i) {
      var c = i;
      for (var bit = 0; bit < 8; ++bit) {
        // `c` is always < 2^32 here, so `>>` never sees a negative value and
        // the mask keeps the xor result inside 32 bits on the web.
        c = ((c & 1) != 0) ? (0xEDB88320 ^ (c >> 1)) & 0xFFFFFFFF : c >> 1;
      }
      table[i] = c;
    }
    return table;
  }

  /// Folds `[offset, offset+length)` of [bytes] into the running [crc].
  ///
  /// Start from [initial] and finish with [finalize]:
  /// ```dart
  /// var crc = Crc32.initial;
  /// crc = Crc32.update(crc, chunk1);
  /// crc = Crc32.update(crc, chunk2);
  /// var result = Crc32.finalize(crc);
  /// ```
  static int update(int crc, Uint8List bytes, [int offset = 0, int? length]) {
    var end = offset + (length ?? (bytes.length - offset));

    RangeError.checkValidRange(offset, end, bytes.length);

    var table = _table;
    for (var i = offset; i < end; ++i) {
      crc = table[(crc ^ bytes[i]) & 0xFF] ^ (crc >> 8);
    }
    return crc;
  }

  /// Applies the final inversion to a [crc] accumulated with [update].
  static int finalize(int crc) => (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;

  /// The CRC-32 of `[offset, offset+length)` of [bytes].
  static int compute(Uint8List bytes, [int offset = 0, int? length]) =>
      finalize(update(initial, bytes, offset, length));
}
