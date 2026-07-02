// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import '../apollovm_base.dart';
import '../ast/apollovm_ast_toplevel.dart';
import '../core/apollovm_core_base.dart';

/// A module resolved to its parsed [ASTRoot], identified by [moduleId].
class LoadedModule {
  final String moduleId;

  final String language;

  final ASTRoot root;

  LoadedModule(this.moduleId, this.language, this.root);

  @override
  String toString() => 'LoadedModule{$moduleId ($language)}';
}

/// Resolves import paths to modules. Pluggable so alternative strategies (e.g. a
/// filesystem loader) can be supplied without changing the resolver.
///
/// The default [VMModuleLoader] is **web-safe**: it resolves purely against
/// modules already loaded into an [ApolloVM] (plus core packages) using string
/// math — it never touches `dart:io`. A filesystem-backed loader would be a
/// separate, non-core implementation of this interface.
abstract class ModuleLoader {
  /// Normalizes [importPath] (optionally relative to [fromModule]) to the
  /// canonical id of a loadable module, or `null` if none matches.
  String? resolveModuleId(
    String importPath, {
    String? fromModule,
    String? language,
  });

  /// Loads the module with canonical id [moduleId], or `null`.
  LoadedModule? loadModule(String moduleId, {String? language});

  /// Resolves [importPath] to a built-in core package, or `null`.
  CorePackageBase? resolveCorePackage(String importPath);
}

/// Web-safe [ModuleLoader] that resolves imports against the [CodeUnit]s already
/// loaded into an [ApolloVM]. No filesystem access.
class VMModuleLoader implements ModuleLoader {
  final ApolloVM vm;

  VMModuleLoader(this.vm);

  @override
  CorePackageBase? resolveCorePackage(String importPath) =>
      CorePackageRegistry.resolve(_unquote(importPath));

  @override
  String? resolveModuleId(
    String importPath, {
    String? fromModule,
    String? language,
  }) {
    var path = _unquote(importPath);

    // A core package is its own canonical id.
    if (CorePackageRegistry.isCorePackage(path)) return path;

    var candidates = _candidatePaths(path, fromModule);

    var units = language != null
        ? vm.allCodeUnits(language)
        : vm.allCodeUnitsAllLanguages();

    // 1) Exact id match.
    for (var candidate in candidates) {
      for (var u in units) {
        if (u.id == candidate) return u.id;
      }
    }

    // 2) Basename (with or without extension) match.
    for (var candidate in candidates) {
      var candBase = _basename(candidate);
      var candStem = _stripExtension(candBase);
      for (var u in units) {
        var idBase = _basename(u.id);
        if (idBase == candBase || _stripExtension(idBase) == candStem) {
          return u.id;
        }
      }
    }

    return null;
  }

  @override
  LoadedModule? loadModule(String moduleId, {String? language}) {
    var units = language != null
        ? vm.allCodeUnits(language)
        : vm.allCodeUnitsAllLanguages();
    for (var u in units) {
      if (u.id == moduleId) {
        var root = u.root;
        if (root != null) return LoadedModule(u.id, u.language, root);
      }
    }
    return null;
  }

  /// Candidate normalized forms for [path], resolving `./` and `../` textually
  /// against [fromModule]'s directory (pure string math — no filesystem).
  List<String> _candidatePaths(String path, String? fromModule) {
    var candidates = <String>{path};

    // Strip a leading `package:scheme/` → the remainder.
    var schemeMatch = RegExp(r'^[a-zA-Z][\w.]*:(.+)$').firstMatch(path);
    if (schemeMatch != null) {
      candidates.add(schemeMatch.group(1)!);
    }

    // Resolve relative segments against the importing module's directory.
    if (path.startsWith('./') || path.startsWith('../')) {
      var baseDir = fromModule != null ? _dirname(fromModule) : '';
      candidates.add(_normalizeRelative(baseDir, path));
    }
    if (path.startsWith('./')) {
      candidates.add(path.substring(2));
    }

    return candidates.toList();
  }

  String _normalizeRelative(String baseDir, String rel) {
    var segments = <String>[if (baseDir.isNotEmpty) ...baseDir.split('/')];
    for (var seg in rel.split('/')) {
      if (seg == '.' || seg.isEmpty) continue;
      if (seg == '..') {
        if (segments.isNotEmpty) segments.removeLast();
      } else {
        segments.add(seg);
      }
    }
    return segments.join('/');
  }

  static String _unquote(String s) {
    s = s.trim();
    if (s.length >= 2) {
      var a = s[0], b = s[s.length - 1];
      if ((a == '"' && b == '"') || (a == "'" && b == "'")) {
        return s.substring(1, s.length - 1);
      }
    }
    return s;
  }

  static String _basename(String path) {
    var i = path.lastIndexOf('/');
    return i < 0 ? path : path.substring(i + 1);
  }

  static String _dirname(String path) {
    var i = path.lastIndexOf('/');
    return i < 0 ? '' : path.substring(0, i);
  }

  static String _stripExtension(String name) {
    var i = name.lastIndexOf('.');
    return i <= 0 ? name : name.substring(0, i);
  }
}
