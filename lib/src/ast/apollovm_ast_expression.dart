import 'dart:async';

import 'package:apollovm/apollovm.dart';

import 'apollovm_ast_statement.dart';
import 'apollovm_ast_toplevel.dart';
import 'apollovm_ast_type.dart';
import 'apollovm_ast_value.dart';
import 'apollovm_ast_variable.dart';

abstract class ASTExpression implements ASTCodeRunner, ASTNode {
  @override
  VMContext defineRunContext(VMContext parentContext) {
    return parentContext;
  }
}

class ASTExpressionVariableAccess extends ASTExpression {
  ASTVariable variable;

  ASTExpressionVariableAccess(this.variable);

  @override
  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus) {
    var context = defineRunContext(parentContext);
    return variable.getValue(context);
  }
}

class ASTExpressionLiteral extends ASTExpression {
  ASTValue value;

  ASTExpressionLiteral(this.value);

  @override
  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus) {
    return value.resolve(parentContext);
  }
}

class ASTExpressionVariableEntryAccess extends ASTExpression {
  ASTVariable variable;
  ASTExpression expression;

  ASTExpressionVariableEntryAccess(this.variable, this.expression);

  @override
  FutureOr<ASTValue> run(
      VMContext parentContext, ASTRunStatus runStatus) async {
    var context = defineRunContext(parentContext);

    var key = await expression.run(context, runStatus);
    var value = await variable.getValue(context);

    var readValue;

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

    var readType = ASTType.from(readValue);
    return ASTValue.from(readType, readValue);
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
      throw UnsupportedError('$op');
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

class ASTExpressionOperation extends ASTExpression {
  ASTExpression expression1;
  ASTExpressionOperator operator;
  ASTExpression expression2;

  ASTExpressionOperation(this.expression1, this.operator, this.expression2);

  @override
  FutureOr<ASTValue> run(
      VMContext parentContext, ASTRunStatus runStatus) async {
    var context = defineRunContext(parentContext);

    var val2 = await expression2.run(context, runStatus);
    var val1 = await expression1.run(context, runStatus);

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
  }

  void throwOperationError(String op, ASTType t1, ASTType t2) {
    var message = "Can't perform '$op' operation with types: $t1 $op $t2";

    if (t1 is ASTTypeNull || t2 is ASTTypeNull) {
      throw ApolloVMNullPointerException(message);
    }

    throw UnsupportedError(message);
  }

  ASTValue operatorAdd(VMContext context, ASTValue val1, ASTValue val2) {
    var t1 = val1.type;
    var t2 = val2.type;

    if (t1 is ASTTypeString || t2 is ASTTypeString) {
      var v1 = val1.getValue(context);
      var v2 = val2.getValue(context);
      var r = '$v1$v2';
      return ASTValueString(r);
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
      if (t2 is ASTTypeInt || t2 is ASTTypeDouble) {
        var v1 = val1.getValue(context) as double;
        var v2 = val2.getValue(context) as num;
        var r = v1 + v2;
        return ASTValueDouble(r);
      }
    }

    throwOperationError('+', t1, t2);
    return ASTValueNull.INSTANCE;
  }

  ASTValue operatorSubtract(VMContext context, ASTValue val1, ASTValue val2) {
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
      if (t2 is ASTTypeInt || t2 is ASTTypeDouble) {
        var v1 = val1.getValue(context) as double;
        var v2 = val2.getValue(context) as num;
        var r = v1 - v2;
        return ASTValueDouble(r);
      }
    }

    throwOperationError('-', t1, t2);
    return ASTValueNull.INSTANCE;
  }

  ASTValue operatorMultiply(VMContext context, ASTValue val1, ASTValue val2) {
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
      if (t2 is ASTTypeInt || t2 is ASTTypeDouble) {
        var v1 = val1.getValue(context) as double;
        var v2 = val2.getValue(context) as num;
        var r = v1 * v2;
        return ASTValueDouble(r);
      }
    }

    throwOperationError('*', t1, t2);
    return ASTValueNull.INSTANCE;
  }

  ASTValue operatorDivide(VMContext context, ASTValue val1, ASTValue val2) {
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
      if (t2 is ASTTypeInt || t2 is ASTTypeDouble) {
        var v1 = val1.getValue(context) as double;
        var v2 = val2.getValue(context) as num;
        var r = v1 / v2;
        return ASTValueDouble(r);
      }
    }

