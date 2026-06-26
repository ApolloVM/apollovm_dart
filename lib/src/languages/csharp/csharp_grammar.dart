// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:petitparser/petitparser.dart';

import '../../apollovm_base.dart';
import '../../apollovm_parser.dart';
import '../../ast/apollovm_ast_base.dart';
import '../../ast/apollovm_ast_expression.dart';
import '../../ast/apollovm_ast_statement.dart';
import '../../ast/apollovm_ast_toplevel.dart';
import '../../ast/apollovm_ast_type.dart';
import '../../ast/apollovm_ast_value.dart';
import '../../ast/apollovm_ast_variable.dart';
import 'csharp_grammar_lexer.dart';

/// C# grammar definition.
class CSharpGrammarDefinition extends CSharpGrammarLexer {
  static ASTType getTypeByName(String name) {
    switch (name) {
      case 'object':
      case 'Object':
        return ASTTypeObject.instance;
      case 'int':
      case 'Int32':
      case 'long':
      case 'Int64':
      case 'short':
      case 'byte':
      case 'uint':
      case 'ulong':
        return ASTTypeInt.instance;
      case 'double':
      case 'Double':
      case 'float':
      case 'decimal':
        return ASTTypeDouble.instance;
      case 'bool':
      case 'Boolean':
        return ASTTypeBool.instance;
      case 'string':
      case 'String':
        return ASTTypeString.instance;
      case 'List':
        return ASTTypeArray(ASTTypeDynamic.instance);
      case 'Func':
      case 'Action':
      case 'Delegate':
      case 'Function':
        return ASTTypeFunction();
      case 'var':
        return ASTTypeVar();
      case 'dynamic':
        return ASTTypeVar();
      default:
        return ASTType(name);
    }
  }

  @override
  Parser start() => ref0(compilationUnit).trim().end();

  Parser<ASTRoot> compilationUnit() =>
      (ref0(usingDirective).star() & ref0(topLevelDefinition).star()).map((v) {
        var topDef = v[1];

        var classes = topDef as List;

        var root = ASTRoot();

        root.addAllClasses(classes.cast());

        root.resolveNode(null);

        return root;
      });

  /// C# `using System;` / `using System.Collections.Generic;`.
  Parser usingDirective() =>
      (string('using').trimHidden() &
      identifier() &
      (char('.').trimHidden() & identifier()).star() &
      char(';').trimHidden());

  Parser topLevelDefinition() => (classDeclaration());

  Parser<ASTClassNormal> classDeclaration() =>
      (classVisibilityModifier().star() &
              string('class').trimHidden() &
              identifier() &
              classBaseList().optional() &
              classCodeBlock())
          .map((v) {
            var name = v[2] as String;
            var block = v[4];
            var clazz = ASTClassNormal(name, ASTType<VMObject>(name), null);
            clazz.set(block);
            return clazz;
          });

  /// `class Foo : Base, IInterface` (parsed and ignored, like Java's
  /// `extends`/`implements`).
  Parser classBaseList() =>
      (char(':').trimHidden() &
      type() &
      (char(',').trimHidden() & type()).star());

  Parser<String> classVisibilityModifier() =>
      (string('public') |
              string('internal') |
              string('abstract') |
              string('sealed') |
              string('static') |
              string('partial'))
          .trimHidden()
          .flatten();

  Parser<ASTBlock> classCodeBlock() =>
      (char('{').trimHidden() &
              (ref0(classConstructorDefaultDeclaration) |
                      ref0(classFunctionDeclaration) |
                      ref0(classFieldDeclaration) |
                      ref0(classFieldDeclarationWithValue))
                  .star() &
              char('}').trimHidden())
          .map((v) {
            var list = v[1] as List;
            var fields = list.whereType<ASTClassField>().toList();
            var constructors = list
                .whereType<ASTClassConstructorDeclaration>()
                .toList();
            var functions = list.whereType<ASTFunctionDeclaration>().toList();

            var block = ASTClassNormal('?', ASTType<VMObject>('?'), null);

            block.addAllFields(fields);
            block.addAllConstructors(constructors);
            block.addAllFunctions(functions);

            return block;
          });

