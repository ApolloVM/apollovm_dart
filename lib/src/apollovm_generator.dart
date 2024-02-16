// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'apollovm_code_storage.dart';
import 'ast/apollovm_ast_base.dart';
import 'ast/apollovm_ast_expression.dart';
import 'ast/apollovm_ast_statement.dart';
import 'ast/apollovm_ast_toplevel.dart';
import 'ast/apollovm_ast_type.dart';
import 'ast/apollovm_ast_value.dart';
import 'ast/apollovm_ast_variable.dart';

/// Base class for generators.
///
/// An [ASTRoot] loaded in [ApolloVM] can be converted to another representation.
abstract class ApolloGenerator<O extends Object,
    S extends ApolloCodeUnitStorage<D>, D extends Object> {
  /// Target programming language of this code generator implementation.
  final String language;

  /// The code storage for generated code.
  final S codeStorage;

  ApolloGenerator(String language, this.codeStorage)
      : language = language.trim().toLowerCase();

  D toStorageData(O out);

  O newOutput();

  O generateASTNode(ASTNode node, {O? out}) {
    if (node is ASTValue) {
      return generateASTValue(node, out: out);
    } else if (node is ASTExpression) {
      return generateASTExpression(node, out: out);
    } else if (node is ASTRoot) {
      return generateASTRoot(node, out: out);
    } else if (node is ASTClassNormal) {
      return generateASTClass(node, out: out);
    } else if (node is ASTBlock) {
      return generateASTBlock(node, out: out);
    } else if (node is ASTStatement) {
      return generateASTStatement(node, out: out);
    } else if (node is ASTClassFunctionDeclaration) {
      return generateASTClassFunctionDeclaration(node, out: out);
    } else if (node is ASTFunctionDeclaration) {
      return generateASTFunctionDeclaration(node, out: out);
    }

    throw UnsupportedError("Can't handle ASTNode: $node");
  }

  O generateASTRoot(ASTRoot root, {O? out}) {
    out ??= newOutput();

    generateASTBlock(root, out: out);

    for (var clazz in root.classes) {
      generateASTClass(clazz, out: out);
    }

    return out;
  }

  O generateASTBlock(ASTBlock block, {O? out});

  O generateASTClass(ASTClassNormal clazz, {O? out});

  O generateASTClassField(ASTClassField field, {O? out});

  O generateASTClassFunctionDeclaration(ASTClassFunctionDeclaration f,
      {O? out});

  O generateASTFunctionDeclaration(ASTFunctionDeclaration f, {O? out});

  O generateASTParametersDeclaration(ASTParametersDeclaration parameters,
      {O? out});

  O generateASTFunctionParameterDeclaration(
      ASTFunctionParameterDeclaration parameter,
      {O? out});

  O generateASTParameterDeclaration(ASTParameterDeclaration parameter,
      {O? out});

  O generateASTType(ASTType type, {O? out}) {
    if (type is ASTTypeArray) {
      return generateASTTypeArray(type, out: out);
    } else if (type is ASTTypeArray2D) {
      return generateASTTypeArray2D(type, out: out);
    } else if (type is ASTTypeArray3D) {
      return generateASTTypeArray3D(type, out: out);
    }

    return generateASTTypeDefault(type, out: out);
  }

  O generateASTTypeArray(ASTTypeArray type, {O? out});

  O generateASTTypeArray2D(ASTTypeArray2D type, {O? out});

  O generateASTTypeArray3D(ASTTypeArray3D type, {O? out});

  String normalizeTypeName(String typeName, [String? callingFunction]) =>
      typeName;

  String normalizeTypeFunction(String typeName, String functionName) =>
      functionName;

  O generateASTTypeDefault(ASTType type, {O? out});

  O generateASTStatement(ASTStatement statement, {O? out}) {
    if (statement is ASTStatementExpression) {
      return generateASTStatementExpression(statement, out: out);
    } else if (statement is ASTStatementVariableDeclaration) {
      return generateASTStatementVariableDeclaration(statement, out: out);
    } else if (statement is ASTBranch) {
      return generateASTBranch(statement, out: out);
    } else if (statement is ASTStatementForLoop) {
      return generateASTStatementForLoop(statement, out: out);
    } else if (statement is ASTStatementReturnNull) {
      return generateASTStatementReturnNull(statement, out: out);
    } else if (statement is ASTStatementReturnValue) {
      return generateASTStatementReturnValue(statement, out: out);
    } else if (statement is ASTStatementReturnVariable) {
      return generateASTStatementReturnVariable(statement, out: out);
    } else if (statement is ASTStatementReturnWithExpression) {
      return generateASTStatementReturnWithExpression(statement, out: out);
    } else if (statement is ASTStatementReturn) {
      return generateASTStatementReturn(statement, out: out);
    }

    throw UnsupportedError("Can't handle statement: $statement");
  }

  O generateASTBranch(ASTBranch branch, {O? out}) {
    if (branch is ASTBranchIfBlock) {
      return generateASTBranchIfBlock(branch, out: out);
    } else if (branch is ASTBranchIfElseBlock) {
      return generateASTBranchIfElseBlock(branch, out: out);
    } else if (branch is ASTBranchIfElseIfsElseBlock) {
      return generateASTBranchIfElseIfsElseBlock(branch, out: out);
    }

    throw UnsupportedError("Can't handle branch: $branch");
  }

  O generateASTStatementForLoop(ASTStatementForLoop forLoop, {O? out});

  O generateASTBranchIfBlock(ASTBranchIfBlock branch, {O? out});

  O generateASTBranchIfElseBlock(ASTBranchIfElseBlock branch, {O? out});

  O generateASTBranchIfElseIfsElseBlock(ASTBranchIfElseIfsElseBlock branch,
      {O? out});

  O generateASTStatementExpression(ASTStatementExpression statement, {O? out});

  O generateASTStatementVariableDeclaration(
      ASTStatementVariableDeclaration statement,
      {O? out});

  O generateASTExpressionVariableAssignment(
      ASTExpressionVariableAssignment expression,
      {O? out});

  O generateASTExpressionVariableDirectOperation(
      ASTExpressionVariableDirectOperation expression,
      {O? out});

  O generateASTStatementReturn(ASTStatementReturn statement, {O? out});

  O generateASTStatementReturnNull(ASTStatementReturnNull statement, {O? out});

  O generateASTStatementReturnValue(ASTStatementReturnValue statement,
      {O? out});

  O generateASTStatementReturnVariable(ASTStatementReturnVariable statement,
      {O? out});

  O generateASTStatementReturnWithExpression(
      ASTStatementReturnWithExpression statement,
      {O? out});

  O generateASTExpression(ASTExpression expression, {O? out}) {
    if (expression is ASTExpressionVariableAccess) {
      return generateASTExpressionVariableAccess(expression, out: out);
    } else if (expression is ASTExpressionVariableAssignment) {
      return generateASTExpressionVariableAssignment(expression, out: out);
    } else if (expression is ASTExpressionVariableEntryAccess) {
      return generateASTExpressionVariableEntryAccess(expression, out: out);
    } else if (expression is ASTExpressionLiteral) {
      return generateASTExpressionLiteral(expression, out: out);
    } else if (expression is ASTExpressionListLiteral) {
      return generateASTExpressionListLiteral(expression, out: out);
    } else if (expression is ASTExpressionMapLiteral) {
      return generateASTExpressionMapLiteral(expression, out: out);
    } else if (expression is ASTExpressionNegation) {
      return generateASTExpressionNegation(expression, out: out);
    } else if (expression is ASTExpressionLocalFunctionInvocation) {
      return generateASTExpressionLocalFunctionInvocation(expression, out: out);
    } else if (expression is ASTExpressionObjectFunctionInvocation) {
      return generateASTExpressionFunctionInvocation(expression, out: out);
    } else if (expression is ASTExpressionOperation) {
      return generateASTExpressionOperation(expression, out: out);
    }

    throw UnsupportedError("Can't generate expression: $expression");
  }

  O generateASTExpressionOperation(ASTExpressionOperation expression, {O? out});

  String resolveASTExpressionOperatorText(
      ASTExpressionOperator operator, ASTNumType aNumType, ASTNumType bNumType);

  O generateASTExpressionLiteral(ASTExpressionLiteral expression, {O? out});

  O generateASTExpressionListLiteral(ASTExpressionListLiteral expression,
      {O? out});

  O generateASTExpressionMapLiteral(ASTExpressionMapLiteral expression,
      {O? out});

  O generateASTExpressionNegation(ASTExpressionNegation expression, {O? out});

  O generateASTExpressionFunctionInvocation(
      ASTExpressionObjectFunctionInvocation expression,
      {O? out});

  O generateASTExpressionLocalFunctionInvocation(
      ASTExpressionLocalFunctionInvocation expression,
      {O? out});

  O generateASTExpressionVariableAccess(ASTExpressionVariableAccess expression,
      {O? out});

  O generateASTExpressionVariableEntryAccess(
      ASTExpressionVariableEntryAccess expression,
      {O? out});

  O generateASTVariable(ASTVariable variable,
      {String? callingFunction, O? out});

  O generateASTScopeVariable(ASTScopeVariable variable,
      {String? callingFunction, O? out});

  O generateASTVariableGeneric(ASTVariable variable,
      {String? callingFunction, O? out});

  O generateASTValue(ASTValue value, {O? out}) {
    if (value is ASTValueString) {
      return generateASTValueString(value, out: out);
    } else if (value is ASTValueInt) {
      return generateASTValueInt(value, out: out);
    } else if (value is ASTValueDouble) {
      return generateASTValueDouble(value, out: out);
    } else if (value is ASTValueNull) {
      return generateASTValueNull(value, out: out);
    } else if (value is ASTValueVar) {
      return generateASTValueVar(value, out: out);
    } else if (value is ASTValueObject) {
      return generateASTValueObject(value, out: out);
    } else if (value is ASTValueStatic) {
      return generateASTValueStatic(value, out: out);
    } else if (value is ASTValueStringVariable) {
      return generateASTValueStringVariable(value, out: out);
    } else if (value is ASTValueStringConcatenation) {
      return generateASTValueStringConcatenation(value, out: out);
    } else if (value is ASTValueStringExpression) {
      return generateASTValueStringExpression(value, out: out);
    } else if (value is ASTValueArray) {
      return generateASTValueArray(value, out: out);
    } else if (value is ASTValueArray2D) {
      return generateASTValueArray2D(value, out: out);
    } else if (value is ASTValueArray3D) {
      return generateASTValueArray3D(value, out: out);
    }

    throw UnsupportedError("Can't generate value: $value");
  }

  O generateASTValueStringConcatenation(ASTValueStringConcatenation value,
      {O? out});

  O generateASTValueStringVariable(ASTValueStringVariable value,
      {O? out, bool precededByString = false});

  O generateASTValueStringExpression(ASTValueStringExpression value, {O? out});

  O generateASTValueString(ASTValueString value, {O? out});

  O generateASTValueInt(ASTValueInt value, {O? out});

  O generateASTValueDouble(ASTValueDouble value, {O? out});

  O generateASTValueNull(ASTValueNull value, {O? out});

  O generateASTValueVar(ASTValueVar value, {O? out});

  O generateASTValueObject(ASTValueObject value, {O? out});

  O generateASTValueStatic(ASTValueStatic value, {O? out});

  O generateASTValueArray(ASTValueArray value, {O? out});

  O generateASTValueArray2D(ASTValueArray2D value, {O? out});

  O generateASTValueArray3D(ASTValueArray3D value, {O? out});
}
