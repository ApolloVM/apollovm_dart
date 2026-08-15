// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:typed_data';

import 'package:data_serializer/data_serializer.dart';

import '../ast/apollovm_ast_annotation.dart';
import '../ast/apollovm_ast_type.dart';
import 'ast_binary_exception.dart';
import 'ast_binary_format.dart';
import 'ast_binary_pool.dart';

/// Writes an [ASTAnnotation] — its name and its parameters — using [strings].
///
/// Annotations hang off both types and declarations, so the encoding lives here
/// rather than being duplicated by each caller.
void writeAnnotation(
  BytesBuffer out,
  ASTStringPoolWriter strings,
  ASTAnnotation a,
) {
  out.writeLeb128UnsignedInt(strings.intern(a.name));

  var parameters = a.parameters;
  if (parameters == null) {
    out.writeLeb128UnsignedInt(0);
    return;
  }

  out.writeLeb128UnsignedInt(parameters.length + 1);
  for (var e in parameters.entries) {
    out.writeLeb128UnsignedInt(strings.intern(e.key));
    out.writeLeb128UnsignedInt(strings.intern(e.value.name));
    out.writeLeb128UnsignedInt(strings.intern(e.value.value));
    out.writeBoolean(e.value.defaultParameter);
  }
}

/// Reads an [ASTAnnotation] written by [writeAnnotation].
ASTAnnotation readAnnotation(BytesBuffer input, ASTStringPoolReader strings) {
  var name = strings[input.readLeb128UnsignedInt()];

  var count = input.readLeb128UnsignedInt();
  if (count == 0) return ASTAnnotation(name);

  var parameters = <String, ASTAnnotationParameter>{};
  for (var i = 1; i < count; ++i) {
    var key = strings[input.readLeb128UnsignedInt()];
    var pName = strings[input.readLeb128UnsignedInt()];
    var pValue = strings[input.readLeb128UnsignedInt()];
    var isDefault = input.readBoolean();
    parameters[key] = ASTAnnotationParameter(pName, pValue, isDefault);
  }

  return ASTAnnotation(name, parameters);
}

/// How a pooled [ASTType] entry is shaped.
///
/// Values are part of the wire format: never renumbered, never reused.
class ASTTypeEntryKind {
  ASTTypeEntryKind._();

  /// One of the interned [ASTType] singletons, by [ASTWellKnownType] id.
  static const int wellKnown = 0x01;

  /// A plain [ASTType]: name, generics, super type, annotations.
  static const int generic = 0x02;

  /// An [ASTTypeInterface].
  static const int interface = 0x03;

  /// An [ASTTypeArray], by component type.
  static const int array1D = 0x04;

  /// An [ASTTypeArray2D], by element type.
  static const int array2D = 0x05;

  /// An [ASTTypeArray3D], by element type.
  static const int array3D = 0x06;

  /// An [ASTTypeMap], by key and value type.
  static const int map = 0x07;

  /// An [ASTTypeFuture], by its value type.
  static const int future = 0x08;

  /// An [ASTTypeFunction], by return type and parameter types.
  static const int function = 0x09;

  /// An [ASTTypeNum] carrying an optional bit width.
  static const int num = 0x0A;

  /// An [ASTTypeInt] carrying an optional bit width.
  static const int int_ = 0x0B;

  /// An [ASTTypeDouble] carrying an optional bit width.
  static const int double_ = 0x0C;

  /// An [ASTTypeVar], carrying its `unmodifiable` flag.
  static const int var_ = 0x0D;

  /// An [ASTTypeGenericVariable], by variable name and optional bound.
  static const int genericVariable = 0x0E;

  /// An [ASTTypeBool].
  static const int bool_ = 0x0F;

  /// An [ASTTypeString].
  static const int string = 0x10;

  /// An [ASTTypeObject].
  static const int object = 0x11;

  /// An [ASTTypeDynamic].
  static const int dynamic_ = 0x12;

  /// An [ASTTypeNull].
  static const int null_ = 0x13;

  /// An [ASTTypeVoid].
  static const int void_ = 0x14;

  /// An [ASTTypeConstructorThis].
  static const int constructorThis = 0x15;

