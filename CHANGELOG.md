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
