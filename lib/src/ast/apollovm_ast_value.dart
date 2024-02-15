// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:async_extension/async_extension.dart';
import 'package:collection/collection.dart'
    show DeepCollectionEquality, ListEquality, MapEquality;
import 'package:swiss_knife/swiss_knife.dart';

import '../apollovm_base.dart';
import '../apollovm_parser.dart';
import 'apollovm_ast_base.dart';
import 'apollovm_ast_expression.dart';
import 'apollovm_ast_toplevel.dart';
import 'apollovm_ast_type.dart';
import 'apollovm_ast_variable.dart';

/// Base class for AST values.
abstract class ASTValue<T> with ASTNode implements ASTTypedNode {
  factory ASTValue.from(ASTType<T> type, T value) {
    if (value is ASTValue) {
      return value as ASTValue<T>;
    } else if (type is ASTTypeString) {
      return ASTValueString(value as String) as ASTValue<T>;
    } else if (type is ASTTypeInt) {
      return ASTValueInt(value as int) as ASTValue<T>;
    } else if (type is ASTTypeDouble) {
      return ASTValueDouble(value as double) as ASTValue<T>;
    } else if (type is ASTTypeNull) {
      return ASTValueNull.instance as ASTValue<T>;
    } else if (type is ASTTypeObject) {
      return ASTValueObject(value!) as ASTValue<T>;
    } else if (type is ASTTypeVoid) {
      return ASTValueVoid.instance as ASTValue<T>;
    } else if (type is ASTTypeArray3D) {
      return ASTValueArray3D(type, value as dynamic) as ASTValue<T>;
    } else if (type is ASTTypeArray2D) {
      return ASTValueArray2D(type, value as dynamic) as ASTValue<T>;
    } else if (type is ASTTypeArray) {
      return ASTValueArray(type, value as dynamic) as ASTValue<T>;
    } else {
      return ASTValueStatic<T>(type, value);
    }
  }

  static ASTValue fromValue(dynamic o) {
    if (o == null) return ASTValueNull.instance;

    if (o is ASTValue) return o;

    if (o is String) return ASTValueString(o);
    if (o is int) return ASTValueInt(o);
    if (o is double) return ASTValueDouble(o);
    if (o is bool) return ASTValueBool(o);

    var t = ASTType.from(o);
    return ASTValue.from(t, o);
  }

  ASTType<T> type;

  ASTValue(this.type);

  bool isInstanceOf(ASTType type) {
    var context = VMContext.getCurrent();

    var valueType = resolveType(context);
    if (valueType is ASTType) {
      return type.acceptsType(valueType);
    } else {
      var value = context != null ? getValue(context) : getValueNoContext();
      var actualValueType = ASTType.from(value);
      return type.acceptsType(actualValueType);
    }
  }

  FutureOr<bool> isInstanceOfAsync(ASTType type) {
    var context = VMContext.getCurrent();
    return resolveType(context).resolveMapped((valueType) {
      return type.acceptsType(valueType);
    });
  }

  FutureOr<T> getValue(VMContext context);

  FutureOr<T> getValueNoContext();

  FutureOr<ASTValue<T>> resolve(VMContext context);

  @override
  FutureOr<ASTType> resolveType(VMContext? context) => type;

  @override
  void associateToType(ASTTypedNode node) {}

  FutureOr<V> readIndex<V>(VMContext context, int index) {
    throw UnsupportedError("Can't read index for type: $type");
  }

  FutureOr<V> readKey<V>(VMContext context, Object key) {
    throw UnsupportedError("Can't read key for type: $type");
  }

  FutureOr<int?> size(VMContext context) => null;

  FutureOr<ASTValue> operator +(ASTValue other) =>
      throw UnsupportedValueOperationError('+');

  FutureOr<ASTValue> operator -(ASTValue other) =>
      throw UnsupportedValueOperationError('+');

  FutureOr<ASTValue> operator /(ASTValue other) =>
      throw UnsupportedValueOperationError('+');

  FutureOr<ASTValue> operator *(ASTValue other) =>
      throw UnsupportedValueOperationError('+');

  FutureOr<ASTValue> operator ~/(ASTValue other) =>
      throw UnsupportedValueOperationError('+');

  FutureOr<T> _getValue(VMContext? context, ASTValue v) => context != null
      ? v.getValue(context) as FutureOr<T>
      : v.getValueNoContext() as FutureOr<T>;

