// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import '../core/apollovm_core_base.dart';
import 'module_loader.dart';

/// A [ModuleLoader] that delegates to a chain of [loaders], returning the first
/// non-null result for each operation. Web-safe: it adds no capabilities of its
/// own, only composition, so an optional (e.g. filesystem/pub) loader can be
/// layered on top of the in-memory [VMModuleLoader] without touching the core.
class CompositeModuleLoader implements ModuleLoader {
  final List<ModuleLoader> loaders;

  CompositeModuleLoader(this.loaders);

  @override
  String? resolveModuleId(
    String importPath, {
    String? fromModule,
    String? language,
  }) {
    for (var loader in loaders) {
      var id = loader.resolveModuleId(
        importPath,
        fromModule: fromModule,
        language: language,
      );
      if (id != null) return id;
    }
    return null;
  }

  @override
  LoadedModule? loadModule(String moduleId, {String? language}) {
    for (var loader in loaders) {
      var m = loader.loadModule(moduleId, language: language);
      if (m != null) return m;
    }
    return null;
  }

  @override
  CorePackageBase? resolveCorePackage(String importPath) {
    for (var loader in loaders) {
      var p = loader.resolveCorePackage(importPath);
      if (p != null) return p;
    }
    return null;
  }
}
