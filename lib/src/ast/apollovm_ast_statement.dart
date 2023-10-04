// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:async_extension/async_extension.dart';
import 'package:collection/collection.dart' show equalsIgnoreAsciiCase;

import '../apollovm_base.dart';
import 'apollovm_ast_base.dart';
import 'apollovm_ast_expression.dart';
import 'apollovm_ast_toplevel.dart';
import 'apollovm_ast_type.dart';
import 'apollovm_ast_value.dart';
import 'apollovm_ast_variable.dart';

/// An AST Statement.
abstract class ASTStatement implements ASTCodeRunner, ASTNode {
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
}

/// An AST Block of code (statements).
class ASTBlock extends ASTStatement {
  ASTBlock? parentBlock;

  ASTBlock(this.parentBlock);

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    for (var e in _statements) {
      e.resolveNode(this);
    }

    for (var e in _functions.values) {
      e.resolveNode(this);
    }
  }

  @override
  ASTNode? getNodeIdentifier(String name) {
    var f = _functions[name];
    if (f != null) return f;

    return parentNode?.getNodeIdentifier(name);
  }

  final Map<String, ASTFunctionSet> _functions = {};

  List<ASTFunctionSet> get functions => _functions.values.toList();

  List<String> get functionsNames => _functions.keys.toList();

  void addFunction(ASTFunctionDeclaration f) {
    var name = f.name;
    f.parentBlock = this;

    var set = _functions[name];
    if (set == null) {
      _functions[name] = ASTFunctionSetSingle(f);
    } else {
      var set2 = set.add(f);
      if (!identical(set, set2)) {
        _functions[name] = set2;
      }
    }
  }

  void addAllFunctions(Iterable<ASTFunctionDeclaration> fs) {
    for (var f in fs) {
      addFunction(f);
    }
  }

  ASTFunctionSet? getFunctionWithName(String name,
      {bool caseInsensitive = false}) {
    var f = _functions[name];

    if (f == null && caseInsensitive) {
      for (var entry in _functions.entries) {
        if (equalsIgnoreAsciiCase(entry.key, name)) {
          f = entry.value;
          break;
        }
      }
    }

    return f;
  }

  bool containsFunctionWithName(String name, {bool caseInsensitive = false}) {
    var set = getFunctionWithName(name, caseInsensitive: caseInsensitive);
    return set != null;
  }

  ASTFunctionDeclaration? getFunction(
    String fName,
    ASTFunctionSignature parametersSignature,
    VMContext context, {
    bool caseInsensitive = false,
  }) {
    var set = getFunctionWithName(fName, caseInsensitive: caseInsensitive);
    if (set != null) return set.get(parametersSignature, false);

    var fExternal =
        context.getMappedExternalFunction(fName, parametersSignature);

    return fExternal;
  }

  ASTType<T>? getFunctionReturnType<T>(String name,
          ASTFunctionSignature parametersTypes, VMContext context) =>
      getFunction(name, parametersTypes, context)?.returnType as ASTType<T>?;

  final List<ASTStatement> _statements = [];

  List<ASTStatement> get statements => _statements.toList();

  void set(ASTBlock? other) {
    if (other == null) return;

    _functions.clear();
    addAllFunctions(other._functions.values.expand((e) => e.functions));

    _statements.clear();
    addAllStatements(other._statements);
  }

  void addStatement(ASTStatement statement) {
    _statements.add(statement);
    if (statement is ASTBlock) {
      statement.parentBlock = this;
    }
  }

  void addAllStatements(Iterable<ASTStatement> statements) {
    for (var stm in statements) {
      addStatement(stm);
    }
  }

  @override
  VMContext defineRunContext(VMContext parentContext) {
    return parentContext;
  }

  @override
  FutureOr<ASTValue> run(
      VMContext parentContext, ASTRunStatus runStatus) async {
    var blockContext = defineRunContext(parentContext);

    FutureOr<ASTValue> returnValue = ASTValueVoid.instance;

    for (var stm in _statements) {
      var ret = await stm.run(blockContext, runStatus);

      if (runStatus.returned) {
        return (runStatus.returnedFutureValue ?? runStatus.returnedValue)!;
      }

      returnValue = ret;
    }

    return returnValue;
  }

  @override
  ASTType resolveType(VMContext? context) => ASTTypeDynamic.instance;

  ASTClassField? getField(String name, {bool caseInsensitive = false}) =>
      parentBlock != null
          ? parentBlock!.getField(name, caseInsensitive: caseInsensitive)
          : null;

  @override
  String toString() {
    var str = StringBuffer();

    str.write('{\n');

    for (var stm in _statements) {
      str.write('$stm\n');
    }

    str.write('}');

    return str.toString();
  }
}

