# ApolloVM Module Resolution & Package Import System

ApolloVM parses, runs, and transpiles source across many languages by
normalizing each into a **shared AST** (`lib/src/ast/`). This document describes
the language-agnostic package/module import and symbol-resolution subsystem: how
imports, exports, and symbols from one source file are resolved against another,
independent of the source language.

## Core concepts

| Concept | ApolloVM representation |
| --- | --- |
| **Package** | A namespace of code units (`CodeNamespace`), plus built-in **core packages** (`CorePackageBase`, e.g. `dart:math`) held in `CorePackageRegistry`. |
| **Module** | One parsed compilation unit — a `CodeUnit` and its `ASTRoot`. Identified by `CodeUnit.id` (usually a file path). |
| **Import** | The canonical `ASTStatementImport` node: `path` + optional `prefix` + `wildcard` + `combinators` (`show`/`hide`) + `namedSymbols` (with per-symbol aliases). |
| **Export** | The canonical `ASTStatementExport` node (named exports and re-exports), plus each `ASTRoot`'s computed `exportedSymbolNames`. |
| **Symbol resolution** | Four-level `SymbolTable`s + a per-module `ImportScope`, consulted at runtime before the greedy fallback. |

Every language's own import syntax normalizes into the **same** `ASTStatementImport`:

```text
Dart:        import 'user.dart' show User;   →  namedSymbols: [User]
TypeScript:  import { User } from './user';  →  namedSymbols: [User]
Python:      from user import User           →  namedSymbols: [User]
```

Whole-module aliases (`import 'x' as p`, `import * as p`) populate `prefix`
(+ `wildcard`); per-symbol aliases (`User as U`) populate `namedSymbols[i].alias`.

## Canonical AST additions (`lib/src/ast/`)

- `ASTStatementImport(path, {prefix, wildcard, combinators, namedSymbols})` —
  enriched additively; existing `ASTStatementImport(path)` / `(path, prefix:)`
  call sites keep compiling.
- `ASTImportCombinator` (`show`/`hide` + names), `ASTImportedSymbol` (name + alias).
- `ASTStatementExport({path, symbols, combinators})` — `path == null` re-exports
  this module's own symbols; a non-null `path` re-exports from another module.
- `ASTTypeAlias(name, targetType)` — the new "type alias" symbol kind (`typedef`,
  TS `type X = …`).
- `ASTRoot` tracks `imports`, `exports`, `typeAliases`, and computes
  `exportedSymbolNames` (default: all public top-level functions/classes/enums/
  type aliases; or exactly the explicitly-exported own symbols).

## Resolution layer (`lib/src/resolution/`) — web-safe, no `dart:io`

- **`ModuleLoader`** — pluggable strategy. The default **`VMModuleLoader`**
  resolves an import path to a loaded `CodeUnit.id` using pure string math
  (strips quotes, resolves `./`/`../` textually, matches by id or basename) plus
  the `CorePackageRegistry`. A filesystem-backed loader would be a separate,
  non-core implementation of this same interface.
- **`SymbolTable`** — one per scope level (`global` → `package` → `module` →
  `local`), chained via `parent`; overload-aware (a name maps to a list of
  `ResolvedSymbol`s). The `local` level defers to the AST's existing `ASTBlock`
  scope rather than duplicating it.
- **`ResolvedSymbol`** — name, `SymbolKind` (`variable`/`function`/`klass`/
  `interface`/`enumeration`/`typeAlias`), declaring module id, and the AST
  declaration node.
- **`ModuleResolver`** — builds a module's own `moduleScope`, then its
  `ImportScope` by pulling each imported module's exported symbols and filtering
  them by `namedSymbols`/`show`/`hide`/`wildcard`, applying aliases, and folding
  in transitive re-exports (cycle-guarded).
- **`ImportScope`** — flat `named` map (unprefixed imports) + `prefixed` map
  (`prefix → module SymbolTable`, for `p.member`). This is the object attached to
  the runtime for scoped lookup.
- **`DependencyGraph`** — nodes = modules, edges = imports.
  - **Cycle detection**: iterative **Tarjan SCC** — any SCC of size > 1 (or a
    self-edge) is a circular import. Resolution never aborts on a cycle: each
    module's own symbols are built and cached *before* its imports are resolved,
    so cyclic modules see each other's exports and links are made by name.
  - **Topological order**: **Kahn's algorithm** (dependencies before dependents);
    cyclic nodes are appended deterministically.
  - **Incremental**: `affectedBy(id)` = reverse reachability (the changed module
    plus every module that transitively imports it).
- **`ImportDiagnostic`** — structured diagnostics for the five error classes:
  `missingModule`, `missingSymbol`, `duplicateSymbol`, `circularImport`,
  `invalidExport`.
- **`ResolutionCache`** — caches `ResolvedModule`s by id; `invalidate(id, graph)`
  drops only `graph.affectedBy(id)`.
