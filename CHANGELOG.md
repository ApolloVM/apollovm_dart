## 0.1.41

### Wasm: static methods + boxed `Object`

- The WebAssembly compiler now supports `static` class methods: each is
  synthesized as an exported module function under the qualified `Class.method`
  name (no `this`), generated like a top-level function. `ApolloRunnerWasm`
  gains `executeClassMethod`, resolving the export by that name.
- New boxed representation for `Object`/`dynamic` values: an i32 pointer to a
  16-byte heap cell `[tag@0][typeId@4][payload@8]`. Concrete values flowing into
  an `Object` slot are boxed, and `toString()` dispatches on the box tag
  (int/double/bool/String, plus boxed instances by `typeId`). Enables
  `List<Object>`/`List<dynamic>` literals and arguments with mixed element
  types, marshalled host-side by `ApolloRunnerWasm`.
- Validated against both the AST interpreter and the compiled+executed Wasm
  module.

## 0.1.40

### Wasm: control flow + bitwise

- The WebAssembly compiler now supports `do`/`while`, `switch`/`case` (integer,
  C-style fall-through), `break`, `continue`, and the bitwise operators
  `& | ^ << >>` and unary `~`. Loops now wrap their body in a `continue` block
  and `WasmContext` tracks structured-control depth so `break`/`continue` emit
  correct relative branch labels. Each construct is validated against both the
  AST interpreter and the compiled+executed Wasm module.

### Bitwise operators: Kotlin and Lua

- **Kotlin**: infix `and`/`or`/`xor`/`shl`/`shr` and `x.inv()` (bitwise NOT).
- **Lua**: `&`/`|`/`~` (xor)/`<<`/`>>` and unary `~`, leaving `~=` (not-equals)
  and `^` (exponent) intact.

### Kotlin member visibility

- Parse and generate member modifiers (`private`/`public`/`internal`/
  `protected`, plus `open`/`override`/`abstract`/`final`/`const`) on Kotlin
  methods/fields/constructors; method visibility round-trips.

### Fixes

- **Java**: `private` members no longer fail with "Can't be private and public"
  (the modifiers parser derived `isPublic` from `private`).

### Docs

- New "Supported Features" section in the README: per-language control-flow /
  operator matrix (with a Wasm column) and a Classes/types/OOP matrix.

## 0.1.39

### enum runtime value access

- `EnumType.entry` now resolves at runtime to the entry's value: its explicit
  value when present (C# `Level.Medium` → `5`), otherwise its ordinal index
  (Dart `Color.blue` → `2`). `ASTRoot.getNodeIdentifier` resolves user
  classes/enums by name; enum entry access short-circuits in
  `ASTExpressionObjectGetterAccess`.

### Generics

- Parse generic type annotations in Java and C# (`List<Integer>`,
  `Map<String,Integer> m`, `Box<T>`); well-known collections map to the shared
  array/map types, other generic types keep their type arguments and round-trip.
- Support generic class declarations and instantiation across the languages that
  have generics: `class Wrapper<T> { T value; … }` plus `new Wrapper<int>(10)` /
  `Wrapper<int>(10)`. Class type parameters are erased to `dynamic` in member
  types; generic type arguments on calls are parsed. Runs end-to-end in Dart,
  Java, C#, Kotlin and TypeScript.
- Type system: generic erasure in `ASTType.acceptsType` — a raw type and a
  parameterized one of the same name are mutually compatible (so a `Wrapper`
  instance binds to a `Wrapper<int>` variable).

### Fixes

- Java for-each now generates the colon form `for (Type x : coll)` instead of the
  invalid `for (var x in coll)`, so generated Java re-parses.
- Kotlin `val`/`var` keywords now require a word boundary, so identifiers like
  `value` are no longer mangled (e.g. a constructor parameter `value` was read as
  `ue`).
- Kotlin and TypeScript class instantiation/constructors now execute: a
  constructor with an omitted class name (`constructor(...)`) resolves its type
  from the enclosing class, and TypeScript `constructor(...)` is parsed as a real
  constructor so `new Foo(...)` works.

## 0.1.38

### Language: C# — lambda parsing

- Parse C# lambda expressions (`x => x * 2`, `(a, b) => a + b`, `(int a) => { ... }`,
  `() => 0`); previously C# could only *generate* lambda syntax, not read it.
- Delegate type names (`Func`, `Action`, `Delegate`, `Function`) map to the shared
  function type, so a lambda value binds to a delegate-typed parameter.

### Control flow: `switch`/`case`, `break`, `continue`, `do`/`while`

- New shared AST/runtime nodes (`ASTStatementBreak`, `ASTStatementContinue`,
  `ASTStatementDoWhileLoop`, `ASTStatementSwitch`/`ASTSwitchCase`). `break`/
  `continue` propagate through `ASTBlock` and are consumed by the enclosing
  loop/switch; `for` still runs its increment on `continue`.
- `switch` uses C-style fall-through (`break` ends a case; `default` runs when no
  case matches). An `ASTStatementSwitch.fallThrough` flag disables fall-through
  for languages whose construct has none.
- Parsing + code generation added to the C-style languages: **Dart, Java, C#,
  JavaScript, TypeScript** (each `case` body accepts a braced block or a bare run
  of statements).
- Mapped to each non-C-style language's idiom:
  - **Kotlin**: `break`/`continue`, `do { } while (c)`, and `when (e) { v -> …;
    else -> … }` (no fall-through).
  - **Python**: `break`/`continue`, and `match`/`case` (`case _:` is the
    default; no fall-through). Python has no `do`/`while`.
  - **Lua**: `break`, and `repeat … until <cond>` mapped to a do-while (the
    condition is negated; the generator unwraps it to emit `until <cond>`).
- New golden tests under `test/tests_definitions/*_control_flow*.test.xml` for
  all eight languages.

### Bitwise operators

- New operators `&`, `|`, `^`, `<<`, `>>` (binary) and `~` (unary complement),
  with shared AST/runtime evaluation (`int` operands) and precedence (shift,
  then AND/XOR/OR, between arithmetic and comparison).
- Parsed and generated in **Dart, Java, C#, JavaScript, TypeScript, Python**.
  Java additionally gains the previously-missing `%`, `&&` and `||` operators.
- Not added for Kotlin (bitwise are infix functions `and`/`or`/`shl`/`inv`) or
  Lua (`~` is xor and `^` is exponentiation) — their non-symbolic forms need
  bespoke handling.
- New golden tests `test/tests_definitions/*_bitwise.test.xml`.

### enum (Java, C#, Kotlin, Python)

- Enum declaration parsing + generation extended to **Java** (`enum E { … }`),
  **C#** (`enum E { A = 1, … }`), **Kotlin** (`enum class E { … }`) and
  **Python** (`class E(Enum): …`), joining the existing Dart/TypeScript support.
- Declaration + round-trip only (matching the prior Dart/TS level); runtime
  enum-value access is a separate future enhancement.
- New golden tests `test/tests_definitions/*_enum.test.xml`.

## 0.1.37

### Language: C#

- New self-contained C# language support (`csharp`, also accepting `cs` and
  `c#`) able to parse, run and translate, at the same level of compatibility as
  Dart and Java: classes, fields (incl. initial values), constructors, methods
  and modifiers (`public`/`private`/`static`/`readonly`/…), `using` directives,
  variable declarations (`var` and typed), the full expression set
  (arithmetic/comparison/logical operators, ternary `?:`, `++`/`--`, negation),
  string concatenation, `if`/`else if`/`else`, `for`, `foreach (T x in coll)`,
  `while`, `try`/`catch`/`finally`, `throw`, lambdas (`=>`), and `List<T>` /
  `Dictionary<K,V>` collection initializers.
- C# types map to the shared AST (`int`/`long`/`short` → int, `double`/`float`/
  `decimal` → double, `bool`, `string`, `object`, …) so code translates
  cleanly to/from every other supported language.
- Registered in `ApolloVM` (`getParser`, `createRunner`, `createCodeGenerator`)
  and exported from `apollovm.dart`; `.cs` files resolve to the `csharp`
  language.
- New golden tests under `test/tests_definitions/csharp_*.test.xml`.

### Lambda / anonymous-function input parsing (Java, Kotlin, Lua)

- **Java**: parse lambdas as expressions — `(a, b) -> expr`, `(int a) -> { ... }`,
  `x -> x * 2`, `() -> 0` (typed or untyped parameters).
- **Kotlin**: parse lambdas `{ x -> x * 2 }`, `{ x: Int, y: Int -> x + y }`,
  `{ 42 }`; the last expression is the implicit return value.
- **Lua**: parse anonymous functions `function(x) ... end`.
- Closures now round-trip (parse → execute → regenerate) in these languages, not
  just generate.

### Wasm: host imports no longer corrupt module-function call indices

- A module-function `call` index is `importCount + position`, but host imports
  (`env.print`, `env.int_to_str`, …) are registered lazily while bodies are
  generated. A call emitted *before* an import was registered (e.g. calling a
  function and then `print`-ing, including across `await` points) got a stale
  index and produced invalid Wasm (`type mismatch`). The import-discovery pass
  that freezes `importCount` before the real pass now runs for all modules (it
  only touches idempotent state, so import-free modules stay byte-identical).
- Fixes `async`/`await` functions that call other functions and `print` between
  awaits, which now run identically on the interpreter and Wasm.

### Wasm: closures capture variables by reference

- Captured variables are now "boxed" into shared heap cells: the closure
  environment holds pointers to the cells (not copied values), so a variable
  mutated after a closure is created — or mutated *by* the closure — is visible
  on both sides, matching the interpreter. Each closure instance still gets its
  own cell (e.g. two counters created from the same factory are independent).

## 0.1.36

### Ternary / conditional expressions

- Parse `condition ? a : b` in Dart, Java, JavaScript and TypeScript, plus the
  native conditional-expression forms `a if condition else b` (Python) and
  `if (condition) a else b` (Kotlin).
- New `ASTExpressionConditional` AST node (only the selected branch is
  evaluated); generated idiomatically per target: `?:` (Dart/Java/JS/TS),
  `a if c else b` (Python), `if (c) a else b` (Kotlin), `c and a or b` (Lua),
  and a value-typed `if`/`else` block in Wasm.

### Anonymous functions / lambdas / closures

- New `ASTExpressionLiteralFunction` AST node that captures the defining scope
  (closure semantics); function values held in variables/parameters are now
  invocable.
- Parse anonymous functions: `(x) => …` / `(x) { … }` (Dart), `(x) => …` /
  `x => …` (JavaScript, TypeScript) and `lambda x: …` (Python).
- Generate anonymous functions for every target: arrow forms (Dart/JS/TS),
  Java `(x) -> …`, Kotlin `{ x -> … }`, Lua `function(x) … end`, Python
  `lambda x: …`.

### Dart function types

- Parse function types `int Function(int n)`, `void Function()` and
  `Function(int n)` (omitted return type → `dynamic`); `ASTTypeFunction` accepts
  any other function type, and function types are generated as
  `int Function(int)` (Dart) / bare `Function` elsewhere.

### Wasm: closures via function table + `call_indirect`

- Added Table and Element sections and the `call_indirect` instruction. A
  function value is an i32 pointer to a heap environment struct
  `[tableSlot, captured…]`; each closure function takes a hidden environment
  pointer and reads its captured variables from it.
- Concrete signatures are inferred for capture-less closures, untyped lambda
  parameters, capturing closures, and closures returned through a concrete
  `Function` return type. Each closure instance gets its own heap environment.
- *Not yet supported in Wasm:* polymorphic dynamic-return function types (a
  `Function(int)` parameter called with both an `int`- and a `double`-returning
  lambda) — these report a clear error and still work on the interpreter.

### Bug fixes

- Python: `self.method()` and `self.field` now round-trip correctly; fixed a
  `self.field` getter parse crash and a stack overflow on self-referential
  bindings (`s = s + i`) during code generation.
- Local function declarations were duplicated in regenerated code after a
  function was executed (`addFunction` is now idempotent and block generation
  no longer emits a statement-level function twice).
- Fixed doubled indentation of nested function declarations.

### Documentation

- Added **Python** to the package description and the README (a `Python`
  language section and updated the TODO list).

## 0.1.35

### Python language support

