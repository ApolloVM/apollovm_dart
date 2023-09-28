// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:typed_data';

import 'package:collection/collection.dart';

/// Base class for code generation output.
abstract class GeneratedOutput<O extends Object, T extends Object> {
  void writeAll(Iterable<T> list) {
    for (var e in list) {
      write(e);
    }
  }

  void write(T o);

  O output();
}

/// Generated Bytes.
/// - [toString] will show bytes description.
class BytesOutput extends GeneratedOutput<Uint8List, List<int>> {
  final String? description;

  BytesOutput({this.description, Object? data}) {
    _addImpl(data);
  }

  //String? get description => _description;

  final List<Object> _data = [];

  void _addImpl(Object? data) {
    if (data == null) return;

    if (data is List<int>) {
      _data.add(data.asUint8List);
    } else if (data is BytesOutput) {
      _data.add(data);
    } else if (data is List<List<int>>) {
      for (var bs in data) {
        _data.addAll(bs.asUint8List);
      }
    } else if (data is List<BytesOutput>) {
      _data.addAll(data);
    } else if (data is int) {
      _data.add(data);
    } else {
      throw StateError("Can't handle data type: ${data.runtimeType}");
    }
  }

  void add(Object? data, {String? description}) {
    if (data == null) return;

    if (data is List<int>) {
      write(data, description: description);
    } else if (data is BytesOutput) {
      writeBytes(data, description: description);
    } else if (data is int) {
      writeByte(data, description: description);
    }
  }

  @override
  void write(List<int> o, {String? description}) {
    if (o.isEmpty) {
      return;
    }

    if (description != null) {
      _data.add(BytesOutput(data: o, description: description));
      return;
    }

    if (o.length == 1) {
      _data.add(o[0]);
    } else {
      _data.add(o.asUint8List);
    }
  }

  void writeByte(int b, {String? description}) {
    if (description != null) {
      _data.add(BytesOutput(data: b, description: description));
      return;
    }

    _data.add(b);
  }

  void writeBytes(BytesOutput bytes, {String? description}) {
    if (description != null) {
      _data.add(BytesOutput(data: bytes, description: description));
      return;
    }

    _data.add(bytes);
  }

  void writeAllBytes(Iterable<BytesOutput> bytes, {String? description}) {
    if (description != null) {
      _data.add(BytesOutput(data: bytes, description: description));
      return;
    }

    for (var bs in bytes) {
      writeBytes(bs);
    }
  }

  void writeBlock(List<List<int>> block, {String? description}) {
    var blockSize = Leb128.encodeUnsigned(block.bytesLength);
    _data.add(BytesOutput(data: blockSize, description: "Bytes block length"));

    if (description != null) {
      _data.add(BytesOutput(data: block, description: description));
    } else {
      writeAll(block);
    }
  }

  void writeBytesBlock(List<BytesOutput> block, {String? description}) {
    var blockSize = Leb128.encodeUnsigned(block.bytesLength);
    _data.add(BytesOutput(data: blockSize, description: "Bytes block length"));

    if (description != null) {
      _data.add(BytesOutput(data: block, description: description));
    } else {
      writeAllBytes(block);
    }
  }

  int get size => _data.map((e) {
        if (e is Uint8List) {
          return e.length;
        } else if (e is BytesOutput) {
          return e.size;
        } else if (e is int) {
          return 1;
        } else {
          throw StateError("Can't handle type: $e");
        }
      }).sum;

  @override
  Uint8List output() {
    final size = this.size;

    var all = Uint8List(size);
    var offset = 0;

    for (var e in _data) {
      Uint8List bs;

      if (e is int) {
        all[offset] = e;
        ++offset;
      } else {
        if (e is BytesOutput) {
          bs = e.output();
        } else if (e is Uint8List) {
          bs = e;
        } else {
          throw StateError("Can't handle type: $e");
        }

        var lng = bs.length;
        all.setRange(offset, offset + lng, bs);

        offset += lng;
      }
    }

    return all;
  }

  /// Show bytes [description] if defined.
  @override
  String toString({String indent = ''}) {
    var s = StringBuffer();

    for (var e in _data) {
      if (e is BytesOutput) {
        s.write(e.toString(indent: '  '));
      } else {
        s.write('$e ');
      }
    }

    var lines = s.toString().split('\n').map((l) => '$indent$l');
    var allLines = lines.join('\n').replaceAll(RegExp(r'(?:[ \t]*\n)+'), '\n');

    final description = this.description;
    if (description != null && description.isNotEmpty) {
      return '$indent## $description:\n$allLines\n';
    } else {
      return '$allLines\n';
    }
  }
}

extension _IterableListIntsExtension on Iterable<List<int>> {
  int get bytesLength => map((e) => e.length).sum;
}

extension _IterableBytesOutputExtension on Iterable<BytesOutput> {
  int get bytesLength => map((e) => e.size).sum;
}

extension _ListIntExtension on List<int> {
  Uint8List get asUint8List {
    final o = this;
    return o is Uint8List ? o : Uint8List.fromList(o);
  }
}

/// LEB128 integer compression.
class Leb128 {
  /// Decodes a LEB128 [bytes] of a signed integer.
  /// - [n] (optional) argument specifies the number of bits in the integer.
  static int decodeUnsigned(Uint8List bytes, {int n = 64}) {
    var result = 0;
    var shift = 0;
    var i = 0;

    while (true) {
      var byte = bytes[i++] & 0xFF;
      result |= (byte & 0x7F) << shift;
      if ((byte & 0x80) == 0) break;
      shift += 7;
    }

    return result;
  }

  /// Decodes a LEB128 [bytes] of a signed integer.
  /// - [n] (optional) argument specifies the number of bits in the integer.
  static int decodeSigned(Uint8List bytes, {int n = 64}) {
    var result = 0;
    var shift = 0;
    var i = 0;

    while (true) {
      var byte = bytes[i];
      result |= ((byte & 0x7F) << shift);
      shift += 7;

      if ((byte & 0x80) == 0) {
        break;
      }

      i += 1;
    }

    if ((shift < n) && (bytes[i] & 0x40) != 0) {
      result |= (~0 << shift);
    }

    return result;
  }

  /// Encodes an [int] into LEB128 unsigned integer.
  static Uint8List encodeUnsigned(int value) {
    var size = (value.toRadixString(2).length / 7.0).ceil();
    var parts = <int>[];
    var i = 0;

    while (i < size) {
      var part = value & 0x7F;
      value >>= 7;
      parts.add(part);

      i += 1;
    }

    for (var i = 0; i < parts.length - 1; i++) {
      parts[i] |= 0x80;
    }

    return Uint8List.fromList(parts);
  }

  /// Encodes an [int] into a LEB128 signed integer.
  static Uint8List encodeSigned(int value) {
    var more = true;
    var parts = <int>[];

    while (more) {
      var byte = value & 0x7F;
      value >>= 7;

      if (value == 0 && (byte & 0x40) == 0) {
        more = false;
      } else if (value == -1 && (byte & 0x40) > 0) {
        more = false;
      } else {
        byte |= 0x80;
      }

      parts.add(byte);
    }

    return Uint8List.fromList(parts);
  }

  /// Decodes a varInt7.
  static decodeVarInt7(int byte) => decodeSigned(Uint8List.fromList([byte]));

  /// Decodes a varUInt7.
  static decodeVarUInt7(int byte) => decodeUnsigned(Uint8List.fromList([byte]));
}