abstract class ASTStatementTyped extends ASTStatement implements ASTTypedNode {}

class ASTStatementValue extends ASTStatementTyped {
  ASTValue value;

  ASTStatementValue(ASTBlock block, this.value) : super();

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    value.resolveNode(parentNode);
  }

  @override
  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus) {
    var context = defineRunContext(parentContext);
    return value.getValue(context) as FutureOr<ASTValue>;
  }

  @override
  FutureOr<ASTType> resolveType(VMContext? context) =>
      value.resolveType(context);
}

enum ASTAssignmentOperator {
  set,
  multiply,
  divide,
  sum,
  subtract;

  ASTExpressionOperator? get asASTExpressionOperator {
    switch (this) {
      case sum:
        return ASTExpressionOperator.add;
      case subtract:
        return ASTExpressionOperator.subtract;
      case multiply:
        return ASTExpressionOperator.multiply;
      case divide:
        return ASTExpressionOperator.divide;
      default:
        return null;
    }
  }
}

ASTAssignmentOperator getASTAssignmentOperator(String op) {
  op = op.trim();

  switch (op) {
    case '=':
      return ASTAssignmentOperator.set;
    case '*=':
      return ASTAssignmentOperator.multiply;
    case '/=':
      return ASTAssignmentOperator.divide;
    case '+=':
      return ASTAssignmentOperator.sum;
    case '-=':
      return ASTAssignmentOperator.subtract;
    default:
      throw UnsupportedError(op);
  }
}

String getASTAssignmentOperatorText(ASTAssignmentOperator op) {
  switch (op) {
    case ASTAssignmentOperator.set:
      return '=';
    case ASTAssignmentOperator.multiply:
      return '*=';
    case ASTAssignmentOperator.divide:
      return '/=';
    case ASTAssignmentOperator.sum:
      return '+=';
    case ASTAssignmentOperator.subtract:
      return '-=';
    default:
      throw UnsupportedError('$op');
  }
}

class ASTStatementExpression extends ASTStatement {
  ASTExpression expression;

  ASTStatementExpression(this.expression);

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    expression.resolveNode(parentNode);
  }

  @override
  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus) {
    var context = defineRunContext(parentContext);
    return expression.run(context, runStatus);
  }

  @override
  FutureOr<ASTType> resolveType(VMContext? context) =>
      expression.resolveType(context);

  @override
  String toString() {
    return '$expression ;';
  }
}

/// [ASTStatement] to return void.
class ASTStatementReturn extends ASTStatement {
  @override
  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus) {
    return runStatus.returnVoid();
  }

  @override
  FutureOr<ASTType> resolveType(VMContext? context) => ASTTypeVoid.instance;

  @override
  String toString() {
    return 'return;';
  }
}

/// [ASTStatement] to return null.
class ASTStatementReturnNull extends ASTStatementReturn
    implements ASTStatementTyped {
  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    return runStatus.returnNull();
  }

  @override
  ASTType resolveType(VMContext? context) => ASTTypeNull.instance;

  @override
  String toString() {
    return 'return null ;';
  }
}

/// [ASTStatement] to return a [value].
class ASTStatementReturnValue extends ASTStatementReturn
    implements ASTStatementTyped {
  ASTValue value;

  ASTStatementReturnValue(this.value);

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    value.resolveNode(parentNode);
  }

  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    return runStatus.returnValue(value);
  }

  @override
  FutureOr<ASTType> resolveType(VMContext? context) =>
      value.resolveType(context);

  @override
  String toString() {
    return 'return $value ;';
  }
}

/// [ASTStatement] to return a [variable].
class ASTStatementReturnVariable extends ASTStatementReturn
    implements ASTStatementTyped {
  ASTVariable variable;

  ASTStatementReturnVariable(this.variable);

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    variable.resolveNode(parentNode);
  }

  @override
  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus) {
    var value = variable.getValue(parentContext);
    return runStatus.returnFutureOrValue(value);
  }

  @override
  FutureOr<ASTType> resolveType(VMContext? context) =>
      variable.resolveType(context);

  @override
  String toString() {
    return 'return $variable ;';
  }
}

