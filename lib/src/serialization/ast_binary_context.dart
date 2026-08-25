// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:typed_data';

import 'package:data_serializer/data_serializer.dart';

import '../ast/apollovm_ast_annotation.dart';
import '../ast/apollovm_ast_base.dart';
import '../ast/apollovm_ast_type.dart';
import 'ast_binary_exception.dart';
import 'ast_binary_format.dart';
import 'ast_binary_pool.dart';
import 'ast_binary_registry.dart';
import 'ast_binary_type_pool.dart';

/// The largest integer that survives a round trip through a JavaScript double,
/// which is what a Dart `int` compiles to under `dart2js`.
const int _maxSafeInteger = 9007199254740991; // 2^53 - 1

/// Tags for the plain-Dart values an [ASTValueStatic] can hold.
class ASTNativeValueTag {
  ASTNativeValueTag._();

  static const int nullValue = 0x00;
  static const int falseValue = 0x01;
  static const int trueValue = 0x02;
  static const int intValue = 0x03;
  static const int doubleValue = 0x04;
  static const int stringValue = 0x05;
  static const int listValue = 0x06;
  static const int mapValue = 0x07;

  /// A nested AST node, which some values carry in place of plain data.
  static const int nodeValue = 0x08;
}

/// How an integer is stored.
///
/// Signed values are written as a form byte plus an **unsigned** LEB128
/// magnitude, rather than as signed LEB128. That is deliberate:
/// `BytesBuffer.readLeb128SignedInt` in `data_serializer` 1.2.2 does not
/// sign-extend correctly — it records the byte *before* the terminating one, so
/// `-2` reads back as `126` and `64` as `-16320`. Splitting the sign out uses
/// only the unsigned path, which is correct, and sidesteps sign-extension
/// differences between the VM and `dart2js` at the same time.
class ASTIntEncoding {
  ASTIntEncoding._();

  /// A non-negative value, as an unsigned LEB128.
  static const int positive = 0x00;

  /// A decimal string, for magnitudes a JavaScript double cannot hold exactly.
  ///
  /// A writer running under `dart2js` can never produce this form, because it
  /// could not have held such a value in the first place.
  static const int bigDecimal = 0x01;

  /// A negative value, as an unsigned LEB128 of its magnitude.
  static const int negative = 0x02;
}

/// Accumulates the AST section, interning strings and types as it goes.
///
/// Codecs are handed one of these and use its typed helpers rather than
/// touching the byte buffer, so the encoding of a field kind is defined once.
class ASTBinaryWriteContext {
  /// The AST section being built.
  final BytesBuffer out = BytesBuffer();

  /// The shared string pool.
  final ASTStringPoolWriter strings;

  /// The shared type pool.
  final ASTTypePoolWriter types;

  final List<String> _path = [];

  ASTBinaryWriteContext(this.strings, this.types);

  /// Where the writer currently is, e.g. `ASTRoot > class Foo > bar`.
  ///
  /// Used to say *where* an unserializable node was found, which matters
  /// because the usual cause is a VM with external functions mapped into it.
  String get declarationPath => _path.isEmpty ? '' : _path.join(' > ');

  /// Runs [body] with [name] appended to [declarationPath].
  T inDeclaration<T>(String name, T Function() body) {
    _path.add(name);
    try {
      return body();
    } finally {
      _path.removeLast();
    }
  }

  /// The finished AST section payload.
  Uint8List toBytes() => out.toBytes();

  /// Writes a node: its tag, then its fields.
  void node(Object node) {
    var codec = ASTCodecRegistry.codecFor(node, declarationPath);
    out.writeLeb128UnsignedInt(codec.tag);
    codec.encodeAny(this, node);
  }

  /// Writes a node, or a single zero byte when it is `null`.
  void nodeOrNull(Object? node) {
    if (node == null) {
      out.writeLeb128UnsignedInt(ASTCodecRegistry.nullTag);
      return;
    }
    this.node(node);
  }

  /// Writes a list of nodes, distinguishing a null list from an empty one.
  void nodes(List<Object>? list) {
    if (list == null) {
      out.writeLeb128UnsignedInt(0);
      return;
    }
    // `n + 1`, so 0 can mean "the list itself was null". The generators treat
    // a missing list and an empty one differently, so the distinction matters.
    out.writeLeb128UnsignedInt(list.length + 1);
    for (var e in list) {
      node(e);
    }
  }

  /// Writes an interned string.
  void str(String s) => out.writeLeb128UnsignedInt(strings.intern(s));

  /// Writes an interned string, or a marker when it is `null`.
  void strOrNull(String? s) =>
      out.writeLeb128UnsignedInt(s == null ? 0 : strings.intern(s) + 1);

