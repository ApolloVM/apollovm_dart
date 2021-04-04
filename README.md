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

ApolloVM is a portable VM (native, JS/Web, Flutter) that can parser, translate and run multiple languages, like Dart, Java, Kotlin and JavaScript.


## Usage

The ApolloVM is still in alpha stage. Below, we can see simple usage examples in Dart and Java.

### Language: Dart

```dart
import 'package:apollovm/apollovm.dart';

void main() async {
  var vm = ApolloVM();

  var codeUnit = CodeUnit(
          'dart',
          r'''
            void main(List<String> args) {
              var s = args[0] ;
              print(s);
            }
          ''',
          'test');

  var loadOK = await vm.loadCodeUnit(codeUnit);

  if (!loadOK) {
    throw StateError('Error parsing Dart code!');
  }

  var dartRunner = vm.getRunner('dart')!;
  dartRunner.executeFunction('', 'main', [
    ['foo!', 'abc']
  ]);

  print('---------------------------------------');
  // Regenerate code:
  var codeStorageDart = vm.generateAllCodeIn('dart');
  var allSourcesDart = codeStorageDart.writeAllSources().toString();
  print(allSourcesDart);
  
}
```

*Note: the parsed function `print` was mapped as an external function.*

### Language: Java8

```dart
import 'package:apollovm/apollovm.dart';

void main() async {

  var vm = ApolloVM();

  var codeUnit = CodeUnit(
          'java8',
          r'''
            class Foo {
               static public void main(String[] args) {
                 String s = args[0] ;
                 print(s);
               }
            }
          ''',
          'test');

  var loadOK = await vm.loadCodeUnit(codeUnit);

  if (!loadOK) {
    throw StateError('Error parsing Java8 code!');
  }

  var java8Runner = vm.getRunner('java8')!;
  java8Runner.executeClassMethod('', 'Foo', 'main', [
    ['foo!', 'abc']
  ]);

  print('---------------------------------------');
  // Regenerate code:
  var codeStorageDart = vm.generateAllCodeIn('dart');
  var allSourcesDart = codeStorageDart.writeAllSources().toString();
  print(allSourcesDart);

  print('---------------------------------------');
  // Regenerate code:
  var codeStorageJava8 = vm.generateAllCodeIn('java8');
  var allSourcesJava8 = codeStorageJava8.writeAllSources().toString();
  print(allSourcesJava8);
  
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
- Which a feature?
  - Open a feature request.
- Are you using and liking the project?
  - Promote the project: create an article, post or make a donation.
- Are you a developer?
  - Fix a bug and send a pull request.
  - Implement a new feature.
  - Implement/improve a language support.
  - Added support for another language.
- Have you already helped in any way?
  - **Many thanks from me, the contributors and everybody that uses this project!**


[tracker]: https://github.com/ApolloVM/apollovm_dart/issues

## Author

Graciliano M. Passos: [gmpassos@GitHub][github].

[github]: https://github.com/gmpassos

## License

[Apache License - Version 2.0][apache_license]

[apache_license]: https://www.apache.org/licenses/LICENSE-2.0.txt
