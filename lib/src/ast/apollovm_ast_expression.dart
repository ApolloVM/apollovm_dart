// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:async_extension/async_extension.dart';
import 'package:swiss_knife/swiss_knife.dart';

import '../apollovm_base.dart';
import 'apollovm_ast_base.dart';
import 'apollovm_ast_statement.dart';
import 'apollovm_ast_toplevel.dart';
import 'apollovm_ast_type.dart';
import 'apollovm_ast_value.dart';
import 'apollovm_ast_variable.dart';

/// Base for AST expressions.
abstract class ASTExpression with ASTNode implements ASTCodeRunner {
  static FutureOr<ASTType> typeFromExpressions(
    Iterable<ASTExpression> expressions, {
    VMContext? context,
  }) {
    var types = expressions.map((e) => e.resolveType(context)).toSet();

    if (types.isEmpty) {
      return ASTTypeDynamic.instance;
    } else if (types.length == 1) {
      return types.first;
    }

    return types.resolveAll().resolveMapped((types) {
      if (types.every((t) => t is ASTTypeNumber)) {
        return ASTTypeNum.instance;
      }

      return ASTTypeDynamic.instance;
    });
  }

  ASTNode? _parentNode;

  @override
  ASTNode? get parentNode => _parentNode;

  bool get isComplex;

  @override
  void resolveNode(ASTNode? parentNode) {
    _parentNode = parentNode;

    cacheDescendantChildren();
  }

  @override
  ASTNode? getNodeIdentifier(String name, {ASTNode? requester}) =>
      parentNode?.getNodeIdentifier(name, requester: requester);

  @override
  VMContext defineRunContext(VMContext parentContext) {
    return parentContext;
  }

  @override
  FutureOr<ASTType> resolveRuntimeType(VMContext context, ASTNode? node) {
    return resolveType(context).resolveMapped((resolvedType) {
      if (node == null) return resolvedType;

      if (node is ASTTypedNode) {
        var typedNode = node as ASTTypedNode;

        return typedNode.resolveRuntimeType(context, null).resolveMapped((
          nodeType,
        ) {
          if (resolvedType != nodeType && resolvedType.acceptsType(nodeType)) {
            return nodeType;
          }
          return resolvedType;
        });
      }

      return resolvedType;
    });
  }

  @override
  void associateToType(ASTTypedNode node) {}

  FutureOr<Object?> getHashcodeValue(VMContext? context) {
    if (context != null) {
      var res = run(
        context,
        ASTRunStatus(),
      ).resolveMapped((result) => result.getValue(context));
      return res;
    } else {
      return '$this';
    }
  }

  bool get hasLiteralString =>
      children.whereType<ASTExpressionLiteral>().any((e) => e.isLiteralString);

  bool get hasDescendantLiteralString =>
      hasLiteralString ||
      descendantChildrenOperations.any((e) => e.hasDescendantLiteralString);

  bool get isOperation {
    return this is ASTExpressionOperation ||
        this is ASTExpressionVariableAssignment ||
        this is ASTExpressionVariableDirectOperation;
  }

  Iterable<ASTExpression> get childrenOperations =>
      children.whereType<ASTExpression>().where((e) => e.isOperation);

  Iterable<ASTExpression> get descendantChildrenOperations =>
      childrenOperations.expand((e) => [e, ...e.childrenOperations]);

  bool get isVariableAccess {
    return this is ASTExpressionVariableAccess;
  }

  bool get isLiteral {
    return this is ASTExpressionLiteral;
  }

  bool get isLiteralString {
    if (isLiteral) {
      var expLiteral = this as ASTExpressionLiteral;
      if (expLiteral.value.type is ASTTypeString) {
        return true;
      }
    }
    return false;
  }

  ASTNumType get literalNumType {
    if (isLiteral) {
      var expLiteral = this as ASTExpressionLiteral;
      var valueType = expLiteral.value.type;

      if (valueType is ASTTypeInt) {
        return ASTNumType.int;
      } else if (valueType is ASTTypeDouble) {
        return ASTNumType.int;
      } else if (valueType is ASTTypeNum) {
        return ASTNumType.num;
      }
    }

    return ASTNumType.nan;
  }

  bool get isLiteralNum {
    if (isLiteral) {
      var expLiteral = this as ASTExpressionLiteral;
      if (expLiteral.value.type is ASTTypeNum) {
        return true;
      }
    }
    return false;
  }

  bool get isLiteralInt {
    if (isLiteral) {
      var expLiteral = this as ASTExpressionLiteral;
      if (expLiteral.value.type is ASTTypeInt) {
        return true;
      }
    }
    return false;
  }

  bool get isLiteralDouble {
    if (isLiteral) {
      var expLiteral = this as ASTExpressionLiteral;
      if (expLiteral.value.type is ASTTypeDouble) {
        return true;
      }
    }
    return false;
  }

  @override
  String toString({bool asGroup = false});
}

/// [ASTExpression] for `null` value.
class ASTExpressionNullValue extends ASTExpression {
  ASTExpressionNullValue();

  @override
  bool get isComplex => false;

  @override
  Iterable<ASTNode> get children => [];

  @override
  FutureOr<ASTType> resolveType(VMContext? context) => ASTTypeNull.instance;

  @override
  ASTNode? getNodeIdentifier(String name, {ASTNode? requester}) =>
      parentNode?.getNodeIdentifier(name, requester: requester);

  @override
  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus) {
    return ASTValueNull.instance;
  }

  @override
  FutureOr<Object?> getHashcodeValue(VMContext? context) {
    return null;
  }

  @override
  String toString({bool asGroup = false}) {
    return 'null';
  }
}

/// [ASTExpression] to access a variable.
class ASTExpressionVariableAccess extends ASTExpression {
  ASTVariable variable;

  ASTExpressionVariableAccess(this.variable);

  @override
  bool get isComplex => false;

  @override
  Iterable<ASTNode> get children => [variable];

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    variable.resolveNode(this);
  }

  @override
  FutureOr<ASTType> resolveType(VMContext? context) =>
      variable.resolveType(context);

  @override
  ASTNode? getNodeIdentifier(String name, {ASTNode? requester}) =>
      parentNode?.getNodeIdentifier(name, requester: requester);

  @override
  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus) {
    var context = defineRunContext(parentContext);
    return variable.getValue(context);
  }

  @override
  String toString({bool asGroup = false}) {
    return '$variable';
  }
}

/// [ASTExpression] that declares a literal (number, boolean and String).
class ASTExpressionLiteral extends ASTExpression {
  ASTValue value;

  ASTExpressionLiteral(this.value);

  @override
  bool get isComplex => false;

  @override
  Iterable<ASTNode> get children => [value];

  @override
  FutureOr<ASTType> resolveType(VMContext? context) =>
      value.resolveType(context);

  @override
  ASTNode? getNodeIdentifier(String name, {ASTNode? requester}) =>
      parentNode?.getNodeIdentifier(name, requester: requester);

  @override
  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus) {
    return value.resolve(parentContext);
  }

  @override
  FutureOr<Object?> getHashcodeValue(VMContext? context) {
    return value.getHashcodeValue(context);
  }

  @override
  String toString({bool asGroup = false}) {
    return '$value';
  }
}

/// [ASTExpression] that declares a [List] literal.
class ASTExpressionListLiteral extends ASTExpression {
  final ASTType? type;

  final List<ASTExpression> valuesExpressions;

  ASTExpressionListLiteral(this.type, this.valuesExpressions);

  @override
  bool get isComplex => false;

  @override
  Iterable<ASTNode> get children => [?type, ...valuesExpressions];