  T? _getValueSafe(VMContext? context, ASTValue v) {
    try {
      var val = _getValue(context, v);
      return val is Future ? null : val;
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    if (other is ASTValue) {
      var context = VMContext.getCurrent();
      var v1 = _getValueSafe(context, this);
      var v2 = _getValueSafe(context, other);
      return v1 == v2;
    }
    return false;
  }

  @override
  int get hashCode {
    var context = VMContext.getCurrent();
    var v1 = _getValueSafe(context, this);
    return v1.hashCode;
  }

  FutureOr<bool> equals(Object other) async {
    if (identical(this, other)) return true;

    if (other is ASTValue) {
      var context = VMContext.getCurrent();
      var v1 = await _getValue(context, this);
      var v2 = await _getValue(context, other);
      return v1 == v2;
    }
    return false;
  }

  FutureOr<bool> operator >(Object other) async {
    if (other is ASTValue) {
      var context = VMContext.getCurrent();
      var v1 = await _getValue(context, this);
      var v2 = await _getValue(context, other);
      if (v1 is num && v2 is num) {
        return v1 > v2;
      }
      throw UnsupportedError(
          "Can't perform operation '>' in non number values: $v1 > $v2");
    }
    return false;
  }

  FutureOr<bool> operator <(Object other) async {
    if (other is ASTValue) {
      var context = VMContext.getCurrent();
      var v1 = await _getValue(context, this);
      var v2 = await _getValue(context, other);
      if (v1 is num && v2 is num) {
        return v1 < v2;
      }
      throw UnsupportedError(
          "Can't perform operation '<' in non number values: $v1 < $v2");
    }
    return false;
  }

  FutureOr<bool> operator >=(Object other) async {
    if (other is ASTValue) {
      var context = VMContext.getCurrent();
      var v1 = await _getValue(context, this);
      var v2 = await _getValue(context, other);
      if (v1 is num && v2 is num) {
        return v1 >= v2;
      }
      throw UnsupportedError(
          "Can't perform operation '>=' in non number values: $v1 >= $v2");
    }
    return false;
  }

  FutureOr<bool> operator <=(Object other) async {
    if (other is ASTValue) {
      var context = VMContext.getCurrent();
      var v1 = await _getValue(context, this);
      var v2 = await _getValue(context, other);
      if (v1 is num && v2 is num) {
        return v1 <= v2;
      }
      throw UnsupportedError(
          "Can't perform operation '<=' in non number values: $v1 <= $v2");
    }
    return false;
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
  String toString();
}

/// Static [ASTValue]. Useful for literals.
class ASTValueStatic<T> extends ASTValue<T> {
  T value;

  ASTValueStatic(super.type, this.value);

  @override
  Iterable<ASTNode> get children {
    final value = this.value;
    return [if (value is ASTNode) value];
  }

  @override
  T getValue(VMContext context) => value;

  @override
  T getValueNoContext() => value;

  @override
  ASTValue<T> resolve(VMContext context) {
    return this;
  }

  @override
  V readIndex<V>(VMContext context, int index) {
    final value = this.value;

    if (value is List) {
      return value[index] as V;
    } else if (value is Iterable) {
      return value.elementAt(index);
    } else if (value is Map) {
      var entry = value.entries.elementAt(index);
      return entry.value;
    }

    throw ApolloVMNullPointerException(
        "Can't read index '$index': type: $type ; value: $value");
  }

  @override
  V readKey<V>(VMContext context, Object key) {
    final value = this.value;

    if (value is Map) {
      return value[key];
    } else if (value is Iterable) {
      var idx = key is int ? key : int.tryParse('$key');
      if (idx != null) {
        return value.elementAt(idx);
      }
    }

    throw ApolloVMNullPointerException(
        "Can't read key '$key': type: $type ; value: $value");
  }

  @override
  int? size(VMContext context) {
    var value = this.value;

    if (value is Iterable) {
      return value.length;
    }

    return null;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    if (other is ASTValueStatic) {
      return value == other.value;
    }

    return super == (other);
  }

  @override
  int get hashCode {
    return value.hashCode;
  }

  @override
  FutureOr<bool> equals(Object other) async {
    if (identical(this, other)) return true;

    if (other is ASTValueStatic) {
      return value == other.value;
    } else if (other is ASTValue) {
      var context = VMContext.getCurrent();
      var otherValue = await _getValue(context, other);
      return value == otherValue;
    }

    return super == (other);
  }

  @override
  String toString() {
    return '{type: $type, value: $value}';
  }
}

/// [ASTValue] for primitive types.
abstract class ASTValuePrimitive<T> extends ASTValueStatic<T> {
  ASTValuePrimitive(super.type, super.value);

  @override
  Iterable<ASTNode> get children => [];

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    if (other is ASTValuePrimitive) {
      return value == other.value;
    } else if (other is ASTValue) {
      var context = VMContext.getCurrent();
      var v2 = _getValue(context, other);
      if (v2 is Future) {
        throw StateError("Can't resolve a Future: $v2");
      }
      return value == v2;
    }

    return super == (other);
  }

  @override
  int get hashCode {
    return value.hashCode;
  }

  @override
  FutureOr<bool> equals(Object other) async {
    if (identical(this, other)) return true;

    if (other is ASTValuePrimitive) {
      return value == other.value;
    } else if (other is ASTValue) {
      var context = VMContext.getCurrent();
      var v2 = await _getValue(context, other);
      return value == v2;
    }

    return super == (other);
  }
}

/// [ASTValue] for booleans ([bool]).
class ASTValueBool extends ASTValuePrimitive<bool> {
  // ignore: non_constant_identifier_names
  static final ASTValueBool TRUE = ASTValueBool(true);

