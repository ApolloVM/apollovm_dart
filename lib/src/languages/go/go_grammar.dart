// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:petitparser/petitparser.dart';

import '../../apollovm_base.dart' show VMObject;
import '../../ast/apollovm_ast_base.dart';
import '../../ast/apollovm_ast_expression.dart';
import '../../ast/apollovm_ast_statement.dart';
import '../../ast/apollovm_ast_toplevel.dart';
import '../../ast/apollovm_ast_type.dart';
import '../../ast/apollovm_ast_value.dart';
import '../../ast/apollovm_ast_variable.dart';
import 'go_grammar_lexer.dart';

/// Go grammar definition.
///
/// Go has no classes: a class is modeled by grouping a `type Name struct { ...
/// }` declaration together with its receiver methods (`func (o *Name) m(...)`)
/// and factory constructors (`func NewName(...) *Name`) — the same owner-based
/// grouping the Lua grammar uses for its table-based classes.
class GoGrammarDefinition extends GoGrammarLexer {
  /// Maps Go's standard output functions to the VM's canonical `print`,
  /// so the same AST runs and translates consistently across languages.
  static String normalizeFunctionName(String name) {
    switch (name) {
      case 'println':
      case 'print':
        return 'print';
      default:
        return name;
    }
  }

  static ASTType getTypeByName(String name) {
    switch (name) {
      case 'any':
        return ASTTypeObject.instance;
      case 'bool':
        return ASTTypeBool.instance;
      case 'int':
      case 'int8':
      case 'int16':
      case 'int32':
      case 'int64':
      case 'uint':
      case 'uint8':
      case 'uint16':
      case 'uint32':
      case 'uint64':
      case 'byte':
      case 'rune':
      case 'uintptr':
        return ASTTypeInt.instance;
      case 'float32':
      case 'float64':
        return ASTTypeDouble.instance;
      case 'string':
        return ASTTypeString.instance;
      default:
        return ASTType(name);
    }
  }

  /// The receiver name of the method/constructor currently being parsed (e.g.
  /// `o` in `func (o *Foo) m()`). Inside that scope `o` (and `this`) denote the
  /// current instance. Set before the body is parsed (like Kotlin's
  /// `_classTypeParameters`), cleared afterwards.
  String? _currentReceiver;

  /// Struct names declared so far in the compilation unit. Go's own generated
  /// code always declares a struct before its factory and before any use, so
  /// tracking them as they are parsed is enough to recognize `&Name{}` and to
  /// map a `NewName(...)` call onto the struct's constructor.
  final Set<String> _structNames = <String>{};

  /// The local name the Go generator gives the instance under construction in a
  /// factory: `o := &Foo{}`.
  static const String _constructorReceiverName = 'o';

  @override
  Parser start() => ref0(compilationUnit).trim().end();

