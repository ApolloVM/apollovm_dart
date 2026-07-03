// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:apollovm/apollovm.dart';

/// Converts an arbitrary value produced by ApolloVM execution
/// (`ASTValue.getValueNoContext()`) into a JSON-safe structure
/// (`null` / `num` / `bool` / `String` / `List` / `Map<String, Object?>`).
///
/// Non-representable values (closures, unresolved futures, unknown objects)
/// degrade to their `toString()`. A [depth] guard prevents runaway recursion.
Object? valueToJson(Object? value, {int depth = 0, int maxDepth = 64}) {
  if (depth > maxDepth) return '$value';

  if (value == null || value is num || value is bool || value is String) {
    return value;
  }

  // A `VMObject` is an object instance with named fields.
  if (value is VMObject) {
    final fields = value.getFieldsValues();
    return <String, Object?>{
      r'$type': value.type.name,
      for (var e in fields.entries)
        e.key: valueToJson(e.value, depth: depth + 1, maxDepth: maxDepth),
    };
  }

  // Resolve ApolloVM value wrappers down to their native value.
  if (value is ASTValue) {
    final native = value.getValueNoContext();
    if (native is Future || identical(native, value)) return '$value';
    return valueToJson(native, depth: depth + 1, maxDepth: maxDepth);
  }

  if (value is Map) {
    return <String, Object?>{
      for (var e in value.entries)
        '${e.key}': valueToJson(e.value, depth: depth + 1, maxDepth: maxDepth),
    };
  }

  if (value is Iterable) {
    return [
      for (var e in value) valueToJson(e, depth: depth + 1, maxDepth: maxDepth),
    ];
  }

  // Fallback: a readable textual form.
  return '$value';
}
