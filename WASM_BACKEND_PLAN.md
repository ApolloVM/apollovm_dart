# Plan: extend the ApolloVM Wasm backend (Dart → WebAssembly)

> A work plan to close concrete gaps in the on-the-fly Wasm compiler. Every gap
> below was **re-verified end-to-end** (compile → load → execute on the native
> `wasm_run` runtime) against the current tree. Fix one gap, make its test
> green, repeat.
>
> **Status note:** all lettered gaps below (A–G) are now **DONE** — closed and
> covered by tests in `test/wasm/`. The sections are retained as design notes and
> a record of the fixes. What remains are narrower limitations (chaining onto a
> non-local method/index result, virtual dispatch through an upcast receiver,
> `super.field`/`super.getter`, the `: super(...)` parser gap) — see the end of
> the "Suggested order" section.

The Wasm backend lives almost entirely in:
- `lib/src/languages/wasm/wasm_generator.dart` — AST → Wasm codegen (most gaps).
- `lib/src/languages/wasm/wasm_parser.dart` — Wasm binary/type parsing.
- `lib/src/languages/wasm/wasm_runner.dart` — load + execute a compiled module.

## How to run / verify

```bash
# The native `wasm_run` lib needs no install step: its build hook downloads it
# into `.dart_tool/lib/` when `dart test`/`dart run` executes.
dart test -t wasm -x wasm-gc -x wasm-chrome    # all Wasm backend tests, native runtime
dart test test/wasm/apollovm_wasm_maps_test.dart -x wasm-gc   # one file
```

- On **macOS arm64** the `wasm_run` 0.2 prebuilt library is SIGKILLed (*Code Signature
  Invalid*) as soon as wasmtime runs JIT-compiled Wasm under the JIT VM. Use
  `--compiler exe` there: `dart test --compiler exe -t wasm -x wasm-gc -x wasm-chrome`.

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

## GAP A — generic class with a type-parameter field (`Box<T>`) — DONE

A generic field (`T value`) is stored **boxed**: the constructor boxes the
argument (a value flowing into an `Object`-represented `T` param goes through
`_emitBoxValue`), and reading it back at the instantiation type unboxes to the
concrete representation. Two fixes closed this:
1. `generateASTStatementReturnWithExpression` now threads the `context` into
   `_autoConvertStackTypes` (it previously passed none, hitting a module-less path
   that threw "Can't unbox an Object without a module").
2. `_autoConvertStackTypes` gained an `Object → String`/`bool`/instance unbox
   case (extract the i32 box payload), alongside the existing `Object → num` one.

Covers `Box<int|double|String|bool>`, generic fields in arithmetic, and
multi-parameter classes (`Pair<int, String>`). See
`apollovm_wasm_generic_field_test`. **Follow-up:** a generic *instance* field
(`Box<SomeClass>`) reads back as `dynamic`, so further member access on it
(`b.value.field`) isn't wired yet — needs the read site to resolve `T` to the
concrete instance type from the receiver's type argument.

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
- **Done (split)**: `.split(sep)` -> `List<String>` — two passes (count
  separators to size the list, then allocate each piece as a fresh String);
  handles multi-char separators and leading/trailing empty pieces. An empty `sep`
  yields a single whole-string piece (Dart's char-split for `''` is a follow-up)
  — `apollovm_wasm_string_split_test`.
- **Done (index)**: `s[i]` -> a length-1 String (the byte at `s + 4 + i`). Also
  added `String[]` (`readIndex`) to the interpreter, which lacked it —
  `apollovm_wasm_string_index_test`.
- **Done (equality)**: `String == String` / `String != String` now compile to
  content equality via the `__streq` synth helper (not pointer identity),
  yielding a `bool` that can be returned, used as an `if`/`&&` condition, etc.
  Covers literal/variable operands and the empty string —
  `apollovm_wasm_string_equality_test`.
- **Still open**: chaining a getter/method onto a method/index *result*
  (`s.toUpperCase().length`, `s.split(',')[0].length`, `s.substring(0,2) == 'x'`)
  — the receiver must be a named local.
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

## GAP F — returning a `List`/`Map` across the module boundary — DONE

The runner decodes a returned collection handle back into a Dart value: the
return path (`wasm_runner.dart`) reads the function's return type and calls
`decodeList` / `decodeMap` on the i32 header pointer (via the AST return type, or
the `apollovm_sig` custom section for raw-bytes modules). Covers `List<int>` /
`List<double>` / `List<String>` (literal, arrow, and built-with-`.add`) and
`Map<String,int>`. Guarded by `apollovm_wasm_aggregate_return_test`.

```dart
test('return a List', () => _testWasm(
  'List<int> run() { return [1, 2, 3]; }', 'run', {[]: [1, 2, 3]}));
```

---

## Suggested order

All lettered gaps are now **DONE**: **B** (String methods), **C** (getters),
**D** (static fields), **E** (inheritance/`super`), **F** (aggregate returns),
**G** (nested collections / `m[0][1]`), and **A** (generic-field boxing).

Remaining known limitations (not full gaps): chaining a getter/method onto a
non-local *result* (`s.toUpperCase().length`, `s.split(',')[0].length`); virtual
dispatch through an upcast receiver; `super.field`/`super.getter`; and the
`: super(...)` constructor-initializer **parser** gap. (`String == String`
returning a `bool` is now supported via the `__streq` helper.)

After each fix: `dart test -t wasm -x wasm-gc -x wasm-chrome` must stay green
(all existing tests + the new one for that gap). Note that some Wasm tests
assert **exact** emitted bytecode via `expecteWasm`; a codegen change that alters
the bytes for those cases requires updating their expected hex (the executions
must still pass).

### Source of these findings

Re-verified by compiling representative snippets per gap through the full Wasm
pipeline (`generateAllIn<BytesOutput>('wasm')` → `BinaryCodeUnit` → execute) on
the native `wasm_run` runtime.
