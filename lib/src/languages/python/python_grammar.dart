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
import 'python_grammar_lexer.dart';

/// Python 3 grammar definition.
///
/// Operates on the INDENT/DEDENT/NEWLINE-marked stream produced by the
/// [PythonIndentationPreprocessor] (see [PythonGrammarLexer]); a suite (block)
/// is `NEWLINE INDENT statement+ DEDENT`. Parses strictly-typed, statically
/// resolvable Python into the shared ApolloVM AST: type hints become concrete
/// [ASTType]s, and un-annotated bindings fall back to `var`/`dynamic`.
class PythonGrammarDefinition extends PythonGrammarLexer {
  /// Maps a Python type-hint name to an [ASTType].
  static ASTType getTypeByName(String name) {
    switch (name) {
      case 'object':
      case 'Object':
        return ASTTypeObject.instance;
      case 'None':
        return ASTTypeVoid.instance;
      case 'bool':
        return ASTTypeBool.instance;
      case 'int':
        return ASTTypeInt.instance;
      case 'float':
        return ASTTypeDouble.instance;
      case 'str':
        return ASTTypeString.instance;
      case 'Any':
      case 'dynamic':
        return ASTTypeDynamic.instance;
      case 'List':
      case 'list':
        return ASTTypeArray.instanceOfDynamic;
      case 'Dict':
      case 'dict':
        return ASTTypeMap.instanceOfDynamicOfDynamic;
      default:
        return ASTType(name);
    }
  }

  @override
  Parser start() => ref0(compilationUnit).trim().end();

  Parser<ASTRoot> compilationUnit() =>
      (ref0(statementImport).star() & ref0(topLevelDefinition).star()).map((v) {
        var imports = v[0] as List;
        var topDef = v[1] as List;

        var root = ASTRoot();

        for (var import in imports) {
          if (import is ASTStatementImport) {
            root.addImport(import);
          }
        }

        var moduleStatements = <ASTStatement>[];

        for (var defList in topDef) {
          for (var def in defList) {
            if (def is ASTFunctionDeclaration) {
              root.addFunction(def);
            } else if (def is ASTClassNormal) {
              root.addClass(def);
            } else if (def is ASTStatement) {
              moduleStatements.add(def);
            }
          }
        }

        for (var stm in resolveScopeBindings(moduleStatements)) {
          root.addStatement(stm);
        }

        root.resolveNode(null);

        return root;
      });

  Parser topLevelDefinition() =>
      (enumDeclaration() |
              functionDeclaration() |
              classDeclaration() |
              ref0(statement))
          .plus();

  /// Python enum: `class Name(Enum): NEWLINE INDENT (NAME = value)+ DEDENT`.
  Parser<ASTClassEnum> enumDeclaration() =>
      (classToken().trimHidden() &
              identifier() &
              char('(').trimHidden() &
              string('Enum') &
              ref0(identifierPartLexicalToken).not() &
              char(')').trimHidden() &
              char(':').trimHidden() &
              newlineToken() &
              indentToken() &
              enumEntry().plus() &
              dedentToken())
          .map((v) {
            var name = v[1] as String;
            var entries = (v[9] as List).cast<ASTEnumEntry>();
            return ASTClassEnum(
              name,
              ASTType<VMObject>(name),
              null,
              entries: entries,
            );
          });

  Parser<ASTEnumEntry> enumEntry() =>
      (identifier().trimHidden() &
              char('=').trimHidden() &
              ref0(expression) &
              newlineToken())
          .map(
            (v) => ASTEnumEntry(v[0] as String, value: v[2] as ASTExpression),
          );

  // ---------------------------------------------------------------------------
  // Imports: `import x [as y]` and `from x import y`.
  // ---------------------------------------------------------------------------
  Parser<ASTStatementImport> statementImport() =>
      (ref0(importFrom) | ref0(importSimple)).cast<ASTStatementImport>();

  Parser<ASTStatementImport> importSimple() =>
      (importToken().trimHidden() &
              dottedName() &
              (asToken().trimHidden() & identifier()).optional() &
              newlineToken())
          .map((v) {
            var path = v[1] as String;
            var asOpt = v[2] as List?;
            var prefix = asOpt != null ? asOpt[1] as String : null;
            return ASTStatementImport(path, prefix: prefix);
          });

  Parser<ASTStatementImport> importFrom() =>
      (fromToken().trimHidden() &
              dottedName() &
              importToken().trimHidden() &
              (char('*').trimHidden().map((_) => null) | ref0(importNameList)) &
              newlineToken())
          .map((v) {
            var path = v[1] as String;
            var names = v[3] as List<ASTImportedSymbol>?;
            if (names == null) {
              // `from x import *`
              return ASTStatementImport(path, wildcard: true);
            }
            return ASTStatementImport(path, namedSymbols: names);
          });

  /// `a [as b], c [as d]` in a `from x import ...` statement.
  Parser<List<ASTImportedSymbol>> importNameList() =>
      (ref0(importName) &
              (char(',').trimHidden() & ref0(importName)).star())
          .map((v) {
            var first = v[0] as ASTImportedSymbol;
            var rest = (v[1] as List)
                .map((e) => (e as List)[1] as ASTImportedSymbol);
            return <ASTImportedSymbol>[first, ...rest];
          });