  Parser<ASTRoot> compilationUnit() =>
      (ref0(packageClause).optional() &
              ref0(importDecl).star() &
              ref0(topLevelItem).star())
          .map((v) {
            var items = _expandListDeeply(v[2] as List);

            var root = ASTRoot();

            // Collect declared struct names first.
            var structOrder = <String>[];
            var structFields = <String, List<ASTClassField>>{};
            var structMethods = <String, List<ASTClassFunctionDeclaration>>{};
            var structConstructors =
                <String, List<ASTClassConstructorDeclaration>>{};

            void ensureStruct(String name) {
              if (!structFields.containsKey(name)) {
                structOrder.add(name);
                structFields[name] = [];
                structMethods[name] = [];
                structConstructors[name] = [];
              }
            }

            for (var it in items) {
              if (it is _StructDecl) ensureStruct(it.name);
              if (it is _OwnerFunction) ensureStruct(it.owner);
            }

            var structNames = structFields.keys.toSet();

            var topFunctions = <ASTFunctionDeclaration>[];
            var topStatements = <ASTStatement>[];

            for (var it in items) {
              if (it is _StructDecl) {
                ensureStruct(it.name);
                structFields[it.name]!.addAll(it.fields);
              } else if (it is _OwnerFunction) {
                ensureStruct(it.owner);
                structMethods[it.owner]!.add(it.toMethod());
              } else if (it is ASTFunctionDeclaration) {
                // A top-level `func NewX(...) *X` where `X` is a struct is the
                // factory constructor for `X`.
                var ctorOwner = _constructorOwner(it, structNames);
                if (ctorOwner != null) {
                  ensureStruct(ctorOwner);
                  structConstructors[ctorOwner]!.add(
                    _toConstructor(it, ctorOwner),
                  );
                } else {
                  topFunctions.add(it);
                }
              } else if (it is ASTStatementImport) {
                root.addImport(it);
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

            for (var name in structOrder) {
              var clazz = ASTClassNormal(name, ASTType<VMObject>(name), null);
              var block = ASTClassNormal('?', ASTType<VMObject>('?'), null);
              block.addAllFields(structFields[name]!);
              block.addAllConstructors(structConstructors[name]!);
              block.addAllFunctions(structMethods[name]!);
              clazz.set(block);
              root.addClass(clazz);
            }

            root.resolveNode(null);

            return root;
          });

  /// `NewFoo` names the factory constructor of the struct `Foo`; the shared AST
  /// invokes a constructor by its class name, so the call site is rewritten.
  /// Returns `null` when [name] is an ordinary function.
  String? _structConstructorName(String name) {
    if (!name.startsWith('New') || name.length <= 3) return null;
    var owner = name.substring(3);
    return _structNames.contains(owner) ? owner : null;
  }

  /// A top-level function is a constructor when it is named `New<Struct>` and
  /// `<Struct>` is a declared struct.
  static String? _constructorOwner(
    ASTFunctionDeclaration f,
    Set<String> structNames,
  ) {
    var name = f.name;
    if (!name.startsWith('New') || name.length <= 3) return null;
    var owner = name.substring(3);
    return structNames.contains(owner) ? owner : null;
  }

  /// Rebuilds an [ASTClassConstructorDeclaration] from a `func NewX(...) *X`
  /// factory, dropping the synthetic `o := &X{}` / `return o` scaffolding so
  /// the constructor body carries only the user statements.
  static ASTClassConstructorDeclaration _toConstructor(
    ASTFunctionDeclaration f,
    String owner,
  ) {
    var statements = f.statements.toList();
    statements.removeWhere((s) {
      if (s is ASTStatementVariableDeclaration &&
          s.name == _constructorReceiverName) {
        return true;
      }
      // `return o` parses as `return this`, since `o` is bound as the receiver.
      if (s is ASTStatementReturnVariable) {
        var v = s.variable;
        return v is ASTThisVariable || v.name == _constructorReceiverName;
      }
      return false;
    });

    var block = ASTBlock(null)..addAllStatements(statements);

    var params = f.parameters;
    var ctorParams = ASTConstructorParametersDeclaration(
      params.positionalParameters
          ?.map(
            (p) => ASTConstructorParameterDeclaration(
              p.type,
              p.name,
              p.index,
              false,
            ),
          )
          .toList(),
      null,
      null,
    );

    return ASTClassConstructorDeclaration(
      ASTType<VMObject>(owner),
      '',
      ctorParams,
      block: block,
    );
  }

  Parser packageClause() =>
      (packageToken().trimHidden() & identifier().trimHidden()).map(
        (v) => null,
      );

  Parser<ASTStatementImport?> importDecl() =>
      (importToken().trimHidden() &
              (ref0(importBlock) | ref0(importSpec)).trimHidden())
          .map((v) {
            // A single quoted path may map to an import; blocks and `fmt` are
            // dropped (fmt is an implementation detail of `print`).
            var spec = v[1];
            if (spec is String) {
              if (spec == 'fmt' || spec.isEmpty) return null;
              return ASTStatementImport(spec);
            }
            return null;
          });

  Parser importBlock() =>
      (char('(').trimHidden() &
              ref0(importSpec).trimHidden().star() &
              char(')').trimHidden())
          .map((v) => null);

  Parser<String> importSpec() => (ref0(goStringLiteral)).map((v) => v);

  Parser<String> goStringLiteral() => (stringLexicalToken()).map((v) {
    var value = v.asValue();
    return value is ASTValueString ? value.value : '';
  });

  Parser topLevelItem() =>
      (ref0(structDeclaration) |
              ref0(methodDeclaration) |
              ref0(functionDeclaration) |
              ref0(statementVariableDeclaration))
          .cast();

  // -----------------------------------------------------------------
  // Structs.
  // -----------------------------------------------------------------

  Parser structDeclaration() =>
      (typeToken().trimHidden() &
              identifier().trimHidden() &
              structToken().trimHidden() &
              char('{').trimHidden() &
              ref0(structField).star() &
              char('}').trimHidden())
          .map((v) {
            var name = v[1] as String;
            var fields = (v[4] as List).cast<ASTClassField>().toList();
            _structNames.add(name);
            return _StructDecl(name, fields);
          });

  Parser<ASTClassField> structField() =>
      (identifier().trimHidden() & type() & char(';').trimHidden().optional())
          .map((v) {
            var name = v[0] as String;
            var type = v[1] as ASTType;
            return ASTClassField(type, name, false);
          });

  // -----------------------------------------------------------------
  // Functions and methods.
  // -----------------------------------------------------------------

  /// `func (o *Name) method(params) ret { body }` — a struct method.
  Parser methodDeclaration() =>
      (funcToken().trimHidden() &
              ref0(methodReceiver) &
              identifier() &
              functionParametersDeclaration() &
              type().optional() &
              codeBlock())
          .map((v) {
            var owner = v[1] as String;
            var name = v[2] as String;
            var parameters = v[3] as ASTFunctionParametersDeclaration;
            var returnType = (v[4] as ASTType?) ?? ASTTypeVoid.instance;
            var block = v[5] as ASTBlock;
            _currentReceiver = null;
            return _OwnerFunction(owner, name, parameters, block, returnType);
          });

  /// `(o *Name)` / `(o Name)` — sets [_currentReceiver] before the body parses,
  /// returns the struct name (the owner).
  Parser<String> methodReceiver() =>
      (char('(').trimHidden() &
              identifier().trimHidden() &
              char('*').trimHidden().optional() &
              identifier().trimHidden() &
              char(')').trimHidden())
          .map((v) {
            var receiverName = v[1] as String;
            var structName = v[3] as String;
            _currentReceiver = receiverName;
            return structName;
          });

  /// `func name(params) ret { body }` — a top-level function.
  Parser<ASTFunctionDeclaration> functionDeclaration() =>
      (funcToken().trimHidden() &
              identifier().map((name) {
                // Inside a `func NewFoo(...) *Foo` factory the local `o` of the
                // `o := &Foo{}` scaffolding *is* the instance under
                // construction, so bind it as the receiver before the body
                // parses. `_toConstructor` strips the scaffolding afterwards.
                _currentReceiver = _structConstructorName(name) != null
                    ? _constructorReceiverName
                    : null;
                return name;
              }) &
              functionParametersDeclaration() &
              type().optional() &
              codeBlock())
          .map((v) {
            var name = v[1] as String;
            var parameters = v[2] as ASTFunctionParametersDeclaration;
            var returnType = (v[3] as ASTType?) ?? ASTTypeVoid.instance;
            var block = v[4] as ASTBlock;
            _currentReceiver = null;
            return ASTFunctionDeclaration(
              name,
              parameters,
              returnType,
              block: block,
              modifiers: ASTModifiers.modifierStatic,
            );
          });

  Parser<ASTFunctionParametersDeclaration> functionParametersDeclaration() =>
      (char('(').trimHidden() &
              parametersList().optional() &
              char(')').trimHidden())
          .map((v) {
            var params = v[1] as List<ASTFunctionParameterDeclaration>?;
            return ASTFunctionParametersDeclaration(params, null, null);
          });

  Parser<List<ASTFunctionParameterDeclaration>> parametersList() =>
      (parameterDeclaration() &
              (char(',').trimHidden() & parameterDeclaration()).star() &
              char(',').trimHidden().optional())
          .map((v) {
            var params = _expandListDeeply(v);
            return params.whereType<ASTFunctionParameterDeclaration>().toList();
          });

  /// A Go parameter has the type *after* the name: `a int`.
  Parser<ASTFunctionParameterDeclaration> parameterDeclaration() =>
      (identifier().trimHidden() & type()).map((v) {
        return ASTFunctionParameterDeclaration(
          v[1] as ASTType,
          v[0] as String,
          -1,
          false,
        );
      });

  /// Go always requires braces: the spec defines `Block = "{" StatementList "}"`
  /// and every control-flow statement takes a `Block`, never a single statement.
  /// So — unlike the other C-style grammars — there is deliberately no
  /// `codeBlockOrSingleLineBlock` here.
  Parser<ASTBlock> codeBlock() =>
      (char('{').trimHidden() & ref0(statement).star() & char('}').trimHidden())
          .map((v) {
            var statements = (v[1] as List).cast<ASTStatement>().toList();
            return ASTBlock(null)..addAllStatements(statements);
          });

  // -----------------------------------------------------------------
  // Statements.
  // -----------------------------------------------------------------

  Parser<ASTStatement> statement() =>
      (statementSwitch() |
              branch() |
              statementBreak() |
              statementContinue() |
              statementForRange() |
              statementForClause() |
              statementWhileLoop() |
              statementInfiniteLoop() |
              statementReturn() |
              statementVariableDeclaration() |
              statementExpression())
          .cast<ASTStatement>();

  Parser<ASTStatement> statementSimple() =>
      (statementVariableDeclaration() | statementExpression())
          .cast<ASTStatement>();

  Parser<ASTStatementBreak> statementBreak() =>
      (breakToken() & char(';').trimHidden().optional()).map(
        (v) => ASTStatementBreak(),
      );

  Parser<ASTStatementContinue> statementContinue() =>
      (continueToken() & char(';').trimHidden().optional()).map(
        (v) => ASTStatementContinue(),
      );

  /// C-style `for init; cond; post { body }`. The `init` [statementSimple]
  /// consumes its own trailing `;` (like the Java grammar), so only the
  /// separator between `cond` and `post` is matched explicitly.
  Parser<ASTStatementForLoop> statementForClause() =>
      (forToken().trimHidden() &
              ref0(statementSimple) &
              ref0(expression) &
              char(';').trimHidden() &
              ref0(expression) &
              codeBlock())
          .map((v) {
            var init = v[1] as ASTStatement;
            var cond = v[2] as ASTExpression;
            var post = v[4] as ASTExpression;
            var block = v[5] as ASTBlock;
            return ASTStatementForLoop(init, cond, post, block);
          });

  /// `for _, x := range xs { body }` / `for x := range xs { body }`.
  Parser<ASTStatementForEach> statementForRange() =>
      (forToken().trimHidden() &
              ((identifier().trimHidden() & char(',').trimHidden()).optional() &
                  identifier().trimHidden()) &
              string(':=').trimHidden() &
              rangeToken().trimHidden() &
              ref0(expression) &
              codeBlock())
          .map((v) {
            var names = v[1] as List;
            var valueName = names[1] as String;
            var iterableExp = v[4] as ASTExpression;
            var block = v[5] as ASTBlock;
            return ASTStatementForEach(
              ASTTypeVar(),
              valueName,
              iterableExp,
              block,
            );
          });

  /// `for cond { body }` — Go's `while`.
  Parser<ASTStatementWhileLoop> statementWhileLoop() =>
      (forToken().trimHidden() & ref0(expression) & codeBlock()).map((v) {
        var cond = v[1] as ASTExpression;
        var block = v[2] as ASTBlock;
        return ASTStatementWhileLoop(cond, block);
      });

  /// `for { body }` — infinite loop, plus the `do { } while` desugaring
  /// `for { body; if !cond { break } }`.
  Parser<ASTStatement> statementInfiniteLoop() =>
      (forToken().trimHidden() & codeBlock()).map((v) {
        var block = v[1] as ASTBlock;

        // Detect the generated do-while shape: a trailing
        // `if !cond { break }` whose only statement is a break.
        var statements = block.statements.toList();
        if (statements.isNotEmpty) {
          var last = statements.last;
          if (last is ASTBranchIfBlock) {
            var onlyBreak =
                last.block.statements.length == 1 &&
                last.block.statements.first is ASTStatementBreak;
            if (onlyBreak) {
              var cond = last.condition;
              // Unwrap the negation: `if !cond break` ⇒ do-while(cond).
              if (cond is ASTExpressionNegation) {
                statements.removeLast();
                var body = ASTBlock(null)..addAllStatements(statements);
                return ASTStatementDoWhileLoop(body, cond.expression);
              }
            }
          }
        }

        return ASTStatementWhileLoop(
          ASTExpressionLiteral(ASTValueBool(true)),
          block,
        );
      });

  /// `switch expr { case v: ...; default: ... }` (Go auto-breaks; no
  /// fall-through).
  Parser<ASTStatementSwitch> statementSwitch() =>
      (switchToken().trimHidden() &
              ref0(expression) &
              char('{').trimHidden() &
              switchCase().star() &
              switchDefault().optional() &
              char('}').trimHidden())
          .map((v) {
            var exp = v[1] as ASTExpression;
            var cases = (v[3] as List).cast<ASTSwitchCase>().toList();
            var defaultCase = v[4] as ASTSwitchCase?;
            if (defaultCase != null) cases.add(defaultCase);
            return ASTStatementSwitch(exp, cases, fallThrough: false);
          });

  Parser<ASTSwitchCase> switchCase() =>
      (caseToken().trimHidden() &
              ref0(expression) &
              char(':').trimHidden() &
              ref0(statement).star())
          .map((v) {
            var value = v[1] as ASTExpression;
            var statements = (v[3] as List).cast<ASTStatement>().toList();
            var block = ASTBlock(null)..addAllStatements(statements);
            return ASTSwitchCase(value, block);
          });

  Parser<ASTSwitchCase> switchDefault() =>
      (defaultToken().trimHidden() &
              char(':').trimHidden() &
              ref0(statement).star())
          .map((v) {
            var statements = (v[2] as List).cast<ASTStatement>().toList();
            var block = ASTBlock(null)..addAllStatements(statements);
            return ASTSwitchCase(null, block);
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
                if (value.variable.name == 'nil') {
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

  /// Go variable declarations:
  /// `x := expr` (short), `var x Type = expr`, `var x Type`, `var x = expr`.
  Parser<ASTStatementVariableDeclaration> statementVariableDeclaration() =>
      (statementVarShort() | statementVarKeyword())
          .cast<ASTStatementVariableDeclaration>();

  Parser<ASTStatementVariableDeclaration> statementVarShort() =>
      (identifier().trimHidden() &
              string(':=').trimHidden() &
              ref0(expression) &
              char(';').trimHidden().optional())
          .map((v) {
            var name = v[0] as String;
            var value = v[2] as ASTExpression;
            var type = ASTTypeVar();
            type.associateToType(value);
            return ASTStatementVariableDeclaration(type, name, value);
          });

  Parser<ASTStatementVariableDeclaration> statementVarKeyword() =>
      (varToken().trimHidden() &
              identifier().trimHidden() &
              type().optional() &
              (char('=').trimHidden() & ref0(expression)).optional() &
              char(';').trimHidden().optional())
          .map((v) {
            var name = v[1] as String;
            var declaredType = v[2] as ASTType?;
            var valueOpt = v[3];
            var value = valueOpt != null ? valueOpt[1] as ASTExpression : null;

            var type = declaredType ?? ASTTypeVar();
            if (value != null) type.associateToType(value);

            return ASTStatementVariableDeclaration(type, name, value);
          });

  // -----------------------------------------------------------------
  // Branches.
  // -----------------------------------------------------------------

  Parser<ASTBranch> branch() =>
      (ref0(branchIfElseIfsElseBlock) |
              ref0(branchIfElseBlock) |
              ref0(branchIfBlock))
          .cast<ASTBranch>();

  Parser<ASTBranchIfBlock> branchIfBlock() =>
      (ifToken().trimHidden() & ref0(expression) & codeBlock()).map((v) {
        var condition = v[1] as ASTExpression;
        var block = v[2] as ASTBlock;
        return ASTBranchIfBlock(condition, block);
      });

  Parser<ASTBranchIfElseBlock> branchIfElseBlock() =>
      (ifToken().trimHidden() &
              ref0(expression) &
              codeBlock() &
              elseToken().trimHidden() &
              codeBlock())
          .map((v) {
            var condition = v[1] as ASTExpression;
            var blockIf = v[2] as ASTBlock;
            var blockElse = v[4] as ASTBlock;
            return ASTBranchIfElseBlock(condition, blockIf, blockElse);
          });

  Parser<ASTBranchIfElseIfsElseBlock> branchIfElseIfsElseBlock() =>
      (ifToken().trimHidden() &
              ref0(expression) &
              codeBlock() &
              ref0(branchElseIfs).plus() &
              (elseToken().trimHidden() & codeBlock()).optional())
          .map((v) {
            var condition = v[1] as ASTExpression;
            var blockIf = v[2] as ASTBlock;
            var blockElseIfs = v[3] as List;
            var blockElse = v[4]?[1];
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
              ref0(expression) &
              codeBlock())
          .map((v) {
            var condition = v[2] as ASTExpression;
            var blockIf = v[3] as ASTBlock;
            return ASTBranchIfBlock(condition, blockIf);
          });

  // -----------------------------------------------------------------
  // Expressions.
  // -----------------------------------------------------------------

  @override
  Parser<ASTExpression> expression() =>
      (ref0(expressionOperationChain)).cast<ASTExpression>();

  Parser<ASTExpression> expressionOperationChain() =>
      (ref0(expressionNoOperation) &
              (ref0(goAndNotOperand) |
                      (expressionOperator() & ref0(expressionNoOperation)))
                  .star())
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
      (string('&&') |
              string('||') |
              string('<<') |
              string('>>') |
              string('==') |
              string('!=') |
              string('<=') |
              string('>=') |
              char('+') |
              char('-') |
              char('*') |
              char('/') |
              char('%') |
              char('&') |
              char('|') |
              char('^') |
              char('<') |
              char('>'))
          .trimHidden()
          .map((v) => getASTExpressionOperator(v as String));

  /// Go `&^` (bit clear / AND NOT): `a &^ b` == `a & (^b)` == `a & (~b)`. There
  /// is no dedicated binary AST operator, so desugar it to a bitwise-AND whose
  /// right operand is the bitwise complement of `b`. Returned in the same
  /// `[operator, operand]` shape as a normal operator/operand pair so the
  /// operator-precedence reducer treats it exactly like `&`.
  ///
  /// This must be tried before [expressionOperator], whose `&` would otherwise
  /// consume the `&` of `&^` and leave a dangling `^`.
  Parser<List> goAndNotOperand() =>
      (string('&^').trimHidden() & ref0(expressionNoOperation)).map(
        (v) => <dynamic>[
          ASTExpressionOperator.bitwiseAnd,
          ASTExpressionBitwiseNot(v[1] as ASTExpression),
        ],
      );

  Parser<ASTExpression> expressionNoOperation() =>
      (expressionConditionalIIFE() |
              expressionLambda() |
              expressionNegate() |
              expressionBitwiseNot() |
              expressionLiteral() |
              expressionGroupFunctionInvocation() |
              expressionGroup() |
              expressionListLiteral() |
              expressionMapLiteral() |
              expressionVariableDirectOperation() |
              expressionObjectFieldAssignment() |
              expressionVariableAssigment() |
              expressionStructLiteral() |
              expressionFunctionInvocation() |
              expressionObjectEntryFunctionInvocation() |
              expressionVariableEntryAccess() |
              expressionGetterAccess() |
              expressionNullValue() |
              expressionVariableAccess() |
              expressionNegative())
          .cast<ASTExpression>();

  /// The IIFE ApolloVM emits for a conditional expression (Go has no ternary):
  /// `func() any { if cond { return a } else { return b } }()`.
  Parser<ASTExpressionConditional> expressionConditionalIIFE() =>
      (funcToken().trimHidden() &
              char('(').trimHidden() &
              char(')').trimHidden() &
              string('any').trimHidden() &
              char('{').trimHidden() &
              ifToken().trimHidden() &
              ref0(expression) &
              char('{').trimHidden() &
              returnToken().trimHidden() &
              ref0(expression) &
              char('}').trimHidden() &
              elseToken().trimHidden() &
              char('{').trimHidden() &
              returnToken().trimHidden() &
              ref0(expression) &
              char('}').trimHidden() &
              char('}').trimHidden() &
              char('(').trimHidden() &
              char(')').trimHidden())
          .map((v) {
            var cond = v[6] as ASTExpression;
            var valueTrue = v[9] as ASTExpression;
            var valueFalse = v[14] as ASTExpression;
            return ASTExpressionConditional(cond, valueTrue, valueFalse);
          });

  Parser<ASTExpressionNegation> expressionNegate() =>
      (char('!').trimHidden() &
              (ref0(expressionNoOperation) | ref0(expressionGroup)))
          .map((v) => ASTExpressionNegation(v[1] as ASTExpression));

  /// Go uses prefix `^` for bitwise NOT (complement).
  Parser<ASTExpressionOperation> expressionBitwiseNot() =>
      (char('^').trimHidden() &
              (ref0(expressionGroup) | ref0(expressionNoOperation)))
          .map((v) {
            var exp = v[1] as ASTExpression;
            return ASTExpressionOperation(
              ASTExpressionLiteral(ASTValueInt(-1)),
              ASTExpressionOperator.subtract,
              exp,
            );
          });

  Parser<ASTExpressionNegative> expressionNegative() =>
      (char('-').trimHidden() &
              (ref0(expressionNoOperation) | ref0(expressionGroup)))
          .map((v) => ASTExpressionNegative(v[1] as ASTExpression));

  Parser<ASTExpression> expressionGroup() =>
      (char('(').trimHidden() & ref0(expression) & char(')').trimHidden()).map(
        (v) => v[1] as ASTExpression,
      );

  /// The zero-valued composite literal of a declared struct: `&Foo{}`.
  ///
  /// Go has no `new`; this is how an instance is created, and it is what the Go
  /// generator emits inside a `func NewFoo() *Foo` factory. It maps to the
  /// struct's no-argument constructor. Only the empty-brace form is supported;
  /// field-initializing literals (`&Foo{x: 1}`) are not.
  Parser<ASTExpression> expressionStructLiteral() =>
      (char('&').trimHidden() &
              identifier() &
              char('{').trimHidden() &
              char('}').trimHidden())
          .map((v) {
            var name = v[1] as String;
            return ASTExpressionLocalFunctionInvocation(name, []);
          });

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

  /// `name(args)`, `pkg.func(args)` (incl. `fmt.Println(...)`),
  /// `receiver.method(args)`.
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
            var rawName = v[1] as String;
            var argsRec =
                v[3]
                    as ({
                      List<ASTExpression> positional,
                      Map<String, ASTExpression>? named,
                    })?;
            var args = argsRec?.positional ?? <ASTExpression>[];
            var chainFunctions = (v[5] as List)
                .whereType<ASTExpressionChainFunctionInvocation>()
                .toList();

            // `fmt.Println(...)` → canonical `print`.
            if (obj == 'fmt') {
              return ASTExpressionLocalFunctionInvocation(
                'print',
                args,
                chainFunctions,
              );
            }

            var name =
                _structConstructorName(rawName) ??
                normalizeFunctionName(rawName);

            if (obj != null && obj != 'this' && obj != _currentReceiver) {
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
            var obj = v[0] as String;
            var name = v[2] as String;
            var chainFunctions = (v[3] as List)
                .whereType<ASTExpressionChainFunctionInvocation>()
                .toList();

            ASTVariable variable = (obj == 'this' || obj == _currentReceiver)
                ? ASTThisVariable()
                : ASTScopeVariable(obj);
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
              ref0(callArguments).optional() &
              char(')').trimHidden())
          .map((v) {
            var fName = v[1] as String;
            var argsRec =
                v[3]
                    as ({
                      List<ASTExpression> positional,
                      Map<String, ASTExpression>? named,
                    })?;
            var args = argsRec?.positional ?? <ASTExpression>[];
            return ASTExpressionChainFunctionInvocation(fName, args);
          });

  Parser<List<ASTExpression>> expressionSequence() =>
      (ref0(expression) & (char(',').trimHidden() & ref0(expression)).star())
          .map((v) {
            var list = _expandListDeeply(v);
            return list.whereType<ASTExpression>().toList();
          });

  Parser<ASTExpressionNullValue> expressionNullValue() =>
      (nilToken()).map((v) => ASTExpressionNullValue());

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
            var fName = v[5] as String;
            var argsRec =
                v[7]
                    as ({
                      List<ASTExpression> positional,
                      Map<String, ASTExpression>? named,
                    })?;
            var args = argsRec?.positional ?? <ASTExpression>[];
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

  /// `[]T{ e0, e1 }` — a Go slice literal.
  Parser<ASTExpressionListLiteral> expressionListLiteral() =>
      (char('[').trimHidden() &
              char(']').trimHidden() &
              type() &
              char('{').trimHidden() &
              ref0(expressionSequence).optional() &
              char(',').trimHidden().optional() &
              char('}').trimHidden())
          .map((v) {
            var elementType = v[2] as ASTType;
            var values = (v[4] as List<ASTExpression>?) ?? <ASTExpression>[];
            return ASTExpressionListLiteral(elementType, values);
          });

  /// `map[K]V{ k0: v0, k1: v1 }` — a Go map literal.
  Parser<ASTExpressionMapLiteral> expressionMapLiteral() =>
      (mapToken().trimHidden() &
              char('[').trimHidden() &
              type() &
              char(']').trimHidden() &
              type() &
              char('{').trimHidden() &
              (mapEntry() & (char(',').trimHidden() & mapEntry()).star())
                  .optional() &
              char(',').trimHidden().optional() &
              char('}').trimHidden())
          .map((v) {
            var keyType = v[2] as ASTType;
            var valueType = v[4] as ASTType;
            var entries = <MapEntry<ASTExpression, ASTExpression>>[];
            var entriesOpt = v[6];
            if (entriesOpt != null) {
              entries.add(
                entriesOpt[0] as MapEntry<ASTExpression, ASTExpression>,
              );
              for (var tail in (entriesOpt[1] as List)) {
                entries.add(tail[1] as MapEntry<ASTExpression, ASTExpression>);
              }
            }
            return ASTExpressionMapLiteral(keyType, valueType, entries);
          });

  Parser<MapEntry<ASTExpression, ASTExpression>> mapEntry() =>
      (ref0(expression) & char(':').trimHidden() & ref0(expression)).map((v) {
        return MapEntry(v[0] as ASTExpression, v[2] as ASTExpression);
      });

  Parser<ASTExpressionVariableDirectOperation>
  expressionVariableDirectOperation() =>
      (variable() & (string('++') | string('--'))).map((v) {
        var variable = v[0];
        var operator = getASTAssignmentDirectOperator(v[1]);
        return ASTExpressionVariableDirectOperation(variable, operator, false);
      });

  Parser<ASTExpressionVariableAssignment> expressionVariableAssigment() =>
      (variable() & assigmentOperator() & ref0(expression)).map((v) {
        return ASTExpressionVariableAssignment(v[0], v[1], v[2]);
      });

  /// `o.field = value` / `this.field = value` (and `+=` etc.).
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
            ASTVariable variable = (obj == 'this' || obj == _currentReceiver)
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
          .map((v) => getASTAssignmentOperator(v));

  Parser<ASTVariable> variable() => (identifier()).map((name) {
    if (name == 'this' || name == _currentReceiver) {
      return ASTThisVariable();
    }
    return ASTScopeVariable(name);
  }).cast<ASTVariable>();

  /// Go closure used as an expression: `func(a int, b int) int { ... }`.
  Parser<ASTExpression> expressionLambda() =>
      (funcToken().trimHidden() &
              functionParametersDeclaration() &
              type().optional() &
              codeBlock())
          .map((v) {
            var parameters = v[1] as ASTFunctionParametersDeclaration;
            var returnType = (v[2] as ASTType?) ?? ASTTypeDynamic.instance;
            var block = v[3] as ASTBlock;
            var f = ASTFunctionDeclaration(
              '',
              parameters,
              returnType,
              block: block,
              modifiers: ASTModifiers.modifierStatic,
            );
            return ASTExpressionLiteralFunction(f);
          });

  // -----------------------------------------------------------------
  // Types.
  // -----------------------------------------------------------------

  Parser<ASTType> type() =>
      (ref0(pointerType) |
              ref0(sliceType) |
              ref0(mapType) |
              ref0(interfaceType) |
              ref0(simpleType))
          .cast<ASTType>();

  /// A pointer type `*T` maps to the underlying `T` (ApolloVM has no pointers).
  Parser<ASTType> pointerType() =>
      (char('*').trimHidden() & ref0(type)).map((v) => v[1] as ASTType);

  Parser<ASTTypeArray> sliceType() =>
      (char('[').trimHidden() & char(']').trimHidden() & ref0(type)).map((v) {
        return ASTTypeArray(v[2] as ASTType);
      });

  Parser<ASTTypeMap> mapType() =>
      (mapToken().trimHidden() &
              char('[').trimHidden() &
              ref0(type) &
              char(']').trimHidden() &
              ref0(type))
          .map((v) {
            return ASTTypeMap(v[2] as ASTType, v[4] as ASTType);
          });

  Parser<ASTType> interfaceType() =>
      ((string('interface').trimHidden() &
                      char('{').trimHidden() &
                      char('}').trimHidden())
                  .map((_) => ASTTypeObject.instance) |
              (string('any') & ref0(identifierPartLexicalToken).not())
                  .trimHidden()
                  .map((_) => ASTTypeObject.instance))
          .cast<ASTType>();

  Parser<ASTType> simpleType() => (identifier()).map((v) => getTypeByName(v));

  // -----------------------------------------------------------------
  // Literals.
  // -----------------------------------------------------------------

  Parser<ASTValue> literal() => (literalBool() | literalNum() | literalString())
      .trimHidden()
      .cast<ASTValue>();

  Parser<ASTValueBool> literalBool() =>
      ((string('true') | string('false')) &
              ref0(identifierPartLexicalToken).not())
          .trim()
          .map((v) => ASTValueBool(v[0] == 'true'));

  Parser<ASTValueNum> literalNum() =>
      (char('-').optional() & numberLexicalToken()).trim().map((v) {
        var negative = v[0] == '-';
        var value = v[1];
        return ASTValueNum.from(value, negative: negative);
      });

  Parser<ASTValue<String>> literalString() =>
      (stringLexicalToken()).map((v) => v.asValue());

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

/// A `type Name struct { ... }` declaration, grouped into an [ASTClassNormal]
/// by [GoGrammarDefinition.compilationUnit].
class _StructDecl {
  final String name;
  final List<ASTClassField> fields;

  _StructDecl(this.name, this.fields);
}

/// A `func (o *Name) method(...)` definition, grouped into an [ASTClassNormal]
/// by [GoGrammarDefinition.compilationUnit].
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