/// [ASTStatement] to return an [expression].
class ASTStatementReturnWithExpression extends ASTStatementReturn
    implements ASTStatementTyped {
  ASTExpression expression;

  ASTStatementReturnWithExpression(this.expression);

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    expression.resolveNode(parentNode);
  }

  @override
  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus) {
    var value = expression.run(parentContext, runStatus);
    return runStatus.returnFutureOrValue(value);
  }

  @override
  FutureOr<ASTType> resolveType(VMContext? context) =>
      expression.resolveType(context);

  @override
  String toString() {
    return 'return $expression ;';
  }
}

/// [ASTStatement] that declares a scope variable.
class ASTStatementVariableDeclaration<V> extends ASTStatementTyped {
  ASTType<V> type;

  String name;

  ASTExpression? value;

  ASTStatementVariableDeclaration(this.type, this.name, this.value);

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    value?.resolveNode(this);
  }

  @override
  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus) {
    return type
        .resolveType(parentContext)
        .resolveMapped((variableResolvedType) {
      return _runImpl(parentContext, runStatus, variableResolvedType);
    });
  }

  Future<ASTValue<dynamic>> _runImpl(VMContext parentContext,
      ASTRunStatus runStatus, ASTType variableResolvedType) async {
    var value = this.value;
    if (value != null) {
      return value
          .resolveType(parentContext)
          .resolveMapped((valueResolvedType) {
        return _runImpl2(parentContext, variableResolvedType, valueResolvedType,
            runStatus, value);
      });
    } else {
      var initValue = ASTValueNull.instance;
      parentContext.declareVariableWithValue(
          variableResolvedType, name, initValue);
      return initValue;
    }
  }

  Future<ASTValue<dynamic>> _runImpl2(
      VMContext parentContext,
      ASTType variableResolvedType,
      ASTType valueResolvedType,
      ASTRunStatus runStatus,
      ASTExpression value) async {
    if (!valueResolvedType.canCastToType(variableResolvedType)) {
      throw ApolloVMRuntimeError(
          "Can't cast variable type ($variableResolvedType) to type: $type");
    }

    var initValue = await value.run(parentContext, runStatus);

    if (!(await initValue.isInstanceOfAsync(variableResolvedType))) {
      throw ApolloVMRuntimeError(
          "Can't cast initial ($initValue) value to type: $type");
    }

    parentContext.declareVariableWithValue(
        variableResolvedType, name, initValue);
    return initValue;
  }

  @override
  FutureOr<ASTType> resolveType(VMContext? context) =>
      type.resolveType(context);

  @override
  String toString() {
    if (value != null) {
      return '$type $name = $value ;';
    } else {
      return '$type $name;';
    }
  }
}

/// [ASTStatement] base for branches.
abstract class ASTBranch extends ASTStatement {
  FutureOr<bool> evaluateCondition(VMContext parentContext,
      ASTRunStatus runStatus, ASTExpression condition) async {
    var evaluation = await condition.run(parentContext, runStatus);
    var evalValue = await evaluation.getValue(parentContext);

    if (evalValue is! bool) {
      throw ApolloVMRuntimeError(
          'A branch condition should return a boolean: $evalValue');
    }

    return evalValue;
  }

  @override
  ASTType resolveType(VMContext? context) => ASTTypeVoid.instance;
}

/// [ASTBranch] simple IF: `if (exp) {}`
class ASTBranchIfBlock extends ASTBranch {
  ASTExpression condition;
  ASTBlock block;

  ASTBranchIfBlock(this.condition, this.block);

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    condition.resolveNode(parentNode);
    block.resolveNode(parentNode);
  }

  @override
  FutureOr<ASTValue> run(
      VMContext parentContext, ASTRunStatus runStatus) async {
    var evalValue =
        await evaluateCondition(parentContext, runStatus, condition);

    if (evalValue) {
      await block.run(parentContext, runStatus);
    }

    return ASTValueVoid.instance;
  }

  @override
  String toString() {
    return 'if ( $condition ) $block';
  }
}