  /// `name` or `name as alias`.
  Parser<ASTImportedSymbol> importName() =>
      (identifier() & (asToken().trimHidden() & identifier()).optional()).map((
        v,
      ) {
        var name = v[0] as String;
        var asOpt = v[1] as List?;
        var alias = asOpt != null ? asOpt[1] as String : null;
        return ASTImportedSymbol(name, alias: alias);
      });

  Parser<String> dottedName() =>
      (identifier() & (char('.') & identifier()).star()).trimHidden().map((v) {
        var first = v[0] as String;
        var rest = (v[1] as List).map((e) => '.${(e as List)[1]}').join();
        return '$first$rest';
      });

  // ---------------------------------------------------------------------------
  // Functions.
  // ---------------------------------------------------------------------------
  Parser<ASTFunctionDeclaration> functionDeclaration() =>
      (asyncToken().trimHidden().optional() &
              defToken().trimHidden() &
              identifier() &
              functionParametersDeclaration() &
              returnAnnotation().optional() &
              char(':').trimHidden() &
              suite())
          .map((v) {
            var isAsync = v[0] != null;
            var name = v[2] as String;
            var parameters = _dropSelf(
              v[3] as ASTFunctionParametersDeclaration,
            );
            var block = v[6] as ASTBlock;
            var declared = v[4] as ASTType?;
            var returnType = declared ?? inferReturnType(block);
            return ASTFunctionDeclaration(
              name,
              parameters,
              returnType,
              block: block,
              modifiers: ASTModifiers(isStatic: true, isAsync: isAsync),
            );
          });

  Parser<ASTType> returnAnnotation() =>
      (string('->').trimHidden() & ref0(type)).map((v) => v[1] as ASTType);

  // ---------------------------------------------------------------------------
  // Classes.
  // ---------------------------------------------------------------------------
  Parser<ASTClassNormal> classDeclaration() =>
      (classToken().trimHidden() &
              identifier() &
              (char('(').trimHidden() &
                      identifier().optional() &
                      char(')').trimHidden())
                  .optional() &
              char(':').trimHidden() &
              classSuite())
          .map((v) {
            var name = v[1] as String;
            var superOpt = v[2] as List?;
            var superName = superOpt != null ? superOpt[1] as String? : null;
            var block = v[4] as ASTClassNormal;

            var clazz = ASTClassNormal(
              name,
              ASTType<VMObject>(name),
              null,
              superClassName: superName,
            );

            clazz.addAllFields(block.fields);

            // Python's `__init__` is the class constructor; everything else is
            // a regular method. The constructor needs the real class name so it
            // round-trips to languages whose constructors are named (Dart/Java).
            for (var set in block.functions) {
              for (var f in set.functions) {
                if (f.name == '__init__') {
                  clazz.addConstructor(_toConstructor(name, f));
                } else {
                  clazz.addFunction(f);
                }
              }
            }

            return clazz;
          });

  Parser<ASTBlock> classSuite() =>
      (newlineToken() &
              indentToken() &
              (ref0(methodDeclaration) |
                      ref0(classFieldDeclarationWithValue) |
                      ref0(classFieldDeclaration))
                  .plus() &
              dedentToken())
          .map((v) {
            var list = v[2] as List;
            var fields = list.whereType<ASTClassField>().toList();
            var functions = list.whereType<ASTFunctionDeclaration>().toList();

            var block = ASTClassNormal('?', ASTType<VMObject>('?'), null);
            block.addAllFields(fields);
            block.addAllFunctions(functions);
            return block;
          });

  /// Builds an [ASTClassConstructorDeclaration] from a parsed `__init__`
  /// method of class [className]. (`self` was already dropped by
  /// [methodDeclaration].)
  static ASTClassConstructorDeclaration _toConstructor(
    String className,
    ASTFunctionDeclaration init,
  ) {
    var positional = init.parameters.positionalParameters
        ?.map(
          (p) => ASTConstructorParameterDeclaration(
            p.type,
            p.name,
            p.index,
            p.optional,
          ),
        )
        .toList();

    var parameters = ASTConstructorParametersDeclaration(
      positional == null || positional.isEmpty ? null : positional,
      null,
      null,
    );

    return ASTClassConstructorDeclaration(
      ASTType<VMObject>(className),
      '',
      parameters,
      block: init,
      modifiers: init.modifiers,
    );
  }

  Parser<ASTClassFunctionDeclaration> methodDeclaration() =>
      (asyncToken().trimHidden().optional() &
              defToken().trimHidden() &
              identifier() &
              functionParametersDeclaration() &
              returnAnnotation().optional() &
              char(':').trimHidden() &
              suite())
          .map((v) {
            var isAsync = v[0] != null;
            var name = v[2] as String;
            var parameters = _dropSelf(
              v[3] as ASTFunctionParametersDeclaration,
            );
            var block = v[6] as ASTBlock;
            var declared = v[4] as ASTType?;
            var returnType = declared ?? inferReturnType(block);
            return ASTClassFunctionDeclaration(
              null,
              name,
              parameters,
              returnType,
              block: block,
              modifiers: ASTModifiers(isAsync: isAsync),
            );
          });

