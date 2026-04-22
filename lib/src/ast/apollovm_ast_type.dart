// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:async_extension/async_extension.dart';
import 'package:collection/collection.dart';
import 'package:swiss_knife/swiss_knife.dart';

import '../apollovm_base.dart';
import '../apollovm_parser.dart';
import '../apollovm_utils.dart';
import '../core/apollovm_core_base.dart';
import 'apollovm_ast_annotation.dart';
import 'apollovm_ast_base.dart';
import 'apollovm_ast_expression.dart';
import 'apollovm_ast_toplevel.dart';
import 'apollovm_ast_value.dart';
import 'apollovm_ast_variable.dart';

/// An AST Type.
class ASTType<V> with ASTNode implements ASTTypedNode {
  static ASTType? fromType(Type type) {
    if (type == String) {
      return ASTTypeString.instance;
    } else if (type == int) {
      return ASTTypeInt.instance;
    } else if (type == double) {
      return ASTTypeDouble.instance;
    } else if (type == bool) {
      return ASTTypeBool.instance;
    } else if (type == Object) {
      return ASTTypeObject.instance;
    } else if (type == dynamic) {
      return ASTTypeDynamic.instance;
    }

    var arrayType = ASTTypeArray.fromType(type);
    if (arrayType != null) return arrayType;

    var mapType = ASTTypeMap.fromType(type);
    if (mapType != null) return mapType;

    return null;
  }

