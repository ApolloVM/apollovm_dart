// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:async_extension/async_extension.dart';

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
      Iterable<ASTExpression> expressions,
      {VMContext? context}) {
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
  void associateToType(ASTTypedNode node) {}

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
}

/// [ASTExpression] to access a variable.
class ASTExpressionVariableAccess extends ASTExpression {
  ASTVariable variable;

  ASTExpressionVariableAccess(this.variable);

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
  String toString() {
    return '$variable';
  }
}

/// [ASTExpression] that declares a literal (number, boolean and String).
class ASTExpressionLiteral extends ASTExpression {
  ASTValue value;

  ASTExpressionLiteral(this.value);

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
  String toString() {
    return '$value';
  }
}

/// [ASTExpression] that declares a [List] literal.
class ASTExpressionListLiteral extends ASTExpression {
  final ASTType? type;

  final List<ASTExpression> valuesExpressions;

  ASTExpressionListLiteral(this.type, this.valuesExpressions);

  @override
  Iterable<ASTNode> get children =>
      [if (type != null) type!, ...valuesExpressions];

  @override
  FutureOr<ASTType> resolveType(VMContext? context) =>
      ASTExpression.typeFromExpressions(valuesExpressions);

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
  String toString() {
    return '$valuesExpressions';
  }
}

/// [ASTExpression] that declares a [Map] literal.
class ASTExpressionMapLiteral extends ASTExpression {
  final ASTType? keyType;
  final ASTType? valueType;

  final List<MapEntry<ASTExpression, ASTExpression>> entriesExpressions;

  ASTExpressionMapLiteral(
      this.keyType, this.valueType, this.entriesExpressions);

  @override
  Iterable<ASTNode> get children => [
        if (keyType != null) keyType!,
        if (valueType != null) valueType!,
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
          var values =
              astValues.map((e) => e.getValue(parentContext)).resolveAll();

          return keys.resolveBoth(values, (keys, values) {
            var map = Map.fromIterables(keys, values);
            return ASTValueMap(keyType, valueType, map);
          });
        });
      });
    });
  }

  @override
  String toString() {
    return '$entriesExpressions';
  }
}

/// [ASTExpression] to access a variable entry, by index (`foo[1]`) or by key (`foo[k]`).
class ASTExpressionVariableEntryAccess extends ASTExpression {
  ASTVariable variable;
  ASTExpression expression;

  ASTExpressionVariableEntryAccess(this.variable, this.expression);

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
  FutureOr<ASTValue> run(
      VMContext parentContext, ASTRunStatus runStatus) async {
    var context = defineRunContext(parentContext);

    var key = await expression.run(context, runStatus);
    var value = await variable.getValue(context);

    dynamic readValue;

    if (key is ASTValueNum) {
      var idx = key.getValue(context).toInt();
      try {
        readValue = await value.readIndex(context, idx);
      } on ApolloVMNullPointerException {
        throw ApolloVMNullPointerException(
            "Can't read variable index: $variable[$idx] (size: ${value.size(context)} ; value: $value)");
      }
    } else {
      var k = await key.getValue(context);
      try {
        readValue = await value.readKey(context, k);
      } on ApolloVMNullPointerException {
        throw ApolloVMNullPointerException(
            "Can't read variable key: $variable[$k]  (size: ${value.size(context)} ; value: $value)");
      }
    }

    return ASTValue.fromValue(readValue);
  }

  @override
  String toString() {
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
    default:
      throw UnsupportedError('$op');
  }
}

/// [ASTExpression] that negates another [expression].
class ASTExpressionNegation extends ASTExpression {
  ASTExpression expression;

  ASTExpressionNegation(this.expression);

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
  String toString() => '!$expression';
}

/// [ASTExpression] for an operation between 2 expressions.
class ASTExpressionOperation extends ASTExpression {
  ASTExpression expression1;
  ASTExpressionOperator operator;
  ASTExpression expression2;