  /// `name: type = expr` — a class field with an initial value.
  Parser<ASTClassField> classFieldDeclarationWithValue() =>
      (identifier().trimHidden() &
              (char(':').trimHidden() & ref0(type)).optional() &
              char('=').trimHidden() &
              ref0(expression) &
              newlineToken())
          .map((v) {
            var name = v[0] as String;
            var annOpt = v[1] as List?;
            var expression = v[3] as ASTExpression;
            var type = annOpt != null
                ? annOpt[1] as ASTType
                : ASTTypeDynamic.instance;
            return ASTClassFieldWithInitialValue(type, name, expression, false);
          });

  /// `name: type` — a class field declaration without a value.
  Parser<ASTClassField> classFieldDeclaration() =>
      (identifier().trimHidden() &
              char(':').trimHidden() &
              ref0(type) &
              newlineToken())
          .map((v) {
            var name = v[0] as String;
            var type = v[2] as ASTType;
            return ASTClassField(type, name, false);
          });

  // ---------------------------------------------------------------------------
  // Suites (indented blocks).
  // ---------------------------------------------------------------------------
  Parser<ASTBlock> suite() =>
      (newlineToken() & indentToken() & ref0(suiteBody) & dedentToken()).map((
        v,
      ) {
        return v[2] as ASTBlock;
      });

  Parser<ASTBlock> suiteBody() =>
      (ref0(passBody) | ref0(statementsBody)).cast<ASTBlock>();

  Parser<ASTBlock> passBody() =>
      (passToken().trimHidden() & newlineToken()).map((_) => ASTBlock(null));

  Parser<ASTBlock> statementsBody() => ref0(statement).plus().map((v) {
    var statements = resolveScopeBindings(v.cast<ASTStatement>());
    return ASTBlock(null)..addAllStatements(statements);
  });

  Parser<ASTStatement> statement() =>
      (statementTryCatch() |
              statementMatch() |
              branch() |
              statementForEach() |
              statementWhileLoop() |
              simpleStatementLine())
          .cast<ASTStatement>();

  /// A simple (single-line) statement terminated by NEWLINE.
  Parser<ASTStatement> simpleStatementLine() =>
      ((statementBreak() |
                      statementContinue() |
                      statementReturn() |
                      statementRaise() |
                      statementVariableDeclaration() |
                      statementExpression())
                  .cast<ASTStatement>() &
              newlineToken())
          .map((v) => v[0] as ASTStatement);

  Parser<ASTStatementBreak> statementBreak() =>
      breakToken().trimHidden().map((_) => ASTStatementBreak());

  Parser<ASTStatementContinue> statementContinue() =>
      continueToken().trimHidden().map((_) => ASTStatementContinue());

  /// Python `match exp: NEWLINE INDENT (case <pattern>: suite)+ DEDENT`
  /// (no fall-through). `case _:` is the default clause.
  Parser<ASTStatementSwitch> statementMatch() =>
      (matchKeyword() &
              ref0(expression) &
              char(':').trimHidden() &
              newlineToken() &
              indentToken() &
              matchCase().plus() &
              dedentToken())
          .map((v) {
            var exp = v[1] as ASTExpression;
            var cases = (v[5] as List).cast<ASTSwitchCase>();
            return ASTStatementSwitch(exp, cases, fallThrough: false);
          });

  Parser<ASTSwitchCase> matchCase() =>
      (caseKeyword() & matchPattern() & char(':').trimHidden() & suite()).map((
        v,
      ) {
        var value = v[1] as ASTExpression?;
        var block = v[3] as ASTBlock;
        return ASTSwitchCase(value, block);
      });

  /// A `case` pattern: `_` (wildcard/default) or a value expression.
  Parser<ASTExpression?> matchPattern() =>
      ((char('_') & ref0(identifierPartLexicalToken).not()).trimHidden().map(
                (v) => null,
              ) |
              ref0(expression).map((v) => v as ASTExpression?))
          .cast<ASTExpression?>();

  /// Soft keyword `match` (only at a statement head).
  Parser matchKeyword() =>
      (string('match') & ref0(identifierPartLexicalToken).not()).trimHidden();

  /// Soft keyword `case`.
  Parser caseKeyword() =>
      (string('case') & ref0(identifierPartLexicalToken).not()).trimHidden();

  Parser<ASTStatementThrow> statementRaise() =>
      (raiseToken().trimHidden() & ref0(expression)).map((v) {
        return ASTStatementThrow(v[1] as ASTExpression);
      });

  Parser<ASTStatementTryCatch> statementTryCatch() =>
      (tryToken().trimHidden() &
              char(':').trimHidden() &
              suite() &
              ref0(exceptClause).star() &
              (finallyToken().trimHidden() & char(':').trimHidden() & suite())
                  .optional())
          .map((v) {
            var tryBlock = v[2] as ASTBlock;
            var catches = (v[3] as List).cast<ASTCatchClause>();
            var finallyOpt = v[4] as List?;
            var finallyBlock = finallyOpt != null
                ? finallyOpt[2] as ASTBlock
                : null;
            return ASTStatementTryCatch(tryBlock, catches, finallyBlock);
          });

