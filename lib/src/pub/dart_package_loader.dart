// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import '../apollovm_base.dart';
import '../ast/apollovm_ast_toplevel.dart';
import '../core/apollovm_core_base.dart';
import '../resolution/diagnostics.dart';
import '../resolution/module_loader.dart';
import 'package_provider.dart';

/// Fetches Dart `package:` imports through a [PackageProvider] and loads their
/// sources into an [ApolloVM] as modules, so the (synchronous) resolver can
/// then resolve them like any other loaded unit.
///
/// Because [ApolloVM.loadCodeUnit] is asynchronous (parsing is async), package
/// fetching cannot happen inside the synchronous [ModuleLoader.loadModule];
/// instead call [provision] as a pre-pass before [ApolloVM.resolve] / execution.
class DartPackageImporter {
  final ApolloVM vm;

  final PackageProvider provider;

  /// Language of the modules this importer loads (Dart packages).
  final String language;

  DartPackageImporter(this.vm, this.provider, {this.language = 'dart'});

  /// Whether a module with [moduleId] is already loaded in [vm].
  bool _isLoaded(String moduleId) =>
      vm.allCodeUnits(language).any((u) => u.id == moduleId);

  /// The `package:` imports declared by an already-loaded [root].
  Iterable<PackageUri> _packageImportsOf(ASTRoot root) => root.imports
      .map((i) => PackageUri.tryParse(i.path))
      .whereType<PackageUri>();

  /// Resolves and loads every `package:` import reachable from the currently
  /// loaded modules (transitively), returning any diagnostics (unresolved
  /// packages, or sources that ApolloVM's Dart subset can't parse).
  Future<List<ImportDiagnostic>> provision() async {
    var diagnostics = <ImportDiagnostic>[];
    var seen = <String>{};
    var queue = <PackageUri>[];

    // Seed from all currently-loaded modules' `package:` imports.
    for (var unit in vm.allCodeUnits(language)) {
      var root = unit.root;
      if (root == null) continue;
      for (var uri in _packageImportsOf(root)) {
        if (seen.add(uri.moduleId)) queue.add(uri);
      }
    }

    while (queue.isNotEmpty) {
      var uri = queue.removeLast();

      if (_isLoaded(uri.moduleId)) continue;

      PackageSource? pkgSource;
      try {
        pkgSource = await provider.resolvePackageUri(uri);
      } catch (e) {
        diagnostics.add(
          ImportDiagnostic(
            kind: ImportDiagnosticKind.missingModule,
            moduleId: uri.moduleId,
            message: "Failed to fetch package import '${uri.moduleId}': $e",
            importPath: uri.moduleId,
          ),
        );
        continue;
      }

      if (pkgSource == null) {
        diagnostics.add(
          ImportDiagnostic.missingModule(uri.moduleId, uri.moduleId),
        );
        continue;
      }

      var unit = SourceCodeUnit(
        language,
        pkgSource.source,
        id: pkgSource.moduleId,
      );

      try {
        await vm.loadCodeUnit(unit);
      } catch (e) {
        // Real-world package sources may use Dart features outside ApolloVM's
        // supported subset; record and keep going rather than aborting.
        diagnostics.add(
          ImportDiagnostic(
            kind: ImportDiagnosticKind.missingModule,
            moduleId: uri.moduleId,
            message:
                "Loaded package '${uri.moduleId}' but it couldn't be parsed by "
                "ApolloVM's Dart subset: $e",
            importPath: uri.moduleId,
            severity: ImportDiagnosticSeverity.warning,
          ),
        );
        continue;
      }

      // Enqueue the package's own `package:` imports (transitive).
      var root = unit.root;
      if (root != null) {
        for (var next in _packageImportsOf(root)) {
          if (seen.add(next.moduleId)) queue.add(next);
        }
      }
    }

    return diagnostics;
  }
}

/// A [ModuleLoader] for Dart projects that use `package:` imports.
///
/// Resolution delegates to the in-memory [VMModuleLoader] (already-loaded units
/// + core packages); package sources are brought into the VM by [provision]
/// (via a [PackageProvider]) before resolution runs. Web-safe: the filesystem/
/// network work lives entirely in the injected [PackageProvider].
class DartPackageLoader implements ModuleLoader {
  final ApolloVM vm;

  final PackageProvider provider;

  late final VMModuleLoader _base = VMModuleLoader(vm);

  late final DartPackageImporter importer = DartPackageImporter(vm, provider);

  DartPackageLoader(this.vm, this.provider);

  /// Fetches and loads all reachable `package:` imports; see
  /// [DartPackageImporter.provision].
  Future<List<ImportDiagnostic>> provision() => importer.provision();

  @override
  String? resolveModuleId(
    String importPath, {
    String? fromModule,
    String? language,
  }) => _base.resolveModuleId(
    importPath,
    fromModule: fromModule,
    language: language,
  );

  @override
  LoadedModule? loadModule(String moduleId, {String? language}) =>
      _base.loadModule(moduleId, language: language);

  @override
  CorePackageBase? resolveCorePackage(String importPath) =>
      _base.resolveCorePackage(importPath);
}