  @override
  FutureOr<ASTType> resolveType(VMContext? context) {
    final type = this.type;
    if (type != null) {
      return ASTTypeArray(type);
    }

    return ASTExpression.typeFromExpressions(
      valuesExpressions,
    ).resolveMapped((elementsType) => ASTTypeArray(elementsType));
  }

  @override
  ASTNode? getNodeIdentifier(String name, {ASTNode? requester}) =>
      parentNode?.getNodeIdentifier(name, requester: requester);

  @override
  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus) {
    var type = this.type ?? resolveType(parentContext);

    return type.resolveMapped((type) {
      if (valuesExpressions.isEmpty) {
        return ASTValueArray(type, []);
      }

      var astValues = valuesExpressions
          .map((e) => e.run(parentContext, runStatus))
          .toList()
          .resolveAll();

      return astValues.resolveMapped((astValues) {
        return astValues
            .map((v) => v.getValue(parentContext))
            .toList()
            .resolveAll()
            .resolveMapped((values) {
              return ASTValueArray(type, values);
            });
      });
    });
  }

  @override
  FutureOr<Object?> getHashcodeValue(VMContext? context) {
    return valuesExpressions.map((e) => e.getHashcodeValue(context)).toList();
  }

  @override
  String toString({bool asGroup = false}) {
    return '$valuesExpressions';
  }
}

/// [ASTExpression] that declares a [Map] literal.
class ASTExpressionMapLiteral extends ASTExpression {
  final ASTType? keyType;
  final ASTType? valueType;

  final List<MapEntry<ASTExpression, ASTExpression>> entriesExpressions;

  ASTExpressionMapLiteral(
    this.keyType,
    this.valueType,
    this.entriesExpressions,
  );

  @override
  bool get isComplex => false;

  @override
  Iterable<ASTNode> get children => [
    ?keyType,
    ?valueType,
    ...entriesExpressions.expand((e) => [e.key, e.value]),
  ];

  FutureOr<ASTType> resolveKeyType(VMContext? context) =>
      ASTExpression.typeFromExpressions(entriesExpressions.map((e) => e.key));

  FutureOr<ASTType> resolveValueType(VMContext? context) =>
      ASTExpression.typeFromExpressions(entriesExpressions.map((e) => e.value));

  @override
  FutureOr<ASTType> resolveType(VMContext? context) =>
      resolveValueType(context);

  @override
  ASTNode? getNodeIdentifier(String name, {ASTNode? requester}) =>
      parentNode?.getNodeIdentifier(name, requester: requester);

  @override
  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus) {
    var keyType = this.keyType ?? resolveKeyType(parentContext);
    var valueType = this.valueType ?? resolveValueType(parentContext);

    return keyType.resolveBoth(valueType, (keyType, valueType) {
      if (entriesExpressions.isEmpty) {
        return ASTValueMap(keyType, valueType, {});
      }

      var astEntries = entriesExpressions
          .map((e) {
            var k = e.key.run(parentContext, runStatus);
            var v = e.value.run(parentContext, runStatus);
            return MapEntry(k, v);
          })
          .toList()
          .resolveAll();

      return astEntries.resolveMapped((astEntries) {
        var astKeys = astEntries.map((e) => e.key).resolveAll();
        var astValues = astEntries.map((e) => e.value).resolveAll();

        return astKeys.resolveBoth(astValues, (astKeys, astValues) {
          var keys = astKeys.map((e) => e.getValue(parentContext)).resolveAll();
          var values = astValues
              .map((e) => e.getValue(parentContext))
              .resolveAll();

          return keys.resolveBoth(values, (keys, values) {
            var map = Map.fromIterables(keys, values);
            return ASTValueMap(keyType, valueType, map);
          });
        });
      });
    });
  }

  @override
  FutureOr<Object?> getHashcodeValue(VMContext? context) {
    return entriesExpressions
        .map(
          (e) => (
            e.key.getHashcodeValue(context),
            e.value.getHashcodeValue(context),
          ),
        )
        .toList();
  }

  @override
  String toString({bool asGroup = false}) {
    return '$entriesExpressions';
  }
}

/// [ASTExpression] to access a variable entry, by index (`foo[1]`) or by key (`foo[k]`).
class ASTExpressionVariableEntryAccess extends ASTExpression {
  ASTVariable variable;
  ASTExpression expression;

  ASTExpressionVariableEntryAccess(this.variable, this.expression);

  @override
  bool get isComplex => false;

  @override
  Iterable<ASTNode> get children => [variable, expression];

  @override
  FutureOr<ASTType> resolveType(VMContext? context) =>
      variable.resolveType(context).resolveMapped((variableType) {
        if (variableType is ASTTypeArray) {
          return variableType.elementType;
        } else if (variableType is ASTTypeMap) {
          return variableType.valueType;
        } else {
          return ASTTypeDynamic.instance;
        }
      });

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    variable.resolveNode(parentNode);
    expression.resolveNode(parentNode);
  }

  @override
  ASTNode? getNodeIdentifier(String name, {ASTNode? requester}) =>
      parentNode?.getNodeIdentifier(name, requester: requester);

  @override
  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus) {
    var context = defineRunContext(parentContext);

    return expression.run(context, runStatus).resolveMapped((key) {
      return variable.getValue(context).resolveMapped((value) {
        if (key is ASTValueNum) {
          var idx = key.getValue(context).toInt();
          return _run2(context, value, idx: idx, readIndex: true);
        } else {
          return key
              .getValue(context)
              .resolveMapped(
                (Object? k) => _run2(context, value, key: k, readIndex: false),
              );
        }
      });
    });
  }

  FutureOr<ASTValue> _run2(
    VMContext context,
    ASTValue value, {
    int? idx,
    Object? key,
    required bool readIndex,
  }) {
    var valueType = value.type;

    var elementType = valueType;
    if (valueType is ASTTypeArray) {
      elementType = valueType.componentType;
    } else if (valueType is ASTTypeMap) {
      elementType = valueType.valueType;
    }

    return elementType.callCasted(<V>() {
      return _readElement<V>(context, value, idx, key, readIndex);
    });
  }

  FutureOr<ASTValue<V>> _readElement<V>(
    VMContext context,
    ASTValue<dynamic> value,
    int? idx,
    Object? key,
    bool readIndex,
  ) {
    try {
      var readValue = readIndex
          ? value.readIndexASTValue<V>(context, idx!)
          : value.readKeyASTValue<V>(context, key);

      if (readValue is Future<ASTValue<V>>) {
        return readValue.catchError((e, s) {
          if (e is ApolloVMNullPointerException) {
            _throwReadNPE(
              context,
              value,
              idx: idx,
              key: key,
              readIndex: readIndex,
              e,
              s,
            );
          }
          Error.throwWithStackTrace(e, s);
        });
      } else {
        return readValue;
      }
    } on ApolloVMNullPointerException catch (e, s) {
      _throwReadNPE(
        context,
        value,
        idx: idx,
        key: key,
        readIndex: readIndex,
        e,
        s,
      );
    }
  }

  Never _throwReadNPE(
    VMContext context,
    ASTValue value,
    Object? error,
    StackTrace stackTrace, {
    Object? key,
    int? idx,
    required bool readIndex,
  }) {
    if (readIndex) {
      Error.throwWithStackTrace(
        ApolloVMNullPointerException(
          "Can't read variable index: $variable[$idx] (size: ${value.size(context)} ; value: $value)",
        ),
        stackTrace,
      );
    } else {
      Error.throwWithStackTrace(
        ApolloVMNullPointerException(
          "Can't read variable key: $variable[$key]  (size: ${value.size(context)} ; value: $value)",
        ),
        stackTrace,
      );
    }
  }

  @override
  String toString({bool asGroup = false}) {
    return '$variable.$expression';
  }
}

