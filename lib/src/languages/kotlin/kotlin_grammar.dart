// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:petitparser/petitparser.dart';

import '../../apollovm_base.dart';
import '../../ast/apollovm_ast_base.dart';
import '../../ast/apollovm_ast_expression.dart';
import '../../ast/apollovm_ast_statement.dart';
import '../../ast/apollovm_ast_toplevel.dart';
import '../../ast/apollovm_ast_type.dart';
import '../../ast/apollovm_ast_value.dart';
import '../../ast/apollovm_ast_variable.dart';
import 'kotlin_grammar_lexer.dart';

/// Kotlin grammar definition.
class KotlinGrammarDefinition extends KotlinGrammarLexer {
  /// Maps Kotlin's standard output functions to the VM's canonical `print`,
  /// so the same AST runs and translates consistently across languages.
  static String normalizeFunctionName(String name) {
    switch (name) {
      case 'println':
        return 'print';
      default:
        return name;
    }
  }

  static ASTType getTypeByName(String name) {
    switch (name) {
      case 'Any':
        return ASTTypeObject.instance;
      case 'Unit':
        return ASTTypeVoid.instance;
      case 'Boolean':
        return ASTTypeBool.instance;
      case 'Int':
      case 'Long':
      case 'Short':
      case 'Byte':
        return ASTTypeInt.instance;
      case 'Double':
      case 'Float':
        return ASTTypeDouble.instance;
      case 'String':
        return ASTTypeString.instance;
      case 'List':
      case 'MutableList':
      case 'Array':
        return ASTTypeArray.instanceOfDynamic;
      case 'Map':
      case 'MutableMap':
        return ASTTypeMap.instanceOfDynamicOfDynamic;
      default:
        return ASTType(name);
    }
  }

  @override
  Parser start() => ref0(compilationUnit).trim().end();

  Parser<ASTRoot> compilationUnit() =>
      (ref0(importDirective).star() & ref0(topLevelDefinition).star()).map((v) {
        var imports = v[0] as List;
        var topDef = v[1] as List;

        var root = ASTRoot();

        for (var import in imports) {
          if (import is ASTStatementImport) {
            root.addImport(import);
          }
        }

        for (var defList in topDef) {
          for (var def in defList) {
            if (def is ASTFunctionDeclaration) {
              root.addFunction(def);
            } else if (def is ASTClassNormal) {
              root.addClass(def);
            } else if (def is ASTStatementVariableDeclaration) {
              root.addStatement(def);
            }
          }
        }

        root.resolveNode(null);

        return root;
      });

  Parser<ASTStatementImport> importDirective() =>
      (importToken().trimHidden() &
              ((identifier() & (char('.') & (identifier() | char('*'))).star())
                      .flatten())
                  .trimHidden() &
              char(';').trimHidden().optional())
          .map((v) {
            var path = (v[1] as String).trim();
            return ASTStatementImport(path);
          });

  Parser topLevelDefinition() =>
      (functionDeclaration() |
              classDeclaration() |
              statementVariableDeclaration())
          .plus();

  Parser<ASTFunctionDeclaration> functionDeclaration() =>
      (funToken().trimHidden() &
              identifier() &
              functionParametersDeclaration() &
              (char(':').trimHidden() & type()).optional() &
              codeBlock())
          .map((v) {
            var name = v[1] as String;
            var parameters = v[2] as ASTFunctionParametersDeclaration;
            var returnType = (v[3]?[1] as ASTType?) ?? ASTTypeVoid.instance;
            var block = v[4] as ASTBlock;
            return ASTFunctionDeclaration(
              name,
              parameters,
              returnType,
              block: block,
              modifiers: ASTModifiers.modifierStatic,
            );
          });

  Parser<ASTClassNormal> classDeclaration() =>
      (classToken().trimHidden() & identifier() & classCodeBlock()).map((v) {
        var name = v[1] as String;
        var block = v[2];
        var clazz = ASTClassNormal(name, ASTType<VMObject>(name), null);
        clazz.set(block);
        return clazz;
      });