  /// Writes a list of interned strings, distinguishing null from empty.
  void strings_(List<String>? list) {
    if (list == null) {
      out.writeLeb128UnsignedInt(0);
      return;
    }
    out.writeLeb128UnsignedInt(list.length + 1);
    for (var s in list) {
      str(s);
    }
  }

  /// Writes an interned type reference.
  void type(ASTType t) => out.writeLeb128UnsignedInt(types.intern(t));

  /// Writes an interned type reference, or a marker when it is `null`.
  void typeOrNull(ASTType? t) =>
      out.writeLeb128UnsignedInt(t == null ? 0 : types.intern(t) + 1);

  /// Writes a list of interned type references, distinguishing null from empty.
  void typeList(List<ASTType>? list) {
    if (list == null) {
      out.writeLeb128UnsignedInt(0);
      return;
    }
    out.writeLeb128UnsignedInt(list.length + 1);
    for (var t in list) {
      type(t);
    }
  }

  /// Writes a non-negative integer.
  void uint(int v) => out.writeLeb128UnsignedInt(v);

  /// Writes a possibly-negative integer, as a sign byte plus a magnitude.
  void sint(int v) {
    out.writeByte(v < 0 ? ASTIntEncoding.negative : ASTIntEncoding.positive);
    out.writeLeb128UnsignedInt(v < 0 ? -v : v);
  }

  /// Writes a nullable non-negative integer.
  void uintOrNull(int? v) => out.writeLeb128UnsignedInt(v == null ? 0 : v + 1);

  /// Writes a boolean as one byte.
  void boolean(bool v) => out.writeBoolean(v);

  /// Writes a byte, for small bitfields and discriminators.
  void byte(int v) => out.writeByte(v);

  /// Writes a `double` as IEEE-754 binary64.
  void float64(double v) => out.writeFloat64(v);

  /// Writes an enum by **name**.
  ///
  /// By name rather than by index deliberately: an index silently mis-decodes
  /// every older file the moment someone inserts a member into the middle of an
  /// enum, and `ASTExpressionOperator` is exactly the sort of enum that grows.
  /// With the string pool the cost is one byte per occurrence, so index
  /// encoding would save essentially nothing.
  ///
  /// Note this is *not* `BytesBuffer.writeEnum`, which writes the index.
  void enumByName(Enum e) => str(e.name);

  /// Writes an integer literal from source, in a form that is exact on the web.
  ///
  /// Dart `int` is a JavaScript double under `dart2js`, so a value beyond 2^53
  /// cannot be held there at all. Such a value is stored as a decimal string so
  /// a VM-written file stays readable, and a `dart2js` reader that meets one
  /// fails with a clear message rather than silently rounding it.
  void literalInt(int v) {
    if (v >= -_maxSafeInteger && v <= _maxSafeInteger) {
      out.writeByte(v < 0 ? ASTIntEncoding.negative : ASTIntEncoding.positive);
      out.writeLeb128UnsignedInt(v < 0 ? -v : v);
    } else {
      out.writeByte(ASTIntEncoding.bigDecimal);
      str(v.toString());
    }
  }

  /// Writes an [ASTModifiers] as a single bitfield byte.
  void modifiers(ASTModifiers m) {
    var bits = 0;
    if (m.isStatic) bits |= 0x01;
    if (m.isFinal) bits |= 0x02;
    if (m.isPrivate) bits |= 0x04;
    if (m.isPublic) bits |= 0x08;
    if (m.isAsync) bits |= 0x10;
    if (m.isAbstract) bits |= 0x20;
    if (m.isProtected) bits |= 0x40;
    out.writeByte(bits);
  }

  /// Writes a plain Dart value held by an [ASTValueStatic].
  ///
  /// Only data a parser could have produced is representable: `null`,
  /// booleans, numbers, strings, and lists and maps of those, plus a nested AST
  /// node. Anything else is a live Dart object that found its way into the tree
  /// at run time, and is refused by name rather than silently dropped — this is
  /// the guard that stops a VM object being written into a file.
  void nativeValue(Object? v) {
    switch (v) {
      case null:
        out.writeByte(ASTNativeValueTag.nullValue);
      case bool b:
        out.writeByte(
          b ? ASTNativeValueTag.trueValue : ASTNativeValueTag.falseValue,
        );
      case int i:
        out.writeByte(ASTNativeValueTag.intValue);
        literalInt(i);
      case double d:
        out.writeByte(ASTNativeValueTag.doubleValue);
        float64(d);
      case String s:
        out.writeByte(ASTNativeValueTag.stringValue);
        str(s);
      case List l:
        out.writeByte(ASTNativeValueTag.listValue);
        uint(l.length);
        for (var e in l) {
          nativeValue(e);
        }
      case Map m:
        out.writeByte(ASTNativeValueTag.mapValue);
        uint(m.length);
        for (var e in m.entries) {
          nativeValue(e.key);
          nativeValue(e.value);
        }
      case ASTNode n:
        out.writeByte(ASTNativeValueTag.nodeValue);
        node(n);
      default:
        throw ASTNotSerializableException(
          v,
          'a value of this type is live Dart state, not something a parser '
          'produces',
          declarationPath: declarationPath.isEmpty ? null : declarationPath,
        );
    }
  }