enum ASTExpressionOperator {
  add,
  subtract,
  multiply,
  divide,
  divideAsInt,
  divideAsDouble,
  equals,
  notEquals,
  greater,
  lower,
  greaterOrEq,
  lowerOrEq,
  remainder,
  and,
  or,
}

ASTExpressionOperator getASTExpressionOperator(String op) {
  op = op.trim();
  switch (op) {
    case '+':
      return ASTExpressionOperator.add;
    case '-':
      return ASTExpressionOperator.subtract;
    case '*':
      return ASTExpressionOperator.multiply;
    case '/':
      return ASTExpressionOperator.divide;
    case '~/':
      return ASTExpressionOperator.divideAsInt;
    case '==':
      return ASTExpressionOperator.equals;
    case '!=':
      return ASTExpressionOperator.notEquals;
    case '>':
      return ASTExpressionOperator.greater;
    case '>=':
      return ASTExpressionOperator.greaterOrEq;
    case '<':
      return ASTExpressionOperator.lower;
    case '<=':
      return ASTExpressionOperator.lowerOrEq;
    case '%':
      return ASTExpressionOperator.remainder;
    case '&&':
      return ASTExpressionOperator.and;
    case '||':
      return ASTExpressionOperator.or;
    default:
      throw UnsupportedError(op);
  }
}

String getASTExpressionOperatorText(ASTExpressionOperator op) {
  switch (op) {
    case ASTExpressionOperator.add:
      return '+';
    case ASTExpressionOperator.subtract:
      return '-';
    case ASTExpressionOperator.multiply:
      return '*';
    case ASTExpressionOperator.divide:
    case ASTExpressionOperator.divideAsDouble:
      return '/';
    case ASTExpressionOperator.divideAsInt:
      return '~/';
    case ASTExpressionOperator.equals:
      return '==';
    case ASTExpressionOperator.notEquals:
      return '!=';
    case ASTExpressionOperator.greater:
      return '>';
    case ASTExpressionOperator.greaterOrEq:
      return '>=';
    case ASTExpressionOperator.lower:
      return '<';
    case ASTExpressionOperator.lowerOrEq:
      return '<=';
    case ASTExpressionOperator.remainder:
      return '%';
    case ASTExpressionOperator.and:
      return '&&';
    case ASTExpressionOperator.or:
      return '||';
  }
}

/// [ASTExpression] that negates another [expression].
class ASTExpressionNegation extends ASTExpression {
  ASTExpression expression;

  ASTExpressionNegation(this.expression);

  @override
  bool get isComplex => true;

  @override
  Iterable<ASTNode> get children => [expression];

  @override
  FutureOr<ASTType> resolveType(VMContext? context) => ASTTypeBool.instance;

  @override
  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus) {
    var context = defineRunContext(parentContext);

    var retVal = expression.run(context, runStatus);

    return retVal.resolveMapped((val) {
      return operatorNegation(parentContext, val);
    });
  }

  Never throwOperationError(ASTType t) {
    var message = "Can't perform negation operation with type: $t";

    if (t is ASTTypeNull) {
      throw ApolloVMNullPointerException(message);
    }

    throw UnsupportedError(message);
  }

  FutureOr<ASTValueBool> operatorNegation(VMContext context, ASTValue val) {
    var t = val.type;

    if (t is ASTTypeBool) {
      var v1 = val.getValue(context) as bool;
      var r = !v1;
      return ASTValueBool(r);
    }

    throwOperationError(t);
  }

  @override
  String toString({bool asGroup = false}) {
    var s = '!$expression';
    return asGroup ? '($s)' : s;
  }
}

/// [ASTExpression] that makes another [expression] negative.
class ASTExpressionNegative extends ASTExpression {
  ASTExpression expression;

  ASTExpressionNegative(this.expression);

  @override
  bool get isComplex => true;

  @override
  Iterable<ASTNode> get children => [expression];

  @override
  FutureOr<ASTType> resolveType(VMContext? context) => ASTTypeNum.instance;

  @override
  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus) {
    var context = defineRunContext(parentContext);

    var retVal = expression.run(context, runStatus);

    return retVal.resolveMapped((val) {
      return operatorNegative(parentContext, val);
    });
  }

  Never throwOperationError(ASTType t) {
    var message = "Can't perform negative operation with type: $t";

    if (t is ASTTypeNull) {
      throw ApolloVMNullPointerException(message);
    }

    throw UnsupportedError(message);
  }

  FutureOr<ASTValueNum> operatorNegative(VMContext context, ASTValue val) {
    var t = val.type;

    if (t is ASTTypeInt) {
      var v1 = val.getValue(context) as int;
      var r = -v1;
      return ASTValueInt(r);
    } else if (t is ASTTypeDouble) {
      var v1 = val.getValue(context) as double;
      var r = -v1;
      return ASTValueDouble(r);
    }

    throwOperationError(t);
  }

  @override
  String toString({bool asGroup = false}) {
    var s = '-$expression';
    return asGroup ? '($s)' : s;
  }
}

/// [ASTExpression] for an operation between 2 expressions.
class ASTExpressionOperation extends ASTExpression {
  ASTExpression expression1;
  ASTExpressionOperator operator;
  ASTExpression expression2;

  ASTExpressionOperation(this.expression1, this.operator, this.expression2);

  @override
  bool get isComplex => true;

