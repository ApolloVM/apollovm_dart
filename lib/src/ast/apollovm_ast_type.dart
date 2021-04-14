import 'dart:async';

import 'package:apollovm/apollovm.dart';
import 'package:swiss_knife/swiss_knife.dart';

import 'apollovm_ast_annotation.dart';
import 'apollovm_ast_value.dart';
import 'apollovm_ast_variable.dart';

/// An AST Type.
class ASTType<V> implements ASTNode {
  static ASTType from(dynamic o) {
    if (o == null) return ASTTypeNull.INSTANCE;

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

    if (o is String) return ASTTypeString.INSTANCE;
    if (o is int) return ASTTypeInt.INSTANCE;
    if (o is double) return ASTTypeDouble.INSTANCE;

    if (o is List) {
      if (o is List<String>) return ASTTypeArray(ASTTypeString.INSTANCE);
      if (o is List<int>) return ASTTypeArray(ASTTypeInt.INSTANCE);
      if (o is List<double>) return ASTTypeArray(ASTTypeDouble.INSTANCE);
      if (o is List<Object>) return ASTTypeArray(ASTTypeObject.INSTANCE);
      if (o is List<dynamic>) return ASTTypeArray(ASTTypeDynamic.INSTANCE);

      if (o is List<List<String>>) {
        return ASTTypeArray2D<ASTTypeString, String>.fromElementType(
            ASTTypeString.INSTANCE);
      }
      if (o is List<List<int>>)
        // ignore: curly_braces_in_flow_control_structures
        return ASTTypeArray2D<ASTTypeInt, int>.fromElementType(
            ASTTypeInt.INSTANCE);
      if (o is List<List<double>>)
        // ignore: curly_braces_in_flow_control_structures
        return ASTTypeArray2D<ASTTypeDouble, double>.fromElementType(
            ASTTypeDouble.INSTANCE);
      if (o is List<List<Object>>) {
        return ASTTypeArray2D<ASTTypeObject, Object>.fromElementType(
            ASTTypeObject.INSTANCE);
      }
      if (o is List<List<dynamic>>) {
        return ASTTypeArray2D<ASTTypeDynamic, dynamic>.fromElementType(
            ASTTypeDynamic.INSTANCE);
      }

      if (o is List<List<List<String>>>) {
        return ASTTypeArray3D<ASTTypeString, String>.fromElementType(
            ASTTypeString.INSTANCE);
      }
      if (o is List<List<List<int>>>) {
        return ASTTypeArray3D<ASTTypeInt, int>.fromElementType(
            ASTTypeInt.INSTANCE);
      }
      if (o is List<List<List<double>>>) {
        return ASTTypeArray3D<ASTTypeDouble, double>.fromElementType(
            ASTTypeDouble.INSTANCE);
      }
      if (o is List<List<List<Object>>>) {
        return ASTTypeArray3D<ASTTypeObject, Object>.fromElementType(
            ASTTypeObject.INSTANCE);
      }
      if (o is List<List<List<dynamic>>>) {
        return ASTTypeArray3D<ASTTypeDynamic, dynamic>.fromElementType(
            ASTTypeDynamic.INSTANCE);
      }

      var t = ASTType.from(o.genericType);
      return ASTTypeArray(t);
    }

    if (o.runtimeType == Object) return ASTTypeObject.INSTANCE;

    return ASTTypeDynamic.INSTANCE;
  }

  final String name;

  List<ASTType>? generics;

  ASTType? superType;

  List<ASTAnnotation>? annotations;

  ASTType(this.name, {this.generics, this.superType, this.annotations});

  /// Will return true if [type] can be cast to [this] type.
  /// Note: This is similar to Java `isInstance` and `isAssignableFrom`.
  bool isInstance(ASTType type) {
    if (type == this) return true;

    if (type == ASTTypeGenericWildcard.INSTANCE) return true;

    if (type.name != type.name) {
      var typeSuperType = type.superType;
      if (typeSuperType == null) return false;

      if (!typeSuperType.isInstance(this)) return false;
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

      if (!g.isInstance(tg)) {
        return false;
      }
    }

    return true;
  }

