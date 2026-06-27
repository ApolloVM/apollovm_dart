# Plan: extend the ApolloVM Wasm backend (Dart → WebAssembly)

> For another Claude. This is a work plan to close concrete gaps in the
> on-the-fly Wasm compiler. Every gap below was reproduced against **0.1.42**
> with the native `wasm_run` runtime and includes a **ready-to-paste test** in
> the repo's existing harness style. Fix one gap, make its test green, repeat.

The Wasm backend lives almost entirely in:
- `lib/src/languages/wasm/wasm_generator.dart` — AST → Wasm codegen (most gaps).
- `lib/src/languages/wasm/wasm_parser.dart` — Wasm binary/type parsing.
- `lib/src/languages/wasm/wasm_runner.dart` — load + execute a compiled module.

## How to run / verify

```bash
dart run wasm_run:setup            # one-time: install the native wasm_run lib
dart test -t wasm -x wasm-gc -x wasm-chrome    # all Wasm backend tests, native runtime
dart test test/wasm/apollovm_wasm_named_parameters_test.dart -x wasm-gc   # one file
```

- `wasm-gc` / `wasm-chrome` tags need a browser (WasmGC engine); the native
  `wasm_run` runtime (wasmtime/wasmi) has **no GC**, so exclude those tags when
  iterating locally. None of the gaps below need GC — they reproduce on the
  native runtime.
- All **59** existing Wasm tests pass today; don't regress them.

## The test harness (`_testWasm`)

Each `test/wasm/apollovm_wasm_*_test.dart` defines a local helper:

```dart
Future<void> _testWasm({
  required String language,            // 'dart' | 'kotlin' | 'java11' | ...
  required String code,
  required String functionName,        // export to call: 'run' or 'Foo.run'
  required Map<List, Object?> executions,   // { argsList : expectedReturn }
  Map<String, dynamic>? expecteWasm,
}) async { ... }
```

It compiles `code` to Wasm, loads it, calls `functionName`, and asserts the
return value equals the expected one (works for `int`, `double`, `String`,
`bool`). Design each new test to **return** the value to assert (not `print`).

---

## What already works (do NOT "fix" these — keep them green)

- Top-level `int`/`double`/`String`/`bool` functions: arithmetic, `while`/`for`,
  `if`/`else`, ternary, `switch` on **`int`**, `do`/`while`, bitwise, `int`
  string-interpolation (`'$n'`), `String + String`.
- **Top-level** function-to-function calls, including **named arguments** and
  **default parameter values** (see `apollovm_wasm_named_parameters_test.dart`,
  `apollovm_wasm_default_parameters_test.dart`).
- Classes driven from a top-level entry: constructors, `this.` params, field
  initializers, **external field read/write**, **`double` fields**, instance
  methods called **via a receiver** (`p.sum()`), `toString()`.
- Static method as the **entry point**; `static main(List<Object> args)`.
- Simple `enum`: entry `.index` / `.name`.
- Dart untyped `try`/`catch`/`finally` + `throw`.

The gaps below are the cases *outside* that envelope.

---

## GAP 1 — unqualified calls to sibling class methods (HIGHEST IMPACT)

**This single gap also causes named-args and default-params to fail when the
callee is a class method** (they already work at top level). Fixing it unblocks
three playground examples at once.

- **Error** (`wasm_generator.dart:2123`):
  `Bad state: Can't resolve local function \`dbl\` with 1 argument(s) in the Wasm function index table.`
- **Trigger**: a method calls a *sibling* method of the same class by bare name
  (no receiver): `dbl(x)` instead of `this.dbl(x)` / `Foo.dbl(x)`. Top-level
  function-to-function calls resolve fine; the function index table just doesn't
  register/resolve class methods for unqualified call sites.
- **Root cause to investigate**: how the function index table is populated
  around `wasm_generator.dart:2123`. Top-level functions are registered by name;
  class methods (static and instance) need to be resolvable for an unqualified
  sibling call, with the named/default-argument normalization applied the same
  way it already is for top-level calls.

**Test — add to `test/wasm/apollovm_wasm_static_method_test.dart`:**

```dart
test('unqualified sibling static call resolves', () => _testWasm(
  language: 'dart',
  code: r'''
    class Foo {
      static int dbl(int n) { return n * 2; }
      static int run(int x) { return dbl(x); }   // bare-name sibling call
    }
  ''',
  functionName: 'Foo.run',
  executions: {[5]: 10},
));
```

**Test — add to `test/wasm/apollovm_wasm_named_parameters_test.dart`** (named
args on a class method):

```dart
test('named args on a static class method', () => _testWasm(
  language: 'dart',
  code: r'''
    class Foo {
      static int area(int w, int h) { return w * h; }
      static int run() { return area(h: 3, w: 4); }
    }
  ''',
  functionName: 'Foo.run',
  executions: {[]: 12},
));
```

**Test — add to `test/wasm/apollovm_wasm_default_parameters_test.dart`**
(omitted default on a class method):