  @override
  Iterable<ASTNode> get children => [expression1, expression2];

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    expression1.resolveNode(this);
    expression2.resolveNode(this);
  }

  @override
  FutureOr<ASTType> resolveType(VMContext? context) {
    switch (operator) {
      case ASTExpressionOperator.add:
      case ASTExpressionOperator.subtract:
      case ASTExpressionOperator.multiply:
      case ASTExpressionOperator.divide:
      case ASTExpressionOperator.remainder:
        {
          var retT1 = expression1.resolveType(context);
          var retT2 = expression2.resolveType(context);

          return retT1.resolveBoth(
            retT2,
            (t1, t2) => _resolveTypePair(t1, t2, context),
          );
        }
      case ASTExpressionOperator.divideAsInt:
        return ASTTypeInt.instance;
      case ASTExpressionOperator.divideAsDouble:
        return ASTTypeDouble.instance;
      case ASTExpressionOperator.equals:
      case ASTExpressionOperator.notEquals:
      case ASTExpressionOperator.greater:
      case ASTExpressionOperator.greaterOrEq:
      case ASTExpressionOperator.lower:
      case ASTExpressionOperator.lowerOrEq:
      case ASTExpressionOperator.and:
      case ASTExpressionOperator.or:
        return ASTTypeBool.instance;
    }
  }

  @override
  FutureOr<ASTType> resolveRuntimeType(VMContext context, ASTNode? node) {
    switch (operator) {
      case ASTExpressionOperator.add:
      case ASTExpressionOperator.subtract:
      case ASTExpressionOperator.multiply:
      case ASTExpressionOperator.divide:
      case ASTExpressionOperator.remainder:
        {
          var retT1 = expression1.resolveRuntimeType(context, null);
          var retT2 = expression2.resolveRuntimeType(context, null);

          return retT1.resolveBoth(
            retT2,
            (t1, t2) => _resolveTypePair(t1, t2, context),
          );
        }
      case ASTExpressionOperator.divideAsInt:
        return ASTTypeInt.instance;
      case ASTExpressionOperator.divideAsDouble:
        return ASTTypeDouble.instance;
      case ASTExpressionOperator.equals:
      case ASTExpressionOperator.notEquals:
      case ASTExpressionOperator.greater:
      case ASTExpressionOperator.greaterOrEq:
      case ASTExpressionOperator.lower:
      case ASTExpressionOperator.lowerOrEq:
      case ASTExpressionOperator.and:
      case ASTExpressionOperator.or:
        return ASTTypeBool.instance;
    }
  }

  FutureOr<ASTType> _resolveTypePair(
    ASTType t1,
    ASTType t2,
    VMContext? context, {
    int resolveDepth = 0,
  }) {
    if (resolveDepth < 3) {
      FutureOr<ASTType>? resolve1;
      FutureOr<ASTType>? resolve2;

      if (t1 is ASTTypeVar || t1 is ASTTypedVariable) {
        resolve1 = t1.resolveType(context);
      }

      if (t2 is ASTTypeVar || t2 is ASTTypedVariable) {
        resolve2 = t2.resolveType(context);
      }

      if (resolve1 != null && resolve2 != null) {
        return resolve1.resolveOther(resolve2, (t1, t2) {
          return _resolveTypePair(
            t1,
            t2,
            context,
            resolveDepth: resolveDepth + 1,
          );
        });
      } else if (resolve1 != null) {
        return resolve1.resolveMapped((t1) {
          return _resolveTypePair(
            t1,
            t2,
            context,
            resolveDepth: resolveDepth + 1,
          );
        });
      } else if (resolve2 != null) {
        return resolve2.resolveMapped((t2) {
          return _resolveTypePair(
            t1,
            t2,
            context,
            resolveDepth: resolveDepth + 1,
          );
        });
      }
    }

    if (t1 == t2) {
      return t1;
    }

    if (t1 is ASTTypeNum && t2 is ASTTypeNum) {
      if (_isOneOfType(t1, t2, ASTTypeDouble.instance)) {
        return ASTTypeDouble.instance;
      }

      if (_isOneOfType(t1, t2, ASTTypeInt.instance)) {
        return ASTTypeInt.instance;
      }

      return ASTTypeNum.instance;
    }

    if (_isOneOfType(t1, t2, ASTTypeString.instance)) {
      return ASTTypeString.instance;
    }

    return ASTTypeDynamic.instance;
  }

  static bool _isOneOfType(ASTType t1, ASTType t2, ASTType target) {
    return t1 == target || t2 == target;
  }

  @override
  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus) {
    var context = defineRunContext(parentContext);

    var retVal2 = expression2.run(context, runStatus);
    var retVal1 = expression1.run(context, runStatus);

    return retVal2.resolveBoth(retVal1, (val2, val1) {
      switch (operator) {
        case ASTExpressionOperator.add:
          return operatorAdd(parentContext, val1, val2);
        case ASTExpressionOperator.subtract:
          return operatorSubtract(parentContext, val1, val2);
        case ASTExpressionOperator.multiply:
          return operatorMultiply(parentContext, val1, val2);
        case ASTExpressionOperator.divide:
          return operatorDivide(parentContext, val1, val2);
        case ASTExpressionOperator.divideAsInt:
          return operatorDivideAsInt(parentContext, val1, val2);
        case ASTExpressionOperator.divideAsDouble:
          return operatorDivideAsDouble(parentContext, val1, val2);
        case ASTExpressionOperator.equals:
          return operatorEquals(parentContext, val1, val2);
        case ASTExpressionOperator.notEquals:
          return operatorNotEquals(parentContext, val1, val2);
        case ASTExpressionOperator.greater:
          return operatorGreater(parentContext, val1, val2);
        case ASTExpressionOperator.greaterOrEq:
          return operatorGreaterOrEq(parentContext, val1, val2);
        case ASTExpressionOperator.lower:
          return operatorLower(parentContext, val1, val2);
        case ASTExpressionOperator.lowerOrEq:
          return operatorLowerOrEq(parentContext, val1, val2);
        case ASTExpressionOperator.remainder:
          return operatorRemainder(parentContext, val1, val2);
        case ASTExpressionOperator.and:
          return operatorAnd(parentContext, val1, val2);
        case ASTExpressionOperator.or:
          return operatorOr(parentContext, val1, val2);
      }
    });
  }

  Never throwOperationError(String op, ASTType t1, ASTType t2) {
    var message = "Can't perform '$op' operation with types: $t1 $op $t2";

    if (t1 is ASTTypeNull || t2 is ASTTypeNull) {
      throw ApolloVMNullPointerException(message);
    }

    throw UnsupportedError(message);
  }

  FutureOr<ASTValue> operatorAdd(
    VMContext context,
    ASTValue val1,
    ASTValue val2,
  ) {
    var t1 = val1.type;
    var t2 = val2.type;

    if (t1 is ASTTypeString || t2 is ASTTypeString) {
      var v1 = val1.getValue(context);
      var v2 = val2.getValue(context);
      if (v1.isResolved && v2.isResolved) {
        var r = '$v1$v2';
        return ASTValueString(r);
      } else {
        return <FutureOr>[v1, v2].resolveAllJoined((l) {
          return ASTValueString(l.join());
        });
      }
    }

    if (t1 is ASTTypeInt) {
      if (t2 is ASTTypeInt) {
        var v1 = val1.getValue(context) as int;
        var v2 = val2.getValue(context) as int;
        var r = v1 + v2;
        return ASTValueInt(r);
      } else if (t2 is ASTTypeDouble) {
        var v1 = val1.getValue(context) as int;
        var v2 = val2.getValue(context) as double;
        var r = v1 + v2;
        return ASTValueDouble(r);
      }
    }

    if (t1 is ASTTypeDouble) {
      if (t2 is ASTTypeNum) {
        var v1 = val1.getValue(context) as double;
        var v2 = val2.getValue(context) as num;
        var r = v1 + v2;
        return ASTValueDouble(r);
      }
    }

    throwOperationError('+', t1, t2);
  }

  FutureOr<ASTValue> operatorSubtract(
    VMContext context,
    ASTValue val1,
    ASTValue val2,
  ) {
    var t1 = val1.type;
    var t2 = val2.type;

    if (t1 is ASTTypeInt) {
      if (t2 is ASTTypeInt) {
        var v1 = val1.getValue(context) as int;
        var v2 = val2.getValue(context) as int;
        var r = v1 - v2;
        return ASTValueInt(r);
      } else if (t2 is ASTTypeDouble) {
        var v1 = val1.getValue(context) as int;
        var v2 = val2.getValue(context) as double;
        var r = v1 - v2;
        return ASTValueDouble(r);
      }
    }

    if (t1 is ASTTypeDouble) {
      if (t2 is ASTTypeNum) {
        var v1 = val1.getValue(context) as double;
        var v2 = val2.getValue(context) as num;
        var r = v1 - v2;
        return ASTValueDouble(r);
      }
    }

    throwOperationError('-', t1, t2);
  }

  FutureOr<ASTValue> operatorMultiply(
    VMContext context,
    ASTValue val1,
    ASTValue val2,
  ) {
    var t1 = val1.type;
    var t2 = val2.type;

    if (t1 is ASTTypeInt) {
      if (t2 is ASTTypeInt) {
        var v1 = val1.getValue(context) as int;
        var v2 = val2.getValue(context) as int;
        var r = v1 * v2;
        return ASTValueInt(r);
      } else if (t2 is ASTTypeDouble) {
        var v1 = val1.getValue(context) as int;
        var v2 = val2.getValue(context) as double;
        var r = v1 * v2;
        return ASTValueDouble(r);
      }
    }

    if (t1 is ASTTypeDouble) {
      if (t2 is ASTTypeNum) {
        var v1 = val1.getValue(context) as double;
        var v2 = val2.getValue(context) as num;
        var r = v1 * v2;
        return ASTValueDouble(r);
      }
    }

    throwOperationError('*', t1, t2);
  }

  FutureOr<ASTValue> operatorDivide(
    VMContext context,
    ASTValue val1,
    ASTValue val2,
  ) {
    var t1 = val1.type;
    var t2 = val2.type;

    if (t1 is ASTTypeInt) {
      if (t2 is ASTTypeInt) {
        var v1 = val1.getValue(context) as int;
        var v2 = val2.getValue(context) as int;
        var r = v1 ~/ v2;
        return ASTValueInt(r);
      } else if (t2 is ASTTypeDouble) {
        var v1 = val1.getValue(context) as int;
        var v2 = val2.getValue(context) as double;
        var r = v1 / v2;
        return ASTValueDouble(r);
      }
    }

    if (t1 is ASTTypeDouble) {
      if (t2 is ASTTypeNum) {
        var v1 = val1.getValue(context) as double;
        var v2 = val2.getValue(context) as num;
        var r = v1 / v2;
        return ASTValueDouble(r);
      }
    }

    throwOperationError('/', t1, t2);
  }

  FutureOr<ASTValue> operatorDivideAsInt(
    VMContext context,
    ASTValue val1,
    ASTValue val2,
  ) {
    var t1 = val1.type;
    var t2 = val2.type;

    if (t1 is ASTTypeNum) {
      if (t2 is ASTTypeNum) {
        var v1 = val1.getValue(context) as num;
        var v2 = val2.getValue(context) as num;
        var r = v1 / v2;
        return ASTValueInt(r.toInt());
      }
    }

    throwOperationError('/', t1, t2);
  }

  FutureOr<ASTValue> operatorDivideAsDouble(
    VMContext context,
    ASTValue val1,
    ASTValue val2,
  ) {
    var t1 = val1.type;
    var t2 = val2.type;

    if (t1 is ASTTypeNum) {
      if (t2 is ASTTypeNum) {
        var v1 = val1.getValue(context) as num;
        var v2 = val2.getValue(context) as num;
        var r = v1 / v2;
        return ASTValueDouble(r);
      }
    }

    throwOperationError('/', t1, t2);
  }

  FutureOr<ASTValueBool> operatorEquals(
    VMContext context,
    ASTValue val1,
    ASTValue val2,
  ) {
    var b = val1.equals(val2);
    return b.resolveMapped((val) => ASTValueBool(val));
  }

  FutureOr<ASTValueBool> operatorNotEquals(
    VMContext context,
    ASTValue val1,
    ASTValue val2,
  ) {
    var b = val1.equals(val2);
    return b.resolveMapped((val) => ASTValueBool(!val));
  }

  FutureOr<ASTValueBool> operatorGreater(
    VMContext context,
    ASTValue val1,
    ASTValue val2,
  ) {
    var b = val1 > val2;
    return b.resolveMapped((val) => ASTValueBool(val));
  }

  FutureOr<ASTValueBool> operatorGreaterOrEq(
    VMContext context,
    ASTValue val1,
    ASTValue val2,
  ) {
    var b = val1 >= val2;
    return b.resolveMapped((val) => ASTValueBool(val));
  }

  FutureOr<ASTValueBool> operatorLower(
    VMContext context,
    ASTValue val1,
    ASTValue val2,
  ) {
    var b = val1 < val2;
    return b.resolveMapped((val) => ASTValueBool(val));
  }

  FutureOr<ASTValueBool> operatorLowerOrEq(
    VMContext context,
    ASTValue val1,
    ASTValue val2,
  ) {
    var b = val1 <= val2;
    return b.resolveMapped((val) => ASTValueBool(val));
  }

  FutureOr<ASTValue> operatorRemainder(
    VMContext context,
    ASTValue val1,
    ASTValue val2,
  ) {
    var t1 = val1.type;
    var t2 = val2.type;

    if (t1 is ASTTypeInt) {
      if (t2 is ASTTypeInt) {
        var v1 = val1.getValue(context) as int;
        var v2 = val2.getValue(context) as int;
        var r = v1 % v2;
        return ASTValueInt(r);
      } else if (t2 is ASTTypeDouble) {
        var v1 = val1.getValue(context) as int;
        var v2 = val2.getValue(context) as double;
        var r = v1 % v2;
        return ASTValueDouble(r);
      }
    }

    if (t1 is ASTTypeDouble) {
      if (t2 is ASTTypeNum) {
        var v1 = val1.getValue(context) as double;
        var v2 = val2.getValue(context) as num;
        var r = v1 % v2;
        return ASTValueDouble(r);
      }
    }

    throwOperationError('%', t1, t2);
  }

  FutureOr<ASTValueBool> operatorAnd(
    VMContext context,
    ASTValue val1,
    ASTValue val2,
  ) {
    var b1 = _toBoolean(val1, context);
    var b2 = _toBoolean(val2, context);

    return b1.resolveBoth(b2, (a, b) {
      var val = a && b;
      return ASTValueBool(val);
    });
  }

  FutureOr<ASTValueBool> operatorOr(
    VMContext context,
    ASTValue val1,
    ASTValue val2,
  ) {
    var b1 = _toBoolean(val1, context);
    var b2 = _toBoolean(val2, context);

    return b1.resolveBoth(b2, (a, b) {
      var val = a || b;
      return ASTValueBool(val);
    });
  }

  FutureOr<bool> _toBoolean(ASTValue val, VMContext context) {
    if (val is ASTValueBool) {
      return val.value;
    }

    return val.resolve(context).resolveMapped((val) {
      if (val is ASTValueBool) {
        return val.value;
      } else if (val is ASTValueNum) {
        return val.value > 0;
      } else if (val is ASTValueString) {
        return parseBool(val.value) ?? false;
      } else if (val is ASTValueArray) {
        return val.value.isNotEmpty;
      } else if (val is ASTValueMap) {
        return val.value.isNotEmpty;
      } else if (val is ASTValueNull) {
        return false;
      } else {
        return false;
      }
    });
  }

  @override
  String toString({bool asGroup = false}) {
    var op = getASTExpressionOperatorText(operator);
    var a = expression1.toString(asGroup: true);
    var b = expression2.toString(asGroup: true);
    var s = '$a $op $b';
    return asGroup ? '($s)' : s;
  }
}

