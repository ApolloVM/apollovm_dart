import 'dart:async';

import 'package:apollovm/apollovm.dart';

import 'apollovm_ast_statement.dart';
import 'apollovm_ast_toplevel.dart';
import 'apollovm_ast_type.dart';
import 'apollovm_ast_value.dart';
import 'apollovm_ast_variable.dart';

/// Base for AST expressions.
abstract class ASTExpression implements ASTCodeRunner, ASTNode {
  ASTNode? _parentNode;

  @override
  ASTNode? get parentNode => _parentNode;

  @override
  void resolveNode(ASTNode? parentNode) {
    _parentNode = parentNode;
  }

  @override
  ASTNode? getNodeIdentifier(String name) =>
      parentNode?.getNodeIdentifier(name);

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
  FutureOr<ASTType> resolveType(VMContext? context) =>
      variable.resolveType(context);

  @override
  ASTNode? getNodeIdentifier(String name) =>
      parentNode?.getNodeIdentifier(name);

  @override
  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus) {
    var context = defineRunContext(parentContext);
    return variable.getValue(context);
  }
}

/// [ASTExpression] that declares a literal (number, boolean and String).
class ASTExpressionLiteral extends ASTExpression {
  ASTValue value;

  ASTExpressionLiteral(this.value);

  @override
  FutureOr<ASTType> resolveType(VMContext? context) =>
      value.resolveType(context);

  @override
  ASTNode? getNodeIdentifier(String name) =>
      parentNode?.getNodeIdentifier(name);

  @override
  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus) {
    return value.resolve(parentContext);
  }
}

/// [ASTExpression] to access a variable entry, by index (`foo[1]`) or by key (`foo[k]`).
class ASTExpressionVariableEntryAccess extends ASTExpression {
  ASTVariable variable;
  ASTExpression expression;

  ASTExpressionVariableEntryAccess(this.variable, this.expression);

  @override
  FutureOr<ASTType> resolveType(VMContext? context) =>
      variable.resolveType(context);

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    variable.resolveNode(parentNode);
    expression.resolveNode(parentNode);
  }

  @override
  ASTNode? getNodeIdentifier(String name) =>
      parentNode?.getNodeIdentifier(name);

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

    return ASTValue.fromValue(readValue);
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

/// [ASTExpression] for an operation between 2 expressions.
class ASTExpressionOperation extends ASTExpression {
  ASTExpression expression1;
  ASTExpressionOperator operator;
  ASTExpression expression2;

  ASTExpressionOperation(this.expression1, this.operator, this.expression2);

  @override
  FutureOr<ASTType> resolveType(VMContext? context) async {
    switch (operator) {
      case ASTExpressionOperator.add:
      case ASTExpressionOperator.subtract:
      case ASTExpressionOperator.multiply:
      case ASTExpressionOperator.divide:
        {
          var t1 = await expression1.resolveType(context);
          var t2 = await expression1.resolveType(context);
          if (_isOneOfType(t1, t2, ASTTypeDouble.INSTANCE)) {
            return ASTTypeDouble.INSTANCE;
          }
          if (_isOneOfType(t1, t2, ASTTypeInt.INSTANCE)) {
            return ASTTypeInt.INSTANCE;
          }
          if (_isOneOfType(t1, t2, ASTTypeString.INSTANCE)) {
            return ASTTypeString.INSTANCE;
          }
          if (_isOneOfType(t1, t2, ASTTypeNum.INSTANCE)) {
            return ASTTypeInt.INSTANCE;
          }
          return ASTTypeDynamic.INSTANCE;
        }
      case ASTExpressionOperator.divideAsInt:
        return ASTTypeInt.INSTANCE;
      case ASTExpressionOperator.divideAsDouble:
        return ASTTypeDouble.INSTANCE;
      case ASTExpressionOperator.equals:
      case ASTExpressionOperator.notEquals:
      case ASTExpressionOperator.greater:
      case ASTExpressionOperator.greaterOrEq:
      case ASTExpressionOperator.lower:
      case ASTExpressionOperator.lowerOrEq:
        return ASTTypeBool.INSTANCE;
    }
  }

  static bool _isOneOfType(ASTType t1, ASTType t2, ASTType target) {
    return t1 == target || t2 == target;
  }

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
        return <FutureOr>[v1, v2].resolveAllMapped((l) {
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
    return ASTValueNull.INSTANCE;
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
    return ASTValueNull.INSTANCE;
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
    return ASTValueNull.INSTANCE;
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
    return ASTValueNull.INSTANCE;
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
    return ASTValueNull.INSTANCE;
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

/// [ASTExpression] to assign the value of a variable.
class ASTExpressionVariableAssignment extends ASTExpression {
  ASTVariable variable;

  ASTAssignmentOperator operator;

  ASTExpression expression;

  ASTExpressionVariableAssignment(
      this.variable, this.operator, this.expression);

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

    variable.setValue(context, await result);
    return value;
  }
}

/// [ASTExpression] base class to call a function.
abstract class ASTExpressionFunctionInvocation extends ASTExpression {
  String name;
  List<ASTExpression> arguments;

  ASTExpressionFunctionInvocation(this.name, this.arguments);

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    for (var e in arguments) {
      e.resolveNode(this);
    }
  }

  @override
  FutureOr<ASTType> resolveType(VMContext? context) async {
    if (context != null) {
      var f = await _getFunction(context);
      return f.resolveType(context);
    }

    return _associatedNode != null
        ? await _associatedNode!.resolveType(context)
        : ASTTypeDynamic.INSTANCE;
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
  ASTExpressionLocalFunctionInvocation(
      String name, List<ASTExpression> arguments)
      : super(name, arguments);

  @override
  ASTFunctionDeclaration _getFunction(VMContext parentContext) {
    var fSignature = _getASTFunctionSignature();
    var f = parentContext.getFunction(name, fSignature);

    if (f == null) {
      throw StateError(
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
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    variable.resolveNode(this);
  }

  FutureOr<ASTValue> _getVariableValue(VMContext parentContext) async {
    var obj = await variable.getValue(parentContext);
    return obj;
  }

  FutureOr<ASTClass> _getObjectClass(VMContext parentContext) async {
    var obj = await _getVariableValue(parentContext);

    if (obj is ASTClassInstance) {
      return obj.clazz;
    }

    var clazz = obj.type.getClass();
    return clazz;
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
      throw StateError(
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
}