  Parser<ASTClassField> classFieldDeclaration() =>
      (modifiers().optional() & type() & identifier() & char(';').trimHidden())
          .map((v) {
            var modifiers =
                (v[0] as ASTModifiers?) ?? ASTModifiers.modifiersNone;
            var type = v[1];
            var name = v[2];
            return ASTClassField(type, name, modifiers.isFinal);
          });

  Parser<ASTClassField> classFieldDeclarationWithValue() =>
      (modifiers().optional() &
              type() &
              identifier() &
              char('=').trimHidden() &
              ref0(expression) &
              char(';').trimHidden())
          .map((v) {
            var modifiers =
                (v[0] as ASTModifiers?) ?? ASTModifiers.modifiersNone;
            var type = v[1];
            var name = v[2];
            var expression = v[4];
            return ASTClassFieldWithInitialValue(
              type,
              name,
              expression,
              modifiers.isFinal,
            );
          });

  Parser<ASTClassConstructorDeclaration> classConstructorDefaultDeclaration() =>
      (classVisibilityModifier().star() &
              identifier() &
              constructorParametersDeclaration() &
              codeBlock())
          .map((v) {
            var className = v[1];
            var parameters = v[2] as ASTConstructorParametersDeclaration;
            var block = v[3];
            return ASTClassConstructorDeclaration(
              ASTType(className),
              '',
              parameters,
              block: block,
            );
          });

  Parser<ASTConstructorParametersDeclaration>
  constructorParametersDeclaration() =>
      (constructorEmptyParametersDeclaration() |
              constructorPositionalParametersDeclaration())
          .cast<ASTConstructorParametersDeclaration>();

  Parser<ASTConstructorParametersDeclaration>
  constructorEmptyParametersDeclaration() => (char('(') & char(')')).map((v) {
    return ASTConstructorParametersDeclaration(null, null, null);
  });

  Parser<ASTConstructorParametersDeclaration>
  constructorPositionalParametersDeclaration() =>
      (char('(') & constructorParametersList() & char(')')).map((v) {
        return ASTConstructorParametersDeclaration(v[1], null, null);
      });

  Parser<List<ASTConstructorParameterDeclaration>>
  constructorParametersList() =>
      (constructorParameterDeclaration() &
              (char(',') & constructorParameterDeclaration()).star() &
              char(',').optional())
          .map((v) {
            var params = _expandListDeeply(v);
            return params
                .whereType<ASTConstructorParameterDeclaration>()
                .toList();
          });

  Parser<ASTConstructorParameterDeclaration>
  constructorParameterDeclaration() =>
      (constructorTypedParameterDeclaration()).map((v) => v);

  Parser<ASTConstructorParameterDeclaration>
  constructorTypedParameterDeclaration() =>
      (readonlyToken().trim().optional() & type().trim() & identifier()).map((
        v,
      ) {
        return ASTConstructorParameterDeclaration(v[1], v[2], -1, false);
      });

  Parser<ASTFunctionDeclaration> classFunctionDeclaration() =>
      (modifiers().optional() &
              type() &
              identifier() &
              functionParametersDeclaration() &
              codeBlock())
          .map((List v) {
            var modifiers = v[0];
            var returnType = v[1];
            var name = v[2];
            var parameters = v[3];
            var block = v[4];
            return ASTClassFunctionDeclaration(
              null,
              name,
              parameters,
              returnType,
              block: block,
              modifiers: modifiers,
            );
          });

  Parser<ASTModifiers> modifiers() => (modifier().plus()).map((v) {
    v = v.map((e) => e.toString().trim()).toList();
    if (v.length > 1) {
      if (v.toSet().length != v.length) {
        throw SyntaxError('Duplicated function modifiers: $v');
      }
    }
    var isStatic = v.contains('static');
    var isFinal =
        v.contains('readonly') || v.contains('const') || v.contains('sealed');
    var isPrivate = v.contains('private');
    var isPublic = v.contains('public');
    return ASTModifiers(
      isStatic: isStatic,
      isFinal: isFinal,
      isPrivate: isPrivate,
      isPublic: isPublic,
    );
  });

  Parser<String> modifier() =>
      (string('public') |
              string('private') |
              string('protected') |
              string('internal') |
              string('readonly') |
              string('const') |
              string('virtual') |
              string('override') |
              string('abstract') |
              string('sealed') |
              string('static'))
          .trimHidden()
          .flatten();