/// [ASTExpression] to assign the value of a variable.
class ASTExpressionVariableAssignment extends ASTExpression {
  ASTVariable variable;

  ASTAssignmentOperator operator;

  ASTExpression expression;

  ASTExpressionVariableAssignment(
    this.variable,
    this.operator,
    this.expression,
  );

  @override
  bool get isComplex => true;

  @override
  Iterable<ASTNode> get children => [variable, expression];

  @override
  FutureOr<ASTType> resolveType(VMContext? context) =>
      expression.resolveType(context);

  @override
  FutureOr<ASTValue> run(
    VMContext parentContext,
    ASTRunStatus runStatus,
  ) async {
    var context = defineRunContext(parentContext);

    var value = await expression.run(context, runStatus);
    var variableValue = await variable.getValue(context);

    FutureOr<ASTValue> result;

    switch (operator) {
      case ASTAssignmentOperator.set:
        {
          result = value;
          break;
        }
      case ASTAssignmentOperator.sum:
        {
          result = variableValue + value;
          break;
        }
      case ASTAssignmentOperator.subtract:
        {
          result = variableValue - value;
          break;
        }
      case ASTAssignmentOperator.divide:
        {
          result = variableValue / value;
          break;
        }
      case ASTAssignmentOperator.divideAsInt:
        {
          result = variableValue ~/ value;
          break;
        }
      case ASTAssignmentOperator.multiply:
        {
          result = variableValue * value;
          break;
        }
    }

    await variable.setValue(context, await result);

    return result;
  }