```dart
test('default param omitted on a class method', () => _testWasm(
  language: 'dart',
  code: r'''
    class Foo {
      static int area(int w, [int h = 3]) { return w * h; }
      static int run() { return area(5); }   // h defaults to 3
    }
  ''',
  functionName: 'Foo.run',
  executions: {[]: 15},
));
```

---

## GAP 2 — `String + <number>` concatenation (number → string)

- **Error** (`wasm_generator.dart:3097`):
  `UnimplementedError: Wasm string \`+\` with a non-String operand (number-to-string) is not supported yet (String + int).`
  (also `String + double`, `String + num`, `String + dynamic`, `String + int(64)`)
- **Trigger**: the `+` operator with a `String` LHS and a numeric RHS. Dart
  forbids this syntactically, so it arrives from **Java/Kotlin/C#/JS/TS** sources
  (e.g. `"n = " + n`). Note `int` interpolation (`'$n'`) and `String + String`
  already work — the missing piece is an `int`/`double` → `String` conversion in
  the `+` codegen path.
- **Fix direction**: reuse whatever number→string conversion the interpolation
  path already uses, in the binary-`+` string branch at `wasm_generator.dart:3097`.

**Test — new file `test/wasm/apollovm_wasm_string_concat_test.dart`** (mirror the
`_testWasm` helper from a sibling file):

```dart
test('String + int (Kotlin)', () => _testWasm(
  language: 'kotlin',
  code: r'''
    fun run(n: Int): String {
      return "n=" + n
    }
  ''',
  functionName: 'run',
  executions: {[5]: 'n=5'},
));

test('String + double (Kotlin)', () => _testWasm(
  language: 'kotlin',
  code: r'''
    fun run(): String {
      return "g=" + 9.8
    }
  ''',
  functionName: 'run',
  executions: {[]: 'g=9.8'},
));
```

---

## GAP 3 — `Map` (collection) → String coercion

- **Error** (`wasm_generator.dart:8517`):
  `UnimplementedError: Wasm string coercion of type Map<String,int> is not supported yet.`
