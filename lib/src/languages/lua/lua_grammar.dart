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
import 'lua_grammar_lexer.dart';

/// Lua grammar definition.
///
/// Parses a subset of Lua into the shared ApolloVM AST: top-level and `local`
/// functions, `local`/global variables, `if/elseif/else`, `while`, numeric and
/// generic `for`, expressions (with `and`/`or`/`not`, `~=` and `..`), table
/// constructors, and a table-based class convention (see [compilationUnit]).
class LuaGrammarDefinition extends LuaGrammarLexer {
  /// Lua's standard `print` is already the VM's canonical function name, so no
  /// remapping is needed; kept for symmetry with the other languages.
  static String normalizeFunctionName(String name) {
    switch (name) {
      default:
        return name;
    }
  }

  @override
  Parser start() => ref0(compilationUnit).trim().end();

  /// Parses the whole source and assembles it into an [ASTRoot].
  ///
  /// Table-based classes are recognized by grouping, by owner name:
  /// `Name = { ... }` (fields), `Name.__index = Name` (boilerplate, ignored),
  /// and `function Name:method(...)` / `function Name.method(...)` (methods).
  Parser<ASTRoot> compilationUnit() => ref0(topLevelItem).star().map((items) {
    var root = ASTRoot();

    // Names that denote a class: any owner with a method or an `__index`.
    var classNames = <String>{};
    for (var it in items) {
      if (it is _OwnerFunction) {
        classNames.add(it.owner);
      } else if (it is _ClassIndex) {
        classNames.add(it.name);
      }
    }

    var classOrder = <String>[];
    var classFields = <String, List<ASTClassField>>{};
    var classMethods = <String, List<ASTClassFunctionDeclaration>>{};

    void ensureClass(String name) {
      if (!classFields.containsKey(name)) {
        classOrder.add(name);
        classFields[name] = [];
        classMethods[name] = [];
      }
    }

    var topFunctions = <ASTFunctionDeclaration>[];
    var topStatements = <ASTStatement>[];

    for (var it in items) {
      if (it is _OwnerFunction) {
        ensureClass(it.owner);
        classMethods[it.owner]!.add(it.toMethod());
      } else if (it is _ClassIndex) {
        ensureClass(it.name);
      } else if (it is _NamedTableAssignment) {
        if (classNames.contains(it.name)) {
          ensureClass(it.name);
          classFields[it.name]!.addAll(it.toFields());
        } else {
          topStatements.add(it.toVariableDeclaration());
        }
      } else if (it is ASTFunctionDeclaration) {
        topFunctions.add(it);
      } else if (it is ASTStatement) {
        topStatements.add(it);
      }
    }

    for (var f in topFunctions) {
      root.addFunction(f);
    }
    for (var s in topStatements) {
      root.addStatement(s);
    }

    for (var name in classOrder) {
      var clazz = ASTClassNormal(name, ASTType<VMObject>(name), null);
      var block = ASTClassNormal('?', ASTType<VMObject>('?'), null);
      block.addAllFields(classFields[name]!);
      block.addAllFunctions(classMethods[name]!);
      clazz.set(block);
      root.addClass(clazz);
    }

    root.resolveNode(null);

    return root;
  });

  Parser topLevelItem() =>
      (ref0(localFunctionDeclaration) |
              ref0(functionDefinition) |
              ref0(classIndexAssignment) |
              ref0(namedTableAssignment) |
              ref0(statement))
          .cast();

  // -----------------------------------------------------------------
  // Functions.
  // -----------------------------------------------------------------

  /// `function name(params) ... end` (plain) or
  /// `function Owner:method(params) ... end` / `function Owner.method(...)`.
  Parser functionDefinition() =>
      (functionToken().trimHidden() &
              identifier() &
              ((char(':') | char('.')).trimHidden() & identifier()).optional() &
              functionParametersDeclaration() &
              ref0(block) &
              endToken().trimHidden())
          .map((v) {
            var owner = v[1] as String;
            var qualifier = v[2] as List?;
            var parameters = v[3] as ASTFunctionParametersDeclaration;
            var body = v[4] as ASTBlock;

            var returnType = _inferReturnType(body);

            if (qualifier != null) {
              var methodName = qualifier[1] as String;
              return _OwnerFunction(
                owner,
                methodName,
                parameters,
                body,
                returnType,
              );
            }

            return ASTFunctionDeclaration(
              owner,
              parameters,
              returnType,
              block: body,
              modifiers: ASTModifiers.modifierStatic,
            );
          });