  /// Writes an annotation list, distinguishing null from empty.
  void annotations(List<ASTAnnotation>? list) {
    if (list == null) {
      out.writeLeb128UnsignedInt(0);
      return;
    }
    out.writeLeb128UnsignedInt(list.length + 1);
    for (var a in list) {
      writeAnnotation(out, strings, a);
    }
  }
}

/// Reads the AST section, resolving pool references as it goes.
///
/// Mirrors [ASTBinaryWriteContext] method for method; a codec's `decode` reads
/// exactly the fields its `encode` wrote, in the same order.
class ASTBinaryReadContext {
  /// The AST section being read.
  final BytesBuffer input;

  /// The decoded string pool.
  final ASTStringPoolReader strings;

  /// The decoded type pool.
  final ASTTypePoolReader types;

  /// The container revision that wrote the file.
  ///
  /// Codecs gate fields added in a later revision on this, which is how a
  /// reader keeps decoding files written before those fields existed.
  final int formatVersion;

  ASTBinaryReadContext(
    this.input,
    this.strings,
    this.types, {
    required this.formatVersion,
  });

  /// Reads a node and checks it is a [T].
  T node<T extends Object>() {
    var n = _readNode();
    if (n == null) {
      throw ASTBinaryException(
        'Expected a $T but found a null node marker.',
        ASTBinaryError.malformedSection,
        offset: input.position,
        sectionId: ASTBinarySection.astRoot.id,
      );
    }
    return _cast<T>(n);
  }

  /// Reads a node that may be absent.
  T? nodeOrNull<T extends Object>() {
    var n = _readNode();
    return n == null ? null : _cast<T>(n);
  }

  /// Reads a node list, distinguishing a null list from an empty one.
  List<T>? nodes<T extends Object>() {
    var n = input.readLeb128UnsignedInt();
    if (n == 0) return null;
    return [for (var i = 1; i < n; ++i) node<T>()];
  }

  /// Reads a node list that the writer never stores as null.
  List<T> nodeList<T extends Object>() => nodes<T>() ?? <T>[];

  Object? _readNode() {
    var tag = input.readLeb128UnsignedInt();
    if (tag == ASTCodecRegistry.nullTag) return null;

    var codec = ASTCodecRegistry.byTag(tag);
    if (codec == null) {
      // An unknown *section* is skipped, but an unknown node tag never can be:
      // there is no length prefix to skip past, and guessing would produce a
      // wrong AST rather than an incomplete one.
      throw ASTBinaryException(
        'Unknown AST node tag $tag at offset ${input.position}. The file was '
        'written by a newer ApolloVM than this one can decode.',
        ASTBinaryError.unsupportedNode,
        offset: input.position,
        formatVersion: formatVersion,
        sectionId: ASTBinarySection.astRoot.id,
      );
    }

    return codec.decode(this);
  }

  T _cast<T extends Object>(Object n) {
    if (n is! T) {
      throw ASTBinaryException(
        'Expected a $T but decoded a ${n.runtimeType}.',
        ASTBinaryError.malformedSection,
        offset: input.position,
        sectionId: ASTBinarySection.astRoot.id,
      );
    }
    return n;
  }

  /// Reads an interned string.
  String str() => strings[input.readLeb128UnsignedInt()];

  /// Reads an interned string that may be absent.
  String? strOrNull() {
    var i = input.readLeb128UnsignedInt();
    return i == 0 ? null : strings[i - 1];
  }

  /// Reads a string list, distinguishing null from empty.
  List<String>? strings_() {
    var n = input.readLeb128UnsignedInt();
    if (n == 0) return null;
    return [for (var i = 1; i < n; ++i) str()];
  }

  /// Reads an interned type reference.
  ASTType type() => types[input.readLeb128UnsignedInt()];

  /// Reads an interned type reference that may be absent.
  ASTType? typeOrNull() {
    var i = input.readLeb128UnsignedInt();
    return i == 0 ? null : types[i - 1];
  }

  /// Reads a type list, distinguishing null from empty.
  List<ASTType>? typeList() {
    var n = input.readLeb128UnsignedInt();
    if (n == 0) return null;
    return [for (var i = 1; i < n; ++i) type()];
  }

  /// Reads a non-negative integer.
  int uint() => input.readLeb128UnsignedInt();

  /// Reads a possibly-negative integer.
  int sint() {
    var sign = input.readByte();
    var magnitude = input.readLeb128UnsignedInt();
    return sign == ASTIntEncoding.negative ? -magnitude : magnitude;
  }

