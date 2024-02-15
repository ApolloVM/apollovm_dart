// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:async_extension/async_extension.dart';

import '../apollovm_base.dart';
import 'apollovm_ast_base.dart';
import 'apollovm_ast_expression.dart';
import 'apollovm_ast_statement.dart';
import 'apollovm_ast_toplevel.dart';
import 'apollovm_ast_type.dart';
import 'apollovm_ast_value.dart';

/// Base class for variable reference.
abstract class ASTVariable with ASTNode implements ASTTypedNode {
  final String name;

  ASTVariable(this.name);

  bool get isTypeIdentifier => false;

  ASTType? get typeIdentifier => null;

  @override
  void associateToType(ASTTypedNode node) {}

  FutureOr<ASTVariable> resolveVariable(VMContext context);

  FutureOr<ASTValue> getValue(VMContext context) {
    var variable = resolveVariable(context);
    return variable.resolveMapped((v) => v.getValue(context));
  }

  FutureOr<void> setValue(VMContext context, ASTValue value) {
    return resolveVariable(context).resolveMapped((variable) {
      variable.setValue(context, value);
    });
  }

  FutureOr<V> readIndex<V>(VMContext context, int index) {
    return getValue(context).resolveMapped((value) {
      return value.readIndex(context, index);
    });
  }

  FutureOr<V> readKey<V>(VMContext context, Object key) {
    return getValue(context).resolveMapped((value) {
      return value.readKey(context, key);
    });
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
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    type.resolveNode(parentNode);
  }

  @override
  String toString() {
    return '$type $name';
  }
}

/// [ASTVariable] for class fields.
class ASTClassField<T> extends ASTTypedVariable<T> {
  ASTClassField(super.type, super.name, super.finalValue);

  @override
  Iterable<ASTNode> get children => [];

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
      : _value = value ?? ASTValueNull.instance,
        super(type, name, false);

  @override
  Iterable<ASTNode> get children => [_value];

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    _value.resolveNode(parentNode);
  }

  @override
  ASTType resolveType(VMContext? context) {
    if (type is ASTTypeVar) {
      var t = _value.resolveType(context);
      if (t is ASTType) {
        return t;
      }
      return _value.type;
    }

    return type;
  }

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

  @override
  String toString() {
    return 'ASTRuntimeVariable{value: $_value}';
  }
}

/// [ASTVariable] for a variable visible in a scope context.
class ASTScopeVariable<T> extends ASTVariable {
  ASTScopeVariable(super.name);

  @override
  Iterable<ASTNode> get children => [];

  @override
  FutureOr<ASTType> resolveType(VMContext? context) {
    final associatedNode = _associatedNode;

    if (associatedNode != null) {
      return associatedNode.resolveType(context);
    }

    if (context == null) {
      var parentNode = _parentNode;
      if (parentNode != null) {
        var node = parentNode.getNodeIdentifier(name, requester: this);

        if (node is ASTTypedNode) {
          var typedNode = node as ASTTypedNode;
          var t = typedNode.resolveType(null);
          if (t is ASTType) return t;
        }
      }

      return ASTTypeDynamic.instance;
    }

    return context.getVariable(name, false).resolveMapped((variable) {
      return variable?.resolveType(context) ?? ASTTypeDynamic.instance;
    });
  }

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
            var staticAccessor = t.getClass().staticAccessor;
            return staticAccessor.staticClassAccessorVariable;
          }
          throw StateError("Can't find variable: '$name'");
        });
      }
      return v;
    });
  }

  ASTNode? resolvedIdentifier;

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    resolvedIdentifier =
        this.parentNode!.getNodeIdentifier(name, requester: this);
  }

  @override
  bool get isTypeIdentifier => resolvedIdentifier is ASTClass;

  @override
  ASTType? get typeIdentifier {
    var resolvedIdentifier = this.resolvedIdentifier;
    return resolvedIdentifier is ASTClass ? resolvedIdentifier.type : null;
  }
}

/// [ASTVariable] for `this`/`self` reference.
class ASTThisVariable<T> extends ASTVariable {
  ASTThisVariable() : super('this');

  @override
  Iterable<ASTNode> get children => [];

  @override
  FutureOr<ASTType> resolveType(VMContext? context) {
    if (context is VMClassContext) {
      return context.clazz.type;
    }

    final associatedNode = _associatedNode;

    return associatedNode == null
        ? ASTTypeDynamic.instance
        : associatedNode.resolveType(context);
  }

  ASTTypedNode? _associatedNode;

  @override
  void associateToType(ASTTypedNode node) => _associatedNode = node;

  @override
  ASTVariable resolveVariable(VMContext context) {
    var obj = context.getClassInstance();
    if (obj == null) {
      throw ApolloVMRuntimeError(
          "Can't determine 'this'! No ASTObjectInstance defined!");
    }
    return ASTRuntimeVariable(obj.type, 'this', obj);
  }
}

/// [ASTVariable] for `static` reference.
class ASTStaticClassAccessorVariable<T> extends ASTVariable {
  final ASTClass<T> clazz;
  late final ASTClassStaticAccessor<ASTClass<T>, T> staticAccessor;

  ASTStaticClassAccessorVariable(this.clazz) : super(clazz.name);

  @override
  Iterable<ASTNode> get children => [staticAccessor];

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