  /// An [ASTTypeGenericWildcard].
  static const int genericWildcard = 0x16;
}

/// Identifiers for the [ASTType] singletons that must decode back to the very
/// same object.
///
/// Identity matters here, it is not an optimization:
/// `ASTConstructorParameterDeclaration.resolveNode` compares its parameter type
/// with `identical(type, ASTTypeConstructorThis.instance)`, so a structurally
/// equal but distinct instance would silently change how `this.field`
/// constructor parameters resolve.
class ASTWellKnownType {
  ASTWellKnownType._();

  static const int typeInt = 0x01;
  static const int typeInt32 = 0x02;
  static const int typeInt64 = 0x03;
  static const int typeDouble = 0x04;
  static const int typeDouble32 = 0x05;
  static const int typeDouble64 = 0x06;
  static const int typeNum = 0x07;
  static const int typeBool = 0x08;
  static const int typeString = 0x09;
  static const int typeObject = 0x0A;
  static const int typeDynamic = 0x0B;
  static const int typeNull = 0x0C;
  static const int typeVoid = 0x0D;
  static const int typeVar = 0x0E;
  static const int typeVarUnmodifiable = 0x0F;
  static const int typeConstructorThis = 0x10;
  static const int typeGenericWildcard = 0x11;
  static const int arrayOfString = 0x12;
  static const int arrayOfInt = 0x13;
  static const int arrayOfDouble = 0x14;
  static const int arrayOfBool = 0x15;
  static const int arrayOfObject = 0x16;
  static const int arrayOfDynamic = 0x17;
  static const int mapOfStringDynamic = 0x18;
  static const int mapOfStringString = 0x19;
  static const int mapOfDynamicDynamic = 0x1A;

  /// The singleton for [id], or `null` when [id] is not a well-known type.
  static ASTType? instanceOf(int id) => switch (id) {
    typeInt => ASTTypeInt.instance,
    typeInt32 => ASTTypeInt.instance32,
    typeInt64 => ASTTypeInt.instance64,
    typeDouble => ASTTypeDouble.instance,
    typeDouble32 => ASTTypeDouble.instance32,
    typeDouble64 => ASTTypeDouble.instance64,
    typeNum => ASTTypeNum.instance,
    typeBool => ASTTypeBool.instance,
    typeString => ASTTypeString.instance,
    typeObject => ASTTypeObject.instance,
    typeDynamic => ASTTypeDynamic.instance,
    typeNull => ASTTypeNull.instance,
    typeVoid => ASTTypeVoid.instance,
    typeVar => ASTTypeVar.instance,
    typeVarUnmodifiable => ASTTypeVar.instanceUnmodifiable,
    typeConstructorThis => ASTTypeConstructorThis.instance,
    typeGenericWildcard => ASTTypeGenericWildcard.instance,
    arrayOfString => ASTTypeArray.instanceOfString,
    arrayOfInt => ASTTypeArray.instanceOfInt,
    arrayOfDouble => ASTTypeArray.instanceOfDouble,
    arrayOfBool => ASTTypeArray.instanceOfBool,
    arrayOfObject => ASTTypeArray.instanceOfObject,
    arrayOfDynamic => ASTTypeArray.instanceOfDynamic,
    mapOfStringDynamic => ASTTypeMap.instanceOfStringOfDynamic,
    mapOfStringString => ASTTypeMap.instanceOfStringOfString,
    mapOfDynamicDynamic => ASTTypeMap.instanceOfDynamicOfDynamic,
    _ => null,
  };

  static final Map<ASTType, int> _idsByInstance = _buildIds();

  static Map<ASTType, int> _buildIds() {
    // Keyed on identity: `ASTType` overrides `==` structurally, and several
    // singletons are structurally equal to each other (`ASTTypeVar.instance`
    // and `ASTTypeVar.instanceUnmodifiable` share a name), so a plain map would
    // collapse them.
    var map = Map<ASTType, int>.identity();
    for (var id = 0x01; id <= 0x1A; ++id) {
      var instance = instanceOf(id);
      if (instance != null) map[instance] = id;
    }
    return map;
  }

  /// The well-known id for [type] when it *is* one of the singletons, or `null`
  /// for any other instance. Compares by identity, never structurally.
  static int? idOf(ASTType type) => _idsByInstance[type];
}

