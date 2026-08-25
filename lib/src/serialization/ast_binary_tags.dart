// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

/// Wire tags for AST node kinds.
///
/// **These numbers are part of the file format.** A tag is never renumbered and
/// never reused, even after the node kind it named is gone — retire it in
/// [ASTNodeTag.retired] instead. That is what lets a build read files written
/// by every earlier build.
///
/// Numbers are assigned roughly by how often a node appears in a real program,
/// so the hot ones stay under 128 and cost a single LEB128 byte: expressions,
/// values and variables first, then the common statements, then declarations
/// and the rarities.
class ASTNodeTag {
  ASTNodeTag._();

  /// Written in place of a node that is absent. Never a real node kind.
  static const int nullNode = 0;

  // --- Values (hot: every literal in the program) ---------------------------

  static const int valueBool = 1;
  static const int valueInt = 2;
  static const int valueDouble = 3;
  static const int valueString = 4;
  static const int valueNull = 5;
  static const int valueVoid = 6;
  static const int valueVar = 7;
  static const int valueObject = 8;
  static const int valueStatic = 9;
  static const int valueArray = 10;
  static const int valueArray2D = 11;
  static const int valueArray3D = 12;
  static const int valueMap = 13;
  static const int valueAsString = 14;
  static const int valuesListAsString = 15;
  static const int valueStringExpression = 16;
  static const int valueStringVariable = 17;
  static const int valueStringConcatenation = 18;

  // --- Variables ------------------------------------------------------------

  static const int scopeVariable = 20;
  static const int thisVariable = 21;
  static const int classField = 22;
  static const int classFieldWithInitialValue = 23;
  static const int staticFieldVariable = 24;
  static const int expressionVariable = 25;

  // --- Expressions ----------------------------------------------------------

  static const int expressionLiteral = 30;
  static const int expressionVariableAccess = 31;
  static const int expressionNullValue = 32;
  static const int expressionOperation = 33;
  static const int expressionVariableAssignment = 34;
  static const int expressionLocalFunctionInvocation = 35;
  static const int expressionObjectFunctionInvocation = 36;
  static const int expressionChainFunctionInvocation = 37;
  static const int expressionGroupFunctionInvocation = 38;
  static const int expressionObjectEntryFunctionInvocation = 39;
  static const int expressionLocalGetterAccess = 40;
  static const int expressionObjectGetterAccess = 41;
  static const int expressionObjectSetterAssignment = 42;
  static const int expressionVariableEntryAccess = 43;
  static const int expressionVariableEntryAssignment = 44;
  static const int expressionVariableDirectOperation = 45;
  static const int expressionConditional = 46;
  static const int expressionLogicalAnd = 47;
  static const int expressionLogicalOr = 48;
  static const int expressionNegation = 49;
  static const int expressionNegative = 50;
  static const int expressionBitwiseNot = 51;
  static const int expressionNullAssertion = 52;
  static const int expressionNullCoalesce = 53;
  static const int expressionNullCheck = 54;
  static const int expressionAwait = 55;
  static const int expressionCascade = 56;
  static const int expressionListLiteral = 57;
  static const int expressionMapLiteral = 58;
  static const int expressionLiteralFunction = 59;

  // --- Statements -----------------------------------------------------------

  static const int block = 65;
  static const int singleLineStatementBlock = 66;
  static const int statementExpression = 67;
  static const int statementVariableDeclaration = 68;
  static const int statementReturn = 69;
  static const int statementReturnNull = 70;
  static const int statementReturnValue = 71;
  static const int statementReturnVariable = 72;
  static const int statementReturnWithExpression = 73;
  static const int statementBlock = 74;
  static const int statementValue = 75;
  static const int statementFunctionDeclaration = 76;
  static const int branchIfBlock = 77;
  static const int branchIfElseBlock = 78;
  static const int branchIfElseIfsElseBlock = 79;
  static const int statementWhileLoop = 80;
  static const int statementDoWhileLoop = 81;
  static const int statementForLoop = 82;
  static const int statementForEach = 83;
  static const int statementBreak = 84;
  static const int statementContinue = 85;
  static const int statementSwitch = 86;
  static const int switchCase = 87;
  static const int statementThrow = 88;
  static const int statementAssert = 89;
  static const int statementTryCatch = 90;
  static const int catchClause = 91;

  // --- Declarations and top level -------------------------------------------

  static const int root = 100;
  static const int classNormal = 101;
  static const int classEnum = 102;
  static const int enumEntry = 103;
  static const int extension = 104;
  static const int typeAlias = 105;
  static const int functionDeclaration = 106;
  static const int classFunctionDeclaration = 107;
  static const int classConstructorDeclaration = 108;
  static const int getterDeclaration = 109;
  static const int classGetterDeclaration = 110;
  static const int setterDeclaration = 111;
  static const int classSetterDeclaration = 112;
  static const int functionParameterDeclaration = 113;
  static const int constructorParameterDeclaration = 114;
  static const int functionParametersDeclaration = 115;
  static const int constructorParametersDeclaration = 116;
  static const int statementImport = 117;
  static const int statementExport = 118;
  static const int importCombinator = 119;
  static const int importedSymbol = 120;

  /// Tags that once existed and must never be handed out again.
  ///
  /// Empty today. When a node kind is removed, its number moves here rather
  /// than becoming available, so an old file can still be diagnosed precisely
  /// instead of decoding as whatever took the number over.
  static const Set<int> retired = <int>{};
}