  // ignore: non_constant_identifier_names
  static final ASTValueBool FALSE = ASTValueBool(false);

  ASTValueBool(bool value) : super(ASTTypeBool.instance, value);

  static ASTValueBool from(dynamic o) {
    if (o is bool) return ASTValueBool(o);
    if (o is num) return ASTValueBool(o > 0);
    if (o is String) return from(parseBool(o.trim()));
    throw StateError("Can't parse boolean: $o");
  }
}

/// [ASTValue] for numbers ([num]).
abstract class ASTValueNum<T extends num> extends ASTValuePrimitive<T> {
  final bool negative;

  ASTValueNum(ASTType<T> type, T value, {bool? negative})
      : negative = negative ?? value.isNegative,
        super(
          type,
          negative != null
              ? (negative
                  ? (value.isNegative ? value : (-value as T))
                  : (value.isNegative ? (-value as T) : value))
              : value,
        ) {
    assert(this.value.isNegative == this.negative);
  }

  static ASTValueNum from(dynamic o, {bool? negative}) {
    if (o is int) {
      return ASTValueInt(o, negative: negative);
    } else if (o is double) {
      return ASTValueDouble(o, negative: negative);
    } else if (o is String) {
      return from(parseNum(o.trim()), negative: negative);
    }
    throw StateError("Can't parse number: $o");
  }

  bool get isZero => value == 0;

  @override
  FutureOr<ASTValue> operator +(ASTValue other);

  @override
  FutureOr<ASTValue> operator -(ASTValue other);

  @override
  FutureOr<ASTValue> operator /(ASTValue other);

  @override
  FutureOr<ASTValue> operator *(ASTValue other);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    if (other is ASTValueNum) {
      return value == other.value;
    } else if (other is ASTValue) {
      var context = VMContext.getCurrent();

      var t1 = resolveType(context);
      var t2 = other.resolveType(context);

      if (t1 != t2 && t1 is ASTType && t2 is ASTType && !t1.acceptsType(t2)) {
        return false;
      }

      var v2 = _getValueSafe(context, other);
      if (v2 is num) {
        return value == v2;
      }

      throw UnsupportedError(
          "Can't perform operation '==' in non number values: $value > $v2");
    }
    return false;
  }

  @override
  int get hashCode {
    return value.hashCode;
  }

  @override
  FutureOr<bool> equals(Object other) async {
    if (identical(this, other)) return true;

    if (other is ASTValueNum) {
      return value == other.value;
    } else if (other is ASTValue) {
      var context = VMContext.getCurrent();
      var v2 = await _getValue(context, other);
      return value == v2;
    }
    return false;
  }

  @override
  FutureOr<bool> operator >(Object other) async {
    if (other is ASTValueNum) {
      return value > other.value;
    } else if (other is ASTValue) {
      var context = VMContext.getCurrent();
      var v2 = await _getValue(context, other);
      return value > v2;
    }
    return false;
  }