/// Interns the [ASTType]s of an AST so each distinct type is written once.
///
/// Types are the most repeated node in a parsed program — every parameter,
/// variable, field and return type carries one — so pooling them turns each
/// occurrence into a single LEB128 index.
///
/// Sharing a decoded type across use sites is safe: apart from `nullable`,
/// which is part of the pool key, an [ASTType] is immutable, and the one piece
/// of mutable state it has ([ASTType.setClass]) is only ever written by an
/// [ASTClass] constructor — which is given a freshly built type rather than a
/// pooled one.
class ASTTypePoolWriter {
  final ASTStringPoolWriter _strings;

  /// Entry payloads in intern order. A type's components are always interned
  /// before it, so decoding front-to-back never needs a forward reference.
  final List<Uint8List> _entries = [];

  final Map<ASTType, int> _byIdentity = Map<ASTType, int>.identity();
  final Map<String, int> _byKey = {};

  ASTTypePoolWriter(this._strings);

  /// The number of distinct types interned so far.
  int get length => _entries.length;

  /// The pool index of [type], adding it if this is its first occurrence.
  int intern(ASTType type) {
    var known = _byIdentity[type];
    if (known != null) return known;

    var key = _keyOf(type);
    known = _byKey[key];
    if (known != null) {
      _byIdentity[type] = known;
      return known;
    }

    // Reserve nothing: components are interned first (inside `_encode`), so the
    // index this entry gets is always greater than every index it references.
    var payload = _encode(type);

    var index = _entries.length;
    _entries.add(payload);
    _byIdentity[type] = index;
    _byKey[key] = index;
    return index;
  }

  /// A structural identity for [type], used to collapse equal types.
  ///
  /// It includes the concrete class, because two types with the same name can
  /// be different classes, and `nullable`, because a nullable type is a
  /// distinct object that must not be shared with its non-nullable form.
  String _keyOf(ASTType type) {
    var wellKnown = ASTWellKnownType.idOf(type);
    if (wellKnown != null) return 'w$wellKnown';

    var b = StringBuffer()
      ..write(type.runtimeType)
      ..write('|')
      ..write(type.name)
      ..write('|')
      ..write(type.nullable ? '?' : '');

    switch (type) {
      case ASTTypeArray3D():
      case ASTTypeArray2D():
      case ASTTypeArray():
        b.write('|c:${intern((type as ASTTypeArray).componentType)}');
      case ASTTypeMap():
        b.write('|k:${intern(type.keyType)}|v:${intern(type.valueType)}');
      case ASTTypeNum():
        b.write('|b:${type.bits}');
      case ASTTypeVar():
        b.write('|u:${type.unmodifiable}');
      case ASTTypeGenericVariable():
        var bound = type.type;
        b.write(
          '|g:${type.variableName}|t:${bound == null ? '-' : intern(bound)}',
        );
      default:
        for (var g in type.generics ?? const <ASTType>[]) {
          b.write('|g:${intern(g)}');
        }
        var s = type.superType;
        if (s != null) b.write('|s:${intern(s)}');
        for (var a in type.annotations ?? const <ASTAnnotation>[]) {
          b.write('|a:${a.name}(');
          var parameters = a.parameters;
          if (parameters != null) {
            for (var p in parameters.entries) {
              b.write('${p.key}=${p.value.name}:${p.value.value},');
            }
          }
          b.write(')');
        }
    }

    return b.toString();
  }

