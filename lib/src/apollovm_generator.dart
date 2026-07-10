// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'apollovm_code_storage.dart';
import 'ast/apollovm_ast_expression.dart';
import 'ast/apollovm_ast_statement.dart';
import 'ast/apollovm_ast_toplevel.dart';
import 'ast/apollovm_ast_type.dart';
import 'ast/apollovm_ast_value.dart';
import 'ast/apollovm_ast_variable.dart';

/// Base class for generators.
///
/// An [ASTRoot] loaded in [ApolloVM] can be converted to another representation.
abstract class ApolloGenerator<
  O extends Object,
  S extends ApolloCodeUnitStorage<D>,
  D extends Object
> {
  /// Target programming language of this code generator implementation.
  final String language;

  /// The code storage for generated code.
  final S codeStorage;

  ApolloGenerator(String language, this.codeStorage)
    : language = language.trim().toLowerCase();

  D toStorageData(O out);

  O newOutput();

  O generateASTRoot(ASTRoot root, {O? out});

  O generateASTBlock(ASTBlock block, {O? out});

  O generateASTSingleLineStatementBlock(
    ASTSingleLineStatementBlock block, {
    O? out,
  });

  O generateASTStatementImport(ASTStatementImport import, {O? out});

  O generateASTClass(ASTClassNormal clazz, {O? out});

  O generateASTClassField(ASTClassField field, {O? out});

  O generateASTClassConstructorDeclaration(
    ASTClassConstructorDeclaration constructor, {
    O? out,
  });

  O generateASTClassFunctionDeclaration(
    ASTClassFunctionDeclaration f, {
    O? out,
  });

  O generateASTFunctionDeclaration(ASTFunctionDeclaration f, {O? out});

  O generateASTParametersDeclaration(
    ASTParametersDeclaration parameters, {
    O? out,
  });

  O generateASTFunctionParameterDeclaration(
    ASTFunctionParameterDeclaration parameter, {
    O? out,
  });

  O generateASTParameterDeclaration(
    ASTParameterDeclaration parameter, {
    O? out,
  });

  O generateASTTypeArray(ASTTypeArray type, {O? out});

  O generateASTTypeArray2D(ASTTypeArray2D type, {O? out});

  O generateASTTypeArray3D(ASTTypeArray3D type, {O? out});

  String normalizeTypeName(String typeName, [String? callingFunction]) =>
      typeName;

  String normalizeTypeFunction(String typeName, String functionName) =>
      functionName;

  O generateASTTypeDefault(ASTType type, {O? out});

  O generateASTStatement(ASTStatement statement, {O? out});

  O generateASTBranch(ASTBranch branch, {O? out});

  O generateASTStatementForLoop(ASTStatementForLoop forLoop, {O? out});

  O generateASTStatementForEach(ASTStatementForEach forEach, {O? out});

  O generateASTStatementWhileLoop(ASTStatementWhileLoop whileLoop, {O? out});

  O generateASTBranchIfBlock(ASTBranchIfBlock branch, {O? out});

  O generateASTBranchIfElseBlock(ASTBranchIfElseBlock branch, {O? out});

  O generateASTBranchIfElseIfsElseBlock(
    ASTBranchIfElseIfsElseBlock branch, {
    O? out,
  });

  O generateASTStatementExpression(ASTStatementExpression statement, {O? out});

  O generateASTStatementVariableDeclaration(
    ASTStatementVariableDeclaration statement, {
    O? out,
  });

  O generateASTStatementFunctionDeclaration(
    ASTStatementFunctionDeclaration statement, {
    O? out,
  });

  O generateASTExpressionVariableAssignment(
    ASTExpressionVariableAssignment expression, {
    O? out,
  });

  O generateASTExpressionVariableEntryAssignment(
    ASTExpressionVariableEntryAssignment expression, {
    O? out,
  }) => throw UnsupportedError("Can't generate entry assignment: $expression");

  O generateASTExpressionVariableDirectOperation(
    ASTExpressionVariableDirectOperation expression, {
    O? out,
  });

  O generateASTStatementBlock(ASTStatementBlock statement, {O? out});

  O generateASTStatementReturn(ASTStatementReturn statement, {O? out});

  O generateASTStatementReturnNull(ASTStatementReturnNull statement, {O? out});

  O generateASTStatementReturnValue(
    ASTStatementReturnValue statement, {
    O? out,
  });

  O generateASTStatementReturnVariable(
    ASTStatementReturnVariable statement, {
    O? out,
  });

  O generateASTStatementReturnWithExpression(
    ASTStatementReturnWithExpression statement, {
    O? out,
  });

  O generateASTExpression(ASTExpression expression, {O? out});

  O generateASTExpressionOperation(ASTExpressionOperation expression, {O? out});

  O generateASTExpressionConditional(
    ASTExpressionConditional expression, {
    O? out,
  });

  O generateASTExpressionLiteralFunction(
    ASTExpressionLiteralFunction expression, {
    O? out,
  });

  String resolveASTExpressionOperatorText(
    ASTExpressionOperator operator,
    ASTNumType aNumType,
    ASTNumType bNumType,
  );

  O generateASTExpressionLiteral(ASTExpressionLiteral expression, {O? out});

  O generateASTExpressionListLiteral(
    ASTExpressionListLiteral expression, {
    O? out,
  });

  O generateASTExpressionMapLiteral(
    ASTExpressionMapLiteral expression, {
    O? out,
  });

  O generateASTExpressionNegation(ASTExpressionNegation expression, {O? out});

  O generateASTExpressionNegative(ASTExpressionNegative expression, {O? out});

  O generateASTExpressionAwait(ASTExpressionAwait expression, {O? out});

  O generateASTExpressionGroupFunctionInvocation(
    ASTExpressionGroupFunctionInvocation expression, {
    O? out,
  });

  O generateASTExpressionFunctionInvocation(
    ASTExpressionObjectFunctionInvocation expression, {
    O? out,
  });

  O generateASTExpressionObjectEntryFunctionInvocation(
    ASTExpressionObjectEntryFunctionInvocation expression, {
    O? out,
  });

  O generateASTExpressionLocalFunctionInvocation(
    ASTExpressionLocalFunctionInvocation expression, {
    O? out,
  });

  StringBuffer generateASTExpressionObjectGetterAccess(
    ASTExpressionObjectGetterAccess expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  });

  StringBuffer generateASTExpressionLocalGetterAccess(
    ASTExpressionLocalGetterAccess expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  });

  O generateASTExpressionNullValue(ASTExpressionNullValue expression, {O? out});

  O generateASTExpressionVariableAccess(
    ASTExpressionVariableAccess expression, {
    O? out,
  });

  O generateASTExpressionVariableEntryAccess(
    ASTExpressionVariableEntryAccess expression, {
    O? out,
  });

  O generateASTVariable(
    ASTVariable variable, {
    String? callingFunction,
    O? out,
  });

  O generateASTScopeVariable(
    ASTScopeVariable variable, {
    String? callingFunction,
    O? out,
  });

  O generateASTVariableGeneric(
    ASTVariable variable, {
    String? callingFunction,
    O? out,
  });

  O generateASTValue(ASTValue value, {O? out});

  O generateASTValueStringConcatenation(
    ASTValueStringConcatenation value, {
    O? out,
  });

  O generateASTValueStringVariable(
    ASTValueStringVariable value, {
    O? out,
    bool precededByString = false,
  });

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