  @override
  FutureOr<bool> operator <(Object other) async {
    if (other is ASTValueNum) {
      return value < other.value;
    } else if (other is ASTValue) {
      var context = VMContext.getCurrent();
      var v2 = await _getValue(context, other);
      return value < v2;
    }
    return false;
  }

  @override
  FutureOr<bool> operator >=(Object other) async {
    if (other is ASTValueNum) {
      return value >= other.value;
    } else if (other is ASTValue) {
      var context = VMContext.getCurrent();
      var v2 = await _getValue(context, other);
      return value >= v2;
    }
    return false;
  }

  @override
  FutureOr<bool> operator <=(Object other) async {
    if (other is ASTValueNum) {
      return value <= other.value;
    } else if (other is ASTValue) {
      var context = VMContext.getCurrent();
      var v2 = await _getValue(context, other);
      return value <= v2;
    }
    return false;
  }
}

/// [ASTValue] for integer ([int]).
class ASTValueInt extends ASTValueNum<int> {
  ASTValueInt(int n, {super.negative}) : super(ASTTypeInt.instance, n);

  @override
  ASTValue operator +(ASTValue other) {
    if (other is ASTValueInt) {
      return ASTValueInt(value + other.value);
    } else if (other is ASTValueDouble) {
      return ASTValueDouble(value + other.value);
    } else if (other is ASTValueString) {
      return ASTValueString('$value${other.value}');
    } else {
      throw UnsupportedValueOperationError(
          "Can't do '+' operation with: $other");
    }
  }

  @override
  ASTValue operator -(ASTValue other) {
    if (other is ASTValueInt) {
      return ASTValueInt(value - other.value);
    } else if (other is ASTValueDouble) {
      return ASTValueDouble(value - other.value);
    } else {
      throw UnsupportedValueOperationError(
          "Can't do '-' operation with: $other");
    }
  }

  @override
  ASTValue operator /(ASTValue other) {
    if (other is ASTValueInt) {
      return ASTValueDouble(value / other.value);
    } else if (other is ASTValueDouble) {
      return ASTValueDouble(value / other.value);
    } else {
      throw UnsupportedValueOperationError(
          "Can't do '/' operation with: $other");
    }
  }

  @override
  ASTValue operator *(ASTValue other) {
    if (other is ASTValueInt) {
      return ASTValueInt(value * other.value);
    } else if (other is ASTValueDouble) {
      return ASTValueDouble(value * other.value);
    } else {
      throw UnsupportedValueOperationError(
          "Can't do '*' operation with: $other");
    }
  }

  @override
  String toString() {
    return '(int) $value';
  }
}

/// [ASTValue] for [double].
class ASTValueDouble extends ASTValueNum<double> {
  ASTValueDouble(double n, {super.negative}) : super(ASTTypeDouble.instance, n);

  @override
  ASTValue operator +(ASTValue other) {
    if (other is ASTValueInt) {
      return ASTValueDouble(value + other.value);
    } else if (other is ASTValueDouble) {
      return ASTValueDouble(value + other.value);
    } else if (other is ASTValueString) {
      return ASTValueString('$value${other.value}');
    } else {
      throw UnsupportedValueOperationError(
          "Can't do '+' operation with: $other");
    }
  }

  @override
  ASTValueDouble operator -(ASTValue other) {
    if (other is ASTValueInt) {
      return ASTValueDouble(value - other.value);
    } else if (other is ASTValueDouble) {
      return ASTValueDouble(value - other.value);
    } else {
      throw UnsupportedValueOperationError(
          "Can't do '-' operation with: $other");
    }
  }

  @override
  ASTValueDouble operator /(ASTValue other) {
    if (other is ASTValueInt) {
      return ASTValueDouble(value / other.value);
    } else if (other is ASTValueDouble) {
      return ASTValueDouble(value / other.value);
    } else {
      throw UnsupportedValueOperationError(
          "Can't do '/' operation with: $other");
    }
  }

  @override
  ASTValueDouble operator *(ASTValue other) {
    if (other is ASTValueInt) {
      return ASTValueDouble(value * other.value);
    } else if (other is ASTValueDouble) {
      return ASTValueDouble(value * other.value);
    } else {
      throw UnsupportedValueOperationError(
          "Can't do '*' operation with: $other");
    }
  }

