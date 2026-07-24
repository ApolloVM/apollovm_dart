// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import '../ast/apollovm_ast_expression.dart';
import '../ast/apollovm_ast_statement.dart';
import '../ast/apollovm_ast_toplevel.dart';
import '../ast/apollovm_ast_type.dart';
import '../ast/apollovm_ast_variable.dart';

/// Severity of a [NullSafetyDiagnostic].
enum NullSafetySeverity { error, warning, info }

/// A single null-safety finding produced by [NullSafetyAnalyzer].
///
/// The AST does not carry source offsets, so [snippet] holds a representative
/// slice of source text (e.g. `a.x` or `x = null`) that the LSP layer can
/// locate to attach a range. It is best-effort (first match).
class NullSafetyDiagnostic {
  final String message;
  final String code;
  final NullSafetySeverity severity;
  final String? snippet;

  NullSafetyDiagnostic(
    this.message, {
    required this.code,
    this.severity = NullSafetySeverity.error,
    this.snippet,
  });

  @override
  String toString() => '[$code/${severity.name}] $message';
}

/// A pragmatic, flow-aware Dart null-safety analyzer.
///
/// It is intentionally *not* a full soundness engine — it reasons only about
/// local variables and parameters, and reports the clear, high-value cases:
///
/// - assigning a `null` literal to a non-nullable declaration/parameter;
/// - unconditionally accessing a member/method/index on a nullable local
///   variable without `?.`, `!` or a prior null check;
/// - a `!` null-assertion applied to a `null` literal (always throws).
///
/// It performs flow promotion for the common guards `if (x != null) { … }` and
/// `if (x == null) { … } else { … }`, narrowing a variable to non-nullable
/// inside the guarded branch. Anything ambiguous (reassignment, closures,
/// non-local receivers) conservatively bails to "not promoted".
class NullSafetyAnalyzer {
  final List<NullSafetyDiagnostic> _findings = [];

  /// Analyzes [root] and returns the findings (deduplicated).
  List<NullSafetyDiagnostic> analyze(ASTRoot root) {
    _findings.clear();

    // Function/method/getter bodies are themselves `ASTBlock`s; analyze each
    // as an independent flow unit seeded with its parameters.
    for (final node in root.descendantChildren) {
      if (node is ASTInvocableDeclaration) {
        _analyzeInvocable(node);
      }
    }

    // Deduplicate (a nested body may be reached more than once).
    final seen = <String>{};
    final unique = <NullSafetyDiagnostic>[];
    for (final f in _findings) {
      final key = '${f.code}|${f.snippet}|${f.message}';
      if (seen.add(key)) unique.add(f);
    }
    return unique;
  }

  void _analyzeInvocable(ASTInvocableDeclaration decl) {
    final scope = _Scope();
    // Seed parameter nullability.
    for (final p in decl.parameters.allParameters) {
      scope.declare(p.name, p.type.nullable);
    }
    _analyzeBlock(decl, scope);
  }

  void _analyzeBlock(ASTBlock block, _Scope parent) {
    final scope = parent.child();
    for (final stmt in block.statements) {
      _analyzeStatement(stmt, scope);
    }
  }

