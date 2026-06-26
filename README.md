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

ApolloVM is a portable VM (native, JS/Web, Flutter) that can parse, translate, and execute multiple languages such as Dart, Java, Kotlin, C#, JavaScript, TypeScript, Lua, and Python. It also provides on-the-fly compilation to Wasm.

-----------------------------

## Live Example

Experience ApolloVM in action right from your browser:

- Explore the [ApolloVM Web Demo](https://apollovm.github.io/apollovm_web_example/www/)

If you prefer to run the demo on your local machine:
- Follow the step-by-step instructions available in the [GitHub Repository](https://github.com/ApolloVM/apollovm_web_example).

-----------------------------

## Command Line Usage

You can use the executable `apollovm` to `run` or `translate` source codes. 

First you should activate the package globally:

```shell
$> dart pub global activate apollovm
```

Now you can use the `apollovm` Dart executable:
```shell
$> apollovm help

ApolloVM - A compact VM for Dart, Java, Kotlin, C#, JavaScript, TypeScript, Lua and Python.

Usage: apollovm <command> [arguments]

Global options:
-h, --help       Print this usage information.
-v, --version    Show ApolloVM version.

Available commands:
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

The same commands work for JavaScript (`.js`) files. To `run` a JavaScript file:
```shell
$> apollovm run -v test/hello_world.js foo
## [RUN]        File: 'test/hello_world.js' ; language: javascript > main( [foo] )
Hello World!
- name: foo
```

To `translate` a JavaScript file to Dart:
```shell
$> apollovm translate -v --target dart test/hello_world.js
## [TRANSLATE]  File: 'test/hello_world.js' ; language: javascript > targetLanguage: dart
<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test/hello_world.js" >>>>
class Hello {

  static void main(dynamic name) {
    print('Hello World!');
    print('- name: ${name}');
  }

}
<<<< CODE_UNIT_END="/test/hello_world.js" >>>>
<<<< [SOURCES_END] >>>>
```

The same commands work for TypeScript (`.ts`) files. To `translate` a TypeScript file to Dart:
```shell
$> apollovm translate -v --target dart test/hello_world.ts
## [TRANSLATE]  File: 'test/hello_world.ts' ; language: typescript > targetLanguage: dart
<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test/hello_world.ts" >>>>
class Hello {

  static void main(String name) {
    print('Hello World!');
    print('- name: ${name}');
  }

}
<<<< CODE_UNIT_END="/test/hello_world.ts" >>>>
<<<< [SOURCES_END] >>>>
```

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

The ApolloVM is still in alpha stage. Below, we can see simple usage examples in Dart, Java, Kotlin, C#, JavaScript, TypeScript, Lua and Python.

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
      
          int main(List<Object> args) {
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

  int main(Object[] args) {
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

### Language: `Kotlin`

Loading Kotlin source code, executing it, and then converting it to Dart:

```dart
import 'package:apollovm/apollovm.dart';

void main() async {
  var vm = ApolloVM();

  var codeUnit = SourceCodeUnit(
          'kotlin',
          r'''
            class Foo {
              fun greet(name: String, count: Int) {
                val msg = "Hello $name, you have $count messages."
                println(msg)
              }
            }
          ''',
          id: 'test');

  var loadOK = await vm.loadCodeUnit(codeUnit);

  if (!loadOK) {
    throw StateError('Error parsing Kotlin code!');
  }

  var kotlinRunner = vm.createRunner('kotlin')!;

  // Map the `print` function in the VM:
  kotlinRunner.externalPrintFunction = (o) => print("» $o");

  await kotlinRunner.executeClassMethod('', 'Foo', 'greet',
      positionalParameters: ['World', 3]);

  print('---------------------------------------');

  // Regenerate code in Dart:
  var codeStorageDart = vm.generateAllCodeIn('dart');
  var allSourcesDart = await codeStorageDart.writeAllSources();
  print(allSourcesDart.toString());
}
```

*Note: the parsed function `println` is normalized to the VM's `print` (mapped as an external function).*

Output:
```text
» Hello World, you have 3 messages.
---------------------------------------
<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
class Foo {

  void greet(String name, int count) {
    final msg = 'Hello $name, you have $count messages.';
    print(msg);
  }

}
<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
```

Kotlin support reaches parity with the Java feature set: top-level and class `fun`
declarations, `val`/`var` with type inference, `if`/`else`, `for (x in …)`, `while`,
`listOf`/`mapOf` literals, and `"$x"` / `"${expr}"` string templates — all
translatable to Dart, Java or back to Kotlin.

### Language: `JavaScript`

Loading JavaScript (modern ES) source code, executing it, and then converting it to Dart:

```dart
import 'package:apollovm/apollovm.dart';

void main() async {
  var vm = ApolloVM();

  var codeUnit = SourceCodeUnit(
          'javascript',
          r'''
            class Foo {
              greet(name, count) {
                let msg = `Hello ${name}, you have ${count} messages.`;
                print(msg);
              }
            }
          ''',
          id: 'test');

  var loadOK = await vm.loadCodeUnit(codeUnit);

  if (!loadOK) {
    throw StateError('Error parsing JavaScript code!');
  }

  var jsRunner = vm.createRunner('javascript')!;

  // Map the `print` function in the VM:
  jsRunner.externalPrintFunction = (o) => print("» $o");

  await jsRunner.executeClassMethod('', 'Foo', 'greet',
      positionalParameters: ['World', 3]);

  print('---------------------------------------');

  // Regenerate code in Dart:
  var codeStorageDart = vm.generateAllCodeIn('dart');
  var allSourcesDart = await codeStorageDart.writeAllSources();
  print(allSourcesDart.toString());
}
```

*Note: the parsed function `print` was mapped as an external function.*

Output:
```text
» Hello World, you have 3 messages.
---------------------------------------
<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
class Foo {

  void greet(dynamic name, dynamic count) {
    var msg = 'Hello ${name}, you have ${count} messages.';
    print(msg);
  }

}
<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
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

Loading TypeScript source code, executing it, and then converting it to Dart:

```dart
import 'package:apollovm/apollovm.dart';

void main() async {
  var vm = ApolloVM();

  var codeUnit = SourceCodeUnit(
          'typescript',
          r'''
            class Foo {
              greet(name: string, count: number): void {
                let msg: string = `Hello ${name}, you have ${count} messages.`;
                print(msg);
              }
            }
          ''',
          id: 'test');

  var loadOK = await vm.loadCodeUnit(codeUnit);

  if (!loadOK) {
    throw StateError('Error parsing TypeScript code!');
  }

  var tsRunner = vm.createRunner('typescript')!;

  // Map the `print` function in the VM:
  tsRunner.externalPrintFunction = (o) => print("» $o");

  await tsRunner.executeClassMethod('', 'Foo', 'greet',
      positionalParameters: ['World', 3]);

  print('---------------------------------------');

  // Regenerate code in Dart:
  var codeStorageDart = vm.generateAllCodeIn('dart');
  var allSourcesDart = await codeStorageDart.writeAllSources();
  print(allSourcesDart.toString());
}
```

*Note: the parsed function `print` was mapped as an external function.*

Output:
```text
» Hello World, you have 3 messages.
---------------------------------------
<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
class Foo {

  void greet(String name, num count) {
    String msg = 'Hello ${name}, you have ${count} messages.';
    print(msg);
  }

}
<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
```

TypeScript is bidirectional: ApolloVM parses `.ts`/`typescript` source (including
`interface`, `enum`, and member modifiers) into the AST, executes it, and generates
idiomatic TypeScript with type annotations. The same `interface`/`enum`/modifier
constructs are also supported in Dart (`abstract class`, `enum`, `static`/`final`),
so they cross-translate between Dart, TypeScript and JavaScript.

### Language: `Lua`

Loading Lua source code, executing it, and then converting it to Dart:

```dart
import 'package:apollovm/apollovm.dart';

void main() async {
  var vm = ApolloVM();

  var codeUnit = SourceCodeUnit(
          'lua',
          r'''
            Foo = {}
            Foo.__index = Foo

            function Foo:main(title, a, b, c)
              local sumAB = a + b
              local sumABC = a + b + c
              print(title)
              print(sumAB)
              print(sumABC)
            end
          ''',
          id: 'test');

  var loadOK = await vm.loadCodeUnit(codeUnit);

  if (!loadOK) {
    throw StateError('Error parsing Lua code!');
  }

  var luaRunner = vm.createRunner('lua')!;

  // Map the `print` function in the VM:
  luaRunner.externalPrintFunction = (o) => print("» $o");

  await luaRunner.executeClassMethod('', 'Foo', 'main',
      positionalParameters: ['Sums:', 10, 20, 30]);

  print('---------------------------------------');

  // Regenerate code in Dart:
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
---------------------------------------
<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
class Foo {

  void main(dynamic title, dynamic a, dynamic b, dynamic c) {
    var sumAB = a + b;
    var sumABC = (a + b) + c;
    print(title);
    print(sumAB);
    print(sumABC);
  }

}
<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
```

Lua is bidirectional: ApolloVM parses `.lua` source into the AST, executes it, and
generates idiomatic Lua (keyword-delimited blocks with `end`, `local` variables, `..`
concatenation, `and`/`or`/`not`/`~=`, and generic `for ... in ipairs(...)`) from any
loaded AST. Object-oriented code uses the conventional table + metatable form
(`Name = {}`, `Name.__index = Name`, `function Name:method(...)`), so classes round-trip
to and from Dart, Java, Kotlin, JavaScript and TypeScript.

### Language: `Python`

Loading Python source code, executing it, and then converting it to Dart:

```dart
import 'package:apollovm/apollovm.dart';

void main() async {
  var vm = ApolloVM();

  var codeUnit = SourceCodeUnit(
          'python',
          r'''
            class Foo:
                def greet(self, name, count):
                    msg = f'Hello {name}, you have {count} messages.'
                    print(msg)
          ''',
          id: 'test');

  var loadOK = await vm.loadCodeUnit(codeUnit);

  if (!loadOK) {
    throw StateError('Error parsing Python code!');
  }

  var pyRunner = vm.createRunner('python')!;

  // Map the `print` function in the VM:
  pyRunner.externalPrintFunction = (o) => print("» $o");

  await pyRunner.executeClassMethod('', 'Foo', 'greet',
      positionalParameters: ['World', 3]);

  print('---------------------------------------');

  // Regenerate code in Dart:
  var codeStorageDart = vm.generateAllCodeIn('dart');
  var allSourcesDart = await codeStorageDart.writeAllSources();
  print(allSourcesDart.toString());
}
```

*Note: the parsed function `print` was mapped as an external function.*

Output:
```text
» Hello World, you have 3 messages.
---------------------------------------
<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
class Foo {

  void greet(dynamic name, dynamic count) {
    var msg = 'Hello ${name}, you have ${count} messages.';
    print(msg);
  }

}
<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
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

- **Status:** *Wasm support is still in the alpha stage and currently only supports basic integer operations. Full support for
AST trees is currently under development.*

Example of Dart code compiled to Wasm:
```dart
int main( int a , double b ) {
  var x = (a + b) / 2 ;
  if (x > 1000) {
    return -1;
  }
  return x ;
}
```

Example code to compile to WebAssembly (Wasm):
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

- JavaScript: extended support (destructuring, spread, async/await, `this.x` constructor parameters, full ESM modules). *Named arrow functions (`const f = (a, b) => a + b;`), anonymous arrow callbacks/closures (`(x) => x * 2`), and the ternary operator (`c ? a : b`) are already supported.*
  - *See the [JavaScript implementation (at "lib/src/languages/javascript/es")](https://github.com/ApolloVM/apollovm_dart/tree/master/lib/src/languages/javascript/es).*


- TypeScript: extended support (generics, union/intersection types, type aliases, parameter properties, enum member access at runtime, decorators). *Type annotations, `interface`, `enum`, and access modifiers (`public`/`private`/`protected`/`readonly`/`static`/`abstract`) are already supported.*
  - *See the [TypeScript implementation (at "lib/src/languages/typescript/ts")](https://github.com/ApolloVM/apollovm_dart/tree/master/lib/src/languages/typescript/ts).*


- Lua: extended support (`repeat ... until`, multiple assignment/returns, varargs, non-`ipairs` numeric-for round-tripping, and hand-written metatable styles beyond the `Name = {}` / `function Name:method` convention).
  - *See the [Lua implementation (at "lib/src/languages/lua")](https://github.com/ApolloVM/apollovm_dart/tree/master/lib/src/languages/lua).*


- Python: extended support (comprehensions, decorators, `with` statements, `*args`/`**kwargs`, multiple assignment/returns). *Functions, classes/`self`-methods, `if`/`elif`/`else`, `while`, `for ... in`, `try`/`except`/`finally` + `raise`, lists & dicts, f-strings, keyword arguments, `lambda` expressions, conditional expressions (`a if c else b`), and `import`/`from ... import` are already supported.*
  - *See the [Python implementation (at "lib/src/languages/python")](https://github.com/ApolloVM/apollovm_dart/tree/master/lib/src/languages/python).*


- Package Importer.


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
