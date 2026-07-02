// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import '../ast/apollovm_ast_toplevel.dart';
import 'dependency_graph.dart';
import 'diagnostics.dart';
import 'module_loader.dart';
import 'module_resolver.dart';
import 'resolution_cache.dart';
import 'symbol_table.dart';

/// Facade for the module-resolution subsystem. Owns the [ModuleLoader],
/// [DependencyGraph], [ResolutionCache], and [ModuleResolver], and exposes
/// memoized resolution, incremental invalidation, and aggregated diagnostics.
class ModuleResolutionEngine {
  final ModuleLoader loader;

  final DependencyGraph graph = DependencyGraph();

  final ResolutionCache cache = ResolutionCache();

  late final ModuleResolver _resolver;

  /// Modules currently being resolved (cycle guard).
  final Set<String> _inProgress = <String>{};

  ModuleResolutionEngine(this.loader) {
    _resolver = ModuleResolver(loader, resolveModule);
  }

  /// Resolves the module [moduleId] (memoized). Returns `null` if the module
  /// can't be loaded. Building the module's own symbol table and caching it
  /// *before* resolving its imports lets cyclic imports resolve against each
  /// other's exported symbols instead of recursing forever.
  ResolvedModule? resolveModule(String moduleId, {String? language}) {
    var cached = cache.get(moduleId);
    if (cached != null) return cached;

    // A module reached again while still resolving (cycle): return whatever is
    // registered; if nothing yet, load its scope now so exports are available.
    if (_inProgress.contains(moduleId)) {
      return cache.get(moduleId);
    }

    var loaded = loader.loadModule(moduleId, language: language);
    if (loaded == null) return null;

    _inProgress.add(moduleId);
    try {
      var moduleScope = _resolver.buildModuleScope(loaded.moduleId, loaded.root);

      var module = ResolvedModule(
        moduleId: loaded.moduleId,
        language: loaded.language,
        root: loaded.root,
        moduleScope: moduleScope,
        importScope: ImportScope(),
        importedModuleIds: <String>[],
        diagnostics: <ImportDiagnostic>[],
      );

      // Register before resolving imports (cycle-safe).
      cache.put(module);
      graph.addModule(loaded.moduleId);

      _resolver.resolveImports(module);

      graph.clearEdges(loaded.moduleId);
      for (var dep in module.importedModuleIds) {
        graph.addEdge(loaded.moduleId, dep);
      }

      // Attach the import scope + module id to the AST for runtime lookup.
      loaded.root.moduleId = loaded.moduleId;
      loaded.root.importScope = module.importScope;

      return module;
    } finally {
      _inProgress.remove(moduleId);
    }
  }

  /// Resolves every module id in [moduleIds] and returns the aggregated
  /// diagnostics (including circular-import diagnostics from the dependency
  /// graph).
  List<ImportDiagnostic> resolveAll(
    Iterable<String> moduleIds, {
    String? language,
  }) {
    for (var id in moduleIds) {
      resolveModule(id, language: language);
    }
    return diagnostics;
  }

  /// Invalidates [moduleId] and every module that transitively imports it, so
  /// the next [resolveModule] re-resolves only the affected subgraph.
  Set<String> invalidate(String moduleId) {
    var affected = cache.invalidate(moduleId, graph);
    for (var id in affected) {
      graph.clearEdges(id);
      var root = _rootOf(id);
      root?.importScope = null;
    }
    return affected;
  }

  ASTRoot? _rootOf(String moduleId) {
    var loaded = loader.loadModule(moduleId);
    return loaded?.root;
  }

  /// The import scope for [moduleId] (resolving it if necessary).
  ImportScope? importScopeFor(String moduleId, {String? language}) =>
      resolveModule(moduleId, language: language)?.importScope;

  /// Per-module diagnostics plus circular-import diagnostics derived from the
  /// current dependency graph.
  List<ImportDiagnostic> get diagnostics {
    var all = <ImportDiagnostic>[];
    for (var module in cache.all) {
      all.addAll(module.diagnostics);
    }
    for (var cycle in graph.findCycles()) {
      var label = cycle.join(' -> ');
      for (var member in cycle) {
        all.add(ImportDiagnostic.circularImport(member, label));
      }
    }
    return all;
  }

  bool get hasErrors => diagnostics.any((d) => d.isError);
}
