// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:petitparser/petitparser.dart';

import '../../../apollovm_base.dart';
import '../../../ast/apollovm_ast_base.dart';
import '../../../ast/apollovm_ast_expression.dart';
import '../../../ast/apollovm_ast_statement.dart';
import '../../../ast/apollovm_ast_toplevel.dart';
import '../../../ast/apollovm_ast_type.dart';
import '../../../ast/apollovm_ast_value.dart';
import '../../../ast/apollovm_ast_variable.dart';
import 'javascript_grammar_lexer.dart';

/// JavaScript (modern ES) grammar definition.
///
/// Parses untyped JavaScript into the shared ApolloVM AST. Inferred types
/// (variables, parameters, fields, return types) are mapped to `dynamic`.
class JavaScriptGrammarDefinition extends JavaScriptGrammarLexer {
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
      (arrowNamedFunction() |
              functionDeclaration() |
              classDeclaration() |
              statementVariableDeclaration())
          .plus();

  Parser<ASTStatementImport> statementImport() =>
      (importToken().trimHidden() &
              (importClause() & fromToken().trimHidden()).optional() &
              stringPathLexicalToken() &
              char(';').trimHidden())
          .map((v) {
            var clause = v[1] as List?;
            var prefix = clause != null ? clause[0] as String? : null;
            var path = v[2] as String;
            return ASTStatementImport(path, prefix: prefix);
          });

  /// Matches `* as name` or `name` in an import; returns the binding name.
  Parser<String?> importClause() =>
      ((char('*').trimHidden() & string('as').trimHidden() & identifier()) |
              identifier())
          .map((v) {
            if (v is List) return v[2] as String;
            return v as String;
          });

  Parser<ASTFunctionDeclaration> functionDeclaration() =>
      (asyncToken().trimHidden().optional() &
              functionToken().trimHidden() &
              identifier() &
              functionParametersDeclaration() &
              codeBlock())
          .map((v) {
            var isAsync = v[0] != null;
            var name = v[2] as String;
            var parameters = v[3] as ASTFunctionParametersDeclaration;
            var block = v[4] as ASTBlock;
            return ASTFunctionDeclaration(
              name,
              parameters,
              inferReturnType(block),
              block: block,
              modifiers: ASTModifiers(isStatic: true, isAsync: isAsync),
            );
          });

  /// Name of the class currently being parsed. Captured when the class name is
  /// matched (before its body) so that a `constructor` method — whose own name
  /// is the keyword `constructor`, not the class name — can be built with the
  /// correct class type. This is required for translation to typed languages
  /// (e.g. Dart/Java), whose generators emit the constructor's `classType.name`.
  String _currentClassName = '';

  Parser<ASTClassNormal> classDeclaration() =>
      (classToken().trimHidden() &
              identifier().map((name) {
                _currentClassName = name;
                return name;
              }) &
              (extendsToken().trimHidden() & identifier()).optional() &
              classCodeBlock())
          .map((v) {
            var name = v[1] as String;
            var block = v[3] as ASTBlock;
            var clazz = ASTClassNormal(name, ASTType<VMObject>(name), null);
            clazz.set(block);
            return clazz;
          });

