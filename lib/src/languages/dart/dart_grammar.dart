import 'package:apollovm/src/apollovm_ast.dart';
import 'package:petitparser/petitparser.dart';

import 'dart_grammar_lexer.dart';

/// Dart grammar.
class DartGrammar extends GrammarParser {
  DartGrammar() : super(DartGrammarDefinition());
}

/// Dart grammar definition.
class DartGrammarDefinition extends DartGrammarLexer {
  static ASTType getTypeByName(String name) {
    switch (name) {
      case 'Object':
        return ASTTypeObject.INSTANCE;
      case 'int':
        return ASTTypeInt.INSTANCE;
      case 'double':
        return ASTTypeDouble.INSTANCE;
      case 'String':
        return ASTTypeString.INSTANCE;
      case 'dynamic':
        return ASTTypeDynamic.INSTANCE;
      case 'List':
        return ASTTypeArray(ASTTypeDynamic.INSTANCE);
      default:
        return ASTType(name);
    }
  }

  @override
  Parser start() => ref(compilationUnit).trim().end();

  Parser<ASTCodeRoot> compilationUnit() =>
      (ref(hashbangLexicalToken).optional() &
              //ref(libraryDirective).optional() &
              //ref(importDirective).star() &
              ref(topLevelDefinition).star())
          .map((v) {
        var topDef = v[1];

        var functions = topDef as List;

        var root = ASTCodeRoot();

        root.addAllFunctions(functions.cast());

        return root;
      });

  Parser topLevelDefinition() => functionDeclaration();

  Parser<ASTFunctionDeclaration> functionDeclaration() =>
      (type() & identifier() & parametersDeclaration() & codeBlock()).map((v) {
        return ASTFunctionDeclaration(v[1], v[2], v[0], v[3]);
      });

  Parser<ASTCodeBlock> codeBlock() =>
      (char('{').trim() & ref(statement).star() & char('}').trim()).map((v) {
        var statements = (v[1] as List).cast<ASTStatement>().toList();
        return ASTCodeBlock(null)..addAllStatements(statements);
      });

  Parser<ASTStatement> statement() =>
      (statementVariableDeclaration() | statementExpression())
          .cast<ASTStatement>();

  Parser<ASTStatementExpression> statementExpression() =>
      (expression() & char(';').trim()).map((v) {
        return ASTStatementExpression(v[0]);
      });

  Parser<ASTStatementVariableDeclaration> statementVariableDeclaration() =>
      (type() &
              identifier() &
              (char('=') & ref(expression)).optional() &
              char(';').trim())
          .map((v) {
        var valueOpt = v[2];
        var value = valueOpt != null ? valueOpt[1] : null;
        return ASTStatementVariableDeclaration(v[0], v[1], value);
      });

  Parser<ASTExpression> expression() => (expressionVariableAssigment() |
          expressionLocalFunctionInvocation() |
          expressionVariableEntryAccess() |
          expressionVariableAccess() |
          expressionLiteral())
      .cast<ASTExpression>();

  Parser<ASTExpressionLocalFunctionInvocation>
      expressionLocalFunctionInvocation() =>
          (identifier() & char('(') & ref(expression).star() & char(')'))
              .map((v) {
            var args = v[2] as List;
            return ASTExpressionLocalFunctionInvocation(
                v[0], args.cast<ASTExpression>().toList());
          });

  Parser<ASTExpressionVariableAccess> expressionVariableAccess() =>
      (variable()).map((v) {
        return ASTExpressionVariableAccess(v);
      });

  Parser<ASTExpressionLiteral> expressionLiteral() => (literal()).map((v) {
        return ASTExpressionLiteral(v);
      });

  Parser<ASTExpressionVariableEntryAccess> expressionVariableEntryAccess() =>
      (variable() & char('[') & ref(expression) & char(']')).map((v) {
        var variable = v[0];
        var expression = v[2];
        return ASTExpressionVariableEntryAccess(variable, expression);
      });

  Parser<ASTExpressionVariableAssignment> expressionVariableAssigment() =>
      (variable() & assigmentOperator() & ref(expression)).map((v) {
        return ASTExpressionVariableAssignment(v[0], v[1], v[2]);
      });