- **`ModuleResolutionEngine`** — the facade owning loader + graph + cache +
  resolver, exposing memoized `resolveModule`, `invalidate`, `importScopeFor`,
  and aggregated `diagnostics`.

## Runtime integration

Resolution plugs into execution without disturbing existing single-file behavior:

- Each `ASTRoot` gets a `moduleId` and an `ImportScope` (set by the engine). The
  scope is threaded onto the runtime `VMContext` when a module executes.
- **Functions**: `ASTRoot.getFunction` consults the import scope (unprefixed
  functions and imported class constructors) *after* local symbols and *before*
  the greedy/core fallback.
- **Prefixed calls** (`p.member(...)`): `ASTExpressionObjectFunctionInvocation`
  detects when the receiver is an import prefix and resolves the member (function
  or constructor) in the imported module.
- **Classes / types**: `ASTRoot.getNodeIdentifier` consults the import scope for
  imported classes/enums/interfaces/type aliases before core classes.
- Scoped resolution is strictly additive — it runs only when an `ImportScope` is
  present, and the pre-existing greedy resolver remains the final fallback, so
  all single-file programs behave exactly as before.

### Where resolution is triggered

- `ApolloVM.resolve({language})` resolves all loaded modules eagerly and returns
  aggregated diagnostics (for tooling/tests).
- `ApolloRunner.executeFunction` / `executeClassMethod` resolve the entry
  module lazily (memoized) before execution.
- `ApolloVM.loadCodeUnit` invalidates the affected subgraph when a `CodeUnit`
  is (re)loaded — the incremental hook.

## Language coverage

The canonical AST, resolver, graph, diagnostics, and runtime linking are
language-agnostic. The richer import/export/typedef **syntax** (named/`show`/
`hide`/wildcard/alias/re-export) is currently wired for parse+generate in
**Dart, TypeScript, and Python**. The other languages (Java, Kotlin, C#,
JavaScript, Lua, Go) keep their existing basic `path`[+`prefix`] imports and
compile unchanged against the enriched AST.

## Optional Dart package importer (`package:` imports)

The web-safe core resolves a `package:foo/bar.dart` import only against modules already
loaded into the VM. An **optional**, non-core importer (`package:apollovm/apollovm_pub.dart`,
kept out of the web-safe entrypoint) resolves `package:` imports against real pub packages
declared in a project's `pubspec`:

- **`PackageProvider`** — the pluggable fetch strategy:
  - **`PackageConfigProvider`** (default, zero extra deps): resolves via
    `.dart_tool/package_config.json` (generated by `dart pub get` from the pubspec, populated
    from pub.dev) → exact pub semantics.
  - **`PubDevProvider`** (opt-in, network): downloads package archives from a pub host
    (`https://pub.dev` by default, or a configurable/private host), extracts + caches them,
    honoring the pubspec version constraints (best-effort highest-satisfying version — not a
    full solver).
- **`DartPackageImporter.provision()`** / **`DartPackageLoader`** — an async pre-pass that
  fetches each reachable `package:` import (transitively) via the provider and loads its source
  into the VM as a `SourceCodeUnit`, after which the synchronous resolver links it like any
  other module. (`loadModule` is synchronous and parsing is async, so fetching happens in the
  pre-pass, not inside the loader.)
- Injected via `ApolloVM.moduleLoader`; usable from the CLI with `apollovm run --pub`
  (`--pub-host` selects the network provider, `--pub-cache` sets its cache dir).

```dart
import 'package:apollovm/apollovm.dart';
import 'package:apollovm/apollovm_pub.dart';

final loader = DartPackageLoader(vm, PackageConfigProvider());
vm.moduleLoader = loader;
await loader.provision();          // fetch + load `package:` imports
final diagnostics = vm.resolve(language: 'dart');
```

Scope: this resolves and loads package **source** so `package:` imports resolve and their
symbols are available (analysis/transpilation, plus best-effort execution). Arbitrary real-world
package code often exceeds ApolloVM's supported Dart subset and is reported as a (non-fatal)
diagnostic rather than executed.

## Extending

- **Add a core package**: `CorePackageRegistry.register('pkg:x', () => MyPackage())`.
- **Add a loader** (e.g. filesystem): implement `ModuleLoader` and construct a
  `ModuleResolutionEngine(myLoader)`, or set `ApolloVM.moduleLoader`.
- **Add a package fetch strategy**: implement `PackageProvider` (e.g. a git or monorepo
  resolver) and pass it to `DartPackageLoader`.
- **Add the rich syntax to another language**: extend its grammar's
  `compilationUnit`/import rule to populate the canonical `ASTStatementImport`
  fields, and its generator to emit them (see the Dart/TS/Python
  `*_grammar.dart` / `*_generator.dart` for the pattern).

See `example/apollovm_example_imports.dart` and `example/import_project/` for a
runnable multi-file demo.