  Parser<ASTBlock> classCodeBlock() =>
      (char('{').trimHidden() &
              (ref0(classFunctionDeclaration) |
                      ref0(classFieldDeclarationWithValue) |
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

  /// `name;` — an untyped class field.
  Parser<ASTClassField> classFieldDeclaration() =>
      (identifier().trimHidden() & char(';').trimHidden()).map((v) {
        var name = v[0] as String;
        return ASTClassField(ASTTypeDynamic.instance, name, false);
      });

  /// `name = expr;` — an untyped class field with an initial value.
  Parser<ASTClassField> classFieldDeclarationWithValue() =>
      (identifier().trimHidden() &
              char('=').trimHidden() &
              ref0(expression) &
              char(';').trimHidden())
          .map((v) {
            var name = v[0] as String;
            var expression = v[2] as ASTExpression;
            var type = ASTTypeDynamic.instance;
            return ASTClassFieldWithInitialValue(type, name, expression, false);
          });

  /// `[static] name(params) { block }` — a class method.
  ///
  /// A method named `constructor` is parsed as an [ASTClassConstructorDeclaration]
  /// (with an empty name; the enclosing class fixes up its type), so that
  /// `new Foo(...)` / `Foo(...)` instantiate the class. The JS code generator
  /// emits it back as the `constructor` keyword.
  Parser<Object> classFunctionDeclaration() =>
      (staticToken().trimHidden().optional() &
              asyncToken().trimHidden().optional() &
              identifier() &
              functionParametersDeclaration() &
              codeBlock())
          .map((v) {
            var isStatic = v[0] != null;
            var isAsync = v[1] != null;
            var name = v[2] as String;
            var parameters = v[3] as ASTFunctionParametersDeclaration;
            var block = v[4] as ASTBlock;

            if (name == 'constructor') {
              return ASTClassConstructorDeclaration(
                ASTType(_currentClassName),
                '',
                _toConstructorParameters(parameters),
                block: block,
                modifiers: ASTModifiers(isAsync: isAsync),
              );
            }

            return ASTClassFunctionDeclaration(
              null,
              name,
              parameters,
              inferReturnType(block),
              block: block,
              modifiers: ASTModifiers(isStatic: isStatic, isAsync: isAsync),
            );
          });

  /// Converts parsed function parameters into constructor parameters (the
  /// `constructor` method name is untyped, so each becomes a positional
  /// `dynamic` constructor parameter).
  ASTConstructorParametersDeclaration _toConstructorParameters(
    ASTFunctionParametersDeclaration fn,
  ) {
    var positional = fn.positionalParameters
        ?.map(
          (p) => ASTConstructorParameterDeclaration(
            p.type,
            p.name,
            p.index,
            p.optional,
          ),
        )
        .toList();
    return ASTConstructorParametersDeclaration(positional, null, null);
  }

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
        return ASTSingleLineStatementBlock(null)..addStatement(v);
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
              statementDoWhileLoop() |
              statementForLoop() |
              statementForEach() |
              statementWhileLoop() |
              statementReturn() |
              statementFunctionDeclaration() |
              statementArrowFunction() |
              statementVariableDeclaration() |
              statementBlock() |
              statementExpression())
          .cast<ASTStatement>();

  Parser<ASTStatementBreak> statementBreak() =>
      (string('break') &
              ref0(identifierPartLexicalToken).not() &
              char(';').trimHidden().optional())
          .map((v) => ASTStatementBreak());

  Parser<ASTStatementContinue> statementContinue() =>
      (string('continue') &
              ref0(identifierPartLexicalToken).not() &
              char(';').trimHidden().optional())
          .map((v) => ASTStatementContinue());

  Parser<ASTStatementDoWhileLoop> statementDoWhileLoop() =>
      (string('do').trimHidden() &
              codeBlock() &
              string('while').trimHidden() &
              char('(').trimHidden() &
              ref0(expression) &
              char(')').trimHidden() &
              char(';').trimHidden().optional())
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

  /// JavaScript `catch (e) { }` (untyped; binding optional).
  Parser<ASTCatchClause> catchClause() =>
      (catchToken().trimHidden() &
              (char('(').trimHidden() &
                      identifier().trimHidden() &
                      char(')').trimHidden())
                  .optional() &
              codeBlock())
          .map((v) {
            var bind = v[1] as List?;
            var varName = bind != null ? bind[1] as String : null;
            var block = v[2] as ASTBlock;
            return ASTCatchClause(null, varName, block);
          });

  Parser<ASTStatement> statementSimple() =>
      (statementVariableDeclaration() | statementExpression())
          .cast<ASTStatement>();

  Parser<ASTStatementForLoop> statementForLoop() =>
      (forToken().trimHidden() &
              char('(').trimHidden() &
              ref0(statementSimple) &
              ref0(expression) &
              char(';').trimHidden() &
              ref0(expression) &
              char(')').trimHidden() &
              codeBlock())
          .map((v) {
            return ASTStatementForLoop(v[2], v[3], v[5], v[7]);
          });

  Parser<ASTStatementForEach> statementForEach() =>
      (forToken().trimHidden() &
              char('(').trimHidden() &
              (constToken() | letToken() | varToken()).trimHidden() &
              identifier().trimHidden() &
              ofToken().trimHidden() &
              ref0(expression) &
              char(')').trimHidden() &
              codeBlock())
          .map((v) {
            var variableName = v[3] as String;
            var iterableExp = v[5] as ASTExpression;
            var block = v[7] as ASTBlock;
            return ASTStatementForEach(
              ASTTypeDynamic.instance,
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
            return ASTStatementWhileLoop(v[2], v[4]);
          });

  Parser<ASTStatementReturn> statementReturn() =>
      (returnToken().trimHidden() &
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
      (functionToken().trimHidden() &
              identifier() &
              functionParametersDeclaration() &
              codeBlock())
          .map((v) {
            var name = v[1] as String;
            var parameters = v[2] as ASTFunctionParametersDeclaration;
            var block = v[3] as ASTBlock;
            return ASTStatementFunctionDeclaration(
              ASTFunctionDeclaration(
                name,
                parameters,
                inferReturnType(block),
                block: block,
                modifiers: ASTModifiers.modifierStatic,
              ),
            );
          });

  // ---------------------------------------------------------------------------
  // Arrow functions.
  //
  // Supported form: an arrow assigned to a name, desugared to a named function
  // declaration (so it is callable as `name(...)`), e.g.
  //   const add = (a, b) => a + b;
  //   const square = x => x * x;
  //   const greet = () => { print('hi'); };
  // Anonymous arrows passed as callbacks (true closures) are not yet supported.
  // ---------------------------------------------------------------------------

  /// `(const|let|var) name = <arrow> ;` → a named [ASTFunctionDeclaration].
  Parser<ASTFunctionDeclaration> arrowNamedFunction() =>
      ((constToken() | letToken() | varToken()).trimHidden() &
              identifier().trimHidden() &
              char('=').trimHidden() &
              asyncToken().trimHidden().optional() &
              arrowParameters() &
              string('=>').trimHidden() &
              arrowBody() &
              char(';').trimHidden())
          .map((v) {
            var name = v[1] as String;
            var isAsync = v[3] != null;
            var parameters = v[4] as ASTFunctionParametersDeclaration;
            var block = v[6] as ASTBlock;
            return ASTFunctionDeclaration(
              name,
              parameters,
              inferReturnType(block),
              block: block,
              modifiers: ASTModifiers(isStatic: true, isAsync: isAsync),
            );
          });

  /// Statement form of [arrowNamedFunction] (registers the function in the
  /// enclosing block when run, making it callable by name).
  Parser<ASTStatementFunctionDeclaration> statementArrowFunction() =>
      arrowNamedFunction().map((f) => ASTStatementFunctionDeclaration(f));

  /// Anonymous arrow function used as an expression (a closure), e.g.
  /// `(a, b) => a + b`, `x => x * x`, `() => { ... }`. Captures the enclosing
  /// scope at runtime and can be passed as a callback or stored in a variable.
  Parser<ASTExpression> expressionArrowFunction() =>
      (asyncToken().trimHidden().optional() &
              arrowParameters() &
              string('=>').trimHidden() &
              arrowBody())
          .map((v) {
            var isAsync = v[0] != null;
            var parameters = v[1] as ASTFunctionParametersDeclaration;
            var block = v[3] as ASTBlock;
            var f = ASTFunctionDeclaration(
              '',
              parameters,
              inferReturnType(block),
              block: block,
              modifiers: ASTModifiers(isStatic: true, isAsync: isAsync),
            );
            return ASTExpressionLiteralFunction(f);
          });

  /// Arrow parameters: `(a, b)`, `()`, or a single bare identifier `a`.
  Parser<ASTFunctionParametersDeclaration> arrowParameters() =>
      (functionParametersDeclaration() | arrowSingleParameter())
          .cast<ASTFunctionParametersDeclaration>();

  Parser<ASTFunctionParametersDeclaration> arrowSingleParameter() =>
      identifier().trimHidden().map((name) {
        return ASTFunctionParametersDeclaration(
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
        );
      });

  /// Arrow body: a `{ … }` block, or an expression (`=> expr`) wrapped as
  /// `{ return expr; }`.
  Parser<ASTBlock> arrowBody() =>
      (codeBlock() | arrowExpressionBody()).cast<ASTBlock>();

  Parser<ASTBlock> arrowExpressionBody() => ref0(expression).map((exp) {
    return ASTBlock(null)..addStatement(_arrowReturnStatement(exp));
  });

  static ASTStatement _arrowReturnStatement(ASTExpression value) {
    if (value is ASTExpressionVariableAccess) {
      if (value.variable.name == 'null') return ASTStatementReturnNull();
      return ASTStatementReturnVariable(value.variable);
    } else if (value is ASTExpressionLiteral) {
      return ASTStatementReturnValue(value.value);
    } else {
      return ASTStatementReturnWithExpression(value);
    }
  }

  Parser<ASTStatementVariableDeclaration> statementVariableDeclaration() =>
      ((constToken() | letToken() | varToken()).trimHidden() &
              identifier().trimHidden() &
              (char('=').trimHidden() & ref0(expression)).optional() &
              char(';').trimHidden())
          .map((v) {
            var keyword = (v[0] as Token).value as String;
            var unmodifiable = keyword == 'const';
            var name = v[1] as String;

            var valueOpt = v[2];
            var value = valueOpt != null ? valueOpt[1] as ASTExpression : null;

            var type = ASTTypeVar(unmodifiable: unmodifiable);
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
            return ASTBranchIfBlock(v[2], v[4]);
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
            return ASTBranchIfElseBlock(v[2], v[4], v[6]);
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
            return ASTBranchIfBlock(v[3], v[5]);
          });

  @override
  Parser<ASTExpression> parseExpressionInString() => ref0(expression);

  @override
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
      (string('===') |
              string('!==') |
              string('==') |
              string('!=') |
              string('<<') |
              string('>>') |
              string('>=') |
              string('<=') |
              string('&&') |
              string('||') |
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
              case '===':
                return ASTExpressionOperator.equals;
              case '!==':
                return ASTExpressionOperator.notEquals;
              case '/':
                // JavaScript `/` is always floating-point division.
                return ASTExpressionOperator.divideAsDouble;
              default:
                return getASTExpressionOperator(v);
            }
          });

  Parser<ASTExpression> expressionNoOperation() =>
      (expressionAwait() |
              expressionArrowFunction() |
              expressionNegate() |
              expressionBitwiseNot() |
              expressionLiteral() |
              expressionGroupFunctionInvocation() |
              expressionGroup() |
              expressionListLiteral() |
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

  Parser<ASTExpressionAwait> expressionAwait() =>
      (awaitToken() & (ref0(expressionNoOperation) | ref0(expressionGroup)))
          .map((v) => ASTExpressionAwait(v[1] as ASTExpression));

  Parser<ASTExpressionNegation> expressionNegate() =>
      (char('!').trimHidden() &
              (ref0(expressionNoOperation) | ref0(expressionGroup)))
          .map((v) => ASTExpressionNegation(v[1] as ASTExpression));

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
              ref0(expressionSequence).optional() &
              char(')').trimHidden() &
              expressionChainFunctionInvocation().star())
          .map((v) {
            var expression = v[0] as ASTExpression;
            var name = v[2] as String;
            var args = (v[4] as List<ASTExpression>?) ?? <ASTExpression>[];
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

  /// A function/method call, optionally prefixed with `new` (e.g.
  /// `new Foo(...)`). The `new` keyword is consumed and ignored: a call to a
  /// class name resolves to its constructor (instantiation) at runtime, exactly
  /// like `Foo(...)`.
  Parser<ASTExpressionFunctionInvocation> expressionFunctionInvocation() =>
      (newToken().trimHidden().optional() &
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
            var args = (v[4] as List<ASTExpression>?) ?? <ASTExpression>[];
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

  Parser<List<ASTExpression>> expressionSequence() =>
      (ref0(expression) & (char(',').trimHidden() & ref0(expression)).star())
          .map((v) {
            var list = _expandListDeeply(v);
            return list.whereType<ASTExpression>().toList();
          });

  Parser<ASTExpressionNullValue> expressionNullValue() =>
      (nullToken()).map((v) => ASTExpressionNullValue());

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
              ref0(expressionSequence).optional() &
              char(')').trimHidden() &
              expressionChainFunctionInvocation().star())
          .map((v) {
            var variable = v[0];
            var expression = v[2];
            var fName = v[5];
            var args = (v[7] as List<ASTExpression>?) ?? <ASTExpression>[];
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
            var args = (v[3] as List<ASTExpression>?) ?? <ASTExpression>[];
            return ASTExpressionChainFunctionInvocation(fName, args);
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

  Parser<ASTExpressionVariableDirectOperation>
  expressionVariableDirectOperation() =>
      (expressionVariableDirectPosOperation() |
              expressionVariableDirectPreOperation())
          .cast<ASTExpressionVariableDirectOperation>();

  Parser<ASTExpressionVariableDirectOperation>
  expressionVariableDirectPosOperation() =>
      (variable() & (string('++') | string('--'))).map((v) {
        var operator = getASTAssignmentDirectOperator(v[1]);
        return ASTExpressionVariableDirectOperation(v[0], operator, false);
      });

  Parser<ASTExpressionVariableDirectOperation>
  expressionVariableDirectPreOperation() =>
      ((string('++') | string('--')) & variable()).map((v) {
        var operator = getASTAssignmentDirectOperator(v[0]);
        return ASTExpressionVariableDirectOperation(v[1], operator, true);
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
      (string('+=') |
              string('-=') |
              string('*=') |
              string('/=') |
              string('%=') |
              char('='))
          .trimHidden()
          .map((v) => getASTAssignmentOperator(v));

  Parser<ASTVariable> variable() =>
      (thisVariable() | scopeVariable()).cast<ASTVariable>();

  Parser<ASTThisVariable> thisVariable() =>
      (token('this')).map((v) => ASTThisVariable());

  Parser<ASTScopeVariable> scopeVariable() =>
      (identifier()).map((v) => ASTScopeVariable(v));

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

  /// A bare, untyped parameter name (typed as `dynamic`).
  Parser<ASTFunctionParameterDeclaration> parameterDeclaration() =>
      (identifier().trimHidden()).map((v) {
        return ASTFunctionParameterDeclaration(
          ASTTypeDynamic.instance,
          v,
          -1,
          false,
        );
      });

  Parser<ASTValue> literal() => (literalBool() | literalNum() | literalString())
      .trimHidden()
      .cast<ASTValue>();

  Parser<ASTValueBool> literalBool() => (trueToken() | falseToken()).map((v) {
    var s = v is Token ? v.value : '$v';
    return ASTValueBool(s == 'true');
  });

  Parser<ASTValueNum> literalNum() =>
      (char('-').optional() & numberLexicalToken()).trim().map((v) {
        var negative = v[0] == '-';
        var value = v[1];
        return ASTValueNum.from(value, negative: negative);
      });

  Parser<ASTValue<String>> literalString() => stringLexicalToken();

  /// Infers a function/method return type from its body: `void` when the body
  /// has no value-returning `return`, otherwise `dynamic` (JavaScript is
  /// untyped, but this keeps cross-translation to typed languages correct).
  static ASTType inferReturnType(ASTBlock block) =>
      _hasValueReturn(block) ? ASTTypeDynamic.instance : ASTTypeVoid.instance;

  static bool _hasValueReturn(ASTNode node) {
    if (node is ASTStatementReturnValue ||
        node is ASTStatementReturnVariable ||
        node is ASTStatementReturnWithExpression ||
        node is ASTStatementReturnNull) {
      return true;
    }
    // Do not descend into nested function declarations.
    if (node is ASTStatementFunctionDeclaration) return false;
    for (var child in node.children) {
      if (_hasValueReturn(child)) return true;
    }
    return false;
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
