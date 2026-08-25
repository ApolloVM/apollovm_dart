// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import '../ast/apollovm_ast_expression.dart';
import '../ast/apollovm_ast_statement.dart';
import '../ast/apollovm_ast_toplevel.dart';
import '../ast/apollovm_ast_value.dart';
import '../ast/apollovm_ast_variable.dart';
import 'ast_binary_context.dart';
import 'ast_binary_node_codec.dart';
import 'ast_binary_tags.dart';

/// Writes the chained calls that may follow an invocation or getter access
/// (`foo().bar().baz()`).
void _writeChain(ASTBinaryWriteContext w, WithCallChainFunction n) =>
    w.nodes(n.chainFunctionInvocation);

List<ASTExpressionChainFunctionInvocation>? _readChain(
  ASTBinaryReadContext r,
) => r.nodes<ASTExpressionChainFunctionInvocation>();

/// Writes the named arguments of a call (`foo(a: 1, b: 2)`).
void _writeNamedArguments(
  ASTBinaryWriteContext w,
  Map<String, ASTExpression>? named,
) {
  if (named == null) {
    w.uint(0);
    return;
  }
  w.uint(named.length + 1);
  for (var e in named.entries) {
    w.str(e.key);
    w.node(e.value);
  }
}

Map<String, ASTExpression>? _readNamedArguments(ASTBinaryReadContext r) {
  var n = r.uint();
  if (n == 0) return null;
  var named = <String, ASTExpression>{};
  for (var i = 1; i < n; ++i) {
    var key = r.str();
    named[key] = r.node<ASTExpression>();
  }
  return named;
}