  Uint8List _encode(ASTType type) {
    var out = BytesBuffer();

    var wellKnown = ASTWellKnownType.idOf(type);
    if (wellKnown != null) {
      out.writeByte(ASTTypeEntryKind.wellKnown);
      out.writeByte(wellKnown);
      return out.toBytes();
    }

    switch (type) {
      // 3D before 2D before 1D: they form an inheritance chain, so the most
      // derived must be tested first.
      case ASTTypeArray3D():
        out.writeByte(ASTTypeEntryKind.array3D);
        _writeArrayElement(out, type, 3);
      case ASTTypeArray2D():
        out.writeByte(ASTTypeEntryKind.array2D);
        _writeArrayElement(out, type, 2);
      case ASTTypeArray():
        out.writeByte(ASTTypeEntryKind.array1D);
        out.writeLeb128UnsignedInt(intern(type.componentType));
      case ASTTypeMap():
        out.writeByte(ASTTypeEntryKind.map);
        out.writeLeb128UnsignedInt(intern(type.keyType));
        out.writeLeb128UnsignedInt(intern(type.valueType));
      case ASTTypeFuture():
        out.writeByte(ASTTypeEntryKind.future);
        out.writeLeb128UnsignedInt(intern(type.futureValueType));
      case ASTTypeFunction():
        // A function type keeps its whole signature in `generics`: the return
        // type first, then the parameters. Encode that list verbatim and
        // rebuild with the same split `ASTTypeFunction.cloneType` uses, so no
        // separate return/parameter accessors are needed.
        out.writeByte(ASTTypeEntryKind.function);
        _writeTypeList(out, type.generics);
      case ASTTypeInt():
        out.writeByte(ASTTypeEntryKind.int_);
        _writeIntOrNull(out, type.bits);
      case ASTTypeDouble():
        out.writeByte(ASTTypeEntryKind.double_);
        _writeIntOrNull(out, type.bits);
      case ASTTypeNum():
        out.writeByte(ASTTypeEntryKind.num);
        _writeIntOrNull(out, type.bits);
      case ASTTypeVar():
        out.writeByte(ASTTypeEntryKind.var_);
        out.writeBoolean(type.unmodifiable);
      case ASTTypeGenericWildcard():
        out.writeByte(ASTTypeEntryKind.genericWildcard);
      case ASTTypeGenericVariable():
        out.writeByte(ASTTypeEntryKind.genericVariable);
        out.writeLeb128UnsignedInt(_strings.intern(type.variableName));
        _writeTypeRefOrNull(out, type.type);
      case ASTTypeBool():
        out.writeByte(ASTTypeEntryKind.bool_);
      case ASTTypeString():
        out.writeByte(ASTTypeEntryKind.string);
      case ASTTypeObject():
        out.writeByte(ASTTypeEntryKind.object);
      case ASTTypeDynamic():
        out.writeByte(ASTTypeEntryKind.dynamic_);
      case ASTTypeNull():
        out.writeByte(ASTTypeEntryKind.null_);
      case ASTTypeVoid():
        out.writeByte(ASTTypeEntryKind.void_);
      case ASTTypeConstructorThis():
        out.writeByte(ASTTypeEntryKind.constructorThis);
      case ASTTypeInterface():
        out.writeByte(ASTTypeEntryKind.interface);
        _writeGenericBody(out, type);
      default:
        out.writeByte(ASTTypeEntryKind.generic);
        _writeGenericBody(out, type);
    }

    out.writeBoolean(type.nullable);
    return out.toBytes();
  }

  void _writeArrayElement(BytesBuffer out, ASTTypeArray type, int rank) {
    // 2D and 3D arrays are built from an *element* type, not from their
    // immediate component type: `ASTTypeArray2D.fromElementType(e)` wraps `e`
    // twice. Unwrap back to the element so decoding can use the same factory
    // the grammars use.
    ASTType t = type;
    for (var i = 0; i < rank; ++i) {
      t = (t as ASTTypeArray).componentType;
    }
    out.writeLeb128UnsignedInt(intern(t));
  }

  void _writeGenericBody(BytesBuffer out, ASTType type) {
    out.writeLeb128UnsignedInt(_strings.intern(type.name));
    _writeTypeList(out, type.generics);
    _writeTypeRefOrNull(out, type.superType);

    var annotations = type.annotations;
    if (annotations == null) {
      out.writeLeb128UnsignedInt(0);
    } else {
      out.writeLeb128UnsignedInt(annotations.length + 1);
      for (var a in annotations) {
        writeAnnotation(out, _strings, a);
      }
    }
  }

  void _writeTypeList(BytesBuffer out, List<ASTType>? types) {
    if (types == null) {
      out.writeLeb128UnsignedInt(0);
      return;
    }
    // `n + 1`, so 0 can mean "the list itself is null" — a distinction the
    // generators rely on (a raw `List` is not a `List<>` with no arguments).
    out.writeLeb128UnsignedInt(types.length + 1);
    for (var t in types) {
      out.writeLeb128UnsignedInt(intern(t));
    }
  }

