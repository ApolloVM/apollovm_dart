import 'dart:async';

import 'package:apollovm/apollovm.dart';

import 'apollovm_ast_type.dart';
import 'apollovm_ast_value.dart';

/// Base class for variable reference.
abstract class ASTVariable implements ASTNode, ASTTypedNode {
  final String name;

  ASTVariable(this.name);

  @override
  void associateToType(ASTTypedNode node) {}

  FutureOr<ASTVariable> resolveVariable(VMContext context);

  FutureOr<ASTValue> getValue(VMContext context) {
    var variable = resolveVariable(context);
    return variable.resolveMapped((v) => v.getValue(context));
  }

  FutureOr<void> setValue(VMContext context, ASTValue value) async {
    var variable = await resolveVariable(context);
    variable.setValue(context, value);
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

/// [ASTVariable] with [type].
abstract class ASTTypedVariable<T> extends ASTVariable {
  ASTType<T> type;
  final bool finalValue;

  ASTTypedVariable(this.type, String name, this.finalValue) : super(name);

  @override
  ASTType resolveType(VMContext? context) => type;

  @override
  String toString() {
    return '$type $name';
  }
}

/// [ASTVariable] for class fields.
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

/// [ASTVariable] for class fields with initial values.
class ASTClassFieldWithInitialValue<T> extends ASTClassField<T> {
  final ASTExpression _initialValueExpression;

  ASTClassFieldWithInitialValue(ASTType<T> type, String name,
      this._initialValueExpression, bool finalValue)
      : super(type, name, finalValue);

  ASTExpression get initialValue => _initialValueExpression;

  FutureOr<ASTValue> getInitialValue(
      VMContext context, ASTRunStatus runStatus) {
    return _initialValueExpression.run(context, runStatus);
  }

  FutureOr<ASTValue> getInitialValueNoContext() {
    var context = VMContext(ASTBlock(null));
    var runStatus = ASTRunStatus();
    return _initialValueExpression.run(context, runStatus);
  }
}

/// [ASTVariable] for a runtime value.
///
/// Used to represent a resolved variable at runtime.
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

/// [ASTVariable] for a variable visible in a scope context.
class ASTScopeVariable<T> extends ASTVariable {
  ASTScopeVariable(String name) : super(name);

  @override
  FutureOr<ASTType> resolveType(VMContext? context) async =>
      _associatedNode != null
          ? await _associatedNode!.resolveType(context)
          : ASTTypeDynamic.INSTANCE;

  ASTTypedNode? _associatedNode;

  @override
  void associateToType(ASTTypedNode node) => _associatedNode = node;

  @override
  FutureOr<ASTVariable> resolveVariable(VMContext context) {
    var variable = context.getVariable(name, true);

    return variable.resolveMapped((v) {
      if (v == null) {
        var typeResolver = context.typeResolver;
        var resolveType = typeResolver.resolveType(name);
        return resolveType.resolveMapped((t) {
          if (t != null) {
            return t.getClass().staticAccessor.staticClassAccessorVariable;
          }
          throw StateError("Can't find variable: '$name'");
        });
      }
      return v;
    });
  }
}

/// [ASTVariable] for `this`/`self` reference.
class ASTThisVariable<T> extends ASTVariable {
  ASTThisVariable() : super('this');

  @override
  FutureOr<ASTType> resolveType(VMContext? context) async {
    if (context is VMClassContext) {
      return context.clazz.type;
    }

    return _associatedNode != null
        ? await _associatedNode!.resolveType(context)
        : ASTTypeDynamic.INSTANCE;
  }

  ASTTypedNode? _associatedNode;

  @override
  void associateToType(ASTTypedNode node) => _associatedNode = node;

  @override
  ASTVariable resolveVariable(VMContext context) {
    var obj = context.getClassInstance();
    if (obj == null) {
      throw StateError("Can't determine 'this'! No ASTObjectInstance defined!");
    }
    return ASTRuntimeVariable(obj.type, 'this', obj);
  }
}

/// [ASTVariable] for `static` reference.
class ASTStaticClassAccessorVariable<T> extends ASTVariable {
  final ASTClass<T> clazz;
  late final ASTClassStaticAccessor<ASTClass<T>, T> staticAccessor;

  ASTStaticClassAccessorVariable(this.clazz) : super(clazz.name);

  void setAccessor(ASTClassStaticAccessor<ASTClass<T>, T> accessor) {
    staticAccessor = accessor;
  }

  @override
  FutureOr<ASTType> resolveType(VMContext? context) {
    return clazz.type;
  }

  @override
  ASTVariable resolveVariable(VMContext context) => this;

  @override
  FutureOr<ASTValue> getValue(VMContext context) {
    return staticAccessor;
  }
}