  static ASTType<T> from<T>(dynamic o, [VMContext? context]) {
    if (o == null) return ASTTypeNull.instance as ASTType<T>;

    if (o is ASTType) {
      return o as ASTType<T>;
    }

    if (o is ASTValue) {
      return o.type as ASTType<T>;
    }

    if (o is ASTTypedVariable) {
      return o.type as ASTType<T>;
    }

    if (o is ASTExpressionLiteral) {
      return ASTType.from(o.value, context);
    }

    if (o is ASTTypedNode) {
      var resolved = o.resolveType(context ?? VMContext.getCurrent());
      if (resolved is ASTType) {
        return resolved as ASTType<T>;
      } else {
        return ASTTypeDynamic.instance as ASTType<T>;
      }
    }

    return fromNativeValue(o) as ASTType<T>;
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
          ASTTypeString.instance,
        );
      } else if (o is List<List<int>>) {
        return ASTTypeArray2D<ASTTypeInt, int>.fromElementType(
          ASTTypeInt.instance,
        );
      } else if (o is List<List<double>>) {
        return ASTTypeArray2D<ASTTypeDouble, double>.fromElementType(
          ASTTypeDouble.instance,
        );
      } else if (o is List<List<Object>>) {
        return ASTTypeArray2D<ASTTypeObject, Object>.fromElementType(
          ASTTypeObject.instance,
        );
      } else if (o is List<List<dynamic>>) {
        return ASTTypeArray2D<ASTTypeDynamic, dynamic>.fromElementType(
          ASTTypeDynamic.instance,
        );
      } else if (o is List<List<List<String>>>) {
        return ASTTypeArray3D<ASTTypeString, String>.fromElementType(
          ASTTypeString.instance,
        );
      } else if (o is List<List<List<int>>>) {
        return ASTTypeArray3D<ASTTypeInt, int>.fromElementType(
          ASTTypeInt.instance,
        );
      } else if (o is List<List<List<double>>>) {
        return ASTTypeArray3D<ASTTypeDouble, double>.fromElementType(
          ASTTypeDouble.instance,
        );
      } else if (o is List<List<List<Object>>>) {
        return ASTTypeArray3D<ASTTypeObject, Object>.fromElementType(
          ASTTypeObject.instance,
        );
      } else if (o is List<List<List<dynamic>>>) {
        return ASTTypeArray3D<ASTTypeDynamic, dynamic>.fromElementType(
          ASTTypeDynamic.instance,
        );
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
  Iterable<ASTNode> get children => [...?generics, ...?annotations, ?superType];

  ASTClass<V>? _class;

  void setClass(ASTClass<V> clazz) {
    if (_class != null && !identical(_class, clazz)) {
      throw StateError('Class already set for type: $this');
    }
    _class = clazz;
  }

  ASTClass<V> getClass() {
    if (_class == null) {
      var coreClass = ApolloVMCore.getClass<V>(name, generics: generics);
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
  FutureOr<ASTType> resolveRuntimeType(VMContext context, ASTNode? node) =>
      resolveType(context);

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

  ASTType? commonType(ASTType? other) {
    if (other == null || identical(this, other)) return this;

    if (acceptsType(other)) {
      return this;
    } else if (other.acceptsType(this)) {
      return other;
    }

    return null;
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

  ASTValue<V>? toASTValue(Object? value) {
    return value == null ? null : ASTValue.from(this, value as V);
  }

  R callCasted<R>(R Function<T>() call) {
    return call<V>();
  }

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

mixin StrictType {
  @override
  bool operator ==(Object other) => equals(other);

  bool equals(Object other, {bool strict = false});
}

extension ASTTypeExtension on ASTType {
  bool equalsStrict(ASTType other) {
    final self = this;
    if (self is StrictType) {
      return (self as StrictType).equals(other, strict: true);
    } else if (other is StrictType) {
      return (other as StrictType).equals(self, strict: true);
    } else {
      return self == other;
    }
  }
}

class ASTTypeInterface<V> extends ASTType<V> {
  ASTTypeInterface(
    super.name, {
    super.generics,
    ASTType? superInterface,
    super.annotations,
  }) : super(superType: superInterface);

  @override
  Iterable<ASTNode> get children => [];
}

/// Base [ASTType] for primitives.
abstract class ASTTypePrimitive<T> extends ASTType<T> {
  ASTTypePrimitive(super.name);

  @override
  bool acceptsType(ASTType type);

  @override
  ASTValue<T>? toASTValue(Object? value);
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
  ASTValueBool? toASTValue(Object? value) {
    return value == null ? null : ASTValueBool(parseBool(value) ?? false);
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

enum ASTNumType { nan, num, int, double }

/// Base [ASTType] for primitive numbers.
abstract class ASTTypeNumber<T extends num> extends ASTTypePrimitive<T> {
  ASTTypeNumber(super.name);

  @override
  bool acceptsType(ASTType type);

  @override
  ASTValueNum<T>? toASTValue(Object? value);
}

/// [ASTType] for numbers ([num]).
class ASTTypeNum<T extends num> extends ASTTypeNumber<T> {
  static final ASTTypeNum instance = ASTTypeNum();

  /// Amount of bits of the `num` (optional).
  final int? bits;

  ASTTypeNum._(super.name, {this.bits});

  ASTTypeNum() : this._('num');

  @override
  Iterable<ASTNode> get children => [];

  @override
  bool acceptsType(ASTType type) {
    if (type == this ||
        type == ASTTypeDouble.instance ||
        type == ASTTypeInt.instance) {
      return true;
    }
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
  ASTValueNum<T>? toASTValue(Object? value) {
    if (value == null) return null;

    var n = parseNum(value) ?? 0;

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
    return 'num';
  }
}

/// [ASTType] for integer ([int]).
class ASTTypeInt extends ASTTypeNum<int> with StrictType {
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
  bool equals(Object other, {bool strict = false}) {
    if (identical(this, other)) return true;

    if (other is ASTTypeInt && runtimeType == other.runtimeType) {
      if (strict || (bits != null && other.bits != null)) {
        return bits == other.bits;
      }

      return true;
    }

    return false;
  }

  @override
  ASTValueInt? toASTValue(Object? value) {
    if (value == null) return null;
    var n = parseInt(value) ?? 0;
    return ASTValueInt(n);
  }

  @override
  bool operator ==(Object other) => equals(other);

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() {
    return 'int${bits != null ? '($bits)' : ''}';
  }
}

/// [ASTType] for [double].
class ASTTypeDouble extends ASTTypeNum<double> with StrictType {
  static final ASTTypeDouble instance = ASTTypeDouble();
  static final ASTTypeDouble instance32 = ASTTypeDouble(bits: 32);
  static final ASTTypeDouble instance64 = ASTTypeDouble(bits: 64);

  ASTTypeDouble({super.bits}) : super._('double');

  @override
  bool acceptsType(ASTType type) {
    if (type == this) return true;
    if (type is ASTTypeInt) {
      return true;
    }
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
  bool equals(Object other, {bool strict = false}) {
    if (identical(this, other)) return true;

    if (other is ASTTypeDouble && runtimeType == other.runtimeType) {
      if (strict || (bits != null && other.bits != null)) {
        return bits == other.bits;
      }

      return true;
    }

    return false;
  }

  @override
  ASTValueDouble? toASTValue(Object? value) {
    if (value == null) return null;
    var n = parseDouble(value) ?? 0.0;
    return ASTValueDouble(n);
  }

  static String doubleToString(num v, {bool allowScientificNotation = true}) {
    var s = v.toString();
    if (v == 0.0) {
      return '0.0';
    } else if (s.contains('e') || s.contains('E')) {
      if (allowScientificNotation) {
        return s;
      } else {
        final digits = v
            .toDouble()
            .fractionDigitsFromScientificNotation()
            .clamp(0, 20);
        return v.toStringAsFixed(digits);
      }
    } else if (!s.contains('.')) {
      return '$s.0';
    } else {
      return s;
    }
  }

  @override
  bool operator ==(Object other) => equals(other);

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
  ASTValueString? toASTValue(Object? value) {
    if (value == null) return null;
    var s = parseString(value) ?? '';
    return ASTValueString(s);
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

/// [ASTType] for constructor `this` parameter declaration.
class ASTTypeConstructorThis extends ASTType<dynamic> {
  static final ASTTypeConstructorThis instance = ASTTypeConstructorThis._();

  ASTTypeConstructorThis._() : super('this');

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
    return 'this';
  }
}

/// [ASTType] for `var` declaration.
class ASTTypeVar extends ASTType<dynamic> {
  static final ASTTypeVar instance = ASTTypeVar();

  static final ASTTypeVar instanceUnmodifiable = ASTTypeVar(unmodifiable: true);

  final bool unmodifiable;

  ASTTypeVar({this.unmodifiable = false})
    : super(unmodifiable ? 'final' : 'var');

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
    return unmodifiable ? 'final' : 'var';
  }
}

/// [ASTType] for [dynamic] declaration.
class ASTTypeDynamic extends ASTType<dynamic> {
  static final ASTTypeDynamic instance = ASTTypeDynamic._();

  ASTTypeDynamic._() : super('dynamic');

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
  ASTValueNull? toASTValue(Object? value) {
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
  ASTValueVoid? toASTValue(Object? value) {
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
  Iterable<ASTNode> get children => [?type];

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
      ASTTypeArray<ASTTypeString, String>._(ASTTypeString.instance);

  static final ASTTypeArray<ASTTypeInt, int> instanceOfInt =
      ASTTypeArray<ASTTypeInt, int>._(ASTTypeInt.instance);

  static final ASTTypeArray<ASTTypeDouble, double> instanceOfDouble =
      ASTTypeArray<ASTTypeDouble, double>._(ASTTypeDouble.instance);

  static final ASTTypeArray<ASTTypeBool, bool> instanceOfBool =
      ASTTypeArray<ASTTypeBool, bool>._(ASTTypeBool.instance);

  static final ASTTypeArray<ASTTypeObject, Object> instanceOfObject =
      ASTTypeArray<ASTTypeObject, Object>._(ASTTypeObject.instance);

  static final ASTTypeArray<ASTTypeDynamic, dynamic> instanceOfDynamic =
      ASTTypeArray<ASTTypeDynamic, dynamic>._(ASTTypeDynamic.instance);

  static ASTTypeArray? fromType(Type type) {
    if (type == List<String>) {
      return ASTTypeArray.instanceOfString;
    } else if (type == List<int>) {
      return ASTTypeArray.instanceOfInt;
    } else if (type == List<double>) {
      return ASTTypeArray.instanceOfDouble;
    } else if (type == List<bool>) {
      return ASTTypeArray.instanceOfBool;
    } else if (type == List<Object>) {
      return ASTTypeArray.instanceOfObject;
    } else if (type == List<dynamic>) {
      return ASTTypeArray.instanceOfDynamic;
    }

    return null;
  }

  final T componentType;

  ASTType get elementType => componentType;

  ASTTypeArray._(this.componentType) : super('List', generics: [componentType]);

  factory ASTTypeArray(T type) {
    if (type is ASTTypeString) {
      return ASTTypeArray.instanceOfString as ASTTypeArray<T, V>;
    } else if (type is ASTTypeInt) {
      return ASTTypeArray.instanceOfInt as ASTTypeArray<T, V>;
    } else if (type is ASTTypeDouble) {
      return ASTTypeArray.instanceOfDouble as ASTTypeArray<T, V>;
    } else if (type is ASTTypeBool) {
      return ASTTypeArray.instanceOfBool as ASTTypeArray<T, V>;
    } else if (type is ASTTypeObject) {
      return ASTTypeArray.instanceOfObject as ASTTypeArray<T, V>;
    } else if (type is ASTTypeDynamic) {
      return ASTTypeArray.instanceOfDynamic as ASTTypeArray<T, V>;
    }

    return ASTTypeArray<T, V>._(type);
  }

  factory ASTTypeArray.withType(Type type) {
    if (type == String) {
      return ASTTypeArray.instanceOfString as ASTTypeArray<T, V>;
    } else if (type == int) {
      return ASTTypeArray.instanceOfInt as ASTTypeArray<T, V>;
    } else if (type == double) {
      return ASTTypeArray.instanceOfDouble as ASTTypeArray<T, V>;
    } else if (type == bool) {
      return ASTTypeArray.instanceOfBool as ASTTypeArray<T, V>;
    } else if (type == Object) {
      return ASTTypeArray.instanceOfObject as ASTTypeArray<T, V>;
    } else if (type == dynamic) {
      return ASTTypeArray.instanceOfDynamic as ASTTypeArray<T, V>;
    }

    var astType = ASTType.from<V>(type);
    return ASTTypeArray<T, V>._(astType as T);
  }

  @override
  Iterable<ASTNode> get children => [componentType];

  @override
  FutureOr<ASTValueArray<T, V>?> toValue(VMContext context, Object? v) {
    if (v == null) return null;

    if (v is ASTValueArray) {
      if (v is ASTValueArray<T, V>) {
        return v;
      }
      return v.cast<T, V>(componentType: componentType);
    }

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

  @override
  ASTValueArray<T, V>? toASTValue(Object? value) {
    if (value == null) return null;
    return _toASTValueArray(value);
  }
}

/// [ASTType] a for a 2D array/List.
class ASTTypeArray2D<T extends ASTType<V>, V>
    extends ASTTypeArray<ASTTypeArray<T, V>, List<V>> {
  ASTTypeArray2D(super.type) : super._();

  factory ASTTypeArray2D.fromElementType(ASTType<V> elementType) {
    var a1 = ASTTypeArray<T, V>._(elementType as T);
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

    return _toASTValueArray2D(v);
  }

  ASTValueArray2D<T, V>? _toASTValueArray2D(Object? v) {
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

  @override
  ASTValueArray2D<T, V>? toASTValue(Object? value) {
    if (value == null) return null;
    return _toASTValueArray2D(value);
  }
}

/// [ASTType] a for a 3D array/List.
class ASTTypeArray3D<T extends ASTType<V>, V>
    extends ASTTypeArray2D<ASTTypeArray<T, V>, List<V>> {
  ASTTypeArray3D(ASTTypeArray2D<T, V> super.type);

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
        ASTTypeString.instance,
        ASTTypeDynamic.instance,
      );

  static final ASTTypeMap<ASTTypeString, ASTTypeString, String, String>
  instanceOfStringOfString =
      ASTTypeMap<ASTTypeString, ASTTypeString, String, String>(
        ASTTypeString.instance,
        ASTTypeString.instance,
      );

  static final ASTTypeMap<ASTTypeDynamic, ASTTypeDynamic, dynamic, dynamic>
  instanceOfDynamicOfDynamic =
      ASTTypeMap<ASTTypeDynamic, ASTTypeDynamic, dynamic, dynamic>(
        ASTTypeDynamic.instance,
        ASTTypeDynamic.instance,
      );

  static ASTTypeMap? fromType(Type type) {
    if (type == Map<String, dynamic>) {
      return ASTTypeMap.instanceOfStringOfDynamic;
    } else if (type == Map<String, String>) {
      return ASTTypeMap.instanceOfStringOfString;
    } else if (type == Map<dynamic, dynamic>) {
      return ASTTypeMap.instanceOfDynamicOfDynamic;
    }

    return null;
  }

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

    var map2 = Map<K, V>.fromEntries(
      map.entries.map((e) {
        var k = e.key;
        var v = e.value;
        return k is K && v is V ? MapEntry(k, v) : null;
      }).nonNulls,
    );

    var value = ASTValueMap<TK, TV, K, V>(keyType, valueType, map2);
    return value;
  }

  @override
  ASTValueMap<TK, TV, K, V>? toASTValue(Object? value) {
    if (value == null) return null;
    return _toASTValueMap(value);
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

  @override
  ASTValueFuture<T, V>? toASTValue(Object? value) {
    if (value == null) return null;
    return ASTValueFuture(
      this,
      value is Future<V>
          ? value
          : (value is Future
                ? value.then((v) => v as V)
                : Future.value(value as V)),
    );
  }
}

/// [ASTType] for a [Function].
class ASTTypeFunction<F extends Function> extends ASTType<F> {
  ASTTypeFunction([ASTType? returnType, List<ASTType>? parameters])
    : super('Function', generics: [?returnType, ...?parameters]);

  @override
  Iterable<ASTNode> get children => [];

  @override
  ASTValueFunction<F>? toValue(VMContext context, Object? v) {
    if (v == null) return null;

    throw UnsupportedError(
      "Can't resolve an `ASTValueFunction` from a: ${v.runtimeType}",
    );
  }

  @override
  ASTValueFunction<F>? toASTValue(Object? value) {
    if (value == null) return null;

    throw UnsupportedError(
      "Can't resolve an `ASTValueFunction` from a: ${value.runtimeType}",
    );
  }
}
