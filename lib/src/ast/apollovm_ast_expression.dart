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
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    var context = defineRunContext(parentContext);
    return variable.getValue(context);
  }
}

class ASTExpressionLiteral extends ASTExpression {
  ASTValue value;

  ASTExpressionLiteral(this.value);

  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    return value.resolve(parentContext);
  }
}

class ASTExpressionVariableEntryAccess extends ASTExpression {
  ASTVariable variable;
  ASTExpression expression;

  ASTExpressionVariableEntryAccess(this.variable, this.expression);

  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    var context = defineRunContext(parentContext);

    var key = expression.run(context, runStatus);
    var value = variable.getValue(context);

    var readValue;

    if (key is ASTValueNum) {
      var idx = key.getValue(context).toInt();
      try {
        readValue = value.readIndex(context, idx);
      } on ApolloVMNullPointerException {
        throw ApolloVMNullPointerException(
            "Can't read variable index: $variable[$idx] (size: ${value.size(context)} ; value: $value)");
      }
    } else {
      var k = key.getValue(context);
      try {
        readValue = value.readKey(context, k);
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
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    var context = defineRunContext(parentContext);

    var val2 = expression2.run(context, runStatus);
    var val1 = expression1.run(context, runStatus);

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

    throw UnsupportedError("Can't perform '+' operation in types: $t1 + $t2");
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

    throw UnsupportedError("Can't perform '-' operation in types: $t1 - $t2");
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

    throw UnsupportedError("Can't perform '*' operation in types: $t1 * $t2");
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

    throw UnsupportedError("Can't perform '/' operation in types: $t1 / $t2");
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

    throw UnsupportedError("Can't perform '/' operation in types: $t1 / $t2");
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

    throw UnsupportedError("Can't perform '/' operation in types: $t1 / $t2");
  }

  ASTValueBool operatorEquals(VMContext context, ASTValue val1, ASTValue val2) {
    var b = val1 == val2;
    return ASTValueBool(b);
  }

  ASTValueBool operatorNotEquals(
      VMContext context, ASTValue val1, ASTValue val2) {
    var b = val1 != val2;
    return ASTValueBool(b);
  }

  ASTValueBool operatorGreater(
      VMContext context, ASTValue val1, ASTValue val2) {
    var b = val1 > val2;
    return ASTValueBool(b);
  }

  ASTValueBool operatorGreaterOrEq(
      VMContext context, ASTValue val1, ASTValue val2) {
    var b = val1 >= val2;
    return ASTValueBool(b);
  }

  ASTValueBool operatorLower(VMContext context, ASTValue val1, ASTValue val2) {
    var b = val1 < val2;
    return ASTValueBool(b);
  }

  ASTValueBool operatorLowerOrEq(
      VMContext context, ASTValue val1, ASTValue val2) {
    var b = val1 <= val2;
    return ASTValueBool(b);
  }
}

class ASTExpressionVariableAssignment extends ASTExpression {
  ASTVariable variable;

  ASTAssignmentOperator operator;

  ASTExpression expression;

  ASTExpressionVariableAssignment(
      this.variable, this.operator, this.expression);

  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    var context = defineRunContext(parentContext);

    var value = expression.run(context, runStatus);
    var variableValue = variable.getValue(context);

    switch (operator) {
      case ASTAssignmentOperator.set:
        {
          variable.setValue(context, value);
          return value;
        }
      case ASTAssignmentOperator.sum:
        {
          var res = variableValue + value;
          variable.setValue(context, res);
          return value;
        }
      case ASTAssignmentOperator.subtract:
        {
          var res = variableValue - value;
          variable.setValue(context, res);
          return value;
        }
      case ASTAssignmentOperator.divide:
        {
          var res = variableValue / value;
          variable.setValue(context, res);
          return value;
        }
      case ASTAssignmentOperator.multiply:
        {
          var res = variableValue * value;
          variable.setValue(context, res);
          return value;
        }
      default:
        throw UnsupportedError('operator: $operator');
    }
  }
}

class ASTExpressionLocalFunctionInvocation extends ASTExpression {
  String name;
  List<ASTExpression> arguments;

  ASTExpressionLocalFunctionInvocation(this.name, this.arguments);

  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    var fSignature = ASTFunctionSignature.from(arguments, null);
    var f = parentContext.block.getFunction(name, fSignature, parentContext);
    if (f == null) {
      throw StateError(
          'Can\'t find function "$name" with parameters signature: $fSignature');
    }

    var argumentsValues = arguments.map((e) {
      return e.run(parentContext, runStatus);
    }).toList();

    return f.call(parentContext, positionalParameters: argumentsValues);
  }
}

class ASTExpressionObjectFunctionInvocation extends ASTExpression {
  ASTVariable variable;
  String name;
  List arguments;

  ASTExpressionObjectFunctionInvocation(
      this.variable, this.name, this.arguments);

  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    // TODO: implement run
    throw UnimplementedError();
  }
}