  @override
  String toString({bool asGroup = false}) {
    switch (operator) {
      case ASTAssignmentOperator.set:
        {
          return '$variable = $expression';
        }
      case ASTAssignmentOperator.sum:
        {
          return '$variable += $expression';
        }
      case ASTAssignmentOperator.subtract:
        {
          return '$variable -= $expression';
        }
      case ASTAssignmentOperator.multiply:
        {
          return '$variable *= $expression';
        }
      case ASTAssignmentOperator.divide:
        {
          return '$variable /= $expression';
        }
      case ASTAssignmentOperator.divideAsInt:
        {
          return '$variable ~/= $expression';
        }
    }
  }
}

/// [ASTExpression] to directly apply a change to a variable.
/// - Operators examples: `++` and `--`
class ASTExpressionVariableDirectOperation extends ASTExpression {
  ASTVariable variable;

  ASTAssignmentOperator operator;

  bool preOperation;

  ASTExpressionVariableDirectOperation(
    this.variable,
    this.operator,
    this.preOperation,
  );

  @override
  bool get isComplex => true;

  @override
  Iterable<ASTNode> get children => [variable];

  @override
  FutureOr<ASTType> resolveType(VMContext? context) =>
      variable.resolveType(context);

  @override
  FutureOr<ASTValue> run(
    VMContext parentContext,
    ASTRunStatus runStatus,
  ) async {
    var context = defineRunContext(parentContext);

    var variableValue = await variable.getValue(context);

    var value = variableValue is ASTValueDouble
        ? ASTValueDouble(1.0) as ASTValueNum<num>
        : ASTValueInt(1) as ASTValueNum<num>;

    FutureOr<ASTValue> result;

    switch (operator) {
      case ASTAssignmentOperator.sum:
        {
          result = variableValue + value;
          break;
        }
      case ASTAssignmentOperator.subtract:
        {
          result = variableValue - value;
          break;
        }
      default:
        throw UnsupportedError('operator: $operator');
    }

    await variable.setValue(context, await result);

    return preOperation ? result : variableValue;
  }

  @override
  String toString({bool asGroup = false}) {
    switch (operator) {
      case ASTAssignmentOperator.sum:
        {
          return preOperation ? '++$variable' : '$variable++';
        }
      case ASTAssignmentOperator.subtract:
        {
          return preOperation ? '--$variable' : '$variable--';
        }
      default:
        return preOperation
            ? '${operator.symbol * 2}$variable'
            : '$variable${operator.symbol * 2}';
    }
  }
}

/// [ASTExpression] base class to call a function.
abstract class ASTExpressionFunctionInvocation extends ASTExpression {
  String name;
  List<ASTExpression> arguments;

  List<ASTExpressionChainFunctionInvocation>? chainFunctionInvocation;

  ASTExpressionFunctionInvocation(
    this.name,
    this.arguments, [
    List<ASTExpressionChainFunctionInvocation>? chainFunctionInvocation,
  ]) : chainFunctionInvocation =
           chainFunctionInvocation != null && chainFunctionInvocation.isNotEmpty
           ? chainFunctionInvocation
           : null;

  @override
  Iterable<ASTNode> get children => arguments;

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    for (var e in arguments) {
      e.resolveNode(this);
    }
  }

  @override
  FutureOr<ASTType> resolveType(VMContext? context) {
    if (context != null) {
      return _getFunction(context).resolveMapped((f) => f.resolveType(context));
    }

    final associatedNode = _associatedNode;
    return associatedNode == null
        ? ASTTypeDynamic.instance
        : associatedNode.resolveType(context);
  }

  ASTTypedNode? _associatedNode;

  @override
  void associateToType(ASTTypedNode node) => _associatedNode = node;

  ASTFunctionSignature? _functionSignature;

  ASTFunctionSignature _getASTFunctionSignature() {
    _functionSignature ??= ASTFunctionSignature.from(arguments, null);
    return _functionSignature!;
  }

  FutureOr<ASTInvocableDeclaration> _getFunction(VMContext parentContext);

  @override
  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus) {
    return _getFunction(parentContext).resolveMapped((f) {
      return _resolveArgumentsValues(
        parentContext,
        runStatus,
        arguments,
      ).resolveMapped((argumentsValues) {
        return _run2(parentContext, runStatus, f, argumentsValues);
      });
    });
  }

  FutureOr<ASTValue> _run2(
    VMContext parentContext,
    ASTRunStatus runStatus,
    ASTInvocableDeclaration f,
    List<ASTValue> argumentsValues,
  ) {
    var ret = f.call(parentContext, positionalParameters: argumentsValues);

    final chainFunctionInvocation = this.chainFunctionInvocation;
    if (chainFunctionInvocation == null || chainFunctionInvocation.isEmpty) {
      return ret;
    }

    return ret.resolveMapped((prevObj) {
      return _callChainFunction(
        parentContext,
        runStatus,
        prevObj,
        chainFunctionInvocation,
      );
    });
  }

  FutureOr<ASTValue> _callFunctionAndChain(
    VMContext parentContext,
    ASTRunStatus runStatus,
    ASTValue obj,
    ASTInvocableDeclaration f,
    List<ASTValue> argumentsValues,
  ) {
    var ret = _callFunction(parentContext, obj, f, argumentsValues);

    final chainFunctionInvocation = this.chainFunctionInvocation;
    if (chainFunctionInvocation == null || chainFunctionInvocation.isEmpty) {
      return ret;
    }

    return ret.resolveMapped((prevObj) {
      return _callChainFunction(
        parentContext,
        runStatus,
        prevObj,
        chainFunctionInvocation,
      );
    });
  }

  FutureOr<ASTValue> _callFunction(
    VMContext parentContext,
    ASTValue obj,
    ASTInvocableDeclaration f,
    List<ASTValue> argumentsValues,
  ) {
    if (f is ASTClassFunctionDeclaration) {
      return f.objectCall(
        parentContext,
        obj,
        positionalParameters: argumentsValues,
      );
    } else {
      // Static function call:
      return f.call(parentContext, positionalParameters: argumentsValues);
    }
  }

  Future<ASTValue> _callChainFunction(
    VMContext parentContext,
    ASTRunStatus runStatus,
    ASTValue prevObj,
    List<ASTExpressionChainFunctionInvocation> chainFunctionInvocation,
  ) async {
    for (var f in chainFunctionInvocation) {
      var ret = await f.run(parentContext, runStatus, prevObj);
      if (runStatus.returned) {
        return ret;
      }
      prevObj = ret;
    }

    return prevObj;
  }

  @override
  String toString({bool asGroup = false}) {
    return '$name( $arguments )';
  }

  String _appendChainFunction(String s) {
    final chainFunctionInvocation = this.chainFunctionInvocation;
    if (chainFunctionInvocation != null && chainFunctionInvocation.isNotEmpty) {
      return '$s${chainFunctionInvocation.join()}';
    } else {
      return s;
    }
  }
}

FutureOr<List<ASTValue>> _resolveArgumentsValues(
  VMContext parentContext,
  ASTRunStatus runStatus,
  List<ASTExpression> arguments,
) {
  var argumentsValues = arguments
      .map((a) => a.run(parentContext, runStatus))
      .resolveAll();
  return argumentsValues;
}