  Parser<ASTBlock> codeBlock() =>
      (char('{').trimHidden() & ref0(statement).star() & char('}').trimHidden())
          .map((v) {
            var statements = (v[1] as List).cast<ASTStatement>().toList();
            return ASTBlock(null)..addAllStatements(statements);
          });

  Parser<ASTBlock> codeBlockOrSingleLineBlock() =>
      ((codeBlock() | singleLineCodeBlock())).cast<ASTBlock>();

  Parser<ASTSingleLineStatementBlock> singleLineCodeBlock() =>
      (singleLineStatement().trimHidden()).map((v) {
        var statements = v;
        return ASTSingleLineStatementBlock(null)..addStatement(statements);
      });

  Parser<ASTStatement> singleLineStatement() =>
      (statementReturn() | statementExpression()).cast<ASTStatement>();

  Parser<ASTStatement> statement() =>
      (statementTryCatch() |
              statementThrow() |
              statementSwitch() |
              branch() |
              statementBreak() |
              statementContinue() |
              statementReturn() |
              statementDoWhileLoop() |
              statementForLoop() |
              statementForEach() |
              statementWhileLoop() |
              statementVariableDeclaration() |
              statementExpression())
          .cast<ASTStatement>();

  Parser<ASTStatementBreak> statementBreak() =>
      (string('break') &
              ref0(identifierPartLexicalToken).not() &
              char(';').trimHidden())
          .map((v) => ASTStatementBreak());

  Parser<ASTStatementContinue> statementContinue() =>
      (string('continue') &
              ref0(identifierPartLexicalToken).not() &
              char(';').trimHidden())
          .map((v) => ASTStatementContinue());

  Parser<ASTStatementDoWhileLoop> statementDoWhileLoop() =>
      (string('do').trimHidden() &
              codeBlock() &
              string('while').trimHidden() &
              char('(').trimHidden() &
              ref0(expression) &
              char(')').trimHidden() &
              char(';').trimHidden())
          .map((v) {
            var block = v[1] as ASTBlock;
            var cond = v[4] as ASTExpression;
            return ASTStatementDoWhileLoop(block, cond);
          });

  Parser<ASTStatementSwitch> statementSwitch() =>
      (string('switch').trimHidden() &
              char('(').trimHidden() &
              ref0(expression) &
              char(')').trimHidden() &
              char('{').trimHidden() &
              switchCase().star() &
              char('}').trimHidden())
          .map((v) {
            var exp = v[2] as ASTExpression;
            var cases = (v[5] as List).cast<ASTSwitchCase>();
            return ASTStatementSwitch(exp, cases);
          });

  Parser<ASTSwitchCase> switchCase() =>
      (switchCaseLabel() & switchCaseBody()).map((v) {
        var value = v[0] as ASTExpression?;
        var block = v[1] as ASTBlock;
        return ASTSwitchCase(value, block);
      });

  Parser<ASTExpression?> switchCaseLabel() =>
      ((string('case').trimHidden() & ref0(expression) & char(':').trimHidden())
                  .map((v) => v[1] as ASTExpression?) |
              (string('default').trimHidden() & char(':').trimHidden()).map(
                (v) => null,
              ))
          .cast<ASTExpression?>();

  /// A `case`/`default` body: a braced block (`{ ... }`) or a bare run of
  /// statements up to the next `case`/`default`/`}`.
  Parser<ASTBlock> switchCaseBody() =>
      (codeBlock() | switchCaseStatements()).cast<ASTBlock>();

  Parser<ASTBlock> switchCaseStatements() => ref0(statement).star().map((v) {
    var statements = v.cast<ASTStatement>();
    return ASTBlock(null)..addAllStatements(statements);
  });

  Parser<ASTStatementThrow> statementThrow() =>
      (string('throw').trimHidden() & ref0(expression) & char(';').trimHidden())
          .map((v) => ASTStatementThrow(v[1] as ASTExpression));

  Parser<ASTStatementTryCatch> statementTryCatch() =>
      (string('try').trimHidden() &
              codeBlock() &
              catchClause().star() &
              (string('finally').trimHidden() & codeBlock()).optional())
          .map((v) {
            var tryBlock = v[1] as ASTBlock;
            var catches = (v[2] as List).cast<ASTCatchClause>();
            var finallyOpt = v[3] as List?;
            var finallyBlock = finallyOpt != null
                ? finallyOpt[1] as ASTBlock
                : null;
            return ASTStatementTryCatch(tryBlock, catches, finallyBlock);
          });

