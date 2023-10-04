// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:async_extension/async_extension.dart';
import 'package:collection/collection.dart';
import 'package:swiss_knife/swiss_knife.dart';

import '../apollovm_base.dart';
import '../apollovm_parser.dart';
import '../core/apollovm_core_base.dart';
import 'apollovm_ast_annotation.dart';
import 'apollovm_ast_base.dart';
import 'apollovm_ast_expression.dart';
import 'apollovm_ast_toplevel.dart';
import 'apollovm_ast_value.dart';
import 'apollovm_ast_variable.dart';

/// An AST Type.
class ASTType<V> with ASTNode implements ASTTypedNode {
  static ASTType from(dynamic o, [VMContext? context]) {
    if (o == null) return ASTTypeNull.instance;

    if (o is ASTType) {
      return o;
    }

    if (o is ASTValue) {
      return o.type;
    }

    if (o is ASTTypedVariable) {
      return o.type;
    }

    if (o is ASTExpressionLiteral) {
      return ASTType.from(o.value, context);
    }

    if (o is ASTTypedNode) {
      var resolved = o.resolveType(context ?? VMContext.getCurrent());
      if (resolved is ASTType) {
        return resolved;
      } else {
        return ASTTypeDynamic.instance;
      }
    }

    return fromNativeValue(o);
  }

  static FutureOr<ASTType> fromAsync(dynamic o) {
    if (o == null) return ASTTypeNull.instance;

    if (o is ASTType) {
      return o;
    }

    if (o is ASTValue) {
      return o.type;
    }

    if (o is ASTTypedVariable) {
      return o.type;
    }

    if (o is ASTExpressionLiteral) {
      return ASTType.from(o.value);
    }

    if (o is ASTTypedNode) {
      return o.resolveType(VMContext.getCurrent());
    }

    return fromNativeValue(o);
  }

  static ASTType fromNativeValue(dynamic o) {
    if (o == null) return ASTTypeNull.instance;

    if (o is String) return ASTTypeString.instance;
    if (o is int) return ASTTypeInt.instance;
    if (o is double) return ASTTypeDouble.instance;

    if (o is List) {
      if (o is List<String>) {
        return ASTTypeArray.instanceOfString;
      } else if (o is List<int>) {
        return ASTTypeArray.instanceOfInt;
      } else if (o is List<double>) {
        return ASTTypeArray.instanceOfDouble;
      } else if (o is List<Object>) {
        return ASTTypeArray.instanceOfObject;
      } else if (o is List<List<String>>) {
        return ASTTypeArray2D<ASTTypeString, String>.fromElementType(
            ASTTypeString.instance);
      } else if (o is List<List<int>>) {
        return ASTTypeArray2D<ASTTypeInt, int>.fromElementType(
            ASTTypeInt.instance);
      } else if (o is List<List<double>>) {
        return ASTTypeArray2D<ASTTypeDouble, double>.fromElementType(
            ASTTypeDouble.instance);
      } else if (o is List<List<Object>>) {
        return ASTTypeArray2D<ASTTypeObject, Object>.fromElementType(
            ASTTypeObject.instance);
      } else if (o is List<List<dynamic>>) {
        return ASTTypeArray2D<ASTTypeDynamic, dynamic>.fromElementType(
            ASTTypeDynamic.instance);
      } else if (o is List<List<List<String>>>) {
        return ASTTypeArray3D<ASTTypeString, String>.fromElementType(
            ASTTypeString.instance);
      } else if (o is List<List<List<int>>>) {
        return ASTTypeArray3D<ASTTypeInt, int>.fromElementType(
            ASTTypeInt.instance);
      } else if (o is List<List<List<double>>>) {
        return ASTTypeArray3D<ASTTypeDouble, double>.fromElementType(
            ASTTypeDouble.instance);
      } else if (o is List<List<List<Object>>>) {
        return ASTTypeArray3D<ASTTypeObject, Object>.fromElementType(
            ASTTypeObject.instance);
      } else if (o is List<List<List<dynamic>>>) {
        return ASTTypeArray3D<ASTTypeDynamic, dynamic>.fromElementType(
            ASTTypeDynamic.instance);
      }

      var genericType = o.genericType;

      if (genericType == dynamic) {
        return ASTTypeArray(ASTTypeDynamic.instance);
      } else {
        var t = ASTType.from(genericType);
        return ASTTypeArray(t);
      }
    }

    if (o.runtimeType == Object) return ASTTypeObject.instance;

    return ASTTypeDynamic.instance;
  }