  @override
  String toString() {
    return '(double) $value';
  }
}

/// [ASTValue] for [String].
class ASTValueString extends ASTValuePrimitive<String> {
  ASTValueString(String s) : super(ASTTypeString.instance, s);

  @override
  bool operator >(Object other) {
    throw UnsupportedError(
        "Can't perform operation '>' in non number values: $this > $other");
  }

  @override
  bool operator <(Object other) {
    throw UnsupportedError(
        "Can't perform operation '<' in non number values: $this > $other");
  }

  @override
  bool operator >=(Object other) {
    throw UnsupportedError(
        "Can't perform operation '>=' in non number values: $this > $other");
  }

  @override
  bool operator <=(Object other) {
    throw UnsupportedError(
        "Can't perform operation '<=' in non number values: $this > $other");
  }

  @override
  String toString() {
    return '"$value"';
  }
}

/// [ASTValue] for [Object].
class ASTValueObject extends ASTValueStatic<Object> {
  ASTValueObject(Object o) : super(ASTTypeObject.instance, o);
}

/// [ASTValue] for `null`.
// ignore: prefer_void_to_null
class ASTValueNull extends ASTValueStatic<Null> {
  ASTValueNull() : super(ASTTypeNull.instance, null);

  static final ASTValueNull instance = ASTValueNull();

  @override
  bool operator ==(Object other) {
    return other is ASTValueNull;
  }

  @override
  int get hashCode {
    return -1;
  }

  @override
  FutureOr<bool> equals(Object other) {
    return other is ASTValueNull;
  }

  @override
  String toString() {
    return 'null';
  }
}

/// [ASTValue] for `void`.
class ASTValueVoid extends ASTValueStatic<void> {
  ASTValueVoid() : super(ASTTypeVoid.instance, null);

  static final ASTValueVoid instance = ASTValueVoid();

  @override
  bool operator ==(Object other) {
    return other is ASTValueVoid;
  }

  @override
  int get hashCode {
    return -2;
  }

  @override
  FutureOr<bool> equals(Object other) {
    return other is ASTValueVoid;
  }

  @override
  String toString() {
    return 'void';
  }
}

/// [ASTValue] for an array/[List].
class ASTValueArray<T extends ASTType<V>, V> extends ASTValueStatic<List<V>> {
  ASTValueArray(T type, List<V> value) : super(ASTTypeArray<T, V>(type), value);

  static final ListEquality _listEquality = const ListEquality();

  @override
  FutureOr<bool> equals(Object other) async {
    if (identical(this, other)) return true;

    if (other is ASTValueArray) {
      var context = VMContext.getCurrent();
      var v1 = await _getValue(context, this);
      var v2 = await _getValue(context, other);
      return _listEquality.equals(v1, v2);
    }
    return super == (other);
  }
}

/// [ASTValue] for a 2D array/[List].
class ASTValueArray2D<T extends ASTType<V>, V>
    extends ASTValueArray<ASTTypeArray<T, V>, List<V>> {
  ASTValueArray2D(T type, List<List<V>> value)
      : super(ASTTypeArray<T, V>(type), value);

  static final DeepCollectionEquality _listEquality =
      const DeepCollectionEquality();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    if (other is ASTValueArray2D) {
      var context = VMContext.getCurrent();
      var v1 = _getValue(context, this);
      var v2 = _getValue(context, other);
      return _listEquality.equals(v1, v2);
    }
    return super == (other);
  }

  @override
  int get hashCode {
    var context = VMContext.getCurrent();
    var v1 = _getValue(context, this);
    return _listEquality.hash(v1);
  }
}

/// [ASTValue] for a 3D array/[List].
class ASTValueArray3D<T extends ASTType<V>, V>
    extends ASTValueArray2D<ASTTypeArray<T, V>, List<V>> {
  ASTValueArray3D(T type, List<List<List<V>>> value)
      : super(ASTTypeArray<T, V>(type), value);
}

/// [ASTValue] for a [Map].
class ASTValueMap<TK extends ASTType<K>, TV extends ASTType<V>, K, V>
    extends ASTValueStatic<Map<K, V>> {
  ASTValueMap(TK keyType, TV valueType, Map<K, V> value)
      : super(ASTTypeMap<TK, TV, K, V>(keyType, valueType), value);

  static final MapEquality _mapEquality = const MapEquality();

  @override
  FutureOr<bool> equals(Object other) async {
    if (identical(this, other)) return true;

    if (other is ASTValueMap) {
      var context = VMContext.getCurrent();
      var v1 = await _getValue(context, this);
      var v2 = await _getValue(context, other);
      return _mapEquality.equals(v1, v2);
    }
    return super == (other);
  }
}