  FutureOr<ASTValue<V>?> toValue(VMContext context, Object? v) async {
    if (v is ASTValue<V>) return v;

    if (v is ASTValue) {
      v = await (v).getValue(context);
    }

    var t = v as V;
    return ASTValue.from(this, t);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ASTType &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          generics == other.generics &&
          superType == other.superType;

  @override
  int get hashCode {
    return name.hashCode ^
        (superType?.hashCode ?? 0) ^
        (generics?.hashCode ?? 0);
  }

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
}

/// Base [ASTType] for primitives.
abstract class ASTTypePrimitive<T> extends ASTType<T> {
  ASTTypePrimitive(String name) : super(name);

  @override
  bool isInstance(ASTType type);
}

/// [ASTType] for booleans ([bool]).
class ASTTypeBool extends ASTTypePrimitive<bool> {
  static final ASTTypeBool INSTANCE = ASTTypeBool();

  ASTTypeBool() : super('bool');

  @override
  bool isInstance(ASTType type) {
    if (type == this) return true;
    return false;
  }

  @override
  FutureOr<ASTValueBool?> toValue(VMContext context, Object? v) async {
    if (v is ASTValueBool) return v;

    if (v is ASTValue) {
      v = await (v).getValue(context);
    }

    var b = parseBool(v);
    return b != null ? ASTValueBool(b) : null;
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

/// [ASTType] for numbers ([num]).
abstract class ASTTypeNum<T extends num> extends ASTTypePrimitive<T> {
  ASTTypeNum(String name) : super(name);
}

/// [ASTType] for integer ([int]).
class ASTTypeInt extends ASTTypeNum<int> {
  static final ASTTypeInt INSTANCE = ASTTypeInt();

  ASTTypeInt() : super('int');

  @override
  bool isInstance(ASTType type) {
    if (type == this) return true;
    return false;
  }

  @override
  FutureOr<ASTValueInt?> toValue(VMContext context, Object? v) async {
    if (v is ASTValueInt) return v;
    if (v is ASTValueDouble) return ASTValueInt(v.value.toInt());

    if (v is ASTValue) {
      v = await (v).getValue(context);
    }

    var n = parseInt(v);
    return n != null ? ASTValueInt(n) : null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other && other is ASTTypeInt && runtimeType == other.runtimeType;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() {
    return 'int';
  }
}

/// [ASTType] for [double].
class ASTTypeDouble extends ASTTypeNum<double> {
  static final ASTTypeDouble INSTANCE = ASTTypeDouble();

  ASTTypeDouble() : super('double');

  @override
  bool isInstance(ASTType type) {
    if (type == this) return true;
    return false;
  }

  @override
  FutureOr<ASTValueDouble?> toValue(VMContext context, Object? v) async {
    if (v is ASTValueDouble) return v;
    if (v is ASTValueInt) return ASTValueDouble(v.value.toDouble());

    if (v is ASTValue) {
      v = await (v).getValue(context);
    }

    var n = parseDouble(v);
    return n != null ? ASTValueDouble(n) : null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other && other is ASTTypeInt && runtimeType == other.runtimeType;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() {
    return 'double';
  }
}

/// [ASTType] for [String].
class ASTTypeString extends ASTTypePrimitive<String> {
  static final ASTTypeString INSTANCE = ASTTypeString();

  ASTTypeString() : super('String');

  @override
  bool isInstance(ASTType type) {
    if (type == this) return true;
    return false;
  }

  @override
  FutureOr<ASTValueString?> toValue(VMContext context, Object? v) async {
    if (v is ASTValueString) return v;

    if (v is ASTValue) {
      v = await (v).getValue(context);
    }

    var n = parseString(v);
    return n != null ? ASTValueString(n) : null;
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
  static final ASTTypeObject INSTANCE = ASTTypeObject();

  ASTTypeObject() : super('Object');

  @override
  bool isInstance(ASTType type) => true;

  @override
  FutureOr<ASTValue<Object>?> toValue(VMContext context, Object? v) async {
    if (v is ASTValueObject) return v;

    if (v is ASTValueNull) {
      return null;
    }

    if (v is ASTValueVoid) {
      throw StateError("Can't resolve 'void' to 'Object': $v");
    }

    if (v is ASTValue) {
      var resolved = await v.resolve(context);
      if (resolved is! ASTValue<Object>) {
        var vDyn = await resolved.getValue(context);
        return ASTValueObject(vDyn);
      }
      return resolved;
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

/// [ASTType] for [var] declaration.
class ASTTypeVar extends ASTType<dynamic> {
  static final ASTTypeVar INSTANCE = ASTTypeVar();

  ASTTypeVar() : super('var');

  @override
  bool isInstance(ASTType type) => true;

  @override
  FutureOr<ASTValue<dynamic>> toValue(VMContext context, Object? v) async {
    if (v is ASTValue<dynamic> && v.type == this) return v;

    if (v is ASTValue) {
      v = await (v).getValue(context);
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
  static final ASTTypeDynamic INSTANCE = ASTTypeDynamic();

  ASTTypeDynamic() : super('dynamic');

  @override
  bool isInstance(ASTType type) => true;

  @override
  FutureOr<ASTValue<dynamic>> toValue(VMContext context, Object? v) async {
    if (v is ASTValue<dynamic> && v.type == this) return v;

    if (v is ASTValue) {
      v = await (v).getValue(context);
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

/// [ASTType] for [null].
class ASTTypeNull extends ASTType<Null> {
  static final ASTTypeNull INSTANCE = ASTTypeNull();

  ASTTypeNull() : super('Null');

  @override
  bool isInstance(ASTType type) {
    if (type == this) return true;
    return false;
  }

  @override
  ASTValueNull toValue(VMContext context, Object? v) {
    if (v is ASTValueNull) return v;
    return ASTValueNull.INSTANCE;
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

/// [ASTType] for [void].
class ASTTypeVoid extends ASTType<void> {
  static final ASTTypeVoid INSTANCE = ASTTypeVoid();

  ASTTypeVoid() : super('void');

  @override
  bool isInstance(ASTType type) {
    if (type == this) return true;
    return false;
  }

  @override
  ASTValueVoid toValue(VMContext context, Object? v) {
    return ASTValueVoid.INSTANCE;
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
  String variableName;

  ASTType? type;

  ASTTypeGenericVariable(this.variableName, [this.type]) : super(variableName);

  ASTType<Object> get resolveType =>
      (type as ASTType<Object>?) ?? ASTTypeObject.INSTANCE;

  @override
  FutureOr<ASTValue<Object>?> toValue(VMContext context, Object? v) {
    return resolveType.toValue(context, v);
  }
}

/// Generic wildcard (`?`) of an [ASTType].
class ASTTypeGenericWildcard extends ASTTypeGenericVariable {
  static final ASTTypeGenericWildcard INSTANCE = ASTTypeGenericWildcard();

  ASTTypeGenericWildcard() : super('?');
}

/// [ASTType] for an array/List.
class ASTTypeArray<T extends ASTType<V>, V> extends ASTType<List<V>> {
  T componentType;

  ASTType get elementType => componentType;

  ASTTypeArray(this.componentType) : super('List') {
    generics = [componentType];
  }

  @override
  FutureOr<ASTValueArray<T, V>?> toValue(VMContext context, Object? v) async {
    if (v == null) return null;
    if (v is ASTValueArray) return v as ASTValueArray<T, V>;

    if (v is ASTValue) {
      v = await (v).getValue(context);
    }

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

/// [ASTType] a for a [Future].
class ASTTypeFuture<T extends ASTType<V>, V> extends ASTType<Future<V>> {
  ASTTypeFuture(T type) : super('Future', generics: [type]);

  @override
  ASTValueFuture<T, V>? toValue(VMContext context, Object? v) {
    return ASTValueFuture(this, v as Future<V>);
  }
}
