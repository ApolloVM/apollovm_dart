// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import '../ast/apollovm_ast_expression.dart';
import '../ast/apollovm_ast_variable.dart';
import 'ast_binary_node_codec.dart';
import 'ast_binary_tags.dart';

/// Codecs for the [ASTVariable] family, **most derived first**.
///
/// `ASTStaticFieldVariable` is absent on purpose: it holds a direct reference
/// to an `ASTClassNormal`, and is only built once a class has been resolved.
/// `ASTRuntimeVariable` and `ASTStaticClassAccessorVariable` are refused for
/// the same reason — see `ASTCodecRegistry.excluded`.
final List<ASTNodeCodec> variableCodecs = [
  ASTNodeCodec<ASTScopeVariable>(
    ASTNodeTag.scopeVariable,
    'ASTScopeVariable',
    // Only the name: `resolvedIdentifier` and the associated node are worked
    // out again by `resolveNode` after the tree is rebuilt, exactly as they are
    // after a parse.
    encode: (w, n) => w.str(n.name),
    decode: (r) => ASTScopeVariable(r.str()),
  ),

  ASTNodeCodec<ASTThisVariable>(
    ASTNodeTag.thisVariable,
    'ASTThisVariable',
    encode: (w, n) {},
    decode: (r) => ASTThisVariable(),
  ),

  ASTNodeCodec<ASTExpressionVariable>(
    ASTNodeTag.expressionVariable,
    'ASTExpressionVariable',
    encode: (w, n) => w.node(n.expression),
    decode: (r) => ASTExpressionVariable(r.node<ASTExpression>()),
  ),

  // Before `ASTClassField`, which it extends.
  ASTNodeCodec<ASTClassFieldWithInitialValue>(
    ASTNodeTag.classFieldWithInitialValue,
    'ASTClassFieldWithInitialValue',
    encode: (w, n) {
      w.type(n.type);
      w.str(n.name);
      // `children` is empty for this node, so the initializer would be missed
      // by any generic walk and has to be written explicitly.
      w.node(n.initialValue);
      w.boolean(n.finalValue);
      w.modifiers(n.modifiers);
    },
    decode: (r) {
      var type = r.type();
      var name = r.str();
      var initialValue = r.node<ASTExpression>();
      var finalValue = r.boolean();
      return ASTClassFieldWithInitialValue(
        type,
        name,
        initialValue,
        finalValue,
        modifiers: r.modifiers(),
      );
    },
  ),

  ASTNodeCodec<ASTClassField>(
    ASTNodeTag.classField,
    'ASTClassField',
    encode: (w, n) {
      w.type(n.type);
      w.str(n.name);
      w.boolean(n.finalValue);
      w.modifiers(n.modifiers);
    },
    decode: (r) {
      var type = r.type();
      var name = r.str();
      var finalValue = r.boolean();
      return ASTClassField(type, name, finalValue, modifiers: r.modifiers());
    },
  ),
];
