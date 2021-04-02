import 'package:apollovm/apollovm.dart';
import 'package:apollovm/src/apollovm_ast.dart';
import 'package:petitparser/petitparser.dart';

import 'java8_grammar_lexer.dart';

/// Dart grammar.
class Java8Grammar extends GrammarParser {
  Java8Grammar() : super(Java8GrammarDefinition());
}

/// Dart grammar definition.
class Java8GrammarDefinition extends Java8GrammarLexer {
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
              //ref(importDirective).star() &
              ref(topLevelDefinition).star())
          .map((v) {
        var topDef = v[1];

        var classes = topDef as List;

        var root = ASTCodeRoot();

        root.addAllClasses(classes.cast());

        return root;
      });

  Parser topLevelDefinition() => (classDeclaration());

  Parser<ASTCodeClass> classDeclaration() =>
      (string('class').trim() & identifier() & classCodeBlock()).map((v) {
        var block = v[2];
        var clazz = ASTCodeClass(v[1], null);
        clazz.set(block);
        return clazz;
      });

  Parser<ASTCodeBlock> classCodeBlock() =>
      (char('{').trim() & ref(functionDeclaration).star() & char('}').trim())
          .map((v) {
        var functions = (v[1] as List).cast<ASTFunctionDeclaration>().toList();
        return ASTCodeBlock(null)..addAllFunctions(functions);
      });

  Parser<ASTFunctionDeclaration> functionDeclaration() =>
      (modifiers().optional() &
              type() &
              identifier() &
              parametersDeclaration() &
              codeBlock())
          .map((v) {
        //var modifier = v[0];
        var returnType = v[1];
        var name = v[2];
        var parameters = v[3];
        var block = v[4];
        return ASTFunctionDeclaration(name, parameters, returnType, block);
      });

  Parser<List<String>> modifiers() => (modifier().plus());

  Parser<String> modifier() => (string('public') |
          string('private') |
          string('final') |
          string('static'))
      .trim()
      .flatten();

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

  Parser<ASTType> type() => (arrayType() | simpleType()).cast<ASTType>();

  Parser<ASTType> simpleType() => identifier().map((v) {
        return getTypeByName(v);
      });

  Parser<ASTTypeArray> arrayType() =>
      (identifier() & string('[]').plus()).map((v) {
        var t = getTypeByName(v[0]);
        var dims = (v[1] as List).length;
        switch (dims) {
          case 1:
            return ASTTypeArray(t);
          case 2:
            return ASTTypeArray2D.fromElementType(t);
          case 3:
            return ASTTypeArray3D.fromElementType(t);
          default:
            throw UnsupportedSyntaxError(
                "Can't parse array with $dims dimensions: $dims");
        }
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
