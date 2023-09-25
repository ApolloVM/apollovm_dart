## ApolloVM


[![pub package](https://img.shields.io/pub/v/apollovm.svg?logo=dart&logoColor=00b9fc)](https://pub.dartlang.org/packages/apollovm)
[![Null Safety](https://img.shields.io/badge/null-safety-brightgreen)](https://dart.dev/null-safety)
[![Dart CI](https://github.com/ApolloVM/apollovm_dart/actions/workflows/dart.yml/badge.svg?branch=master)](https://github.com/ApolloVM/apollovm_dart/actions/workflows/dart.yml)
[![GitHub Tag](https://img.shields.io/github/v/tag/ApolloVM/apollovm_dart?logo=git&logoColor=white)](https://github.com/ApolloVM/apollovm_dart/releases)
[![New Commits](https://img.shields.io/github/commits-since/ApolloVM/apollovm_dart/latest?logo=git&logoColor=white)](https://github.com/ApolloVM/apollovm_dart/network)
[![Last Commits](https://img.shields.io/github/last-commit/ApolloVM/apollovm_dart?logo=git&logoColor=white)](https://github.com/ApolloVM/apollovm_dart/commits/master)
[![Pull Requests](https://img.shields.io/github/issues-pr/ApolloVM/apollovm_dart?logo=github&logoColor=white)](https://github.com/ApolloVM/apollovm_dart/pulls)
[![Code size](https://img.shields.io/github/languages/code-size/ApolloVM/apollovm_dart?logo=github&logoColor=white)](https://github.com/ApolloVM/apollovm_dart)
[![License](https://img.shields.io/github/license/ApolloVM/apollovm_dart?logo=open-source-initiative&logoColor=green)](https://github.com/ApolloVM/apollovm_dart/blob/master/LICENSE)

ApolloVM is a portable VM (native, JS/Web, Flutter) that can parse, translate and run multiple languages, like Dart, Java and JavaScript.

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

ApolloVM - A compact VM for Dart and Java.

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

-----------------------------

## Package Usage

The ApolloVM is still in alpha stage. Below, we can see a simple usage examples in Dart and Java.

### Language: `Dart`

Loading Dart source code, executing it, and then converting it to Java 11:

```dart
import 'package:apollovm/apollovm.dart';

void main() async {
  var vm = ApolloVM();

  var codeUnit = CodeUnit(
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
          'test');

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
  var allSourcesJava = codeStorageJava.writeAllSources();
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

  var codeUnit = CodeUnit(
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
          'test');

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
  var allSourcesDart = codeStorageDart.writeAllSources().toString();
  print(allSourcesDart);
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