    throwOperationError('/', t1, t2);
    return ASTValueNull.INSTANCE;
  }

  ASTValue operatorDivideAsInt(
      VMContext context, ASTValue val1, ASTValue val2) {
    var t1 = val1.type;
    var t2 = val2.type;

    if (t1 is ASTTypeInt || t1 is ASTTypeDouble) {
      if (t2 is ASTTypeInt || t2 is ASTTypeDouble) {
        var v1 = val1.getValue(context) as double;
        var v2 = val2.getValue(context) as num;
        var r = v1 / v2;
        return ASTValueInt(r.toInt());
      }
    }

    throwOperationError('/', t1, t2);
    return ASTValueNull.INSTANCE;
  }

  ASTValue operatorDivideAsDouble(
      VMContext context, ASTValue val1, ASTValue val2) {
    var t1 = val1.type;
    var t2 = val2.type;

    if (t1 is ASTTypeInt || t1 is ASTTypeDouble) {
      if (t2 is ASTTypeInt || t2 is ASTTypeDouble) {
        var v1 = val1.getValue(context) as double;
        var v2 = val2.getValue(context) as num;
        var r = v1 / v2;
        return ASTValueDouble(r);
      }
    }

    throwOperationError('/', t1, t2);
    return ASTValueNull.INSTANCE;
  }

  FutureOr<ASTValueBool> operatorEquals(
      VMContext context, ASTValue val1, ASTValue val2) async {
    var b = await val1.equals(val2);
    return ASTValueBool(b);
  }

  FutureOr<ASTValueBool> operatorNotEquals(
      VMContext context, ASTValue val1, ASTValue val2) async {
    var b = await val1.equals(val2);
    return ASTValueBool(!b);
  }

  FutureOr<ASTValueBool> operatorGreater(
      VMContext context, ASTValue val1, ASTValue val2) async {
    var b = val1 > val2;
    return ASTValueBool(await b);
  }

  FutureOr<ASTValueBool> operatorGreaterOrEq(
      VMContext context, ASTValue val1, ASTValue val2) async {
    var b = val1 >= val2;
    return ASTValueBool(await b);
  }

  FutureOr<ASTValueBool> operatorLower(
      VMContext context, ASTValue val1, ASTValue val2) async {
    var b = val1 < val2;
    return ASTValueBool(await b);
  }

  FutureOr<ASTValueBool> operatorLowerOrEq(
      VMContext context, ASTValue val1, ASTValue val2) async {
    var b = val1 <= val2;
    return ASTValueBool(await b);
  }
}

class ASTExpressionVariableAssignment extends ASTExpression {
  ASTVariable variable;

  ASTAssignmentOperator operator;

  ASTExpression expression;

  ASTExpressionVariableAssignment(
      this.variable, this.operator, this.expression);

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

    variable.setValue(context, await result);
    return value;
  }
}

class ASTExpressionLocalFunctionInvocation extends ASTExpression {
  String name;
  List<ASTExpression> arguments;

  ASTExpressionLocalFunctionInvocation(this.name, this.arguments);

  @override
  FutureOr<ASTValue> run(
      VMContext parentContext, ASTRunStatus runStatus) async {
    var fSignature = ASTFunctionSignature.from(arguments, null);
    var f = parentContext.getFunction(name, fSignature, parentContext);
    if (f == null) {
      throw StateError(
          'Can\'t find function "$name" with parameters signature: $fSignature');
    }

    var argumentsValues =
        await _resolveArgumentsValues(parentContext, runStatus, arguments);

    return f.call(parentContext, positionalParameters: argumentsValues);
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

class ASTExpressionObjectFunctionInvocation extends ASTExpression {
  ASTVariable variable;
  String name;
  List<ASTExpression> arguments;

  ASTExpressionObjectFunctionInvocation(
      this.variable, this.name, this.arguments);

  @override
  FutureOr<ASTValue> run(
      VMContext parentContext, ASTRunStatus runStatus) async {
    var obj = await variable.getValue(parentContext);

    if (obj is! ASTObjectInstance) {
      throw StateError(
          'Variable $variable not pointing to an object instance: $obj');
    }

    var clazz = obj.clazz;

    var fSignature = ASTFunctionSignature.from(arguments, null);

    var f = clazz.getFunction(name, fSignature, parentContext);
    if (f == null) {
      throw StateError(
          "Can't find class[${clazz.name}] function[$name( $fSignature )] for object: $obj");
    }

    var argumentsValues =
        await _resolveArgumentsValues(parentContext, runStatus, arguments);

    return f.call(parentContext, positionalParameters: argumentsValues);
  }
}
