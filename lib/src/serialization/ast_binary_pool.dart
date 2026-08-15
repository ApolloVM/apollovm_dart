// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:typed_data';

import 'package:data_serializer/data_serializer.dart';

import 'ast_binary_exception.dart';
import 'ast_binary_format.dart';

/// Collects the strings of an AST into a pool, so each distinct string is
/// stored once and every use of it costs a LEB128 index.
///
/// Identifiers repeat pervasively in a parsed program — every variable
/// reference, type name, parameter, field and method name — so this is where
/// most of the size reduction comes from. A string that occurs only once costs
/// the same as writing it inline, since an index and a length prefix are both
/// one LEB128 value.
///
/// Indices are assigned in first-seen order. That is an implementation detail
/// of the writer, not part of the format: a later writer may order the pool by
/// frequency (so the hottest strings get one-byte indices) without any reader
/// change.
class ASTStringPoolWriter {
  final Map<String, int> _indexes = {};
  final List<String> _values = [];

  /// The number of distinct strings interned so far.
  int get length => _values.length;

  /// The index of [s] in the pool, adding it if this is its first occurrence.
  int intern(String s) {
    var i = _indexes[s];
    if (i != null) return i;

    i = _values.length;
    _indexes[s] = i;
    _values.add(s);
    return i;
  }

  /// Encodes the pool as the payload of an [ASTBinarySection.stringTable].
  Uint8List encode() {
    var out = BytesBuffer();
    out.writeLeb128UnsignedInt(_values.length);
    for (var s in _values) {
      out.writeLeb128String(s);
    }
    return out.toBytes();
  }
}

/// The decoded string pool: a positional list that the AST section indexes into.
class ASTStringPoolReader {
  final List<String> _values;

  ASTStringPoolReader(this._values);

  /// The number of strings in the pool.
  int get length => _values.length;

  /// Decodes a pool from an [ASTBinarySection.stringTable] payload.
  factory ASTStringPoolReader.decode(Uint8List payload) {
    var input = BytesBuffer.from(payload);

    int count;
    try {
      count = input.readLeb128UnsignedInt();
    } catch (e) {
      throw ASTBinaryException(
        'Malformed string table: $e',
        ASTBinaryError.malformedSection,
        sectionId: ASTBinarySection.stringTable.id,
      );
    }

    var values = <String>[];
    for (var i = 0; i < count; ++i) {
      if (input.remaining <= 0) {
        throw ASTBinaryException(
          'String table declares $count strings but ran out of bytes at $i.',
          ASTBinaryError.malformedSection,
          offset: input.position,
          sectionId: ASTBinarySection.stringTable.id,
        );
      }
      values.add(input.readLeb128String());
    }

    return ASTStringPoolReader(values);
  }

  /// The string at [index].
  String operator [](int index) {
    if (index < 0 || index >= _values.length) {
      throw ASTBinaryException(
        'String pool index $index is out of range (0..${_values.length - 1}). '
        'The file is corrupted or was written by an incompatible encoder.',
        ASTBinaryError.malformedSection,
        sectionId: ASTBinarySection.stringTable.id,
      );
    }
    return _values[index];
  }
}
