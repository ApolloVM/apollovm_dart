// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:apollovm/apollovm.dart';

import 'value_json.dart';

/// Serializes an [ASTType] to a JSON-safe map: `{name, generics?, superType?}`.
Map<String, Object?> typeToJson(ASTType type) {
  final generics = type.generics;
  final superType = type.superType;
  return <String, Object?>{
    'name': type.name,
    if (generics != null && generics.isNotEmpty)
      'generics': [for (var g in generics) typeToJson(g)],
    if (superType != null) 'superType': superType.name,
  };
}

/// Serializes an [ASTModifiers] to its active modifier list (e.g. `['static']`).
List<String> modifiersToJson(ASTModifiers modifiers) => modifiers.modifiers;

/// Serializes a parameters declaration to a list of `{name, type, optional?,
/// named?, hasDefault?}` maps (positional, then optional, then named).
List<Map<String, Object?>> parametersToJson(ASTParametersDeclaration params) {
  Map<String, Object?> one(
    ASTParameterDeclaration p, {
    required bool optional,
    required bool named,
  }) => <String, Object?>{
    'name': p.name,
    'type': typeToJson(p.type),
    if (optional) 'optional': true,
    if (named) 'named': true,
    if (p.defaultValue != null) 'hasDefault': true,
  };

  return <Map<String, Object?>>[
    for (var p in params.positionalParameters ?? const [])
      one(p, optional: false, named: false),
    for (var p in params.optionalParameters ?? const [])
      one(p, optional: true, named: false),
    for (var p in params.namedParameters ?? const [])
      one(p, optional: true, named: true),
  ];
}

/// Serializes an invocable declaration (function / method / constructor) to
/// `{name, returnType, modifiers, parameters}`.
Map<String, Object?> invocableToJson(ASTInvocableDeclaration inv) =>
    <String, Object?>{
      'name': inv.name,
      'returnType': typeToJson(inv.returnType),
      'modifiers': modifiersToJson(inv.modifiers),
      'parameters': parametersToJson(inv.parameters),
    };

/// Serializes any [ASTNode] into a JSON tree.
///
/// Every node contributes its concrete `runtimeType` as `node`, a set of
/// node-specific fields (see below), and — up to [maxDepth] — its `children`.
/// The walk is total: an unhandled node still yields `{node, children}`.
///
/// Note: ApolloVM AST nodes carry NO source positions (line/column), so none
/// are emitted here. Positions are available only for parse-error diagnostics.
Map<String, Object?> astNodeToJson(
  ASTNode node, {
  int depth = 0,
  int maxDepth = 200,
}) {
  final json = <String, Object?>{'node': node.runtimeType.toString()};

  switch (node) {
    case ASTRoot():
      json['namespace'] = node.namespace;
      json['classes'] = node.classesNames;
      json['functions'] = node.functions.map((f) => f.name).toList();
      json['imports'] = node.imports.map((i) => i.path).toList();
      if (node.extensions.isNotEmpty) {
        json['extensions'] = node.extensions
            .map((e) => e.name ?? 'on ${e.targetType.name}')
            .toList();
      }
    case ASTExtension():
      if (node.name != null) json['name'] = node.name;
      json['on'] = typeToJson(node.targetType);
    case ASTClassNormal():
      json['name'] = node.name;
      json['kind'] = node.kind.name;
      if (node.superClassName != null) {
        json['superClassName'] = node.superClassName;
      }
      if (node.implementsTypes != null) {
        json['implements'] = node.implementsTypes;
      }
      json['fields'] = node.fieldsNames;
      json['constructors'] = node.constructorsNames;
    case ASTInvocableDeclaration():
      json.addAll(invocableToJson(node));
    case ASTGetterDeclaration():
      json['name'] = node.name;
      json['returnType'] = typeToJson(node.returnType);
      json['modifiers'] = modifiersToJson(node.modifiers);
    case ASTClassField():
      json['name'] = node.name;
      json['type'] = typeToJson(node.type);
      json['modifiers'] = modifiersToJson(node.modifiers);
    case ASTType():
      json.addAll(typeToJson(node));
    case ASTStatementImport():
      json['path'] = node.path;
      if (node.prefix != null) json['prefix'] = node.prefix;
    case ASTValue():
      final native = node.getValueNoContext();
      if (native is! Future) {
        json['value'] = valueToJson(native);
      }
    case ASTVariable():
      json['name'] = node.name;
    default:
    // No extra fields; the generic node + children still describe it.
  }

  if (depth < maxDepth) {
    // `ASTNode.children` omits some container members: an `ASTRoot` does not
    // list its classes, and an `ASTClassNormal` lists only its methods (not its
    // fields or constructors). Augment the walk so the tree is complete.
    final children = <ASTNode>[
      ...node.children,
      ...switch (node) {
        // `ASTExtension.children` already lists its own methods and getters.
        ASTRoot() => [...node.imports, ...node.classes, ...node.extensions],
        ASTClassNormal() => [
          ...node.fields,
          for (final set in node.constructors) ...set.functions,
        ],
        _ => const <ASTNode>[],
      },
    ];
    if (children.isNotEmpty) {
      json['children'] = [
        for (var c in children)
          astNodeToJson(c, depth: depth + 1, maxDepth: maxDepth),
      ];
    }
  }

  return json;
}
