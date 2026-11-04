# Dart language support in ApolloVM — feature gaps

Which features of the **Dart language** ApolloVM's Dart front end (grammar +
interpreter) currently supports, and which are still missing.

The feature list follows the official
[Dart language evolution](https://dart.dev/resources/language/evolution) page,
version by version, plus a second table for core constructs that predate the
versioned evolution list (Dart 1.x / 2.0 baseline).

- **Measured against:** ApolloVM `2.34.0` (`lib/src/languages/dart/`), Dart SDK `3.13.5`.
- **Date:** 2026-11-04 (the records, top-level variable, constructor, subtyping, type-test and getter rows; the rest was last probed on 2026-09-09 against `2.31.0`).
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
| 2.0  | Sound type system (subtyping) | ⚠️ | Runtime type checks follow the class hierarchy: a subclass or implementer goes in a variable, parameter, return value or field of its supertype (`A a = B();`), and a supertype is rejected in a subtype slot. What's missing is the *static* side: there is no compile-time subtype checker, and type arguments aren't compared across a hierarchy (generics are erased). |
| 2.1  | `int` literal where a `double` is expected | ✅ | `double d = 1;` runs. |
| 2.2  | Set literals (`{1, 2}`) | ✅ | `{1, 2}`, `<T>{}` and `Set<T>` as a type, with `length` / `contains` / `add` / `remove` / `for-in`; a bare `{}` stays an empty map. Generated for every target (Go and Lua through their idioms); compiled to Wasm (since 2.35.0) with distinct elements, `length` / `isEmpty` / `isNotEmpty` and printing. |
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
| 2.17 | Enhanced enums (fields, constructors, methods) | ✅ | Constructor arguments, fields, methods and accessors (`int get i => …`, `set x(v) { … }`), plus `.index`, `.name`, `E.values`. |
| 2.17 | Super-initializer parameters (`B(super.x)`) | ✅ | Positional, named (with `required`), defaulted, and in a primary constructor header; the value is assigned to the inherited field, through any depth of superclass. With an explicit `: super(…)` they are also passed to the superclass constructor; without one, no superclass constructor runs (see table 2). |
| 2.17 | Named arguments anywhere in the argument list | ✅ | `g(b: 1, 2)` runs. |
| 2.18 | Inference flowing between arguments of a generic call | ❌ | No generic inference engine; generics are erased at runtime. |
| 2.19 | Unnamed libraries (`library;`) | ❌ | Does not parse. `library foo;` *appears* to parse only because it matches a top-level variable declaration (type `library`, name `foo`) — a false positive, not support. |
| 3.0  | **Records** (`(1, 'a')`, `(int, String)`) | ✅ | Literals (positional, named, interleaved, `(1,)`) and types (`(int, String)`, `({int x})`, `(int, {String s})`, `(int,)`, nullable, inside collection types). Fields read as `r.$1` / `r.name`; structural `==` / `hashCode`; Dart's `toString`; `is` by shape and field types. Destructuring needs patterns (next row). Calling a method on a record (`r.toString()`) isn't supported — `'$r'` is. |
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
| 3.12 | Private named parameters (`A({required this._x})`) | ✅ | The leading `_` is stripped from the parameter name, so callers write `A(x: 3)` while the field stays `_x`. A name with no valid public form (`__x`, `_`) is left alone. |
| 3.13 | Primary constructors (`class A(final int x) {}`) | ⚠️ | The class-header form is supported — declaring (`var`/`final`) and plain parameters, named/optional groups, `required`, defaults, a `;` body — and is desugared into fields plus an ordinary constructor. A *named* primary constructor (`class A.custom(…)`), `class const A(…)` and the in-body `this : …` form are not yet parsed. Named constructors and initializer lists now exist (table 2); compile-time constants do not. |

-----------------------------

## 2. Core language constructs (Dart 1.x / 2.0 baseline)

These predate the versioned evolution list, so they have no "Dart X.Y" row
above, but they are the largest part of the gap.

| Feature | ApolloVM | Notes |
|:--|:--:|:--|
| Named constructors (`A.named(…)`) | ✅ | Declared with `this.x` formals, an initializer list and/or a body, private ones (`A._()`) included; called as `A.named(…)`, `new A.named(…)` or `const A.named(…)`, with positional and named arguments. Declaring only named constructors removes the unnamed one. |
| Factory constructors (`factory A.zero()`) | ✅ | Unnamed or named, with a block or `=> expr` body; the body runs like a static method and its returned value is the instance (an existing one included). A factory that returns nothing is a runtime error. *Redirecting* factories (`factory A() = B;`) do not parse. |
| Constructor initializer lists (`A(int v) : x = v`) | ✅ | `x = v` and `this.x = v` field initializers and `assert(cond[, msg])`, run in order after the initializing formals and before the body. |
| Redirecting constructors (`A.zero() : this(0)`) | ✅ | `this(…)` and `this.named(…)`; the target runs in full — formals, initializer list and body — on the same instance. Redirecting to a factory is a runtime error. |
| `super(…)` constructor calls | ✅ | An explicit `: super(…)` / `: super.named(…)` runs the superclass constructor in full, body included, before the subclass body, through any depth; super parameters are passed along. Without one, the implicit `super()` is made — from a declared constructor and from the default one. The rule is per language (the AST records the language it was parsed from): Java and C# make the same implicit call, while JS/TS/Python inherit a parent constructor instead (see the README, footnote 13). |
| `const` constructors / canonicalization | ⚠️ | `const` is parsed and discarded; `const A(1)` builds an ordinary instance, with no compile-time constant evaluation or identity canonicalization. |
| Mixins (`mixin M { … }`, `class A with M`) | ❌ | Neither the declaration nor the `with` clause parses. |
| Operator overloading (`A operator +(A o)`) | ❌ | The `operator` token exists in the lexer but is unused. |
| `is` / `is!` type tests | ✅ | At Dart's relational precedence (`a + b is int`, `x is A && y`, and `x is int ? a : b` stays a conditional). A subclass or implementer passes, `null` passes only a nullable type, an `int` is not a `double`. Generated as each target's idiom (README, footnote 21). Flow-based type promotion isn't modelled, but none is needed at run time: `if (a is B) a.onlyB()` dispatches on the runtime class. |
| `as` casts | ✅ | Returns the value unchanged when it is an instance, otherwise throws `ApolloVMCastException`. |
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
| Top-level variables | ⚠️ | Read and written from any function or method, from a class-method entry point, and across `import`. Names resolve lexically (a function never sees its caller's locals). Initialization is eager and in order, not lazy: an initializer reading a variable declared after it fails. |
| Top-level getters/setters, `static` getters/setters | ❌ | Accessors are parsed on class and extension bodies only. |
| Unqualified getter read inside a class (`return value;`) | ✅ | Own, inherited and extension getters; dispatches on the receiver like `this.value`; a local or parameter of the same name shadows it. |
| Function tear-offs (`var f = g;`) | ❌ | A top-level function is not a value: `Can't find variable: 'g'`. |
| Callable objects (`class A { call(…) }`, then `a(1)`) | ❌ | The declaration parses; invoking the instance does not resolve. |
| Interface polymorphism (`A a = B();` where `B implements A`) | ✅ | Through any depth of superclasses and superinterfaces (see the 2.0 row). |

-----------------------------

## 3. What already works

For contrast, the Dart constructs verified as parsing **and** running:
classes, fields (with initializers), unnamed and **named** constructors with
`this.x` / `required` / named / optional-positional / defaulted / **private
named** / **super** parameters, **initializer lists** (fields, `assert`,
`super(…)`, `this(…)`), **factory** constructors, **primary constructors** in
the class header, the **implicit `super()`**, methods,
`static` members, `abstract`, `extends` with inherited members and
`super.method()`, **subtype polymorphism** (`A a = B();`, interfaces included),
**`is` / `is!` / `as`**, generic **classes** and instantiation, enums (including
rich enums with constructor args, fields, methods and accessors), extensions,
getters and setters (including **bare getter reads** inside a member), closures
and `Function`-typed parameters, `async` / `await`,
cascades, `try` / `on` / `catch` / `finally` / `throw` / `rethrow`, `assert`,
all control flow (`if`, `for`, `for-in`, `while`, `do-while`, `switch` on
`int` / `String`, `break`, `continue`), ternary and null-aware operators,
list, map & **set** literals (including `const` ones and nested generic types),
string interpolation, raw and triple-quoted strings, `final` / `const` /
`var` locals, **top-level variables** (lexically scoped, across `import`),
and **records** (literals, types, `r.$1` / `r.name`, structural equality).

-----------------------------

## 4. Scope note

This document is about **parsing and running Dart source**. A construct marked
✅ here still has separate coverage questions for the other two pipelines —
translation to the other eight languages, and Wasm compilation — which the
[README feature tables](../README.md#supported-features) track per target.