  /// An anonymous function used as an expression (a closure):
  /// `function(params) ... end`. Captures the enclosing scope.
  Parser<ASTExpression> expressionAnonymousFunction() =>
      (functionToken().trimHidden() &
              functionParametersDeclaration() &
              ref0(block) &
              endToken().trimHidden())
          .map((v) {
            var parameters = v[1] as ASTFunctionParametersDeclaration;
            var body = v[2] as ASTBlock;
            var f = ASTFunctionDeclaration(
              '',
              parameters,
              _inferReturnType(body),
              block: body,
              modifiers: ASTModifiers.modifierStatic,
            );
            return ASTExpressionLiteralFunction(f);
          });

  Parser<ASTFunctionDeclaration> localFunctionDeclaration() =>
      (localToken().trimHidden() &
              functionToken().trimHidden() &
              identifier() &
              functionParametersDeclaration() &
              ref0(block) &
              endToken().trimHidden())
          .map((v) {
            var name = v[2] as String;
            var parameters = v[3] as ASTFunctionParametersDeclaration;
            var body = v[4] as ASTBlock;
            return ASTFunctionDeclaration(
              name,
              parameters,
              _inferReturnType(body),
              block: body,
              modifiers: ASTModifiers.modifierStatic,
            );
          });

  /// Lua is untyped, so the return type is inferred: `dynamic` when the body
  /// can return a value, otherwise `void`. Keeps translations to typed
  /// languages (e.g. Kotlin) executable.
  static ASTType _inferReturnType(ASTNode node) =>
      _hasValueReturn(node) ? ASTTypeDynamic.instance : ASTTypeVoid.instance;

  static bool _hasValueReturn(ASTNode node) {
    if (node is ASTStatementReturnValue ||
        node is ASTStatementReturnVariable ||
        node is ASTStatementReturnWithExpression) {
      return true;
    }
    for (var child in node.children) {
      if (_hasValueReturn(child)) return true;
    }
    return false;
  }

  Parser<ASTFunctionParametersDeclaration> functionParametersDeclaration() =>
      (char('(').trimHidden() &
              parametersList().optional() &
              char(')').trimHidden())
          .map((v) {
            var params = v[1] as List<ASTFunctionParameterDeclaration>?;
            if (params == null || params.isEmpty) {
              return ASTFunctionParametersDeclaration(null, null, null);
            }
            return ASTFunctionParametersDeclaration(params, null, null);
          });

  Parser<List<ASTFunctionParameterDeclaration>> parametersList() =>
      (identifier().trimHidden() &
              (char(',').trimHidden() & identifier().trimHidden()).star())
          .map((v) {
            var names = <String>[v[0] as String];
            for (var tail in (v[1] as List)) {
              names.add(tail[1] as String);
            }
            return [
              for (var i = 0; i < names.length; ++i)
                ASTFunctionParameterDeclaration(
                  ASTTypeDynamic.instance,
                  names[i],
                  i,
                  false,
                ),
            ];
          });

  // -----------------------------------------------------------------
  // Table-based class boilerplate.
  // -----------------------------------------------------------------

  /// `Name.__index = Name` — recognized so it can be grouped (and dropped).
  Parser classIndexAssignment() =>
      (identifier() &
              char('.').trimHidden() &
              string('__index').trimHidden() &
              char('=').trimHidden() &
              identifier())
          .map((v) => _ClassIndex(v[0] as String));

  /// `Name = { ... }` — a class field table when `Name` is a class, otherwise a
  /// normal global table variable.
  Parser namedTableAssignment() =>
      (identifier() &
              (char('=') & char('=').not()).trimHidden() &
              ref0(tableConstructor))
          .map(
            (v) => _NamedTableAssignment(v[0] as String, v[2] as _TableLiteral),
          );

  // -----------------------------------------------------------------
  // Blocks and statements.
  // -----------------------------------------------------------------

  Parser<ASTBlock> block() => ref0(statement).star().map((v) {
    var statements = v.cast<ASTStatement>();
    return ASTBlock(null)..addAllStatements(statements);
  });