  ASTExpressionOperation(this.expression1, this.operator, this.expression2);

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
        {
          var retT1 = expression1.resolveType(context);
          var retT2 = expression2.resolveType(context);

          return retT1.resolveBoth(
              retT2, (t1, t2) => _resolveTypePair(t1, t2, context));
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
        return ASTTypeBool.instance;
    }
  }

  FutureOr<ASTType> _resolveTypePair(ASTType t1, ASTType t2, VMContext? context,
      {int resolveDepth = 0}) {
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
          return _resolveTypePair(t1, t2, context,
              resolveDepth: resolveDepth + 1);
        });
      } else if (resolve1 != null) {
        return resolve1.resolveMapped((t1) {
          return _resolveTypePair(t1, t2, context,
              resolveDepth: resolveDepth + 1);
        });
      } else if (resolve2 != null) {
        return resolve2.resolveMapped((t2) {
          return _resolveTypePair(t1, t2, context,
              resolveDepth: resolveDepth + 1);
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
      VMContext context, ASTValue val1, ASTValue val2) {
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
      VMContext context, ASTValue val1, ASTValue val2) {
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
      VMContext context, ASTValue val1, ASTValue val2) {
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
      VMContext context, ASTValue val1, ASTValue val2) {
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
      VMContext context, ASTValue val1, ASTValue val2) {
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
      VMContext context, ASTValue val1, ASTValue val2) {
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
      VMContext context, ASTValue val1, ASTValue val2) {
    var b = val1.equals(val2);
    return b.resolveMapped((val) => ASTValueBool(val));
  }

  FutureOr<ASTValueBool> operatorNotEquals(
      VMContext context, ASTValue val1, ASTValue val2) {
    var b = val1.equals(val2);
    return b.resolveMapped((val) => ASTValueBool(!val));
  }

  FutureOr<ASTValueBool> operatorGreater(
      VMContext context, ASTValue val1, ASTValue val2) {
    var b = val1 > val2;
    return b.resolveMapped((val) => ASTValueBool(val));
  }

  FutureOr<ASTValueBool> operatorGreaterOrEq(
      VMContext context, ASTValue val1, ASTValue val2) {
    var b = val1 >= val2;
    return b.resolveMapped((val) => ASTValueBool(val));
  }

  FutureOr<ASTValueBool> operatorLower(
      VMContext context, ASTValue val1, ASTValue val2) {
    var b = val1 < val2;
    return b.resolveMapped((val) => ASTValueBool(val));
  }

  FutureOr<ASTValueBool> operatorLowerOrEq(
      VMContext context, ASTValue val1, ASTValue val2) {
    var b = val1 <= val2;
    return b.resolveMapped((val) => ASTValueBool(val));
  }

  @override
  String toString() {
    var op = getASTExpressionOperatorText(operator);
    return '$expression1 $op $expression2';
  }
}

/// [ASTExpression] to assign the value of a variable.
class ASTExpressionVariableAssignment extends ASTExpression {
  ASTVariable variable;

  ASTAssignmentOperator operator;

  ASTExpression expression;

  ASTExpressionVariableAssignment(
      this.variable, this.operator, this.expression);

  @override
  Iterable<ASTNode> get children => [variable, expression];

  @override
  FutureOr<ASTType> resolveType(VMContext? context) =>
      expression.resolveType(context);

  @override
  FutureOr<ASTValue> run(
      VMContext parentContext, ASTRunStatus runStatus) async {
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
      case ASTAssignmentOperator.multiply:
        {
          result = variableValue * value;
          break;
        }
      default:
        throw UnsupportedError('operator: $operator');
    }

    await variable.setValue(context, await result);

    return result;
  }
}

/// [ASTExpression] to directly apply a change to a variable.
/// - Operators examples: `++` and `--`
class ASTExpressionVariableDirectOperation extends ASTExpression {
  ASTVariable variable;