  final String name;

  final List<ASTType>? generics;

  final ASTType? superType;

  final List<ASTAnnotation>? annotations;

  ASTType(this.name, {this.generics, this.superType, this.annotations});

  @override
  Iterable<ASTNode> get children =>
      [...?generics, ...?annotations, if (superType != null) superType!];

  ASTClass<V>? _class;

  void setClass(ASTClass<V> clazz) {
    if (_class != null && !identical(_class, clazz)) {
      throw StateError('Class already set for type: $this');
    }
    _class = clazz;
  }

  ASTClass<V> getClass() {
    if (_class == null) {
      var coreClass = ApolloVMCore.getClass<V>(name);
      if (coreClass == null) {
        throw StateError('Class not set for type: $this');
      }
      _class = coreClass;
    }
    return _class!;
  }

  @override
  FutureOr<ASTType> resolveType(VMContext? context) => this;

  @override
  void associateToType(ASTTypedNode node) {}

  /// Returns true if this type has generics.
  bool get hasGenerics => generics != null && generics!.isNotEmpty;

  /// Returns true if this type has a super type.
  bool get hasSuperType => superType != null;

  /// Return true if [this] can be cast to [type];
  bool canCastToType(ASTType type) => type.acceptsType(this);

  /// Will return true if [type] can be cast to [this] type.
  /// Note: This is similar to Java `isInstance` and `isAssignableFrom`.
  bool acceptsType(ASTType type) {
    if (type == this) return true;

    if (type == ASTTypeGenericWildcard.instance) return true;

    if (name != type.name) {
      var typeSuperType = type.superType;
      if (typeSuperType == null) return false;

      if (!typeSuperType.acceptsType(this)) return false;
    }

    var generics = this.generics;
    var typeGenerics = type.generics;

    if (generics == null || generics.isEmpty) {
      return typeGenerics == null || typeGenerics.isEmpty;
    }

    if (typeGenerics == null || typeGenerics.isEmpty) {
      return false;
    }

    if (generics.length != typeGenerics.length) return false;

    var genericsLength = generics.length;

    for (var i = 0; i < genericsLength; ++i) {
      var g = generics[i];
      var tg = typeGenerics[i];

      if (!g.acceptsType(tg)) {
        return false;
      }
    }

    return true;
  }

  FutureOr<ASTValue<V>?> toValue(VMContext context, Object? v) {
    if (v == null) return null;

    if (v is ASTValue<V>) return v;

    if (v is ASTValue) {
      return v.getValue(context).resolveMapped((val) {
        var t = val as V;
        return ASTValue.from(this, t);
      });
    } else {
      var t = v as V;
      return ASTValue.from(this, t);
    }
  }

  FutureOr<ASTValue<V>?> toDefaultValue(VMContext context) => null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ASTType &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          generics == other.generics &&
          superType == other.superType;

  static final ListEquality<ASTType> _listEquality = ListEquality();

  @override
  int get hashCode {
    final generics = this.generics;

    return name.hashCode ^
        (superType?.hashCode ?? 0) ^
        (generics != null ? _listEquality.hash(generics) : 0);
  }

  ASTNode? _parentNode;

  @override
  ASTNode? get parentNode => _parentNode;

  @override
  void resolveNode(ASTNode? parentNode) {
    _parentNode = parentNode;

    cacheDescendantChildren();
  }

  @override
  ASTNode? getNodeIdentifier(String name, {ASTNode? requester}) =>
      parentNode?.getNodeIdentifier(name, requester: requester);

  @override
  String toString() {
    return generics == null ? name : '$name<${generics!.join(',')}>';
  }
}