  Parser<ASTStatement> statement() =>
      (ref0(branch) |
              ref0(statementWhileLoop) |
              ref0(statementRepeatUntil) |
              ref0(statementForNumeric) |
              ref0(statementForEach) |
              ref0(statementBreak) |
              ref0(statementReturn) |
              ref0(statementVariableDeclaration) |
              ref0(statementExpression))
          .cast<ASTStatement>();

  Parser<ASTStatementBreak> statementBreak() =>
      breakToken().trimHidden().map((_) => ASTStatementBreak());

  /// Lua `repeat <block> until <cond>` — a do-while that loops while the
  /// condition is false, i.e. `do { } while (not cond)`.
  Parser<ASTStatementDoWhileLoop> statementRepeatUntil() =>
      (repeatToken().trimHidden() &
              ref0(block) &
              untilToken().trimHidden() &
              ref0(expression))
          .map((v) {
            var loopBlock = v[1] as ASTBlock;
            var untilCond = v[3] as ASTExpression;
            return ASTStatementDoWhileLoop(
              loopBlock,
              ASTExpressionNegation(untilCond),
            );
          });

  Parser<ASTStatementVariableDeclaration> statementVariableDeclaration() =>
      (localToken().trimHidden() &
              identifier().trimHidden() &
              ((char('=') & char('=').not()).trimHidden() & ref0(expression))
                  .optional())
          .map((v) {
            var name = v[1] as String;
            var valueOpt = v[2];
            var value = valueOpt != null ? valueOpt[1] as ASTExpression : null;
            var type = ASTTypeVar();
            if (value != null) type.associateToType(value);
            return ASTStatementVariableDeclaration(
              type,
              name,
              value,
              unmodifiable: false,
            );
          });

  Parser<ASTStatementExpression> statementExpression() =>
      ref0(expression).map((v) => ASTStatementExpression(v));

  Parser<ASTStatementReturn> statementReturn() =>
      (returnToken().trimHidden() & ref0(expression).optional()).map((v) {
        var value = v[1];

        if (value == null) {
          return ASTStatementReturn();
        } else if (value is ASTExpression) {
          if (value is ASTExpressionVariableAccess) {
            return ASTStatementReturnVariable(value.variable);
          } else if (value is ASTExpressionLiteral) {
            return ASTStatementReturnValue(value.value);
          } else {
            return ASTStatementReturnWithExpression(value);
          }
        }

        throw UnsupportedError("Can't handle return value: $value");
      });

  // -----------------------------------------------------------------
  // Control flow.
  // -----------------------------------------------------------------

  Parser<ASTBranch> branch() =>
      (ifToken().trimHidden() &
              ref0(expression) &
              thenToken().trimHidden() &
              ref0(block) &
              ref0(branchElseIf).star() &
              (elseToken().trimHidden() & ref0(block)).optional() &
              endToken().trimHidden())
          .map((v) {
            var condition = v[1] as ASTExpression;
            var ifBlock = v[3] as ASTBlock;
            var elseIfs = (v[4] as List).cast<ASTBranchIfBlock>();
            var elseOpt = v[5];
            var elseBlock = elseOpt != null ? elseOpt[1] as ASTBlock : null;

            if (elseIfs.isNotEmpty) {
              return ASTBranchIfElseIfsElseBlock(
                condition,
                ifBlock,
                elseIfs,
                elseBlock,
              );
            } else if (elseBlock != null) {
              return ASTBranchIfElseBlock(condition, ifBlock, elseBlock);
            } else {
              return ASTBranchIfBlock(condition, ifBlock);
            }
          });

  Parser<ASTBranchIfBlock> branchElseIf() =>
      (elseifToken().trimHidden() &
              ref0(expression) &
              thenToken().trimHidden() &
              ref0(block))
          .map((v) {
            var condition = v[1] as ASTExpression;
            var ifBlock = v[3] as ASTBlock;
            return ASTBranchIfBlock(condition, ifBlock);
          });

  Parser<ASTStatementWhileLoop> statementWhileLoop() =>
      (whileToken().trimHidden() &
              ref0(expression) &
              doToken().trimHidden() &
              ref0(block) &
              endToken().trimHidden())
          .map((v) {
            var condition = v[1] as ASTExpression;
            var loopBlock = v[3] as ASTBlock;
            return ASTStatementWhileLoop(condition, loopBlock);
          });