- **Trigger**: interpolating/coercing a whole `Map` (or `List`) to a `String`.
- **Fix direction**: implement a runtime string-coercion for collection values
  at `wasm_generator.dart:8517` (emit `{k: v, ...}` like Dart's `Map.toString`).

**Test — add to `test/wasm/apollovm_wasm_maps_test.dart`:**

```dart
test('Map interpolated into a String', () => _testWasm(
  language: 'dart',
  code: r'''
    String run() {
      var m = <String, int>{'a': 1, 'b': 2};
      return 'Map: $m';
    }
  ''',
  functionName: 'run',
  executions: {[]: 'Map: {a: 1, b: 2}'},
));
```

---

## GAP 4 — generic class `Box<T>` produces invalid Wasm

- **Error** (at execution, after compile): the module fails validation —
  `FrbAnyhowException(WebAssembly translation error … type mismatch: expected i64, found i32)`.
- **Trigger**: a generic class with a type-parameter field, e.g. `Box<T>{ T value; }`,
  instantiated as `Box<int>` and read back. Non-generic classes with the same
  shape already work (`apollovm_wasm_object_field_test.dart`), so this is specific
  to type-parameter fields: the field's storage/width is emitted as `i32` where
  the `int` value needs `i64` (an int-width mismatch in object-field codegen).
- **Fix direction**: when a type parameter resolves to `int`, the field
  load/store must use the i64 representation. Look at object-field codegen and
  generic type resolution in `wasm_generator.dart`.

**Test — add to `test/wasm/apollovm_wasm_object_field_test.dart`:**

```dart
test('generic Box<int> field round-trips', () => _testWasm(
  language: 'dart',
  code: r'''
    class Box<T> {
      T value;
      Box(this.value);
    }
    int run(int x) {
      var b = Box<int>(x);
      return b.value;
    }
  ''',
  functionName: 'run',
  executions: {[7]: 7},
));
```

---

## GAP 5 — `switch` on a non-`int` scrutinee

- **Error** (`wasm_generator.dart:7424`):
  `UnimplementedError: Wasm switch on dynamic is not supported (int only).`
  (also `Wasm switch on num is not supported (int only)`)
- **Trigger**: `switch` where the scrutinee is `dynamic` (untyped JS/Python) or
  `num` (TS). `switch` on a statically-`int` value works.
- **Fix direction**: coerce/narrow the scrutinee to `int` (or `i64`) before the
  branch table at `wasm_generator.dart:7424`, or support a fallback compare chain.

**Test — add to `test/wasm/apollovm_wasm_ops_test.dart`:**

```dart
test('switch on a num scrutinee (TypeScript)', () => _testWasm(
  language: 'typescript',
  code: r'''
    function run(n: number): number {
      switch (n) {
        case 1: return 10;
        case 2: return 20;
        default: return 99;
      }
    }
  ''',
  functionName: 'run',
  executions: {[1]: 10, [2]: 20, [5]: 99},
));
```

---

## GAP 6 — anonymous functions / lambdas

- **Error** (`wasm_generator.dart:841`):
  `Unsupported operation: Wasm: can't infer the return type of an anonymous function …`
  and, for JS/TS, `UnimplementedError: generateASTStatementFunctionDeclaration`.
- **Trigger**: assigning a lambda to a local and invoking it.
- **Fix direction**: infer the closure's return type from its body / the
  expected type at the use site; implement nested function-declaration codegen
  for JS/TS.

**Test — new file `test/wasm/apollovm_wasm_lambda_test.dart`:**

```dart
test('local lambda invoked', () => _testWasm(
  language: 'dart',
  code: r'''
    int run(int x) {
      var twice = (int n) => n * 2;
      return twice(x);
    }
  ''',
  functionName: 'run',
  executions: {[5]: 10},
));
```

---

## GAP 7 — rich-enum methods & enum-typed parameters

Simple enums (`.index`/`.name`) already compile and run. The gaps appear with
**enhanced enums that declare methods** and with **enum-typed parameters**.

- **Error**: `Bad state: Can't handle type: Planet` (`wasm_parser.dart:176` /
  `wasm_generator.dart:10081`) when an enum type is used as a parameter type;
  enum entries with method bodies also need codegen.
- **Trigger** (the playground's `Dart — Rich enum (fields & methods)`):

```dart
enum Planet {
  earth(9.8),
  mars(3.7);

  final double gravity;

  const Planet(this.gravity);

  double mult(double m) => gravity * m;

  double ratio(Planet p) => gravity / p.gravity;   // enum-typed param `p`
}
```

**Test — add to `test/wasm/apollovm_wasm_enum_test.dart`:**

```dart
test('enum method using a field', () => _testWasm(
  language: 'dart',
  code: r'''
    enum Planet {
      earth(9.8), mars(3.7);
      final double gravity;
      const Planet(this.gravity);
      double mult(double m) { return gravity * m; }
    }
    double run() {
      var e = Planet.earth;
      return e.mult(2.0);   // expect 19.6
    }
  ''',
  functionName: 'run',
  executions: {[]: 19.6},
));

test('enum method taking an enum-typed parameter', () => _testWasm(
  language: 'dart',
  code: r'''
    enum Planet {
      earth(9.8), mars(3.7);
      final double gravity;
      const Planet(this.gravity);
      double ratio(Planet p) { return gravity / p.gravity; }
    }
    double run() {
      var e = Planet.earth;
      var m = Planet.mars;
      return e.ratio(m);    // 9.8 / 3.7
    }
  ''',
  functionName: 'run',
  executions: {[]: 9.8 / 3.7},
));
```

---

## GAP 8 — typed exception catch (`catch (Exception e)`)

- **Error**: `Bad state: Can't handle type: Exception`.
- **Trigger**: a `catch` clause with a declared exception **type** (Java/Kotlin/C#).
  Dart's untyped `catch (e)` + `try`/`finally` already work
  (`apollovm_wasm_exception_test.dart`).
- **Fix direction**: treat a typed catch like the untyped one (the Wasm model
  has a single thrown value); ignore/normalize the declared type.

**Test — add to `test/wasm/apollovm_wasm_exception_test.dart`:**

```dart
test('typed catch (Java)', () => _testWasm(
  language: 'java11',
  code: r'''
    class Foo {
      static int run(int b) {
        try {
          if (b == 0) { throw "zero"; }
          return b;
        } catch (Exception e) {
          return -1;
        }
      }
    }
  ''',
  functionName: 'Foo.run',
  executions: {[0]: -1, [5]: 5},
));
```

---

## GAP 9 — C# enum `.value` getter

- **Error** (`wasm_generator.dart:4449`):
  `UnimplementedError: Wasm getter \`.value\` on Level is not supported yet.`
- **Trigger**: reading an explicit-value (C#) enum entry's `.value`.

**Test — add to `test/wasm/apollovm_wasm_enum_test.dart`:**

```dart
test('C# enum .value', () => _testWasm(
  language: 'csharp',
  code: r'''
    enum Level { Low = 1, Medium = 5, High = 10 }
    class Foo {
      public static int run() {
        var m = Level.Medium;
        return m.value;
      }
    }
  ''',
  functionName: 'Foo.run',
  executions: {[]: 5},
));
```

---

## Suggested order

1. **GAP 1** (class-method call resolution) — one subsystem, unblocks named
   args + defaults + sibling/async calls on class methods.
2. **GAP 2** (`String + number`) — unblocks most non-Dart examples broadly.
3. **GAP 4** (generic field i64/i32) — object-field codegen correctness.
4. **GAP 3** (Map coercion), **GAP 5** (non-int switch), **GAP 6** (lambdas),
   **GAP 7** (rich-enum methods / enum params), **GAP 8** (typed catch),
   **GAP 9** (C# `.value`) — independent, feature-by-feature.

After each fix: `dart test -t wasm -x wasm-gc -x wasm-chrome` must stay green
(all existing tests + the new one for that gap).

### Source of these findings

Reproduced by compiling the ApolloVM web playground examples
(`apollovm_web_example`) through the full Wasm pipeline; the playground itself is
a good end-to-end smoke test once these land.
