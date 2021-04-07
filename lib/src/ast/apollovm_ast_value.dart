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

  T getValue(VMContext context);

  T getValueNoContext();

  ASTValue<T> resolve(VMContext context);

  ASTValue(this.type);

  V readIndex<V>(VMContext context, int index) {
    throw UnsupportedError("Can't read index for type: $type");
  }

  V readKey<V>(VMContext context, Object key) {
    throw UnsupportedError("Can't read key for type: $type");
  }

  int? size(VMContext context) => null;

  ASTValue operator +(ASTValue other) =>
      throw UnsupportedValueOperationError('+');

  ASTValue operator -(ASTValue other) =>
      throw UnsupportedValueOperationError('+');

  ASTValue operator /(ASTValue other) =>
      throw UnsupportedValueOperationError('+');

  ASTValue operator *(ASTValue other) =>
      throw UnsupportedValueOperationError('+');

  ASTValue operator ~/(ASTValue other) =>
      throw UnsupportedValueOperationError('+');

  T _getValue(VMContext? context, ASTValue v) =>
      context != null ? v.getValue(context) : v.getValueNoContext();

  @override
  bool operator ==(Object other) {
    if (other is ASTValue) {
      var context = VMContext.getCurrent();
      var v1 = _getValue(context, this);
      var v2 = _getValue(context, other);
      return v1 == v2;
    }
    return false;
  }

  bool operator >(Object other) {
    if (other is ASTValue) {
      var context = VMContext.getCurrent();
      var v1 = _getValue(context, this);
      var v2 = _getValue(context, other);
      if (v1 is num && v2 is num) {
        return v1 > v2;
      }
      throw UnsupportedError(
          "Can't perform operation '>' in non number values: $v1 > $v2");
    }
    return false;
  }

  bool operator <(Object other) {
    if (other is ASTValue) {
      var context = VMContext.getCurrent();
      var v1 = _getValue(context, this);
      var v2 = _getValue(context, other);
      if (v1 is num && v2 is num) {
        return v1 < v2;
      }
      throw UnsupportedError(
          "Can't perform operation '<' in non number values: $v1 < $v2");
    }
    return false;
  }

  bool operator >=(Object other) {
    if (other is ASTValue) {
      var context = VMContext.getCurrent();
      var v1 = _getValue(context, this);
      var v2 = _getValue(context, other);
      if (v1 is num && v2 is num) {
        return v1 >= v2;
      }
      throw UnsupportedError(
          "Can't perform operation '>=' in non number values: $v1 >= $v2");
    }
    return false;
  }

  bool operator <=(Object other) {
    if (other is ASTValue) {
      var context = VMContext.getCurrent();
      var v1 = _getValue(context, this);
      var v2 = _getValue(context, other);
      if (v1 is num && v2 is num) {
        return v1 <= v2;
      }
      throw UnsupportedError(
          "Can't perform operation '<=' in non number values: $v1 <= $v2");
    }
    return false;
  }
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
    if (other is ASTValueStatic) {
      return value == other.value;
    }
    return super == (other);
  }

  @override
  bool operator >(Object other) {
    if (other is ASTValueStatic) {
      return value == other.value;
    }
    return super > (other);
  }
}

abstract class ASTValuePrimitive<T> extends ASTValueStatic<T> {
  ASTValuePrimitive(ASTType<T> type, T value) : super(type, value);

