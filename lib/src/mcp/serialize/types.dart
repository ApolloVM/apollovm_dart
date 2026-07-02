// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:apollovm/apollovm.dart';

import 'ast_json.dart';

/// Well-known builtin/primitive type names (used to classify `kind`).
const _builtinTypeNames = <String>{
  'int', 'double', 'num', 'bool', 'String', 'Object', 'dynamic', 'void',
  'Null', 'var', 'List', 'Map', 'Set', 'Future', 'Function', 'Iterable',
};

/// Builds a deduplicated type table for a parsed [ASTRoot].
///
/// Every [ASTType] referenced by a signature, field, return type or class is
/// collected once (keyed by name) and classified as `class` (declared in this
/// unit), `builtin`, or `unknown`.
Map<String, Object?> typesToJson(ASTRoot root) {
  final collected = <String, ASTType>{};

  void add(ASTType type) {
    collected.putIfAbsent(type.name, () => type);
    final generics = type.generics;
    if (generics != null) {
      for (var g in generics) {
        add(g);
      }
    }
  }

  void addInvocable(ASTInvocableDeclaration inv) {
    add(inv.returnType);
    for (var p in inv.parameters.allParameters) {
      add(p.type);
    }
  }

  for (var set in root.functions) {
    for (var f in set.functions) {
      addInvocable(f);
    }
  }

  final declaredClasses = root.classesNames.toSet();

  for (var clazz in root.classes) {
    add(clazz.type);
    for (var field in clazz.fields) {
      add(field.type);
    }
    for (var set in clazz.functions) {
      for (var m in set.functions) {
        addInvocable(m);
      }
    }
    for (var set in clazz.constructors) {
      for (var c in set.functions) {
        addInvocable(c);
      }
    }
  }

  String kindOf(String name) {
    if (declaredClasses.contains(name)) return 'class';
    if (_builtinTypeNames.contains(name)) return 'builtin';
    return 'unknown';
  }

  final names = collected.keys.toList()..sort();

  return <String, Object?>{
    'types': [
      for (var name in names)
        <String, Object?>{...typeToJson(collected[name]!), 'kind': kindOf(name)},
    ],
  };
}