  /// Generic-for: `for [k,] v in ipairs(expr)|pairs(expr)|expr do ... end`.
  /// The iterated variable is the last name (the value when using `ipairs`).
  Parser<ASTStatementForEach> statementForEach() =>
      (forToken().trimHidden() &
              ref0(forNameList) &
              inToken().trimHidden() &
              ref0(forIterable) &
              doToken().trimHidden() &
              ref0(block) &
              endToken().trimHidden())
          .map((v) {
            var names = v[1] as List<String>;
            var iterable = v[3] as ASTExpression;
            var loopBlock = v[5] as ASTBlock;
            return ASTStatementForEach(
              ASTTypeVar(),
              names.last,
              iterable,
              loopBlock,
            );
          });

  Parser<List<String>> forNameList() =>
      (identifier().trimHidden() &
              (char(',').trimHidden() & identifier().trimHidden()).star())
          .map((v) {
            var names = <String>[v[0] as String];
            for (var tail in (v[1] as List)) {
              names.add(tail[1] as String);
            }
            return names;
          });

  Parser<ASTExpression> forIterable() =>
      (((string('ipairs') | string('pairs')).trimHidden() &
                      char('(').trimHidden() &
                      ref0(expression) &
                      char(')').trimHidden())
                  .map((v) => v[2] as ASTExpression) |
              ref0(expression))
          .cast<ASTExpression>();

  /// Numeric-for: `for i = a, b[, step] do ... end`, desugared to a C-style
  /// [ASTStatementForLoop].
  Parser<ASTStatementForLoop> statementForNumeric() =>
      (forToken().trimHidden() &
              identifier().trimHidden() &
              (char('=') & char('=').not()).trimHidden() &
              ref0(expression) &
              char(',').trimHidden() &
              ref0(expression) &
              (char(',').trimHidden() & ref0(expression)).optional() &
              doToken().trimHidden() &
              ref0(block) &
              endToken().trimHidden())
          .map((v) {
            var name = v[1] as String;
            var start = v[3] as ASTExpression;
            var stop = v[5] as ASTExpression;
            var stepOpt = v[6];
            ASTExpression step = stepOpt != null
                ? stepOpt[1] as ASTExpression
                : ASTExpressionLiteral(ASTValueInt(1));
            var loopBlock = v[8] as ASTBlock;

            var initType = ASTTypeVar();
            initType.associateToType(start);
            var init = ASTStatementVariableDeclaration(
              initType,
              name,
              start,
              unmodifiable: false,
            );

            var condition = ASTExpressionOperation(
              ASTExpressionVariableAccess(ASTScopeVariable(name)),
              ASTExpressionOperator.lowerOrEq,
              stop,
            );

            var continueExpression = ASTExpressionVariableAssignment(
              ASTScopeVariable(name),
              getASTAssignmentOperator('='),
              ASTExpressionOperation(
                ASTExpressionVariableAccess(ASTScopeVariable(name)),
                ASTExpressionOperator.add,
                step,
              ),
            );

            return ASTStatementForLoop(
              init,
              condition,
              continueExpression,
              loopBlock,
            );
          });

  // -----------------------------------------------------------------
  // Expressions.
  // -----------------------------------------------------------------

  @override
  Parser<ASTExpression> expression() =>
      (ref0(expressionNoOperation) &
              (ref0(expressionOperator) & ref0(expressionNoOperation)).star())
          .map((v) {
            var exp1 = v[0];
            var rest = v[1] as List;
            if (rest.isEmpty) return exp1;

            var all = <dynamic>[exp1];
            for (var pair in rest) {
              all.add(pair[0]);
              all.add(pair[1]);
            }
            return computeFinalExpression(all);
          });

