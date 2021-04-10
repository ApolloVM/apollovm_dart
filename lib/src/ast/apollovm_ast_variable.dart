import 'package:apollovm/apollovm.dart';

import 'apollovm_ast_type.dart';
import 'apollovm_ast_value.dart';

import 'dart:async';

abstract class ASTVariable implements ASTNode {
  final String name;

  ASTVariable(this.name);

  FutureOr<ASTVariable> resolveVariable(VMContext context);

  FutureOr<ASTValue> getValue(VMContext context) async {
    var variable = await resolveVariable(context);
    return variable.getValue(context);
  }

  FutureOr<void> setValue(VMContext context, ASTValue value) async {
    var variable = await resolveVariable(context);
    await variable.setValue(context, value);
  }

  FutureOr<V> readIndex<V>(VMContext context, int index) async {
    var value = await getValue(context);
    return value.readIndex(context, index);
  }

  FutureOr<V> readKey<V>(VMContext context, Object key) async {
    var value = await getValue(context);
    return value.readKey(context, key);
  }

  @override
  String toString() {
    return name;
  }
}

abstract class ASTTypedVariable<T> extends ASTVariable {
  ASTType<T> type;
  final bool finalValue;

  ASTTypedVariable(this.type, String name, this.finalValue) : super(name);

  @override
  String toString() {
    return '$type $name';
  }
}

class ASTClassField<T> extends ASTTypedVariable<T> {
  ASTClassField(ASTType<T> type, String name, bool finalValue)
      : super(type, name, finalValue);

  @override
  ASTVariable resolveVariable(VMContext context) {
    var variable = context.getField(name);
    if (variable == null) {
      throw StateError("Can't find Class field: $name");
    }
    return variable;
  }
}

class ASTRuntimeVariable<T> extends ASTTypedVariable<T> {
  ASTValue _value;

  ASTRuntimeVariable(ASTType<T> type, String name, [ASTValue? value])
      : _value = value ?? ASTValueNull.INSTANCE,
        super(type, name, false);

  @override
  ASTVariable resolveVariable(VMContext context) {
    return this;
  }

  @override
  ASTValue getValue(VMContext context) {
    return _value;
  }

  @override
  void setValue(VMContext context, ASTValue value) {
    _value = value;
  }
}

class ASTScopeVariable<T> extends ASTVariable {
  ASTScopeVariable(String name) : super(name);

  @override
  ASTVariable resolveVariable(VMContext context) {
    var variable = context.getVariable(name, true);
    if (variable == null) {
      throw StateError("Can't find variable: '$name'");
    }
    return variable;
  }
}

class ASTThisVariable<T> extends ASTVariable {
  ASTThisVariable() : super('this');

  @override
  ASTVariable resolveVariable(VMContext context) {
    var obj = context.getObjectInstance();
    if (obj == null) {
      throw StateError("Can't determine 'this'! No ASTObjectInstance defined!");
    }
    return ASTRuntimeVariable(obj.type, 'this', obj);
  }
}
