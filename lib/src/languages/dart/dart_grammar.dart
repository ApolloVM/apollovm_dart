// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:collection/collection.dart';
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
      case 'void':
        return ASTTypeVoid.instance;
      case 'bool':
        return ASTTypeBool.instance;
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
      case 'final':
        return ASTTypeVar(unmodifiable: true);
      default:
        return ASTType(name);
    }
  }

  @override
  Parser start() => ref0(compilationUnit).trim().end();

  Parser<ASTRoot> compilationUnit() =>
      (ref0(hashbangLexicalToken).optional() &
              //ref0(libraryDirective).optional() &
              ref0(statementImport).star() &
              ref0(topLevelDefinition).star())
          .map((v) {
            var imports = v[1] as List;
            var topDef = v[2] as List;

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

  Parser topLevelDefinition() =>
      (functionDeclaration() |
              classDeclaration() |
              statementVariableDeclaration())
          .plus();

  Parser<ASTFunctionDeclaration> functionDeclaration() =>
      (type().optional() &
              identifier() &
              functionParametersDeclaration() &
              codeBlock())
          .map((v) {
            var returnType = v[0] as ASTType? ?? ASTTypeDynamic.instance;
            var parameters = v[2];
            var name = v[1];
            var block = v[3];
            return ASTFunctionDeclaration(
              name,
              parameters,
              returnType,
              block: block,
              modifiers: ASTModifiers.modifierStatic,
            );
          });

  Parser<ASTStatementImport> statementImport() =>
      (importToken().trimHidden() &
              stringLexicalToken() &
              char(';').trimHidden())
          .map((v) {
            var parsedPath = v[1] as ParsedString;
            var path =
                parsedPath.literalString ??
                (throw StateError("Invalid import parsed path: $parsedPath"));
            return ASTStatementImport(path);
          });

  Parser<ASTClassNormal> classDeclaration() =>
      (string('class').trimHidden() & identifier() & classCodeBlock()).map((v) {
        var name = v[1] as String;
        var block = v[2];
        var clazz = ASTClassNormal(name, ASTType<VMObject>(name), null);
        clazz.set(block);
        return clazz;
      });

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
      (finalToken().optional() &
              type().trimHidden() &
              identifier().trimHidden() &
              char(';').trimHidden())
          .map((v) {
            var finalValue = v[0] != null;
            var type = v[1] as ASTType;
            var name = v[2] as String;
            return ASTClassField(type, name, finalValue);
          });

  Parser<ASTClassField> classFieldDeclarationWithValue() =>
      (type() &
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

  Parser<ASTClassConstructorDeclaration> classConstructorDefaultDeclaration() =>
      (identifier() &
              constructorParametersDeclaration() &
              (char(';').trim() | codeBlock()))
          .map((v) {
            var className = v[0];
            var parameters = v[1] as ASTConstructorParametersDeclaration;
            var optionalBlock = v[2];
            var block = optionalBlock is ASTBlock ? optionalBlock : null;
            return ASTClassConstructorDeclaration(
              ASTType(className),
              '',
              parameters,
              block: block,
            );
          });

  Parser<ASTConstructorParametersDeclaration>
  constructorParametersDeclaration() =>
      (functionEmptyParametersDeclaration() |
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
      (constructorThisParameterDeclaration() |
              constructorTypedParameterDeclaration())
          .map((v) => v);

  Parser<ASTConstructorParameterDeclaration>
  constructorThisParameterDeclaration() =>
      (thisToken().trim() & char('.') & identifier()).map((v) {
        return ASTConstructorParameterDeclaration(
          ASTTypeConstructorThis.instance,
          v[2],
          -1,
          false,
          thisParameter: true,
        );
      });

  Parser<ASTConstructorParameterDeclaration>
  constructorTypedParameterDeclaration() =>
      (finalToken().trim().optional() & type().trim() & identifier()).map((v) {
        return ASTConstructorParameterDeclaration(v[1], v[2], -1, false);
      });

  Parser<ASTFunctionDeclaration> classFunctionDeclaration() =>
      (functionModifiers().optional() &
              type().optional() &
              identifier() &
              functionParametersDeclaration() &
              codeBlock())
          .map((v) {
            var modifiers = v[0];
            var returnType = v[1] as ASTType? ?? ASTTypeDynamic.instance;
            var name = v[2] as String;
            var parameters = v[3] as ASTFunctionParametersDeclaration;
            var block = v[4] as ASTBlock;
            return ASTClassFunctionDeclaration(
              null,
              name,
              parameters,
              returnType,
              block: block,
              modifiers: modifiers,
            );
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
      (branch() |
              statementForLoop() |
              statementForEach() |
              statementWhileLoop() |
              statementReturn() |
              statementFunctionDeclaration() |
              statementVariableDeclaration() |
              statementBlock() |
              statementExpression())
          .cast<ASTStatement>();

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

  Parser<ASTStatementForEach> statementForEach() =>
      (string('for').trimHidden() &
              char('(').trimHidden() &
              type().trimHidden() &
              ref0(identifier).trimHidden() &
              string('in').trimHidden() &
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

  Parser<ASTStatementBlock> statementBlock() =>
      (codeBlock()).map((v) => ASTStatementBlock(v));

  Parser<ASTStatementFunctionDeclaration> statementFunctionDeclaration() =>
      (type().optional() &
              identifier() &
              functionParametersDeclaration() &
              codeBlock())
          .map((v) {
            var returnType = v[0] as ASTType? ?? ASTTypeDynamic.instance;
            var parameters = v[2];
            var name = v[1];
            var block = v[3];
            return ASTStatementFunctionDeclaration(
              ASTFunctionDeclaration(
                name,
                parameters,
                returnType,
                block: block,
                modifiers: ASTModifiers.modifierStatic,
              ),
            );
          });

  Parser<ASTStatementVariableDeclaration> statementVariableDeclaration() =>
      (
          // var definition:
          (
              // final Type name:
              (finalToken().trimHidden() & type() & identifier().trimHidden()) |
                  // final name:
                  (finalToken() & identifier().trimHidden()) |
                  // Type name:
                  (type() & identifier().trimHidden())
              // end var definition
              ) &
              (char('=').trimHidden() & ref0(expression)).optional() &
              char(';').trimHidden())
          .map((v) {
            var varDef = v[0] as List;

            bool unmodifiable;
            ASTType type;
            String name;

            if (varDef.length == 3) {
              unmodifiable = true;
              assert((varDef[0] as Token).value == 'final');
              type = varDef[1];
              name = varDef[2];
            } else if (varDef.length == 2) {
              final varDef0 = varDef[0];
              if (varDef0 is Token && varDef0.value == 'final') {
                unmodifiable = true;
                type = getTypeByName('final');
                name = varDef[1];
              } else {
                unmodifiable = false;
                type = varDef[0];
                name = varDef[1];
              }
            } else {
              throw StateError("Invalid var definition: $varDef");
            }

            var valueOpt = v[1];
            var value = valueOpt != null ? valueOpt[1] as ASTExpression : null;
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
              (string('else').trimHidden() & codeBlock()).optional())
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

  @override
  Parser<ParsedString> parseExpressionInString() =>
      expression().map((e) => ParsedString.expression(e));

  Parser<ASTExpression> expression() =>
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

            // Split expression into logical blocks
            // separated by `&&` and `||` operators:
            var blocks = all
                .splitBefore(
                  (e) =>
                      e == ASTExpressionOperator.and ||
                      e == ASTExpressionOperator.or,
                )
                .toList();

            // Resolve the final expression:
            ASTExpression? finalExpressionOp;

            for (var i = 0; i < blocks.length; ++i) {
              final block = blocks[i];

              // Detect leading logical operator (&& / ||)
              ASTExpressionOperator? blockOp;
              final first = block.first;

              if (first == ASTExpressionOperator.and ||
                  first == ASTExpressionOperator.or) {
                block.removeAt(0);
                blockOp = first;
                // Must already have a left-hand expression:
                assert(finalExpressionOp != null);
              }

              // Resolve higher-precedence remainder (%) first
              while (block.length >= 5) {
                var e2 = block.removeLast();
                var op = block.removeLast();
                var e1 = block.removeLast();

                var maybeOpRemainder = block.last;
                if (maybeOpRemainder == ASTExpressionOperator.remainder &&
                    block.length >= 2) {
                  var maybeLeft = block[block.length - 2];
                  if (maybeLeft is ASTExpression) {
                    block.removeLast();
                    block.removeLast();
                    e1 = ASTExpressionOperation(
                      maybeLeft,
                      maybeOpRemainder,
                      e1,
                    );
                  }
                }

                var exp = ASTExpressionOperation(e1, op, e2);
                block.add(exp);
              }

              // Resolve remaining binary expressions (left-to-right)
              while (block.length >= 3) {
                var e2 = block.removeLast();
                var op = block.removeLast();
                var e1 = block.removeLast();
                var exp = ASTExpressionOperation(e1, op, e2);
                block.add(exp);
              }
              assert(block.length == 1);

              var expressionOp = block.single as ASTExpression;

              if (finalExpressionOp == null) {
                finalExpressionOp = expressionOp;
              } else {
                if (blockOp == null) {
                  throw StateError('Missing logical operator between blocks');
                }

                finalExpressionOp = ASTExpressionOperation(
                  finalExpressionOp,
                  blockOp,
                  expressionOp,
                );
              }
            }

            return finalExpressionOp!;
          });

  Parser<ASTExpressionOperator> expressionOperator() =>
      (char('+') |
              char('-') |
              char('*') |
              char('/') |
              string('~/') |
              string('==') |
              string('!=') |
              string('>=') |
              string('<=') |
              char('>') |
              char('<') |
              char('%') |
              string('&&') |
              string('||'))
          .trimHidden()
          .map((v) {
            var op = getASTExpressionOperator(v);
            if (op == ASTExpressionOperator.divide) {
              return ASTExpressionOperator.divideAsDouble;
            }
            return op;
          });

  Parser<ASTExpression> expressionNoOperation() =>
      (expressionNegate() |
              expressionLiteral() |
              expressionGroupFunctionInvocation() |
              expressionGroup() |
              expressionListEmptyLiteral() |
              expressionListLiteral() |
              expressionMapEmptyLiteral() |
              expressionMapLiteral() |
              expressionVariableDirectOperation() |
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
            var name = v[1] as String;
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
      ((identifier() & char('.')) & identifier().trimHidden()).map((v) {
        var obj = v[0] as String?;
        var name = v[2] as String;

        if (obj != null && obj != 'this') {
          var variable = ASTScopeVariable(obj);
          return ASTExpressionObjectGetterAccess(variable, name);
        } else {
          return ASTExpressionLocalGetterAccess(name);
        }
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
            var type = v[0]?[1] as ASTType?;
            var v0 = v[2];
            var tail = (v[3] as List?) ?? [];

            var vs = <ASTExpression>[
              v0,
              ...tail.expand((e) => e).whereType<ASTExpression>(),
            ];

            if (type == null) {
              var vsTypeResolving = vs.map((e) => e.resolveType(null)).toList();
              var vsTypes = vsTypeResolving.whereType<ASTType>().toList();
              if (vsTypes.length == vsTypeResolving.length) {
                var commonType = vsTypes.isEmpty
                    ? ASTTypeDynamic.instance
                    : vsTypes.reduce(
                        (a, b) => a.commonType(b) ?? ASTTypeDynamic.instance,
                      );
                type = commonType;
              }
            }

            return ASTExpressionListLiteral(type, vs);
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
              ...?entriesTail?.map((e) => MapEntry(e[0], e[1])),
            ];

            return ASTExpressionMapLiteral(keyType, valueType, entries);
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

  Parser<ASTAssignmentOperator> assigmentOperator() =>
      (char('=') |
              string('+=') |
              string('-=') |
              string('*=') |
              string('/=') |
              string('~/='))
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
  functionEmptyParametersDeclaration() => (char('(') & char(')')).map((v) {
    return ASTFunctionParametersDeclaration(null, null, null);
  });

  Parser<ASTFunctionParametersDeclaration>
  functionPositionalParametersDeclaration() =>
      (char('(') & parametersList() & char(')')).map((v) {
        return ASTFunctionParametersDeclaration(v[1], null, null);
      });

  Parser<List<ASTFunctionParameterDeclaration>> parametersList() =>
      (parameterDeclaration() &
              (char(',') & parameterDeclaration()).star() &
              char(',').optional())
          .map((v) {
            var params = _expandListDeeply(v);
            return params.whereType<ASTFunctionParameterDeclaration>().toList();
          });

  Parser<ASTFunctionParameterDeclaration> parameterDeclaration() =>
      (finalToken().trim().optional() & type().trim() & identifier()).map((v) {
        return ASTFunctionParameterDeclaration(
          v[1],
          v[2],
          -1,
          false,
          unmodifiable: v[0] != null,
        );
      });

  Parser<ASTType> type() =>
      (arrayTyped() |
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

  Parser<ASTTypeArray2D> array2DTyped() =>
      (string('List') &
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

  Parser<ASTTypeArray3D> array3DTyped() =>
      (string('List') &
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

  Parser<ASTTypeArray3D> array3DTypeDynamic() =>
      (string('List') &
              char('<') &
              string('List') &
              char('<') &
              string('List') &
              char('>') &
              char('>'))
          .map((v) {
            return ASTTypeArray3D.fromElementType(ASTTypeDynamic.instance);
          });

  Parser<ASTTypeMap> mapTyped() =>
      (string('Map') &
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
      (string('true') | string('false').trim()).map((v) {
        return ASTValueBool(v == 'true');
      });

  Parser<ASTValueNum> literalNum() =>
      (char('-').optional() & numberLexicalToken()).trim().map((v) {
        var negative = v[0] == '-';
        var value = v[1];
        return ASTValueNum.from(value, negative: negative);
      });

  Parser<ASTValue<String>> literalString() =>
      (stringLexicalToken()).plus().map((l) {
        if (l.length == 1) {
          var v = l[0];
          return v.asValue();
        } else {
          var values = l.map((e) => e.asValue()).toList();
          return ASTValueStringConcatenation(values);
        }
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
