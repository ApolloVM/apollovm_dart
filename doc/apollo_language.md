# The Apollo Language

Apollo is a statically-typed, Dart-derived language built into ApolloVM. It can
be **parsed**, **executed** (tree-walking interpreter), **translated** to and
from every other language ApolloVM supports (Dart, Java, Kotlin, Go, C#,
JavaScript, TypeScript, Lua, Python), and **regenerated** back to Apollo source.
Apollo source files use the `.apollo` extension and the language id `apollo`.

## Purpose & objectives

Apollo exists to be a **familiar, low-ceremony language that is comfortable for
both humans and coding agents**. It keeps Dart's semantics and tooling
(interpreter, cross-language translation, Wasm backend) but trims the syntactic
noise that gets in the way when reading or generating code:

- **Minimal punctuation, maximum readability.** Optional parentheses around
  control-flow conditions and optional statement semicolons remove characters
  that carry no meaning.
- **Static typing with inference by default.** Types are checked, but return
  types can be inferred and `var` infers locals — you write types where they add
  clarity, not everywhere.
- **A single obvious place for modifiers.** `async` is always a leading
  declaration modifier, so a function's shape is clear from its first token.
- **Dart-compatible strings.** Anyone who knows Dart (or an agent trained on it)
  already knows Apollo strings — interpolation, multiline, raw, and adjacent
  concatenation all behave identically.
- **Interoperable by construction.** Because Apollo shares ApolloVM's AST, any
  Apollo program can be translated to any other supported language and back.

Design influences: Dart, Kotlin, Swift, TypeScript, Java and C#.

## Relationship to Dart

Apollo *is* Dart, with five deliberate divergences:

| Aspect | Dart | Apollo |
|---|---|---|
| Control-flow parentheses | required | **optional** |
| `async` position | trailing: `f() async {}` | **leading**: `async f() {}` |
| Statement semicolons | required | **optional** |
| Primitive type names | `int`, `double`, `bool` | **`Int`, `Double`, `Bool`, `Num`, `Void`** |
| Typed catch | `on T catch (e)` | **`catch T e`** (parentheses optional) |

Everything else — classes, constructors, mixins-style composition, enums,
generics erasure, closures, list/map literals, operators, imports — follows
Dart.

Translating between the two is automatic:

```apollo
async User loadUser(Int id) {
  return await fetch(id)
}
```

becomes, in Dart:

```dart
Future<User> loadUser(int id) async {
  return await fetch(id);
}
```

and Dart translated to Apollo reverses the transformation (leading `async`,
capitalized types).

---

## Strings

Apollo strings use the exact same syntax as Dart.

### Single & double quotes

```apollo
var a = 'John'
var b = "John"
```

### Interpolation

```apollo
var text  = "Hello $name"
var text2 = "Hello ${user.name}"
```

### Multiline

```apollo
var text = '''
Line 1
Line 2
Line 3
'''
```

### Raw strings

```apollo
var path = r'C:\temp\file.txt'
```

### Adjacent strings

Adjacent string literals are concatenated at parse time:

```apollo
var text =
    "Hello "
    "World"     // => "Hello World"
```

---

## Control flow

Parentheses around the condition are optional throughout.

### If / else if / else

```apollo
if score >= 90 {
  print("A")
} else if score >= 80 {
  print("B")
} else {
  print("C")
}
```

The parenthesized form is equally valid:

```apollo
if (score >= 90) {
  print("A")
}
```

### While & do/while

```apollo
while connected {
  process()
}

do {
  retry()
} while shouldRetry
```

### Switch

```apollo
switch role {
  case Role.admin:
    print("Admin")
    break
  case Role.user:
    print("User")
    break
  default:
    print("Guest")
}
```

### For

Apollo has three `for` forms: the concise **range-based** counting loop, the
**classic C-style** loop, and **for-in** iteration.

#### Range-based `for`

The range form is the concise, readable way to write a counting loop. The step
(`++`/`+=` ascending, `--`/`-=` descending) drives the direction, and the range
operator selects the bound:

```apollo
for i++ from 0..limit   { ... }   // ascending, inclusive     (i <= limit)
for i-- from limit..0   { ... }   // descending, inclusive    (i >= 0)
for i++ from 0..<limit  { ... }   // ascending, exclusive up  (i <  limit)
for i-- from limit..>0  { ... }   // descending, exclusive lo (i >  0)
for i += 2 from 0..limit { ... }  // custom step, ascending   (i += 2)
for i -= 2 from limit..0 { ... }  // custom step, descending  (i -= 2)
```

Each range loop is exactly equivalent to the classic form — e.g.
`for i++ from 0..limit` ≡ `for (var i = 0; i <= limit; i++)`. The two are the
same after parsing, and Apollo **regenerates the range sugar whenever a loop has
this canonical counting shape** (so a classic `for (var i = 0; i <= n; i++)` also
comes back as `for i++ from 0..n`). Loops that can't be expressed as a range —
a typed loop variable (`for (Int i = …)`), a non-additive step (`i = i * 2`), or
a direction that doesn't match its comparison — regenerate as the classic form.