class ASTTypeInterface<V> extends ASTType<V> {
  ASTTypeInterface(String name,
      {List<ASTType>? generics,
      ASTType? superInterface,
      List<ASTAnnotation>? annotations})
      : super(name,
            generics: generics,
            superType: superInterface,
            annotations: annotations);

  @override
  Iterable<ASTNode> get children => [];
}

/// Base [ASTType] for primitives.
abstract class ASTTypePrimitive<T> extends ASTType<T> {
  ASTTypePrimitive(String name) : super(name);

  @override
  bool acceptsType(ASTType type);
}

/// [ASTType] for booleans ([bool]).
class ASTTypeBool extends ASTTypePrimitive<bool> {
  static final ASTTypeBool instance = ASTTypeBool();

  ASTTypeBool() : super('bool');

  @override
  Iterable<ASTNode> get children => [];

  @override
  bool acceptsType(ASTType type) {
    if (type == this) return true;
    return false;
  }

  @override
  FutureOr<ASTValueBool?> toValue(VMContext context, Object? v) {
    if (v is ASTValueBool) return v;

    if (v is ASTValue) {
      return v.getValue(context).resolveMapped(_toASTValueBool);
    } else {
      return _toASTValueBool(v);
    }
  }

  ASTValueBool? _toASTValueBool(dynamic v) {
    var b = parseBool(v);
    return b != null ? ASTValueBool(b) : null;
  }

  @override
  FutureOr<ASTValueBool?> toDefaultValue(VMContext context) {
    return ASTValueBool(false);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other && other is ASTTypeInt && runtimeType == other.runtimeType;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() {
    return 'bool';
  }
}

enum ASTNumType {
  nan,
  num,
  int,
  double,
}

/// Base [ASTType] for primitive numbers.
abstract class ASTTypeNumber<T> extends ASTTypePrimitive<T> {
  ASTTypeNumber(String name) : super(name);

  @override
  bool acceptsType(ASTType type);
}

/// [ASTType] for numbers ([num]).
class ASTTypeNum<T extends num> extends ASTTypeNumber<T> {
  static final ASTTypeNum instance = ASTTypeNum();

  /// Amount of bits of the `num` (optional).
  final int? bits;

  ASTTypeNum._(String name, {this.bits}) : super(name);

  ASTTypeNum() : this._('num');

  @override
  Iterable<ASTNode> get children => [];

  @override
  bool acceptsType(ASTType type) {
    if (type == this ||
        type == ASTTypeDouble.instance ||
        type == ASTTypeInt.instance) return true;
    return false;
  }

  @override
  FutureOr<ASTValueNum<T>?> toValue(VMContext context, Object? v) {
    if (v is ASTTypeNum) return v as ASTValueNum<T>;
    if (v is ASTValueInt) return v as ASTValueNum<T>;
    if (v is ASTValueDouble) return v as ASTValueNum<T>;

    if (v is ASTValue) {
      return v.getValue(context).resolveMapped(_toASTValueNum);
    } else {
      return _toASTValueNum(v);
    }
  }