- Added **Python** language support (parse, run, and code-generation target),
  emitting strict, idiomatic Python 3.
  - Indentation-significant blocks are handled by an INDENT/DEDENT/NEWLINE
    pre-tokenizer (`PythonIndentationPreprocessor`), so the petitparser grammar
    consumes Python suites like braces; implicit (`(`/`[`/`{`) and explicit (`\`)
    line continuations, blank/comment lines, and string literals are handled,
    and the source is dedented by its common minimum indentation (so a
    uniformly-indented embedded block parses like a flush-left one).
  - Strict generation: PEP-484 type hints when the AST type is statically known
    (`def f(x: int) -> int:`, `x: str = ...`, `List[T]`/`Dict[K, V]`), with a
    dynamic/untyped fallback; `==`/`!=`, `and`/`or`/`not`, `//` integer division,
    `True`/`False`/`None`, f-strings for interpolation, and `self`-based methods.
  - Supports functions, variables (Python first-binding-is-declaration scoping),
    arithmetic/comparison/boolean expressions, `if`/`elif`/`else`, `while`,
    `for ... in`, `try`/`except`/`finally` + `raise`, `class` with methods, lists
    & dicts, and `import`/`from ... import`.
  - Registered `python` (`py` / `.py`) across `getParser`, `createRunner`,
    `createCodeGenerator`, and the CLI.

### Wasm: `print` accepts any value (not only `String`)

- `int` / `double` reuse the host number-to-string imports (`env.int_to_str` /
  `env.double_to_str`); `bool` lowers in-module to the interned `"true"` /
  `"false"` literals (via `select`); `print(null)` prints `"null"`. String
  interpolation gained the same parity.
- The interpreter's mapped `print` now accepts `null` (nullable `Object?`), and a
  `bool` argument passed to a public Wasm function is marshalled to its i32 ABI
  value.

### Classes and instantiation (Dart, Java, and Wasm)

- The `new` keyword is now parsed in Dart and Java (`new User()`); `new User()`
  and `User()` resolve to the same constructor (boundary-safe, so identifiers
  like `newValue` are unaffected). Java also gained a generic
  `new ClassName(args)` rule (previously only `new ArrayList<…>()` /
  `new HashMap<…>()` were recognized).
- Classes that declare no constructor get an implicit default (zero-arg)
  constructor — on the interpreter and the Wasm backend; field initializers still
  apply.
- Constructors that set fields: `this.field` parameters, and constructor
  **bodies** that assign fields (`this.field = value` and bare `field = value`,
  with parameters shadowing same-named fields, e.g. `User(int id) { this.id = id; }`).
  Fixed empty-parameter constructors with a body (`User() { … }`), which threw a
  parser cast error.
- A class method can instantiate sibling classes and call top-level functions
  (`ASTClass.getFunction` falls back to the enclosing `ASTRoot`) — essential for
  Java, where all code lives in a class.
- Dart arrow (expression-bodied) functions and methods: `T name(params) => expr;`
  (e.g. `String toString() => '…';`), for top-level functions and instance
  methods, including `void` bodies. Desugars to `{ return expr; }`.
- WebAssembly compilation of classes (first slice): single classes (no
  inheritance) with `int` / `double` / `bool` / `String` / object-reference
  fields, constructors (`this.field` params, field initializers, default and
  body constructors), instance methods, in-code instantiation, and method calls
  (`p.sum()` and implicit-`this` `foo()`). An object is an i32 pointer to a
  bump-allocated struct; methods take `this` as the first parameter; a discovery
  pass registers host imports before the code section so cross-function call
  indices stay correct.

### Object field access on instances (read and write)

- Field assignment `obj.field = value` (and `this.field = value`), including
  compound operators (`+=`, `-=`, `*=`, `/=`, `~/=`), via a new
  `ASTExpressionObjectSetterAssignment` node — added to the Dart, Java, Kotlin,
  JavaScript and TypeScript grammars, the shared source generator (round-trips
  back to `obj.field = value`), and the Wasm backend (stores at `recv + offset`).
- Field read `obj.field` is now supported in Java (which had no object
  getter-access rule); `this.field` reads resolve to the current instance's field
  across all languages (previously routed to a local-getter lookup and failed
  with "Can't find getter").

### `print(obj)` calls the user-defined `toString()`

- Interpreter: `print(instance)` invokes a user-declared `toString()` (a class
  without one still prints the default `Class{…}` representation), and
  `ASTExternalFunction.call` now awaits resolved argument values so an async
  resolver result isn't passed through as a `Future`.
- Wasm: `print(instance)` (and string coercion / interpolation) calls the
  instance's compiled `toString()` and prints the resulting string handle.

This makes programs like the following compile and run on Wasm with
interpreter-parity:

```dart
class User {
  int id;
  String name;
  User(this.id, this.name);
  String toString() => 'User#$id<$name>';
}
void main() {
  var user = new User(123, 'Joe');
  print(user);
  print(user.id * 1000);
}
```

Not included: inheritance / interfaces / abstract / `static` members /
polymorphism.

## 0.1.34

- Wasm `throw` / `try` / `catch` / `finally`: exception handling now compiles to
  WebAssembly (previously deferred / loud-failure), engine-agnostic — no Wasm
  exception-handling proposal required.
  - A function that uses (or transitively calls) exceptions is lowered to a
    `$pc`-dispatched CFG (like the Asyncify transform but without suspension), so
    a `throw` is an absolute jump to the nearest handler — no fragile relative
    `br` bookkeeping. The thrown value + an in-flight flag live in a small fixed
    exception region of linear memory.
  - Supported: `throw` of int/double/bool/`String`/object values; typed
    (`on T catch`), untyped, and multiple catch clauses; type matching that
    mirrors the interpreter (`ASTType.acceptsType`, e.g. `on double` accepts an
    `int`); `finally` on every exit path (normal, caught, propagated, and
    `return`-through-`finally`, with `return`-in-`finally` overriding); `throw`
    inside `if`/`while`/`for`; **cross-function propagation** (a callee sets the
    pending flag + returns, each call site re-checks it); and **catching VM
    traps** — integer division by zero (`1 ~/ 0`) raises a catchable `String`
    instead of trapping the module.
  - Deferred (these fail loudly rather than miscompile): `async`/`await` combined
    with exceptions in the same function, `for-each` containing a `throw`,
    multiple raising operations in a single statement, and `return <throwing
    call>` directly inside a `try`.

## 0.1.33

- Exception handling: **`throw`, `try` / `catch` / `finally`** for Dart, Java,
  Kotlin, JavaScript and TypeScript (parse, run and translate).
  - New AST nodes `ASTStatementThrow`, `ASTStatementTryCatch` and `ASTCatchClause`;
    a thrown value is carried by the new `ApolloVMThrownException`.
  - Catch semantics (faithful to Dart's `catch (e)`): an **untyped** `catch`
    catches both user `throw`n values *and* built-in VM runtime errors (e.g.
    integer division by zero, surfaced as their message `String`); a **typed**
    clause matches user-thrown values by type. The universal supertypes
    (`Object`, `dynamic`, `Exception`, `Throwable`, `Error`) act as catch-all so
    an untyped catch round-trips faithfully across languages.
  - `finally` always runs (on normal completion, after a caught throw, or on a
    `return` inside `try`/`catch`), and a `return` inside `finally` overrides.
  - Per-language catch syntax on both parse and generation: Dart `on T catch (e)`
    / `catch (e)`, Java `catch (T e)` (untyped → `catch (Exception e)`), Kotlin
    `catch (e: T)` (untyped → `catch (e: Throwable)`), JS/TS `catch (e)`.
  - **Wasm** `try`/`catch`/`throw` is deferred: it fails loudly (no silent
    miscompile).

## 0.1.32

- Wasm Asyncify: **awaits inside `for-each`** over a list. `for (T e in it)` is
  desugared in the CFG into an indexed loop (`__i = 0; while (__i < it.length) {
  T e = it[__i]; body; __i++ }`), so awaits in the body really suspend. `it[__i]`
  uses the normal list index-access; the index/length are temp locals
  spilled/restored on the Asyncify frame stack, and the only non-AST bit (the
  length read + index reset) is emitted via a small per-block raw hook. The
  iterable must be a list variable; other iterables fall back to
  synchronous-collapse. Tested end-to-end through `ApolloRunnerWasm`.

## 0.1.31

- TypeScript language support (parse, run, translate):
  - New language at `lib/src/languages/typescript/ts/`: `ApolloParserTypeScript`,
    `TypeScriptGrammarDefinition`, `TypeScriptGrammarLexer`,
    `ApolloCodeGeneratorTypeScript`, `ApolloRunnerTypeScript`.
  - Superset of JavaScript: all JS features plus **type annotations** on
    variables, parameters, return types and class fields
    (`number`/`string`/`boolean`/`any`/`void`, `T[]`/`Array<T>`), **interfaces**,
    **enums**, and access modifiers (`public`/`private`/`protected`/`readonly`/
    `static`/`abstract`).
  - Code generation emits idiomatic TypeScript (type annotations, `interface`,
    `enum`, `abstract class`, member modifiers) and erases types cleanly when
    targeting JavaScript.
  - Registered `'typescript'`/`'ts'` in the parser/runner/generator factories and
    the `.ts` file-extension mapping; CLI `apollovm run`/`translate` support `.ts`.
  - Tests: TypeScript test definitions under `test/tests_definitions/` plus the
    `test/hello_world.ts` fixture and `example/apollovm_example_typescript.dart`.

- Generalized class/member modeling in the shared AST (used by Dart and TypeScript):
  - `ASTModifiers`: added `isAbstract` and `isProtected` (and `modifierAbstract`).
  - `ASTClassNormal`: added `kind` (`ASTClassKind.normalClass` / `abstractClass` /
    `interface`), plus optional `superClassName` and `implementsTypes`.
  - New `ASTClassEnum` (extends `ASTClassNormal`) with `ASTEnumEntry` entries.
  - `ASTClassField`: added a `modifiers` field (e.g. `static`/`private`/`readonly`).
  - Dart now parses and generates `abstract class`, `enum`, `extends`/`implements`,
    abstract (body-less) methods, and `static` fields; these cross-translate
    between Dart, TypeScript and JavaScript.

## 0.1.30

- Wasm Asyncify: **awaits inside control flow** (`if`/`if-else`/`else if`,
  `while`, `for`), plus `return await ...` and `x = await ...`. The generator
  lowers such async functions into a CFG of basic blocks and emits a
  program-counter state machine — a `loop` + `br_table` dispatch over a `$pc`
  local, with `$pc` spilled/restored on the Asyncify frame stack alongside the
  locals. Awaits become block boundaries; leaf (host) and internal (module-
  async) awaits both work inside loops/branches, composing with multi-frame
  unwinding. Functions whose awaits are all top-level keep the linear path.
  Awaits nested inside expressions (`t = t + await f()`, `return await f() + 1`,
  `await f() + await g()`) are hoisted into temp locals automatically. Remaining
  unsupported shapes (`for-each`, awaits in loop/branch conditions) fall back to
  synchronous-collapse. Tested end-to-end through `ApolloRunnerWasm`.

- `async`/`await` support (real asynchrony) — Dart parse/run/translate and
  JavaScript translation:
  - AST: new `ASTModifiers.isAsync`, new `ASTExpressionAwait` expression, and a
    new abstract `generateASTExpressionAwait` generator hook. Reuses the
    existing `ASTTypeFuture`/`ASTValueFuture` (added `ASTTypeFuture.futureValueType`).
  - Runtime: an `async` function returns a first-class future *immediately*
    (a non-awaited call yields an `ASTValueFuture` that can be stored and
    awaited later); `await` suspends on real Dart `Future`s, including those
    returned by external functions declared with a `Future<...>` return type.
    `ASTEntryPointBlock.execute` awaits the entry future before tearing down the
    entry-point context (external mapper, current context).
  - Dart grammar: parses the `async` body keyword (after the parameter list) and
    the `await` prefix expression; `Future<T>` types parse to `ASTTypeFuture`;
    the `await`/`async` contextual keywords no longer shadow identifiers
    (e.g. `awaiter`) or get read as a type name.
  - Code generation: Dart emits `... ) async {` and `await `; JavaScript emits
    `async function` / `async name(` and `await `.
  - Wasm: async/await compiles via **synchronous collapse** — the backend runs
    synchronously, so `Future<T>` collapses to `T` (`effectiveReturnType`) and
    `await` is a value pass-through. Compute-style async Dart compiles to Wasm
    and matches the AST interpreter.
  - Wasm real-suspension **Asyncify prototype**
    (`test/apollovm_wasm_asyncify_prototype_test.dart`): a hand-assembled
    two-frame module proves real suspension against the live `WasmRuntime` — a
    running call unwinds to the host (saving live locals to linear memory), the
    host awaits a real Dart `Future`, then re-invokes the export which rewinds
    and resumes. Demonstrates multi-frame state preservation, exactly-once
    prologue execution, and two concurrent computations interleaving by host
    delay.
  - Wasm **Asyncify code generation**: the generator emits the unwind/rewind
    state machine for an `async` function whose `await`s are statement-level
    calls — a low-memory Asyncify control region (`WasmModuleContext`) with a
    LIFO **frame stack**, live-local spill/restore, `br_table` resume dispatch
    supporting **multiple `await` points** in one function, and **multi-frame
    unwinding**: an `async` function may `await` another module `async` function
    (an *internal* frame) as well as a host import (a *leaf*). The unwind
    propagates up every frame on the call stack to the host and rewinds back
    down (an eligibility fixed-point decides which async functions transform;
    the rest use synchronous-collapse). Validated against the live runtime in
    `test/apollovm_wasm_asyncify_codegen_test.dart` and the multi-frame /
    mixed-await cases in `test/apollovm_wasm_asyncify_runner_test.dart`. Shapes
    that still fall back to synchronous-collapse: awaits nested in control flow,
    multiple awaits in one statement, and async recursion.
  - Wasm Asyncify **runner integration**: `ApolloRunnerWasm.executeFunction`
    now detects real-suspension `async` functions (flagged in `apollovm_sig`)
    and drives their unwind/rewind loop, awaiting a real Dart `Future` from a
    host function registered via the new `ApolloRunnerWasm.mapWasmAsyncFunction`
    API. So real-suspension async/await works end-to-end through the VM
    (`test/apollovm_wasm_asyncify_runner_test.dart`). A `br_table`
    multi-await/multi-frame transform is the remaining follow-up.
  - Kotlin async/await translation: an `async` function maps to a `suspend fun`
    (the declared `Future<T>` collapses to `T`), and `await e` becomes just `e`
    (suspension is implicit when calling a `suspend` function in coroutines).
  - Tests: `test/apollovm_async_test.dart` (parse, real-suspension ordering,
    await chains, top-level async, identifier guard, Dart/JS/Kotlin translation)
    and `test/apollovm_wasm_async_test.dart` (AST-vs-compiled-Wasm parity).

## 0.1.29

- Lua language support (parse, run, and translate):
  - New `lib/src/languages/lua/` module: `ApolloParserLua`,
    `LuaGrammarDefinition`/`LuaGrammarLexer`, `ApolloCodeGeneratorLua` and
    `ApolloRunnerLua`, all built on the shared AST (no AST changes).
  - Grammar covers top-level and `local` functions, `local`/global variables,
    `if/elseif/else`, `while`, numeric and generic `for ... in ipairs(...)`,
    `return`, expressions/operators (`and`/`or`/`not`, `~=`, `..` concatenation),
    table constructors (list and map), and a table-based class convention
    (`Name = {}`, `Name.__index = Name`, `function Name:method(...)`) grouped
    into the shared class AST. Return types are inferred (`void` vs `dynamic`).
  - Generator emits idiomatic Lua: keyword-delimited blocks with `end`, `local`
    variables, `..` string concatenation, `and`/`or`/`not`/`~=`, table literals,
    and `self.`/`self:` prefixing inside methods.
  - Registered in `ApolloVM` (`getParser`/`createRunner`/`createCodeGenerator`).
  - Tests in `test/apollovm_lua_test.dart` cover parse+run, translate+re-execute
    to Dart/Lua/Kotlin, and bidirectional table-based classes.

## 0.1.28

- Kotlin language support (parse, run, and translate), reaching parity with the
  existing Java feature set:
  - New `lib/src/languages/kotlin/` module: `ApolloParserKotlin`,
    `KotlinGrammarDefinition`/`KotlinGrammarLexer`, `ApolloCodeGeneratorKotlin`
    and `ApolloRunnerKotlin`, all built on the shared AST (no AST changes).
  - Grammar covers top-level and class `fun` declarations, `val`/`var`
    declarations (with type inference), `Int`/`Double`/`Boolean`/`String`/
    `Unit`/`Any`/`List`/`Map` types, `if/else`, `for (x in ...)`, `while`,
    expressions/operators, `listOf`/`mapOf` literals, and `"$x"` / `"${expr}"`
    string templates. `println` is normalized to the VM's `print`.
  - Registered in `ApolloVM` (`getParser`/`createRunner`/`createCodeGenerator`);
    `.kt` files already mapped to `kotlin`.
  - Tests in `test/apollovm_kotlin_test.dart` cover parse+run and
    Kotlin→Dart/Java/Kotlin translation round-trips.
- JavaScript (modern ES) language support — fully bidirectional:
  - **Parser** (`ApolloParserJavaScript`, `JavaScriptGrammarDefinition`, `JavaScriptGrammarLexer`): parses `.js`/`javascript` source into the shared ApolloVM AST. Covers classes (fields + methods, `static`, `constructor`), top-level `function` declarations, `let`/`const`/`var`, `for`/`for...of`/`while`, `if`/`else if`/`else`, list literals, `++`/`--`, compound assignment, strict equality (`===`/`!==`), and single/double-quoted strings plus back-tick **template literals** with `${ … }` interpolation. Untyped sites map to `dynamic`; method/function return types are inferred as `void` (no value-return) or `dynamic`.
  - **Code generator** (`ApolloCodeGeneratorJavaScript`): emits idiomatic modern JS from any loaded AST (Dart, Java, or JS) — `let`/`const`, template literals for string interpolation, `for...of`, top-level functions, untyped params/fields, `===`/`!==`, and `Math.trunc(a / b)` for integer division.
  - **Runner** (`ApolloRunnerJavaScript`): executes JS-parsed ASTs in the VM (subject to the VM's existing limitation that arithmetic requires concrete/inferable types — dynamic-typed arithmetic is unsupported, as for Dart `dynamic`).
  - Registered `javascript`/`js` in `ApolloVM.getParser`, `createRunner`, and `createCodeGenerator`.
  - **CLI**: `apollovm run`/`translate` now work on `.js` files (the `.js` extension already mapped to `javascript`); added a `test/hello_world.js` fixture and updated the CLI banner to "Dart, Java and JavaScript".
  - Tests: added `javascript_basic_*` definitions (parse + execute + round-trip + cross-translation to Dart/Java) and a JavaScript generation block to the Dart class-function test.
  - Follow-ups: destructuring, spread, async/await, true `constructor` semantics with `this.x` parameters, and full ESM are not yet supported.
- CLI bug fix: `apollovm translate` printed `Instance of 'Future<StringBuffer>'` instead of the translated source — `writeAllSources()` was stringified without `await`. Fixed for all languages.
- Runtime fix — `for-each` / `for...of` over any iterable: `ASTStatementForEach` only accepted an `ASTValueArray`, so iterating a list bound to a `dynamic`/`Object` variable (which resolves to a plain `ASTValueStatic`) threw at runtime. It now iterates any resolved `Iterable` (and `Map` values), and wraps each element into a concretely-typed `ASTValue` (via `ASTValue.fromValue`) so per-element operations (e.g. arithmetic, string concatenation) work. Affects all languages; enables JavaScript `for...of` over arrays.
- Runtime fix — arithmetic/comparison on dynamically-typed operands: binary operators (`+ - * / % == != > < …`) dispatched on the operand's static `ASTValue.type` and only handled concrete primitives, so two `dynamic`/`var`/`Object` operands (e.g. untyped JavaScript parameters) threw `Can't perform '+' operation with types: dynamic + dynamic` even when the runtime values were real numbers/strings. `ASTExpressionOperation.run` now resolves each "boxed"/untyped operand to its concrete `ASTValue` (via `ASTValue.fromValue`) before dispatching. Affects all languages; enables executing parsed JavaScript arithmetic.
- JavaScript `/` is now floating-point division (`ASTExpressionOperator.divideAsDouble`), matching JS semantics (`7 / 2 === 3.5`) instead of integer division.
- JavaScript arrow functions: a named arrow assignment (`const add = (a, b) => a + b;`, `const square = n => n * n;`, `const greet = () => { … };`) is parsed and desugared to a named function declaration — callable by name (`add(1, 2)`), at top level or as a local statement, with expression or block bodies. Translates to a regular `function`/method on output. Anonymous arrows passed as callbacks (true closures) are a follow-up.
- Code generation fix — logical negation of a complex operand: `!(a > b)` was emitted as `!a > b` (which re-parses as `(!a) > b`). The negated operand is now parenthesized when complex. Affects all languages.
- Tests: broad JavaScript coverage added — parse + execute + translate (to Dart/Java where applicable) + re-execute the generated code: `javascript_basic_vars`, `branches`, `while_loop`, `for_loop`, `comparisons`, `division`, `negation`, `this_method`, plus the earlier `class_function`, `control_flow`, `for_of`, `arithmetic`, and arrow-function definitions.
- Docs/examples: added per-language runnable examples under `example/` — `apollovm_example_java.dart`, `apollovm_example_kotlin.dart` and `apollovm_example_javascript.dart` (each load + run + translate to Dart, with verified output) — and fixed the existing `apollovm_example.dart` to `await writeAllSources()` (was printing `Instance of 'Future<StringBuffer>'`). README updated with a Kotlin section and the CLI banner now reads "Dart, Java, Kotlin and JavaScript".

## 0.1.27

- Wasm collections — compound subscript assignment (P3, part 9):
  - `m[k] += v` (and `-=`, `*=`, `/=`, `~/=`) and the same for list indices `a[i] += v` now compile to Wasm. Lowered by desugaring `c[k] OP= v` into `c[k] = c[k] OP v`, so it reuses the existing get/set codegen and works for maps (`int`/`String` keys) and lists across `int`/`double` values. Matches the interpreter on both `wasm_run` and Chrome (e.g. a frequency counter can now use `m[w] += 1` directly).
- Wasm collections — map parameters & returns (P3, part 8):
  - Functions can now accept and return whole `Map`s across the host boundary. The runner marshals a Dart `Map` into the module's map layout (header + parallel key/value buffers, via the exported `__alloc`) for `Map` parameters, and decodes a returned map-header pointer back into a Dart `Map`. Covers `int`/`String` keys × `int`/`double`/`String`/`bool` values, including round-tripping and returning a map built with `m[k] = v`.
  - The `apollovm_sig` custom section now encodes a map type as `[7, <key tag>, <value tag>]`, so raw-byte modules self-describe their key/value types. Element read/write was factored into shared helpers used by both list and map marshalling.
- Wasm collections — map `.keys` / `.values` + iteration (P3, part 7):
  - `m.keys` and `m.values` now compile to Wasm: each materializes a fresh list by copying the map's parallel key (or value) buffer (which already has the list element layout), so `for (var k in m.keys)` / `for (var v in m.values)` work via the existing list for-each. Matches the interpreter on both `wasm_run` and Chrome.
  - The for-each loop-variable type resolver now derives the element type from the map (`m.keys` → key type, `m.values` → value type) so the loop variable is correctly typed.
- Wasm collections — maps with `String` keys (P3, part 6):
  - `Map<String, V>` now compiles to Wasm (`V` = `int`/`double`/`String`/`bool`): literals, `m[k]` get, `m[k] = v` set, `.length`/`.isEmpty`/`.isNotEmpty`, and `.containsKey(k)`. Matches the interpreter on both `wasm_run` and Chrome.
  - String keys are stored as i32 pointers and compared by content via a synthesized `__streq(a, b)` helper (length check + byte loop), so e.g. `containsKey("app")` correctly returns `false` for a map keyed by `"apple"`, and multi-byte UTF-8 keys work.
- Wasm collections — maps with `int` keys (P3, part 5):
  - `Map<int, V>` now compiles to Wasm (`V` = `int`/`double`/`String`/`bool`). A map value is an i32 pointer to a 16-byte header `[length][capacity][keysPtr][valuesPtr]` with parallel key/value buffers; lookup/set is a linear scan with `i64` key equality. Matches the interpreter on both `wasm_run` and Chrome.
  - Supported: map literals (incl. empty `{}`), `m[k]` get, `m[k] = v` set (in-place update or append, growing both buffers when full), `.length`, `.isEmpty`/`.isNotEmpty`, and `.containsKey(k)`.
  - Also adds Wasm **list index assignment** `a[i] = v` (the subscript-assignment AST node now lowers to Wasm for both maps and lists).
  - Out of scope for this slice: `String` keys (need a string-equality helper), `.keys`/`.values`/iteration, map parameters/returns, and compound subscript assignment (`m[k] += v`) — note `m[k] = m[k] + 1` already works.
- Dart subscript assignment — `m[k] = v` and `a[i] = v` (frontend + interpreter):
  - The grammar now parses container-entry assignment targets (previously the assignment left-hand side was only a bare variable, so `m[k] = v` / `a[i] = v` failed with a `SyntaxError`). Compound operators (`+=`, `-=`, `*=`, `/=`, `~/=`) are supported, e.g. `m["x"] += 1` for building a frequency map.
  - New AST node `ASTExpressionVariableEntryAssignment`; new `ASTValue.writeKey`/`writeIndex` write into the underlying `Map`/`List` in place. A `Map` is always written by key (even a numeric one); a `List` by index. Round-trips through the code generators (parse → regenerate → re-parse).
  - **Empty collection inference fix**: an empty `{}` literal (typed `Map<dynamic,dynamic>`) is now assignable to a typed map such as `Map<String,int>` — `ASTTypeMap.acceptsType` treats a `dynamic` key/value component as a wildcard, matching how lists already ignore their element type for assignment (so `Map<String,int> m = {};` works, like `List<int> a = [];`).
- Dart `Map` support — frontend + interpreter (read/query; prerequisite for Wasm maps):
  - **Grammar fix**: `Map<K,V>` type annotations now parse. `mapTyped()` was missing the value-type parser (it accepted only `Map<K,>` and read the `,` token as the value type), so every `Map<int,int>` declaration failed with a `SyntaxError`. Key/value types also accept `List<...>` (e.g. `Map<String,List<int>>`).
  - Map literals now infer their key/value types from entries (mirroring list literals) instead of being hardcoded to `Map<dynamic,dynamic>`, so `Map<int,int> m = {1:10}` assigns cleanly. `ASTExpressionMapLiteral.resolveType` returns the `Map` type (it previously returned just the *value* type).
  - **Map index by key**: `m[k]` now does a key lookup for any `Map` (the access was incorrectly routed to positional/list indexing whenever the key was numeric, so int-keyed maps failed).
  - New core `Map` class (`CoreClassMap`): getters `.length`/`.isEmpty`/`.isNotEmpty`/`.keys`/`.values` and methods `.containsKey`/`.containsValue`/`.remove`/`.clear`. `.keys`/`.values` resolve to `List<keyType>`/`List<valueType>` so iterating them yields properly-typed elements.
  - Maps work as function parameters.
  - Note: map subscript assignment (`m[k] = v`) is a follow-up (the grammar's assignment target is still a bare variable).
  - Functions can now accept and return whole lists across the host boundary. The runner marshals a Dart `List` into module memory (header + elements buffer, via the exported `__alloc`) for `List` parameters, and decodes a returned list-header pointer back into a Dart `List`. Covers `int`/`double`/`String`/`bool` element lists, including round-tripping (`List<int> echo(List<int> a)`) and building a result with `.add` before returning it.
  - The `apollovm_sig` custom section now carries list types as `[6, <element tag>]` (was a single opaque tag), so modules loaded from raw bytes self-describe their list element types; the runner uses 64-bit element reads/writes via `BigInt` so it works on both the Dart VM and dart2js (Chrome).
  - A `String`/`List` parameter now also forces an exported `__alloc` (previously only String params did), so list-only functions can be fed their arguments.
- Wasm collections — `String` & `bool` element lists (P3, part 3):
  - `List<String>` and `List<bool>` now compile to Wasm: literals, index reads `a[i]`, `for (var e in a)`, `.add`, and the `.first`/`.last`/`.isEmpty`/`.isNotEmpty`/`.length` getters all work (elements stored as i32 — a string pointer or a `0`/`1` boolean). Matches the interpreter on both `wasm_run` and Chrome.
  - Maps remain a later slice.
- Wasm collections — growable lists `.add` + getters (P3, part 2):
  - List values are now an indirect handle: a 12-byte header `[length:i32][capacity:i32][dataPtr:i32]` pointing at a separately-allocated elements buffer. This makes `.add` aliasing-safe — growing reallocates the data buffer (doubling capacity, `memory.copy`ing existing elements) and updates the header in place, so existing references observe the new length/contents.
  - `list.add(x)` now compiles to Wasm for `int`/`double` lists (including starting from an empty `[]` literal), growing linear memory on demand.
  - New list getters compiled to Wasm: `.first`, `.last`, `.isEmpty`, `.isNotEmpty`.
  - `bool`-returning functions loaded from raw Wasm bytes now decode correctly: the `apollovm_sig` custom section is emitted for `bool` returns (not just String signatures), and the runner maps the i32 `0`/`1` back to a Dart `bool`.
- Wasm collections — lists, read + iterate (P3, part 1):
  - `int`/`double` list literals compile to linear-memory blocks; index reads `a[i]`, the `.length` getter, and `for (var e in a)` now compile to Wasm (matching the interpreter, on both `wasm_run` and Chrome).
  - Lists currently stay internal (return scalars); list parameters/returns and maps are later slices.
- Wasm generator — major feature expansion (`ApolloGeneratorWasm`), moving toward full Dart parity:
  - **Loops**: `while` and `for` loops now compile to Wasm (`block`/`loop`/`br_if`/`br`), including `return` from inside a loop. Added the `br` opcode helper and recursion into loop bodies when collecting function locals.
  - **Function calls**: local function invocation (calling other top-level functions, including recursion) via a function-index table threaded through the generator and a `Wasm.call`.
  - **Operators**: integer modulo `%` (`i64.rem_s`), logical `&&`/`||` (`i32.and`/`i32.or`), logical negation `!` (`i32.eqz`), and unary minus `-` (`f64.neg` / `i64` multiply-by-`-1`).
  - **Booleans**: `bool` literals and `bool`-typed locals (represented as Wasm `i32`).
  - **Bug fix**: the `== 0` fast-path (`i64.eqz`) was incorrectly applied to *any* operator with a literal-`0` right operand (e.g. `x > 0` compiled as `x == 0`). It is now restricted to the `equals` operator.
  - **Short-circuit `&&` / `||`**: now compile to an `if/else` so the right operand is only evaluated when needed. The AST interpreter was also made short-circuiting, so interpreted and compiled execution stay consistent (and match Dart).
  - **Full Dart `%` semantics**: integer and double modulo now return the Dart-correct non-negative result in `[0, |b|)` for negative operands (sign-corrected via scratch locals); double `%` is computed as `a - trunc(a / b) * b`.
  - **Fix**: compound assignment (`+=`, `-=`, `*=`, …) emitted its operation to a discarded buffer (missing `out`/`context`), producing broken code; now applied to the real output.
- Tests: added Wasm coverage for every feature above plus a combined integration test (prime counting / sum-of-squares using loops + calls + logic + modulo), all executed against the real compiled-and-run Wasm module.
- Wasm strings — String parameters + `memory.grow` (P2, part 5, completes the strings milestone):
  - Functions taking `String` parameters now work: the runner encodes the Dart string into module memory (via the exported `__alloc`, guided by the `apollovm_sig` param tags) and passes the i32 pointer. Enables `String echo(String s)`, `String greet(String name)`, etc.
  - The allocator (both the exported `__alloc` and the inline concat allocator) now **grows linear memory on demand** (`memory.size`/`memory.grow`), so large strings/concatenations no longer trap.
- Wasm strings — number→string interpolation (P2, part 4):
  - Interpolation of `int`/`double` (`"n=$n"`, `"${a + b}"`) now compiles to Wasm via host imports `env.int_to_str`/`env.double_to_str`; the host formats the number (matching the interpreter; doubles via `ASTTypeDouble.doubleToString`) and writes it into module memory.
  - Adds a synthesized, **exported `__alloc`** bump-allocator function so host imports can allocate strings in the module's memory (reentrant host→module calls), plus value-returning host imports and i64↔BigInt marshalling on the web.
- Wasm strings — String-returning functions (P2, part 3):
  - Functions returning `String` now work: the value is an i32 pointer the runner decodes back into a Dart `String`.
  - Modules are now **self-describing**: a custom `apollovm_sig` section records each public function's high-level return/parameter type tags, so the runner can marshal strings even for modules loaded from raw bytes. Emitted only when a public signature involves a `String` (pure-numeric modules stay byte-identical).
- Wasm strings — concatenation + bump allocator (P2, part 2):
  - A mutable heap-pointer **Global** (`$hp`) bump allocator; runtime string allocation via `__alloc` + `memory.copy`.
  - String `+`, adjacent string literals, and `$var` interpolation of `String` variables now compile to Wasm (left-folded binary concatenation producing a fresh `[len:i32][utf8]` string). Validated on `wasm_run` and Chrome.
  - Note: bump-and-leak (no free yet); number→string interpolation and string returns are later slices.
- Wasm linear-memory foundation + strings (P2, part 1 — `print` of string literals):
  - The generator now emits **Import / Memory / Global / Data** sections and offsets the function-index space past imported functions (a body-first two-pass build). Modules with no strings/imports remain byte-identical.
  - String literals are interned into a static data segment as `[len:i32][utf8]`; a `String` value is an `i32` pointer into the exported linear memory.
  - `print(stringLiteral)` lowers to a host import `env.print(i32)`. The runtime layer (`WasmRuntime`/`WasmModule`) now wires **host imports** at instantiation and exposes **exported memory** reads, on both the native (`wasm_run`) and browser runtimes; the runner decodes the pointer and routes to `externalPrintFunction`.
  - New `wasm.dart` memory opcodes (i32/i64 load/store, load8_u/store8, memory.size/grow/copy/fill) and section-id helpers.
- Test infrastructure — WebAssembly GC validation path:
  - Established a browser (`dart test -p chrome`) parity harness that runs generated Wasm on Chrome's own engine. The native `wasm_run` backend (wasmtime 14 / wasmi 0.31) does not support the WebAssembly GC proposal; Chrome (v119+) does.
  - Added a `wasm-gc` test tag (`dart_test.yaml`) and a WasmGC capability spike; CI's `wasm_run`-based jobs exclude the tag (`--exclude-tags wasm-gc`) while the Chrome job runs it. This gates the planned dual-target (linear-memory + WasmGC) backend work.

- Bug fixes:
  - Loop `return` propagation: a `return` inside a `for`, `while`, or `for-each` loop was ignored (the loop shadowed `runStatus` with a fresh instance and never broke on return). Returns now propagate and stop iteration correctly.
  - `ASTType` equality: `ASTTypeBool`, `ASTTypeString`, `ASTTypeObject`, `ASTTypeConstructorThis`, `ASTTypeVar`, `ASTTypeDynamic`, `ASTTypeNull`, and `ASTTypeVoid` mistakenly checked `other is ASTTypeInt`, so equal instances never compared equal. Each now checks its own type.
  - `ASTTypeMap`: building a map from a flat key/value list read from the (empty) target map instead of the input list, producing an empty map.
  - Java generator (`_escapeString`): backslashes were not escaped, producing invalid Java string literals (e.g. `"a\b"` instead of `"a\\b"`).
  - `ASTExpression.literalNumType` returned `ASTNumType.int` for `double` literals.
  - Corrected the operator symbol shown in `ASTValueString`/`ASTValueNum` comparison/equality error messages.

- Tests:
  - Increased line coverage from ~64.6% to ~70.9%.
  - Added regression tests for all the fixes above and extensive unit/integration tests for `ASTValue`, `ASTType`, `ApolloVM`, expressions, the core library, and the Wasm generator.

- Dependencies:
  - data_serializer: ^1.2.1 -> ^1.2.2
  - test: ^1.31.0 -> ^1.31.1

## 0.1.26

- `DartGrammarDefinition`:
  - Updated `getTypeByName` to treat `'const'` as an unmodifiable variable type alongside `'final'`.
  - Modified `classFieldDeclaration`, `constructorTypedParameterDeclaration`, `statementVariableDeclaration`, and `parameterDeclaration` parsers to accept both `final` and `const` tokens as optional modifiers.
  - Adjusted logic in `statementVariableDeclaration` to recognize `'const'` as unmodifiable and handle it similarly to `'final'`.

## 0.1.25

- `ApolloCodeGeneratorDart`:
  - `generateASTExpression`:
    - Fixed string template merging logic to correctly handle variable accesses and literal strings by swapping checks on `expression1` and `expression2`.
    - Improved merging of adjacent quoted strings with different quote types by adding `_tryMergeQuotedStrings` and related helper methods.
    - Added robust checks for unescaped quotes inside strings to safely convert quote types.
  - Added helper methods:
    - `_isQuotedString`, `_isSingleQuoteString`, `_isDoubleQuoteString`
    - `_canConvertQuote`, `_convertQuote`
    - `_mergeQuotedStrings`, `_tryMergeQuotedStrings`
- `DartGrammarDefinition`:
  - Refactored expression parsing to delegate expression operation precedence and logical operator handling to `computeFinalExpression`.
- `DartGrammarLexer`:
  - Refactored to extend new `BaseGrammarLexer` abstract class.
  - Moved common lexer methods and token handling to `BaseGrammarLexer`.
  - Updated whitespace and comment parsers to static methods for reuse.
- `BaseGrammarLexer` (new):
  - Added as base class for grammar lexers with common token and identifier parsing.
  - Added expression operation precedence handling via `computeFinalExpression` and `reduceExpressionBlock`.
- `Java11GrammarLexer`:
  - Refactored to extend `BaseGrammarLexer`.
  - Removed duplicated token and identifier parsing code.
  - Updated whitespace and comment parsers to static methods.
- `Java11GrammarDefinition`:
  - Refactored expression parsing to use `computeFinalExpression` for operator precedence.
- Tests:
  - Added comprehensive Dart arithmetic and logical expression tests covering operator precedence, mixed numeric types, and complex expressions.
  - Updated multiple Dart and Java11 test definitions to normalize expression grouping from `a + (b + c)` to `(a + b) + c` for consistent operator associativity.
  - Fixed string concatenation tests to correctly merge adjacent string literals and variables.
  - Updated WASM tests to fix generated bytecode for integer operations.
  - Fixed linear regression and forecast tests with corrected arithmetic expressions.
  - Improved test outputs to reflect corrected expression evaluation and string concatenation results.

## 0.1.24

- `ASTExpressionFunctionInvocation` and related classes:
  - Added mixin `WithCallChainFunction` to support chained function invocations.
  - Added field `chainFunctionInvocation` to hold chained calls.
  - Updated function invocation methods to generate chained calls in code generation (`ApolloCodeGenerator`).
  - Updated runtime execution to process chained function calls after the main call.
- `ApolloCodeGenerator`:
  - Refactored function invocation code to use `_generateChainFunctionInvocation` helper for chained calls.
- Dart grammar (`dart_grammar.dart`):
  - Updated `expressionGetterAccess` parser to parse and attach chained function invocations.


- `CoreClassPrimitive`:
  - Removed `_functionToString` field and initialization.

- `CoreClassString`:
  - Added `_functionToString` external class function returning `self.toString()`.

- `CoreClassInt`:
  - Added `_functionToString` external class function returning `self.toString()`.

- `CoreClassDouble`:
  - Added `_functionToString` external class function with custom logic:
    - If the double is an integer value, returns string with `.0` suffix.
    - Otherwise, returns standard `toString()`.

## 0.1.23

- `ASTExpressionVariableEntryAccess`:
  - Replaced `_asyncTry` with `_run2` to improve element access with proper type casting.
  - Added generic `_readElement<V>` method to read elements with type safety.
  - Updated `readIndexASTValue` and `readKeyASTValue` to return typed `ASTValue<V>`.

- `ASTExpressionFunctionInvocation` and subclasses:
  - Added support for chained function invocations via new `chainFunctionInvocation` field.
  - Updated `run` methods to invoke chained functions sequentially after the initial call.
  - Added `_callChainFunction` helper to process chained calls asynchronously.
  - Added `ASTExpressionChainFunctionInvocation` class representing chained function calls.
  - Updated `toString` methods to include chained function calls.
  - Updated constructors and parsing to support chained function invocations.

- `ASTExpressionObjectFunctionInvocation`, `ASTExpressionObjectEntryFunctionInvocation`, `ASTExpressionGroupFunctionInvocation`:
  - Updated constructors and `run` methods to support chained function invocations.
  - Added caching of function class for performance.
  - Improved error handling and function resolution with chained calls.

- `lib/src/apollovm_code_generator.dart`:
  - Updated code generator to output chained function invocations in generated code.

- Grammar updates (`dart_grammar.dart`, `java11_grammar.dart`):
  - Added parsing rules for chained function invocations (`expressionChainFunctionInvocation`).
  - Updated function invocation parsers to parse and attach chained function calls.

- `ASTValue`:
  - Added generic static method `fromValue<V>` to convert dynamic values to typed `ASTValue<V>`.
  - Added `readIndexASTValue<V>` and `readKeyASTValue<V>` methods returning typed `ASTValue<V>`.

- `CoreClassString`:
  - Added new external string functions: `replaceFirst`, `trimLeft`, `trimRight`, `padLeft`, `padRight`, `lastIndexOf`, `codeUnitAt`.
  - Registered new functions in `getFunction` with case-insensitive support.

- `ASTClass`:
  - Added `toString` override for better debug output.

## 0.1.22

- `ASTExpressionVariableEntryAccess`:
  - Refactored `run` method to use nested `resolveMapped` calls for asynchronous handling.
  - Added private helper `_asyncTry` to unify index/key reading logic with async support.
  - Added private helper `__throwReadNPE` to throw detailed `ApolloVMNullPointerException` with stack trace on read failures.
  - Improved error messages for index/key read failures including variable, index/key, size, and value details.

- `ASTExpressionObjectEntryFunctionInvocation`:
  - Added class-level documentation with code examples for usage of object entry function calls like `obj[i].fx(args)` and `obj[key].fx(args)`.

- `ASTValue`:
  - Updated `readKey` method signature to accept nullable `Object? key` parameter for better null safety.

- `ASTValueStatic`:
  - Updated `readKey` method signature to accept nullable `Object? key`.

## 0.1.21

- `CoreClassBase` and `CoreClassPrimitive`:
  - Added `_functionToString` external function returning the string representation of the instance.
- `CoreClassString`, `CoreClassInt`, `CoreClassDouble`, `CoreClassList`:
  - Added support for the `toString` core function, returning the respective `_functionToString`.

## 0.1.20

- `ASTSingleLineStatementBlock`:
  - Added new subclass of `ASTBlock` that allows only a single statement.
  - Overrides `addStatement` to enforce single statement constraint.
  - Overrides `toString` to output the single statement without braces.

- `ApolloCodeGenerator`:
  - Added support for `ASTSingleLineStatementBlock` in `generateASTNode` dispatch.
  - Added `generateASTSingleLineStatementBlock` method to generate single-line statement blocks.
  - Updated `generateASTBlock` to delegate to `generateASTSingleLineStatementBlock` if block is single-line.
  - Updated `generateASTBranchIfBlock` to generate single-line blocks without braces.

- `ApolloGenerator`:
  - Added abstract method `generateASTSingleLineStatementBlock`.
  - Added support for `ASTSingleLineStatementBlock` in `generateASTNode` dispatch.

- `ApolloGeneratorWasm`:
  - Implemented `generateASTSingleLineStatementBlock` to generate the single statement.

- Dart and Java11 grammars:
  - Added `ASTSingleLineStatementBlock` parsing support.
  - Added `codeBlockOrSingleLineBlock` parser to accept either a block or a single-line block.
  - Updated `branchIfBlock` parser to accept single-line blocks as branch bodies.

## 0.1.19

- Added new AST statement classes:
  - `ASTStatementBlock` representing a block of statements.
  - `ASTStatementFunctionDeclaration` representing a function declaration statement.

- `ApolloCodeGenerator`:
  - Added support for generating code for `ASTStatementFunctionDeclaration` and `ASTStatementBlock`.
  - Added methods `generateASTStatementFunctionDeclaration` and `generateASTStatementBlock`.

- `ApolloGenerator` interface:
  - Added abstract methods `generateASTStatementFunctionDeclaration` and `generateASTStatementBlock`.
  - Updated statement dispatch to handle `ASTStatementFunctionDeclaration` and `ASTStatementBlock`.

- `ApolloGeneratorWasm`:
  - Added `generateASTStatementBlock` implementation.
  - Added stub for `generateASTStatementFunctionDeclaration` (throws `UnimplementedError`).

- `apollovm_ast_statement.dart`:
  - Added `ASTStatementBlock` class wrapping an `ASTBlock` with proper context and run behavior.
  - Added `ASTStatementFunctionDeclaration` class wrapping an `ASTFunctionDeclaration` with run behavior registering the function in the context.

- `apollovm_ast_toplevel.dart`:
  - Extended `ASTFunctionDeclaration` with:
    - `toASTValueFunction` method to convert to `ASTValueFunction`.
    - `toFunction` method to convert to a Dart `Function` with limited support for zero or one positional parameter.
    - `resolveFunctionType` and `callFunctionTyped` helpers for function type resolution and invocation.

- `apollovm_ast_type.dart`:
  - Added `ASTTypeFunction` representing function types with optional return type and parameters.
  - Added `callCasted` helper method for generic type casting.

- `apollovm_ast_value.dart`:
  - Added `ASTValueFunction` wrapping a Dart `Function` with proper type and invocation support.
  - Implemented equality, hashCode, and string representation for `ASTValueFunction`.

- `apollovm_utils.dart`:
  - Added `resolveGeneric<T>()` helper function for generic type resolution.

- `dart_grammar.dart`:
  - Extended grammar to parse function declarations as top-level definitions and statements.
  - Added parsing support for `ASTStatementFunctionDeclaration` and `ASTStatementBlock`.
  - Allowed optional return type in function declarations.
  - Updated statement parser to include function declarations and blocks.

## 0.1.18

- `ASTExpressionObjectEntryFunctionInvocation`:
  - Added new AST expression class to represent calls to class object entry functions.
  - Implements function resolution and invocation on class instances or static context.
  - Overrides `run` and `toString` methods for execution and debugging.

- `ApolloCodeGenerator`:
  - Added support for generating code for `ASTExpressionObjectEntryFunctionInvocation`.
  - Updated `generateASTExpression` method to handle `ASTExpressionObjectEntryFunctionInvocation`.

- `ApolloGenerator` interface:
  - Added abstract method `generateASTExpressionObjectEntryFunctionInvocation`.

- `ApolloGeneratorWasm`:
  - Added stub implementation for `generateASTExpressionObjectEntryFunctionInvocation` throwing `UnimplementedError`.

- Dart and Java11 grammars:
  - Added parsing rule `expressionObjectEntryFunctionInvocation` to support syntax for object entry function invocation expressions.

## 0.1.17

- Added `ApolloImportManager` to manage package/library imports and resolve core packages.
- `VMContext`:
  - Made sealed class.
  - Added `importManager` field and `import` method to support import resolution and delegation to parent contexts.
  - Updated function and external function lookup to consider imported functions.
- Added `VMScopeContext` as a final subclass of `VMContext` for scoped runtime contexts.
- Updated `VMClassContext` and other runtime contexts to be final and use `VMScopeContext` for nested scopes.
- `ASTStatementImport`:
  - New AST node to represent import statements.
  - Supports running import in a context, throwing on failure.
- `ASTRoot`:
  - Supports tracking and running import statements.
  - Considers imported functions in function resolution.
- `ApolloRunner`:
  - Added `importManager` field and initialization with default import manager.
  - Supports auto-import of `dart:math` core package.
  - Passes `importManager` to execution and function lookup calls.
- `CorePackageBase` and `CorePackageMath`:
  - Added `path` getter for core package identification.
- Code generators (`dart`, `java11`, `wasm`):
  - Added support for generating import statements (`ASTStatementImport`).
- Dart and Java11 grammar:
  - Added parsing of import statements into `ASTStatementImport`.
- Test framework:
  - Added support for `auto-import-dart-math` attribute in test XML.
  - Tests updated to import `dart:math` and use `pow` function.
- Various runtime and AST classes:
  - Updated to use `VMScopeContext` instead of base `VMContext` for nested scopes.
  - Updated `VMObject` field value methods to use `VMScopeContext`.
- Minor fixes and improvements in import handling, context management, and code generation.

## 0.1.16

- `DartGrammarDefinition`:
  - Changed type of `finalExpressionOp` from `ASTExpressionOperation?` to `ASTExpression?`.
  - Updated cast of `expressionOp` from `ASTExpressionOperation` to `ASTExpression`.

## 0.1.15

- `ApolloCodeGenerator`:
  - `generateASTValueDouble`: replaced manual double string formatting with `ASTTypeDouble.doubleToString` for consistent double string representation.

- `ASTStatementVariableDeclaration`:
  - `_runImpl2`: updated type cast check to allow dynamic type to bypass cast validation.

- `ASTTypeDouble`:
  - Added static method `doubleToString` to format double values consistently, optionally allowing scientific notation.
  - Updated `toString` method of `ASTTypeNum` to return `'num'` instead of `'double'`.

- `ASTValueAsString` and `ASTValuesListAsString`:
  - Updated string conversion to use `valueToString` method that formats doubles using `ASTTypeDouble.doubleToString`.

- `CorePackageMath`:
  - Updated math function external static function wrappers to explicitly type parameters as `num` and return `ASTTypeDouble.instance` for functions returning double values.

- Test framework (`apollovm_languages_test_definition.dart`):
  - Moved output printing before output assertion in `_testCall` for clearer test logs.

## 0.1.14

- Added new `ASTExpression` subclass `ASTExpressionNegative` to represent unary negative expressions.
- Added new `ASTExpression` subclass `ASTExpressionGroupFunctionInvocation` to represent function calls on grouped expressions (e.g., `(-d).toStringAsFixed(4)`).
- `ApolloCodeGenerator`:
  - Updated `generateASTExpression` to handle `ASTExpressionNegative` and `ASTExpressionGroupFunctionInvocation`.
  - Added methods `generateASTExpressionNegative` and `generateASTExpressionGroupFunctionInvocation`.
  - Refactored function invocation code into private `_generateFunctionInvocation` helper.
- `ApolloGenerator` interface:
  - Added abstract methods `generateASTExpressionNegative` and `generateASTExpressionGroupFunctionInvocation`.
  - Updated `generateASTExpression` to support new expression types.
- `apollovm_ast_expression.dart`:
  - Added implementation of `ASTExpressionNegative` with type resolution, runtime evaluation, and string representation.
  - Added implementation of `ASTExpressionGroupFunctionInvocation` with function resolution and invocation logic.
- Dart and Java11 grammars:
  - Added parsing support for unary negative expressions (`-expr`).
  - Added parsing support for group function invocations (e.g., `(expr).func(args)`).
- `ApolloGeneratorWasm`:
  - Added stub implementations for `generateASTExpressionNegative` and `generateASTExpressionGroupFunctionInvocation`.
  - Updated expression generation dispatch to handle new expression types.

## 0.1.13

- `ASTStatementWhileLoop`:
  - Added new AST node class representing a while loop statement.
  - Implemented `run` method to execute the loop with proper context handling.
  - Added type resolution returning `ASTTypeVoid.instance`.
  - Added children and node resolution methods.

- `ApolloCodeGenerator`:
  - Added support for generating code for `ASTStatementWhileLoop` in `generateASTStatement`.
  - Implemented `generateASTStatementWhileLoop` method to generate while loop source code.

- `ApolloGenerator`:
  - Added abstract method `generateASTStatementWhileLoop`.
  - Added dispatch for `ASTStatementWhileLoop` in `generateASTStatement`.

- `DartGrammarDefinition`:
  - Added `statementWhileLoop` parser to parse while loop statements.
  - Integrated `statementWhileLoop` into the main `statement` parser.

- `Java11GrammarDefinition`:
  - Added `statementWhileLoop` parser to parse while loop statements.
  - Integrated `statementWhileLoop` into the main `statement` parser.

- `ApolloGeneratorWasm`:
  - Added stub for `generateASTStatementWhileLoop` method throwing `UnimplementedError`.
  - Added dispatch for `ASTStatementWhileLoop` in `generateASTStatement`.

- Tests:
  - Added new test `dart_basic_printFibonacci.test.xml` demonstrating while loop usage in Dart source and generated code.

## 0.1.12

- `ASTInvocableDeclaration`:
  - Replaced `ASTFunctionDeclaration` with generic `ASTInvocableDeclaration` for function and constructor declarations.
  - Added `ASTClassConstructorDeclaration` for class constructors with support for `this` parameters.
  - Added `resolveRuntimeType` method to support runtime type resolution with context and node.
  - Updated `call` and `run` methods to support async and context-aware execution.
  - Added `initializeVariables` for constructor variable initialization.

- `ASTParametersDeclaration`:
  - Made generic over parameter type `P`.
  - Added `ASTConstructorParametersDeclaration` and `ASTFunctionParametersDeclaration` subclasses.
  - Updated parameter accessors and type checks to use generic parameter type.

- `ASTParameterDeclaration`:
  - Added `ASTConstructorParameterDeclaration` with `thisParameter` flag.
  - Added extensions for filtering `this` parameters.

- `ASTFunctionSet` and `ASTConstructorSet`:
  - Introduced generic base `ASTInvokableSet` with single and multiple implementations.
  - Added `ASTConstructorSet` for constructors, similar to function sets.

- `ASTClassNormal`:
  - Added support for constructors with `ASTConstructorSet`.
  - Added methods to add, get, and check constructors by name and signature.
  - Updated `resolveNode` to resolve constructors.

- `ASTRoot`:
  - Updated `getFunction` to return constructors if matching class name and signature.

- `ASTExpression` and `ASTValue`:
  - Added `resolveRuntimeType` and `getHashcodeValue` methods for runtime type and value hashing.
  - Updated equality and hashCode to use `getHashcodeValue`.

- `ASTExpressionFunctionInvocation` and subclasses:
  - Updated to use `ASTInvocableDeclaration` for function retrieval.
  - Updated `run` method to support async and context-aware invocation.

- `ASTExpressionObjectGetterAccess`:
  - Updated getter retrieval and runtime type resolution to support async and context-aware evaluation.
  - Added `_runGetter` helper for getter invocation.

- `ASTStatementVariableDeclaration`:
  - Added `unmodifiable` flag.
  - Updated type resolution and run implementation to use `resolveRuntimeType`.

- `ASTType`:
  - Added `ASTTypeConstructorThis` singleton for constructor `this` parameter.
  - Added `resolveRuntimeType` method.

- `ASTVariable`:
  - Added `resolveRuntimeType` method.

- `CorePackageBase` and `CoreClassMixin`:
  - Updated external function and class function creation to use `ASTFunctionParametersDeclaration`.

- `CoreClassList`:
  - Added `first` and `last` getters with runtime component type resolution.
  - Added empty constructor list and related methods.

- `DartGrammarDefinition` and `Java11GrammarDefinition`:
  - Added parsing support for class constructors with parameters and optional blocks.
  - Updated function and constructor parameter parsing to use `ASTFunctionParametersDeclaration` and `ASTConstructorParametersDeclaration`.
  - Added parsing for `this` constructor parameters.

- `ApolloCodeGeneratorDart` and `ApolloCodeGeneratorJava11`:
  - Added `generateASTClassConstructorDeclaration` method to generate constructor code.
  - Updated function parameter generation to use generic parameter declaration.

- `ApolloParserWasm`:
  - Updated WASM function parsing to use `ASTFunctionParametersDeclaration`.

- `Test`:
  - Added new test `dart_basic_linearRegression.test.xml` with Dart source for linear regression and forecast.
  - Added new test `dart_basic_calculateShippingCost.test.xml` for shipping cost calculation.
  - Updated test runner to include new tests.

## 0.1.11

- `ASTValueNum`:
  - `from` method:
    - Added optional `asDouble` parameter to control numeric type coercion.
    - Improved parsing logic to preserve numeric intent from strings containing decimal points or exponents by forcing double representation.
    - Added error handling for unsupported input types when `asDouble` is specified.

- Added `ASTExpressionNullValue` class to represent `null` literal expressions.
- `ASTScopeVariable`:
  - Special handling for variable named `'null'` to resolve as `ASTValueNull`.
- `ApolloCodeGenerator`:
  - Added `generateASTExpressionNullValue` method to generate code for `null` expressions.
  - Updated `generateASTExpression` to handle `ASTExpressionNullValue`.
  - `generateASTValueDouble`:
    - Fixed formatting of double values to ensure consistent decimal representation.
    - Added handling to convert scientific notation doubles to fixed decimal format with appropriate fraction digits.
  - Added helper method `fractionDigitsFromScientificNotation` to determine the number of fraction digits needed for doubles in scientific notation.

- `ApolloGenerator` interface:
  - Added `generateASTExpressionNullValue` method.
  - Updated `generateASTExpression` to handle `ASTExpressionNullValue`.
- `ApolloRunner`:
  - Added optional `importCorePackageMath` parameter to constructor and `createRunner` method.
  - When `importCorePackageMath` is true, maps math functions from `CorePackageMath` to external functions.
- `CorePackageMath`:
  - New core package providing Dart `dart:math` functions as external functions for ApolloVM.
  - Includes `pow`, `sqrt`, `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `atan2`, `log`, `exp`, `abs`, `min`, `max`.
- Language grammars (`dart`, `java11`):
  - Added parsing support for `null` literal expressions producing `ASTExpressionNullValue`.
- Language runners (`dart`, `java11`, `wasm`):
  - Added support for `importCorePackageMath` parameter in constructors.
- `ApolloGeneratorWasm`:
  - Added stub for `generateASTExpressionNullValue` throwing `UnimplementedError`.
  - Updated `generateASTExpression` to handle `ASTExpressionNullValue`.
- Test framework:
  - Added new test `dart_basic_stdv.test.xml` demonstrating usage of math functions (`pow`, `sqrt`) and `null` checks.
  - Updated test runner to create runners with `importCorePackageMath: true` to enable math functions in tests.

## 0.1.10

- `ASTAssignmentOperator`:
  - Added new operator `divideAsInt` with symbol `'~/'`.
  - Updated `asASTExpressionOperator` getter to support `divideAsInt`.
  - Updated `getASTAssignmentOperator` and `getASTAssignmentOperatorText` to handle `divideAsInt` and its assignment form `'~/='`.
- `ASTExpressionVariableAssignment`:
  - Added support for `divideAsInt` operator in evaluation and string representation.
- Dart grammar (`dart_grammar.dart`):
  - Extended `assigmentOperator` parser to recognize `'~/='` operator.
- Java11 grammar (`java11_grammar.dart`):
  - No changes for `divideAsInt` operator (remains unsupported).

## 0.1.9

- `ASTExpressionListLiteral`:
  - `resolveType`: updated to return `ASTTypeArray` of the specified type or deduced common element type.
  - `children`: fixed to include `type` correctly.

- `ASTStatementVariableDeclaration`:
  - Constructor enhanced to handle `ASTExpressionListLiteral` values with type adjustments or cast exceptions.

- `ASTStatementForEach`:
  - Added `variableType` field.
  - Constructor updated to accept `variableType`.

- `ASTType`:
  - Added `commonType` method to find common compatible type between two types.

- `ASTTypeArray`:
  - `toValue`: improved to cast `ASTValueArray` to correct generic type if needed.

- `ASTValueArray`:
  - Added `cast` method to convert to another generic type with optional component type.

- Dart grammar (`dart_grammar.dart`):
  - `statementForEach` parser updated to parse explicit variable type before variable name.
  - `expressionListLiteral` parser updated to infer common element type if not specified.

- Java11 grammar (`java11_grammar.dart`):
  - `statementForEach` parser updated to parse explicit variable type before variable name.

- Tests:
  - Added Dart test for `findMax(List<int> numbers)` function with multiple test cases including empty list handling.

## 0.1.8

- `ASTStatementForEach`:
  - Added new AST statement class representing a for-each loop with a variable name, iterable expression, and loop block.
  - Implements `run` method to iterate over an iterable AST value, declaring the loop variable in a nested context and running the loop block.
  - Resolves type as `void`.

- `ApolloCodeGenerator`:
  - Added support for generating code for `ASTStatementForEach` in `generateASTStatement`.
  - Implemented `generateASTStatementForEach` method to output a for-in loop syntax with variable declaration and loop block.

- `ApolloGenerator`:
  - Added abstract method `generateASTStatementForEach`.
  - Updated `generateASTStatement` to dispatch to `generateASTStatementForEach` for `ASTStatementForEach`.

- Dart language grammar (`dart_grammar.dart`):
  - Added parser `statementForEach` to parse Dart-style for-each loops (`for (var x in iterable) { ... }`).
  - Added helper parser `_forEachVariableDecl` to parse optional `var` or `final` before variable name.

- Java language grammar (`java11_grammar.dart`):
  - Added parser `statementForEach` to parse Java-style for-each loops (`for (Type var : iterable) { ... }`).

## 0.1.7

- CI:
  - `.github/workflows/dart.yml`: updated `actions/checkout` from v3 to v6 and `codecov/codecov-action` from v3 to v5.

- `apollovm.dart`:
  - Exported new utility file `src/apollovm_utils.dart`.

- `apollovm_runner.dart`:
  - `ApolloRunner`:
    - `executeClassMethod`: changed to async, added parameter normalization before execution.
    - Added `normalizeParameters` method to normalize positional and named parameters against AST function declarations.
    - `executeFunction`: added parameter normalization for top-level functions.
    - Improved parameter handling for function execution.

- `apollovm_utils.dart` (new):
  - Added utilities for generic typed list conversion and case-insensitive map key lookup.
  - Extensions on `List` for typed list creation and on `Map` for case-insensitive key lookup.

- `apollovm_ast_toplevel.dart`:
  - `ASTFunctionDeclaration`:
    - Added `normalizeParameters`, `normalizePositionalParameters`, and `normalizeNamedParameters` methods to convert and normalize parameters according to function declarations.
  - Added extension `IterableASTFunctionDeclarationExtension` with `resolveBestMatchBySignature` to select best matching function overload by parameter signature.

- `apollovm_ast_type.dart`:
  - `ASTType`:
    - Added `fromType` factory to create ASTType from Dart `Type`.
    - Added `toASTValue` method to convert native values to ASTValue according to type.
  - Added `toASTValue` overrides in primitive and collection types (`ASTTypeBool`, `ASTTypeNum`, `ASTTypeInt`, `ASTTypeDouble`, `ASTTypeString`, `ASTTypeNull`, `ASTTypeVoid`, `ASTTypeArray`, `ASTTypeArray2D`, `ASTTypeMap`, `ASTTypeFuture`).
  - Added static `fromType` methods for `ASTTypeArray` and `ASTTypeMap` to create instances from Dart generic types.
  - `ASTTypeArray` and `CoreClassList`:
    - Added typed singleton instances for common generic types (e.g., `List<String>`, `List<int>`, etc.).
    - Added factory constructors and `fromType` methods to resolve types generically.
  - `ASTTypeMap`:
    - Added `fromType` method for common map generic types.
  - `ASTTypeFuture`:
    - Added `toASTValue` override to handle conversion from native or future values.

- `apollovm_ast_value.dart`:
  - `ASTValue.from` factory:
    - Added support for `ASTTypeBool` to create `ASTValueBool`.

- `apollovm_core_base.dart`:
  - `ApolloVMCore.getClass`:
    - Added optional `generics` parameter.
    - `List` class resolution now uses `CoreClassList.fromType` with generic type.
  - `CoreClassList`:
    - Converted to generic class `CoreClassList<T>`.
    - Added typed singleton instances for common generic types.
    - Added `fromType` static method to resolve generic list classes.
    - Constructor updated to accept generic type and resolve `ASTTypeArray` accordingly.

- `wasm_runner.dart`:
  - `ApolloRunnerWasm`:
    - Added parameter normalization before calling Wasm functions.

- `wasm_runtime.dart`:
  - Added `ensureBooted()` method and `lastBootError` getter to `WasmRuntime` interface.

- `wasm_runtime_dart_html.dart`, `wasm_runtime_generic.dart`, `wasm_runtime_web.dart`:
  - Implemented `ensureBooted()` as no-op and `lastBootError` as null.

- `wasm_runtime_io.dart`:
  - Added boot logic with error capture.
  - Implemented `ensureBooted()` to call boot.
  - Added `lastBootError` getter.

- Tests (`apollovm_languages_test_definition.dart`):
  - Updated `_parseJsonList` to return untyped `List` without generic type conversion.
  - Removed redundant generic list conversion helpers from test file.
  - Updated tests to call `.toListOfType()` extension for typed list checks.

- Tests (`apollovm_wasm_test.dart`):
  - Added call to `wasmRuntime.ensureBooted()` before checking support.
  - On unsupported runtime, print last boot error for diagnostics.

## 0.1.6

- Added support for external getters in `ApolloVM`:
  - New class `ApolloExternalGetterMapper` to map Dart getters to ApolloVM.
  - Added `getGetter` and `getMappedExternalGetter` methods in `VMContext` for getter resolution.
  - Extended `ASTBlock` with getter management (`addGetter`, `getGetter`, etc.).
  - Added `ASTGetterDeclaration` and related classes (`ASTClassGetterDeclaration`, `ASTExternalGetter`, `ASTExternalClassGetter`) to represent getters in the AST.
  - Added `ASTExpressionGetterAccess` base class and subclasses `ASTExpressionLocalGetterAccess` and `ASTExpressionObjectGetterAccess` for getter expressions.
  - Updated `DartGrammarDefinition` to parse getter access expressions.
  - Updated `ApolloCodeGenerator` and `ApolloGenerator` interfaces and implementations to generate code for getter access expressions.
  - Added `externalGetterMapper` field to `VMContext` to support external getter mapping.

- Core library updates:
  - Added `CoreClassList` class implementing core `List` type support with external class functions and getters for common list operations (`add`, `remove`, `length`, `isEmpty`, `sublist`, etc.).
  - Refactored core class base and primitive classes to use `CoreClassMixin` for external function and getter creation.

## 0.1.5

- `ASTExpressionOperator`:
  - Added new operators: `remainder`, `and`, `or`.
  - Updated `getASTExpressionOperator` and `getASTExpressionOperatorText` to support `%`, `&&`, and `||`.

- `ASTExpressionOperation`:
  - Updated `resolveType` to handle `remainder`, `and`, and `or` operators.
  - Added evaluation methods:
    - `operatorRemainder` for `%` operator supporting int and double operands.
    - `operatorAnd` and `operatorOr` for logical `&&` and `||` with boolean coercion.
  - Added private helper `_toBoolean` to convert various `ASTValue` types to boolean.
  - Updated `throwOperationError` to handle new operators.

- `ASTValue` and subclasses:
  - Added `%` operator support in `ASTValueNum`, `ASTValueInt`, and `ASTValueDouble`.
  - Fixed incorrect error messages in base `ASTValue` operator overrides.
  - Added `operator ~/(ASTValue other)` implementations in `ASTValueInt` and `ASTValueDouble`.
  - Updated operator return types for numeric operations to be more specific (`ASTValueNum`).

- `DartGrammarDefinition`:
  - Extended `expressionOperator` parser to recognize `%`, `&&`, and `||`.
  - Updated expression parsing logic to:
    - Split expressions into blocks separated by logical operators `&&` and `||`.
    - Resolve `%` operator with higher precedence within blocks.
    - Correctly build AST for logical expressions combining blocks with `&&` and `||`.

- `WasmGenerator`:
  - Added default case throwing `UnsupportedError` for unsupported operators in WASM code generation.

## 0.1.4

- `ASTTypeVar`:
  - Added `unmodifiable` field to distinguish `var` and `final` types.
  - Added static instance `instanceUnmodifiable` for `final`.
  - Updated constructor to accept `unmodifiable` flag and set name accordingly.
  - Updated `toString` and equality to reflect `unmodifiable` state.

- `ApolloVMCore`:
  - Added support for `double` and `Double` core classes returning `CoreClassDouble`.

- `CoreClassPrimitive`:
  - Added helper `_externalClassFunctionArgs2` for external class functions with two parameters.

- `CoreClassString`:
  - Added many new external class functions:
    - `length`, `isEmpty`, `isNotEmpty`
    - `substring`, `indexOf`, `startsWith`, `endsWith`
    - `trim`, `split`, `replaceAll`
  - Updated `getFunction` to support these new string functions.

- `CoreClassInt`:
  - Added external static function `tryParse`.
  - Added external class functions:
    - `compareTo`, `abs`, `sign`, `clamp`, `remainder`, `toRadixString`, `toDouble`
  - Updated `getFunction` to support new int functions.

- Added new class `CoreClassDouble`:
  - External static functions: `parseDouble` (alias `parse`), `tryParse`, `valueOf`.
  - External class functions: `compareTo`, `abs`, `sign`, `clamp`, `remainder`,
    `toStringAsFixed`, `toStringAsExponential`, `toStringAsPrecision`,
    `toInt`, `round`, `floor`, `ceil`, `truncate`.
  - Implements `getFunction` to provide these functions.

- `ApolloCodeGeneratorDart`:
  - Improved string literal concatenation handling:
    - Added support for concatenating multiple string literals including raw and multiline strings.
    - Added helper `writeAllStrings` to write concatenated string parts correctly.
    - Improved splitting and merging of string literal blocks to avoid unnecessary concatenations.
    - Preserves multiline string formatting and raw string prefixes.

- `DartGrammarDefinition`:
  - Added support for `final` keyword returning `ASTTypeVar(unmodifiable: true)`.
  - Updated `literalString` parser to support concatenation of multiple string literals into `ASTValueStringConcatenation`.

- `Java11GrammarDefinition`:
  - Added support for `final` keyword returning `ASTTypeVar(unmodifiable: true)`.

## 0.1.3

- `DartGrammarDefinition`:
  - `getTypeByName`: added support for Dart types `void` and `bool`.

- `DartGrammarLexer`:
  - `stringContentQuotedLexicalTokenEscaped`: added handling of unnecessary escape sequences for characters `(`, `)`, `{`, `}`, and space in string literals.

- Tests:
  - Added `dart_basic_sumOrDouble.test.xml` with a test for a Dart function `sumOrDouble`.
  - Added `dart_basic_main_print_multi_line.test.xml` testing multi-line string printing.
  - Added `dart_basic_main_print_unnecessary_escape.test.xml` testing string literals with unnecessary escape sequences and ASCII art printing.

## 0.1.2

- `ApolloCodeGenerator` and `ApolloCodeGeneratorDart`:
  - `generateASTExpressionOperation`: updated to conditionally group complex expressions with parentheses based on operator and presence of literal strings to improve expression formatting and string interpolation merging.
  - Improved string concatenation merging for `add` operator when involving variables and literal strings.

- `ASTExpression` and subclasses (`ASTExpressionOperation`, `ASTExpressionVariableAssignment`, `ASTExpressionVariableDirectOperation`, `ASTExpressionNegation`, `ASTExpressionFunctionInvocation`, etc.):
  - Added `isComplex` getter to distinguish complex expressions.
  - Added `hasLiteralString` and `hasDescendantLiteralString` to detect literal strings in expression trees.
  - Updated `toString` methods to support optional grouping with parentheses for clarity.
  - Updated `ASTExpressionOperation.toString` to optionally wrap expressions in parentheses.
  - Updated `ASTExpressionVariableAssignment` and `ASTExpressionVariableDirectOperation` to provide detailed `toString` implementations reflecting operators.
  - Added `childrenOperations` and `descendantChildrenOperations` helpers for expression traversal.

- `ASTAssignmentOperator` enum:
  - Added `symbol` field for operator symbol representation.

## 0.1.1

- `lib/apollovm.dart`:
  - Added library-level documentation describing ApolloVM as a portable VM supporting Dart, Java, and WebAssembly compilation.
  - Changed `library apollovm;` to a library directive without a name.

- AST classes (`lib/src/ast/`):
  - Updated `children` getters to use null-aware spread operators (`...?` and `?`) for optional fields in:
    - `ASTExpressionListLiteral`
    - `ASTExpressionMapLiteral`
    - `ASTStatementVariableDeclaration`
    - `ASTBranchIfElseBlock`
    - `ASTBranchIfElseIfsElseBlock`
    - `ASTType`
    - `ASTTypeGenericVariable`

- `pubspec.yaml`:
  - Updated dependencies:
    - `petitparser` from `^6.1.0` to `^7.0.2`
    - `lints` from `^3.0.0` to `^6.1.0`
    - `dependency_validator` from `^3.2.3` to `^5.0.5`
    - `xml` from `^6.5.0` to `^6.6.1`

- Tests (`test/apollovm_languages_extended_test.dart`, `test/apollovm_version_test.dart`):
  - Added `library;` directive at the top of test files for consistency.

## 0.1.0

- `WasmRuntime`:
  - Added `WasmModuleFunction` typedef to represent a WebAssembly-exported function with metadata including the Dart function and a `varArgs` flag.
  - Updated `WasmModule.getFunction` signature to return `WasmModuleFunction<F>?` instead of just `F?`.

- `WasmRunnerWasm`:
  - Updated function invocation logic in `ApolloRunnerWasm` to handle `WasmModuleFunction` with `varArgs` flag.
  - Added special handling for functions with no arguments and functions expecting a single `List` argument.

- `wasm_runtime_generic.dart`:
  - Updated `WasmModuleGeneric.getFunction` to return `null` as `WasmModuleFunction<F>?`.

- `wasm_runtime_io.dart`:
  - Updated `WasmModuleIO.getFunction` to return a `WasmModuleFunction` with `varArgs: true`.

- `wasm_runtime_dart_html.dart`:
  - Deprecated `WasmRuntimeDartHTML` in favor of `WasmRuntimeWeb`.
  - Updated `WasmModuleBrowser.getFunction` to return a `WasmModuleFunction` with `varArgs: true`.
  - Updated `createWasmRuntime` to return `WasmRuntimeDartHTML` with deprecation warning.

- `wasm_runtime_web.dart`:
  - New `WasmRuntimeWeb` implementation using `dart:js_interop` and `web` package.
  - Added JS interop bindings for WebAssembly APIs using extension types.
  - Implemented `WasmModuleBrowser` wrapping `_WasmInstance` with proper JS interop.
  - `getFunction` returns a Dart function wrapping JS function calls with argument conversion and `varArgs: false`.
  - Added utilities to convert JS BigInt to Dart `num` or `BigInt`.
  - Updated `createWasmRuntime` to return `WasmRuntimeWeb`.
  - Added extensions for JS function invocation and JSAny type checks and casts.

- `pubspec.yaml`:
  - Added dependency on `web: ^1.1.1`.

- Tests:
  - Added new tests `operation3` and `operation4` verifying multi-parameter Dart functions compiled to Wasm and executed correctly.

## 0.0.54

- Updated minimum Dart SDK constraint to `>=3.10.0 <4.0.0`.
- Dependency updates:
  - `swiss_knife`: ^3.3.14
  - `async_extension`: ^1.2.22
  - `data_serializer`: ^1.2.1
  - `petitparser`: ^6.1.0
  - `collection`: ^1.19.1
  - `args`: ^2.7.0
  - `wasm_run`: ^0.1.0+2
  - `crypto`: ^3.0.7
  - `path`: ^1.9.1
  - `test`: ^1.31.0


- Reformatted code for Dart 3.10+

- `lib/src/languages/wasm/wasm_runtime_browser.dart`
  - Suppress deprecated `dart:html` usage warning with
    `// ignore: deprecated_member_use` import directive

## 0.0.53

- wasm_run: ^0.1.0+1

## 0.0.52

- New `ASTExpressionVariableDirectOperation` (`++` and `--` operators).

- New `StrictType` interface for `equalsStrict` over `ASTTypeInt` and `ASTTypeDouble`.

- `ApolloGeneratorWasm`:
  - Improve auto casting to int32/int64 and float32/float64.
  - Implemented `generateASTExpressionVariableDirectOperation`.

## 0.0.51

- sdk: '>=3.3.0 <4.0.0'

- swiss_knife: ^3.2.0
- data_serializer: ^1.1.0
- petitparser: ^6.0.2
- path: ^1.9.0

- lints: ^3.0.0
- dependency_validator: ^3.2.3
- test: ^1.25.2
- xml: ^6.5.0

## 0.0.50

- `WasmRuntime`: new VM implementation.
- `wasm_runtime_io.dart`:
- Dart CI: wasm_run:setup (install dynamic library)
- wasm_run: ^0.0.1+3

## 0.0.49

- `ASTTypeDouble`:
  - `acceptsType`: now also accepts an `ASTTypeInt`.
- `wasm_generator.dart`:
  - Fix `isBits64`.
- Improve Wasm test coverage.

## 0.0.48

- `ASTNode`: 
  - Now is a mixin.
  - `getNodeIdentifier`: added optional parameter `requester`.
  - Added `children` and `descendantChildren`.
- `ASTFunctionDeclaration`:
  - `getNodeIdentifier`: now can also resolve identifiers inside statements.
 
- Wasm:
  - Encode function names with UTF-8.
  - `Wasm64`: added `i64WrapToi32`.
- `WasmContext`:
  - Added `returns` state. 
- `ApolloGeneratorWasm`:
  - Added `_autoConvertStackTypes`.
  - `generateASTStatementReturnValue` and `generateASTStatementReturnVariable`:
    - Auto cast returning types. 

- Dart CI: added job `test_exe`.

## 0.0.47

- Improve variable type resolution while compiling to Wasm.

## 0.0.46

- Improve type resolution of `ASTTypeVar`.
- Optimize some `async` methods.

## 0.0.45

- `ASTBranchIfElseBlock` and `ASTBranchIfElseIfsElseBlock`:
  - `blockElse`: optional.
- `ASTParametersDeclaration`:
  - Added `allParameters`.
- `ASTTypeInt` and `ASTTypeDouble`:
  - Added `bits`
  - Added `ASTTypeInt.instance32` and `ASTTypeInt.instance64`.
  - Added `ASTTypeDouble.instance32` and `ASTTypeDouble.instance64`.
- `ASTValueNum`:
  - Added field `negative`.

- `ApolloGeneratorWasm`:
  - Changed to 64 bits.
  - `Wasm`: split in `Wasm32` and `Wasm64` with improved opcodes.
  - Allow operations with different types (auto casting).
  - Handle `unreachable` end of function cases.
  - Implemented:
    - `generateASTValue`, `generateASTValueDouble`, `generateASTValueInt`.
    - `generateASTExpressionVariableAssignment`, `generateASTStatementExpression`
    - `generateASTBranchIfBlock`, `generateASTBranchIfElseBlock`, `generateASTBranchIfElseIfsElseBlock`.
    - `generateASTStatementReturnWithExpression`, `generateASTStatementReturn`, `generateASTStatementReturnValue`.

- `ApolloParserWasm`:
  - Identify if an `ASTTypeInt` or `ASTTypeDouble` type is a `32` or `64` bits. 

- `ApolloRunnerWasm`:
  - Use the parsed Wasm functions (AST) to normalize the parameters before calling the Wasm function.  

- `WasmModule`:
  - Added `resolveReturnedValue`.
    - Browser implementation: when the function returns a `f64`, the JS `bigint` needs to be converted to a Dart `BigInt`.
- New `WasmModuleExecutionError`.

## 0.0.44

- `pubspec.yaml`: update description.

## 0.0.43

- `ApolloRunner`:
  - `getFunctionCodeUnit`: fix returned codeUnit when `allowClassMethod = true`.

## 0.0.42

- New `SourceCodeUnit` and `BinaryCodeUnit`.
  - `CodeUnit` now is `abstract`:
    - Renamed field `source` to `code`.
- Using `SourceCodeUnit` instead of `CodeUnit` when necessary.
- `ApolloParser` renamed to `ApolloCodeParser`:
  - Allows binary code parsing (not only strings).
  - New `ApolloSourceCodeParser`.
- `ApolloRunner`:
  - Added `getFunctionCodeUnit`.
- Using `Leb128` from package `data_serializer`.
- `BytesOutput` now extends `BytesEmitter` (from `data_serializer`).
- `ApolloGeneratorWasm`:
  - `generateASTExpressionOperation`: allow operations with different types (auto casting from `int` to `double`).
- New `WasmRuntime` and `WasmModule`.
  - Implementation: `WasmRuntimeBrowser`.
- New `WasmModuleLoadError`.
- `WasmContext`:
  - Added stack status to help code generation. 

- data_serializer: ^1.0.11
- wasm_interop: ^2.0.1
- crypto: ^3.0.3
- path: ^1.8.3

## 0.0.42+alpha

- Renamed `ApolloLanguageRunner` to `ApolloRunner`.
- Organize runners implementation files.

## 0.0.41

- `README.md`: added Wasm example.
- Minor fixes.

## 0.0.40

- New `ApolloGeneratorWasm`.
  - Basic support to compile the AST tree to Wasm.
- New `BytesOutput` for binary code generation.

- data_serializer: ^1.0.10

## 0.0.39

- `ApolloVMNullPointerException` and `ApolloVMCastException` now extends `ApolloVMRuntimeError`.
- AST implementation:
  - Changes some `StateError` while executing to `ApolloVMRuntimeError`.
- New abstract `ApolloCodeUnitStorage`:
  - Implementations:
    - `ApolloSourceCodeStorage`, `ApolloSourceCodeStorageMemory`.
    - `ApolloBinaryCodeStorage`, `ApolloBinaryCodeStorageMemory`.
    - `ApolloGenericCodeStorageMemory`.
- `ApolloGenerator` now defines the output type.
- New `GeneratedOutput`.

## 0.0.38

- `pubspec.yaml`:
  - Added issue_tracker
  - Added topics.
  - Added screenshots.
- `README.md`:
  - Added `Codecov` badge and link.

## 0.0.37

- Update `pubspec.yaml` description.
- `README.md`: added TODO list.

## 0.0.36

- `ApolloCodeGenerator`:
  - `generateASTValueStringExpression`: try to preserve single quotes in concatenations sequence.
- Java 11:
  - Added support for `ArrayList` and `HashMap` literals. 

## 0.0.35

- `ASTRoot`:
  - Added `getClassWithMethod`.
- `CodeNamespace`:
  - Added `getCodeUnitWithClassMethod`.
- `ApolloLanguageRunner`:
  - `executeFunction`: added parameter `allowClassMethod`.
- Added `ASTExpressionListLiteral` and `ASTExpressionMapLiteral`:
  - Support in `dart` and `java` grammar.

## 0.0.34

- `ApolloVM`:
  - `loadCodeUnit` now throws a `SyntaxError` with extended details.
- `ParseResult`:
  - Added fields `codeUnit`, `errorPosition` and `errorLineAndColumn`.
  - Added getters `errorLine` and `errorMessageExtended`
- Added `ASTExpressionNegation`:
  - Added support for `dart` and `java11`. 

## 0.0.33

- `ASTNode` implementations:
  - Implement `toString` with a pseudo-code version of the node to facilitate debugging. 
- Fixed parsing of comments in Dart and Java 11.

## 0.0.32

- Dart CI: update and optimize jobs.

- sdk: '>=3.0.0 <4.0.0'

- swiss_knife: ^3.1.5
- async_extension: ^1.2.5
- petitparser: ^6.0.1
- collection: ^1.18.0
- args: ^2.4.2
- lints: ^2.1.1
- test: ^1.24.6
- xml: ^6.4.2
- path: ^1.8.3

## 0.0.31

- Improved GitHub CI:
  - Added browser tests. 
- Optimize imports.
- Clean code and new lints adjusts.
- sdk: '>=2.15.0 <3.0.0'
- swiss_knife: ^3.1.1
- async_extension: ^1.0.9
- petitparser: ^5.0.0
- collection: ^1.16.0
- args: ^2.3.1
- lints: ^2.0.0
- dependency_validator: ^3.2.2
- test: ^1.21.4
- pubspec: ^2.3.0
- xml: ^6.1.0
- path: ^1.8.2

## 0.0.30

- Using `async_extension` to optimize async calls.
  - Removed internal extensions with similar functionality.
- Migrated from `pedantic` to `lints`.
- Fixed missing await in `ASTExpressionVariableAssignment`.
- lints: ^1.0.1
- swiss_knife: ^3.0.8
- async_extension: ^1.0.6
- petitparser: ^4.2.0

## 0.0.29

- Improve `ApolloVMCore`:
  - Implementing portable `int` class for `dart` and `java11`:
    - `parse`, `parseInt`.
- Code generation:
  - Correctly normalize `int` and `Integer` for `dart` and `java11`.
- Improve `async` optimization.

## 0.0.28

- Implement static class accessor, to allow calls to static functions.
- Initial version of `ApolloVMCore`:
  - Implementing portable `String` class for `dart` and `java11`:
    - Mapping: `contains`, `toUpperCase`, `toLowerCase`, `valueOf`.
- Fixed class field code generation for `dart` and `java11`.
- `async` optimization:
  - Avoid instantiation of `Future`, using `FutureOrExtension` and
    `ListFutureOrExtension`:
    - `resolve`, `resolveMapped` and `resolveAllMapped`.
- Improved languages tests, to also executed regenerated code.

## 0.0.27

- Runner:
  - Strong types.
    - `var` types can be resolved.
    - `ASTTypedNode`: nodes can be typed,
      and resolution is performed and cached while running.
  - Optimize resolution of functions.
- Grammar:
  - Dart & Java:
    - `var` types to be resolved at runtime.

## 0.0.26

- Generator:
  - Dart & Java:
    - Improve String concatenation with variables. 

## 0.0.25

- Grammar:
  - Dart & Java:
    - Added `for` loop statement: `ASTStatementForLoop`.
- Adjust `README.md`.

## 0.0.24

- `ApolloVM`:
  - `parseLanguageFromFilePathExtension`
- `ApolloLanguageRunner`:
  - `tryExecuteFunction`
  - `tryExecuteClassFunction`
- Executable:
    - `apollovm`
- args: ^2.0.0
- pubspec: ^2.0.1
- path: ^1.8.0

## 0.0.23

- Improve tests, to tests definitions directory of XML files.

## 0.0.22

- `caseInsensitive` option for:
  - setField, getField, getFunctionWithName, getFunction,getClass 

## 0.0.21

- Better handling of function signature and how to pass positional and named parameters.

## 0.0.20

- Added `ASTClass.getFieldsMap`.
- `ASTEntryPointBlock.execute` with extra parameters `classInstanceObject` and `classInstanceFields`.
- Change signature of`dartRunner.executeFunction` and `javaRunner.executeClassMethod`.
  - Now they use named parameters for `positionalParameters` and `namedParameters`.

## 0.0.19

- Grammar:
  - Java & Dart:
    - Parse boolean literal.
- Improve API documentation.

## 0.0.18

- API Documentation.

## 0.0.17

- Fix call of function using `dynamic` type in parameter value.
- Code Generator:
  - Better formatting for classes and methods. 
- Grammar:
  - Dart:
    - Fix parsing of function with multiple parameters.
  - Java:
    - Class fields.
    - Fix parsing of function with multiple parameters.
    - Return statements ;

## 0.0.16

- Grammars:
  - Dart & Java11:
    - Fix parsing of multiple parameters.
- Runner:
  - Fix division with double and int.
- Code Generator:
  - Dart & Java11:
    - Fix variable assigment duplicated ';'.
  - Dart:
    - Improve string template regeneration, specially when
    parsed code comes from Java.
- Improved example.

## 0.0.15

- `ASTBlock`: added `functionsNames`.
- `ASTClass`: added `fields` and `fieldsNames`.
- `ApolloLanguageRunner`: added `getClass`.

## 0.0.14

- AST:
  - `ASTClassFunctionDeclaration`:
    To ensure that any class function is parsed from a class block
    and also ensure that is running from a class block.
- Generator:
  - Dart:
    - Fix non class function: due static modifier.
  - Java:
    - Will throw an exception if the generation of a function without
      a class is attempted.
- Runner:
  - Fix class object instance context.

## 0.0.13

- Grammar & Runner:
  - Dart & Java: 
    - Class fields.
    - Class object instance fields at runtime.
- Code Generator:
  - Dart & Java: 
    - Fix return statement with value/expression ;
  - Java:
    - Better/shorter code for String concatenation.

## 0.0.12

- Grammars & Code Generators & Runner:
  - Dart & Java11:
    - Better definition of static methods.
    - Class object instance.

## 0.0.11

- Renamed:
  - `ASTCodeBlock` -> `ASTBlock`. 
  - `ASTCodeRoot` -> `ASTRoot`.
  - `ASTCodeClass` -> `ASTClass`.
- Added support to `async` calls in `ASTNode` execution.
  - Any part of an `ASTNode` can have an `async` resolution.
    This allows the mapping of external functions that
    returns a `Future` or other languages that accepts
    `async` at any point.
- Better mapping of external functions:
  - Better Identification of number of parameters of mapped
    functions.
- Now an `ASTRoot` or an `ASTClass` are initialized:
  - Class/Root statements are executed once, and a context for
    each Class/Root is held during VM execution.

## 0.0.10

- Refactor:
  - Split `apollovm_ast.dart` into multiple `ast/apollovm_ast_*.dart` files.

## 0.0.9

- Code Generators:
  - Fix `else` branch indentation.

## 0.0.8

- Fix package description.
- Renamed Java8 to Java11:
  - Java 11 is closer to Dart 2 than Java 8.
- Grammars & Code Generators:
  - Dart & Java11:
    - Support `if`, `else if` and `else` branches. 

## 0.0.7

- Added type `ASTTypeBool` and value `ASTValueBool`.
- Added `ApolloVMNullPointerException`.
- Grammars & Code Generators:
  - Dart & Java8:
    - Support to expression comparison operators `==`, `!=`, `>`, `<`, `>=`, `<=`.
- Upgrade: petitparser: ^4.1.0

## 0.0.6

- Grammars:
  - Dart:
    - Added support for string templates:
      - including variable access: `$x`.
      - including expressions: `${ x * 2 }`.
      - Not implemented for multiline string yet.
  - Java8:
    - Support for string concatenation.
- Code Generators:
  - Java8:
    - Translate string templates to Java String concatenations.

## 0.0.5

- Grammars:
  - Dart:
    - Raw single line and raw multiline line strings.
    - Improved parser tests for literal String.

## 0.0.4

- Added type check:
  - `ASTType.isInstance`.
  - Function call now checks type signature and type inheritance.
- Grammars:
  - Dart:
    - Single line and multiline line strings with escaped chars.
  - Java8:
    - Single line strings with escaped chars.

## 0.0.3

- Removed `ASTCodeGenerator`, that is language specific now: `ApolloCodeGenerator`.
- Better external function mapping.
- Grammars:
  - Dart:
    - Expression operations: `+`, `-`, `*`, `/`, `~/`.
  - Java8:
    - Expression operations: `+`, `-`, `*`, `/`.
- Improved tests.

## 0.0.2

- Improved execution:
  - Now can call a class method or a function.
- Improved code generation:
  - Now supporting Java8 and Dart.
- Grammars:
  - Dart:
    - Basic class definition.
  - Java8:
    - Basic class definition.

## 0.0.1

- Basic Dart and Java8 support.
- Initial version, created by Stagehand