/// [ASTValue] declared with `var`.
class ASTValueVar extends ASTValueStatic<dynamic> {
  ASTValueVar(Object o) : super(ASTTypeVar.instance, o);
}

/// [ASTValue] that should be converted to [String].
class ASTValueAsString<T> extends ASTValue<String> {
  ASTValue<T> value;

  ASTValueAsString(this.value) : super(ASTTypeString.instance);

  @override
  Iterable<ASTNode> get children => [value];

  @override
  FutureOr<String> getValue(VMContext context) {
    return value.getValue(context).resolveMapped((v) => '$v');
  }

  @override
  FutureOr<String> getValueNoContext() {
    return value.getValueNoContext().resolveMapped((v) => '$v');
  }

  @override
  FutureOr<ASTValue<String>> resolve(VMContext context) {
    return getValue(context).resolveMapped((v) => ASTValueString(v));
  }
}

/// [ASTValue] for lists that should be converted to [String].
class ASTValuesListAsString extends ASTValue<String> {
  List<ASTValue> values;

  ASTValuesListAsString(this.values) : super(ASTTypeString.instance);

  @override
  Iterable<ASTNode> get children => [...values];

  @override
  FutureOr<String> getValue(VMContext context) {
    var vsFuture = values.map((e) {
      var val = e.resolve(context).resolveMapped((v) => v.getValue(context));
      return val.resolveMapped((v) => '$v');
    }).toList();
    return vsFuture.resolveAllJoined((l) => l.join());
  }

  @override
  FutureOr<String> getValueNoContext() {
    var vsFuture = values.map((e) => e.resolveMapped((v) => '$v')).toList();
    return vsFuture.resolveAllJoined((l) => l.join());
  }

  @override
  FutureOr<ASTValueString> resolve(VMContext context) {
    var value = getValue(context);
    return value.resolveMapped((v) => ASTValueString(v));
  }
}

/// [ASTValue] for expressions that should be converted to [String].
class ASTValueStringExpression<T> extends ASTValue<String> {
  final ASTExpression expression;

  ASTValueStringExpression(this.expression) : super(ASTTypeString.instance);

  @override
  Iterable<ASTNode> get children => [expression];

  @override
  FutureOr<String> getValue(VMContext context) {
    var res = expression
        .run(context, ASTRunStatus())
        .resolveMapped((result) => result.getValue(context))
        .resolveMapped((res) => '$res');
    return res;
  }

  @override
  FutureOr<String> getValueNoContext() => throw UnsupportedError(
      "Can't define an expression value without a context!");

  @override
  FutureOr<ASTValueString> resolve(VMContext context) {
    return getValue(context).resolveMapped((s) => ASTValueString(s));
  }

  @override
  String toString() {
    return '"\${ $expression }"';
  }
}

/// [ASTValue] for a variable that should resolved and converted to [String].
class ASTValueStringVariable<T> extends ASTValue<String> {
  final ASTVariable variable;

  ASTValueStringVariable(this.variable) : super(ASTTypeString.instance);

  @override
  Iterable<ASTNode> get children => [];

  @override
  FutureOr<String> getValue(VMContext context) {
    return variable.getValue(context).resolveMapped((value) {
      return value.getValue(context).resolveMapped((v) => '$v');
    });
  }

  @override
  String getValueNoContext() => throw UnsupportedError(
      "Can't define an variable value without a context!");

  @override
  FutureOr<ASTValue<String>> resolve(VMContext context) {
    return variable.getValue(context).resolveMapped((value) {
      return value is ASTValue<String> ? value : ASTValueAsString(value);
    });
  }

  @override
  String toString() {
    return '"\$$variable"';
  }
}

/// [ASTValue] for a concatenations of other [values].
class ASTValueStringConcatenation extends ASTValue<String> {
  final List<ASTValue<String>> values;

  ASTValueStringConcatenation(this.values) : super(ASTTypeString.instance);

  @override
  Iterable<ASTNode> get children => [...values];

