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
  header) — see `apollovm_wasm_string_length_test.dart`.
- **Still open** (compile error `UnimplementedError: Wasm getter/method .X on
  String is not supported yet.`): `.toUpperCase`, `.toLowerCase`, `.substring`,
  `.contains`, `.indexOf`, `.trim`, `.split`, `.replaceAll` (and siblings).
- **Trigger**: any String manipulation beyond concatenation/interpolation and
  the length/emptiness getters above. Still the broadest gap.
- **Fix direction**: implement runtime helpers over the String memory layout the
  backend already uses for `__streq`/concatenation. Case conversion is the
  cheapest next step (allocate a same-length buffer, map each ASCII byte);
  `.substring`, `.indexOf`, `.contains`, `.split`, `.replaceAll` build on the
  same buffer ops. Note the stored length is UTF-8 bytes, so any method whose
  Dart semantics are in UTF-16 code units is only correct for ASCII until the
  layout carries a code-unit count.

```dart
test('String.toUpperCase', () => _testWasm(
  "String run() { var s = 'hi'; return s.toUpperCase(); }", 'run', {[]: 'HI'}));
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

## GAP D — reading a `static` field

- **Error** (compile): `Bad state: Can't find local variable \`count\` in
  context.`
- **Trigger**: reading a `static` field from a static method (`return count;` or
  `C.count`). Static *methods* work; static *fields* don't resolve.
- **Fix direction**: give static fields module-level storage (a global or a
  fixed memory slot) and resolve a bare/`Class.`-qualified static-field name to
  a load from it.

```dart
test('static field read', () => _testWasm(
  'class C { static int count = 7; static int run() { return count; } }',
  'C.run', {[]: 7}));
```

---

## GAP E — inherited / `super` method calls

- **Error** (compile): `Unsupported operation: Can't call non-static method
  'A.base' without an instance.`
- **Trigger**: a subclass calling a concrete method it inherits from its
  superclass (`class B extends A { int run() { return base() + 2; } }`), and
  `super.method()` / `super(...)`. A class calling *its own* methods works.
- **Fix direction**: walk the superclass chain when resolving an unqualified
  method call and when laying out the vtable / function index table, so an
  inherited method is callable on a subclass instance.

```dart
test('inherited superclass method', () => _testWasm(
  'class A { int base() { return 1; } }'
  ' class B extends A { int run() { return base() + 2; } }'
  ' int run() { var b = B(); return b.run(); }', 'run', {[]: 3}));
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

1. **GAP B** (remaining String methods) — by far the widest impact on real code
   (`.length`/`.isEmpty`/`.isNotEmpty` already done).
2. **GAP D** (static field reads) and **GAP C** (getters) — small, common,
   independent.
3. **GAP E** (inheritance/`super`) — one subsystem (method resolution + vtable).
4. **GAP A** (generic field i64/boxing) and **GAP F** (aggregate returns) —
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
