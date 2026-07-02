// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import '../ast/apollovm_ast_base.dart';
import '../ast/apollovm_ast_toplevel.dart';

/// The kind of a resolved [ResolvedSymbol]. Covers the symbol categories the
/// import system must resolve across all languages.
enum SymbolKind {
  variable,
  function,
  klass,
  interface,
  enumeration,
  typeAlias,
}

/// The four symbol-table scope levels, from widest to narrowest.
///
/// - [global]: built-in/core packages and VM-wide symbols.
/// - [package]: symbols shared across a package/namespace.
/// - [module]: a single module's own top-level declarations.
/// - [local]: block/function scope (delegated to the AST's `ASTBlock`).
enum SymbolScopeLevel { global, package, module, local }

/// A resolved symbol: a name bound to a top-level AST declaration in a module.
class ResolvedSymbol {
  /// The local (possibly aliased) name this symbol is bound to.
  final String name;

  final SymbolKind kind;

  /// The id of the module that declares this symbol.
  final String moduleId;

  /// The declaring AST node: an [ASTFunctionSet] (functions), [ASTClassNormal]
  /// (class/interface/enum), [ASTTypeAlias] (type alias), or a variable node.
  final ASTNode declaration;

  /// The whole-module import prefix this symbol was reached through (if any).
  final String? importPrefix;

  const ResolvedSymbol({
    required this.name,
    required this.kind,
    required this.moduleId,
    required this.declaration,
    this.importPrefix,
  });

  ResolvedSymbol withName(String newName) => ResolvedSymbol(
    name: newName,
    kind: kind,
    moduleId: moduleId,
    declaration: declaration,
    importPrefix: importPrefix,
  );

  @override
  String toString() =>
      'ResolvedSymbol{$name: ${kind.name} @ $moduleId${importPrefix != null ? ' (as $importPrefix)' : ''}}';
}

/// A chained symbol table for one [SymbolScopeLevel]. Lookups check this level
/// then walk up to [parent] (module → package → global).
///
/// Overloads are supported: a name maps to a list of [ResolvedSymbol]s.
class SymbolTable {
  final SymbolScopeLevel level;

  final SymbolTable? parent;

  /// The module this table belongs to, when [level] is [SymbolScopeLevel.module].
  final String? moduleId;

  final Map<String, List<ResolvedSymbol>> _symbols =
      <String, List<ResolvedSymbol>>{};

  SymbolTable(this.level, {this.parent, this.moduleId});

  /// Defines [symbol] at this level. Returns `false` if a distinct symbol with
  /// the same name+kind is already defined here (a duplicate).
  bool define(ResolvedSymbol symbol) {
    var list = _symbols.putIfAbsent(symbol.name, () => <ResolvedSymbol>[]);
    var duplicate = list.any(
      (s) =>
          s.kind == symbol.kind &&
          !identical(s.declaration, symbol.declaration),
    );
    list.add(symbol);
    return !duplicate;
  }

  /// Symbols defined at this exact level for [name] (no parent walk).
  List<ResolvedSymbol> lookupLocal(String name) =>
      _symbols[name] ?? const <ResolvedSymbol>[];

  /// Symbols for [name] at this level, or walking up to [parent].
  List<ResolvedSymbol> lookup(String name) {
    var here = _symbols[name];
    if (here != null && here.isNotEmpty) return here;
    return parent?.lookup(name) ?? const <ResolvedSymbol>[];
  }

  ResolvedSymbol? lookupFirst(String name) {
    var list = lookup(name);
    return list.isEmpty ? null : list.first;
  }

  bool contains(String name) =>
      _symbols.containsKey(name) || (parent?.contains(name) ?? false);

  Iterable<String> get names => _symbols.keys;

  @override
  String toString() =>
      'SymbolTable{level: ${level.name}, symbols: ${_symbols.length}}';
}

/// The set of symbols visible inside one importing module: unprefixed [named]
/// symbols and whole-module [prefixed] scopes (`import ... as p` → `p.member`).
///
/// Built by the module resolver and attached to the module's `ASTRoot` and the
/// runtime `VMContext`, so scoped resolution runs before the greedy fallback.
class ImportScope {
  /// Visible unprefixed name → symbol (merged from show/named/wildcard imports).
  final Map<String, ResolvedSymbol> named = <String, ResolvedSymbol>{};

  /// Import prefix → the imported module's exported symbol table.
  final Map<String, SymbolTable> prefixed = <String, SymbolTable>{};

  bool get isEmpty => named.isEmpty && prefixed.isEmpty;

  ResolvedSymbol? resolve(String name) => named[name];

  bool hasPrefix(String prefix) => prefixed.containsKey(prefix);

  ResolvedSymbol? resolvePrefixed(String prefix, String name) =>
      prefixed[prefix]?.lookupFirst(name);

  /// The declaration AST node for an unprefixed imported [name], or `null`.
  ASTNode? resolveNode(String name) => named[name]?.declaration;

  /// The imported function overload set for [name], or `null`.
  ASTFunctionSet? resolveFunctionSet(String name) {
    var s = named[name];
    if (s == null || s.kind != SymbolKind.function) return null;
    var d = s.declaration;
    return d is ASTFunctionSet ? d : null;
  }

  /// The imported class/interface/enum for [name], or `null`.
  ASTClassNormal? resolveClass(String name) {
    var s = named[name];
    if (s == null) return null;
    if (s.kind != SymbolKind.klass &&
        s.kind != SymbolKind.interface &&
        s.kind != SymbolKind.enumeration) {
      return null;
    }
    var d = s.declaration;
    return d is ASTClassNormal ? d : null;
  }

  /// The imported type alias for [name], or `null`.
  ASTTypeAlias? resolveTypeAlias(String name) {
    var s = named[name];
    if (s == null || s.kind != SymbolKind.typeAlias) return null;
    var d = s.declaration;
    return d is ASTTypeAlias ? d : null;
  }

  /// A prefixed member (`p.member`) resolved to its declaration node.
  ASTNode? resolvePrefixedNode(String prefix, String name) =>
      resolvePrefixed(prefix, name)?.declaration;

  ASTClassNormal? resolvePrefixedClass(String prefix, String name) {
    var s = resolvePrefixed(prefix, name);
    if (s == null) return null;
    var d = s.declaration;
    return d is ASTClassNormal ? d : null;
  }

  ASTFunctionSet? resolvePrefixedFunctionSet(String prefix, String name) {
    var s = resolvePrefixed(prefix, name);
    if (s == null || s.kind != SymbolKind.function) return null;
    var d = s.declaration;
    return d is ASTFunctionSet ? d : null;
  }

  @override
  String toString() =>
      'ImportScope{named: ${named.length}, prefixed: ${prefixed.keys.toList()}}';
}