  Parser<ASTBlock> classCodeBlock() =>
      (char('{').trimHidden() &
              (ref0(classConstructorDeclaration) |
                      ref0(classFunctionDeclaration) |
                      ref0(classFieldDeclaration))
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
      ((valToken() | varToken()).trimHidden() &
              identifier().trimHidden() &
              char(':').trimHidden() &
              type() &
              (char('=').trimHidden() & ref0(expression)).optional() &
              char(';').trimHidden().optional())
          .map((v) {
            var finalValue = (v[0] as Token).value == 'val';
            var name = v[1] as String;
            var type = v[3] as ASTType;
            var valueOpt = v[4];
            if (valueOpt != null) {
              var expression = valueOpt[1] as ASTExpression;
              type.associateToType(expression);
              return ASTClassFieldWithInitialValue(
                type,
                name,
                expression,
                finalValue,
              );
            }
            return ASTClassField(type, name, finalValue);
          });

  Parser<ASTClassConstructorDeclaration> classConstructorDeclaration() =>
      (constructorToken().trimHidden() &
              constructorParametersDeclaration() &
              codeBlock())
          .map((v) {
            var parameters = v[1] as ASTConstructorParametersDeclaration;
            var block = v[2];
            return ASTClassConstructorDeclaration(
              ASTType(''),
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
  constructorEmptyParametersDeclaration() =>
      (char('(').trimHidden() & char(')').trimHidden()).map((v) {
        return ASTConstructorParametersDeclaration(null, null, null);
      });

  Parser<ASTConstructorParametersDeclaration>
  constructorPositionalParametersDeclaration() =>
      (char('(').trimHidden() &
              constructorParametersList() &
              char(')').trimHidden())
          .map((v) {
            return ASTConstructorParametersDeclaration(v[1], null, null);
          });

  Parser<List<ASTConstructorParameterDeclaration>>
  constructorParametersList() =>
      (constructorParameterDeclaration() &
              (char(',').trimHidden() & constructorParameterDeclaration())
                  .star() &
              char(',').trimHidden().optional())
          .map((v) {
            var params = _expandListDeeply(v);
            return params
                .whereType<ASTConstructorParameterDeclaration>()
                .toList();
          });

  Parser<ASTConstructorParameterDeclaration>
  constructorParameterDeclaration() =>
      ((valToken() | varToken()).trimHidden().optional() &
              identifier().trimHidden() &
              char(':').trimHidden() &
              type())
          .map((v) {
            return ASTConstructorParameterDeclaration(v[3], v[1], -1, false);
          });

  Parser<ASTFunctionDeclaration> classFunctionDeclaration() =>
      (funToken().trimHidden() &
              identifier() &
              functionParametersDeclaration() &
              (char(':').trimHidden() & type()).optional() &
              codeBlock())
          .map((v) {
            var name = v[1] as String;
            var parameters = v[2] as ASTFunctionParametersDeclaration;
            var returnType = (v[3]?[1] as ASTType?) ?? ASTTypeVoid.instance;
            var block = v[4] as ASTBlock;
            return ASTClassFunctionDeclaration(
              null,
              name,
              parameters,
              returnType,
              block: block,
            );
          });

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
              branch() |
              statementForEach() |
              statementWhileLoop() |
              statementReturn() |
              statementVariableDeclaration() |
              statementExpression())
          .cast<ASTStatement>();

  Parser<ASTStatementThrow> statementThrow() =>
      (throwToken().trimHidden() &
              ref0(expression) &
              char(';').trimHidden().optional())
          .map((v) => ASTStatementThrow(v[1] as ASTExpression));

  Parser<ASTStatementTryCatch> statementTryCatch() =>
      (tryToken().trimHidden() &
              codeBlock() &
              catchClause().star() &
              (finallyToken().trimHidden() & codeBlock()).optional())
          .map((v) {
            var tryBlock = v[1] as ASTBlock;
            var catches = (v[2] as List).cast<ASTCatchClause>();
            var finallyOpt = v[3] as List?;
            var finallyBlock = finallyOpt != null
                ? finallyOpt[1] as ASTBlock
                : null;
            return ASTStatementTryCatch(tryBlock, catches, finallyBlock);
          });

  /// Kotlin `catch (e: Type) { }`.
  Parser<ASTCatchClause> catchClause() =>
      (catchToken().trimHidden() &
              char('(').trimHidden() &
              identifier().trimHidden() &
              char(':').trimHidden() &
              type() &
              char(')').trimHidden() &
              codeBlock())
          .map((v) {
            var varName = v[2] as String;
            var exceptionType = v[4] as ASTType;
            var block = v[6] as ASTBlock;
            return ASTCatchClause(exceptionType, varName, block);
          });

  Parser<ASTStatementForEach> statementForEach() =>
      (forToken().trimHidden() &
              char('(').trimHidden() &
              ref0(identifier).trimHidden() &
              inToken().trimHidden() &
              ref0(expression) &
              char(')').trimHidden() &
              codeBlock())
          .map((v) {
            var variableName = v[2];
            var iterableExp = v[4];
            var block = v[6];

            return ASTStatementForEach(
              ASTTypeVar(),
              variableName,
              iterableExp,
              block,
            );
          });

  Parser<ASTStatementWhileLoop> statementWhileLoop() =>
      (whileToken().trimHidden() &
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
      (returnToken().trimHidden() &
              expression().optional() &
              char(';').trimHidden().optional())
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
      (expression() & char(';').trimHidden().optional()).map((v) {
        return ASTStatementExpression(v[0]);
      });

  Parser<ASTStatementVariableDeclaration> statementVariableDeclaration() =>
      ((valToken() | varToken()).trimHidden() &
              identifier().trimHidden() &
              (char(':').trimHidden() & type()).optional() &
              (char('=').trimHidden() & ref0(expression)).optional() &
              char(';').trimHidden().optional())
          .map((v) {
            var unmodifiable = (v[0] as Token).value == 'val';
            var name = v[1] as String;
            var typeOpt = v[2];
            var valueOpt = v[3];
            var value = valueOpt != null ? valueOpt[1] as ASTExpression : null;

            ASTType type;
            if (typeOpt != null) {
              type = typeOpt[1] as ASTType;
            } else {
              type = ASTTypeVar(unmodifiable: unmodifiable);
            }

            if (value != null) type.associateToType(value);

            return ASTStatementVariableDeclaration(
              type,
              name,
              value,
              unmodifiable: unmodifiable,
            );
          });

  Parser<ASTBranch> branch() =>
      (ref0(branchIfElseIfsElseBlock) |
              ref0(branchIfElseBlock) |
              ref0(branchIfBlock))
          .cast<ASTBranch>();

  Parser<ASTBranchIfBlock> branchIfBlock() =>
      (ifToken().trimHidden() &
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
      (ifToken().trimHidden() &
              char('(').trimHidden() &
              ref0(expression) &
              char(')').trimHidden() &
              codeBlock() &
              elseToken().trimHidden() &
              codeBlock())
          .map((v) {
            var condition = v[2];
            var blockIf = v[4];
            var blockElse = v[6];
            return ASTBranchIfElseBlock(condition, blockIf, blockElse);
          });

  Parser<ASTBranchIfElseIfsElseBlock> branchIfElseIfsElseBlock() =>
      (ifToken().trimHidden() &
              char('(').trimHidden() &
              ref0(expression) &
              char(')').trimHidden() &
              codeBlock() &
              ref0(branchElseIfs).plus() &
              (elseToken().trimHidden() & codeBlock()).optional())
          .map((v) {
            var condition = v[2];
            var blockIf = v[4];
            var blockElseIfs = v[5] as List;
            var blockElse = v[6]?[1];

            return ASTBranchIfElseIfsElseBlock(
              condition,
              blockIf,
              blockElseIfs.cast<ASTBranchIfBlock>().toList(),
              blockElse,
            );
          });

  Parser<ASTBranchIfBlock> branchElseIfs() =>
      (elseToken().trimHidden() &
              ifToken().trimHidden() &
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

  Parser<ASTExpression> expression() =>
      (ref0(ifExpression) | ref0(expressionOperationChain)).cast<ASTExpression>();

  /// Kotlin's `if` used as an expression that yields a value:
  /// `if (cond) valueIfTrue else valueIfFalse`. Statement-level `if` with
  /// `{ ... }` blocks is handled earlier by [branch].
  Parser<ASTExpression> ifExpression() =>
      (ifToken().trimHidden() &
              char('(').trimHidden() &
              ref0(expression) &
              char(')').trimHidden() &
              ref0(expressionOperationChain) &
              elseToken().trimHidden() &
              ref0(expression))
          .map(
            (v) => ASTExpressionConditional(
              v[2] as ASTExpression,
              v[4] as ASTExpression,
              v[6] as ASTExpression,
            ),
          );

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
              char('<') |
              char('>') |
              string('&&') |
              string('||'))
          .trimHidden()
          .map((v) {
            return getASTExpressionOperator(v);
          });

  Parser<ASTExpression> expressionNoOperation() =>
      (expressionNegate() |
              expressionLiteral() |
              expressionGroupFunctionInvocation() |
              expressionGroup() |
              expressionListLiteral() |
              expressionMapLiteral() |
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
      ((identifier() & char('.')).optional() &
              identifier() &
              char('(').trimHidden() &
              ref0(expressionSequence).optional() &
              char(')').trimHidden() &
              expressionChainFunctionInvocation().star())
          .map((v) {
            var objOpt = v[0] as List?;
            var obj = objOpt != null ? objOpt[0] as String : null;
            var name = normalizeFunctionName(v[1] as String);
            var args = v[3] as List<ASTExpression>?;
            args ??= <ASTExpression>[];
            var chainFunctions = (v[5] as List)
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

            // `this.field` reads from the current instance; `obj.field` from
            // the named variable's instance.
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

  Parser<ASTExpressionListLiteral> expressionListLiteral() =>
      ((string('listOf') | string('mutableListOf') | string('arrayListOf'))
                  .trimHidden() &
              char('(').trimHidden() &
              ref0(expressionSequence).optional() &
              char(')').trimHidden())
          .map((v) {
            var values = (v[2] as List<ASTExpression>?) ?? <ASTExpression>[];

            // Infer the element type from the values, so iteration/arithmetic
            // over the list elements uses a concrete type instead of `dynamic`:
            ASTType type = ASTTypeDynamic.instance;
            var resolved = values.map((e) => e.resolveType(null)).toList();
            var types = resolved.whereType<ASTType>().toList();
            if (types.isNotEmpty && types.length == resolved.length) {
              type = types.reduce(
                (a, b) => a.commonType(b) ?? ASTTypeDynamic.instance,
              );
            }

            return ASTExpressionListLiteral(type, values);
          });

  Parser<ASTExpressionMapLiteral> expressionMapLiteral() =>
      ((string('mapOf') | string('mutableMapOf') | string('hashMapOf'))
                  .trimHidden() &
              char('(').trimHidden() &
              (mapEntry() & (char(',').trimHidden() & mapEntry()).star())
                  .optional() &
              char(')').trimHidden())
          .map((v) {
            var entries = <MapEntry<ASTExpression, ASTExpression>>[];
            var entriesOpt = v[2];
            if (entriesOpt != null) {
              entries.add(
                entriesOpt[0] as MapEntry<ASTExpression, ASTExpression>,
              );
              for (var tail in (entriesOpt[1] as List)) {
                entries.add(tail[1] as MapEntry<ASTExpression, ASTExpression>);
              }
            }
            return ASTExpressionMapLiteral(
              ASTTypeDynamic.instance,
              ASTTypeDynamic.instance,
              entries,
            );
          });

  Parser<MapEntry<ASTExpression, ASTExpression>> mapEntry() =>
      (ref0(expression) & string('to').trimHidden() & ref0(expression)).map((
        v,
      ) {
        return MapEntry(v[0] as ASTExpression, v[2] as ASTExpression);
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

  Parser<ASTFunctionParametersDeclaration> functionParametersDeclaration() =>
      (functionEmptyParametersDeclaration() |
              functionPositionalParametersDeclaration())
          .cast<ASTFunctionParametersDeclaration>();

  Parser<ASTFunctionParametersDeclaration>
  functionEmptyParametersDeclaration() =>
      (char('(').trimHidden() & char(')').trimHidden()).map((v) {
        return ASTFunctionParametersDeclaration(null, null, null);
      });

  Parser<ASTFunctionParametersDeclaration>
  functionPositionalParametersDeclaration() =>
      (char('(').trimHidden() & parametersList() & char(')').trimHidden()).map((
        v,
      ) {
        return ASTFunctionParametersDeclaration(v[1], null, null);
      });

  Parser<List<ASTFunctionParameterDeclaration>> parametersList() =>
      (parameterDeclaration() &
              (char(',').trimHidden() & parameterDeclaration()).star() &
              char(',').trimHidden().optional())
          .map((v) {
            var params = _expandListDeeply(v);
            return params.whereType<ASTFunctionParameterDeclaration>().toList();
          });

  Parser<ASTFunctionParameterDeclaration> parameterDeclaration() =>
      (identifier().trimHidden() & char(':').trimHidden() & type()).map((v) {
        return ASTFunctionParameterDeclaration(v[2], v[0], -1, false);
      });

  Parser<ASTType> type() =>
      ((mapTyped() | arrayTyped() | simpleType()) & char('?').optional()).map((
        v,
      ) {
        return v[0] as ASTType;
      });

  Parser<ASTType> simpleType() => identifier().map((v) {
    return getTypeByName(v);
  });

  Parser<ASTTypeArray> arrayTyped() =>
      ((string('List') | string('MutableList') | string('Array')) &
              char('<').trimHidden() &
              simpleType() &
              char('>').trimHidden())
          .map((v) {
            var t = v[2] as ASTType;
            return ASTTypeArray(t);
          });

  Parser<ASTTypeMap> mapTyped() =>
      ((string('Map') | string('MutableMap')) &
              char('<').trimHidden() &
              simpleType() &
              char(',').trimHidden() &
              simpleType() &
              char('>').trimHidden())
          .map((v) {
            var key = v[2] as ASTType;
            var val = v[4] as ASTType;
            return ASTTypeMap(key, val);
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

  Parser<ASTValue<String>> literalString() => (stringLexicalToken()).map((v) {
    return v.asValue();
  });

  static List _expandListDeeply(List l) {
    if (l.isEmpty) return l;
    if (l.length == 1 && l[0] is! List) return l;

    final result = [];
    _expandInto(l, result);
    return result;
  }

  static void _expandInto(List source, List target) {
    for (final e in source) {
      if (e is List) {
        _expandInto(e, target);
      } else {
        target.add(e);
      }
    }
  }
}