  /// Reads a nullable non-negative integer.
  int? uintOrNull() {
    var v = input.readLeb128UnsignedInt();
    return v == 0 ? null : v - 1;
  }

  /// Reads a boolean.
  bool boolean() => input.readBoolean();

  /// Reads a byte.
  int byte() => input.readByte();

  /// Reads a `double`.
  double float64() => input.readFloat64();

  /// Reads an enum written by [ASTBinaryWriteContext.enumByName].
  E enumByName<E extends Enum>(List<E> values) {
    var name = str();
    for (var v in values) {
      if (v.name == name) return v;
    }
    throw ASTBinaryException(
      "Unknown $E value '$name'. The file was written by a newer ApolloVM, or "
      'is corrupted.',
      ASTBinaryError.unsupportedNode,
      offset: input.position,
      formatVersion: formatVersion,
      sectionId: ASTBinarySection.astRoot.id,
    );
  }

  /// Reads an integer literal written by [ASTBinaryWriteContext.literalInt].
  int literalInt() {
    var form = input.readByte();
    switch (form) {
      case ASTIntEncoding.positive:
        return input.readLeb128UnsignedInt();
      case ASTIntEncoding.negative:
        return -input.readLeb128UnsignedInt();
      case ASTIntEncoding.bigDecimal:
        var text = str();
        var v = int.tryParse(text);
        if (v == null || v.toString() != text) {
          // Reachable only on the web, where an `int` is a double: the value
          // exists in the file but cannot be represented here. Say so, rather
          // than silently handing back a rounded number.
          throw ASTBinaryException(
            "Integer literal '$text' cannot be represented exactly on this "
            'platform (JavaScript integers are exact only up to 2^53-1).',
            ASTBinaryError.unsupportedNode,
            offset: input.position,
            sectionId: ASTBinarySection.astRoot.id,
          );
        }
        return v;
      default:
        throw ASTBinaryException(
          'Unknown integer encoding 0x${form.toRadixString(16)}.',
          ASTBinaryError.unsupportedNode,
          offset: input.position,
          sectionId: ASTBinarySection.astRoot.id,
        );
    }
  }

  /// Reads an [ASTModifiers] bitfield.
  ASTModifiers modifiers() {
    var bits = input.readByte();

    // `ASTModifiers` refuses to be both private and public, and a corrupted
    // byte can ask for exactly that. Report it as a malformed file rather than
    // letting a bare `StateError` escape the reader.
    if ((bits & 0x04) != 0 && (bits & 0x08) != 0) {
      throw ASTBinaryException(
        'Modifiers byte 0x${bits.toRadixString(16)} is both private and '
        'public.',
        ASTBinaryError.malformedSection,
        offset: input.position,
        sectionId: ASTBinarySection.astRoot.id,
      );
    }

    return ASTModifiers(
      isStatic: (bits & 0x01) != 0,
      isFinal: (bits & 0x02) != 0,
      isPrivate: (bits & 0x04) != 0,
      isPublic: (bits & 0x08) != 0,
      isAsync: (bits & 0x10) != 0,
      isAbstract: (bits & 0x20) != 0,
      isProtected: (bits & 0x40) != 0,
    );
  }

  /// Reads a value written by [ASTBinaryWriteContext.nativeValue].
  Object? nativeValue() {
    var tag = input.readByte();
    switch (tag) {
      case ASTNativeValueTag.nullValue:
        return null;
      case ASTNativeValueTag.falseValue:
        return false;
      case ASTNativeValueTag.trueValue:
        return true;
      case ASTNativeValueTag.intValue:
        return literalInt();
      case ASTNativeValueTag.doubleValue:
        return float64();
      case ASTNativeValueTag.stringValue:
        return str();
      case ASTNativeValueTag.listValue:
        var n = uint();
        return [for (var i = 0; i < n; ++i) nativeValue()];
      case ASTNativeValueTag.mapValue:
        var n = uint();
        var m = <Object?, Object?>{};
        for (var i = 0; i < n; ++i) {
          var k = nativeValue();
          m[k] = nativeValue();
        }
        return m;
      case ASTNativeValueTag.nodeValue:
        return node<Object>();
      default:
        throw ASTBinaryException(
          'Unknown native value tag 0x${tag.toRadixString(16)}.',
          ASTBinaryError.unsupportedNode,
          offset: input.position,
          sectionId: ASTBinarySection.astRoot.id,
        );
    }
  }

  /// Reads an annotation list, distinguishing null from empty.
  List<ASTAnnotation>? annotations() {
    var n = input.readLeb128UnsignedInt();
    if (n == 0) return null;
    return [for (var i = 1; i < n; ++i) readAnnotation(input, strings)];
  }
}