  void _analyzeStatement(ASTStatement stmt, _Scope scope) {
    if (stmt is ASTStatementVariableDeclaration) {
      final value = stmt.value;
      if (value != null) {
        _analyzeExpression(value, scope);
        if (!_isNullableSlot(stmt.type)) {
          if (value is ASTExpressionNullValue) {
            _add(
              "A value of type 'Null' can't be assigned to the non-nullable "
              "variable '${stmt.name}' of type '${stmt.type.name}'.",
              code: 'null-to-non-nullable',
              snippet: '${stmt.name} = null',
            );
          } else {
            // A nullable *variable* flowing into a non-nullable slot
            // (`int x = a;` where `a` is `int?`) is the same error one step
            // removed, and is only safe behind `!`, `??` or a null check.
            final name = _nullableVariableRead(value, scope);
            if (name != null) {
              _add(
                "A nullable value ('$name') can't be assigned to the "
                "non-nullable variable '${stmt.name}' of type "
                "'${stmt.type.name}'. Use '??', '!' or a null check.",
                code: 'nullable-to-non-nullable',
                snippet: '${stmt.name} = $name',
              );
            }
          }
        }
      }
      scope.declare(stmt.name, stmt.type.nullable);
      return;
    }

    if (stmt is ASTBranchIfBlock) {
      _analyzeExpression(stmt.condition, scope);
      final promo = _promotionsFrom(stmt.condition);
      final thenScope = scope.child();
      for (final n in promo.whenTrue) {
        thenScope.promote(n);
      }
      _analyzeBlock(stmt.block, thenScope);
      return;
    }

    if (stmt is ASTBranchIfElseBlock) {
      _analyzeExpression(stmt.condition, scope);
      final promo = _promotionsFrom(stmt.condition);
      final thenScope = scope.child();
      for (final n in promo.whenTrue) {
        thenScope.promote(n);
      }
      _analyzeBlock(stmt.blockIf, thenScope);
      final elseBlock = stmt.blockElse;
      if (elseBlock != null) {
        final elseScope = scope.child();
        for (final n in promo.whenFalse) {
          elseScope.promote(n);
        }
        _analyzeBlock(elseBlock, elseScope);
      }
      return;
    }

    if (stmt is ASTBranchIfElseIfsElseBlock) {
      _analyzeExpression(stmt.condition, scope);
      final promo = _promotionsFrom(stmt.condition);
      final thenScope = scope.child();
      for (final n in promo.whenTrue) {
        thenScope.promote(n);
      }
      _analyzeBlock(stmt.blockIf, thenScope);
      for (final elseIf in stmt.blocksElseIf) {
        _analyzeExpression(elseIf.condition, scope);
        _analyzeBlock(elseIf.block, scope.child());
      }
      final elseBlock = stmt.blockElse;
      if (elseBlock != null) _analyzeBlock(elseBlock, scope.child());
      return;
    }

    if (stmt is ASTStatementExpression) {
      _analyzeExpression(stmt.expression, scope);
      return;
    }

    if (stmt is ASTStatementReturnWithExpression) {
      _analyzeExpression(stmt.expression, scope);
      return;
    }

    if (stmt is ASTBlock) {
      _analyzeBlock(stmt, scope);
      return;
    }

    // Other statement kinds: descend into any nested blocks/expressions
    // generically (no promotion tracking across them).
    for (final child in stmt.children) {
      if (child is ASTBlock) {
        _analyzeBlock(child, scope);
      } else if (child is ASTExpression) {
        _analyzeExpression(child, scope);
      } else if (child is ASTStatement) {
        _analyzeStatement(child, scope);
      }
    }
  }

  void _analyzeExpression(ASTExpression expr, _Scope scope) {
    // Null-aware access nodes are always safe — but still check their operands.
    if (expr is ASTExpressionObjectGetterAccess) {
      _checkNullableReceiver(
        expr.variable,
        expr.isNullAware || expr.assertReceiver,
        member: expr.name,
        scope: scope,
      );
    } else if (expr is ASTExpressionObjectFunctionInvocation) {
      _checkNullableReceiver(
        expr.variable,
        expr.isNullAware || expr.assertReceiver,
        member: '${expr.name}()',
        scope: scope,
      );
    } else if (expr is ASTExpressionVariableEntryAccess) {
      _checkNullableReceiver(
        expr.variable,
        expr.isNullAware || expr.assertReceiver,
        member: '[]',
        scope: scope,
        isIndex: true,
      );
    } else if (expr is ASTExpressionNullAssertion) {
      final inner = expr.expression;
      if (inner is ASTExpressionNullValue) {
        _add(
          'The null-assertion operator (`!`) is applied to a `null` literal, '
          'which always throws.',
          code: 'null-assertion-on-null',
          severity: NullSafetySeverity.warning,
          snippet: 'null!',
        );
      }
    } else if (expr is ASTExpressionOperation) {
      _checkOperationOperands(expr, scope);
    } else if (expr is ASTExpressionVariableAssignment) {
      // A reassignment invalidates promotion for that variable.
      final v = expr.variable;
      if (v is ASTScopeVariable) scope.demote(v.name);
    }

    for (final child in expr.children) {
      if (child is ASTExpression) _analyzeExpression(child, scope);
    }
  }

  void _checkNullableReceiver(
    ASTVariable variable,
    bool guarded, {
    required String member,
    required _Scope scope,
    bool isIndex = false,
  }) {
    // `?.`/`?[` (null-aware) or `!` (null-assertion) make the access safe.
    if (guarded) return;
    if (variable is! ASTScopeVariable) return;

    final name = variable.name;
    final declaredNullable = scope.declaredNullable(name);
    if (declaredNullable != true) return; // unknown or non-nullable: fine
    if (scope.isPromoted(name)) return; // narrowed by a prior null check

    final access = isIndex ? '$name[...]' : '$name.$member';
    _add(
      "The receiver '$name' can be 'null', so the ${isIndex ? 'index access' : "member '$member'"} "
      "can't be accessed unconditionally. Use '?.'/'?[', '!' or a null check.",
      code: 'unchecked-nullable-access',
      snippet: access,
    );
  }