/// [ASTExpression] to call a local context function.
class ASTExpressionLocalFunctionInvocation
    extends ASTExpressionFunctionInvocation {
  ASTExpressionLocalFunctionInvocation(
    super.name,
    super.arguments, [
    super.chainFunctionInvocation,
  ]);

  @override
  bool get isComplex => false;

  @override
  ASTInvocableDeclaration _getFunction(VMContext parentContext) {
    var fSignature = _getASTFunctionSignature();
    var f = parentContext.getFunction(name, fSignature);

    if (f == null) {
      throw ApolloVMRuntimeError(
        'Can\'t find function "$name" with parameters signature: $fSignature > $arguments',
      );
    }

    return f;
  }
}

/// [ASTExpression] to call a class object function.
class ASTExpressionChainFunctionInvocation
    extends ASTExpressionFunctionInvocation {
  ASTExpressionChainFunctionInvocation(super.name, super.arguments);

  @override
  bool get isComplex => false;

  @override
  Iterable<ASTNode> get children => [];

  FutureOr<ASTClass> _getObjectClass(ASTValue? obj) {
    if (obj == null) {
      throw ApolloVMRuntimeError("Can't resolve object clazz");
    }

    if (obj is ASTClassInstance) {
      return obj.clazz;
    }

    var clazz = obj.type.getClass();
    return clazz;
  }

  ASTClass? _functionClass;

  FutureOr<ASTClass> _getFunctionClass(ASTValue? previousValue) {
    if (_functionClass == null) {
      return _getObjectClass(previousValue).resolveMapped((clazz) {
        return _functionClass = clazz;
      });
    }
    return _functionClass!;
  }

  @override
  FutureOr<ASTInvocableDeclaration> _getFunction(
    VMContext parentContext, [
    ASTValue? previousValue,
  ]) {
    return _getFunctionClass(previousValue).resolveMapped((clazz) {
      var fSignature = _getASTFunctionSignature();

      var f = clazz.getFunction(name, fSignature, parentContext);

      if (f == null) {
        throw ApolloVMRuntimeError(
          "Can't find class[${clazz.name}] function[$name( $fSignature )] for previous object in function chain: $previousValue",
        );
      }

      return f;
    });
  }

  @override
  FutureOr<ASTValue> run(
    VMContext parentContext,
    ASTRunStatus runStatus, [
    ASTValue? previousValue,
  ]) {
    if (previousValue == null) {
      return runStatus.returnNull();
    }

    return _getFunction(parentContext, previousValue).resolveMapped((f) {
      return _resolveArgumentsValues(
        parentContext,
        runStatus,
        arguments,
      ).resolveMapped((argumentsValues) {
        if (f is ASTClassFunctionDeclaration) {
          return f.objectCall(
            parentContext,
            previousValue,
            positionalParameters: argumentsValues,
          );
        } else {
          // Static function call:
          return f.call(parentContext, positionalParameters: argumentsValues);
        }
      });
    });
  }

  @override
  String toString({bool asGroup = false}) {
    var f = super.toString();
    return '.$f';
  }
}

/// [ASTExpression] to call a class object function.
class ASTExpressionObjectFunctionInvocation
    extends ASTExpressionFunctionInvocation {
  ASTVariable variable;

  ASTExpressionObjectFunctionInvocation(
    this.variable,
    String name,
    List<ASTExpression> arguments, [
    List<ASTExpressionChainFunctionInvocation>? chainFunctionInvocation,
  ]) : super(name, arguments, chainFunctionInvocation);

  @override
  bool get isComplex => false;

  @override
  Iterable<ASTNode> get children => [variable];

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    variable.resolveNode(this);
  }

  FutureOr<ASTValue> _getVariableValue(VMContext parentContext) {
    return variable.getValue(parentContext);
  }

  FutureOr<ASTClass> _getObjectClass(VMContext parentContext) {
    var retObj = _getVariableValue(parentContext);

    return retObj.resolveMapped((obj) {
      if (obj is ASTClassInstance) {
        return obj.clazz;
      }

      var clazz = obj.type.getClass();
      return clazz;
    });
  }

  ASTClass? _functionClass;

  FutureOr<ASTClass> _getFunctionClass(VMContext parentContext) {
    if (_functionClass == null) {
      return _getObjectClass(parentContext).resolveMapped((clazz) {
        return _functionClass = clazz;
      });
    }
    return _functionClass!;
  }

  @override
  FutureOr<ASTInvocableDeclaration> _getFunction(VMContext parentContext) {
    return _getFunctionClass(parentContext).resolveMapped((clazz) {
      var fSignature = _getASTFunctionSignature();

      var f = clazz.getFunction(name, fSignature, parentContext);
      if (f == null) {
        throw ApolloVMRuntimeError(
          "Can't find class[${clazz.name}] function[$name( $fSignature )] for object!",
        );
      }

      return f;
    });
  }

  @override
  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus) {
    return _getFunction(parentContext).resolveMapped((f) {
      return _resolveArgumentsValues(
        parentContext,
        runStatus,
        arguments,
      ).resolveMapped((argumentsValues) {
        return _getVariableValue(parentContext).resolveMapped((obj) {
          return _callFunctionAndChain(
            parentContext,
            runStatus,
            obj,
            f,
            argumentsValues,
          );
        });
      });
    });
  }

  @override
  String toString({bool asGroup = false}) {
    var f = super.toString();
    var s = '$variable.$f';
    return _appendChainFunction(s);
  }
}

/// [ASTExpression] to call a class object entry function.
/// Code example:
/// - `obj[i].fx(args)`
/// - `obj[key].fx(args)`
class ASTExpressionObjectEntryFunctionInvocation
    extends ASTExpressionFunctionInvocation {
  ASTExpressionVariableEntryAccess variableAccess;

  ASTExpressionObjectEntryFunctionInvocation(
    ASTVariable variable,
    ASTExpression expression,
    super.name,
    super.arguments, [
    super.chainFunctionInvocation,
  ]) : variableAccess = ASTExpressionVariableEntryAccess(variable, expression);

  @override
  bool get isComplex => false;

  @override
  Iterable<ASTNode> get children => variableAccess.children;

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    variableAccess.resolveNode(this);
  }

  FutureOr<ASTClass> _getObjectClass(VMContext parentContext, ASTValue obj) {
    if (obj is ASTClassInstance) {
      return obj.clazz;
    }

    var clazz = obj.type.getClass();
    return clazz;
  }

  ASTClass? _functionClass;

  FutureOr<ASTClass> _getFunctionClass(VMContext parentContext, ASTValue obj) {
    if (_functionClass == null) {
      return _getObjectClass(parentContext, obj).resolveMapped((clazz) {
        return _functionClass = clazz;
      });
    }
    return _functionClass!;
  }

  @override
  FutureOr<ASTInvocableDeclaration> _getFunction(
    VMContext parentContext, [
    ASTValue? obj,
  ]) {
    if (obj == null) {
      throw ApolloVMNullPointerException(
        "Null variable entry: $variableAccess",
      );
    }

    return _getFunctionClass(parentContext, obj).resolveMapped((clazz) {
      var fSignature = _getASTFunctionSignature();

      var f = clazz.getFunction(name, fSignature, parentContext);
      if (f == null) {
        throw ApolloVMRuntimeError(
          "Can't find class[${clazz.name}] function[$name( $fSignature )] for object: $obj",
        );
      }

      return f;
    });
  }

  @override
  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus) {
    return variableAccess.run(parentContext, runStatus).resolveMapped((obj) {
      return _getFunction(parentContext, obj).resolveMapped((f) {
        return _resolveArgumentsValues(
          parentContext,
          runStatus,
          arguments,
        ).resolveMapped((argumentsValues) {
          return _callFunctionAndChain(
            parentContext,
            runStatus,
            obj,
            f,
            argumentsValues,
          );
        });
      });
    });
  }

  @override
  String toString({bool asGroup = false}) {
    var f = super.toString();
    var s = '$variableAccess.$f';
    return _appendChainFunction(s);
  }
}