  ASTAssignmentOperator operator;

  bool preOperation;

  ASTExpressionVariableDirectOperation(
      this.variable, this.operator, this.preOperation);

  @override
  Iterable<ASTNode> get children => [variable];

  @override
  FutureOr<ASTType> resolveType(VMContext? context) =>
      variable.resolveType(context);

  @override
  FutureOr<ASTValue> run(
      VMContext parentContext, ASTRunStatus runStatus) async {
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
}

/// [ASTExpression] base class to call a function.
abstract class ASTExpressionFunctionInvocation extends ASTExpression {
  String name;
  List<ASTExpression> arguments;

  ASTExpressionFunctionInvocation(this.name, this.arguments);

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

  FutureOr<ASTFunctionDeclaration> _getFunction(VMContext parentContext);

  @override
  FutureOr<ASTValue> run(
      VMContext parentContext, ASTRunStatus runStatus) async {
    var f = await _getFunction(parentContext);

    var argumentsValues =
        await _resolveArgumentsValues(parentContext, runStatus, arguments);

    return f.call(parentContext, positionalParameters: argumentsValues);
  }

  @override
  String toString() {
    return '$name( $arguments )';
  }
}

Future<List<ASTValue>> _resolveArgumentsValues(VMContext parentContext,
    ASTRunStatus runStatus, List<ASTExpression> arguments) async {
  var argumentsFuture = arguments.map((e) async {
    return await e.run(parentContext, runStatus);
  }).toList();

  var argumentsValues = await Future.wait(argumentsFuture);
  return argumentsValues;
}

/// [ASTExpression] to call a local context function.
class ASTExpressionLocalFunctionInvocation
    extends ASTExpressionFunctionInvocation {
  ASTExpressionLocalFunctionInvocation(super.name, super.arguments);

  @override
  ASTFunctionDeclaration _getFunction(VMContext parentContext) {
    var fSignature = _getASTFunctionSignature();
    var f = parentContext.getFunction(name, fSignature);

    if (f == null) {
      throw ApolloVMRuntimeError(
          'Can\'t find function "$name" with parameters signature: $fSignature > $arguments');
    }

    return f;
  }
}

/// [ASTExpression] to call a class object function.
class ASTExpressionObjectFunctionInvocation
    extends ASTExpressionFunctionInvocation {
  ASTVariable variable;

  ASTExpressionObjectFunctionInvocation(
      this.variable, String name, List<ASTExpression> arguments)
      : super(name, arguments);

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

  FutureOr<ASTClass> _getFunctionClass(VMContext parentContext) async {
    if (_functionClass == null) {
      var clazz = await _getObjectClass(parentContext);
      _functionClass = clazz;
    }
    return _functionClass!;
  }

  @override
  FutureOr<ASTFunctionDeclaration> _getFunction(VMContext parentContext) async {
    var clazz = await _getFunctionClass(parentContext);
    var fSignature = _getASTFunctionSignature();

    var f = clazz.getFunction(name, fSignature, parentContext);

    if (f == null) {
      var obj = await _getVariableValue(parentContext);
      throw ApolloVMRuntimeError(
          "Can't find class[${clazz.name}] function[$name( $fSignature )] for object: $obj");
    }

    return f;
  }

  @override
  FutureOr<ASTValue> run(
      VMContext parentContext, ASTRunStatus runStatus) async {
    var f = await _getFunction(parentContext);

    var argumentsValues =
        await _resolveArgumentsValues(parentContext, runStatus, arguments);

    var obj = await _getVariableValue(parentContext);

    if (f is ASTClassFunctionDeclaration) {
      return f.objectCall(parentContext, obj,
          positionalParameters: argumentsValues);
    } else {
      // Static function call:
      return f.call(parentContext, positionalParameters: argumentsValues);
    }
  }

  @override
  String toString() {
    var f = super.toString();
    return '$variable.$f';
  }
}
