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