  @override
  FutureOr<String> getValue(VMContext context) {
    var vsFuture = values.map((e) => e.getValue(context));
    return vsFuture.resolveAllJoined((l) => l.join());
  }

  @override
  FutureOr<String> getValueNoContext() {
    var vsFuture = values.map((e) => e.getValueNoContext()).toList();
    return vsFuture.resolveAllJoined((l) => l.join());
  }

  @override
  FutureOr<ASTValue<String>> resolve(VMContext context) {
    var vsFuture = values.map((e) => e.resolve(context));
    return vsFuture.resolveAllJoined((vs) => ASTValuesListAsString(vs));
  }

  @override
  String toString() {
    return values.join(' + ');
  }
}

/// [ASTValue] for a variable read index: `elem[1]`.
class ASTValueReadIndex<T> extends ASTValue<T> {
  final ASTVariable variable;
  final Object _index;

  ASTValueReadIndex(super.type, this.variable, this._index);

  @override
  Iterable<ASTNode> get children => [variable];

  @override
  FutureOr<ASTType> resolveType(VMContext? context) {
    return variable.resolveType(context).resolveMapped((type) {
      if (type.hasGenerics) {
        var generics = type.generics!;
        var generic = generics[0];
        return generic;
      }

      return ASTTypeDynamic.instance;
    });
  }

  int getIndex(VMContext context) {
    if (_index is int) {
      return _index;
    } else if (_index is ASTValue) {
      var idx = (_index).getValue(context);
      return parseInt(idx)!;
    } else {
      return parseInt(_index)!;
    }
  }

  @override
  FutureOr<T> getValue(VMContext context) {
    return variable.readIndex(context, getIndex(context));
  }

  @override
  T getValueNoContext() =>
      throw UnsupportedError("Can't define variable value without a context!");

  @override
  FutureOr<ASTValue<T>> resolve(VMContext context) {
    return getValue(context).resolveMapped((v) {
      return ASTValue.from(type, v);
    });
  }

  @override
  String toString() {
    return '{type: $type, value: $variable[$_index]}';
  }
}

/// [ASTValue] for a variable read key: `elem[k]`.
class ASTValueReadKey<T> extends ASTValue<T> {
  final ASTVariable variable;
  final Object _key;

  ASTValueReadKey(super.type, this.variable, this._key);

  @override
  Iterable<ASTNode> get children => [variable];

  @override
  FutureOr<ASTType> resolveType(VMContext? context) {
    return variable.resolveType(context).resolveMapped((type) {
      if (type.hasGenerics) {
        var generics = type.generics!;
        var generic = generics[Math.min(1, generics.length - 1)];

        return generic;
      }

      return ASTTypeDynamic.instance;
    });
  }

  FutureOr<Object> getKey(VMContext context) {
    if (_key is ASTValue) {
      return (_key).getValue(context).resolveMapped((v) => v as Object);
    } else {
      return _key;
    }
  }

  @override
  FutureOr<T> getValue(VMContext context) {
    var key = getKey(context);
    return variable.readKey(context, key);
  }

  @override
  T getValueNoContext() =>
      throw UnsupportedError("Can't define variable value without a context!");

  @override
  FutureOr<ASTValue<T>> resolve(VMContext context) {
    return getValue(context).resolveMapped((v) {
      return ASTValue.from(type, v);
    });
  }

  @override
  String toString() {
    return '{type: $type, value: $variable[$_key]}';
  }
}

/// [ASTValue] for an object class instance.
class ASTClassInstance<V extends ASTValue> extends ASTValue<V> {
  final ASTClass<V> clazz;
  final V _object;

  ASTClassInstance(this.clazz, this._object) : super(clazz.type) {
    if (type.name != clazz.name) {
      throw StateError('Incompatible class with type: $clazz != $type');
    }
  }

  @override
  Iterable<ASTNode> get children => [_object];

  @override
  ASTType resolveType(VMContext? context) => clazz.type;

  /// The internal [VMObject] of this instance.
  V get vmObject => _object;

  @override
  V getValue(VMContext context) => _object;

  @override
  V getValueNoContext() => _object;

  @override
  ASTClassInstance<V> resolve(VMContext context) {
    return this;
  }

  FutureOr<ASTValue?> getField(VMClassContext context, String name,
          {bool caseInsensitive = false}) =>
      clazz.getInstanceFieldValue(context, ASTRunStatus(), this, name,
          caseInsensitive: caseInsensitive);