/// [ASTBranch] IF,ELSE: `if (exp) {} else {}`
class ASTBranchIfElseBlock extends ASTBranch {
  ASTExpression condition;
  ASTBlock blockIf;
  ASTBlock? blockElse;

  ASTBranchIfElseBlock(this.condition, this.blockIf, this.blockElse);

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    condition.resolveNode(parentNode);
    blockIf.resolveNode(parentNode);
    blockElse?.resolveNode(parentNode);
  }

  @override
  FutureOr<ASTValue> run(
      VMContext parentContext, ASTRunStatus runStatus) async {
    var evalValue =
        await evaluateCondition(parentContext, runStatus, condition);

    if (evalValue) {
      await blockIf.run(parentContext, runStatus);
    } else {
      await blockElse?.run(parentContext, runStatus);
    }

    return ASTValueVoid.instance;
  }

  @override
  String toString() {
    return 'if ( $condition ) $blockIf\nelse $blockElse';
  }
}

/// [ASTBranch] IF,ELSE IF,ELSE: `if (exp) {} else if (exp) {}* else {}`
class ASTBranchIfElseIfsElseBlock extends ASTBranch {
  ASTExpression condition;
  ASTBlock blockIf;
  List<ASTBranchIfBlock> blocksElseIf;
  ASTBlock? blockElse;

  ASTBranchIfElseIfsElseBlock(
      this.condition, this.blockIf, this.blocksElseIf, this.blockElse);

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    condition.resolveNode(parentNode);

    blockIf.resolveNode(parentNode);

    for (var e in blocksElseIf) {
      e.resolveNode(parentNode);
    }

    blockElse?.resolveNode(parentNode);
  }

  @override
  FutureOr<ASTValue> run(
      VMContext parentContext, ASTRunStatus runStatus) async {
    var evalValue =
        await evaluateCondition(parentContext, runStatus, condition);
    if (evalValue) {
      await blockIf.run(parentContext, runStatus);
      return ASTValueVoid.instance;
    } else {
      for (var branch in blocksElseIf) {
        evalValue =
            await evaluateCondition(parentContext, runStatus, branch.condition);

        if (evalValue) {
          await branch.block.run(parentContext, runStatus);
          return ASTValueVoid.instance;
        }
      }

      await blockElse?.run(parentContext, runStatus);
      return ASTValueVoid.instance;
    }
  }

  @override
  String toString() {
    var str = StringBuffer();
    str.write('if ( $condition ) $blockIf\n');

    for (var e in blocksElseIf) {
      str.write('else $e');
    }

    str.write('else $blockElse');

    return str.toString();
  }
}

class ASTStatementForLoop extends ASTStatement {
  final ASTStatement initStatement;

  final ASTExpression conditionExpression;

  final ASTExpression continueExpression;

  final ASTBlock loopBlock;

  ASTStatementForLoop(this.initStatement, this.conditionExpression,
      this.continueExpression, this.loopBlock);

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    initStatement.resolveNode(parentNode);
    conditionExpression.resolveNode(parentNode);
    continueExpression.resolveNode(parentNode);

    loopBlock.resolveNode(parentNode);
  }

  @override
  VMContext defineRunContext(VMContext parentContext) {
    return parentContext;
  }

  @override
  FutureOr<ASTValue> run(
      VMContext parentContext, ASTRunStatus runStatus) async {
    var context = VMContext(parentContext.block, parent: parentContext);
    var runStatus = ASTRunStatus();

    var prevContext = VMContext.setCurrent(context);
    try {
      await initStatement.run(context, runStatus);

      while (true) {
        var cond = await conditionExpression.run(context, runStatus);

        if (cond is ASTValueBool) {
          if (!cond.value) break;
        } else {
          var condOK = await cond.getValue(context);

          if (condOK is bool) {
            if (!condOK) break;
          } else {
            throw ApolloVMRuntimeError(
                'Condition not returning a boolean: $condOK');
          }
        }

        var loopContext = VMContext(parentContext.block, parent: context);

        VMContext.setCurrent(loopContext);

        await loopBlock.run(loopContext, runStatus);

        VMContext.setCurrent(context);

        await continueExpression.run(context, runStatus);
      }
    } finally {
      VMContext.setCurrent(prevContext);
    }

    return ASTValueVoid.instance;
  }

  @override
  ASTType resolveType(VMContext? context) => ASTTypeVoid.instance;
}
