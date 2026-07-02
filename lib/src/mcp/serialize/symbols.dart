// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:apollovm/apollovm.dart';

import 'ast_json.dart';

/// Builds a symbol graph from a parsed [ASTRoot]: top-level functions and
/// classes (with their fields, methods and constructors). Pure introspection —
/// no execution required.
Map<String, Object?> symbolsToJson(ASTRoot root) {
  List<Map<String, Object?>> invocables(Iterable<ASTFunctionSet> sets) => [
    for (var set in sets)
      for (var f in set.functions) invocableToJson(f),
  ];

  return <String, Object?>{
    'namespace': root.namespace,
    'imports': root.imports.map((i) => i.path).toList(),
    'functions': invocables(root.functions),
    'classes': [
      for (var clazz in root.classes)
        <String, Object?>{
          'name': clazz.name,
          'kind': clazz.kind.name,
          if (clazz.superClassName != null)
            'superClassName': clazz.superClassName,
          if (clazz.implementsTypes != null)
            'implements': clazz.implementsTypes,
          'fields': [
            for (var field in clazz.fields)
              <String, Object?>{
                'name': field.name,
                'type': typeToJson(field.type),
                'modifiers': modifiersToJson(field.modifiers),
              },
          ],
          'constructors': [
            for (var set in clazz.constructors)
              for (var c in set.functions) invocableToJson(c),
          ],
          'methods': invocables(clazz.functions),
        },
    ],
  };
}
