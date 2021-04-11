import 'dart:async';

import 'package:apollovm/apollovm.dart';
import 'package:collection/collection.dart'
    show ListEquality, DeepCollectionEquality;
import 'package:swiss_knife/swiss_knife.dart';

import 'apollovm_ast_expression.dart';
import 'apollovm_ast_type.dart';
import 'apollovm_ast_variable.dart';

abstract class ASTValue<T> implements ASTNode {
  factory ASTValue.from(ASTType<T> type, T value) {
    if (type is ASTTypeString) {
      return ASTValueString(value as String) as ASTValue<T>;
    } else if (type is ASTTypeInt) {
      return ASTValueInt(value as int) as ASTValue<T>;
    } else if (type is ASTTypeDouble) {
      return ASTValueDouble(value as double) as ASTValue<T>;
    } else if (type is ASTTypeNull) {
      return ASTValueNull.INSTANCE as ASTValue<T>;
    } else if (type is ASTTypeObject) {
      return ASTValueObject(value!) as ASTValue<T>;
    } else if (type is ASTTypeVoid) {
      return ASTValueVoid.INSTANCE as ASTValue<T>;
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
    if (o == null) return ASTValueNull.INSTANCE;

    if (o is String) return ASTValueString(o);
    if (o is int) return ASTValueInt(o);
    if (o is double) return ASTValueDouble(o);

    var t = ASTType.from(o);
    return ASTValueStatic(t, o);
  }

  ASTType<T> type;

  FutureOr<T> getValue(VMContext context);

  FutureOr<T> getValueNoContext();

  FutureOr<ASTValue<T>> resolve(VMContext context);

  ASTValue(this.type);

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

  FutureOr<T> _getValue(VMContext? context, ASTValue v) =>
      context != null ? v.getValue(context) as T : v.getValueNoContext() as T;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    if (other is ASTValue) {
      var context = VMContext.getCurrent();
      var v1 = _getValue(context, this);
      var v2 = _getValue(context, other);
      if (v1 is Future || v2 is Future) {
        throw StateError("Can't compare Future");
      }
      return v1 == v2;
    }
    return false;
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

  @override
  String toString();
}

class ASTValueStatic<T> extends ASTValue<T> {
  T value;

  ASTValueStatic(ASTType<T> type, this.value) : super(type);

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
    if (value is List) {
      var list = value as List;
      return list[index] as V;
    } else if (value is Iterable) {
      var it = value as Iterable;

      var idx = 0;
      for (var e in it) {
        if (idx == index) {
          return e;
        }
        idx++;
      }

      throw RangeError.index(index, it);
    }

    throw ApolloVMNullPointerException(
        "Can't read index '$index': type: $type ; value: $value");
  }