  /// Python `except [Type [as e]]:` suite.
  Parser<ASTCatchClause> exceptClause() =>
      (exceptToken().trimHidden() &
              (ref0(type) & (asToken().trimHidden() & identifier()).optional())
                  .optional() &
              char(':').trimHidden() &
              suite())
          .map((v) {
            var head = v[1] as List?;
            ASTType? exceptionType;
            String? varName;
            if (head != null) {
              exceptionType = head[0] as ASTType;
              var asOpt = head[1] as List?;
              varName = asOpt != null ? asOpt[1] as String : null;
            }
            var block = v[3] as ASTBlock;
            return ASTCatchClause(exceptionType, varName, block);
          });

  Parser<ASTStatementForEach> statementForEach() =>
      (forToken().trimHidden() &
              identifier().trimHidden() &
              inToken().trimHidden() &
              ref0(expression) &
              char(':').trimHidden() &
              suite())
          .map((v) {
            var variableName = v[1] as String;
            var iterableExp = v[3] as ASTExpression;
            var block = v[5] as ASTBlock;
            return ASTStatementForEach(
              ASTTypeDynamic.instance,
              variableName,
              iterableExp,
              block,
            );
          });

  Parser<ASTStatementWhileLoop> statementWhileLoop() =>
      (whileToken().trimHidden() &
              ref0(expression) &
              char(':').trimHidden() &
              suite())
          .map((v) {
            return ASTStatementWhileLoop(v[1], v[3]);
          });