  Parser<AssignmentOperator> assigmentOperator() =>
      (char('=').trim() | string('+=').trim()).map((v) {
        return getAssignmentOperator(v);
      });

  Parser<ASTVariable> variable() =>
      (thisVariable() | scopeVariable()).cast<ASTVariable>();

  Parser<ASTThisVariable> thisVariable() => (token('this')).map((v) {
        return ASTThisVariable();
      });

  Parser<ASTScopeVariable> scopeVariable() => (identifier()).map((v) {
        return ASTScopeVariable(v);
      });

  Parser<ASTParametersDeclaration> parametersDeclaration() =>
      (emptyParametersDeclaration() | positionalParametersDeclaration())
          .cast<ASTParametersDeclaration>();

  Parser<ASTParametersDeclaration> emptyParametersDeclaration() =>
      (char('(') & char(')')).map((v) {
        return ASTParametersDeclaration(null, null, null);
      });

  Parser<ASTParametersDeclaration> positionalParametersDeclaration() =>
      (char('(') & parametersList() & char(')')).map((v) {
        return ASTParametersDeclaration(v[1], null, null);
      });

  Parser<List<ASTFunctionParameterDeclaration>> parametersList() =>
      (parameterDeclaration() & (char(',') & parameterDeclaration()).star())
          .map((v) {
        return v
            .expand((e) => e is List ? e : [e])
            .cast<ASTFunctionParameterDeclaration>()
            .toList();
      });

  Parser<ASTFunctionParameterDeclaration> parameterDeclaration() =>
      (type() & identifier()).map((v) {
        return ASTFunctionParameterDeclaration(v[0], v[1], -1, false);
      });

  Parser<ASTType> type() =>
      (arrayTyped() | arrayTypeDynamic() | simpleType()).cast<ASTType>();

  Parser<ASTType> simpleType() => identifier().map((v) {
        return getTypeByName(v);
      });

  Parser<ASTTypeArray> arrayTyped() =>
      (array3DTyped() | array2DTyped() | array1DTyped()).cast<ASTTypeArray>();

  Parser<ASTTypeArray> array1DTyped() =>
      (string('List') & char('<') & simpleType() & char('>')).map((v) {
        var t = ASTType.from(v[2]);
        return ASTTypeArray(t);
      });

  Parser<ASTTypeArray2D> array2DTyped() => (string('List') &
              char('<') &
              string('List') &
              char('<') &
              simpleType() &
              char('>') &
              char('>'))
          .map((v) {
        var t = ASTType.from(v[4]);
        return ASTTypeArray2D.fromElementType(t);
      });

  Parser<ASTTypeArray3D> array3DTyped() => (string('List') &
              char('<') &
              string('List') &
              char('<') &
              string('List') &
              char('<') &
              simpleType() &
              char('>') &
              char('>') &
              char('>'))
          .map((v) {
        var t = ASTType.from(v[4]);
        return ASTTypeArray3D.fromElementType(t);
      });

  Parser<ASTTypeArray> arrayTypeDynamic() =>
      (array3DTypeDynamic() | array2DTypeDynamic() | array1DTypeDynamic())
          .cast<ASTTypeArray>();

  Parser<ASTTypeArray> array1DTypeDynamic() => string('List').map((v) {
        return ASTTypeArray(ASTTypeDynamic.INSTANCE);
      });

  Parser<ASTTypeArray2D> array2DTypeDynamic() =>
      (string('List') & char('<') & string('List') & char('>')).map((v) {
        return ASTTypeArray2D.fromElementType(ASTTypeDynamic.INSTANCE);
      });

  Parser<ASTTypeArray3D> array3DTypeDynamic() => (string('List') &
              char('<') &
              string('List') &
              char('<') &
              string('List') &
              char('>') &
              char('>'))
          .map((v) {
        return ASTTypeArray3D.fromElementType(ASTTypeDynamic.INSTANCE);
      });

  Parser<ASTValue> literal() =>
      (literalNum() | literalString()).cast<ASTValue>();

  Parser<ASTValueNum> literalNum() => (numberLexicalToken()).map((v) {
        return ASTValueNum.from(v);
      });

  Parser<ASTValueString> literalString() => (stringLexicalToken()).map((v) {
        return ASTValueString(v);
      });
}