  /// C# `catch (Type e) { }` (the variable name is optional in C#).
  Parser<ASTCatchClause> catchClause() =>
      (string('catch').trimHidden() &
              char('(').trimHidden() &
              type() &
              identifier().trimHidden().optional() &
              char(')').trimHidden() &
              codeBlock())
          .map((v) {
            var type = v[2] as ASTType;
            var varName = (v[3] as String?) ?? 'e';
            var block = v[5] as ASTBlock;
            return ASTCatchClause(type, varName, block);
          });

  Parser<ASTStatement> statementSimple() =>
      (statementVariableDeclaration() | statementExpression())
          .cast<ASTStatement>();

  Parser<ASTStatementForLoop> statementForLoop() =>
      (string('for').trimHidden() &
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

  /// C# `foreach (T x in coll) { }`.
  Parser<ASTStatementForEach> statementForEach() =>
      (string('foreach').trimHidden() &
              char('(').trimHidden() &
              type().trimHidden() &
              ref0(identifier) &
              inToken().trimHidden() &
              ref0(expression) &
              char(')').trimHidden() &
              codeBlock())
          .map((v) {
            var variableType = v[2];
            var variableName = v[3];
            var iterableExp = v[5];
            var block = v[7];

            return ASTStatementForEach(
              variableType,
              variableName,
              iterableExp,
              block,
            );
          });

  Parser<ASTStatementWhileLoop> statementWhileLoop() =>
      (string('while').trimHidden() &
              char('(').trimHidden() &
              ref0(expression) &
              char(')').trimHidden() &
              codeBlock())
          .map((v) {
            var condExp = v[2];
            var block = v[4];
            return ASTStatementWhileLoop(condExp, block);
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
            var valueOpt = v[2];
            var value = valueOpt != null ? valueOpt[1] : null;
            return ASTStatementVariableDeclaration(v[0], v[1], value);
          });

  Parser<ASTBranch> branch() =>
      (ref0(branchIfElseIfsElseBlock) |
              ref0(branchIfElseBlock) |
              ref0(branchIfBlock))
          .cast<ASTBranch>();

  Parser<ASTBranchIfBlock> branchIfBlock() =>
      (string('if').trimHidden() &
              char('(').trimHidden() &
              ref0(expression) &
              char(')').trimHidden() &
              codeBlockOrSingleLineBlock())
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

            return ASTBranchIfElseIfsElseBlock(
              condition,
              blockIf,
              blockElseIfs.cast<ASTBranchIfBlock>().toList(),
              blockElse,
            );
          });

  Parser<ASTBranchIfBlock> branchElseIfs() =>
      (string('else').trimHidden() &
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

  Parser<ASTExpression> expression() =>
      (ref0(expressionOperationChain) &
              (char('?').trimHidden() &
                      ref0(expression) &
                      char(':').trimHidden() &
                      ref0(expression))
                  .optional())
          .map((v) {
            var base = v[0] as ASTExpression;
            var ternary = v[1] as List?;
            if (ternary == null) return base;
            return ASTExpressionConditional(
              base,
              ternary[1] as ASTExpression,
              ternary[3] as ASTExpression,
            );
          });

  Parser<ASTExpression> expressionOperationChain() =>
      (ref0(expressionNoOperation) &
              (expressionOperator() & ref0(expressionNoOperation)).star())
          .map((v) {
            var exp1 = v[0];

            var rest = v[1] as List;
            if (rest.isEmpty) {
              return exp1;
            }

            var extra = _expandListDeeply(rest);
            var all = <dynamic>[exp1, ...extra];

            return computeFinalExpression(all);
          });

  Parser<ASTExpressionOperator> expressionOperator() =>
      (char('+') |
              char('-') |
              char('*') |
              char('/') |
              char('%') |
              string('==') |
              string('!=') |
              string('<=') |
              string('>=') |
              string('&&') |
              string('||') |
              char('<') |
              char('>'))
          .trimHidden()
          .map((v) {
            return getASTExpressionOperator(v);
          });

  Parser<ASTExpression> expressionNoOperation() =>
      (expressionLambda() |
              expressionNegate() |
              expressionLiteral() |
              expressionGroupFunctionInvocation() |
              expressionGroup() |
              expressionListLiteral() |
              expressionListEmptyLiteral() |
              expressionMapLiteral() |
              expressionMapEmptyLiteral() |
              expressionVariableDirectOperation() |
              expressionObjectFieldAssignment() |
              expressionVariableAssigment() |
              expressionFunctionInvocation() |
              expressionObjectEntryFunctionInvocation() |
              expressionVariableEntryAccess() |
              expressionGetterAccess() |
              expressionNullValue() |
              expressionVariableAccess() |
              expressionNegative())
          .cast<ASTExpression>();

  Parser<ASTExpressionNegation> expressionNegate() =>
      (char('!').trimHidden() &
              (ref0(expressionNoOperation) | ref0(expressionGroup)))
          .map((v) {
            var exp = v[1] as ASTExpression;
            return ASTExpressionNegation(exp);
          });

  Parser<ASTExpressionNegative> expressionNegative() =>
      (char('-').trimHidden() &
              (ref0(expressionNoOperation) | ref0(expressionGroup)))
          .map((v) {
            var exp = v[1] as ASTExpression;
            return ASTExpressionNegative(exp);
          });

  Parser<ASTExpression> expressionGroup() =>
      (char('(').trimHidden() & ref0(expression) & char(')').trimHidden()).map(
        (v) => v[1] as ASTExpression,
      );

  Parser<ASTExpressionGroupFunctionInvocation>
  expressionGroupFunctionInvocation() =>
      (ref0(expressionGroup) &
              char('.') &
              identifier() &
              char('(').trimHidden() &
              ref0(expressionSequence).optional() &
              char(')').trimHidden() &
              expressionChainFunctionInvocation().star())
          .map((v) {
            var expression = v[0] as ASTExpression;
            var name = v[2] as String;
            var args = v[4] as List<ASTExpression>?;
            args ??= <ASTExpression>[];
            var chainFunctions = (v[6] as List)
                .whereType<ASTExpressionChainFunctionInvocation>()
                .toList();

            return ASTExpressionGroupFunctionInvocation(
              expression,
              name,
              args,
              chainFunctions,
            );
          });

  Parser<ASTExpressionFunctionInvocation> expressionFunctionInvocation() =>
      // Optional `new` prefix for class instantiation (`new User()`); the
      // collection literals (`new List<…>()`) match earlier in the
      // alternation, so this generic rule handles user classes.
      (newToken().optional() &
              (identifier() & char('.')).optional() &
              identifier() &
              char('(').trimHidden() &
              ref0(expressionSequence).optional() &
              char(')').trimHidden() &
              expressionChainFunctionInvocation().star())
          .map((v) {
            var objOpt = v[1] as List?;
            var obj = objOpt != null ? objOpt[0] as String : null;
            var name = v[2] as String;
            var args = v[4] as List<ASTExpression>?;
            args ??= <ASTExpression>[];
            var chainFunctions = (v[6] as List)
                .whereType<ASTExpressionChainFunctionInvocation>()
                .toList();

            if (obj != null && obj != 'this') {
              var variable = ASTScopeVariable(obj);
              return ASTExpressionObjectFunctionInvocation(
                variable,
                name,
                args,
                chainFunctions,
              );
            } else {
              return ASTExpressionLocalFunctionInvocation(
                name,
                args,
                chainFunctions,
              );
            }
          });

  /// `obj.field` (and `this.field`) read access.
  Parser<ASTExpressionGetterAccess> expressionGetterAccess() =>
      ((identifier() & char('.')) &
              identifier().trimHidden() &
              expressionChainFunctionInvocation().star())
          .map((v) {
            var obj = v[0] as String?;
            var name = v[2] as String;
            var chainFunctions = (v[3] as List)
                .whereType<ASTExpressionChainFunctionInvocation>()
                .toList();

            ASTVariable variable = obj == 'this'
                ? ASTThisVariable()
                : ASTScopeVariable(obj!);
            return ASTExpressionObjectGetterAccess(
              variable,
              name,
              chainFunctions,
            );
          });

  Parser<ASTExpressionChainFunctionInvocation>
  expressionChainFunctionInvocation() =>
      (char('.').trimHidden() &
              identifier() &
              char('(').trimHidden() &
              ref0(expressionSequence).optional() &
              char(')').trimHidden())
          .map((v) {
            var fName = v[1];
            var args = v[3];
            args ??= <ASTExpression>[];
            return ASTExpressionChainFunctionInvocation(fName, args);
          });

  Parser<List<ASTExpression>> expressionSequence() =>
      (ref0(expression) & (char(',').trimHidden() & ref0(expression)).star())
          .map((v) {
            var list = _expandListDeeply(v);
            var expressions = list.whereType<ASTExpression>().toList();
            return expressions;
          });

  Parser<ASTExpressionNullValue> expressionNullValue() =>
      (nullToken()).map((v) {
        return ASTExpressionNullValue();
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

  Parser<ASTExpressionObjectEntryFunctionInvocation>
  expressionObjectEntryFunctionInvocation() =>
      (variable() &
              char('[') &
              ref0(expression) &
              char(']') &
              char('.').trimHidden() &
              identifier() &
              char('(').trimHidden() &
              ref0(expressionSequence).optional() &
              char(')').trimHidden() &
              expressionChainFunctionInvocation().star())
          .map((v) {
            var variable = v[0];
            var expression = v[2];
            var fName = v[5];
            var args = v[7];
            args ??= <ASTExpression>[];
            var chainFunctions = (v[9] as List)
                .whereType<ASTExpressionChainFunctionInvocation>()
                .toList();

            return ASTExpressionObjectEntryFunctionInvocation(
              variable,
              expression,
              fName,
              args,
              chainFunctions,
            );
          });

  /// C# collection initializer: `new List<T>()` (empty).
  Parser<ASTExpressionListLiteral> expressionListEmptyLiteral() =>
      (newToken().trimHidden() &
              string('List').trimHidden() &
              ((char('<').trimHidden() &
                      simpleType() &
                      char('>').trimHidden()) |
                  (char('<').trimHidden() & char('>').trimHidden())) &
              char('(').trimHidden() &
              char(')').trimHidden() &
              (char('{').trimHidden() & char('}').trimHidden()).optional())
          .map((v) {
            var type = (v[2]?[1] as ASTType?) ?? ASTTypeDynamic.instance;
            return ASTExpressionListLiteral(type, []);
          });

  /// C# collection initializer: `new List<T>(){ e0, e1, ... }`.
  Parser<ASTExpressionListLiteral> expressionListLiteral() =>
      (newToken().trimHidden() &
              string('List').trimHidden() &
              ((char('<').trimHidden() &
                      simpleType() &
                      char('>').trimHidden()) |
                  (char('<').trimHidden() & char('>').trimHidden())) &
              char('(').trimHidden() &
              char(')').trimHidden() &
              char('{').trimHidden() &
              expression() &
              (char(',').trimHidden() & expression()).star() &
              char(',').trimHidden().optional() &
              char('}').trimHidden())
          .map((v) {
            var type = (v[2]?[1] as ASTType?) ?? ASTTypeDynamic.instance;
            var v0 = v[6] as ASTExpression;
            var tail =
                (v[7] as List?)
                    ?.whereType<List>()
                    .map((e) => e.whereType<ASTExpression>().first)
                    .toList() ??
                [];

            return ASTExpressionListLiteral(type, [v0, ...tail]);
          });

  /// C# collection initializer: `new Dictionary<K,V>()` (empty).
  Parser<ASTExpressionMapLiteral> expressionMapEmptyLiteral() =>
      (newToken().trimHidden() &
              string('Dictionary').trimHidden() &
              ((char('<').trimHidden() &
                      simpleType() &
                      char(',').trimHidden() &
                      simpleType() &
                      char('>').trimHidden()) |
                  (char('<').trimHidden() & char('>').trimHidden())) &
              char('(').trimHidden() &
              char(')').trimHidden() &
              (char('{').trimHidden() & char('}').trimHidden()).optional())
          .map((v) {
            var keyType = (v[2]?[1] as ASTType?) ?? ASTTypeDynamic.instance;
            var valueType = (v[2]?[3] as ASTType?) ?? ASTTypeDynamic.instance;
            return ASTExpressionMapLiteral(keyType, valueType, []);
          });

  /// C# collection initializer:
  /// `new Dictionary<K,V>(){ {k0,v0}, {k1,v1}, ... }`.
  Parser<ASTExpressionMapLiteral> expressionMapLiteral() =>
      (newToken().trimHidden() &
              string('Dictionary').trimHidden() &
              ((char('<').trimHidden() &
                      simpleType() &
                      char(',').trimHidden() &
                      simpleType() &
                      char('>').trimHidden()) |
                  (char('<').trimHidden() & char('>').trimHidden())) &
              char('(').trimHidden() &
              char(')').trimHidden() &
              char('{').trimHidden() &
              mapEntryLiteral() &
              (char(',').trimHidden() & mapEntryLiteral()).star() &
              char(',').trimHidden().optional() &
              char('}').trimHidden())
          .map((v) {
            var keyType = (v[2]?[1] as ASTType?) ?? ASTTypeDynamic.instance;
            var valueType = (v[2]?[3] as ASTType?) ?? ASTTypeDynamic.instance;
            var entry0 = v[6] as List;
            var entriesTail = (v[7] as List?)
                ?.whereType<List>()
                .map((l) => l.whereType<List>().first)
                .toList();

            var entries = [
              MapEntry<ASTExpression, ASTExpression>(
                entry0[0] as ASTExpression,
                entry0[1] as ASTExpression,
              ),
              ...?entriesTail?.map(
                (e) => MapEntry<ASTExpression, ASTExpression>(
                  e[0] as ASTExpression,
                  e[1] as ASTExpression,
                ),
              ),
            ];

            return ASTExpressionMapLiteral(keyType, valueType, entries);
          });

  /// A single `{ key, value }` pair inside a C# dictionary initializer.
  Parser<List<ASTExpression>> mapEntryLiteral() =>
      (char('{').trimHidden() &
              expression() &
              char(',').trimHidden() &
              expression() &
              char('}').trimHidden())
          .map((v) {
            return [v[1] as ASTExpression, v[3] as ASTExpression];
          });

  Parser<ASTExpressionVariableDirectOperation>
  expressionVariableDirectOperation() =>
      (expressionVariableDirectPosOperation() |
              expressionVariableDirectPreOperation())
          .cast<ASTExpressionVariableDirectOperation>();

  Parser<ASTExpressionVariableDirectOperation>
  expressionVariableDirectPosOperation() =>
      (variable() & (string('++') | string('--'))).map((v) {
        var variable = v[0];
        var operator = getASTAssignmentDirectOperator(v[1]);
        return ASTExpressionVariableDirectOperation(variable, operator, false);
      });

  Parser<ASTExpressionVariableDirectOperation>
  expressionVariableDirectPreOperation() =>
      ((string('++') | string('--')) & variable()).map((v) {
        var operator = getASTAssignmentDirectOperator(v[0]);
        var variable = v[1];
        return ASTExpressionVariableDirectOperation(variable, operator, true);
      });

  Parser<ASTExpressionVariableAssignment> expressionVariableAssigment() =>
      (variable() & assigmentOperator() & ref0(expression)).map((v) {
        return ASTExpressionVariableAssignment(v[0], v[1], v[2]);
      });

  /// `obj.field = value` (and `this.field = value`), including `+=` etc.
  Parser<ASTExpressionObjectSetterAssignment>
  expressionObjectFieldAssignment() =>
      (identifier() &
              char('.') &
              identifier().trimHidden() &
              assigmentOperator() &
              ref0(expression))
          .map((v) {
            var obj = v[0] as String;
            var name = v[2] as String;
            var op = v[3] as ASTAssignmentOperator;
            var valueExpr = v[4] as ASTExpression;
            ASTVariable variable = obj == 'this'
                ? ASTThisVariable()
                : ASTScopeVariable(obj);
            return ASTExpressionObjectSetterAssignment(
              variable,
              name,
              op,
              valueExpr,
            );
          });

  Parser<ASTAssignmentOperator> assigmentOperator() =>
      (char('=') | string('+=') | string('-=') | string('*=') | string('/='))
          .trimHidden()
          .map((v) {
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

  /// C# lambda used as an expression (a closure): `(a, b) => expr`,
  /// `(int a) => { ... }`, `x => x * 2`, `() => 0`. Captures the enclosing scope.
  Parser<ASTExpression> expressionLambda() =>
      (lambdaParameters() & string('=>').trimHidden() & lambdaBody()).map((v) {
        var parameters = v[0] as ASTFunctionParametersDeclaration;
        var block = v[2] as ASTBlock;
        var f = ASTFunctionDeclaration(
          '',
          parameters,
          ASTTypeDynamic.instance,
          block: block,
          modifiers: ASTModifiers.modifierStatic,
        );
        return ASTExpressionLiteralFunction(f);
      });

  Parser<ASTBlock> lambdaBody() =>
      (codeBlock() | lambdaExpressionBody()).cast<ASTBlock>();

  Parser<ASTBlock> lambdaExpressionBody() => ref0(expression).map(
    (e) => ASTBlock(null)..addStatement(ASTStatementReturnWithExpression(e)),
  );

  Parser<ASTFunctionParametersDeclaration> lambdaParameters() =>
      (lambdaParenParameters() | lambdaSingleParameter())
          .cast<ASTFunctionParametersDeclaration>();

  Parser<ASTFunctionParametersDeclaration> lambdaSingleParameter() =>
      identifier().trim().map(
        (name) => ASTFunctionParametersDeclaration(
          [
            ASTFunctionParameterDeclaration(
              ASTTypeDynamic.instance,
              name,
              -1,
              false,
            ),
          ],
          null,
          null,
        ),
      );

  Parser<ASTFunctionParametersDeclaration> lambdaParenParameters() =>
      (char('(').trimHidden() &
              (lambdaParameter() &
                      (char(',').trimHidden() & lambdaParameter()).star())
                  .optional() &
              char(')').trimHidden())
          .map((v) {
            var first = v[1];
            if (first == null) {
              return ASTFunctionParametersDeclaration(null, null, null);
            }
            var params = <ASTFunctionParameterDeclaration>[
              (first as List)[0] as ASTFunctionParameterDeclaration,
            ];
            for (var e in (first[1] as List)) {
              params.add((e as List)[1] as ASTFunctionParameterDeclaration);
            }
            return ASTFunctionParametersDeclaration(params, null, null);
          });

  /// A lambda parameter: typed (`int a`) or untyped (`a`).
  Parser<ASTFunctionParameterDeclaration> lambdaParameter() =>
      ((type().trim() & identifier()) | identifier().trim()).map((v) {
        if (v is List) {
          return ASTFunctionParameterDeclaration(
            v[0] as ASTType,
            v[1] as String,
            -1,
            false,
          );
        }
        return ASTFunctionParameterDeclaration(
          ASTTypeDynamic.instance,
          v,
          -1,
          false,
        );
      });

  Parser<ASTFunctionParametersDeclaration> functionParametersDeclaration() =>
      (functionEmptyParametersDeclaration() |
              functionPositionalParametersDeclaration())
          .cast<ASTFunctionParametersDeclaration>();

  Parser<ASTFunctionParametersDeclaration>
  functionEmptyParametersDeclaration() => (char('(') & char(')')).map((v) {
    return ASTFunctionParametersDeclaration(null, null, null);
  });

  Parser<ASTFunctionParametersDeclaration>
  functionPositionalParametersDeclaration() =>
      (char('(') & parametersList() & char(')')).map((v) {
        return ASTFunctionParametersDeclaration(v[1], null, null);
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
              "Can't parse array with $dims dimensions: $dims",
            );
        }
      });

  Parser<ASTValue> literal() => (literalBool() | literalNum() | literalString())
      .trimHidden()
      .cast<ASTValue>();

  Parser<ASTValueBool> literalBool() =>
      (string('true') | string('false')).trim().map((v) {
        return ASTValueBool(v == 'true');
      });

  Parser<ASTValueNum> literalNum() =>
      (char('-').optional() & numberLexicalToken()).trim().map((v) {
        var negative = v[0] == '-';
        var value = v[1];
        return ASTValueNum.from(value, negative: negative);
      });

  Parser<ASTValueString> literalString() => (stringLexicalToken()).map((v) {
    return ASTValueString(v);
  });

  static List _expandListDeeply(List l) {
    if (l.isEmpty) return l;
    if (l.length == 1 && l[0] is! List) return l;

    return l.expand((e) => e is List ? _expandListDeeply(e) : [e]).toList();
  }
}