  ASTValueNum<T>? _toASTValueNum(dynamic v) {
    var n = parseNum(v);
    if (n == null) return null;

    if (n is int) {
      return ASTValueInt(n) as ASTValueNum<T>;
    } else {
      return ASTValueDouble(n.toDouble()) as ASTValueNum<T>;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other && other is ASTTypeNum && runtimeType == other.runtimeType;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() {
    return 'double';
  }
}

/// [ASTType] for integer ([int]).
class ASTTypeInt extends ASTTypeNum<int> {
  static final ASTTypeInt instance = ASTTypeInt();
  static final ASTTypeInt instance32 = ASTTypeInt(bits: 32);
  static final ASTTypeInt instance64 = ASTTypeInt(bits: 64);

  ASTTypeInt({super.bits}) : super._('int');

  @override
  bool acceptsType(ASTType type) {
    if (type == this) return true;
    return false;
  }

  @override
  FutureOr<ASTValueInt?> toValue(VMContext context, Object? v) {
    if (v is ASTValueInt) return v;
    if (v is ASTValueDouble) return ASTValueInt(v.value.toInt());

    if (v is ASTValue) {
      return v.getValue(context).resolveMapped(_toASTValueInt);
    } else {
      return _toASTValueInt(v);
    }
  }

  ASTValueInt? _toASTValueInt(dynamic v) {
    var n = parseInt(v);
    return n != null ? ASTValueInt(n) : null;
  }

  @override
  ASTValueInt toDefaultValue(VMContext context) {
    return ASTValueInt(0);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    if (other is ASTTypeInt && runtimeType == other.runtimeType) {
      if (bits != null && other.bits != null) {
        return bits == other.bits;
      }

      return true;
    }

    return false;
  }

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() {
    return 'int${bits != null ? '($bits)' : ''}';
  }
}

/// [ASTType] for [double].
class ASTTypeDouble extends ASTTypeNum<double> {
  static final ASTTypeDouble instance = ASTTypeDouble();
  static final ASTTypeDouble instance32 = ASTTypeDouble(bits: 32);
  static final ASTTypeDouble instance64 = ASTTypeDouble(bits: 64);

  ASTTypeDouble({super.bits}) : super._('double');

  @override
  bool acceptsType(ASTType type) {
    if (type == this) return true;
    return false;
  }

  @override
  FutureOr<ASTValueDouble?> toValue(VMContext context, Object? v) {
    if (v is ASTValueDouble) return v;
    if (v is ASTValueInt) return ASTValueDouble(v.value.toDouble());

    if (v is ASTValue) {
      return v.getValue(context).resolveMapped(_toASTValueDouble);
    }

    return _toASTValueDouble(v);
  }

  ASTValueDouble? _toASTValueDouble(dynamic v) {
    var n = parseDouble(v);
    return n != null ? ASTValueDouble(n) : null;
  }

  @override
  FutureOr<ASTValueDouble?> toDefaultValue(VMContext context) {
    return ASTValueDouble(0.0);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    if (other is ASTTypeDouble && runtimeType == other.runtimeType) {
      if (bits != null && other.bits != null) {
        return bits == other.bits;
      }

      return true;
    }

    return false;
  }

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() {
    return 'double${bits != null ? '($bits)' : ''}';
  }
}

/// [ASTType] for [String].
class ASTTypeString extends ASTTypePrimitive<String> {
  static final ASTTypeString instance = ASTTypeString();

  ASTTypeString() : super('String');

  @override
  Iterable<ASTNode> get children => [];

  @override
  bool acceptsType(ASTType type) {
    if (type == this) return true;
    return false;
  }

  @override
  FutureOr<ASTValueString?> toValue(VMContext context, Object? v) {
    if (v is ASTValueString) return v;

    if (v is ASTValue) {
      return v.getValue(context).resolveMapped(_toASTValueString);
    } else {
      return _toASTValueString(v);
    }
  }

  ASTValueString? _toASTValueString(dynamic v) {
    var n = parseString(v);
    return n != null ? ASTValueString(n) : null;
  }

  @override
  FutureOr<ASTValueString?> toDefaultValue(VMContext context) {
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other && other is ASTTypeInt && runtimeType == other.runtimeType;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() {
    return 'String';
  }
}

/// [ASTType] for [Object].
class ASTTypeObject extends ASTType<Object> {
  static final ASTTypeObject instance = ASTTypeObject();

  ASTTypeObject() : super('Object');

  @override
  Iterable<ASTNode> get children => [];

  @override
  bool acceptsType(ASTType type) => true;

  @override
  FutureOr<ASTValue<Object>?> toValue(VMContext context, Object? v) {
    if (v is ASTValueObject) return v;

    if (v is ASTValueNull) {
      return null;
    }

    if (v is ASTValueVoid) {
      throw StateError("Can't resolve 'void' to 'Object': $v");
    }

    if (v is ASTValue) {
      return v.resolve(context).resolveMapped((resolved) {
        if (resolved is! ASTValue<Object>) {
          return resolved.getValue(context).resolveMapped((vDyn) {
            return ASTValueObject(vDyn);
          });
        }
        return resolved;
      });
    }

    return v != null ? ASTValueObject(v) : null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other && other is ASTTypeInt && runtimeType == other.runtimeType;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() {
    return 'Object';
  }
}

/// [ASTType] for `var` declaration.
class ASTTypeVar extends ASTType<dynamic> {
  static final ASTTypeVar instance = ASTTypeVar();

  ASTTypeVar() : super('var');

  @override
  Iterable<ASTNode> get children => [];

  @override
  bool acceptsType(ASTType type) => true;

  ASTType? _resolvedType;

  @override
  FutureOr<ASTType> resolveType(VMContext? context) {
    final resolvedType = _resolvedType;
    if (resolvedType != null) return resolvedType;

    return _resolveTypeImpl(context).resolveMapped((resolvedType) {
      _resolvedType = resolvedType;
      return resolvedType;
    });
  }

  FutureOr<ASTType> _resolveTypeImpl(VMContext? context) {
    var associatedNode = _associatedNode;
    return associatedNode == null ? this : associatedNode.resolveType(context);
  }

  ASTTypedNode? _associatedNode;

  @override
  void associateToType(ASTTypedNode node) => _associatedNode = node;

  @override
  FutureOr<ASTValue<dynamic>> toValue(VMContext context, Object? v) {
    if (v is ASTValue<dynamic> && v.type == this) {
      return v;
    }

    if (v is ASTValue) {
      return v.getValue(context).resolveMapped((v) {
        return ASTValueStatic<dynamic>(this, v);
      });
    }

    return ASTValueStatic<dynamic>(this, v);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other && other is ASTTypeInt && runtimeType == other.runtimeType;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() {
    return 'var';
  }
}

/// [ASTType] for [dynamic] declaration.
class ASTTypeDynamic extends ASTType<dynamic> {
  static final ASTTypeDynamic instance = ASTTypeDynamic();

  ASTTypeDynamic() : super('dynamic');

  @override
  Iterable<ASTNode> get children => [];

  @override
  bool acceptsType(ASTType type) => true;

  @override
  FutureOr<ASTValue<dynamic>> toValue(VMContext context, Object? v) {
    if (v is ASTValue && v.type == this) {
      return v;
    }

    if (v is ASTValue) {
      return v.getValue(context).resolveMapped((v) {
        return ASTValue.from(this, v);
      });
    }

    return ASTValue.from(this, v);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other && other is ASTTypeInt && runtimeType == other.runtimeType;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() {
    return 'dynamic';
  }
}

/// [ASTType] for `null`.
// ignore: prefer_void_to_null
class ASTTypeNull extends ASTType<Null> {
  static final ASTTypeNull instance = ASTTypeNull();

  ASTTypeNull() : super('Null');

  @override
  Iterable<ASTNode> get children => [];

  @override
  bool acceptsType(ASTType type) {
    if (type == this) return true;
    return false;
  }

  @override
  ASTValueNull toValue(VMContext context, Object? v) {
    if (v is ASTValueNull) return v;
    return ASTValueNull.instance;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other && other is ASTTypeInt && runtimeType == other.runtimeType;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() {
    return 'Null';
  }
}

/// [ASTType] for `void`.
class ASTTypeVoid extends ASTType<void> {
  static final ASTTypeVoid instance = ASTTypeVoid();

  ASTTypeVoid() : super('void');

  @override
  Iterable<ASTNode> get children => [];

  @override
  bool acceptsType(ASTType type) {
    if (type == this) return true;
    return false;
  }

  @override
  ASTValueVoid toValue(VMContext context, Object? v) {
    return ASTValueVoid.instance;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other && other is ASTTypeInt && runtimeType == other.runtimeType;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() {
    return 'void';
  }
}

/// Generic variable of an [ASTType].
class ASTTypeGenericVariable extends ASTType<Object> {
  final String variableName;

  final ASTType? type;

  ASTTypeGenericVariable(this.variableName, [this.type]) : super(variableName);

  @override
  Iterable<ASTNode> get children => [if (type != null) type!];

  @override
  ASTType<Object> resolveType(VMContext? context) =>
      (type as ASTType<Object>?) ?? ASTTypeObject.instance;

  @override
  FutureOr<ASTValue<Object>?> toValue(VMContext context, Object? v) {
    return resolveType(context).toValue(context, v);
  }
}

/// Generic wildcard (`?`) of an [ASTType].
class ASTTypeGenericWildcard extends ASTTypeGenericVariable {
  static final ASTTypeGenericWildcard instance = ASTTypeGenericWildcard();

  ASTTypeGenericWildcard() : super('?');

  @override
  ASTType<Object> resolveType(VMContext? context) => ASTTypeObject.instance;
}

/// [ASTType] for an array/List.
class ASTTypeArray<T extends ASTType<V>, V> extends ASTType<List<V>> {
  static final ASTTypeArray<ASTTypeString, String> instanceOfString =
      ASTTypeArray<ASTTypeString, String>(ASTTypeString.instance);

  static final ASTTypeArray<ASTTypeInt, int> instanceOfInt =
      ASTTypeArray<ASTTypeInt, int>(ASTTypeInt.instance);

  static final ASTTypeArray<ASTTypeDouble, double> instanceOfDouble =
      ASTTypeArray<ASTTypeDouble, double>(ASTTypeDouble.instance);

  static final ASTTypeArray<ASTTypeBool, bool> instanceOfBool =
      ASTTypeArray<ASTTypeBool, bool>(ASTTypeBool.instance);

  static final ASTTypeArray<ASTTypeObject, Object> instanceOfObject =
      ASTTypeArray<ASTTypeObject, Object>(ASTTypeObject.instance);

  static final ASTTypeArray<ASTTypeDynamic, dynamic> instanceOfDynamic =
      ASTTypeArray<ASTTypeDynamic, dynamic>(ASTTypeDynamic.instance);

  final T componentType;

  ASTType get elementType => componentType;

  ASTTypeArray(this.componentType) : super('List', generics: [componentType]);

  @override
  Iterable<ASTNode> get children => [componentType];

  @override
  FutureOr<ASTValueArray<T, V>?> toValue(VMContext context, Object? v) {
    if (v == null) return null;
    if (v is ASTValueArray) return v as ASTValueArray<T, V>;

    if (v is ASTValue) {
      return v.getValue(context).resolveMapped(_toASTValueArray);
    } else {
      return _toASTValueArray(v);
    }
  }

  ASTValueArray<T, V>? _toASTValueArray(Object? v) {
    List list;
    if (v is List) {
      list = v;
    } else {
      list = [v];
    }

    var list2 = list.whereType<V>().toList();

    var value = ASTValueArray<T, V>(componentType, list2);
    return value;
  }
}

/// [ASTType] a for a 2D array/List.
class ASTTypeArray2D<T extends ASTType<V>, V>
    extends ASTTypeArray<ASTTypeArray<T, V>, List<V>> {
  ASTTypeArray2D(ASTTypeArray<T, V> type) : super(type);

  factory ASTTypeArray2D.fromElementType(ASTType<V> elementType) {
    var a1 = ASTTypeArray<T, V>(elementType as T);
    return ASTTypeArray2D<T, V>(a1);
  }

  @override
  ASTType get elementType => componentType.elementType;

  @override
  ASTValueArray2D<T, V>? toValue(VMContext context, Object? v) {
    if (v == null) return null;
    if (v is ASTValueArray2D) return v as ASTValueArray2D<T, V>;

    if (v is ASTValue) {
      v = (v).getValue(context);
    }

    List list;
    if (v is List) {
      list = v;
    } else {
      list = [v];
    }

    var list2 = list.whereType<List<V>>().toList();

    var value = ASTValueArray2D<T, V>(elementType as T, list2);
    return value;
  }
}

/// [ASTType] a for a 3D array/List.
class ASTTypeArray3D<T extends ASTType<V>, V>
    extends ASTTypeArray2D<ASTTypeArray<T, V>, List<V>> {
  ASTTypeArray3D(ASTTypeArray2D<T, V> type) : super(type);

  factory ASTTypeArray3D.fromElementType(ASTType<V> elementType) {
    var a1 = ASTTypeArray<T, V>(elementType as T);
    var a2 = ASTTypeArray2D<T, V>(a1);
    return ASTTypeArray3D(a2);
  }

  @override
  ASTType get elementType => componentType.elementType;

  @override
  ASTValueArray3D<T, V>? toValue(VMContext context, Object? v) {
    if (v == null) return null;
    if (v is ASTValueArray2D) return v as ASTValueArray3D<T, V>;

    if (v is ASTValue) {
      v = (v).getValue(context);
    }

    List list;
    if (v is List) {
      list = v;
    } else {
      list = [v];
    }

    var list2 = list.whereType<List<List<V>>>().toList();

    var value = ASTValueArray3D<T, V>(elementType as T, list2);
    return value;
  }
}

/// [ASTType] for an array/List.
class ASTTypeMap<TK extends ASTType<K>, TV extends ASTType<V>, K, V>
    extends ASTType<Map<K, V>> {
  static final ASTTypeMap<ASTTypeString, ASTTypeDynamic, String, dynamic>
      instanceOfStringOfDynamic =
      ASTTypeMap<ASTTypeString, ASTTypeDynamic, String, dynamic>(
          ASTTypeString.instance, ASTTypeDynamic.instance);

  static final ASTTypeMap<ASTTypeString, ASTTypeString, String, String>
      instanceOfStringOfString =
      ASTTypeMap<ASTTypeString, ASTTypeString, String, String>(
          ASTTypeString.instance, ASTTypeString.instance);

  static final ASTTypeMap<ASTTypeDynamic, ASTTypeDynamic, dynamic, dynamic>
      instanceOfDynamicOfDynamic =
      ASTTypeMap<ASTTypeDynamic, ASTTypeDynamic, dynamic, dynamic>(
          ASTTypeDynamic.instance, ASTTypeDynamic.instance);

  final TK keyType;
  final TV valueType;

  ASTTypeMap(this.keyType, this.valueType)
      : super('Map', generics: [keyType, valueType]);

  @override
  Iterable<ASTNode> get children => [keyType, valueType];

  @override
  FutureOr<ASTValue<Map<K, V>>?> toValue(VMContext context, Object? v) {
    if (v == null) return null;
    if (v is ASTValueMap) return v as ASTValueMap<TK, TV, K, V>;

    if (v is ASTValue) {
      return v.getValue(context).resolveMapped(_toASTValueMap);
    } else {
      return _toASTValueMap(v);
    }
  }

  ASTValueMap<TK, TV, K, V>? _toASTValueMap(Object? v) {
    Map? map;
    if (v is Map) {
      map = v;
    } else if (v is List) {
      if (v is List<MapEntry>) {
        map = Map.fromEntries(v);
      } else if (v.every((e) => e is MapEntry)) {
        map = Map.fromEntries(v.cast<MapEntry>());
      } else if (v.isEmpty) {
        map = {};
      } else if (v.length == 2) {
        map = {v[0]: v[1]};
      } else if (v.length % 2 == 0) {
        map = {};
        for (var i = 0; i < v.length; i += 2) {
          var k = map[i];
          var v = map[i + 1];
          map[k] = v;
        }
      }
    }

    map ??= {};

    var map2 = Map<K, V>.fromEntries(map.entries.map((e) {
      var k = e.key;
      var v = e.value;
      return k is K && v is V ? MapEntry(k, v) : null;
    }).whereNotNull());

    var value = ASTValueMap<TK, TV, K, V>(keyType, valueType, map2);
    return value;
  }
}

/// [ASTType] a for a [Future].
class ASTTypeFuture<T extends ASTType<V>, V> extends ASTType<Future<V>> {
  ASTTypeFuture(T type) : super('Future', generics: [type]);

  @override
  Iterable<ASTNode> get children => [];

  @override
  ASTValueFuture<T, V>? toValue(VMContext context, Object? v) {
    return ASTValueFuture(this, v as Future<V>);
  }
}
