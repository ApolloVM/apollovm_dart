## ApolloVM


[![pub package](https://img.shields.io/pub/v/apollovm.svg?logo=dart&logoColor=00b9fc)](https://pub.dartlang.org/packages/apollovm)
[![Null Safety](https://img.shields.io/badge/null-safety-brightgreen)](https://dart.dev/null-safety)
[![Codecov](https://img.shields.io/codecov/c/github/ApolloVM/apollovm_dart)](https://app.codecov.io/gh/ApolloVM/apollovm_dart)
[![Dart CI](https://github.com/ApolloVM/apollovm_dart/actions/workflows/dart.yml/badge.svg?branch=master)](https://github.com/ApolloVM/apollovm_dart/actions/workflows/dart.yml)
[![GitHub Tag](https://img.shields.io/github/v/tag/ApolloVM/apollovm_dart?logo=git&logoColor=white)](https://github.com/ApolloVM/apollovm_dart/releases)
[![New Commits](https://img.shields.io/github/commits-since/ApolloVM/apollovm_dart/latest?logo=git&logoColor=white)](https://github.com/ApolloVM/apollovm_dart/network)
[![Last Commits](https://img.shields.io/github/last-commit/ApolloVM/apollovm_dart?logo=git&logoColor=white)](https://github.com/ApolloVM/apollovm_dart/commits/master)
[![Pull Requests](https://img.shields.io/github/issues-pr/ApolloVM/apollovm_dart?logo=github&logoColor=white)](https://github.com/ApolloVM/apollovm_dart/pulls)
[![Code size](https://img.shields.io/github/languages/code-size/ApolloVM/apollovm_dart?logo=github&logoColor=white)](https://github.com/ApolloVM/apollovm_dart)
[![License](https://img.shields.io/github/license/ApolloVM/apollovm_dart?logo=open-source-initiative&logoColor=green)](https://github.com/ApolloVM/apollovm_dart/blob/master/LICENSE)

ApolloVM is a portable VM (native, JS/Web, Flutter) that can parse, translate, and execute multiple languages such as Dart, Java, Kotlin, Go, C#, JavaScript, TypeScript, Lua, and Python. It also provides on-the-fly compilation to Wasm.

-----------------------------

## Use Cases

- 🤖 **MCP tool for LLMs** — expose ApolloVM over MCP so an LLM can use it as a sandboxed reasoning scratchpad and validate generated code (parse, run, check output).
- 🔄 **Cross-language translation / porting** — translate and regenerate source between any supported languages to prototype, migrate, or share logic across stacks.
- 📱 **Embedded scripting in Dart/Flutter** — ship logic, UIs, and behavior that update live at runtime, with no rebuild or app-store redeploy.
- 📐 **Business rules & formulas** — define pricing, discounts, validation, and eligibility logic as editable rules in a real, familiar language, evaluated safely at runtime — no hardcoding or custom expression engine to build and maintain.
- 🔒 **Sandboxed execution** — run untrusted, user-supplied snippets isolated from the host, via the interpreter or compiled Wasm.
- ⚙️ **On-the-fly WebAssembly** — compile loaded source to portable Wasm modules at runtime (browser or native) without any external toolchain.
- 🎓 **Playgrounds & education** — build multi-language runners/REPLs that show the same program across languages and its translated output.
- 🧪 **Reference implementations / test oracles** — write an algorithm once, then run or emit it across language targets to cross-check behavior.
- 🌳 **Polyglot AST tooling** — parse multiple languages into one shared AST for analysis, transformation, and code generation.
- 🪶 **Small, multi-platform VM** — runs on native, web/JS, and Flutter; the CLI compiles to a self-contained native binary under 10 MB with all features included.

-----------------------------

## Live Example

Experience ApolloVM in action right from your browser:

- Explore the [ApolloVM Web Demo](https://apollovm.github.io/apollovm_web_example/)

If you prefer to run the demo on your local machine:
- Follow the step-by-step instructions available in the [GitHub Repository](https://github.com/ApolloVM/apollovm_web_example).

-----------------------------

## Supported Features

ApolloVM can **parse**, **execute** (interpret), and **translate** (cross-compile)
source code between all supported languages, and **compile to WebAssembly** on the fly.

### Languages

`Dart`, `Java 11`, `Kotlin`, `Go`, `C#`, `JavaScript`, `TypeScript`, `Lua` and `Python`.

Any supported language can be translated to any other (e.g. Java → Dart, C# → Python,
Kotlin → JavaScript, Go → Dart), and code can be regenerated back to its original language.

### Core capabilities

- **Parsing** of each language into a shared AST.
- **Execution**: a tree-walking interpreter runs the AST directly.
- **Translation**: regenerate the AST as source in any supported language.
- **Wasm compilation**: compile to WebAssembly, including `async`/`await` (via
  Asyncify), classes (fields, constructors, instance & `static` methods,
  `toString()` dispatch, `Object`/`dynamic` boxing), exceptions, closures,
  lists/maps and GC types.
- **Null safety**: nullable types (`T?`), `??` / `??=`, `?.` / `?[`, `!` and
  cascades — parsed from Dart, interpreted, compiled to Wasm and translated to
  every target, plus a flow-aware static analyzer surfaced through the LSP.
  See [Null safety](#null-safety).

### Control flow & operators

Legend: ✅ supported · 🧩 supported via the language's idiom · 🚧 not yet supported (exists in the
language but not implemented yet) · 🚫 not applicable (the language has no such construct).

The **Wasm** column shows what the on-the-fly WebAssembly compiler currently supports
(any source language is compiled through the same shared AST).

| Feature | Dart | Java | Kotlin | Go | C# | JS | TS | Lua | Python | Wasm |
|---|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|
| `if` / `else if` / `else`        | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `for` (C-style)                  | ✅ | ✅ | 🚫  | ✅ | ✅ | ✅ | ✅ | 🧩¹ | 🚫 | ✅ |
| `for-each` / `for-in`            | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `while`                          | ✅ | ✅ | ✅ | 🧩⁸ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `do` / `while`                   | ✅ | ✅ | ✅ | 🧩⁹ | ✅ | ✅ | ✅ | 🧩² | 🚫 | ✅ |
| `switch` / `case`                | ✅ | ✅ | 🧩³ | ✅ | ✅ | ✅ | ✅ | 🚫  | 🧩⁴ | ✅ |
| `break`                          | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `continue`                       | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 🚫  | ✅ | ✅ |
| `try` / `catch` / `finally`      | ✅ | ✅ | ✅ | 🚧 | ✅ | ✅ | ✅ | 🚫  | ✅ | ✅ |
| `throw` / `raise`                | ✅ | ✅ | ✅ | 🚧 | ✅ | ✅ | ✅ | 🚫  | ✅ | ✅ |
| `async` / `await`                | ✅ | 🚫  | 🧩⁷ | 🚫 | ✅ | ✅ | ✅ | 🚫  | ✅ | ✅ |
| Ternary (`? :`)                  | ✅ | ✅ | ✅ | 🧩¹⁰ | ✅ | ✅ | ✅ | 🚫  | ✅ | ✅ |
| Arithmetic (`+ - * / %`)         | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Comparison / logical             | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Bitwise (`& \| ^ << >> ~`)       | ✅ | ✅ | 🧩⁵ | 🧩¹¹ | ✅ | ✅ | ✅ | 🧩⁶ | ✅ | ✅ |
| `++` / `--`, compound assign     | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Lambdas / closures               | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Named / keyword arguments        | ✅ | 🚫  | ✅ | 🚫 | ✅ | 🚫  | 🚫  | 🚫  | ✅ | ✅ |
| Parameter default values         | ✅ | 🚫  | ✅ | 🚫 | ✅ | 🚫  | 🚫  | 🚫  | ✅ | ✅ |
| String interpolation / concat    | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| List & map / dict literals       | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Index access (`a[i]`, nested `m[i][j]`)¹² | ✅ | 🧩 | 🧩 | 🧩 | 🧩 | 🧩 | 🧩 | 🧩 | 🧩 | ✅ |
| `null` / `None` / `nil`¹³        | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 🧩¹³ |

¹ Lua numeric-for (`for i = a, b do`). &nbsp; ² Lua `repeat … until`. &nbsp;
³ Kotlin `when`. &nbsp; ⁴ Python `match` / `case`. &nbsp;
⁵ Kotlin bitwise are infix functions: `and`/`or`/`xor`/`shl`/`shr` and `.inv()`. &nbsp;
⁶ Lua bitwise use `&`/`|`/`~` (xor)/`<<`/`>>` and unary `~` (Lua 5.3). &nbsp;
⁷ Kotlin's async idiom is `suspend` / coroutines: ApolloVM generates `suspend fun`
(dropping `await`) when translating to Kotlin, but does not yet parse Kotlin `suspend`.
`await` unwraps the awaitable (`Future<T>` / `Promise<T>` / `Task<T>`) to `T`. &nbsp;
⁸ Go has no `while`; the condition-only `for cond {}` is used. &nbsp;
⁹ Go has no `do`/`while`; emitted as `for { … if !cond { break } }`. &nbsp;
¹⁰ Go has no `?:`/if-expression; ApolloVM emits an IIFE
`func() any { if c { return a } else { return b } }()`. &nbsp;
¹¹ Go bitwise use `&`/`|`/`^` (xor)/`<<`/`>>`, unary `^` for NOT and `&^` (AND-NOT).
`try`/`catch`/`throw` (Go uses `defer`/`recover`/`panic`) and `async`/`await`
(Go uses goroutines/channels) are not applicable / not implemented yet. &nbsp;
¹² Reading and writing list/map entries by index/key (`a[i]`, `m['k']`), including
compound assignment (`a[i] += 1`). **Chained/nested** access and assignment
(`m[0][1]`, `m['a']['b'] = v`) run on the shared interpreter and are parsed from
**Dart** source; the other languages currently parse a single `[...]` only (`🧩`),
with nested-index parsing being extended per grammar. &nbsp;
¹³ The null *literal* and its per-language spelling (`null` / `nil` / `None`).
Wasm has no null value of its own and represents it as a boxed pointer, so it is
`🧩` — see [Null safety](#null-safety) for the operators (`??`, `?.`, `!`, …) and
the Wasm limits.

### Null safety

Dart's null-safety surface — nullable types (`T?`), the null-coalescing operators
`??` / `??=`, null-aware access `?.` / `?[`, the null assertion `!`, and cascades
`..` / `?..` — is **parsed from Dart source** (the other grammars do not accept
this syntax yet), runs on the interpreter, compiles to Wasm within the limits
below, and is **translated to every target**.

Same legend as above, plus **⚠️** *lossy*: the construct is emitted in a form that
compiles but drops its null semantics (the null check is not performed).

| Feature | Dart | Java | Kotlin | Go | C# | JS | TS | Lua | Python | Wasm |
|---|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|
| Nullable type `T?`               | ✅ | 🚫 | ✅¹ | 🧩² | 🚫 | 🚫 | 🧩³ | 🚫 | 🚫 | 🧩⁴ |
| `??` (null-coalescing)           | ✅ | 🧩⁵ | ✅⁶ | 🧩⁷ | ✅ | ✅ | ✅ | 🧩⁸ | 🧩⁹ | 🧩⁴ |
| `??=` (null-coalescing assign)   | ✅ | 🧩⁵ | 🧩⁶ | 🚧¹⁰ | ✅ | ✅ | ✅ | 🧩⁸ | 🧩⁹ | 🧩⁴ |
| `?.` (null-aware access)         | ✅ | ⚠️ | ✅ | 🚧¹¹ | ⚠️ | ⚠️ | ✅ | ⚠️ | ⚠️ | 🧩⁴ |
| `?[` (null-aware index)          | ✅ | ⚠️ | ✅¹² | ⚠️ | ⚠️ | ⚠️ | ✅¹³ | ⚠️ | ⚠️ | 🧩⁴ |
| `!` (null assertion)             | ✅ | ⚠️ | ✅¹⁴ | 🧩¹⁵ | ⚠️ | ⚠️ | ✅ | ⚠️ | ⚠️ | 🧩⁴ |
| Cascades `..` / `?..`            | ✅ | 🧩 | 🧩 | 🧩 | 🧩 | 🧩 | 🧩 | 🧩 | 🧩 | 🚧 |
| `x == null` / `x != null`        | ✅ | ✅ | ✅ | ✅¹⁶ | ✅ | ✅ | ✅ | ✅¹⁷ | ✅¹⁸ | ✅ |
| Static null-safety analysis¹⁹    | ✅ | 🚫 | 🚫 | 🚫 | 🚫 | 🚫 | 🚫 | 🚫 | 🚫 | 🚫 |
| Enforce analysis at load²⁰       | ✅ | 🚫 | 🚫 | 🚫 | 🚫 | 🚫 | 🚫 | 🚫 | 🚫 | 🚫 |

¹ Kotlin renders the suffix natively (`Int?`). &nbsp;
² Go has no nullable value types: a `T?` is generated as a pointer `*T` — reads
deref (`(*a)`), `x == null` compares the pointer (`x == nil`), and a non-null
value takes its address through a generated `func goPtr[T any](v T) *T` helper
(Go cannot write `&5`). Types already nilable in Go are left alone, so a
`List<int>?` stays `[]int`, not `*[]int`. &nbsp;
³ TypeScript renders nullable *types* without the suffix — `T?` on a member is
not valid TS — while the null-aware *operators* are native. &nbsp;
⁴ Wasm has no null value of its own, so `null` is the boxed-`Object` pointer `0`.
That covers everything that stays boxed: a `var` / `Object?` local, a ternary
arm, a `List<Object>` element, `??`, `== null`, and string interpolation (which
prints `null`). A slot with a concrete Wasm type has no encoding for it — an
`int` is an i64 — and is reported as an `UnsupportedSyntaxError` naming the type
rather than compiled into a module that fails to validate. &nbsp;
⁵ Java has no null-coalescing operator; emitted as the ternary
`(a != null ? a : b)`, and `a ??= b` as `a = (a != null ? a : b)`. &nbsp;
⁶ Kotlin's null-coalescing is the Elvis operator `a ?: b`. It has no `??=`, so
that becomes `a = a ?: b`. &nbsp;
⁷ Go has no conditional *expression*, so `a ?? b` is an inline function that
nil-checks the pointer: `func() int { if a != nil { return *a }; return b }()`.
&nbsp;
⁸ Lua has no null-coalescing operator, and neither `a or b` nor the common
`a ~= nil and a or b` idiom is correct — Lua treats `false` as falsy, so a
non-nil `false` would wrongly fall through. It is emitted as an
immediately-invoked function with an explicit `nil` test, which also evaluates
the left operand only once. &nbsp;
⁹ Python uses a conditional expression testing `is not None`, so `0` / `''` /
`False` are preserved (an `or` shortcut would not). &nbsp;
¹⁰ Go's `??=` lowering (`t = t ?? v`) needs the target's element type to build
the inline function's return type, which the text-level assignment hook does not
have; it is reported as unsupported. Plain `??` is unaffected. &nbsp;
¹¹ In Go, degrading `?.` to `.` would both skip the nil check *and* yield a value
where a `*T` is expected, so it is reported rather than mis-emitted. &nbsp;
¹² Kotlin has no `?[` operator: null-aware element access is the call
`a?.get(i)`. &nbsp;
¹³ TypeScript's null-aware element access is `a?.[i]`, not `a?[i]`. &nbsp;
¹⁴ Kotlin's null assertion is `!!`. &nbsp;
¹⁵ Go's `a!` is the pointer dereference `(*a)`, which panics on `nil` — the same
shape as the assertion's throw. &nbsp;
¹⁶ Go compares the pointer directly (`a != nil`), without dereferencing. &nbsp;
¹⁷ Lua's null literal is `nil`. &nbsp; ¹⁸ Python's is `None`. &nbsp;
¹⁹ A pragmatic, flow-aware analyzer reports assigning `null` (or a nullable
value) to a non-nullable slot, and unconditional member/method/index access or
operator use on a nullable — with promotion for `if (x != null) { … }` /
`if (x == null) … else { … }`, and suppression via `?.` / `!` / `??`. Its
diagnostics are surfaced through the [LSP](#language-server-lsp) for Dart
documents. It analyzes top-level functions **and** class methods, constructors
and getters. &nbsp;
²⁰ `ApolloVM(nullSafetyChecks: true)` makes `loadCodeUnit` throw
`NullSafetyError` when the AST has null-safety **errors**, so a mistake fails at
resolution time instead of partway through a run:

```dart
var vm = ApolloVM(nullSafetyChecks: true);

// class Foo { static void main(int a, int? b) { print(a); var c = a + b; } }
await vm.loadCodeUnit(unit);
// NullSafetyError — nothing printed, nothing executed.
```

Off by default, so loading is unchanged unless you opt in. Only `error`-severity
findings block; warnings and info stay diagnostic-only. The thrown error carries
the offending `findings`.

> The `⚠️` cells are targets whose language has no equivalent construct: the
> access is emitted without its null check (`a?.x` becomes `a.x`, `a!` becomes
> `a`). The generated source compiles, but a null receiver behaves differently
> than in the source language. `??` / `??=` are never lossy — every target either
> has the operator or gets a faithful desugaring.

### Member-access chains

A chain of field/method accesses of any depth, in any mix of `.`, `?.` and `!`
(`a.b.c`, `a.b?.c`, `a.b!.c`, `a.b.m()`, `a.b?.m(x)`), plus chained writes
(`a.b.c = v`), a field read off a parenthesized receiver (`(a).v`, `(a)?.v`) and
a call followed by a field access (`(expr).m().field`), are parsed from **Dart**
source. Each segment folds onto the previous one and reuses the same
object-access nodes, so the runtime, null-aware and code-generation behaviour is
shared. The other grammars parse a single access segment only.

### Classes, types & OOP

Same legend and **Wasm** column semantics as the table above.

| Feature | Dart | Java | Kotlin | Go | C# | JS | TS | Lua | Python | Wasm |
|---|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|
| Classes                                                       | ✅ | ✅ | ✅ | 🧩⁷ | ✅ | ✅ | ✅ | 🚫  | ✅ | ✅ |
| Fields (with initializers)                                    | ✅ | ✅ | ✅ | 🧩⁸ | ✅ | ✅ | ✅ | 🧩¹ | ✅ | ✅ |
| Constructors & instantiation (`new Foo(...)` / `Foo(...)`)    | ✅ | ✅ | ✅ | 🧩⁹ | ✅ | ✅ | ✅ | 🧩¹ | ✅ | ✅ |
| Methods                                                       | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Static / visibility modifiers                                 | ✅ | ✅ | 🧩³ | 🧩¹⁰ | ✅ | 🧩² | ✅ | 🚫  | 🚫  | 🧩⁴ |
| Inheritance (`extends`) / superclass members¹³               | ✅ | ✅ | 🚧 | 🚧 | ✅ | ✅ | ✅ | 🚫  | ✅ | 🚧 |
| Enums (rich: ctor args, fields, methods)⁶                     | ✅ | ✅ | ✅ | 🚧 | ✅ | 🚫  | ✅ | 🚫  | ✅ | ✅⁶ |
| Generics (generic classes + instantiation + type erasure)    | ✅ | ✅ | ✅ | 🚧 | ✅ | 🚫  | ✅ | 🚫  | 🚫  | 🚧 |
| Type inference (`var` / `val` / `auto`)                       | ✅ | ✅ | ✅ | ✅ | ✅ | 🚫  | ✅ | 🚫  | 🚫  | ✅⁵ |
| Extensions (methods + getters)¹¹                              | ✅ | 🚫  | ✅ | 🚫  | 🧩¹² | 🚫  | 🚫  | 🚫  | 🚫  | 🚧 |

¹ Lua is table-based: "fields" are table entries (`obj.x`), "constructors" are factory/`setmetatable`
idioms, methods are `function Obj:method`. &nbsp;
² JavaScript has `static` but no visibility keywords (privacy is by convention/closures). &nbsp;
³ Kotlin `private`/`public` visibility round-trips; `internal`/`protected` are parsed but not preserved
yet; no `static` (uses `companion object`, not yet supported). &nbsp;
⁴ Wasm compiles `static` methods (exported as `Class.method`) and instance methods (called with a
receiver); only static methods are callable as entry points, with no source-level visibility. &nbsp;
⁵ Wasm consumes the already type-resolved AST, so `var`/`val`-typed code compiles unchanged. &nbsp;
⁶ Each enum entry is a `const` **instance** of the enum's class (Dart enhanced enums): `.index`,
`.name`, `EnumName.values`, identity `==`, plus rich-enum constructor args, fields and methods.
Java/Kotlin emit native rich enums; C#/TS/Python use a class + `static`-const-instances idiom; Wasm
compiles entries to heap instances (a method chained directly on an entry needs a variable first).
**Breaking change**: an entry is no longer an `int` — use `.index` (and `.value` for `= N` entries). &nbsp;
Generics are `🚫` for JS/Lua/Python: no static type syntax to parameterize. &nbsp;
⁷ Go has no classes; a class is modeled as a `type Name struct { ... }` plus receiver
methods `func (o *Name) m(...)` (the same idiom Lua uses for tables). &nbsp;
⁸ Go struct types can't carry inline field initializers, so initializers are moved into the
generated `NewName` factory. &nbsp;
⁹ Go constructors/instantiation use a `func NewName(...) *Name` factory (built around the
zero-valued composite literal `&Name{}`), and call sites read `NewName(...)`, since Go has
no `new`. Every struct gets a factory, so instantiation always resolves. Only the empty-brace
composite literal is parsed; field-initializing literals (`&Name{x: 1}`) are not. &nbsp;
¹⁰ Go has no `static`/visibility keywords: static methods become package-level `func`s and
visibility follows identifier capitalization. Inheritance, rich enums and generics
(Go embedding/`iota`/`[T any]`) are `🚧` — not implemented for Go yet. &nbsp;
¹¹ Members added to an existing type (a core type like `int`/`String`, or a user class) from
outside its declaration: Dart `extension E on T { ... }`, Kotlin top-level `fun T.m()` and
`val T.g: R get()`, C# `static class E { static R M(this T self) }`. A class member always wins
over an extension member, and an extension is visible only within its own module (not carried
across `import`). The languages marked `🚫` have no equivalent construct — prototype patching,
monkey patching and metatables are not the same thing — so generating an extension for them
throws `UnsupportedSyntaxError` rather than emitting a semantically different shim. &nbsp;
¹² C# has no extension *property*, so an extension declaring a getter cannot be emitted as C#;
its methods round-trip, with `this`/`self` translated both ways. &nbsp;
¹³ A subclass inherits its superclass's methods, fields, getters and `static`
fields; `super.method()` / `super.getter` / `super.field` reach the parent, and a
subclass override wins. Works for the languages that record their base class:
Dart, Java (`extends`), C# / TS / JS (`: Base` / `extends`), Python. Kotlin's
`class B : A()` base clause and Go embedding aren't parsed yet (`🚧`), and the
Wasm backend doesn't compile inheritance yet. Constructor initializer lists with
an explicit `: super(v)` call are not parsed yet — set inherited fields from the
constructor body or a `this.param`.

> Per-language behavior is normalized to a shared AST, so types and constructs map
> cleanly when translating between languages (e.g. C# `string` ⇄ Dart `String`,
> Java `List<Integer>` ⇄ Dart `List<int>`).

-----------------------------

## Command Line Usage

You can use the executable `apollovm` to `run`, `translate` or `compile` source
files, and to start the [MCP](#mcp-server) and [LSP](#language-server-lsp) servers.

First you should activate the package globally:

```shell
$> dart pub global activate apollovm
```

Now you can use the `apollovm` Dart executable:
```shell
$> apollovm help

ApolloVM - A compact VM for Dart, Java, Kotlin, Go, C#, JavaScript, TypeScript, Lua and Python.

Usage: apollovm <command> [arguments]

Global options:
-h, --help       Print this usage information.
-v, --version    Show ApolloVM version.

Available commands:
  compile     Compile a source file to a binary target (WebAssembly).
  lsp         Start the ApolloVM Language Server (LSP) over stdin/stdout.
  mcp         ApolloVM MCP (Model Context Protocol) server and tools.
  run         Run a source file.
  translate   Translate a source file.

Run "apollovm help <command>" for more information about a command.

```

To `run` a Java file: 
```shell
$> apollovm run -v test/hello-world.java foo
## [RUN]        File: 'test/hello-world.java' ; language: java11 > main( [foo] )
Hello World!
- args: [foo]
- a0: foo
```

To `translate` a Java file to Dart:

```shell
$> apollovm translate -v --target dart test/hello-world.java
## [TRANSLATE]  File: 'test/hello-world.java' ; language: java11 > targetLanguage: dart
<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test/hello-world.java" >>>>
class Hello {

  static void main(List<String> args) {
    var a0 = args[0];
    print('Hello World!');
    print('- args: $args');
    print('- a0: $a0');
  }

}
<<<< CODE_UNIT_END="/test/hello-world.java" >>>>
<<<< [SOURCES_END] >>>>
```

The same commands work for any supported language — the language is detected
from the file extension (`.dart`, `.java`, `.kt`, `.go`, `.cs`, `.js`, `.ts`,
`.lua`, `.py`), and `--target` accepts any of them.

### Compiling ApolloVM executable.

Dart supports compilation to native self-contained executables.

To have a fast and small executable of `ApolloVM`, just clone the project and compile it:

```shell

## Go to a directory to clone the project (usually a workspace):
$> cd ./some-workspace/

## Git clone the project:
$> git clone https://github.com/ApolloVM/apollovm_dart.git

## Enter the project:
$> cd ./apollovm_dart

## Compile ApolloVM executable:
$> dart compile exe bin/apollovm.dart

## Copy the binary to your preferred PATH:
$> cp bin/apollovm.exe /usr/bin/apollovm
```

Now you can use `apollovm` as a self-executable,
even if you don't have Dart installed.

-----------------------------

## Package Usage

The examples below load source code into the VM, execute it, and regenerate it
in another language. The first two (Dart and Java) show the full host code; the
host code is identical for every language — only the language id passed to
`SourceCodeUnit(...)` and `vm.createRunner(...)` changes.

### Language: `Dart`

Loading Dart source code, executing it, and then converting it to Java 11:

```dart
import 'package:apollovm/apollovm.dart';

void main() async {
  var vm = ApolloVM();

  var codeUnit = SourceCodeUnit(
          'dart',
          r'''
      
      class Foo {
      
          static int main(List<Object> args) {
            var title = args[0];
            var a = args[1];
            var b = args[2] ~/ 2;
            var c = args[3] * 3;
            
            if (c > 120) {
              c = 120 ;
            }
            
            var str = 'variables> a: $a ; b: $b ; c: $c' ;
            var sumAB = a + b ;
            var sumABC = a + b + c;
            
            print(str);
            print(title);
            print(sumAB);
            print(sumABC);
            
            // Map:
            var map = <String,int>{
            'a': a,
            'b': b,
            'c': c,
            'sumAB': sumAB,
            "sumABC": sumABC,
            };
            
            print('Map: $map');
            print('Map `b`: ${map['b']}');
            
            return map['sumABC'];
          }
          
      }
      
      ''',
          id: 'test');

  var loadOK = await vm.loadCodeUnit(codeUnit);

  if (!loadOK) {
    print("Can't load source!");
    return;
  }

  print('---------------------------------------');

  var dartRunner = vm.createRunner('dart')!;

  // Map the `print` function in the VM:
  dartRunner.externalPrintFunction = (o) => print("» $o");

  var astValue = await dartRunner.executeClassMethod(
    '',
    'Foo',
    'main',
    positionalParameters: [
      ['Sums:', 10, 30, 50]
    ],
  );

  var result = astValue.getValueNoContext();
  print('Result: $result');

  print('---------------------------------------');

  // Regenerate code in Java11:
  var codeStorageJava = vm.generateAllCodeIn('java11');
  var allSourcesJava = await codeStorageJava.writeAllSources();
  print(allSourcesJava);
}
```
*Note: the parsed function `print` was mapped as an external function.*

Output:
```text
---------------------------------------
» variables> a: 10 ; b: 15 ; c: 120
» Sums:
» 25
» 145
» Map: {a: 10, b: 15, c: 120, sumAB: 25, sumABC: 145}
» Map `b`: 15
Result: 145
---------------------------------------
<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
class Foo {

  static int main(Object[] args) {
    var title = args[0];
    var a = args[1];
    var b = args[2] / 2;
    var c = args[3] * 3;
    if (c > 120) {
        c = 120;
    }

    var str = "variables> a: " + a + " ; b: " + b + " ; c: " + c;
    var sumAB = a + b;
    var sumABC = a + b + c;
    print(str);
    print(title);
    print(sumAB);
    print(sumABC);
    var map = new HashMap<String,int>(){{
      put("a", a);
      put("b", b);
      put("c", c);
      put("sumAB", sumAB);
      put("sumABC", sumABC);
    }};
    print("Map: " + map);
    print("Map `b`: " + String.valueOf( map["b"] ));
    return map["sumABC"];
  }

}
<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
```

### Language: `Java 11`

Loading Java 11 source code, executing it, and then converting it to Dart:

```dart
import 'package:apollovm/apollovm.dart';

void main() async {
  var vm = ApolloVM();

  var codeUnit = SourceCodeUnit(
          'java11',
          r'''
            class Foo {
               static public void main(Object[] args) {
                 var title = args[0];
                 var a = args[1];
                 var b = args[2];
                 var c = args[3];
                 var sumAB = a + b ;
                 var sumABC = a + b + c;
                 print(title);
                 print(sumAB);
                 print(sumABC);
                 
                 // Map:
                 var map = new HashMap<String,int>(){{
                  put("a", a);
                  put("b", b);
                  put("c", c);
                  put("sumAB", sumAB);
                  put("sumABC", sumABC);
                }};
                 
                print("Map: " + map);
               }
            }
          ''',
          id: 'test');

  var loadOK = await vm.loadCodeUnit(codeUnit);

  if (!loadOK) {
    throw StateError('Error parsing Java11 code!');
  }

  var javaRunner = vm.createRunner('java11')!;

  // Map the `print` function in the VM:
  javaRunner.externalPrintFunction = (o) => print("» $o");

  await javaRunner.executeClassMethod('', 'Foo', 'main', positionalParameters: [
    ['Sums:', 10, 20, 30]
  ]);

  print('---------------------------------------');

  // Regenerate code:
  var codeStorageDart = vm.generateAllCodeIn('dart');
  var allSourcesDart = await codeStorageDart.writeAllSources();
  print(allSourcesDart.toString());
}
```

*Note: the parsed function `print` was mapped as an external function.*

Output:
```text
» Sums:
» 30
» 60
» Map: {a: 10, b: 20, c: 30, sumAB: 30, sumABC: 60}
---------------------------------------
<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
class Foo {

  static void main(List<Object> args) {
    var title = args[0];
    var a = args[1];
    var b = args[2];
    var c = args[3];
    var sumAB = a + b;
    var sumABC = a + b + c;
    print(title);
    print(sumAB);
    print(sumABC);
    var map = <String,int>{'a': a, 'b': b, 'c': c, 'sumAB': sumAB, 'sumABC': sumABC};
    print('Map: $map');
  }

}
<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
```

The remaining languages follow the same pattern, so only each language's source
snippet is shown. Two notes that apply below: instance (non-`static`) methods —
Kotlin's `greet`, Go receiver methods, Lua's `Foo:main`, Python's `self`
methods — need a class instance, provided via `classInstanceFields: const {}`;
and each language's native print (`println`, `fmt.Println`, …) is normalized to
the VM's `print`, mapped as an external function.

### Language: `Kotlin`

```kotlin
class Foo {
  fun greet(name: String, count: Int) {
    val msg = "Hello $name, you have $count messages."
    println(msg)
  }
}
```

Kotlin support reaches parity with the Java feature set: top-level and class `fun`
declarations, `val`/`var` with type inference, `if`/`else`, `for (x in …)`, `while`,
`listOf`/`mapOf` literals, and `"$x"` / `"${expr}"` string templates — all
translatable to Dart, Java or back to Kotlin.

### Language: `Go`

```go
type Foo struct {
}

func (o *Foo) greet(name string, count int) {
  msg := "Hello " + name + ", you have " + count + " messages."
  fmt.Println(msg)
}
```

Go is bidirectional: ApolloVM parses `.go`/`go` source into the AST, executes it, and
generates idiomatic Go — `package main` with an `import "fmt"` when needed, type-after-name
declarations (`func f(a int) int`, `x := …`), `for`-only control flow (`for cond {}` for
`while`, `for { … if !cond { break } }` for `do`/`while`, `for _, x := range xs {}` for
for-each), Go `switch` (no fall-through), slices/maps (`[]int{…}`, `map[K]V{…}`) and closures
(`func(x int) int { … }`). Classes map to the Go idiom — a `type Name struct { … }` plus
receiver methods `func (o *Name) m(...)` — so object-oriented code round-trips to and from
Dart, Java, Kotlin, C#, JavaScript, TypeScript and Python.

### Language: `JavaScript`

```javascript
class Foo {
  static greet(name, count) {
    let msg = `Hello ${name}, you have ${count} messages.`;
    print(msg);
  }
}
```

JavaScript is fully bidirectional: ApolloVM can parse `.js`/`javascript` source into
the AST, execute it, and generate idiomatic modern ES (`let`/`const`, template
literals, `for...of`, top-level functions, `===`/`!==`) from any loaded AST (Dart,
Java, or JavaScript).

### Language: `TypeScript`

TypeScript is supported as a superset of JavaScript: everything JavaScript supports,
plus **type annotations** (variables, parameters, return types, fields), **interfaces**,
**enums**, and **access modifiers** (`public`/`private`/`protected`/`readonly`/`static`/
`abstract`).

```typescript
class Foo {
  static greet(name: string, count: number): void {
    let msg: string = `Hello ${name}, you have ${count} messages.`;
    print(msg);
  }
}
```

TypeScript is bidirectional: ApolloVM parses `.ts`/`typescript` source (including
`interface`, `enum`, and member modifiers) into the AST, executes it, and generates
idiomatic TypeScript with type annotations. The same `interface`/`enum`/modifier
constructs are also supported in Dart (`abstract class`, `enum`, `static`/`final`),
so they cross-translate between Dart, TypeScript and JavaScript.

### Language: `Lua`

```lua
Foo = {}
Foo.__index = Foo

function Foo:main(title, a, b, c)
  local sumAB = a + b
  local sumABC = a + b + c
  print(title)
  print(sumAB)
  print(sumABC)
end
```

Lua is bidirectional: ApolloVM parses `.lua` source into the AST, executes it, and
generates idiomatic Lua (keyword-delimited blocks with `end`, `local` variables, `..`
concatenation, `and`/`or`/`not`/`~=`, and generic `for ... in ipairs(...)`) from any
loaded AST. Object-oriented code uses the conventional table + metatable form
(`Name = {}`, `Name.__index = Name`, `function Name:method(...)`), so classes round-trip
to and from Dart, Java, Kotlin, JavaScript and TypeScript.

### Language: `Python`

```python
class Foo:
    def greet(self, name, count):
        msg = f'Hello {name}, you have {count} messages.'
        print(msg)
```

Python is bidirectional: ApolloVM parses `.py`/`python` source into the AST, executes it,
and generates strict, idiomatic Python 3. Indentation-significant blocks are handled by an
INDENT/DEDENT/NEWLINE pre-tokenizer, and generation emits PEP-484 type hints when the AST
type is statically known (`def f(x: int) -> int:`, `x: str = ...`, `List[T]`/`Dict[K, V]`)
with a dynamic fallback. Supported constructs include functions, `self`-based methods and
`class` declarations, `if`/`elif`/`else`, `while`, `for ... in`, `try`/`except`/`finally`
with `raise`, lists & dicts, f-string interpolation, `//` integer division,
`and`/`or`/`not`, `True`/`False`/`None`, and `import`/`from ... import` — all
cross-translatable with Dart, Java, Kotlin, JavaScript, TypeScript and Lua.

## Wasm Support

ApolloVM can compile its AST tree to WebAssembly (Wasm). This means that parsed code loaded into the VM can be compiled
on the fly, without the need for any third-party tools.

- **Compiling** Wasm works everywhere, out of the box, with this package alone.
- **Executing** a compiled module needs a Wasm engine. Browsers have one built in. The Dart VM does not,
  so it needs [`apollovm_wasm`][apollovm_wasm_pub] — a separate package, so that the native/FFI toolchain
  it depends on is paid for only by those who actually run Wasm on the VM:

  ```dart
  import 'package:apollovm_wasm/apollovm_wasm.dart';

  void main() {
    registerApolloVMWasmRuntime(); // now `WasmRuntime()` executes on the VM
  }
  ```

  Without it, `WasmRuntime().isSupported` is `false` on the VM.

[apollovm_wasm_pub]: https://pub.dev/packages/apollovm_wasm

- **Status:** *Wasm support is under active development. It already compiles a broad subset of
the AST — functions, full control flow (`if`/`for`/`for-each`/`while`/`do-while`/`switch`/
`break`/`continue`/ternary), arithmetic/comparison/logical/bitwise operators, `try`/`catch`/`throw`,
classes, closures, lists/maps, `async`/`await` (via Asyncify), and `null` within
its boxed-`Object` domain; see the [feature table](#supported-features). Constructs not yet
compiled to Wasm are limited to a few higher-level features (e.g. non-integer `switch`),
and a `null` in a slot with a concrete Wasm type (an `int` is an i64) is reported as an
unsupported construct rather than mis-compiled — see [Null safety](#null-safety).*

Example compiling Dart code to WebAssembly (Wasm):
```dart
import 'dart:typed_data';
import 'package:apollovm/apollovm.dart';

void main() async {
  var wasmBytes = await compileToWasm('dart', '''
    
    int main( int a , double b ) {
      var x = (a + b) / 2 ;
      if (x > 1000) {
        return -1;
      }
      return x ;
    }
    
  ''');

  // Execute or save the compiled Wasm...
}

Future<Uint8List> compileToWasm(String codeLanguage, String code) async {
  var vm = ApolloVM();

  var codeUnit = SourceCodeUnit(codeLanguage, code, id: 'test');

  Object? loadError;
  var loadOK = false;
  try {
    loadOK = await vm.loadCodeUnit(codeUnit);
  } catch (e, s) {
    loadError = e;
  }

  if (!loadOK) {
    throw StateError(
            "Can't load source! Language: $codeLanguage\n\n$loadError");
  }

  var storageWasm = vm.generateAllIn<BytesOutput>('wasm');
  var wasmModules = await storageWasm.allEntries();

  var namespace0 = wasmModules.values.first;

  var wasmModule = namespace0.entries.first;
  var wasmOutput = wasmModule.value; // BytesOutput

  print(wasmOutput.toString()); // Show bytes description.

  var wasmBytes = wasmOutput.output();
  return wasmBytes;
}
```

Generated `Wasm` bytes with description:
```text

  ## Wasm Magic:
  [0 97 115 109]
  ## Version 1:
  [1 0 0 0]
  ## Section: Type:
      ## Section Type ID:
      [1]
      ## Bytes block length:
      [7]
      ## Functions signatures:
        ## Types count:
        [1]
          ## Type: function:
          [96]
          ## Parameters types:
          [2 126 124]
          ## Return value:
          [1 126]
  ## Section: Function:
      ## Section Function ID:
      [3]
      ## Bytes block length:
      [2]
      ## Functions type indexes:
      [1 0]
  ## Section: Export:
      ## Section Export ID:
      [7]
      ## Bytes block length:
      [8]
      ## Exported types:
        ## Exported types count:
        [1]
        ## Export function:
          ## Function name(`main`):
          [4 109 97 105 110]
          ## Export type(function):
          [0]
          ## Type index(0):
          [0]
  ## Section: Code:
      ## Section Code ID:
      [10]
      ## Bytes block length:
      [35]
      ## Functions bodies:
        ## Bodies count:
        [1]
          ## Bytes block length:
          [33]
          ## Function body:
              ## Local variables count:
              [1]
              ## Declared variable count:
              [1]
              ## Declared variable type(f64):
              [124]
                  ## [OP] local get: 0 $a:
                  [32 0]
                ## [OP] convert i64 to f64 signed:
                [185]
                  ## [OP] local get: 1 $b:
                  [32 1]
                ## [OP] operator: add(f64):
                [160]
                ## [OP] push constant(i64): 2:
                [66 2]
              ## [OP] convert i64 to f64 signed:
              [185]
              ## [OP] operator: divide(f64):
              [163]
              ## [OP] local set: 2 $x:
              [33 2]
                ## [OP] local get: 2 $x:
                [32 2]
                ## [OP] push constant(i64): 1000:
                [66 232 7]
              ## [OP] convert i64 to f64 signed:
              [185]
              ## [OP] operator: greaterThan(f64):
              [100]
              ## [OP] if ( x > (int) 1000 ):
              [4 64]
              ## [OP] push constant(i64): -1:
              [66 127]
              ## [OP] return value: (int) -1:
              [15]
              ## [OP] if end:
              [11]
              ## [OP] local get: 2 $x (return):
              [32 2]
              ## f64TruncateToI64Signed:
              [176]
              ## [OP] return variable: 2 $x:
              [15]
              ## Code body end:
              [11]

```

- NOTE: *When compiling to WebAssembly, ApolloVM keeps track of the stack and performs automatic type casting to facilitate operations between different types or return values.*

-----------------------------

## MCP Server

ApolloVM ships an **MCP (Model Context Protocol)** server that exposes the VM as a
programmable execution engine for AI agents. Agents can parse, execute, translate,
compile, and inspect code across all supported languages through MCP tools.

Start it over stdio (the standard local transport):

```bash
apollovm mcp serve
```

or over HTTP/SSE for networked agents:

```bash
apollovm mcp serve --http 8080          # binds 127.0.0.1:8080, SSE at /sse
```

Example MCP client configuration (e.g. for an agent/IDE):

```json
{
  "mcpServers": {
    "apollovm": { "command": "apollovm", "args": ["mcp", "serve"] }
  }
}
```

### `mcp` subcommands

| Subcommand | Purpose |
|------------|---------|
| `mcp serve` | Run the MCP server over stdio (default) or HTTP/SSE (`--http <port>`). |
| `mcp list` | List the available tools (names, descriptions, input schemas) as JSON. |
| `mcp call <tool>` | Invoke one tool once and print its JSON result — source via `--source`/`--file`/stdin, args via flags. Use it from scripts/CI with no MCP client. |
| `mcp info` | Print server metadata: version, MCP protocol, transports, languages, limits. |
| `mcp schema [tool]` | Print the JSON input schema(s) for one or all tools. |
| `mcp doctor` | Check the server/tools and report capabilities (e.g. whether the native `wasm_run` lib is available to run compiled Wasm). |

```bash
# Run a tool from the shell without an MCP client:
apollovm mcp call apollovm.execute --language dart \
  --source 'int main(List a){ print("hi"); return 42; }'

apollovm mcp call apollovm.translate --from go --to dart --file main.go
```

### Tools

| Tool | Input | Output |
|------|-------|--------|
| `apollovm.parse` | `language`, `source` | parse `ok`, `diagnostics`, `summary` (classes/functions/imports) |
| `apollovm.execute` | `language`, `source`, `function?`, `className?`, `args?`, `timeoutMs?` | `result`, `output` (console), `diagnostics` |
| `apollovm.translate` | `from`, `to`, `source` | `generated` source |
| `apollovm.ast` | `language`, `source`, `maxDepth?` | full AST as JSON |
| `apollovm.symbols` | `language`, `source` | symbol graph (functions/classes/fields/methods/constructors) |
| `apollovm.types` | `language`, `source` | deduplicated type table (`class`/`builtin`/`unknown`) |
| `apollovm.wasm` | `language`, `source` | WebAssembly modules as base64 bytes |

Supported `language` values: `dart`, `java`, `kotlin`, `go`, `csharp`, `javascript`,
`typescript`, `lua`, `python`, `wasm`.

#### Code-inspection tools (LSP)

The `apollovm.lsp.*` tools let an agent inspect code the way an editor does —
backed by ApolloVM's in-process Language Server (results carry precise LSP
line/character ranges). They accept the same `language` values above (except
`wasm`).

| Tool | Input | Output |
|------|-------|--------|
| `apollovm.lsp.diagnostics` | `language`, `source`, `uri?` | `diagnostics` (with ranges), `ok` |
| `apollovm.lsp.symbols` | `language`, `source`, `uri?` | document outline (nested symbols + ranges) |
| `apollovm.lsp.hover` | `language`, `source`, `line`, `character`, `uri?` | `hover` (signature, type, doc) |
| `apollovm.lsp.definition` | `language`, `source`, `line`, `character`, `uri?` | `definition` location |
| `apollovm.lsp.references` | `language`, `source`, `line`, `character`, `includeDeclaration?`, `uri?` | `references` |
| `apollovm.lsp.completion` | `language`, `source`, `line`, `character`, `uri?` | `completion` items |
| `apollovm.lsp.workspaceSymbols` | `query`, `files: [{uri, source, language?}]` | matching `symbols` across the files |

`apollovm.lsp.workspaceSymbols` takes multiple in-memory files, enabling
codebase-wide symbol search. See
[`example/apollovm_example_mcp_lsp.dart`](example/apollovm_example_mcp_lsp.dart).

### Workspace / repository tools

Start the server with `--workspace <dir>` to additionally expose tools that work
on **real files in a repository**, so a coding agent can explore, search,
navigate and version-control the codebase without shelling out to POSIX:

```bash
apollovm mcp serve --workspace .                       # read-only
apollovm mcp serve --workspace . --allow-write --allow-git-write
```

| Group | Tools | Replaces |
|-------|-------|----------|
| `apollovm.fs.*` | `read`, `list`, `find`, `stat`, `write`, `edit`, `mkdir`, `move`, `delete` | `cat`/`ls`/`find`/`sed`/`mv`/`rm` |
| `apollovm.search.*` | `text` (regex), `symbols` (**language-aware**) | `grep` |
| `apollovm.code.*` | `outline`, `definition`, `references`, `hover`, `diagnostics`, `workspaceSymbols` | editor navigation |
| `apollovm.git.*` | `status`, `diff`, `log`, `show`, `blame`, `add`, `commit`, `checkout`, `restore` | the `git` CLI |

`search.symbols` and `code.*` reuse ApolloVM's parsers/LSP, so they match
*declarations* (not comment/string text) with precise ranges. Everything is
**read-only by default**; writes and git mutations are opt-in
(`--allow-write` / `--allow-git-write`). Paths are confined to the workspace root
(`..`/absolute rejected), and `fs.edit` supports an `atLine` safety anchor. See
[`doc/MCP.md`](doc/MCP.md#workspace-tools) for details.

These tools are a thin JSON layer over a **standalone repository library** — the
features are **not MCP-exclusive**. A web IDE, editor, agent or test can use them
directly via `RepositoryService` (a typed façade over a pluggable
`RepositoryAdapter`):

```dart
import 'package:apollovm/apollovm_repository_io.dart'; // web: apollovm_repository.dart

final repo = RepositoryService(
  LocalRepositoryAdapter('.'),                 // or InMemoryRepositoryAdapter(files)
  config: const RepoConfig(allowWrite: true),
);
final outline = await repo.outline('lib/foo.dart');   // typed, language-aware
final hits = await repo.searchText('TODO', glob: 'lib/**');
print(await repo.gitStatus());
await repo.close();
```

`RepositoryAdapter` backends: `LocalRepositoryAdapter` (`dart:io` + `git`),
`InMemoryRepositoryAdapter` (web-safe), or a future remote/web backend — enabling
file edits and git commands from the browser. A `PermissionGuard` enforces the
`RepoConfig` uniformly across backends.

### Security model

- **File/network access is denied by construction** — executed code is only ever
  granted `print`; no filesystem or socket bridge is exposed, and tools operate on
  inline source strings only (never a path).
- **Timeout / CPU** — `apollovm.execute` runs inside a killable **isolate** by default,
  so a hard wall-clock timeout is enforced even against a runaway synchronous loop
  (`--timeout-ms`, default 5000). Other tools run in-process. Which tools use an
  isolate is configurable (`--isolate-tools`).
- **Input/output caps** — `--max-source-chars` (default 262144) and
  `--max-output-chars` (default 65536) bound request/response size.
- **Memory** — Dart has no per-isolate hard heap cap, so memory limiting is
  best-effort; run the process with `--old_gen_heap_size=<MB>` for a hard ceiling.

The embeddable API lives in `package:apollovm/apollovm_mcp.dart`
(`ApolloMcpServer`, `serveStdio`, `HttpSseTransport`, `McpLimits`). See
[`doc/MCP.md`](doc/MCP.md) for the full tool schemas and protocol notes.

-----------------------------

## Language Server (LSP)

ApolloVM ships a **Language Server (LSP 3.17)** for its supported languages,
included in the `apollovm` package as the separate library
`package:apollovm/apollovm_lsp.dart`.

Start it over stdio (for local editors):

```bash
apollovm lsp
```

The library imports no `dart:io`, so a browser IDE or an AI agent can embed the
server and drive it with decoded JSON-RPC messages via `MessageLspEndpoint`
(`StreamLspEndpoint` provides `Content-Length` framing for stdio/sockets):

```dart
import 'package:apollovm/apollovm_lsp.dart';

final endpoint = MessageLspEndpoint((msg) => hostPort.send(msg)); // outgoing
final server = LspServer(endpoint);
endpoint.receive(incomingMessage); // deliver each incoming JSON-RPC object
```

To *consume* the server, use `LspClient`. It correlates responses to requests,
streams server-pushed diagnostics, and offers typed helpers (`hover`,
`definition`, `documentSymbol`, `completion`, `references`, `documentHighlight`,
`prepareRename`, `rename`, `workspaceSymbol`). `LspClient.inProcess()` pairs a
client with a fresh server in the same isolate — no subprocess, no `dart:io`:

```dart
import 'package:apollovm/apollovm_lsp.dart';

final client = LspClient.inProcess();
client.diagnostics.listen((d) => print('${d.uri}: ${d.diagnostics.length} problems'));

await client.initialize();
client.initialized();
client.didOpen('file:///Foo.dart', source);

final hover = await client.hover('file:///Foo.dart', Position(2, 13));
print(hover?.contents.value);

await client.shutdown();
client.exit();
```

For an out-of-process server, wrap its transport instead —
`LspClient(StreamLspEndpoint(process.stdout, process.stdin))..start()`.

### In-process API — no socket, no handshake (web / agents)

For the simplest embedding, use **`LspService`**: a document-oriented facade
over an in-process server. There is no transport to wire, no socket to open and
no `initialize` handshake to run by hand — construct it, hand it code, ask
questions. Being `dart:io`-free, it runs unchanged in the browser.

```dart
import 'package:apollovm/apollovm_lsp.dart';

final lsp = LspService();

// One-shot: analyze a buffer and get its diagnostics.
final errors = await lsp.analyze('file:///Foo.dart', source);

// Or query features against the current buffer.
final hover = await lsp.hover('file:///Foo.dart', Position(2, 13));
final outline = await lsp.documentSymbols('file:///Foo.dart');
final edit = await lsp.rename('file:///Foo.dart', Position(2, 13), 'compute');

lsp.change('file:///Foo.dart', edited); // update as the buffer changes
await lsp.dispose();
```

`LspService` exposes `analyze`, `open`/`change`/`close`, a `diagnostics` stream,
and typed `hover`, `definition`, `documentSymbols`, `completion`, `references`,
`documentHighlight`, `prepareRename`, `rename` and `workspaceSymbols`. Use
`LspService.wrap(client)` to layer the same convenience over a client connected
to a remote (out-of-process) server.

Runnable walkthroughs are in
[`example/apollovm_example_lsp_api.dart`](example/apollovm_example_lsp_api.dart)
(the `LspService` API) and
[`example/apollovm_example_lsp.dart`](example/apollovm_example_lsp.dart) (the
lower-level `LspClient`).

A minimal VS Code client, an example workspace and a latency benchmark live in
the repository's [`lsp/`](lsp/) directory (not part of the published package) —
see [`lsp/README.md`](lsp/README.md) for features, design and editor setup.

-----------------------------

## Module Imports & Dart Package Importer

ApolloVM has a language-agnostic module import system: `import` declarations in
loaded code resolve through pluggable `ModuleLoader`s (in-memory, filesystem, or
custom). See [`doc/module_resolution.md`](doc/module_resolution.md).

For Dart code, the **opt-in** library `package:apollovm/apollovm_pub.dart` adds
a `package:` importer that resolves dependencies from a local
`package_config.json` (`PackageConfigProvider`) or directly from pub.dev
(`PubDevProvider`, web-compatible) — see
[`example/apollovm_example_pub_importer.dart`](example/apollovm_example_pub_importer.dart).
It is intentionally not exported from `package:apollovm/apollovm.dart`, so VMs
that don't import it stay fully sandboxed.

-----------------------------

## See Also

ApolloVM uses [PetitParser for Dart][petitparser-pub] to define the grammars of the languages and to analyze the source codes.

- [PetitParser @ GitHub][petitparser-github] (a very nice project to build parsers).

[petitparser-pub]: https://pub.dev/packages/petitparser
[petitparser-github]: https://github.com/petitparser

## Features and bugs

Please file feature requests and bugs at the [issue tracker][tracker].

[tracker]: https://github.com/ApolloVM/apollovm_dart/issues

## Contribution

Any help from the open-source community is always welcome and needed:

- **Have an issue?**
  Please fill a bug report 👍.
- **Feature?**
  Request with use cases 🤝.
- **Like the project?**
  Promote, post, or donate 😄.
- **Are you a developer?**
  Fix a bug, add a feature, or improve tests 🚀.
- **Already helped?**
  Many thanks from me, the contributors and all project users 👏👏👏!

*Contribute an hour and inspire others to do the same.*

## TODO

- JavaScript: extended support (destructuring, spread, `this.x` constructor parameters, full ESM modules). *Named arrow functions (`const f = (a, b) => a + b;`), anonymous arrow callbacks/closures (`(x) => x * 2`), the ternary operator (`c ? a : b`), and `async`/`await` are already supported.*
  - *See the [JavaScript implementation (at "lib/src/languages/javascript/es")](https://github.com/ApolloVM/apollovm_dart/tree/master/lib/src/languages/javascript/es).*


- TypeScript: extended support (union/intersection types, type aliases, parameter properties, decorators). *Type annotations, `interface`, `enum` (incl. member access at runtime), generic classes/instantiation, and access modifiers (`public`/`private`/`protected`/`readonly`/`static`/`abstract`) are already supported.*
  - *See the [TypeScript implementation (at "lib/src/languages/typescript/ts")](https://github.com/ApolloVM/apollovm_dart/tree/master/lib/src/languages/typescript/ts).*


- Lua: extended support (multiple assignment/returns, varargs, non-`ipairs` numeric-for round-tripping, and hand-written metatable styles beyond the `Name = {}` / `function Name:method` convention).
  - *See the [Lua implementation (at "lib/src/languages/lua")](https://github.com/ApolloVM/apollovm_dart/tree/master/lib/src/languages/lua).*


- Python: extended support (comprehensions, decorators, `with` statements, `*args`/`**kwargs`, multiple assignment/returns). *Functions, classes/`self`-methods, `if`/`elif`/`else`, `while`, `for ... in`, `try`/`except`/`finally` + `raise`, lists & dicts, f-strings, keyword arguments, `lambda` expressions, conditional expressions (`a if c else b`), and `import`/`from ... import` are already supported.*
  - *See the [Python implementation (at "lib/src/languages/python")](https://github.com/ApolloVM/apollovm_dart/tree/master/lib/src/languages/python).*


- Go: extended support (`panic`/`recover`/`defer` for `try`/`catch`/`throw`, interfaces + struct embedding for inheritance, `const`/`iota` enums, and `[T any]` generics). *Top-level and struct receiver `func`s, `struct` types + fields + factory constructors, `var`/`:=` with type inference, `if`/`else if`/`else`, `for` (C-style, condition-only, `range`, infinite), `switch`, slices/maps, closures, string `+` concatenation, and `fmt.Println` (normalized to `print`) are already supported.*
  - *See the [Go implementation (at "lib/src/languages/go")](https://github.com/ApolloVM/apollovm_dart/tree/master/lib/src/languages/go).*


- Full Wasm support:
  - *See the [Wasm generator](https://github.com/ApolloVM/apollovm_dart/tree/master/lib/src/languages/wasm).*

## Author

Graciliano M. Passos: [gmpassos@GitHub][github].

[github]: https://github.com/gmpassos

## Sponsor

Don't be shy, show some love, and become our [GitHub Sponsor][github_sponsors].
Your support means the world to us, and it keeps the code caffeinated! ☕✨

Thanks a million! 🚀😄

[github_sponsors]: https://github.com/sponsors/gmpassos

## License

[Apache License - Version 2.0][apache_license]

[apache_license]: https://www.apache.org/licenses/LICENSE-2.0.txt