  void _writeTypeRefOrNull(BytesBuffer out, ASTType? type) {
    out.writeLeb128UnsignedInt(type == null ? 0 : intern(type) + 1);
  }

  void _writeIntOrNull(BytesBuffer out, int? v) {
    out.writeLeb128UnsignedInt(v == null ? 0 : v + 1);
  }

  /// Encodes the pool as the payload of an [ASTBinarySection.typeTable].
  Uint8List encode() {
    var out = BytesBuffer();
    out.writeLeb128UnsignedInt(_entries.length);
    for (var e in _entries) {
      out.writeLeb128UnsignedInt(e.length);
      out.writeAllBytes(e);
    }
    return out.toBytes();
  }
}

/// The decoded type pool: a positional list of [ASTType]s that the AST section
/// indexes into.
class ASTTypePoolReader {
  final List<ASTType> _values;

  ASTTypePoolReader(this._values);

  /// The number of types in the pool.
  int get length => _values.length;

  /// Decodes a pool from an [ASTBinarySection.typeTable] payload.
  ///
  /// Entries are decoded front to back; because the writer interns a type's
  /// components before the type itself, every reference points backwards and
  /// resolves immediately.
  factory ASTTypePoolReader.decode(
    Uint8List payload,
    ASTStringPoolReader strings,
  ) {
    var input = BytesBuffer.from(payload);
    var values = <ASTType>[];

    int count;
    try {
      count = input.readLeb128UnsignedInt();
    } catch (e) {
      throw ASTBinaryException(
        'Malformed type table: $e',
        ASTBinaryError.malformedSection,
        sectionId: ASTBinarySection.typeTable.id,
      );
    }

    for (var i = 0; i < count; ++i) {
      var size = input.readLeb128UnsignedInt();
      if (size > input.remaining) {
        throw ASTBinaryException(
          'Type table entry $i declares $size bytes but only '
          '${input.remaining} remain.',
          ASTBinaryError.malformedSection,
          offset: input.position,
          sectionId: ASTBinarySection.typeTable.id,
        );
      }
      var entry = input.readBytes(size);
      values.add(_decodeEntry(entry, strings, values, i));
    }

    return ASTTypePoolReader(values);
  }

