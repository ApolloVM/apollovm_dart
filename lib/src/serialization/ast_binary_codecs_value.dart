// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import '../ast/apollovm_ast_expression.dart';
import '../ast/apollovm_ast_type.dart';
import '../ast/apollovm_ast_value.dart';
import '../ast/apollovm_ast_variable.dart';
import 'ast_binary_node_codec.dart';
import 'ast_binary_tags.dart';

/// Codecs for the [ASTValue] family, **most derived first**.
///
/// Dispatch walks this list with `is` tests, so `ASTValueBool` has to precede
/// `ASTValuePrimitive`, and everything concrete has to precede the
/// `ASTValueStatic` catch-all at the end.
final List<ASTNodeCodec> valueCodecs = [
  // --- Primitives -----------------------------------------------------------
  ASTNodeCodec<ASTValueBool>(
    ASTNodeTag.valueBool,
    'ASTValueBool',
    encode: (w, n) => w.boolean(n.value),
    decode: (r) => ASTValueBool(r.boolean()),
  ),

  ASTNodeCodec<ASTValueInt>(
    ASTNodeTag.valueInt,
    'ASTValueInt',
    encode: (w, n) {
      w.literalInt(n.value);
      // `negative` is not derivable from the value: it records that the source
      // wrote a unary minus, which the generators reproduce, and it defaults to
      // `value.isNegative` only when the parser did not say.
      w.boolean(n.negative);
    },
    decode: (r) {
      var v = r.literalInt();
      return ASTValueInt(v, negative: r.boolean());
    },
  ),

  ASTNodeCodec<ASTValueDouble>(
    ASTNodeTag.valueDouble,
    'ASTValueDouble',
    encode: (w, n) {
      w.float64(n.value);
      w.boolean(n.negative);
    },
    decode: (r) {
      var v = r.float64();
      return ASTValueDouble(v, negative: r.boolean());
    },
  ),

  ASTNodeCodec<ASTValueString>(
    ASTNodeTag.valueString,
    'ASTValueString',
    encode: (w, n) => w.str(n.value),
    decode: (r) => ASTValueString(r.str()),
  ),

  ASTNodeCodec<ASTValueNull>(
    ASTNodeTag.valueNull,
    'ASTValueNull',
    encode: (w, n) {},
    decode: (r) => ASTValueNull(),
  ),

  ASTNodeCodec<ASTValueVoid>(
    ASTNodeTag.valueVoid,
    'ASTValueVoid',
    encode: (w, n) {},
    decode: (r) => ASTValueVoid(),
  ),

  // --- String composition ---------------------------------------------------
  ASTNodeCodec<ASTValueStringExpression>(
    ASTNodeTag.valueStringExpression,
    'ASTValueStringExpression',
    encode: (w, n) => w.node(n.expression),
    decode: (r) => ASTValueStringExpression(r.node<ASTExpression>()),
  ),

  ASTNodeCodec<ASTValueStringVariable>(
    ASTNodeTag.valueStringVariable,
    'ASTValueStringVariable',
    // `children` reports nothing for this node, so the variable has to be
    // written explicitly rather than picked up by a generic walk.
    encode: (w, n) => w.node(n.variable),
    decode: (r) => ASTValueStringVariable(r.node<ASTVariable>()),
  ),

  ASTNodeCodec<ASTValueStringConcatenation>(
    ASTNodeTag.valueStringConcatenation,
    'ASTValueStringConcatenation',
    encode: (w, n) => w.nodes(n.values),
    decode: (r) => ASTValueStringConcatenation(r.nodeList<ASTValue<String>>()),
  ),

  ASTNodeCodec<ASTValuesListAsString>(
    ASTNodeTag.valuesListAsString,
    'ASTValuesListAsString',
    encode: (w, n) => w.nodes(n.values),
    decode: (r) => ASTValuesListAsString(r.nodeList<ASTValue>()),
  ),

  ASTNodeCodec<ASTValueAsString>(
    ASTNodeTag.valueAsString,
    'ASTValueAsString',
    encode: (w, n) => w.node(n.value),
    decode: (r) => ASTValueAsString(r.node<ASTValue>()),
  ),

  // --- Containers -----------------------------------------------------------
  // 3D before 2D before 1D: they are an inheritance chain.
  ASTNodeCodec<ASTValueArray3D>(
    ASTNodeTag.valueArray3D,
    'ASTValueArray3D',
    encode: (w, n) {
      w.type(_elementTypeOf(n.type, 3));
      w.nativeValue(n.value);
    },
    decode: (r) {
      var elementType = r.type();
      var raw = r.nativeValue() as List;
      return ASTValueArray3D(elementType, [
        for (var a in raw) [for (var b in a as List) (b as List)],
      ]);
    },
  ),

  ASTNodeCodec<ASTValueArray2D>(
    ASTNodeTag.valueArray2D,
    'ASTValueArray2D',
    encode: (w, n) {
      w.type(_elementTypeOf(n.type, 2));
      w.nativeValue(n.value);
    },
    decode: (r) {
      var elementType = r.type();
      var raw = r.nativeValue() as List;
      return ASTValueArray2D(elementType, [for (var a in raw) (a as List)]);
    },
  ),

  ASTNodeCodec<ASTValueArray>(
    ASTNodeTag.valueArray,
    'ASTValueArray',
    encode: (w, n) {
      w.type(_elementTypeOf(n.type, 1));
      w.nativeValue(n.value);
    },
    decode: (r) {
      var componentType = r.type();
      var raw = r.nativeValue() as List;
      return ASTValueArray(componentType, raw);
    },
  ),

  ASTNodeCodec<ASTValueMap>(
    ASTNodeTag.valueMap,
    'ASTValueMap',
    encode: (w, n) {
      var type = n.type as ASTTypeMap;
      w.type(type.keyType);
      w.type(type.valueType);
      w.nativeValue(n.value);
    },
    decode: (r) {
      var keyType = r.type();
      var valueType = r.type();
      var raw = r.nativeValue() as Map;
      return ASTValueMap(keyType, valueType, raw);
    },
  ),

  // --- Loosely typed statics ------------------------------------------------
  ASTNodeCodec<ASTValueVar>(
    ASTNodeTag.valueVar,
    'ASTValueVar',
    encode: (w, n) => w.nativeValue(n.value),
    decode: (r) => ASTValueVar(r.nativeValue() as Object),
  ),

  ASTNodeCodec<ASTValueObject>(
    ASTNodeTag.valueObject,
    'ASTValueObject',
    encode: (w, n) => w.nativeValue(n.value),
    decode: (r) => ASTValueObject(r.nativeValue() as Object),
  ),

  // Last of the family: the catch-all base every concrete static value extends.
  ASTNodeCodec<ASTValueStatic>(
    ASTNodeTag.valueStatic,
    'ASTValueStatic',
    encode: (w, n) {
      w.type(n.type);
      w.nativeValue(n.value);
    },
    decode: (r) {
      var type = r.type();
      return ASTValueStatic(type, r.nativeValue());
    },
  ),
];

/// The element type buried [rank] levels down an array type.
///
/// `ASTValueArray2D` and `ASTValueArray3D` take the *element* type and wrap it
/// themselves, so encoding their `type` directly and replaying it would add a
/// level of nesting on every round trip.
ASTType _elementTypeOf(ASTType type, int rank) {
  ASTType t = type;
  for (var i = 0; i < rank; ++i) {
    if (t is! ASTTypeArray) return t;
    t = t.componentType;
  }
  return t;
}