  Parser<ASTExpressionOperator> expressionOperator() =>
      (string('..').map((_) => ASTExpressionOperator.add) |
              string('==').map((_) => ASTExpressionOperator.equals) |
              // `~=` (not-equals) MUST be matched before the single-char `~`
              // (bitwise xor) so the binary `~` never swallows the `=`.
              string('~=').map((_) => ASTExpressionOperator.notEquals) |
              // `<<`/`>>` (shifts) MUST be matched before single `<`/`>`.
              string('<<').map((_) => ASTExpressionOperator.shiftLeft) |
              string('>>').map((_) => ASTExpressionOperator.shiftRight) |
              string('<=').map((_) => ASTExpressionOperator.lowerOrEq) |
              string('>=').map((_) => ASTExpressionOperator.greaterOrEq) |
              andToken().map((_) => ASTExpressionOperator.and) |
              orToken().map((_) => ASTExpressionOperator.or) |
              char('+').map((_) => ASTExpressionOperator.add) |
              char('-').map((_) => ASTExpressionOperator.subtract) |
              char('*').map((_) => ASTExpressionOperator.multiply) |
              char('/').map((_) => ASTExpressionOperator.divide) |
              char('%').map((_) => ASTExpressionOperator.remainder) |
              char('&').map((_) => ASTExpressionOperator.bitwiseAnd) |
              char('|').map((_) => ASTExpressionOperator.bitwiseOr) |
              // In Lua, binary `~` is bitwise XOR (not `^`, which is exponent).
              char('~').map((_) => ASTExpressionOperator.bitwiseXor) |
              char('<').map((_) => ASTExpressionOperator.lower) |
              char('>').map((_) => ASTExpressionOperator.greater))
          .trimHidden()
          .cast<ASTExpressionOperator>();

  Parser<ASTExpression> expressionNoOperation() =>
      (ref0(expressionAnonymousFunction) |
              ref0(expressionNegate) |
              ref0(expressionBitwiseNot) |
              ref0(expressionLiteral) |
              ref0(expressionGroup) |
              ref0(expressionTableLiteral) |
              ref0(selfMethodInvocation) |
              ref0(selfFieldAccess) |
              ref0(expressionVariableAssignment) |
              ref0(expressionObjectFunctionInvocation) |
              ref0(expressionFunctionInvocation) |
              ref0(expressionObjectGetterAccess) |
              ref0(expressionNilValue) |
              ref0(expressionVariableAccess) |
              ref0(expressionNegative))
          .cast<ASTExpression>();

  Parser<ASTExpressionNegation> expressionNegate() =>
      (notToken().trimHidden() & ref0(expressionNoOperation)).map((v) {
        return ASTExpressionNegation(v[1] as ASTExpression);
      });

  Parser<ASTExpressionNegative> expressionNegative() =>
      (char('-').trimHidden() &
              (ref0(expressionNoOperation) | ref0(expressionGroup)))
          .map((v) {
            return ASTExpressionNegative(v[1] as ASTExpression);
          });

  /// Unary prefix `~expr` — Lua's bitwise NOT. Prefix position only, so it
  /// never conflicts with binary `~` (xor) or `~=` (not-equals).
  Parser<ASTExpressionBitwiseNot> expressionBitwiseNot() =>
      (char('~').trimHidden() &
              (ref0(expressionNoOperation) | ref0(expressionGroup)))
          .map((v) {
            return ASTExpressionBitwiseNot(v[1] as ASTExpression);
          });

  Parser<ASTExpression> expressionGroup() =>
      (char('(').trimHidden() & ref0(expression) & char(')').trimHidden()).map(
        (v) => v[1] as ASTExpression,
      );

  Parser<ASTExpressionLiteral> expressionLiteral() =>
      ref0(literal).map((v) => ASTExpressionLiteral(v));

  Parser<ASTExpressionNullValue> expressionNilValue() =>
      nilToken().map((_) => ASTExpressionNullValue());

  Parser<ASTExpressionVariableAccess> expressionVariableAccess() =>
      ref0(variable).map((v) => ASTExpressionVariableAccess(v));

  Parser<ASTExpressionVariableAssignment> expressionVariableAssignment() =>
      (ref0(variable) &
              (char('=') & char('=').not()).trimHidden() &
              ref0(expression))
          .map((v) {
            return ASTExpressionVariableAssignment(
              v[0] as ASTVariable,
              getASTAssignmentOperator('='),
              v[2] as ASTExpression,
            );
          });

  /// `self:method(args)` / `self.method(args)` — resolved as a call on the
  /// current object (a local-function invocation, like a bare sibling call).
  Parser<ASTExpressionLocalFunctionInvocation> selfMethodInvocation() =>
      (selfToken() &
              (char(':') | char('.')).trimHidden() &
              identifier() &
              char('(').trimHidden() &
              ref0(expressionSequence).optional() &
              char(')').trimHidden())
          .map((v) {
            var name = normalizeFunctionName(v[2] as String);
            var args = (v[4] as List<ASTExpression>?) ?? <ASTExpression>[];
            return ASTExpressionLocalFunctionInvocation(name, args, []);
          });

