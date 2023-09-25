import 'package:petitparser/petitparser.dart';

import '../../apollovm_base.dart';
import '../../ast/apollovm_ast_base.dart';
import '../../ast/apollovm_ast_expression.dart';
import '../../ast/apollovm_ast_statement.dart';
import '../../ast/apollovm_ast_toplevel.dart';
import '../../ast/apollovm_ast_type.dart';
import '../../ast/apollovm_ast_value.dart';
import '../../ast/apollovm_ast_variable.dart';
import 'dart_grammar_lexer.dart';

/// Dart grammar definition.
class DartGrammarDefinition extends DartGrammarLexer {
  static ASTType getTypeByName(String name) {
    switch (name) {
      case 'Object':
        return ASTTypeObject.instance;
      case 'int':
        return ASTTypeInt.instance;
      case 'double':
        return ASTTypeDouble.instance;
      case 'num':
        return ASTTypeNum.instance;
      case 'String':
        return ASTTypeString.instance;
      case 'dynamic':
        return ASTTypeDynamic.instance;
      case 'List':
        return ASTTypeArray.instanceOfDynamic;
      case 'Map':
        return ASTTypeMap.instanceOfDynamicOfDynamic;
      case 'var':
        return ASTTypeVar();
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
            } else if (def is ASTClassNormal) {
              root.addClass(def);
            }
          }
        }

        root.resolveNode(null);

        return root;
      });

  Parser topLevelDefinition() =>
      (functionDeclaration() | classDeclaration()).plus();

  Parser<ASTFunctionDeclaration> functionDeclaration() =>
      (type() & identifier() & parametersDeclaration() & codeBlock()).map((v) {
        var returnType = v[0];
        var parameters = v[2];
        var name = v[1];
        var block = v[3];
        return ASTFunctionDeclaration(name, parameters, returnType,
            block: block, modifiers: ASTModifiers.modifierStatic);
      });

  Parser<ASTClassNormal> classDeclaration() =>
      (string('class').trimHidden() & identifier() & classCodeBlock()).map((v) {
        var name = v[1] as String;
        var block = v[2];
        var clazz = ASTClassNormal(name, ASTType<VMObject>(name), null);
        clazz.set(block);
        return clazz;
      });

  Parser<ASTBlock> classCodeBlock() => (char('{').trimHidden() &
              (ref0(classFunctionDeclaration) |
                      ref0(classFieldDeclaration) |
                      ref0(classFieldDeclarationWithValue))
                  .star() &
              char('}').trimHidden())
          .map((v) {
        var list = v[1] as List;
        var fields = list.whereType<ASTClassField>().toList();
        var functions = list.whereType<ASTFunctionDeclaration>().toList();

        var block = ASTClassNormal('?', ASTType<VMObject>('?'), null);

        block.addAllFields(fields);
        block.addAllFunctions(functions);

        return block;
      });

  Parser<ASTClassField> classFieldDeclaration() =>
      (type() & identifier() & char(';').trimHidden()).map((v) {
        var type = v[0] as ASTType;
        var name = v[1] as String;
        return ASTClassField(type, name, false);
      });

  Parser<ASTClassField> classFieldDeclarationWithValue() => (type() &
              identifier() &
              char('=').trimHidden() &
              ref0(expression) &
              char(';').trimHidden())
          .map((v) {
        var type = v[0] as ASTType;
        var name = v[1] as String;
        var expression = v[3] as ASTExpression;
        type.associateToType(expression);
        return ASTClassFieldWithInitialValue(type, name, expression, false);
      });

  Parser<ASTFunctionDeclaration> classFunctionDeclaration() =>
      (functionModifiers().optional() &
              type() &
              identifier() &
              parametersDeclaration() &
              codeBlock())
          .map((v) {
        var modifiers = v[0];
        var returnType = v[1] as ASTType;
        var name = v[2] as String;
        var parameters = v[3] as ASTParametersDeclaration;
        var block = v[4] as ASTBlock;
        return ASTClassFunctionDeclaration(null, name, parameters, returnType,
            block: block, modifiers: modifiers);
      });

  Parser<ASTModifiers> functionModifiers() =>
      string('static').trimHidden().flatten().map((v) {
        return ASTModifiers(isStatic: true);
      });

  Parser<ASTBlock> codeBlock() =>
      (char('{').trimHidden() & ref0(statement).star() & char('}').trimHidden())
          .map((v) {
        var statements = (v[1] as List).cast<ASTStatement>().toList();
        return ASTBlock(null)..addAllStatements(statements);
      });

  Parser<ASTStatement> statement() => (branch() |
          statementLoop() |
          statementReturn() |
          statementVariableDeclaration() |
          statementExpression())
      .cast<ASTStatement>();

  Parser<ASTStatement> statementSimple() =>
      (statementVariableDeclaration() | statementExpression())
          .cast<ASTStatement>();

  Parser<ASTStatementForLoop> statementLoop() => (string('for').trimHidden() &
              char('(').trimHidden() &
              ref0(statementSimple) &
              ref0(expression) &
              char(';').trimHidden() &
              ref0(expression) &
              char(')').trimHidden() &
              codeBlock())
          .map((v) {
        var initExp = v[2];
        var condExp = v[3];
        var contExp = v[5];
        var block = v[7];
        return ASTStatementForLoop(initExp, condExp, contExp, block);
      });

  Parser<ASTStatementReturn> statementReturn() =>
      (string('return').trimHidden() &
              expression().optional() &
              char(';').trimHidden())
          .map((v) {
        var value = v[1];

        if (value == null) {
          return ASTStatementReturn();
        } else if (value is ASTExpression) {
          if (value is ASTExpressionVariableAccess) {
            if (value.variable.name == 'null') {
              return ASTStatementReturnNull();
            } else {
              return ASTStatementReturnVariable(value.variable);
            }
          } else if (value is ASTExpressionLiteral) {
            return ASTStatementReturnValue(value.value);
          } else {
            return ASTStatementReturnWithExpression(value);
          }
        }

        throw UnsupportedError("Can't handle return value: $value");
      });

  Parser<ASTStatementExpression> statementExpression() =>
      (expression() & char(';').trimHidden()).map((v) {
        return ASTStatementExpression(v[0]);
      });

  Parser<ASTStatementVariableDeclaration> statementVariableDeclaration() =>
      (type() &
              identifier() &
              (char('=').trimHidden() & ref0(expression)).optional() &
              char(';').trimHidden())
          .map((v) {
        var type = v[0] as ASTType;
        var name = v[1] as String;
        var valueOpt = v[2];
        var value = valueOpt != null ? valueOpt[1] as ASTExpression : null;
        if (value != null) type.associateToType(value);
        return ASTStatementVariableDeclaration(type, name, value);
      });

  Parser<ASTBranch> branch() => (ref0(branchIfElseIfsElseBlock) |
          ref0(branchIfElseBlock) |
          ref0(branchIfBlock))
      .cast<ASTBranch>();

  Parser<ASTBranchIfBlock> branchIfBlock() => (string('if').trimHidden() &
              char('(').trimHidden() &
              ref0(expression) &
              char(')').trimHidden() &
              codeBlock())
          .map((v) {
        var condition = v[2];
        var block = v[4];
        return ASTBranchIfBlock(condition, block);
      });

  Parser<ASTBranchIfElseBlock> branchIfElseBlock() =>
      (string('if').trimHidden() &
              char('(').trimHidden() &
              ref0(expression) &
              char(')').trimHidden() &
              codeBlock() &
              string('else').trimHidden() &
              codeBlock())
          .map((v) {
        var condition = v[2];
        var blockIf = v[4];
        var blockElse = v[6];
        return ASTBranchIfElseBlock(condition, blockIf, blockElse);
      });

  Parser<ASTBranchIfElseIfsElseBlock> branchIfElseIfsElseBlock() =>
      (string('if').trimHidden() &
              char('(').trimHidden() &
              ref0(expression) &
              char(')').trimHidden() &
              codeBlock() &
              ref0(branchElseIfs).plus() &
              string('else').trimHidden() &
              codeBlock())
          .map((v) {
        var condition = v[2];
        var blockIf = v[4];
        var blockElseIfs = v[5] as List;
        var blockElse = v[7];

        return ASTBranchIfElseIfsElseBlock(condition, blockIf,
            blockElseIfs.cast<ASTBranchIfBlock>().toList(), blockElse);
      });

  Parser<ASTBranchIfBlock> branchElseIfs() => (string('else').trimHidden() &
              string('if').trimHidden() &
              char('(').trimHidden() &
              ref0(expression) &
              char(')').trimHidden() &
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

        var extra = _expandListDeeply(rest);

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
          .trimHidden()
          .map((v) {
        var op = getASTExpressionOperator(v);
        if (op == ASTExpressionOperator.divide) {
          return ASTExpressionOperator.divideAsDouble;
        }
        return op;
      });

  Parser<ASTExpression> expressionNoOperation() => (expressionNegate() |
          expressionLiteral() |
          expressionGroup() |
          expressionListEmptyLiteral() |
          expressionListLiteral() |
          expressionMapEmptyLiteral() |
          expressionMapLiteral() |
          expressionVariableAssigment() |
          expressionFunctionInvocation() |
          expressionVariableEntryAccess() |
          expressionVariableAccess())
      .cast<ASTExpression>();

  Parser<ASTExpressionNegation> expressionNegate() => (char('!').trimHidden() &
              (ref0(expressionNoOperation) | ref0(expressionGroup)))
          .map((v) {
        var exp = v[1] as ASTExpression;
        return ASTExpressionNegation(exp);
      });

  Parser<ASTExpression> expressionGroup() =>
      (char('(').trimHidden() & ref0(expression) & char(')').trimHidden())
          .map((v) => v[1] as ASTExpression);

  Parser<ASTExpressionFunctionInvocation> expressionFunctionInvocation() =>
      ((identifier() & char('.')).optional() &
              identifier() &
              char('(').trimHidden() &
              ref0(expressionSequence).optional() &
              char(')').trimHidden())
          .map((v) {
        var objOpt = v[0] as List?;
        var obj = objOpt != null ? objOpt[0] as String : null;
        var name = v[1] as String;
        var args = v[3] as List<ASTExpression>?;
        args ??= <ASTExpression>[];

        if (obj != null && obj != 'this') {
          var variable = ASTScopeVariable(obj);
          return ASTExpressionObjectFunctionInvocation(variable, name, args);
        } else {
          return ASTExpressionLocalFunctionInvocation(name, args);
        }
      });

  Parser<List<ASTExpression>> expressionSequence() =>
      (ref0(expression) & (char(',').trimHidden() & ref0(expression)).star())
          .map((v) {
        var list = _expandListDeeply(v);
        var expressions = list.whereType<ASTExpression>().toList();
        return expressions;
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

  Parser<ASTExpressionListLiteral> expressionListEmptyLiteral() =>
      ((char('<').trimHidden() & simpleType() & char('>').trimHidden())
                  .optional() &
              char('[').trimHidden() &
              char(']').trimHidden())
          .map((v) {
        var type = (v[0]?[1] as ASTType?) ?? ASTTypeDynamic.instance;
        return ASTExpressionListLiteral(type, []);
      });

  Parser<ASTExpressionListLiteral> expressionListLiteral() =>
      ((char('<').trimHidden() & simpleType() & char('>').trimHidden())
                  .optional() &
              char('[').trimHidden() &
              ref0(expression) &
              (char(',').trimHidden() & ref0(expression)).star() &
              char(',').trimHidden().optional() &
              char(']').trimHidden())
          .map((v) {
        var type = (v[0]?[1] as ASTType?) ?? ASTTypeDynamic.instance;
        var v0 = v[2];
        var tail = (v[3] as List?) ?? [];

        var vs = tail.expand((e) => e).whereType<ASTExpression>().toList();

        return ASTExpressionListLiteral(type, [v0, ...vs]);
      });

  Parser<ASTExpressionMapLiteral> expressionMapEmptyLiteral() =>
      ((char('<').trimHidden() &
                      simpleType() &
                      char(',').trimHidden() &
                      simpleType() &
                      char('>').trimHidden())
                  .optional() &
              char('{').trimHidden() &
              char('}').trimHidden())
          .map((v) {
        var keyType = (v[0]?[1] as ASTType?) ?? ASTTypeDynamic.instance;
        var valueType = (v[0]?[2] as ASTType?) ?? ASTTypeDynamic.instance;
        return ASTExpressionMapLiteral(keyType, valueType, []);
      });

  Parser<ASTExpressionMapLiteral> expressionMapLiteral() =>
      ((char('<').trimHidden() &
                      simpleType() &
                      char(',').trimHidden() &
                      simpleType() &
                      char('>').trimHidden())
                  .optional() &
              char('{').trimHidden() &
              (expression() & char(':').trimHidden() & expression()) &
              (char(',').trimHidden() &
                      expression() &
                      char(':').trimHidden() &
                      expression())
                  .star() &
              char(',').trimHidden().optional() &
              char('}').trimHidden())
          .map((v) {
        var keyType = (v[0]?[1] as ASTType?) ?? ASTTypeDynamic.instance;
        var valueType = (v[0]?[3] as ASTType?) ?? ASTTypeDynamic.instance;
        var entry0 = (v[2] as List).whereType<ASTExpression>().toList();
        var entriesTail = (v[3] as List?)
            ?.whereType<List>()
            .map((l) => l.whereType<ASTExpression>().toList())
            .toList();

        var entries = [
          MapEntry(entry0[0], entry0[1]),
          ...?entriesTail?.map((e) => MapEntry(e[0], e[1]))
        ];

        return ASTExpressionMapLiteral(keyType, valueType, entries);
      });

  Parser<ASTExpressionVariableAssignment> expressionVariableAssigment() =>
      (variable() & assigmentOperator() & ref0(expression)).map((v) {
        return ASTExpressionVariableAssignment(v[0], v[1], v[2]);
      });

  Parser<ASTAssignmentOperator> assigmentOperator() =>
      (char('=') | string('+=')).trimHidden().map((v) {
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
        var params = _expandListDeeply(v);
        return params.whereType<ASTFunctionParameterDeclaration>().toList();
      });

  Parser<ASTFunctionParameterDeclaration> parameterDeclaration() =>
      (type() & identifier()).map((v) {
        return ASTFunctionParameterDeclaration(v[0], v[1], -1, false);
      });

  Parser<ASTType> type() => (arrayTyped() |
          arrayTypeDynamic() |
          mapTyped() |
          mapTypeDynamic() |
          simpleType())
      .cast<ASTType>();

  Parser<ASTType> simpleType() => identifier().map((v) {
        return getTypeByName(v);
      });

  Parser<ASTTypeArray> arrayTyped() =>
      (array3DTyped() | array2DTyped() | array1DTyped()).cast<ASTTypeArray>();

  Parser<ASTTypeArray> array1DTyped() =>
      (string('List') & char('<') & simpleType() & char('>')).map((v) {
        var t = v[2] as ASTType;
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
        var t = v[4] as ASTType;
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
        var t = v[4] as ASTType;
        return ASTTypeArray3D.fromElementType(t);
      });

  Parser<ASTTypeArray> arrayTypeDynamic() =>
      (array3DTypeDynamic() | array2DTypeDynamic() | array1DTypeDynamic())
          .cast<ASTTypeArray>();

  Parser<ASTTypeArray> array1DTypeDynamic() => string('List').map((v) {
        return ASTTypeArray.instanceOfDynamic;
      });

  Parser<ASTTypeArray2D> array2DTypeDynamic() =>
      (string('List') & char('<').trim() & string('List') & char('>').trim())
          .map((v) {
        return ASTTypeArray2D.fromElementType(ASTTypeDynamic.instance);
      });

  Parser<ASTTypeArray3D> array3DTypeDynamic() => (string('List') &
              char('<') &
              string('List') &
              char('<') &
              string('List') &
              char('>') &
              char('>'))
          .map((v) {
        return ASTTypeArray3D.fromElementType(ASTTypeDynamic.instance);
      });

  Parser<ASTTypeMap> mapTyped() => (string('Map') &
              char('<').trim() &
              simpleType() &
              char(',').trim() &
              char('>').trim())
          .map((v) {
        var key = v[2] as ASTType;
        var val = v[3] as ASTType;
        return ASTTypeMap(key, val);
      });

  Parser<ASTTypeMap> mapTypeDynamic() => string('Map').map((v) {
        return ASTTypeMap.instanceOfDynamicOfDynamic;
      });

  Parser<ASTValue> literal() => (literalBool() | literalNum() | literalString())
      .trimHidden()
      .cast<ASTValue>();

  Parser<ASTValueBool> literalBool() =>
      ((string('true') | string('false')).trim()).map((v) {
        return ASTValueBool(v == 'true');
      });

  Parser<ASTValueNum> literalNum() => (numberLexicalToken().trim()).map((v) {
        return ASTValueNum.from(v);
      });

  Parser<ASTValue<String>> literalString() =>
      (stringLexicalToken()).map((v) => v.asValue());

  static List _expandListDeeply(List l) {
    if (l.isEmpty) return l;
    if (l.length == 1 && l[0] is! List) return l;

    return l.expand((e) => e is List ? _expandListDeeply(e) : [e]).toList();
  }
}
