import 'package:apollovm/apollovm.dart';
import 'package:petitparser/petitparser.dart';

import 'dart_grammar_lexer.dart';

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
  Parser start() => ref0(compilationUnit).trim().end();

  Parser<ASTRoot> compilationUnit() => (ref0(hashbangLexicalToken).optional() &
              //ref0(libraryDirective).optional() &
              //ref0(importDirective).star() &
              ref0(topLevelDefinition).star())
          .map((v) {
        var topDef = v[1] as List;

        var root = ASTRoot();

        for (var defList in topDef) {
          for (var def in defList) {
            if (def is ASTFunctionDeclaration) {
              root.addFunction(def);
            } else if (def is ASTClass) {
              root.addClass(def);
            }
          }
        }

        return root;
      });

  Parser topLevelDefinition() =>
      (functionDeclaration() | classDeclaration()).plus();

  Parser<ASTClass> classDeclaration() =>
      (string('class').trim() & identifier() & classCodeBlock()).map((v) {
        var block = v[2];
        var clazz = ASTClass(v[1], null);
        clazz.set(block);
        return clazz;
      });

  Parser<ASTBlock> classCodeBlock() =>
      (char('{').trim() & ref0(functionDeclaration).star() & char('}').trim())
          .map((v) {
        var functions = (v[1] as List).cast<ASTFunctionDeclaration>().toList();
        return ASTBlock(null)..addAllFunctions(functions);
      });

  Parser<ASTFunctionDeclaration> functionDeclaration() =>
      (type() & identifier() & parametersDeclaration() & codeBlock()).map((v) {
        return ASTFunctionDeclaration(v[1], v[2], v[0], v[3]);
      });

  Parser<ASTBlock> codeBlock() =>
      (char('{').trim() & ref0(statement).star() & char('}').trim()).map((v) {
        var statements = (v[1] as List).cast<ASTStatement>().toList();
        return ASTBlock(null)..addAllStatements(statements);
      });

  Parser<ASTStatement> statement() =>
      (branch() | statementVariableDeclaration() | statementExpression())
          .cast<ASTStatement>();

  Parser<ASTStatementExpression> statementExpression() =>
      (expression() & char(';').trim()).map((v) {
        return ASTStatementExpression(v[0]);
      });

  Parser<ASTStatementVariableDeclaration> statementVariableDeclaration() =>
      (type() &
              identifier() &
              (char('=') & ref0(expression)).optional() &
              char(';').trim())
          .map((v) {
        var valueOpt = v[2];
        var value = valueOpt != null ? valueOpt[1] : null;
        return ASTStatementVariableDeclaration(v[0], v[1], value);
      });

  Parser<ASTBranch> branch() => (ref0(branchIfElseIfsElseBlock) |
          ref0(branchIfElseBlock) |
          ref0(branchIfBlock))
      .cast<ASTBranch>();

  Parser<ASTBranchIfBlock> branchIfBlock() => (string('if').trim() &
              char('(').trim() &
              ref0(expression) &
              char(')').trim() &
              codeBlock())
          .map((v) {
        var condition = v[2];
        var block = v[4];
        return ASTBranchIfBlock(condition, block);
      });

  Parser<ASTBranchIfElseBlock> branchIfElseBlock() => (string('if').trim() &
              char('(').trim() &
              ref0(expression) &
              char(')').trim() &
              codeBlock() &
              string('else').trim() &
              codeBlock())
          .map((v) {
        var condition = v[2];
        var blockIf = v[4];
        var blockElse = v[6];
        return ASTBranchIfElseBlock(condition, blockIf, blockElse);
      });

  Parser<ASTBranchIfElseIfsElseBlock> branchIfElseIfsElseBlock() =>
      (string('if').trim() &
              char('(').trim() &
              ref0(expression) &
              char(')').trim() &
              codeBlock() &
              ref0(branchElseIfs).plus() &
              string('else').trim() &
              codeBlock())
          .map((v) {
        var condition = v[2];
        var blockIf = v[4];
        var blockElseIfs = v[5] as List;
        var blockElse = v[7];

        return ASTBranchIfElseIfsElseBlock(condition, blockIf,
            blockElseIfs.cast<ASTBranchIfBlock>().toList(), blockElse);
      });

  Parser<ASTBranchIfBlock> branchElseIfs() => (string('else').trim() &
              string('if').trim() &
              char('(').trim() &
              ref0(expression) &
              char(')').trim() &
              codeBlock())
          .map((v) {
        var condition = v[3];
        var blockIf = v[5];
        return ASTBranchIfBlock(condition, blockIf);
      });

  @override
  Parser<ParsedString> parseExpressionInString() =>
      expression().map((e) => ParsedString.expression(e));

  Parser<ASTExpression> expression() => (ref0(expressionNoOperation) &
              (expressionOperator() & ref0(expressionNoOperation)).star())
          .map((v) {
        var exp1 = v[0];

        var rest = v[1] as List;
        if (rest.isEmpty) {
          return exp1;
        }

        var extra = rest.expand((e) => e is List ? e : [e]).toList();

        var all = <dynamic>[exp1, ...extra];

        while (all.length >= 3) {
          var e2 = all.removeLast();
          var op = all.removeLast();
          var e1 = all.removeLast();
          var exp = ASTExpressionOperation(e1, op, e2);
          all.add(exp);
        }
        assert(all.length == 1);

        return all[0] as ASTExpressionOperation;
      });

  Parser<ASTExpressionOperator> expressionOperator() => (char('+') |
              char('-') |
              char('*') |
              char('/') |
              string('~/') |
              string('==') |
              string('!=') |
              string('>=') |
              string('<=') |
              char('>') |
              char('<'))
          .trim()
          .map((v) {
        var op = getASTExpressionOperator(v);
        if (op == ASTExpressionOperator.divide) {
          return ASTExpressionOperator.divideAsDouble;
        }
        return op;
      });

  Parser<ASTExpression> expressionNoOperation() => (expressionLiteral() |
          expressionVariableAssigment() |
          expressionLocalFunctionInvocation() |
          expressionVariableEntryAccess() |
          expressionVariableAccess())
      .cast<ASTExpression>();

  Parser<ASTExpressionLocalFunctionInvocation>
      expressionLocalFunctionInvocation() => (string('this').optional() &
                  identifier() &
                  char('(') &
                  ref0(expression).star() &
                  char(')'))
              .map((v) {
            var name = v[1];
            var args = v[3] as List;
            return ASTExpressionLocalFunctionInvocation(
                name, args.cast<ASTExpression>().toList());
          });

  Parser<ASTExpressionVariableAccess> expressionVariableAccess() =>
      (variable()).map((v) {
        return ASTExpressionVariableAccess(v);
      });

  Parser<ASTExpressionLiteral> expressionLiteral() => (literal()).map((v) {
        return ASTExpressionLiteral(v);
      });

  Parser<ASTExpressionVariableEntryAccess> expressionVariableEntryAccess() =>
      (variable() & char('[') & ref0(expression) & char(']')).map((v) {
        var variable = v[0];
        var expression = v[2];
        return ASTExpressionVariableEntryAccess(variable, expression);
      });

  Parser<ASTExpressionVariableAssignment> expressionVariableAssigment() =>
      (variable() & assigmentOperator() & ref0(expression)).map((v) {
        return ASTExpressionVariableAssignment(v[0], v[1], v[2]);
      });

  Parser<ASTAssignmentOperator> assigmentOperator() =>
      (char('=') | string('+=')).trim().map((v) {
        return getASTAssignmentOperator(v);
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

  Parser<ASTValueNum> literalNum() => (numberLexicalToken().trim()).map((v) {
        return ASTValueNum.from(v);
      });

  Parser<ASTValue<String>> literalString() =>
      (stringLexicalToken()).map((v) => v.asValue());
}