/// [ASTExpression] to call a function from an expression.
/// Example: `(-d).toStringAsFixed(4)`
class ASTExpressionGroupFunctionInvocation
    extends ASTExpressionFunctionInvocation {
  ASTExpression expression;

  ASTExpressionGroupFunctionInvocation(
    this.expression,
    String name,
    List<ASTExpression> arguments, [
    List<ASTExpressionChainFunctionInvocation>? chainFunctionInvocation,
  ]) : super(name, arguments, chainFunctionInvocation);

  @override
  bool get isComplex => false;

  @override
  Iterable<ASTNode> get children => [expression];

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    expression.resolveNode(this);
  }

  FutureOr<ASTValue> _getExpressionValue(VMContext parentContext) {
    return expression.run(parentContext, ASTRunStatus());
  }

  FutureOr<ASTClass> _getObjectClass(VMContext parentContext) {
    var retObj = _getExpressionValue(parentContext);

    return retObj.resolveMapped((obj) {
      if (obj is ASTClassInstance) {
        return obj.clazz;
      }

      var clazz = obj.type.getClass();
      return clazz;
    });
  }

  ASTClass? _functionClass;

  FutureOr<ASTClass> _getFunctionClass(VMContext parentContext) {
    if (_functionClass == null) {
      return _getObjectClass(parentContext).resolveMapped((clazz) {
        return _functionClass = clazz;
      });
    }
    return _functionClass!;
  }

  @override
  FutureOr<ASTInvocableDeclaration> _getFunction(VMContext parentContext) {
    return _getFunctionClass(parentContext).resolveMapped((clazz) {
      var fSignature = _getASTFunctionSignature();

      var f = clazz.getFunction(name, fSignature, parentContext);
      if (f == null) {
        throw ApolloVMRuntimeError(
          "Can't find class[${clazz.name}] function[$name( $fSignature )] for object!",
        );
      }

      return f;
    });
  }

  @override
  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus) {
    return _getFunction(parentContext).resolveMapped((f) {
      return _resolveArgumentsValues(
        parentContext,
        runStatus,
        arguments,
      ).resolveMapped((argumentsValues) {
        return _getExpressionValue(parentContext).resolveMapped((obj) {
          return _callFunctionAndChain(
            parentContext,
            runStatus,
            obj,
            f,
            argumentsValues,
          );
        });
      });
    });
  }

  @override
  String toString({bool asGroup = false}) {
    var f = super.toString();
    var s = '($expression).$f';
    return _appendChainFunction(s);
  }
}

/// [ASTExpression] base class to call a function.
abstract class ASTExpressionGetterAccess extends ASTExpression {
  String name;

  ASTExpressionGetterAccess(this.name);

  @override
  FutureOr<ASTType> resolveType(VMContext? context) {
    if (context != null) {
      return _getGetter(context).resolveMapped((f) => f.resolveType(context));
    }

    final associatedNode = _associatedNode;
    return associatedNode == null
        ? ASTTypeDynamic.instance
        : associatedNode.resolveType(context);
  }

  ASTTypedNode? _associatedNode;

  @override
  void associateToType(ASTTypedNode node) => _associatedNode = node;

  FutureOr<ASTGetterDeclaration> _getGetter(VMContext parentContext);

  @override
  FutureOr<ASTValue> run(
    VMContext parentContext,
    ASTRunStatus runStatus,
  ) async {
    var g = await _getGetter(parentContext);
    return g.call(parentContext);
  }

  @override
  String toString({bool asGroup = false}) {
    return 'get:$name';
  }
}

/// [ASTExpression] to call a local context function.
class ASTExpressionLocalGetterAccess extends ASTExpressionGetterAccess {
  ASTExpressionLocalGetterAccess(super.name);

  @override
  bool get isComplex => false;

  @override
  Iterable<ASTNode> get children => [];

  @override
  ASTGetterDeclaration _getGetter(VMContext parentContext) {
    var g = parentContext.getGetter(name);

    if (g == null) {
      throw ApolloVMRuntimeError('Can\'t find getter "$name"');
    }

    return g;
  }
}

/// [ASTExpression] to call a class object function.
class ASTExpressionObjectGetterAccess extends ASTExpressionGetterAccess {
  ASTVariable variable;

  ASTExpressionObjectGetterAccess(this.variable, String name) : super(name);

  @override
  bool get isComplex => false;

  @override
  Iterable<ASTNode> get children => [variable];

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    variable.resolveNode(this);
  }

  FutureOr<ASTValue> _getVariableValue(VMContext parentContext) {
    return variable.getValue(parentContext);
  }

  FutureOr<ASTClass> _getObjectClass(VMContext parentContext) {
    var retObj = _getVariableValue(parentContext);

    return retObj.resolveMapped((obj) {
      if (obj is ASTClassInstance) {
        return obj.clazz;
      }

      var clazz = obj.type.getClass();
      return clazz;
    });
  }

  ASTClass? _getterClass;

  FutureOr<ASTClass> _getGetterClass(VMContext parentContext) {
    final clazz = _getterClass;

    if (clazz == null) {
      return _getObjectClass(parentContext).resolveMapped((clazz) {
        return _getterClass = clazz;
      });
    }

    return clazz;
  }

  @override
  FutureOr<ASTGetterDeclaration> _getGetter(VMContext parentContext) {
    return _getGetterClass(parentContext).resolveMapped((clazz) {
      var g = clazz.getGetter(name, parentContext);
      if (g == null) {
        return _getVariableValue(parentContext).resolveMapped((obj) {
          throw ApolloVMRuntimeError(
            "Can't find class[${clazz.name}] getter[$name] for object: $obj",
          );
        });
      }

      return g;
    });
  }

  @override
  FutureOr<ASTType> resolveType(VMContext? context) {
    if (context == null) {
      return super.resolveType(context);
    }

    return _getVariableValue(context).resolveMapped((obj) {
      if (obj is ASTClassInstance) {
        var classContext = obj.createContext(context);
        return obj.getField(classContext, name).resolveMapped((fieldValue) {
          if (fieldValue != null) {
            return fieldValue.type;
          }
          return super.resolveType(context);
        });
      }

      return super.resolveType(context);
    });
  }

  @override
  FutureOr<ASTType<dynamic>> resolveRuntimeType(
    VMContext context,
    ASTNode? node,
  ) {
    return _getVariableValue(context).resolveMapped((obj) {
      if (obj is ASTClassInstance) {
        var classContext = obj.createContext(context);
        return obj.getField(classContext, name).resolveMapped((fieldValue) {
          if (fieldValue != null) {
            return fieldValue.type;
          }
          return super.resolveRuntimeType(context, node);
        });
      }

      return super.resolveRuntimeType(context, node);
    });
  }

  @override
  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus) {
    return _getVariableValue(parentContext).resolveMapped((obj) {
      if (obj is ASTClassInstance) {
        var classContext = obj.createContext(parentContext);
        return obj.getField(classContext, name).resolveMapped((fieldValue) {
          if (fieldValue != null) {
            return fieldValue;
          }
          return _runGetter(parentContext, obj);
        });
      }

      return _runGetter(parentContext, obj);
    });
  }

  FutureOr<ASTValue> _runGetter(VMContext parentContext, ASTValue obj) {
    return _getGetter(parentContext).resolveMapped((g) {
      if (g is ASTClassGetterDeclaration) {
        return g.objectCall(parentContext, obj);
      } else {
        // Static getter call:
        return g.call(parentContext);
      }
    });
  }

  @override
  String toString({bool asGroup = false}) {
    var f = super.toString();
    return '$variable.$f';
  }
}