/// Codecs for the [ASTExpression] family, **most derived first**.
final List<ASTNodeCodec> expressionCodecs = [
  // --- Leaves ---------------------------------------------------------------
  ASTNodeCodec<ASTExpressionNullValue>(
    ASTNodeTag.expressionNullValue,
    'ASTExpressionNullValue',
    encode: (w, n) {},
    decode: (r) => ASTExpressionNullValue(),
  ),

  ASTNodeCodec<ASTExpressionLiteral>(
    ASTNodeTag.expressionLiteral,
    'ASTExpressionLiteral',
    encode: (w, n) => w.node(n.value),
    decode: (r) => ASTExpressionLiteral(r.node<ASTValue>()),
  ),

  ASTNodeCodec<ASTExpressionVariableAccess>(
    ASTNodeTag.expressionVariableAccess,
    'ASTExpressionVariableAccess',
    encode: (w, n) => w.node(n.variable),
    decode: (r) => ASTExpressionVariableAccess(r.node<ASTVariable>()),
  ),

  // --- Operators ------------------------------------------------------------
  ASTNodeCodec<ASTExpressionOperation>(
    ASTNodeTag.expressionOperation,
    'ASTExpressionOperation',
    encode: (w, n) {
      w.node(n.expression1);
      w.enumByName(n.operator);
      w.node(n.expression2);
    },
    decode: (r) {
      var e1 = r.node<ASTExpression>();
      var op = r.enumByName(ASTExpressionOperator.values);
      return ASTExpressionOperation(e1, op, r.node<ASTExpression>());
    },
  ),

  ASTNodeCodec<ASTExpressionLogicalAnd>(
    ASTNodeTag.expressionLogicalAnd,
    'ASTExpressionLogicalAnd',
    encode: (w, n) {
      w.node(n.expression1);
      w.node(n.expression2);
    },
    decode: (r) {
      var e1 = r.node<ASTExpression>();
      return ASTExpressionLogicalAnd(e1, r.node<ASTExpression>());
    },
  ),

  ASTNodeCodec<ASTExpressionLogicalOr>(
    ASTNodeTag.expressionLogicalOr,
    'ASTExpressionLogicalOr',
    encode: (w, n) {
      w.node(n.expression1);
      w.node(n.expression2);
    },
    decode: (r) {
      var e1 = r.node<ASTExpression>();
      return ASTExpressionLogicalOr(e1, r.node<ASTExpression>());
    },
  ),

  ASTNodeCodec<ASTExpressionNegation>(
    ASTNodeTag.expressionNegation,
    'ASTExpressionNegation',
    encode: (w, n) => w.node(n.expression),
    decode: (r) => ASTExpressionNegation(r.node<ASTExpression>()),
  ),

  ASTNodeCodec<ASTExpressionNegative>(
    ASTNodeTag.expressionNegative,
    'ASTExpressionNegative',
    encode: (w, n) => w.node(n.expression),
    decode: (r) => ASTExpressionNegative(r.node<ASTExpression>()),
  ),

  ASTNodeCodec<ASTExpressionBitwiseNot>(
    ASTNodeTag.expressionBitwiseNot,
    'ASTExpressionBitwiseNot',
    encode: (w, n) => w.node(n.expression),
    decode: (r) => ASTExpressionBitwiseNot(r.node<ASTExpression>()),
  ),

  ASTNodeCodec<ASTExpressionAwait>(
    ASTNodeTag.expressionAwait,
    'ASTExpressionAwait',
    encode: (w, n) => w.node(n.expression),
    decode: (r) => ASTExpressionAwait(r.node<ASTExpression>()),
  ),

  ASTNodeCodec<ASTExpressionConditional>(
    ASTNodeTag.expressionConditional,
    'ASTExpressionConditional',
    encode: (w, n) {
      w.node(n.condition);
      w.node(n.valueIfTrue);
      w.node(n.valueIfFalse);
    },
    decode: (r) {
      var condition = r.node<ASTExpression>();
      var ifTrue = r.node<ASTExpression>();
      return ASTExpressionConditional(
        condition,
        ifTrue,
        r.node<ASTExpression>(),
      );
    },
  ),

  // --- Null handling --------------------------------------------------------
  ASTNodeCodec<ASTExpressionNullAssertion>(
    ASTNodeTag.expressionNullAssertion,
    'ASTExpressionNullAssertion',
    encode: (w, n) => w.node(n.expression),
    decode: (r) => ASTExpressionNullAssertion(r.node<ASTExpression>()),
  ),

  ASTNodeCodec<ASTExpressionNullCoalesce>(
    ASTNodeTag.expressionNullCoalesce,
    'ASTExpressionNullCoalesce',
    encode: (w, n) {
      w.node(n.expression1);
      w.node(n.expression2);
    },
    decode: (r) {
      var e1 = r.node<ASTExpression>();
      return ASTExpressionNullCoalesce(e1, r.node<ASTExpression>());
    },
  ),

  ASTNodeCodec<ASTExpressionNullCheck>(
    ASTNodeTag.expressionNullCheck,
    'ASTExpressionNullCheck',
    encode: (w, n) {
      w.node(n.expression);
      // The `null` literal is kept as a real child — the Wasm backend scans for
      // it — so it is written rather than synthesized on the way back.
      w.node(n.nullValue);
      w.boolean(n.negated);
      w.boolean(n.nullFirst);
    },
    decode: (r) {
      var expression = r.node<ASTExpression>();
      var nullValue = r.node<ASTExpressionNullValue>();
      var negated = r.boolean();
      return ASTExpressionNullCheck(
        expression,
        nullValue,
        negated: negated,
        nullFirst: r.boolean(),
      );
    },
  ),

  // --- Literals with structure ----------------------------------------------
  ASTNodeCodec<ASTExpressionListLiteral>(
    ASTNodeTag.expressionListLiteral,
    'ASTExpressionListLiteral',
    encode: (w, n) {
      w.typeOrNull(n.type);
      w.nodes(n.valuesExpressions);
    },
    decode: (r) {
      var type = r.typeOrNull();
      return ASTExpressionListLiteral(type, r.nodeList<ASTExpression>());
    },
  ),

  ASTNodeCodec<ASTExpressionMapLiteral>(
    ASTNodeTag.expressionMapLiteral,
    'ASTExpressionMapLiteral',
    encode: (w, n) {
      w.typeOrNull(n.keyType);
      w.typeOrNull(n.valueType);
      w.uint(n.entriesExpressions.length);
      for (var e in n.entriesExpressions) {
        w.node(e.key);
        w.node(e.value);
      }
    },
    decode: (r) {
      var keyType = r.typeOrNull();
      var valueType = r.typeOrNull();
      var count = r.uint();
      var entries = <MapEntry<ASTExpression, ASTExpression>>[];
      for (var i = 0; i < count; ++i) {
        var k = r.node<ASTExpression>();
        entries.add(MapEntry(k, r.node<ASTExpression>()));
      }
      return ASTExpressionMapLiteral(keyType, valueType, entries);
    },
  ),

  ASTNodeCodec<ASTExpressionLiteralFunction>(
    ASTNodeTag.expressionLiteralFunction,
    'ASTExpressionLiteralFunction',
    encode: (w, n) => w.node(n.function),
    decode: (r) =>
        ASTExpressionLiteralFunction(r.node<ASTFunctionDeclaration>()),
  ),

  ASTNodeCodec<ASTExpressionCascade>(
    ASTNodeTag.expressionCascade,
    'ASTExpressionCascade',
    encode: (w, n) {
      w.node(n.receiver);
      w.str(n.targetVariableName);
      w.nodes(n.sections);
      w.boolean(n.isNullAware);
    },
    decode: (r) {
      var receiver = r.node<ASTExpression>();
      var targetVariableName = r.str();
      var sections = r.nodeList<ASTExpression>();
      return ASTExpressionCascade(
        receiver,
        targetVariableName,
        sections,
        isNullAware: r.boolean(),
      );
    },
  ),

  // --- Entry access and assignment ------------------------------------------
  ASTNodeCodec<ASTExpressionVariableEntryAccess>(
    ASTNodeTag.expressionVariableEntryAccess,
    'ASTExpressionVariableEntryAccess',
    encode: (w, n) {
      w.node(n.variable);
      w.node(n.expression);
      w.nodes(n.extraIndices);
      w.boolean(n.isNullAware);
      w.boolean(n.assertReceiver);
    },
    decode: (r) {
      var variable = r.node<ASTVariable>();
      var expression = r.node<ASTExpression>();
      var extraIndices = r.nodeList<ASTExpression>();
      var isNullAware = r.boolean();
      return ASTExpressionVariableEntryAccess(
        variable,
        expression,
        extraIndices,
        isNullAware,
        r.boolean(),
      );
    },
  ),

  ASTNodeCodec<ASTExpressionVariableEntryAssignment>(
    ASTNodeTag.expressionVariableEntryAssignment,
    'ASTExpressionVariableEntryAssignment',
    encode: (w, n) {
      w.node(n.variable);
      w.node(n.keyExpression);
      w.enumByName(n.operator);
      w.node(n.expression);
      w.nodes(n.extraKeys);
    },
    decode: (r) {
      var variable = r.node<ASTVariable>();
      var keyExpression = r.node<ASTExpression>();
      var operator = r.enumByName(ASTAssignmentOperator.values);
      var expression = r.node<ASTExpression>();
      return ASTExpressionVariableEntryAssignment(
        variable,
        keyExpression,
        operator,
        expression,
        r.nodeList<ASTExpression>(),
      );
    },
  ),

  ASTNodeCodec<ASTExpressionVariableAssignment>(
    ASTNodeTag.expressionVariableAssignment,
    'ASTExpressionVariableAssignment',
    encode: (w, n) {
      w.node(n.variable);
      w.enumByName(n.operator);
      w.node(n.expression);
    },
    decode: (r) {
      var variable = r.node<ASTVariable>();
      var operator = r.enumByName(ASTAssignmentOperator.values);
      return ASTExpressionVariableAssignment(
        variable,
        operator,
        r.node<ASTExpression>(),
      );
    },
  ),

  ASTNodeCodec<ASTExpressionVariableDirectOperation>(
    ASTNodeTag.expressionVariableDirectOperation,
    'ASTExpressionVariableDirectOperation',
    encode: (w, n) {
      w.node(n.variable);
      w.enumByName(n.operator);
      w.boolean(n.preOperation);
    },
    decode: (r) {
      var variable = r.node<ASTVariable>();
      var operator = r.enumByName(ASTAssignmentOperator.values);
      return ASTExpressionVariableDirectOperation(
        variable,
        operator,
        r.boolean(),
      );
    },
  ),

  ASTNodeCodec<ASTExpressionObjectSetterAssignment>(
    ASTNodeTag.expressionObjectSetterAssignment,
    'ASTExpressionObjectSetterAssignment',
    encode: (w, n) {
      w.node(n.variable);
      w.str(n.name);
      w.enumByName(n.operator);
      w.node(n.expression);
    },
    decode: (r) {
      var variable = r.node<ASTVariable>();
      var name = r.str();
      var operator = r.enumByName(ASTAssignmentOperator.values);
      return ASTExpressionObjectSetterAssignment(
        variable,
        name,
        operator,
        r.node<ASTExpression>(),
      );
    },
  ),

  // --- Invocations ----------------------------------------------------------
  ASTNodeCodec<ASTExpressionObjectEntryFunctionInvocation>(
    ASTNodeTag.expressionObjectEntryFunctionInvocation,
    'ASTExpressionObjectEntryFunctionInvocation',
    encode: (w, n) {
      // The constructor builds `variableAccess` from these two, so its parts
      // are written and the node re-synthesizes it on the way back.
      w.node(n.variableAccess.variable);
      w.node(n.variableAccess.expression);
      w.str(n.name);
      w.nodes(n.arguments);
      _writeChain(w, n);
      _writeNamedArguments(w, n.namedArguments);
    },
    decode: (r) {
      var variable = r.node<ASTVariable>();
      var expression = r.node<ASTExpression>();
      var name = r.str();
      var arguments = r.nodeList<ASTExpression>();
      var node = ASTExpressionObjectEntryFunctionInvocation(
        variable,
        expression,
        name,
        arguments,
        _readChain(r),
      );
      node.namedArguments = _readNamedArguments(r);
      return node;
    },
  ),

  ASTNodeCodec<ASTExpressionObjectFunctionInvocation>(
    ASTNodeTag.expressionObjectFunctionInvocation,
    'ASTExpressionObjectFunctionInvocation',
    encode: (w, n) {
      w.node(n.variable);
      w.str(n.name);
      w.nodes(n.arguments);
      _writeChain(w, n);
      w.boolean(n.isNullAware);
      w.boolean(n.assertReceiver);
      _writeNamedArguments(w, n.namedArguments);
    },
    decode: (r) {
      var variable = r.node<ASTVariable>();
      var name = r.str();
      var arguments = r.nodeList<ASTExpression>();
      var chain = _readChain(r);
      var isNullAware = r.boolean();
      var node = ASTExpressionObjectFunctionInvocation(
        variable,
        name,
        arguments,
        chain,
        isNullAware,
        r.boolean(),
      );
      node.namedArguments = _readNamedArguments(r);
      return node;
    },
  ),

  ASTNodeCodec<ASTExpressionGroupFunctionInvocation>(
    ASTNodeTag.expressionGroupFunctionInvocation,
    'ASTExpressionGroupFunctionInvocation',
    encode: (w, n) {
      w.node(n.expression);
      w.str(n.name);
      w.nodes(n.arguments);
      _writeChain(w, n);
      _writeNamedArguments(w, n.namedArguments);
    },
    decode: (r) {
      var expression = r.node<ASTExpression>();
      var name = r.str();
      var arguments = r.nodeList<ASTExpression>();
      var node = ASTExpressionGroupFunctionInvocation(
        expression,
        name,
        arguments,
        _readChain(r),
      );
      node.namedArguments = _readNamedArguments(r);
      return node;
    },
  ),

  ASTNodeCodec<ASTExpressionChainFunctionInvocation>(
    ASTNodeTag.expressionChainFunctionInvocation,
    'ASTExpressionChainFunctionInvocation',
    encode: (w, n) {
      w.str(n.name);
      w.nodes(n.arguments);
      _writeNamedArguments(w, n.namedArguments);
    },
    decode: (r) {
      var name = r.str();
      var node = ASTExpressionChainFunctionInvocation(
        name,
        r.nodeList<ASTExpression>(),
      );
      node.namedArguments = _readNamedArguments(r);
      return node;
    },
  ),

  ASTNodeCodec<ASTExpressionLocalFunctionInvocation>(
    ASTNodeTag.expressionLocalFunctionInvocation,
    'ASTExpressionLocalFunctionInvocation',
    encode: (w, n) {
      w.str(n.name);
      w.nodes(n.arguments);
      _writeChain(w, n);
      _writeNamedArguments(w, n.namedArguments);
    },
    decode: (r) {
      var name = r.str();
      var arguments = r.nodeList<ASTExpression>();
      var node = ASTExpressionLocalFunctionInvocation(
        name,
        arguments,
        _readChain(r),
      );
      node.namedArguments = _readNamedArguments(r);
      return node;
    },
  ),

  // --- Getter access --------------------------------------------------------
  ASTNodeCodec<ASTExpressionObjectGetterAccess>(
    ASTNodeTag.expressionObjectGetterAccess,
    'ASTExpressionObjectGetterAccess',
    encode: (w, n) {
      w.node(n.variable);
      w.str(n.name);
      _writeChain(w, n);
      w.boolean(n.isNullAware);
      w.boolean(n.assertReceiver);
    },
    decode: (r) {
      var variable = r.node<ASTVariable>();
      var name = r.str();
      var chain = _readChain(r);
      var isNullAware = r.boolean();
      return ASTExpressionObjectGetterAccess(
        variable,
        name,
        chain,
        isNullAware,
        r.boolean(),
      );
    },
  ),

  ASTNodeCodec<ASTExpressionLocalGetterAccess>(
    ASTNodeTag.expressionLocalGetterAccess,
    'ASTExpressionLocalGetterAccess',
    encode: (w, n) {
      w.str(n.name);
      _writeChain(w, n);
    },
    decode: (r) {
      var name = r.str();
      return ASTExpressionLocalGetterAccess(name, _readChain(r));
    },
  ),
];