  @override
  V readKey<V>(VMContext context, Object key) {
    if (value is Map) {
      var map = value as Map;
      return map[key];
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

abstract class ASTValuePrimitive<T> extends ASTValueStatic<T> {
  ASTValuePrimitive(ASTType<T> type, T value) : super(type, value);

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

class ASTValueBool extends ASTValuePrimitive<bool> {
  ASTValueBool(bool value) : super(ASTTypeBool.INSTANCE, value);

  static ASTValueBool from(dynamic o) {
    if (o is bool) return ASTValueBool(o);
    if (o is num) return ASTValueBool(o > 0);
    if (o is String) return from(parseBool(o.trim()));
    throw StateError("Can't parse boolean: $o");
  }
}

abstract class ASTValueNum<T extends num> extends ASTValuePrimitive<T> {
  ASTValueNum(ASTType<T> type, T value) : super(type, value);

  static ASTValueNum from(dynamic o) {
    if (o is int) return ASTValueInt(o);
    if (o is double) return ASTValueDouble(o);
    if (o is String) return from(parseNum(o.trim()));
    throw StateError("Can't parse number: $o");
  }

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
      var v2 = _getValue(context, other);
      if (v2 is num) {
        return value == v2;
      }
      throw UnsupportedError(
          "Can't perform operation '==' in non number values: $value > $v2");
    }
    return false;
  }

  @override
  FutureOr<bool> equals(Object other) async {
    if (identical(this, other)) return true;

    if (other is ASTValueNum) {
      return value == other.value;
    } else if (other is ASTValue) {
      var context = VMContext.getCurrent();
      var v2 = await _getValue(context, other);
      if (v2 is num) {
        return value == v2;
      }
      throw UnsupportedError(
          "Can't perform operation '==' in non number values: $value > $v2");
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
      if (v2 is num) {
        return value > v2;
      }
      throw UnsupportedError(
          "Can't perform operation '>' in non number values: $value > $v2");
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
      if (v2 is num) {
        return value < v2;
      }
      throw UnsupportedError(
          "Can't perform operation '<' in non number values: $value > $v2");
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
      if (v2 is num) {
        return value >= v2;
      }
      throw UnsupportedError(
          "Can't perform operation '>=' in non number values: $value > $v2");
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
      if (v2 is num) {
        return value <= v2;
      }
      throw UnsupportedError(
          "Can't perform operation '<=' in non number values: $value > $v2");
    }
    return false;
  }
}

class ASTValueInt extends ASTValueNum<int> {
  ASTValueInt(int n) : super(ASTTypeInt.INSTANCE, n);

  @override
  ASTValue operator +(ASTValue other) {
    if (other is ASTValueInt) {
      return ASTValueInt(value + other.value);
    } else if (other is ASTValueDouble) {
      return ASTValueDouble(value + other.value);
    } else if (other is ASTValueString) {
      return ASTValueString('$value' + other.value);
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

class ASTValueDouble extends ASTValueNum<double> {
  ASTValueDouble(double n) : super(ASTTypeDouble.INSTANCE, n);

  @override
  ASTValue operator +(ASTValue other) {
    if (other is ASTValueInt) {
      return ASTValueDouble(value + other.value);
    } else if (other is ASTValueDouble) {
      return ASTValueDouble(value + other.value);
    } else if (other is ASTValueString) {
      return ASTValueString('$value' + other.value);
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

class ASTValueString extends ASTValuePrimitive<String> {
  ASTValueString(String s) : super(ASTTypeString.INSTANCE, s);

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
    return '(String) $value';
  }
}

class ASTValueObject extends ASTValueStatic<Object> {
  ASTValueObject(Object o) : super(ASTTypeObject.INSTANCE, o);
}

class ASTValueNull extends ASTValueStatic<Null> {
  ASTValueNull() : super(ASTTypeNull.INSTANCE, null);

  static final ASTValueNull INSTANCE = ASTValueNull();

  @override
  bool operator ==(Object other) {
    return other is ASTValueNull;
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

class ASTValueVoid extends ASTValueStatic<void> {
  ASTValueVoid() : super(ASTTypeVoid.INSTANCE, null);

  static final ASTValueVoid INSTANCE = ASTValueVoid();

  @override
  bool operator ==(Object other) {
    return other is ASTValueVoid;
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
}

class ASTValueArray3D<T extends ASTType<V>, V>
    extends ASTValueArray2D<ASTTypeArray<T, V>, List<V>> {
  ASTValueArray3D(T type, List<List<List<V>>> value)
      : super(ASTTypeArray<T, V>(type), value);
}

class ASTValueVar extends ASTValueStatic<dynamic> {
  ASTValueVar(Object o) : super(ASTTypeVar.INSTANCE, o);
}

class ASTValueAsString<T> extends ASTValue<String> {
  ASTValue<T> value;

  ASTValueAsString(this.value) : super(ASTTypeString.INSTANCE);

  @override
  FutureOr<String> getValue(VMContext context) async {
    var v = await value.getValue(context);
    return '$v';
  }

  @override
  FutureOr<String> getValueNoContext() async {
    var v = await value.getValueNoContext();
    return '$v';
  }

  @override
  FutureOr<ASTValue<String>> resolve(VMContext context) async {
    var value = await getValue(context);
    return ASTValueString(value);
  }
}

class ASTValuesListAsString extends ASTValue<String> {
  List<ASTValue> values;

  ASTValuesListAsString(this.values) : super(ASTTypeString.INSTANCE);

  @override
  FutureOr<String> getValue(VMContext context) async {
    var vsFuture = values.map((e) async {
      var resolved = await e.resolve(context);
      var v = await resolved.getValue(context);
      return '$v';
    });
    var vs = await Future.wait(vsFuture);
    return vs.join();
  }

  @override
  FutureOr<String> getValueNoContext() async {
    var vsFuture = values.map((e) async {
      var v = await e.getValueNoContext();
      return '$v';
    });
    var vs = await Future.wait(vsFuture);
    return vs.join();
  }

  @override
  FutureOr<ASTValueString> resolve(VMContext context) async {
    var value = await getValue(context);
    return ASTValueString(value);
  }
}

class ASTValueStringExpresion<T> extends ASTValue<String> {
  final ASTExpression expression;

  ASTValueStringExpresion(this.expression) : super(ASTTypeString.INSTANCE);

  @override
  FutureOr<String> getValue(VMContext context) async {
    var result = await expression.run(context, ASTRunStatus());
    var res = await result.getValue(context);
    return '$res';
  }

  @override
  FutureOr<String> getValueNoContext() => throw UnsupportedError(
      "Can't define an expression value without a context!");

  @override
  FutureOr<ASTValueString> resolve(VMContext context) async {
    var s = await getValue(context);
    return ASTValueString(s);
  }
}

class ASTValueStringVariable<T> extends ASTValue<String> {
  final ASTVariable variable;

  ASTValueStringVariable(this.variable) : super(ASTTypeString.INSTANCE);

  @override
  FutureOr<String> getValue(VMContext context) async {
    var value = await variable.getValue(context);
    var v = await value.getValue(context);
    return '$v';
  }

  @override
  String getValueNoContext() => throw UnsupportedError(
      "Can't define an variable value without a context!");

  @override
  FutureOr<ASTValue<String>> resolve(VMContext context) async {
    var value = await variable.getValue(context);
    return value is ASTValue<String> ? value : ASTValueAsString(value);
  }
}

class ASTValueStringConcatenation extends ASTValue<String> {
  final List<ASTValue<String>> values;

  ASTValueStringConcatenation(this.values) : super(ASTTypeString.INSTANCE);

  @override
  FutureOr<String> getValue(VMContext context) async {
    var vsFuture = values.map((e) async {
      return await e.getValue(context);
    }).toList();
    var vs = await Future.wait(vsFuture);
    return vs.join();
  }

  @override
  FutureOr<String> getValueNoContext() async {
    var vsFuture = values.map((e) async {
      return await e.getValueNoContext();
    }).toList();
    var vs = await Future.wait(vsFuture);
    return vs.join();
  }

  @override
  FutureOr<ASTValue<String>> resolve(VMContext context) async {
    var vsFuture = values.map((e) async {
      return await e.resolve(context);
    }).toList();
    var vs = await Future.wait(vsFuture);
    return ASTValuesListAsString(vs);
  }
}

class ASTValueReadIndex<T> extends ASTValue<T> {
  final ASTVariable variable;
  final Object _index;

  ASTValueReadIndex(ASTType<T> type, this.variable, this._index) : super(type);

  int getIndex(VMContext context) {
    if (_index is int) {
      return _index as int;
    } else if (_index is ASTValue) {
      var idx = (_index as ASTValue).getValue(context);
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
  FutureOr<ASTValue<T>> resolve(VMContext context) async {
    var v = await getValue(context);
    return ASTValue.from(type, v);
  }

  @override
  String toString() {
    return '{type: $type, value: $variable[$_index]}';
  }
}

class ASTValueReadKey<T> extends ASTValue<T> {
  final ASTVariable variable;
  final Object _key;

  ASTValueReadKey(ASTType<T> type, this.variable, this._key) : super(type);

  FutureOr<Object> getKey(VMContext context) async {
    if (_key is ASTValue) {
      return await (_key as ASTValue).getValue(context);
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
  FutureOr<ASTValue<T>> resolve(VMContext context) async {
    var v = await getValue(context);
    return ASTValue.from(type, v);
  }

  @override
  String toString() {
    return '{type: $type, value: $variable[$_key]}';
  }
}

class ASTObjectInstance extends ASTValue<VMObject> {
  final ASTClass clazz;
  final VMObject _object;

  ASTObjectInstance(this.clazz)
      : _object = VMObject(clazz.type),
        super(clazz.type) {
    if (type.name != clazz.name) {
      throw StateError('Incompatible class with type: $clazz != $type');
    }
  }

  @override
  VMObject getValue(VMContext context) => _object;

  @override
  VMObject getValueNoContext() => _object;

  @override
  ASTValue<VMObject> resolve(VMContext context) {
    return this;
  }

  ASTRuntimeVariable? getField(String name) => _object[name];

  ASTRuntimeVariable? setField(String name, ASTValue value) {
    var field = clazz.getField(name);
    if (field == null) throw StateError("No field '$name' in class $clazz");

    var prev = _object[name];
    _object[name] = ASTRuntimeVariable(field.type, name, value);
    return prev;
  }

  @override
  String toString() {
    return '$type$_object';
  }
}

class ASTValueFuture<T extends ASTType<V>, V> extends ASTValue<Future<V>> {
  Future<V> future;

  ASTValueFuture(ASTType type, this.future)
      : super(type is ASTTypeFuture
            ? type as ASTTypeFuture<T, V>
            : ASTTypeFuture<T, V>(type as T));

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
