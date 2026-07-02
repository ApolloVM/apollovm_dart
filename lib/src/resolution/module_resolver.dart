// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import '../ast/apollovm_ast_statement.dart';
import '../ast/apollovm_ast_toplevel.dart';
import 'diagnostics.dart';
import 'module_loader.dart';
import 'symbol_table.dart';

/// The result of resolving one module: its own symbol table, the import scope
/// it sees, the modules it imports, and any diagnostics produced.
class ResolvedModule {
  final String moduleId;

  final String language;

  final ASTRoot root;

  /// This module's own top-level symbols (functions/classes/enums/aliases).
  final SymbolTable moduleScope;

  /// What this module can see through its imports.
  final ImportScope importScope;

  /// Canonical ids of modules this module imports.
  final List<String> importedModuleIds;

  final List<ImportDiagnostic> diagnostics;

  ResolvedModule({
    required this.moduleId,
    required this.language,
    required this.root,
    required this.moduleScope,
    required this.importScope,
    required this.importedModuleIds,
    required this.diagnostics,
  });

  @override
  String toString() =>
      'ResolvedModule{$moduleId, imports: $importedModuleIds, diagnostics: ${diagnostics.length}}';
}

/// Builds a module's own [SymbolTable] and, using a [ModuleLoader] and a
/// recursive resolver callback, its [ImportScope]. Language-agnostic: it only
/// reads the canonical AST (`ASTStatementImport`/`ASTStatementExport`).
class ModuleResolver {
  final ModuleLoader loader;

  /// Recursively resolves a module by id (memoized by the engine). Used to pull
  /// a target module's exported symbols when building this module's imports.
  final ResolvedModule? Function(String moduleId, {String? language}) resolveDependency;

  ModuleResolver(this.loader, this.resolveDependency);

  /// Builds the [SymbolTable] of a module's own declared top-level symbols.
  SymbolTable buildModuleScope(
    String moduleId,
    ASTRoot root, {
    SymbolTable? parent,
  }) {
    var table = SymbolTable(
      SymbolScopeLevel.module,
      parent: parent,
      moduleId: moduleId,
    );

    for (var f in root.functions) {
      var set = root.getFunctionWithName(f.name);
      if (set != null) {
        table.define(ResolvedSymbol(
          name: f.name,
          kind: SymbolKind.function,
          moduleId: moduleId,
          declaration: set,
        ));
      }
    }

    for (var clazz in root.classes) {
      table.define(ResolvedSymbol(
        name: clazz.name,
        kind: clazz is ASTClassEnum
            ? SymbolKind.enumeration
            : (clazz.isInterface ? SymbolKind.interface : SymbolKind.klass),
        moduleId: moduleId,
        declaration: clazz,
      ));
    }

    for (var alias in root.typeAliases) {
      table.define(ResolvedSymbol(
        name: alias.name,
        kind: SymbolKind.typeAlias,
        moduleId: moduleId,
        declaration: alias,
      ));
    }

    return table;
  }

  /// The exported symbols of a resolved module (honoring explicit exports and
  /// re-exports). [visiting] guards against cycles in re-export chains.
  Map<String, ResolvedSymbol> exportedSymbolsOf(
    ResolvedModule module, {
    Set<String>? visiting,
  }) {
    visiting ??= <String>{};
    if (!visiting.add(module.moduleId)) return const {};

    var exported = <String, ResolvedSymbol>{};

    var exportedNames = module.root.exportedSymbolNames;
    for (var name in exportedNames) {
      var sym = module.moduleScope.lookupFirst(name);
      if (sym != null) exported[name] = sym;
    }

    // Re-exports from other modules: `export ... from 'path'`.
    for (var export in module.root.exports) {
      var path = export.path;
      if (path == null) continue;

      var targetId = loader.resolveModuleId(
        path,
        fromModule: module.moduleId,
        language: module.language,
      );
      if (targetId == null) continue;

      var target = resolveDependency(targetId, language: module.language);
      if (target == null) continue;

      var targetExports = exportedSymbolsOf(target, visiting: visiting);
      for (var entry in targetExports.entries) {
        if (!_exportSelects(export, entry.key)) continue;
        var localName = _exportLocalName(export, entry.key);
        exported[localName] = entry.value.withName(localName);
      }
    }

    return exported;
  }

  bool _exportSelects(ASTStatementExport export, String name) {
    if (export.symbols.isNotEmpty) {
      return export.symbols.any((s) => s.name == name);
    }
    var visible = true;
    for (var c in export.combinators) {
      if (c.isShow) {
        visible = c.names.contains(name);
      } else if (c.names.contains(name)) {
        visible = false;
      }
    }
    return visible;
  }

  String _exportLocalName(ASTStatementExport export, String name) {
    for (var s in export.symbols) {
      if (s.name == name) return s.localName;
    }
    return name;
  }

  /// Populates [module]'s [ImportScope], imported-ids, and diagnostics from its
  /// imports. The module (with its own [moduleScope] already built) must be
  /// registered in the engine cache before this runs, so cyclic imports resolve
  /// against each other's own exported symbols instead of recursing forever.
  void resolveImports(ResolvedModule module) {
    var moduleId = module.moduleId;
    var language = module.language;
    var root = module.root;
    var diagnostics = module.diagnostics;
    var importScope = module.importScope;
    var importedIds = module.importedModuleIds;

    // Invalid-export diagnostics for this module's own exports.
    for (var missing in root.exportNamesNotDeclared()) {
      diagnostics.add(ImportDiagnostic.invalidExport(moduleId, missing));
    }

    for (var import in root.imports) {
      // Core packages are handled by the runtime ApolloImportManager; skip here
      // but do not flag them as missing.
      if (loader.resolveCorePackage(import.path) != null) continue;

      var targetId = loader.resolveModuleId(
        import.path,
        fromModule: moduleId,
        language: language,
      );

      if (targetId == null) {
        diagnostics.add(ImportDiagnostic.missingModule(moduleId, import.path));
        continue;
      }

      var target = resolveDependency(targetId, language: language);
      if (target == null) {
        diagnostics.add(ImportDiagnostic.missingModule(moduleId, import.path));
        continue;
      }

      importedIds.add(targetId);

      var targetExports = exportedSymbolsOf(target);

      // Whole-module alias: `import 'x' as p;` / `import * as p`.
      if (import.prefix != null) {
        var table = SymbolTable(
          SymbolScopeLevel.module,
          moduleId: targetId,
        );
        for (var entry in targetExports.entries) {
          table.define(entry.value.withName(entry.key));
        }
        importScope.prefixed[import.prefix!] = table;
        // A prefixed import may ALSO be selective in some languages; but the
        // common case binds the whole module under the prefix.
        continue;
      }

      // Named/show/hide/wildcard: merge selected symbols into the flat scope.
      for (var entry in targetExports.entries) {
        var exportedName = entry.key;

        // `importsSymbol` applies the named allow-list then show/hide clauses.
        if (!import.importsSymbol(exportedName)) continue;

        var localName = import.localNameOf(exportedName);
        var existing = importScope.named[localName];
        if (existing != null &&
            !identical(existing.declaration, entry.value.declaration)) {
          diagnostics.add(
            ImportDiagnostic.duplicateSymbol(moduleId, localName),
          );
          continue;
        }
        importScope.named[localName] = entry.value.withName(localName);
      }

      // Missing-symbol diagnostics: named symbols not exported by the target.
      for (var s in import.namedSymbols) {
        if (!targetExports.containsKey(s.name)) {
          diagnostics.add(
            ImportDiagnostic.missingSymbol(moduleId, import.path, s.name),
          );
        }
      }
    }
  }
}
