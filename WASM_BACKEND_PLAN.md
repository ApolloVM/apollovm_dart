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

## GAP B — String methods & getters (HIGHEST IMPACT, mostly done)

- **Done (getters)**: `.length`, `.isEmpty`, `.isNotEmpty` (read the
  `[len:i32][utf8]` header) — `apollovm_wasm_string_length_test.dart`.
- **Done (transforms)**: `.toUpperCase`, `.toLowerCase` (ASCII case-bit shift) —
  `apollovm_wasm_string_case_test.dart`.
- **Done (slice/search)**: `.substring(start,[end])` (fresh-buffer `memory.copy`
  slice), `.codeUnitAt(i)`, `.startsWith`/`.endsWith`, `.indexOf`, `.contains`
  (byte scans over the layout, OOB-guarded) — `apollovm_wasm_string_methods_test`
  and `_tryGenerateStringMethod`.
- **Done (trim/pad)**: `.trim`/`.trimLeft`/`.trimRight` (ASCII-whitespace strip)
  and `.padLeft`/`.padRight(width,[pad])` (single-byte pad) —
  `apollovm_wasm_string_methods2_test`.
- **Done (replace)**: `.replaceAll(from,to)` / `.replaceFirst(from,to)` — two
  passes (count matches to size the output buffer, then build it); handles
  grow/shrink/removal and matches at the ends; an empty `from` returns a copy —
  `apollovm_wasm_string_replace_test`.
- **Done (compareTo)**: `.compareTo(other)` — lexicographic byte compare
  returning `-1`/`0`/`1`. Also added `String.compareTo` to the interpreter core
  (`apollovm_core_base.dart`), which lacked it — `apollovm_wasm_string_compareto_test`.
- **Still open**: `.split` (returns a `List`) and index `[]`. Also: chaining a
  getter/method onto a method *result* (`s.toUpperCase().length`,
  `s.substring(0,2) == 'x'`) — the receiver must be a named local, and a bare
  `String == String` returning a `bool` is a separate pre-existing limitation.
- **Fix direction**: same allocate-buffer + byte-loop pattern
  (`_generateStringCaseConvert`, `_emitBytesEqualNoBreak`). `.split`/`.replaceAll`
  build a fresh buffer/`List` from scan results. Stored length is UTF-8 bytes, so
  byte-indexed methods are exact for ASCII; UTF-16-code-unit semantics need the
  layout to carry a code-unit count.

```dart
test('String.substring', () => _testWasm(
  "String run() { var s = 'hello'; return s.substring(1, 3); }",
  'run', {[]: 'el'}));
```

---

## GAP C — custom instance getters — DONE

A user-declared getter (`int get x { ... }`) is synthesized as a zero-argument
instance method (see `_buildClassFunctions`), so a getter access via a receiver
(`c.x`) lowers to a 0-arg method call on the receiver — reusing the whole
instance-method path (argument marshalling, return conversion) and the
superclass-chain resolution, so **inherited getters** and **overrides** resolve
just like methods. `hasGetter` distinguishes a getter from a same-named 0-arg
method (both compile to the same shape). Covers `int`/`double`/`bool`/`String`
getters, a computed-expression getter body, a getter used inside an expression
(read once or twice), inherited, and overridden getters. See
`apollovm_wasm_getter_test.dart`.

**Remaining (follow-up):** **bare** getter access inside a method body (`x`
resolving to `this.x`, no receiver) is not wired — the AST interpreter does not
resolve it yet either, so closing it means fixing both together, and it is left
as a shared follow-up. Setters (`set x(v)`) are likewise unimplemented.

```dart
test('instance getter', () => _testWasm(
  'class C { int _x = 5; int get x { return _x; } }'
  ' class M { static int go() { var c = C(); return c.x; } }',
  'M.go', {[]: 5}));
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

## GAP E — inheritance: methods, fields, `super` — DONE

A subclass instance now carries its superclass's fields **first** in the heap
layout ([`_allInstanceFields`], superclass-first), so an inherited field sits at
the same offset on a subclass instance as on the superclass — a superclass method
compiled once against the superclass layout reads/writes the correct slot when
invoked on a subclass instance. Method resolution (`methodIndex` /
`methodIndexForCall`) walks the `extends` chain: the most-derived class that
declares the method wins (an override), otherwise the inherited superclass method.
`super.m(args)` keeps the current instance as the receiver but starts dispatch at
the enclosing class's superclass (skipping the override). The subclass constructor
also runs inherited field initializers (superclass-first). See
`apollovm_wasm_inheritance_test.dart`. Covered: inherited method (bare and via a
receiver, with args), inherited field read/write (incl. `double`), own+inherited
fields at distinct offsets, override-wins, `super.m()` / `super.m(args)`, and a
two-level `extends` chain.

**Remaining (follow-up):** dispatch is *static* (by the receiver's declared type),
not virtual — an upcast receiver (`A a = B();`) calls the declared type's method,
not the runtime type's; a true vtable would be needed for polymorphic dispatch.
`super.field` / `super.getter` and inherited user-getters are not wired (GAP C is
still open for getters generally). Static members are intentionally **not**
inherited (matching Dart). The `: super(...)` constructor-initializer syntax is a
separate **parser** gap (the Dart grammar doesn't parse it yet).

```dart
test('inherited superclass method', () => _testWasm(
  'class A { int base() { return 9; } }'
  ' class B extends A { int run() { return base(); } }'
  ' class M { static int go() { var b = B(); return b.run(); } }',
  'M.go', {[]: 9}));
```

---

## GAP G — nested lists & nested indexing (`m[0][1]`) — DONE

A nested collection is stored as an i32 pointer to the inner header, so a
`List`/`Map` literal can now hold `List`/`Map` elements (`_isSupportedElemType`
accepts `ASTTypeArray`/`ASTTypeMap`; `_emitElemStore`/`_emitElemLoad` already
handled the i32-pointer slot). Nested literals use **depth-offset scratch locals**
(`collectionLiteralDepth` on the context, distinct slot bands per level) so an
inner literal never aliases the enclosing literal's header/buffer locals — depth 0
keeps the original slots, so single-level collections stay byte-identical.

Chained subscripts read and write through every level: `_emitApplyIndexOnStack`
applies one index to a container pointer already on the stack (list or map),
looping over `expression.expression + extraIndices` for reads and navigating
all-but-last for `m[0][1] = v` writes (`_generateChainedEntryAssignment`,
including the `+=` compound form). Covers 2D/3D lists, nested maps, list-of-map,
map-of-list, mixed navigation, and writes (incl. through a map into a nested
list). See `apollovm_wasm_nested_collection_test.dart`.

**Remaining (follow-up):** writing into an *innermost `Map`* (`list[0]['k'] = v`)
— reads of that shape work, but the write path only stores into an innermost
`List`. Also `getList()[0]` / `m[1].length` (a subscript/method on a non-variable
receiver) is a separate parser/receiver gap.

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

GAPs **C** (getters), **D** (static fields), **E** (inheritance/`super`) and **G**
(nested collections / `m[0][1]`) are **DONE**; **GAP B** (String methods) is mostly
done (slice/search/case complete). Remaining:

1. **GAP B tail** — `.split` (returns a `List`) and index `[]`. (`.trim`/`.pad`/
   `.replaceAll`/`.replaceFirst`/`.compareTo` done.)
2. **GAP A** (generic field i64/boxing) and **GAP F** (aggregate returns) —
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