  /// `self.field` — resolved as access to a field of the current object.
  Parser<ASTExpressionVariableAccess> selfFieldAccess() =>
      (selfToken() & char('.').trimHidden() & identifier()).map((v) {
        return ASTExpressionVariableAccess(ASTScopeVariable(v[2] as String));
      });

  Parser selfToken() =>
      (string('self') & ref0(identifierPartLexicalToken).not())
          .pick(0)
          .trim(ref0(hiddenStuffWhitespace));

  /// `obj:method(args)` — invocation on another object/variable.
  Parser<ASTExpressionObjectFunctionInvocation>
  expressionObjectFunctionInvocation() =>
      (identifier() &
              char(':').trimHidden() &
              identifier() &
              char('(').trimHidden() &
              ref0(expressionSequence).optional() &
              char(')').trimHidden())
          .map((v) {
            var obj = v[0] as String;
            var name = normalizeFunctionName(v[2] as String);
            var args = (v[4] as List<ASTExpression>?) ?? <ASTExpression>[];
            return ASTExpressionObjectFunctionInvocation(
              ASTScopeVariable(obj),
              name,
              args,
              [],
            );
          });

  /// `name(args)` — local/global function call.
  Parser<ASTExpressionLocalFunctionInvocation> expressionFunctionInvocation() =>
      (identifier() &
              char('(').trimHidden() &
              ref0(expressionSequence).optional() &
              char(')').trimHidden())
          .map((v) {
            var name = normalizeFunctionName(v[0] as String);
            var args = (v[2] as List<ASTExpression>?) ?? <ASTExpression>[];
            return ASTExpressionLocalFunctionInvocation(name, args, []);
          });

  /// `obj.field` — getter access on another object/variable.
  Parser<ASTExpressionObjectGetterAccess> expressionObjectGetterAccess() =>
      (identifier() & char('.').trimHidden() & identifier()).map((v) {
        var obj = v[0] as String;
        var name = v[2] as String;
        return ASTExpressionObjectGetterAccess(ASTScopeVariable(obj), name, []);
      });

  Parser<List<ASTExpression>> expressionSequence() =>
      (ref0(expression) & (char(',').trimHidden() & ref0(expression)).star())
          .map((v) {
            var list = <ASTExpression>[v[0] as ASTExpression];
            for (var tail in (v[1] as List)) {
              list.add(tail[1] as ASTExpression);
            }
            return list;
          });

  Parser<ASTVariable> variable() =>
      ref0(identifier).map((v) => ASTScopeVariable(v));

  // -----------------------------------------------------------------
  // Tables.
  // -----------------------------------------------------------------

  Parser<ASTExpression> expressionTableLiteral() =>
      ref0(tableConstructor).map((t) => t.toExpression());

  Parser tableConstructor() =>
      (char('{').trimHidden() &
              ref0(tableEntries).optional() &
              char('}').trimHidden())
          .map((v) {
            var entries = (v[1] as List<_TableEntry>?) ?? <_TableEntry>[];
            return _TableLiteral(entries);
          });

  Parser tableEntries() =>
      (ref0(tableEntry) &
              (ref0(tableSeparator) & ref0(tableEntry)).star() &
              ref0(tableSeparator).optional())
          .map((v) {
            var entries = <_TableEntry>[v[0] as _TableEntry];
            for (var tail in (v[1] as List)) {
              entries.add(tail[1] as _TableEntry);
            }
            return entries;
          });

  Parser tableSeparator() => (char(',') | char(';')).trimHidden();

  Parser tableEntry() =>
      (ref0(tableEntryBracketKey) |
              ref0(tableEntryNameKey) |
              ref0(tableEntryPositional))
          .cast<_TableEntry>();

  Parser tableEntryBracketKey() =>
      (char('[').trimHidden() &
              ref0(expression) &
              char(']').trimHidden() &
              (char('=') & char('=').not()).trimHidden() &
              ref0(expression))
          .map((v) {
            return _TableEntry(
              keyExpr: v[1] as ASTExpression,
              value: v[4] as ASTExpression,
            );
          });

  Parser tableEntryNameKey() =>
      (identifier().trimHidden() &
              (char('=') & char('=').not()).trimHidden() &
              ref0(expression))
          .map((v) {
            return _TableEntry(
              keyName: v[0] as String,
              value: v[2] as ASTExpression,
            );
          });

  Parser tableEntryPositional() =>
      ref0(expression).map((v) => _TableEntry(value: v));

