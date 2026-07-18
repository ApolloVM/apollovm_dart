# Plan: extend the ApolloVM Wasm backend (Dart → WebAssembly)

> A work plan to close concrete gaps in the on-the-fly Wasm compiler. Every gap
> below was **re-verified end-to-end** (compile → load → execute on the native
> `wasm_run` runtime) against the current tree. Fix one gap, make its test
> green, repeat.
>
> **Status note (re-verified):** the original 9-gap list this file shipped with
> was written against an older build. On re-check, **8 of those 9 now compile
> and execute correctly** (sibling class-method calls, `String + number`,
> `Map → String`, `switch` on `num`/`dynamic`, lambdas, rich-enum methods,
> typed `catch`, C# enum `.value`). Only the **generic type-parameter field**
> gap survives (now GAP A). The gaps below are the ones that reproduce today.

The Wasm backend lives almost entirely in:
- `lib/src/languages/wasm/wasm_generator.dart` — AST → Wasm codegen (most gaps).
- `lib/src/languages/wasm/wasm_parser.dart` — Wasm binary/type parsing.
- `lib/src/languages/wasm/wasm_runner.dart` — load + execute a compiled module.

## How to run / verify

```bash
dart run wasm_run:setup            # one-time: install the native wasm_run lib
dart test -t wasm -x wasm-gc -x wasm-chrome    # all Wasm backend tests, native runtime
dart test test/wasm/apollovm_wasm_maps_test.dart -x wasm-gc   # one file
```

- `wasm-gc` / `wasm-chrome` tags need a browser (WasmGC engine); the native
  `wasm_run` runtime (wasmtime/wasmi) has **no GC**, so exclude those tags when
  iterating locally. None of the gaps below need GC.

## The test harness (`_testWasm`)

Each `test/wasm/apollovm_wasm_*_test.dart` defines a local helper that compiles
`code` to Wasm, loads it, calls `functionName`, and asserts the return value
equals the expected one (works for `int`, `double`, `String`, `bool`). Design
each new test to **return** the value to assert (not `print`). The positional
form in `apollovm_wasm_ops_test.dart` / `apollovm_wasm_loop_increment_test.dart`
is the simplest to copy.

---

## What already works (do NOT "fix" these — keep them green)

- Top-level `int`/`double`/`String`/`bool` functions: arithmetic, `while`/`for`,
  `if`/`else`, ternary, `switch` (on `int`, `num`, `dynamic`, `String`, `enum`),
  `do`/`while`, bitwise, `int` string-interpolation, `String + String`,
  `String + <number>`.
- **`i++`/`++i`/`i--`/`--i` as a statement** inside any loop body — fixed;
  see `apollovm_wasm_loop_increment_test.dart`. (Previously a bare increment
  statement in a `while`/`do-while` body left its value on the operand stack and
  the module failed validation. `for`-header updates were never affected.)
- Function-to-function calls, **including class methods** by bare (unqualified)
  name, named arguments, and default parameter values.
- Classes: constructors, `this.` params, field initializers, external field
  read/write, `double` fields, instance methods via a receiver, `toString()`.
- Static method as the entry point; `static main(List<Object> args)`.
- `enum`: `.index` / `.name`, **methods that read entry fields**, enum-typed
  parameters, C# explicit-value `.value`. `switch` on an enum entry.
- `Map` / `List` construction, index read/write, and `Map → String` coercion.
- `try`/`catch`/`finally` + `throw`, including a **typed** `catch (Exception e)`.
- Local lambdas assigned to a variable and invoked.

The gaps below are the cases *outside* that envelope.

---

## GAP A — generic class with a type-parameter field (`Box<T>`)

- **Error** (compile): `Bad state: Can't unbox an Object without a module.`
- **Trigger**: a generic class with a type-parameter field, e.g.
  `class Box<T> { T value; Box(this.value); }`, instantiated as `Box<int>` and
  read back. Non-generic classes with the same shape already work.
- **Fix direction**: when a type parameter resolves to a concrete primitive
  (`int` → i64), the field load/store must use that representation instead of
  the boxed-Object path. Look at object-field codegen and generic type
  resolution in `wasm_generator.dart`.

```dart
test('generic Box<int> field round-trips', () => _testWasm(
  'class Box<T> { T value; Box(this.value); }'
  ' int run(int x) { var b = Box<int>(x); return b.value; }',
  'run', {[7]: 7}));
```

---

## GAP B — String methods & getters (HIGHEST IMPACT, partially done)

- **Done**: `.length`, `.isEmpty`, `.isNotEmpty` (read the `[len:i32][utf8]`
  header) — see `apollovm_wasm_string_length_test.dart`; `.toUpperCase`,
  `.toLowerCase` (ASCII, fresh buffer + case-bit shift) — see
  `apollovm_wasm_string_case_test.dart`.
- **Still open** (compile error `UnimplementedError: Wasm getter/method .X on
  String is not supported yet.`): `.substring`, `.contains`, `.indexOf`,
  `.trim`, `.split`, `.replaceAll` (and siblings). Also: chaining a getter/method
  onto a method *result* (`s.toUpperCase().length`) — the receiver must be a
  named local today.
- **Trigger**: any String manipulation beyond concatenation/interpolation and
  the length/emptiness getters above. Still the broadest gap.
- **Fix direction**: implement runtime helpers over the String memory layout the
  backend already uses for `__streq`/concatenation (see `_emitStringConcat2` and
  `_generateStringCaseConvert` for the allocate-buffer + byte-loop pattern).
  `.substring` (copy a slice), `.indexOf`/`.contains` (byte scan), `.split`,
  `.replaceAll` build on the same buffer ops. Note the stored length is UTF-8
  bytes, so any method whose Dart semantics are in UTF-16 code units is only
  correct for ASCII until the layout carries a code-unit count.

```dart
test('String.substring', () => _testWasm(
  "String run() { var s = 'hello'; return s.substring(1, 3); }",
  'run', {[]: 'el'}));
```

---

## GAP C — custom instance getters

- **Error** (compile): `UnimplementedError: Wasm getter .x on C is not
  supported yet.`
- **Trigger**: a user-declared getter, `int get x { return _x; }`, read as
  `c.x`. (External/plain field reads already work; this is the *getter method*
  form.)
- **Fix direction**: lower a getter access to a zero-argument method call on the
  receiver, reusing the instance-method-call path.

```dart
test('instance getter', () => _testWasm(
  'class C { int _x = 5; int get x { return _x; } }'
  ' int run() { var c = C(); return c.x; }', 'run', {[]: 5}));
```

---

## GAP D — `static` fields — DONE (bare access)

Static fields now compile to typed, mutable module **globals** (one per field,
placed after the heap pointer and before the enum-entry caches), seeded with
their literal `int`/`double`/`bool` initializer. A bare reference inside a
`static` method reads/writes the global (`global.get`/`global.set`), including
compound assignment; values persist across calls. See
`apollovm_wasm_static_field_test.dart`.

**Remaining (follow-up):** qualified `C.field` from *another* class (goes through
the getter path, not the bare-variable path), inherited static fields (walk the
superclass chain), and non-literal initializers (need a start function). Bare
same-class access — the common case — is covered.

---

## GAP E — inheritance: methods, fields, getters, `static`, `super` (INTERPRETER-SUPPORTED since 2.2.0)

> The AST interpreter fully implements inheritance as of 2.2.0: inherited
> methods (override wins), inherited fields, inherited getters, inherited static
> fields, and `super.method()` / `super.getter` / `super.field`. The Wasm
> backend compiles none of it yet.

- **Errors** (compile): `Can't call non-static method 'A.base' without an
  instance.` (inherited method); `Can't find local variable \`x\`` (inherited
  field); `Can't find local variable \`super\`` (`super.*`).
- **Trigger**: any access to a member declared on a superclass, or `super`.
- **Fix direction**: resolve the superclass chain when laying out object fields
  and the method/function index table (vtable), so inherited members are
  reachable on a subclass instance; model `super` as the current instance with
  dispatch starting at the enclosing class's superclass.

```dart
test('inherited superclass method', () => _testWasm(
  'class A { int base() { return 1; } }'
  ' class B extends A { int run() { return base() + 2; } }', 'B.run', {[]: 3}));
```

---

## GAP G — nested lists & nested indexing (`m[0][1]`) (INTERPRETER-SUPPORTED since 2.2.0)

- **Error** (compile): `UnimplementedError: Wasm list literal of element type
  List<int> is not supported yet.` — the blocker is the **2D list literal**
  (`[[1, 2], [3, 4]]`), not the index chain itself.
- **Trigger**: a list whose element type is a `List`/`Map` (a nested collection),
  and, once buildable, chained access/assignment `m[0][1]` / `m['a']['b'] = v`.
- **Fix direction**: support a nested-collection element type in list/map literal
  codegen (element is a pointer to another list/map header), then confirm the
  chained index/key read+write path compiles.

```dart
test('nested list read', () => _testWasm(
  'int run() { var m = [[1, 2], [3, 4]]; return m[0][1]; }', 'run', {[]: 2}));
```

---

## GAP F — returning a `List`/`Map` across the module boundary

- **Error** (execute): `Bad state: Unsupported Wasm Object box tag: 0.`
- **Trigger**: a function whose return type is a collection, `List run() =>
  [1, 2, 3];`. Building and using collections *inside* a function works; handing
  one back across the call boundary does not.
- **Fix direction**: box the collection handle with a tag the host unwrapper
  understands (mirror how scalar returns are boxed), so `executeFunction` can
  read a `List`/`Map` result back.

```dart
test('return a List', () => _testWasm(
  'List run() { return [1, 2, 3]; }', 'run', {[]: [1, 2, 3]}));
```

---

## Suggested order

GAPs D, E and G below are **already implemented in the AST interpreter** (2.1.1 /
2.2.0), so closing them brings the Wasm backend to parity with what source
already runs — good candidates to prioritize.

1. **GAP B** (remaining String methods) — by far the widest impact on real code
   (`.length`/`.isEmpty`/`.isNotEmpty` already done).
2. **GAP D** (static fields) and **GAP C** (getters) — small, common,
   independent; D is interpreter-supported.
3. **GAP E** (inheritance/`super`) — one subsystem (field layout + method/vtable
   resolution over the superclass chain); interpreter-supported.
4. **GAP G** (nested collections / `m[0][1]`) — list/map literal codegen for a
   nested element type; interpreter-supported.
5. **GAP A** (generic field i64/boxing) and **GAP F** (aggregate returns) —
   value-representation work; related boxing concerns.

After each fix: `dart test -t wasm -x wasm-gc -x wasm-chrome` must stay green
(all existing tests + the new one for that gap). Note that some Wasm tests
assert **exact** emitted bytecode via `expecteWasm`; a codegen change that alters
the bytes for those cases requires updating their expected hex (the executions
must still pass).

### Source of these findings

Re-verified by compiling representative snippets per gap through the full Wasm
pipeline (`generateAllIn<BytesOutput>('wasm')` → `BinaryCodeUnit` → execute) on
the native `wasm_run` runtime.