  FutureOr<ASTValue?> setField(
          VMClassContext context, String name, ASTValue value,
          {bool caseInsensitive = false}) =>
      clazz.setInstanceFieldValue(context, ASTRunStatus(), this, name, value,
          caseInsensitive: caseInsensitive);

  FutureOr<ASTValue?> removeField(VMClassContext context, String name,
          {bool caseInsensitive = false}) =>
      clazz.removeInstanceFieldValue(context, ASTRunStatus(), this, name,
          caseInsensitive: caseInsensitive);

  void setFields(VMClassContext context, Map<String, ASTValue> fieldsValues,
      {bool caseInsensitive = false}) {
    for (var entry in fieldsValues.entries) {
      setField(context, entry.key, entry.value,
          caseInsensitive: caseInsensitive);
    }
  }

  @override
  String toString() {
    return '$type$_object';
  }
}

/// [ASTValue] for static access of class methods and fields.
class ASTClassStaticAccessor<C extends ASTClass<V>, V> extends ASTValue<V> {
  final C clazz;

  final ASTStaticClassAccessorVariable<V> staticClassAccessorVariable;

  ASTClassStaticAccessor(this.clazz)
      : staticClassAccessorVariable = ASTStaticClassAccessorVariable(clazz),
        super(clazz.type) {
    if (type.name != clazz.name) {
      throw StateError('Incompatible class with type: $clazz != $type');
    }
    staticClassAccessorVariable.setAccessor(this);
  }

  @override
  Iterable<ASTNode> get children => [staticClassAccessorVariable];

  @override
  ASTType resolveType(VMContext? context) => clazz.type;

  @override
  V getValue(VMContext context) => getValueNoContext();

  @override
  V getValueNoContext() =>
      throw UnsupportedError('Static accessor for class $clazz');

  @override
  ASTClassStaticAccessor<C, V> resolve(VMContext context) {
    return this;
  }

  FutureOr<ASTValue?> getField(VMClassContext context, String name,
          {bool caseInsensitive = false}) =>
      clazz.getInstanceFieldValue(context, ASTRunStatus(), this, name,
          caseInsensitive: caseInsensitive);

  FutureOr<ASTValue?> setField(
          VMClassContext context, String name, ASTValue value,
          {bool caseInsensitive = false}) =>
      clazz.setInstanceFieldValue(context, ASTRunStatus(), this, name, value,
          caseInsensitive: caseInsensitive);

  FutureOr<ASTValue?> removeField(VMClassContext context, String name,
          {bool caseInsensitive = false}) =>
      clazz.removeInstanceFieldValue(context, ASTRunStatus(), this, name,
          caseInsensitive: caseInsensitive);

  void setFields(VMClassContext context, Map<String, ASTValue> fieldsValues,
      {bool caseInsensitive = false}) {
    for (var entry in fieldsValues.entries) {
      setField(context, entry.key, entry.value,
          caseInsensitive: caseInsensitive);
    }
  }

  @override
  String toString() {
    return '$clazz';
  }
}

/// [ASTValue] for a [Future].
class ASTValueFuture<T extends ASTType<V>, V> extends ASTValue<Future<V>> {
  Future<V> future;

  ASTValueFuture(ASTType type, this.future)
      : super(type is ASTTypeFuture
            ? type as ASTTypeFuture<T, V>
            : ASTTypeFuture<T, V>(type as T));

  @override
  Iterable<ASTNode> get children => [];

  @override
  Future<V> getValue(VMContext context) => future;

  @override
  Future<V> getValueNoContext() => future;

  @override
  ASTValueFuture<T, V> resolve(VMContext context) {
    return this;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    if (other is ASTValueFuture) {
      return future == other.future;
    }

    return super == (other);
  }

  @override
  int get hashCode {
    return future.hashCode;
  }

  @override
  FutureOr<bool> equals(Object other) async {
    if (identical(this, other)) return true;

    if (other is ASTValueFuture) {
      var v1 = await future;
      var v2 = await other.future;
      return v1 == v2;
    } else if (other is ASTValue) {
      var context = VMContext.getCurrent()!;
      var v1 = await future;
      var v2 = await other.getValue(context);
      return v1 == v2;
    }

    return super == (other);
  }
}