  // -----------------------------------------------------------------
  // Literals.
  // -----------------------------------------------------------------

  Parser<ASTValue> literal() =>
      (ref0(literalBool) | ref0(literalNum) | ref0(literalString))
          .trimHidden()
          .cast<ASTValue>();

  Parser<ASTValueBool> literalBool() => (trueToken() | falseToken()).map((v) {
    return ASTValueBool('$v'.trim() == 'true');
  });

  Parser<ASTValueNum> literalNum() =>
      (char('-').optional() & numberLexicalToken()).trim().map((v) {
        var negative = v[0] == '-';
        var value = v[1];
        return ASTValueNum.from(value, negative: negative);
      });

  Parser<ASTValue<String>> literalString() =>
      ref0(stringLexicalToken).map((v) => v.asValue());
}

// -----------------------------------------------------------------
// Intermediate parse results used while assembling [ASTRoot].
// -----------------------------------------------------------------

/// A `function Owner:method(...)` / `function Owner.method(...)` definition,
/// grouped into an [ASTClassNormal] by [compilationUnit].
class _OwnerFunction {
  final String owner;
  final String name;
  final ASTFunctionParametersDeclaration parameters;
  final ASTBlock body;
  final ASTType returnType;

  _OwnerFunction(
    this.owner,
    this.name,
    this.parameters,
    this.body,
    this.returnType,
  );

  ASTClassFunctionDeclaration toMethod() => ASTClassFunctionDeclaration(
    null,
    name,
    parameters,
    returnType,
    block: body,
  );
}

/// A `Name.__index = Name` marker (Lua class boilerplate).
class _ClassIndex {
  final String name;

  _ClassIndex(this.name);
}

/// A `Name = { ... }` assignment, interpreted as class fields or a variable.
class _NamedTableAssignment {
  final String name;
  final _TableLiteral table;

  _NamedTableAssignment(this.name, this.table);

  List<ASTClassField> toFields() {
    var fields = <ASTClassField>[];
    for (var e in table.entries) {
      var fieldName = e.keyName;
      if (fieldName == null) continue;
      if (e.value is ASTExpressionNullValue) {
        fields.add(ASTClassField(ASTTypeDynamic.instance, fieldName, false));
      } else {
        var type = ASTTypeDynamic.instance;
        fields.add(
          ASTClassFieldWithInitialValue(type, fieldName, e.value, false),
        );
      }
    }
    return fields;
  }

  ASTStatementVariableDeclaration toVariableDeclaration() {
    var value = table.toExpression();
    var type = ASTTypeVar();
    type.associateToType(value);
    return ASTStatementVariableDeclaration(
      type,
      name,
      value,
      unmodifiable: false,
    );
  }
}

/// A single entry of a Lua table constructor.
class _TableEntry {
  final String? keyName;
  final ASTExpression? keyExpr;
  final ASTExpression value;

  _TableEntry({this.keyName, this.keyExpr, required this.value});

  bool get isPositional => keyName == null && keyExpr == null;
}

/// A parsed Lua table constructor (`{ ... }`).
class _TableLiteral {
  final List<_TableEntry> entries;

  _TableLiteral(this.entries);

  /// Converts to a list literal (all positional) or a map literal (any keyed).
  ASTExpression toExpression() {
    var anyKeyed = entries.any((e) => !e.isPositional);

    if (!anyKeyed) {
      var values = entries.map((e) => e.value).toList();
      ASTType type = ASTTypeDynamic.instance;
      var resolved = values.map((e) => e.resolveType(null)).toList();
      var types = resolved.whereType<ASTType>().toList();
      if (types.isNotEmpty && types.length == resolved.length) {
        type = types.reduce(
          (a, b) => a.commonType(b) ?? ASTTypeDynamic.instance,
        );
      }
      return ASTExpressionListLiteral(type, values);
    }

    var mapEntries = <MapEntry<ASTExpression, ASTExpression>>[];
    for (var e in entries) {
      ASTExpression key;
      if (e.keyExpr != null) {
        key = e.keyExpr!;
      } else if (e.keyName != null) {
        key = ASTExpressionLiteral(ASTValueString(e.keyName!));
      } else {
        continue;
      }
      mapEntries.add(MapEntry(key, e.value));
    }
    return ASTExpressionMapLiteral(
      ASTTypeDynamic.instance,
      ASTTypeDynamic.instance,
      mapEntries,
    );
  }
}