  @override
  bool operator ==(Object other) {
    if (other is ASTValuePrimitive) {
      var context = VMContext.getCurrent();
      var v1 = _getValue(context, this);
      var v2 = _getValue(context, other);
      return v1 == v2;
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
  ASTValue operator +(ASTValue other);

  @override
  ASTValue operator -(ASTValue other);

  @override
  ASTValue operator /(ASTValue other);

  @override
  ASTValue operator *(ASTValue other);

  @override
  bool operator ==(Object other) {
    if (other is ASTValueNum) {
      return value == other.value;
    }
    return super == (other);
  }

  @override
  bool operator >(Object other) {
    if (other is ASTValueNum) {
      var context = VMContext.getCurrent();
      var v1 = _getValue(context, this);
      var v2 = _getValue(context, other);
      if (v1 is num && v2 is num) {
        return v1 > v2;
      }
      throw UnsupportedError(
          "Can't perform operation '>' in non number values: $v1 > $v2");
    }
    return false;
  }

  @override
  bool operator <(Object other) {
    if (other is ASTValueNum) {
      var context = VMContext.getCurrent();
      var v1 = _getValue(context, this);
      var v2 = _getValue(context, other);
      if (v1 is num && v2 is num) {
        return v1 < v2;
      }
      throw UnsupportedError(
          "Can't perform operation '<' in non number values: $v1 < $v2");
    }
    return false;
  }

  @override
  bool operator >=(Object other) {
    if (other is ASTValueNum) {
      var context = VMContext.getCurrent();
      var v1 = _getValue(context, this);
      var v2 = _getValue(context, other);
      if (v1 is num && v2 is num) {
        return v1 >= v2;
      }
      throw UnsupportedError(
          "Can't perform operation '>=' in non number values: $v1 >= $v2");
    }
    return false;
  }

  @override
  bool operator <=(Object other) {
    if (other is ASTValueNum) {
      var context = VMContext.getCurrent();
      var v1 = _getValue(context, this);
      var v2 = _getValue(context, other);
      if (v1 is num && v2 is num) {
        return v1 <= v2;
      }
      throw UnsupportedError(
          "Can't perform operation '<=' in non number values: $v1 <= $v2");
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
}

class ASTValueVoid extends ASTValueStatic<void> {
  ASTValueVoid() : super(ASTTypeVoid.INSTANCE, null);

  static final ASTValueVoid INSTANCE = ASTValueVoid();

  @override
  bool operator ==(Object other) {
    return other is ASTValueVoid;
  }
}

class ASTValueArray<T extends ASTType<V>, V> extends ASTValueStatic<List<V>> {
  ASTValueArray(T type, List<V> value) : super(ASTTypeArray<T, V>(type), value);

  static final ListEquality _listEquality = const ListEquality();

  @override
  bool operator ==(Object other) {
    if (other is ASTValueArray) {
      var context = VMContext.getCurrent();
      var v1 = _getValue(context, this);
      var v2 = _getValue(context, other);
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
  String getValue(VMContext context) {
    var v = value.getValue(context);
    return '$v';
  }

  @override
  String getValueNoContext() => value.getValueNoContext().toString();

  @override
  ASTValue<String> resolve(VMContext context) {
    return ASTValueString(getValue(context));
  }
}

class ASTValuesListAsString extends ASTValue<String> {
  List<ASTValue> values;

  ASTValuesListAsString(this.values) : super(ASTTypeString.INSTANCE);

  @override
  String getValue(VMContext context) {
    return values.map((e) {
      var v = e.resolve(context).getValue(context);
      return '$v';
    }).join();
  }

  @override
  String getValueNoContext() {
    return values.map((e) {
      var v = e.getValueNoContext();
      return '$v';
    }).join();
  }

  @override
  ASTValue<String> resolve(VMContext context) {
    return ASTValueString(getValue(context));
  }
}

class ASTValueStringExpresion<T> extends ASTValue<String> {
  final ASTExpression expression;

  ASTValueStringExpresion(this.expression) : super(ASTTypeString.INSTANCE);

  @override
  String getValue(VMContext context) {
    var res = expression.run(context, ASTRunStatus()).getValue(context);
    return '$res';
  }

  @override
  String getValueNoContext() => throw UnsupportedError(
      "Can't define an expression value without a context!");

  @override
  ASTValue<String> resolve(VMContext context) {
    var s = getValue(context);
    return ASTValueString(s);
  }
}

class ASTValueStringVariable<T> extends ASTValue<String> {
  final ASTVariable variable;

  ASTValueStringVariable(this.variable) : super(ASTTypeString.INSTANCE);

  @override
  String getValue(VMContext context) {
    var v = variable.getValue(context).getValue(context);
    return '$v';
  }

  @override
  String getValueNoContext() => throw UnsupportedError(
      "Can't define an variable value without a context!");

  @override
  ASTValue<String> resolve(VMContext context) {
    var value = variable.getValue(context);
    return value is ASTValue<String> ? value : ASTValueAsString(value);
  }
}

class ASTValueStringConcatenation extends ASTValue<String> {
  final List<ASTValue<String>> values;

  ASTValueStringConcatenation(this.values) : super(ASTTypeString.INSTANCE);

  @override
  String getValue(VMContext context) {
    var vs = values.map((e) => e.getValue(context)).toList();
    return vs.join();
  }

  @override
  String getValueNoContext() {
    var vs = values.map((e) => e.getValueNoContext()).toList();
    return vs.join();
  }

  @override
  ASTValue<String> resolve(VMContext context) {
    var vs = values.map((e) => e.resolve(context)).toList();
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
  T getValue(VMContext context) =>
      variable.readIndex(context, getIndex(context));

  @override
  T getValueNoContext() =>
      throw UnsupportedError("Can't define variable value without a context!");

  @override
  ASTValue<T> resolve(VMContext context) {
    var v = getValue(context);
    return ASTValue.from(type, v);
  }
}

class ASTValueReadKey<T> extends ASTValue<T> {
  final ASTVariable variable;
  final Object _key;

  ASTValueReadKey(ASTType<T> type, this.variable, this._key) : super(type);

  Object getKey(VMContext context) {
    if (_key is ASTValue) {
      return (_key as ASTValue).getValue(context);
    } else {
      return _key;
    }
  }

  @override
  T getValue(VMContext context) => variable.readKey(context, getKey(context));

  @override
  T getValueNoContext() =>
      throw UnsupportedError("Can't define variable value without a context!");

  @override
  ASTValue<T> resolve(VMContext context) {
    var v = getValue(context);
    return ASTValue.from(type, v);
  }
}

class ASTObjectValue<T> extends ASTValue<T> {
  final Map<String, ASTValue> _o = {};

  ASTObjectValue(ASTType<T> type) : super(type);

  @override
  T getValue(VMContext context) => _o as T;

  @override
  T getValueNoContext() => _o as T;

  @override
  ASTValue<T> resolve(VMContext context) {
    return this;
  }

  ASTValue? getField(String name) => _o[name];

  ASTValue? setField(String name, ASTValue value) {
    var prev = _o[name];
    _o[name] = value;
    return prev;
  }
}
