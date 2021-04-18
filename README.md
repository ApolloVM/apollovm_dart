## ApolloVM


[![pub package](https://img.shields.io/pub/v/apollovm.svg?logo=dart&logoColor=00b9fc)](https://pub.dartlang.org/packages/apollovm)
[![Null Safety](https://img.shields.io/badge/null-safety-brightgreen)](https://dart.dev/null-safety)

[![CI](https://img.shields.io/github/workflow/status/ApolloVM/apollovm_dart/Dart%20CI/master?logo=github-actions&logoColor=white)](https://github.com/ApolloVM/apollovm_dart/actions)
[![GitHub Tag](https://img.shields.io/github/v/tag/ApolloVM/apollovm_dart?logo=git&logoColor=white)](https://github.com/ApolloVM/apollovm_dart/releases)
[![New Commits](https://img.shields.io/github/commits-since/ApolloVM/apollovm_dart/latest?logo=git&logoColor=white)](https://github.com/ApolloVM/apollovm_dart/network)
[![Last Commits](https://img.shields.io/github/last-commit/ApolloVM/apollovm_dart?logo=git&logoColor=white)](https://github.com/ApolloVM/apollovm_dart/commits/master)
[![Pull Requests](https://img.shields.io/github/issues-pr/ApolloVM/apollovm_dart?logo=github&logoColor=white)](https://github.com/ApolloVM/apollovm_dart/pulls)
[![Code size](https://img.shields.io/github/languages/code-size/ApolloVM/apollovm_dart?logo=github&logoColor=white)](https://github.com/ApolloVM/apollovm_dart)
[![License](https://img.shields.io/github/license/ApolloVM/apollovm_dart?logo=open-source-initiative&logoColor=green)](https://github.com/ApolloVM/apollovm_dart/blob/master/LICENSE)

ApolloVM is a portable VM (native, JS/Web, Flutter) that can parse, translate and run multiple languages, like Dart, Java, Kotlin and JavaScript.

## Command Line Usage

You can use the executable `apollovm` to `run` or `translate` source codes. 

First you should activate the package globally:

```shell
$> dart pub global activate apollovm
```

Now you can use the `apollovm` Dart executable:
```shell
$> apollovm help

ApolloVM - a compact VM for Dart and Java.

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

## Package Usage

The ApolloVM is still in alpha stage. Below, we can see a simple usage examples in Dart and Java.

### Language: Dart

```dart
import 'package:apollovm/apollovm.dart';

void main() async {
  var vm = ApolloVM();

  var codeUnit = CodeUnit(
          'dart',
          r'''
          
          void main(List<Object> args) {
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
          }
            
          ''',
          'test');

  var loadOK = await vm.loadCodeUnit(codeUnit);

  if (!loadOK) {
    throw StateError('Error parsing Dart code!');
  }

  var dartRunner = vm.getRunner('dart')!;
  
  dartRunner.executeFunction('', 'main', [
    ['Sums:', 10, 30, 50]
  ]);

  print('---------------------------------------');
  // Regenerate code:
  var codeStorageDart = vm.generateAllCodeIn('dart');
  var allSourcesDart = codeStorageDart.writeAllSources().toString();
  print(allSourcesDart);
  
}
```

*Note: the parsed function `print` was mapped as an external function.*


Output:
```text
variables> a: 10 ; b: 15 ; c: 120
Sums:
25
145 
```

### Language: Java11

```dart
import 'package:apollovm/apollovm.dart';

void main() async {

  var vm = ApolloVM();

  var codeUnit = CodeUnit(
          'java11',
          r'''
            class Foo {
               static public void main(String[] args) {
                 var title = args[0];
                 var a = args[1];
                 var b = args[2];
                 var c = args[3];
                 var sumAB = a + b ;
                 var sumABC = a + b + c;
                 print(title);
                 print(sumAB);
                 print(sumABC);
               }
            }
          ''',
          'test');

  var loadOK = await vm.loadCodeUnit(codeUnit);

  if (!loadOK) {
    throw StateError('Error parsing Java11 code!');
  }

  var javaRunner = vm.getRunner('java11')!;
  
  javaRunner.executeClassMethod('', 'Foo', 'main', [
    ['Sums:', 10, 20, 30]
  ]);

  print('---------------------------------------');
  // Regenerate code:
  var codeStorageDart = vm.generateAllCodeIn('dart');
  var allSourcesDart = codeStorageDart.writeAllSources().toString();
  print(allSourcesDart);

  print('---------------------------------------');
  // Regenerate code:
  var codeStorageJava = vm.generateAllCodeIn('java11');
  var allSourcesJava = codeStorageJava.writeAllSources().toString();
  print(allSourcesJava);
  
}
```

*Note: the parsed function `print` was mapped as an external function.*


## See Also

ApolloVM uses [PetitParser for Dart][petitparser-pub] to define the grammars of the languages and to analyze the source codes.

- [PetitParser @ GitHub][petitparser-github] (a very nice project to build parsers).

[petitparser-pub]: https://pub.dev/packages/petitparser
[petitparser-github]: https://github.com/petitparser

## Features and bugs

Please file feature requests and bugs at the [issue tracker][tracker].

## Contribution

Any help from open-source community is always welcome and needed:
- Found an issue?
  - Fill a bug with details.
- Wish a feature?
  - Open a feature request.
- Are you using and liking the project?
  - Promote the project: create an article, post or make a donation.
- Are you a developer?
  - Fix a bug and send a pull request.
  - Implement a new feature.
  - Improve a language support.
  - Add support for another language.
  - Improve unit tests.
- Have you already helped in any way?
  - **Many thanks from me, the contributors and everybody that uses this project!**


[tracker]: https://github.com/ApolloVM/apollovm_dart/issues

## Author

Graciliano M. Passos: [gmpassos@GitHub][github].

[github]: https://github.com/gmpassos

## License

[Apache License - Version 2.0][apache_license]

[apache_license]: https://www.apache.org/licenses/LICENSE-2.0.txt