#### Classic C-style `for`

The classic loop is still supported, but its header **must be parenthesized**
(this removes the ambiguity with the range form):

```apollo
for (var i = 0; i <= limit; i++) {
  print(items[i])
}
```

Omitting the parentheses is a syntax error:

```text
Classic for loops require parentheses:
for (...)
```

#### For-in

```apollo
for String name in names {
  print(name)
}
```

(For-in parentheses remain optional — `for (String name in names)` is also
accepted.)

---

## Exceptions

### Catch (untyped)

```apollo
try {
  process()
} catch error {
  print(error)
}
```

### Typed catch

```apollo
try {
  process()
} catch IOException error {
  print(error)
}
```

The parenthesized forms `catch (error)` and `catch (IOException error)` are also
accepted. `throw` works as in Dart:

```apollo
throw "boom"
```

---

## Types

Primitive types are **capitalized**: `Int`, `Double`, `Bool`, `Num`, `Void`,
plus `String` and `Object`. Type inference is the default — use `var` for locals
and omit return types to let them be inferred.

```apollo
Int add(Int a, Int b) {
  return a + b
}

var total = add(2, 3)   // inferred Int
```

Generic containers (`List<Int>`, `Map<String, Int>`), `dynamic`, and
`Future<T>` follow Dart.

---

## Functions

### Declarations

```apollo
Int square(Int n) {
  return n * n
}
```

Return types can be omitted (inferred):

```apollo
greet(String name) {
  print("Hi $name")
}
```

Semicolons are optional, so a function body is a clean sequence of statements.

---

## Async functions

Apollo places `async` **before** the declaration. `await` is only valid inside
an `async` function.

### Inferred async return type

```apollo
async loadUser(Int id) {
  var response = await http.get("/users/$id")
  return User.fromJson(response.body)
}
```

Inferred type: `async User` — runtime type `Future<User>`.

### Explicit async return type

```apollo
async User loadUser(Int id) {
  ...
}
```

### Async void

```apollo
async processQueue() {
  await queue.run()
}
```

Inferred type: `async Void` — runtime type `Future<Void>`.

### Async main

```apollo
async main() {
  var user = await loadUser(1)
  print(user.name)
}
```

### Accepted async spellings (Dart-compatibility)

The **canonical** form — and the one Apollo always regenerates — is the leading
`async` with the unwrapped return type: `async User loadUser(Int id)`. So that
agent-produced Dart still parses, Apollo also accepts two equivalent spellings
and normalizes them to the canonical form:

```apollo
async User loadUser(Int id) { ... }          // canonical / generated
async Future<User> loadUser(Int id) { ... }  // leading async, explicit Future
Future<User> loadUser(Int id) async { ... }  // trailing async (Dart form)
```

All three parse to the same declaration and regenerate as
`async User loadUser(Int id) { ... }`. A `Future<T>` return type on an `async`
function is unwrapped to `T`. The trailing-`async` (Dart) form is likewise
accepted for any function (e.g. `main() async { ... }`), but Apollo always emits
the leading form.

---

## Classes

Classes support fields, named and default constructors, instance and `static`
methods, and getters — as in Dart. Because return types are optional, a method
without a return type (e.g. `run()`) is distinguished from a constructor by the
class name.

```apollo
class Account {
  Int balance

  Account(Int start) {
    this.balance = start
  }

  Int deposit(Int amount) {
    this.balance = this.balance + amount
    return this.balance
  }

  static run() {
    var a = Account(100)
    print("bal=" + a.deposit(50))
  }
}
```

### Enums

Rich enums with associated values follow Dart's enhanced-enum syntax:

```apollo
enum Planet {
  earth(5.97, 6371),
  mars(0.642, 3389)
  ;

  Double mass
  Double radius

  const Planet(Double mass, Double radius)
}
```

---

## Using Apollo from Dart (ApolloVM API)

```dart
import 'package:apollovm/apollovm.dart';

void main() async {
  var vm = ApolloVM();

  await vm.loadCodeUnit(SourceCodeUnit('apollo', r'''
    Int addOne(Int n) {
      return n + 1
    }
  ''', id: 'demo'));

  // Execute:
  var runner = vm.createRunner('apollo')!;
  var result = await runner.executeFunction('', 'addOne',
      positionalParameters: [41]);
  print(result.getValueNoContext()); // 42

  // Translate Apollo -> Dart:
  var dart = vm.generateAllCodeIn('dart');
  print((await dart.writeAllSources()).toString());
}
```

A runnable example lives at
[`example/apollovm_example_apollo.dart`](../example/apollovm_example_apollo.dart).

---

## Design philosophy

- Dart-compatible string syntax
- Parentheses optional in control-flow statements
- Static typing everywhere, with type inference by default
- Optional explicit return types
- `async` is a declaration modifier; `await` only inside `async` functions
- Rich enums with associated values
- Named and factory constructors
- Logical imports
- Semicolons optional
- Familiar syntax inspired by Dart, Kotlin, Swift, TypeScript, Java and C#
- Designed for both humans and coding agents
- Minimal punctuation, maximum readability