  Parser<ASTStatementReturn> statementReturn() =>
      (returnToken().trimHidden() & ref0(expression).optional()).map((v) {
        var value = v[1];

        if (value == null) {
          return ASTStatementReturn();
        } else if (value is ASTExpression) {
          if (value is ASTExpressionVariableAccess) {
            if (value.variable.name == 'None') {
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
      (ref0(expression)).map((v) => ASTStatementExpression(v));

  /// `name [: type] = expr` — a variable binding. The first binding of a name
  /// in a scope is a declaration; [resolveScopeBindings] rewrites later ones to
  /// plain assignments.
  Parser<ASTStatementVariableDeclaration> statementVariableDeclaration() =>
      (identifier().trimHidden() &
              (char(':').trimHidden() & ref0(type)).optional() &
              char('=').trimHidden() &
              ref0(expression))
          .map((v) {
            var name = v[0] as String;
            var annOpt = v[1] as List?;
            var value = v[3] as ASTExpression;

            ASTType type;
            if (annOpt != null) {
              type = annOpt[1] as ASTType;
            } else {
              type = ASTTypeVar();
            }
            type.associateToType(value);

            return ASTStatementVariableDeclaration(type, name, value);
          });

  // ---------------------------------------------------------------------------
  // Branches: if / elif / else.
  // ---------------------------------------------------------------------------
  Parser<ASTBranch> branch() =>
      (ref0(branchIfElseIfsElseBlock) |
              ref0(branchIfElseBlock) |
              ref0(branchIfBlock))
          .cast<ASTBranch>();

  Parser<ASTBranchIfBlock> branchIfBlock() =>
      (ifToken().trimHidden() &
              ref0(expression) &
              char(':').trimHidden() &
              suite())
          .map((v) => ASTBranchIfBlock(v[1], v[3]));

  Parser<ASTBranchIfElseBlock> branchIfElseBlock() =>
      (ifToken().trimHidden() &
              ref0(expression) &
              char(':').trimHidden() &
              suite() &
              elseToken().trimHidden() &
              char(':').trimHidden() &
              suite())
          .map((v) => ASTBranchIfElseBlock(v[1], v[3], v[6]));

  Parser<ASTBranchIfElseIfsElseBlock> branchIfElseIfsElseBlock() =>
      (ifToken().trimHidden() &
              ref0(expression) &
              char(':').trimHidden() &
              suite() &
              ref0(branchElseIfs).plus() &
              (elseToken().trimHidden() & char(':').trimHidden() & suite())
                  .optional())
          .map((v) {
            var condition = v[1];
            var blockIf = v[3];
            var blockElseIfs = v[4] as List;
            var elseOpt = v[5] as List?;
            var blockElse = elseOpt != null ? elseOpt[2] as ASTBlock : null;

            return ASTBranchIfElseIfsElseBlock(
              condition,
              blockIf,
              blockElseIfs.cast<ASTBranchIfBlock>().toList(),
              blockElse,
            );
          });

  Parser<ASTBranchIfBlock> branchElseIfs() =>
      (elifToken().trimHidden() &
              ref0(expression) &
              char(':').trimHidden() &
              suite())
          .map((v) => ASTBranchIfBlock(v[1], v[3]));

  // ---------------------------------------------------------------------------
  // Expressions.
  // ---------------------------------------------------------------------------
  @override
  Parser<ASTExpression> parseExpressionInString() => ref0(expression);

  @override
  Parser<ASTExpression> expression() =>
      (ref0(expressionOperationChain) &
              (ifToken().trimHidden() &
                      ref0(expressionOperationChain) &
                      elseToken().trimHidden() &
                      ref0(expression))
                  .optional())
          .map((v) {
            var base = v[0] as ASTExpression;
            var ternary = v[1] as List?;
            if (ternary == null) return base;
            // Python's conditional expression:
            // `valueIfTrue if condition else valueIfFalse`.
            return ASTExpressionConditional(
              ternary[1] as ASTExpression,
              base,
              ternary[3] as ASTExpression,
            );
          });

  Parser<ASTExpression> expressionOperationChain() =>
      (ref0(expressionNoOperation) &
              (expressionOperator() & ref0(expressionNoOperation)).star())
          .map((v) {
            var exp1 = v[0];
            var rest = v[1] as List;
            if (rest.isEmpty) return exp1;

            var extra = _expandListDeeply(rest);
            var all = <dynamic>[exp1, ...extra];
            return computeFinalExpression(all);
          });

  Parser<ASTExpressionOperator> expressionOperator() =>
      ((string('//') |
                      string('==') |
                      string('!=') |
                      string('<<') |
                      string('>>') |
                      string('>=') |
                      string('<=') |
                      char('+') |
                      char('-') |
                      char('*') |
                      char('/') |
                      char('>') |
                      char('<') |
                      char('%') |
                      char('&') |
                      char('|') |
                      char('^'))
                  .trimHidden()
                  .map((v) {
                    switch (v) {
                      case '//':
                        return ASTExpressionOperator.divideAsInt;
                      case '/':
                        // Python `/` is always floating-point division.
                        return ASTExpressionOperator.divideAsDouble;
                      default:
                        return getASTExpressionOperator(v);
                    }
                  }) |
              andToken().map((_) => ASTExpressionOperator.and) |
              orToken().map((_) => ASTExpressionOperator.or))
          .cast<ASTExpressionOperator>();

  Parser<ASTExpression> expressionNoOperation() =>
      (expressionAwait() |
              expressionLambda() |
              expressionNegate() |
              expressionBitwiseNot() |
              expressionLiteral() |
              expressionGroupFunctionInvocation() |
              expressionGroup() |
              expressionListLiteral() |
              expressionMapLiteral() |
              expressionVariableEntryAssignment() |
              expressionObjectFieldAssignment() |
              expressionVariableAssigment() |
              expressionFunctionInvocation() |
              expressionObjectEntryFunctionInvocation() |
              expressionVariableEntryAccess() |
              expressionGetterAccess() |
              expressionNoneValue() |
              expressionVariableAccess() |
              expressionNegative())
          .cast<ASTExpression>();

  /// Python `await expr` — suspends until the awaited awaitable completes.
  Parser<ASTExpressionAwait> expressionAwait() =>
      (awaitToken() & (ref0(expressionNoOperation) | ref0(expressionGroup)))
          .map((v) => ASTExpressionAwait(v[1] as ASTExpression));

  /// Python anonymous function: `lambda [params]: expr` (single-expression
  /// body). Captures the enclosing scope at runtime (closure).
  Parser<ASTExpression> expressionLambda() =>
      (lambdaToken().trimHidden() &
              _lambdaParameters() &
              char(':').trimHidden() &
              ref0(expression))
          .map((v) {
            var parameters = v[1] as ASTFunctionParametersDeclaration;
            var body = v[3] as ASTExpression;
            var block = ASTBlock(null)
              ..addStatement(ASTStatementReturnWithExpression(body));
            var f = ASTFunctionDeclaration(
              '',
              parameters,
              inferReturnType(block),
              block: block,
              modifiers: ASTModifiers.modifierStatic,
            );
            return ASTExpressionLiteralFunction(f);
          });

  Parser<ASTFunctionParametersDeclaration> _lambdaParameters() =>
      (identifier().trimHidden() &
              (char(',').trimHidden() & identifier().trimHidden()).star())
          .optional()
          .map((v) {
            if (v == null) {
              return ASTFunctionParametersDeclaration(null, null, null);
            }
            var names = <String>[v[0] as String];
            for (var e in (v[1] as List)) {
              names.add((e as List)[1] as String);
            }
            var params = <ASTFunctionParameterDeclaration>[];
            for (var i = 0; i < names.length; ++i) {
              params.add(
                ASTFunctionParameterDeclaration(
                  ASTTypeDynamic.instance,
                  names[i],
                  i,
                  false,
                ),
              );
            }
            return ASTFunctionParametersDeclaration(params, null, null);
          });

  Parser<ASTExpressionNegation> expressionNegate() =>
      (notToken() & (ref0(expressionNoOperation) | ref0(expressionGroup))).map((
        v,
      ) {
        return ASTExpressionNegation(v[1] as ASTExpression);
      });

  Parser<ASTExpressionNegative> expressionNegative() =>
      (char('-').trimHidden() &
              (ref0(expressionNoOperation) | ref0(expressionGroup)))
          .map((v) => ASTExpressionNegative(v[1] as ASTExpression));

  Parser<ASTExpressionBitwiseNot> expressionBitwiseNot() =>
      (char('~').trimHidden() &
              (ref0(expressionNoOperation) | ref0(expressionGroup)))
          .map((v) => ASTExpressionBitwiseNot(v[1] as ASTExpression));

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
              ref0(callArguments).optional() &
              char(')').trimHidden() &
              expressionChainFunctionInvocation().star())
          .map((v) {
            var expression = v[0] as ASTExpression;
            var name = v[2] as String;
            var argsRec =
                v[4]
                    as ({
                      List<ASTExpression> positional,
                      Map<String, ASTExpression>? named,
                    })?;
            var args = argsRec?.positional ?? <ASTExpression>[];
            var named = argsRec?.named;
            var chainFunctions = (v[6] as List)
                .whereType<ASTExpressionChainFunctionInvocation>()
                .toList();
            return ASTExpressionGroupFunctionInvocation(
              expression,
              name,
              args,
              chainFunctions,
            )..namedArguments = named;
          });

  Parser<ASTExpression> expressionFunctionInvocation() =>
      ((identifier() & char('.')).optional() &
              identifier() &
              char('(').trimHidden() &
              ref0(callArguments).optional() &
              char(')').trimHidden() &
              expressionChainFunctionInvocation().star())
          .map((v) {
            var objOpt = v[0] as List?;
            var obj = objOpt != null ? objOpt[0] as String : null;
            var name = v[1] as String;
            var argsRec =
                v[3]
                    as ({
                      List<ASTExpression> positional,
                      Map<String, ASTExpression>? named,
                    })?;
            var args = argsRec?.positional ?? <ASTExpression>[];
            var named = argsRec?.named;
            var chainFunctions = (v[5] as List)
                .whereType<ASTExpressionChainFunctionInvocation>()
                .toList();

            if (obj == null) {
              return ASTExpressionLocalFunctionInvocation(
                name,
                args,
                chainFunctions,
              )..namedArguments = named;
            }

            // `self.method(...)`/`this.method(...)` invoke on the current
            // instance; `obj.method(...)` on the named variable's instance.
            // Keep the receiver so the call round-trips (Python needs the
            // explicit `self.`), mirroring the Dart/Java grammars.
            ASTVariable variable = (obj == 'self' || obj == 'this')
                ? ASTThisVariable()
                : ASTScopeVariable(obj);
            return ASTExpressionObjectFunctionInvocation(
              variable,
              name,
              args,
              chainFunctions,
            )..namedArguments = named;
          });

  Parser<ASTExpression> expressionGetterAccess() =>
      ((identifier() & char('.')) &
              identifier().trimHidden() &
              expressionChainFunctionInvocation().star())
          .map((v) {
            var obj = v[0] as String;
            var name = v[2] as String;
            var chainFunctions = (v[3] as List)
                .whereType<ASTExpressionChainFunctionInvocation>()
                .toList();

            // `self.field`/`this.field` reads from the current instance;
            // `obj.field` from the named variable's instance. Keep the receiver
            // so the access round-trips, mirroring the Dart/Java grammars.
            ASTVariable variable = (obj == 'self' || obj == 'this')
                ? ASTThisVariable()
                : ASTScopeVariable(obj);
            return ASTExpressionObjectGetterAccess(
              variable,
              name,
              chainFunctions,
            );
          });

  Parser<List<ASTExpression>> expressionSequence() =>
      (ref0(expression) & (char(',').trimHidden() & ref0(expression)).star())
          .map((v) {
            var list = _expandListDeeply(v);
            return list.whereType<ASTExpression>().toList();
          });

  /// Python uses `=` (not `==`) to separate a keyword argument's name from its
  /// value, e.g. `f(a=1)`.
  @override
  Parser namedArgumentSeparatorParser() => char('=') & char('=').not();

  Parser<ASTExpressionNullValue> expressionNoneValue() =>
      (noneToken()).map((v) => ASTExpressionNullValue());

  Parser<ASTExpressionVariableAccess> expressionVariableAccess() =>
      (variable()).map((v) => ASTExpressionVariableAccess(v));

  Parser<ASTExpressionLiteral> expressionLiteral() =>
      (literal()).map((v) => ASTExpressionLiteral(v));

  Parser<ASTExpressionVariableEntryAccess> expressionVariableEntryAccess() =>
      (variable() & char('[') & ref0(expression) & char(']')).map((v) {
        return ASTExpressionVariableEntryAccess(v[0], v[2]);
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
              ref0(callArguments).optional() &
              char(')').trimHidden() &
              expressionChainFunctionInvocation().star())
          .map((v) {
            var variable = v[0];
            var expression = v[2];
            var fName = v[5];
            var argsRec =
                v[7]
                    as ({
                      List<ASTExpression> positional,
                      Map<String, ASTExpression>? named,
                    })?;
            var args = argsRec?.positional ?? <ASTExpression>[];
            var named = argsRec?.named;
            var chainFunctions = (v[9] as List)
                .whereType<ASTExpressionChainFunctionInvocation>()
                .toList();
            return ASTExpressionObjectEntryFunctionInvocation(
              variable,
              expression,
              fName,
              args,
              chainFunctions,
            )..namedArguments = named;
          });

  Parser<ASTExpressionChainFunctionInvocation>
  expressionChainFunctionInvocation() =>
      (char('.').trimHidden() &
              identifier() &
              char('(').trimHidden() &
              ref0(callArguments).optional() &
              char(')').trimHidden())
          .map((v) {
            var fName = v[1];
            var argsRec =
                v[3]
                    as ({
                      List<ASTExpression> positional,
                      Map<String, ASTExpression>? named,
                    })?;
            var args = argsRec?.positional ?? <ASTExpression>[];
            var named = argsRec?.named;
            return ASTExpressionChainFunctionInvocation(fName, args)
              ..namedArguments = named;
          });

  Parser<ASTExpressionListLiteral> expressionListLiteral() =>
      (char('[').trimHidden() &
              (ref0(expression) &
                      (char(',').trimHidden() & ref0(expression)).star() &
                      char(',').trimHidden().optional())
                  .optional() &
              char(']').trimHidden())
          .map((v) {
            var body = v[1] as List?;

            var vs = <ASTExpression>[];
            if (body != null) {
              vs.add(body[0] as ASTExpression);
              var tail = (body[1] as List?) ?? [];
              vs.addAll(tail.expand((e) => e).whereType<ASTExpression>());
            }

            ASTType? type;
            if (vs.isNotEmpty) {
              var vsTypeResolving = vs.map((e) => e.resolveType(null)).toList();
              var vsTypes = vsTypeResolving.whereType<ASTType>().toList();
              if (vsTypes.length == vsTypeResolving.length) {
                type = vsTypes.isEmpty
                    ? ASTTypeDynamic.instance
                    : vsTypes.reduce(
                        (a, b) => a.commonType(b) ?? ASTTypeDynamic.instance,
                      );
              }
            }

            return ASTExpressionListLiteral(
              type ?? ASTTypeDynamic.instance,
              vs,
            );
          });

  Parser<ASTExpressionMapLiteral> expressionMapLiteral() =>
      (char('{').trimHidden() &
              (ref0(mapEntry) &
                      (char(',').trimHidden() & ref0(mapEntry)).star() &
                      char(',').trimHidden().optional())
                  .optional() &
              char('}').trimHidden())
          .map((v) {
            var body = v[1] as List?;

            var entries = <MapEntry<ASTExpression, ASTExpression>>[];
            if (body != null) {
              entries.add(body[0] as MapEntry<ASTExpression, ASTExpression>);
              var tail = (body[1] as List?) ?? [];
              for (var e in tail) {
                entries.add(
                  (e as List)[1] as MapEntry<ASTExpression, ASTExpression>,
                );
              }
            }

            return ASTExpressionMapLiteral(null, null, entries);
          });

  Parser<MapEntry<ASTExpression, ASTExpression>> mapEntry() =>
      (ref0(expression) & char(':').trimHidden() & ref0(expression)).map((v) {
        return MapEntry(v[0] as ASTExpression, v[2] as ASTExpression);
      });

  Parser<ASTExpressionVariableAssignment> expressionVariableAssigment() =>
      (variable() & assigmentOperator() & ref0(expression)).map((v) {
        return ASTExpressionVariableAssignment(v[0], v[1], v[2]);
      });

  /// `self.x = value` / `obj.field = value` (and `+=`, `-=`, `*=`, `//=`, `/=`).
  /// `self`/`this` target the current instance; `obj` the named variable's
  /// instance. Mirrors the Dart/Java object field assignment.
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
            ASTVariable variable = (obj == 'self' || obj == 'this')
                ? ASTThisVariable()
                : ASTScopeVariable(obj);
            return ASTExpressionObjectSetterAssignment(
              variable,
              name,
              op,
              valueExpr,
            );
          });

  Parser<ASTExpressionVariableEntryAssignment>
  expressionVariableEntryAssignment() =>
      (variable() &
              char('[') &
              ref0(expression) &
              char(']').trimHidden() &
              assigmentOperator() &
              ref0(expression))
          .map((v) {
            return ASTExpressionVariableEntryAssignment(v[0], v[2], v[4], v[5]);
          });

  Parser<ASTAssignmentOperator> assigmentOperator() =>
      (string('+=') |
              string('-=') |
              string('*=') |
              string('//=') |
              string('/=') |
              char('='))
          .trimHidden()
          .map((v) {
            var op = v == '//=' ? '~/=' : v;
            return getASTAssignmentOperator(op);
          });

  Parser<ASTVariable> variable() =>
      (thisVariable() | scopeVariable()).cast<ASTVariable>();

  /// `self` (and `this`) bind to the current instance.
  Parser<ASTThisVariable> thisVariable() =>
      ((string('self') | string('this')) &
              ref0(identifierPartLexicalToken).not())
          .pick(0)
          .trim(ref0(hiddenStuffWhitespace))
          .map((v) => ASTThisVariable());

  Parser<ASTScopeVariable> scopeVariable() =>
      (identifier()).map((v) => ASTScopeVariable(v));

  // ---------------------------------------------------------------------------
  // Parameters.
  // ---------------------------------------------------------------------------
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

  /// `name` or `name: type`, optionally with a `= default` value (e.g.
  /// `a=5` / `a: int = 5`).
  Parser<ASTFunctionParameterDeclaration> parameterDeclaration() =>
      (identifier().trimHidden() &
              (char(':').trimHidden() & ref0(type)).optional() &
              parameterDefaultValue().optional())
          .map((v) {
            var name = v[0] as String;
            var annOpt = v[1] as List?;
            var type = annOpt != null
                ? annOpt[1] as ASTType
                : ASTTypeDynamic.instance;
            return ASTFunctionParameterDeclaration(type, name, -1, false)
              ..defaultValue = v[2] as ASTExpression?;
          });

  // ---------------------------------------------------------------------------
  // Types.
  // ---------------------------------------------------------------------------
  Parser<ASTType> type() =>
      (listType() | dictType() | simpleType()).cast<ASTType>();

  Parser<ASTType> simpleType() =>
      (noneToken().map((_) => ASTTypeVoid.instance) |
              identifier().map((name) => getTypeByName(name)))
          .cast<ASTType>();

  Parser<ASTTypeArray> listType() =>
      ((string('List') | string('list')) &
              char('[').trimHidden() &
              ref0(type) &
              char(']').trimHidden())
          .map((v) => ASTTypeArray(v[2] as ASTType));

  Parser<ASTTypeMap> dictType() =>
      ((string('Dict') | string('dict')) &
              char('[').trimHidden() &
              ref0(type) &
              char(',').trimHidden() &
              ref0(type) &
              char(']').trimHidden())
          .map((v) => ASTTypeMap(v[2] as ASTType, v[4] as ASTType));

  // ---------------------------------------------------------------------------
  // Literals.
  // ---------------------------------------------------------------------------
  Parser<ASTValue> literal() => (literalBool() | literalNum() | literalString())
      .trimHidden()
      .cast<ASTValue>();

  Parser<ASTValueBool> literalBool() => (trueToken() | falseToken()).map((v) {
    var s = v is Token ? v.value : '$v';
    return ASTValueBool(s == 'True');
  });

  Parser<ASTValueNum> literalNum() =>
      (char('-').optional() & numberLexicalToken()).trim().map((v) {
        var negative = v[0] == '-';
        var value = v[1];
        return ASTValueNum.from(value, negative: negative);
      });

  Parser<ASTValue<String>> literalString() => stringLexicalToken();

  // ---------------------------------------------------------------------------
  // Helpers.
  // ---------------------------------------------------------------------------

  /// Removes a leading `self`/`this` parameter (the method receiver).
  static ASTFunctionParametersDeclaration _dropSelf(
    ASTFunctionParametersDeclaration parameters,
  ) {
    var positional = parameters.positionalParameters;
    if (positional == null || positional.isEmpty) return parameters;

    var first = positional.first.name;
    if (first != 'self' && first != 'this') return parameters;

    var rest = positional.sublist(1);
    return ASTFunctionParametersDeclaration(
      rest.isEmpty ? null : rest,
      null,
      null,
    );
  }

  /// Infers a return type from the body: `void` when there's no value-returning
  /// `return`, otherwise `dynamic`.
  static ASTType inferReturnType(ASTBlock block) =>
      _hasValueReturn(block) ? ASTTypeDynamic.instance : ASTTypeVoid.instance;

  static bool _hasValueReturn(ASTNode node) {
    if (node is ASTStatementReturnValue ||
        node is ASTStatementReturnVariable ||
        node is ASTStatementReturnWithExpression ||
        node is ASTStatementReturnNull) {
      return true;
    }
    for (var child in node.children) {
      if (_hasValueReturn(child)) return true;
    }
    return false;
  }

  /// Implements Python binding semantics within a single scope: the first
  /// binding of a name is a declaration; later bindings of the same name become
  /// plain assignments (so the runtime never redeclares a variable).
  static List<ASTStatement> resolveScopeBindings(
    List<ASTStatement> statements,
  ) {
    var declared = <String>{};
    var result = <ASTStatement>[];

    for (var stm in statements) {
      if (stm is ASTStatementVariableDeclaration) {
        var name = stm.name;
        var value = stm.value;

        // A first binding whose value references the name being bound (e.g.
        // `s = s + 1`) can't be a real declaration-with-initializer — the name
        // must already exist in an enclosing scope (a parameter or an outer
        // binding). Treat it (and any later binding) as a plain assignment;
        // otherwise it becomes a self-referential declaration that recurses
        // forever during type resolution / code generation.
        if (value != null &&
            (declared.contains(name) || _valueReferences(value, name))) {
          declared.add(name);
          result.add(
            ASTStatementExpression(
              ASTExpressionVariableAssignment(
                ASTScopeVariable(name),
                ASTAssignmentOperator.set,
                value,
              ),
            ),
          );
          continue;
        }

        declared.add(name);
      }
      result.add(stm);
    }

    return result;
  }

  /// Whether [value] reads the variable [name] anywhere in its expression tree.
  static bool _valueReferences(ASTExpression value, String name) {
    bool isRef(ASTNode n) => n is ASTVariable && n.name == name;
    if (isRef(value)) return true;
    return value.descendantChildren.any(isRef);
  }

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