  static ASTType _decodeEntry(
    Uint8List entry,
    ASTStringPoolReader strings,
    List<ASTType> resolved,
    int index,
  ) {
    var input = BytesBuffer.from(entry);

    ASTType ref() {
      var i = input.readLeb128UnsignedInt();
      return _resolve(resolved, i, index);
    }

    ASTType? refOrNull() {
      var i = input.readLeb128UnsignedInt();
      return i == 0 ? null : _resolve(resolved, i - 1, index);
    }

    List<ASTType>? typeList() {
      var n = input.readLeb128UnsignedInt();
      if (n == 0) return null;
      return [for (var i = 1; i < n; ++i) ref()];
    }

    int? intOrNull() {
      var v = input.readLeb128UnsignedInt();
      return v == 0 ? null : v - 1;
    }

    var kind = input.readByte();

    if (kind == ASTTypeEntryKind.wellKnown) {
      var id = input.readByte();
      var instance = ASTWellKnownType.instanceOf(id);
      if (instance == null) {
        throw ASTBinaryException(
          'Unknown well-known type id $id in type table entry $index.',
          ASTBinaryError.unsupportedNode,
          sectionId: ASTBinarySection.typeTable.id,
        );
      }
      return instance;
    }

    ASTType type;
    switch (kind) {
      case ASTTypeEntryKind.array1D:
        // Mirrors the grammars: `ASTTypeArray(t)` with `t` statically an
        // `ASTType`, which is also what returns the interned array singletons
        // for primitive component types.
        type = ASTTypeArray(ref());
      case ASTTypeEntryKind.array2D:
        type = ASTTypeArray2D.fromElementType(ref());
      case ASTTypeEntryKind.array3D:
        type = ASTTypeArray3D.fromElementType(ref());
      case ASTTypeEntryKind.map:
        var k = ref();
        var v = ref();
        type = ASTTypeMap(k, v);
      case ASTTypeEntryKind.future:
        type = ASTTypeFuture(ref());
      case ASTTypeEntryKind.function:
        var g = typeList() ?? const <ASTType>[];
        type = ASTTypeFunction(
          g.isNotEmpty ? g.first : null,
          g.length > 1 ? g.sublist(1) : null,
        );
      case ASTTypeEntryKind.num:
        var bits = intOrNull();
        if (bits != null) {
          // Only `ASTTypeInt` and `ASTTypeDouble` can carry a bit width, and
          // both have their own entry kind; a bare `ASTTypeNum` with one is not
          // constructible through any public API.
          throw ASTBinaryException(
            'Type table entry $index is a plain `num` carrying a $bits-bit '
            'width, which cannot be reconstructed.',
            ASTBinaryError.unsupportedNode,
            sectionId: ASTBinarySection.typeTable.id,
          );
        }
        type = ASTTypeNum();
      case ASTTypeEntryKind.int_:
        type = ASTTypeInt(bits: intOrNull());
      case ASTTypeEntryKind.double_:
        type = ASTTypeDouble(bits: intOrNull());
      case ASTTypeEntryKind.var_:
        type = ASTTypeVar(unmodifiable: input.readBoolean());
      case ASTTypeEntryKind.genericWildcard:
        type = ASTTypeGenericWildcard();
      case ASTTypeEntryKind.genericVariable:
        var name = strings[input.readLeb128UnsignedInt()];
        type = ASTTypeGenericVariable(name, refOrNull());
      case ASTTypeEntryKind.bool_:
        type = ASTTypeBool();
      case ASTTypeEntryKind.string:
        type = ASTTypeString();
      case ASTTypeEntryKind.object:
        type = ASTTypeObject();
      case ASTTypeEntryKind.dynamic_:
        type = ASTTypeDynamic.instance;
      case ASTTypeEntryKind.null_:
        type = ASTTypeNull();
      case ASTTypeEntryKind.void_:
        type = ASTTypeVoid();
      case ASTTypeEntryKind.constructorThis:
        type = ASTTypeConstructorThis.instance;
      case ASTTypeEntryKind.interface:
      case ASTTypeEntryKind.generic:
        var name = strings[input.readLeb128UnsignedInt()];
        var generics = typeList();
        var superType = refOrNull();

        var annotationsCount = input.readLeb128UnsignedInt();
        List<ASTAnnotation>? annotations;
        if (annotationsCount > 0) {
          annotations = [
            for (var i = 1; i < annotationsCount; ++i)
              readAnnotation(input, strings),
          ];
        }

        type = kind == ASTTypeEntryKind.interface
            ? ASTTypeInterface(
                name,
                generics: generics,
                superInterface: superType,
                annotations: annotations,
              )
            : ASTType(
                name,
                generics: generics,
                superType: superType,
                annotations: annotations,
              );
      default:
        throw ASTBinaryException(
          'Unknown type entry kind 0x${kind.toRadixString(16)} at type table '
          'entry $index.',
          ASTBinaryError.unsupportedNode,
          sectionId: ASTBinarySection.typeTable.id,
        );
    }

    // `asNullable` clones rather than mutating, so a shared singleton is never
    // altered by a nullable use of the same type.
    var nullable = input.readBoolean();
    return nullable == type.nullable ? type : type.asNullable(nullable);
  }

  static ASTType _resolve(List<ASTType> resolved, int i, int at) {
    if (i < 0 || i >= resolved.length) {
      throw ASTBinaryException(
        'Type table entry $at references type $i, which is not yet defined '
        '(only ${resolved.length} entries precede it).',
        ASTBinaryError.malformedSection,
        sectionId: ASTBinarySection.typeTable.id,
      );
    }
    return resolved[i];
  }

  /// The type at [index].
  ASTType operator [](int index) {
    if (index < 0 || index >= _values.length) {
      throw ASTBinaryException(
        'Type pool index $index is out of range (0..${_values.length - 1}).',
        ASTBinaryError.malformedSection,
        sectionId: ASTBinarySection.typeTable.id,
      );
    }
    return _values[index];
  }
}