  /// The name of the variable [expr] reads, when that variable is declared
  /// nullable and has not been promoted by a preceding null check — i.e. the
  /// expression can be `null` here. Otherwise `null`.
  ///
  /// Only a bare variable read qualifies: `x!` is an [ASTExpressionNullAssertion]
  /// and `x ?? 0` an [ASTExpressionOperation], so both correctly fall through.
  String? _nullableVariableRead(ASTExpression expr, _Scope scope) {
    if (expr is! ASTExpressionVariableAccess) return null;

    final v = expr.variable;
    if (v is! ASTScopeVariable) return null;

    final name = v.name;
    if (scope.declaredNullable(name) != true) return null;
    if (scope.isPromoted(name)) return null;

    return name;
  }

  /// Reports a nullable operand used in an operation that would dereference it.
  ///
  /// `??`, `==` and `!=` are exempt: a nullable operand is exactly what they
  /// exist to handle.
  void _checkOperationOperands(ASTExpressionOperation expr, _Scope scope) {
    final op = expr.operator;
    if (op == ASTExpressionOperator.nullCoalesce ||
        op == ASTExpressionOperator.equals ||
        op == ASTExpressionOperator.notEquals) {
      return;
    }

    // The diagnostic range is located by searching the source for the snippet,
    // so pair the operand with the operator: a bare name like `x` would match
    // its own declaration line instead of the operation.
    final opText = getASTExpressionOperatorText(op);

    final left = _nullableVariableRead(expr.expression1, scope);
    if (left != null) {
      _add(
        "The operand '$left' can be 'null', so it can't be used in an "
        "operation unconditionally. Use '??', '!' or a null check.",
        code: 'unchecked-nullable-operand',
        snippet: '$left $opText',
      );
    }

    final right = _nullableVariableRead(expr.expression2, scope);
    if (right != null) {
      _add(
        "The operand '$right' can be 'null', so it can't be used in an "
        "operation unconditionally. Use '??', '!' or a null check.",
        code: 'unchecked-nullable-operand',
        snippet: '$opText $right',
      );
    }
  }

  /// Whether a declared slot [type] accepts `null` without a diagnostic
  /// (nullable, or an untyped/top slot where nullability is not enforced).
  bool _isNullableSlot(ASTType type) {
    if (type.nullable) return true;
    if (type is ASTTypeDynamic) return true;
    if (type is ASTTypeVar) return true;
    if (type is ASTTypeObject) return true;
    if (type is ASTTypeNull) return true;
    return false;
  }

  /// Extracts the variable-name promotions implied by a boolean [condition]:
  /// `x != null` promotes `x` when the condition is true; `x == null` promotes
  /// `x` when the condition is false.
  _Promotions _promotionsFrom(ASTExpression condition) {
    final whenTrue = <String>{};
    final whenFalse = <String>{};

    void handle(ASTExpression e) {
      if (e is ASTExpressionOperation) {
        final op = e.operator;
        if (op == ASTExpressionOperator.notEquals ||
            op == ASTExpressionOperator.equals) {
          final name = _nullComparisonVariable(e.expression1, e.expression2);
          if (name != null) {
            if (op == ASTExpressionOperator.notEquals) {
              whenTrue.add(name);
            } else {
              whenFalse.add(name);
            }
          }
        } else if (op == ASTExpressionOperator.and) {
          // `x != null && …`: both sides promote when true.
          handle(e.expression1);
          handle(e.expression2);
        }
      }
    }

    handle(condition);
    return _Promotions(whenTrue, whenFalse);
  }

  /// If [a]/[b] is a `variable <op> null` comparison, returns the variable name.
  String? _nullComparisonVariable(ASTExpression a, ASTExpression b) {
    String? nameOf(ASTExpression e) {
      if (e is ASTExpressionVariableAccess) {
        final v = e.variable;
        if (v is ASTScopeVariable) return v.name;
      }
      return null;
    }

    if (b is ASTExpressionNullValue) return nameOf(a);
    if (a is ASTExpressionNullValue) return nameOf(b);
    return null;
  }

  void _add(
    String message, {
    required String code,
    NullSafetySeverity severity = NullSafetySeverity.error,
    String? snippet,
  }) {
    _findings.add(
      NullSafetyDiagnostic(
        message,
        code: code,
        severity: severity,
        snippet: snippet,
      ),
    );
  }
}

class _Promotions {
  final Set<String> whenTrue;
  final Set<String> whenFalse;
  _Promotions(this.whenTrue, this.whenFalse);
}

class _Scope {
  final _Scope? parent;
  final Map<String, bool> _nullable = {};
  final Set<String> _promoted = {};

  _Scope([this.parent]);

  _Scope child() => _Scope(this);

  void declare(String name, bool nullable) {
    _nullable[name] = nullable;
    _promoted.remove(name);
  }

  bool? declaredNullable(String name) =>
      _nullable[name] ?? parent?.declaredNullable(name);

  bool isPromoted(String name) =>
      _promoted.contains(name) || (parent?.isPromoted(name) ?? false);

  void promote(String name) => _promoted.add(name);

  void demote(String name) => _promoted.remove(name);
}
