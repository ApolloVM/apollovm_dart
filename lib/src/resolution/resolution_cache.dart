// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dependency_graph.dart';
import 'module_resolver.dart';

/// Caches resolved modules by their canonical id, and invalidates only the
/// modules affected by a change (the changed module plus its transitive
/// importers) so re-resolution is incremental.
class ResolutionCache {
  final Map<String, ResolvedModule> _modules = <String, ResolvedModule>{};

  ResolvedModule? get(String moduleId) => _modules[moduleId];

  bool contains(String moduleId) => _modules.containsKey(moduleId);

  void put(ResolvedModule module) => _modules[module.moduleId] = module;

  Iterable<ResolvedModule> get all => _modules.values;

  int get length => _modules.length;

  /// Drops [moduleId] and every module that transitively imports it (per
  /// [graph]). Returns the set of invalidated module ids.
  Set<String> invalidate(String moduleId, DependencyGraph graph) {
    var affected = graph.affectedBy(moduleId);
    for (var id in affected) {
      _modules.remove(id);
    }
    return affected;
  }

  void clear() => _modules.clear();
}
