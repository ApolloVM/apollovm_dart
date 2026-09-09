# Dart language support in ApolloVM — feature gaps

Which features of the **Dart language** ApolloVM's Dart front end (grammar +
interpreter) currently supports, and which are still missing.

The feature list follows the official
[Dart language evolution](https://dart.dev/resources/language/evolution) page,
version by version, plus a second table for core constructs that predate the
versioned evolution list (Dart 1.x / 2.0 baseline).

- **Measured against:** ApolloVM `2.30.0` (`lib/src/languages/dart/`), Dart SDK `3.13.3`.
- **Date:** 2026-09-08.
- **Method:** every row was probed by loading a minimal source unit through
  `ApolloVM.loadCodeUnit('dart', …)` and, when it parsed, executing it with the
  Dart runner — so a ✅ means *parsed and ran*, not "the grammar mentions it".
  A few constructs *parse* but mean something else to ApolloVM than to Dart;
  those are called out explicitly (⚠️) rather than counted as support.

Legend: ✅ supported · ⚠️ partial / different semantics · ❌ missing ·
➖ not a language feature, or nothing to implement (no language change in
that version, or a static-analysis-only change).

-----------------------------

## 1. By Dart language version

| Dart | Feature | ApolloVM | Notes |
|:--|:--|:--:|:--|
| 2.0  | Sound type system (subtyping) | ⚠️ | Declared types are enforced at runtime by **exact match**: `A a = B();` and passing a `B` to an `A` parameter both fail (`Can't cast value type (B) to variable type (A)`). Polymorphism works through `dynamic` and through element types (`List<A> l = [B()]`). |
| 2.1  | `int` literal where a `double` is expected | ✅ | `double d = 1;` runs. |
| 2.2  | Set literals (`{1, 2}`) | ❌ | `{ … }` is parsed as a map literal only; there is no `Set` type or literal. |
| 2.3  | Spread operator (`...`, `...?`) | ❌ | Not parsed in list or map literals. |
| 2.3  | Collection `if` | ❌ | `[1, if (c) 2]` does not parse. |
| 2.3  | Collection `for` | ❌ | `[for (var e in l) e]` does not parse. |
| 2.4  | Covariance of type variables in super-interfaces | ➖ | Static-checking rule; ApolloVM has no static subtype checker. The `covariant` modifier itself is **not parsed** (see table 2). |
| 2.5  | `dart:ffi` | ➖ | Library, not language — and out of scope for a sandboxed VM. |
| 2.6  | `Null` / `FutureOr<T>` subtype rule | ➖ | Static-checking rule. |
| 2.7  | Extension methods | ✅ | `extension X on T { … }`, named or unnamed, with methods, getters and setters; module-scoped, class members win over extension members. |
| 2.8–2.10 | — | ➖ | No language features. |
| 2.12 | Sound null safety (`T?`, `!`, `?.`, `?[`, `??`, `??=`) | ✅ | Parsed, interpreted, compiled to Wasm, translated to every target, plus the flow-aware analyzer exposed through the LSP. |
| 2.12 | `late` modifier | ⚠️ | Accepted and **dropped**: `late int x = 1;` runs, but initialization is eager and `late` without an initializer has no lazy semantics. |
| 2.13 | Generalized type aliases (`typedef X = T;`) | ⚠️ | `typedef IntMap = Map<String, int>;` parses, but the alias is not resolved when used as a type (`IntMap m = {…}` fails to cast). Generic aliases (`typedef F<T> = List<T>;`) do not parse. |
| 2.14 | Triple-shift operator (`>>>`) | ❌ | Not in the operator set (`~/`, `<<`, `>>` are). |
| 2.14 | Type arguments in annotations (`@Foo<int>()`) | ❌ | Fails to parse. Annotations in general are parsed and then discarded (they do not survive a round-trip). |
| 2.15 | Constructor tear-offs (`A.new`, `A.named`) | ❌ | `var c = A.new;` fails (`Can't find class[A] getter[new]`). Plain function tear-offs are missing too — see table 2. |
| 2.16 | — | ➖ | No language features. |
| 2.17 | Enhanced enums (fields, constructors, methods) | ⚠️ | Constructor arguments, fields and methods work (`enum E { a(1); final int v; const E(this.v); int twice() => …}`), plus `.index`, `.name`, `E.values`. A **getter inside an enum body** (`int get i => index;`) does not parse. |
| 2.17 | Super-initializer parameters (`B(super.x)`) | ❌ | Does not parse (no constructor initializer list at all). |
| 2.17 | Named arguments anywhere in the argument list | ✅ | `g(b: 1, 2)` runs. |
| 2.18 | Inference flowing between arguments of a generic call | ❌ | No generic inference engine; generics are erased at runtime. |
| 2.19 | Unnamed libraries (`library;`) | ❌ | Does not parse. `library foo;` *appears* to parse only because it matches a top-level variable declaration (type `library`, name `foo`) — a false positive, not support. |
| 3.0  | **Records** (`(1, 'a')`, `(int, String)`) | ❌ | Neither record literals nor record types parse. |
| 3.0  | **Patterns** (declaration, list/map/object/record patterns, `case` patterns, `when` guards) | ❌ | None parse. `switch` supports constant `case` labels only. |
| 3.0  | Switch expressions (`switch (x) { 1 => … }`) | ❌ | Statement form only. |
| 3.0  | If-case (`if (x case int n)`) | ❌ | Does not parse. |
| 3.0  | Class modifiers (`sealed`, `final`, `base`, `interface`, `mixin class`) | ❌ | Only `abstract class`, `extends` and `implements` are parsed (`ASTClassKind` = normal / abstract / interface). |
| 3.1  | — | ➖ | No language features. |
| 3.2  | Type promotion of private final fields | ❌ | The null-safety analyzer promotes locals and parameters, not fields. |
| 3.3  | **Extension types** (`extension type E(int i)`) | ❌ | Does not parse. |
| 3.4  | Type-analysis refinements | ➖ | Static-analysis only. |
| 3.5  | — | ➖ | No language features. |
| 3.6  | Digit separators (`1_000_000`) | ❌ | The number lexer accepts digits only. (Hex literals `0xFF` are missing too — the lexer defines a hex token that the grammar never uses.) |
| 3.7  | Wildcard variables (`_` non-binding) | ❌ | `_` binds like an ordinary name, so two `_` in one scope fail: `Variable '_' already declared`. |
| 3.8  | Null-aware elements (`[?maybe]`) | ❌ | Does not parse. |
| 3.9  | Null-safety assumptions for promotion/reachability | ➖ | Analyzer behaviour. |
| 3.10 | Dot shorthands (`E e = .a;`) | ❌ | Does not parse. |
| 3.11 | — | ➖ | No language features. |
| 3.12 | Private named parameters (`A({required this._x})`) | ❌ | The declaration parses, but the leading underscore is **not** stripped: callers must write `A(_x: 3)`; the Dart-correct `A(x: 3)` fails to resolve the constructor. |
| 3.13 | Primary constructors (`class A(final int x) {}`) | ❌ | Only *appears* to parse — it matches a top-level **function** declaration whose return type is `class` — and instantiation then fails. |

-----------------------------

## 2. Core language constructs (Dart 1.x / 2.0 baseline)

These predate the versioned evolution list, so they have no "Dart X.Y" row
above, but they are the largest part of the gap.

| Feature | ApolloVM | Notes |
|:--|:--:|:--|
| Named constructors (`A.named(…)`) | ❌ | The class body parser accepts one unnamed constructor per class (its name is fixed to `''`). |
| Factory constructors (`factory A.zero()`) | ❌ | The `factory` token exists in the lexer but is never used by the grammar. |
| Constructor initializer lists (`A(int v) : x = v`) | ❌ | Use `this.x` parameters or a constructor body instead. |
| Redirecting constructors (`A.zero() : this(0)`) | ❌ | Follows from the two rows above. |
| `super(…)` constructor calls | ❌ | A subclass cannot initialize inherited fields through the superclass constructor. |
| `const` constructors / canonicalization | ⚠️ | `const` is parsed and discarded; `const A(1)` builds an ordinary instance, with no compile-time constant evaluation or identity canonicalization. |
| Mixins (`mixin M { … }`, `class A with M`) | ❌ | Neither the declaration nor the `with` clause parses. |
| Operator overloading (`A operator +(A o)`) | ❌ | The `operator` token exists in the lexer but is unused. |
| `is` / `is!` type tests | ❌ | Not in the expression grammar. |
| `as` casts | ❌ | `as` is parsed only as an `import … as prefix` clause. |
| Generators: `sync*` / `async*`, `yield`, `yield*` | ❌ | Only `async` functions are parsed; there is no `Stream`/`Iterable` generator support. |
| `await for` (async for-each) | ❌ | Does not parse. |
| Statement labels, labeled `break`/`continue`, `continue <label>` in `switch` | ❌ | `break`/`continue` are unlabeled only. |
| `covariant` parameters | ❌ | Does not parse. |
| `external` declarations | ❌ | Does not parse. |
| Hex / binary integer literals (`0xFF`) | ❌ | See the 3.6 row. |
| Symbol literals (`#foo`) | ❌ | Does not parse. |
| Generic methods / generic functions (`T first<T>(List<T> l)`) | ❌ | Type parameters are parsed on **classes** only. |
| Old-style function typedefs (`typedef int F(int a);`) | ❌ | Only the `typedef Name = Type;` form parses (see the 2.13 row). |
| `library` / `part` / `part of` directives | ❌ | Only `import` and `export` (with `show` / `hide` / `as`) are directives. |
| Top-level variables | ⚠️ | `int gx = 4;` parses and is recorded on the AST root, but the name does not resolve at runtime from either a function or a static method (`Can't find variable: 'gx'`). |
| Top-level getters/setters, `static` getters/setters | ❌ | Accessors are parsed on class and extension bodies only. |
| Unqualified getter read inside a class (`return value;`) | ❌ | Known limitation, documented in the README: use `this.value`. |
| Function tear-offs (`var f = g;`) | ❌ | A top-level function is not a value: `Can't find variable: 'g'`. |
| Callable objects (`class A { call(…) }`, then `a(1)`) | ❌ | The declaration parses; invoking the instance does not resolve. |
| Interface polymorphism (`A a = B();` where `B implements A`) | ❌ | Same exact-type restriction as the 2.0 row. |

-----------------------------

## 3. What already works

For contrast, the Dart constructs verified as parsing **and** running:
classes, fields (with initializers), unnamed constructors with `this.x` /
`required` / named / optional-positional / defaulted parameters, methods,
`static` members, `abstract`, `extends` with inherited members and
`super.method()`, generic **classes** and instantiation, enums (including rich
enums with constructor args, fields and methods), extensions, getters and
setters, closures and `Function`-typed parameters, `async` / `await`,
cascades, `try` / `on` / `catch` / `finally` / `throw` / `rethrow`, `assert`,
all control flow (`if`, `for`, `for-in`, `while`, `do-while`, `switch` on
`int` / `String`, `break`, `continue`), ternary and null-aware operators,
list & map literals (including `const` ones and nested generic types), string
interpolation, raw and triple-quoted strings, and `final` / `const` / `var`
locals.

-----------------------------

## 4. Scope note

This document is about **parsing and running Dart source**. A construct marked
✅ here still has separate coverage questions for the other two pipelines —
translation to the other eight languages, and Wasm compilation — which the
[README feature tables](../README.md#supported-features) track per target.
