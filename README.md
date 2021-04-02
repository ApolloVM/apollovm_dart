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

The ApolloVM is still in alpha stage. Below we can see simple examples in Dart and Java.

### Language: Dart

```dart
import 'package:apollovm/apollovm.dart';

void main() async {

  var parser = ApolloParserDart();

  var root = await parser.parse(r'''
          void main(List<String> args) {
            var s = args[0] ;
            print(s);
          }
      ''');

  if (root == null) {
    throw StateError('Error parsing Dart code!');
  }

  print('<<<<<<<<<<<<<<<<<<<< REGENERATE PARSED DART CODE:');
  print(root.generateCode());
  print('>>>>>>>>>>>>>>>>>>>>');

  // Execute parsed code, calling function `main`:
  root.execute('main', [
    ['foo!', 'abc']
  ]);
}
```

*Note: the parsed function `print` was mapped as an external function.*

### Language: Java8

```dart
import 'package:apollovm/apollovm.dart';

void main() async {
  var parser = ApolloParserJava8();

  var root = await parser.parse(r'''
        class Foo {
           static public void main(String[] args) {
             String s = args[0] ;
             print(s);
           }
        }
      ''');

  if (root == null) {
    throw StateError('Error parsing Java8 code!');
  }

  print('<<<<<<<<<<<<<<<<<<<< REGENERATE PARSED JAVA CODE:');
  print(root.generateCode());
  print('>>>>>>>>>>>>>>>>>>>>');

  root.getClass('Foo')!.execute('main', [
    ['foo!', 'abc']
  ]);
}
```

*Note: the parsed function `print` was mapped as an external function.*


## See Also

ApolloVM uses [PetitParser for Dart][petitparser] (a very nice project) to define language grammar and parse source code.

[petitparser]: https://pub.dev/packages/petitparser

## Features and bugs

Please file feature requests and bugs at the [issue tracker][tracker].

## Contribution

Any help from open-source community is always welcome and needed:
- Found an issue?
  - Fill a bug with details.
- Which a feature?
  - Open a feature request.
- Are you using and liking the project?
  - Prommote the project: create an article, post or a donation.
- Are you a developer?
  - Fix a bug and send a pull request.
  - Implement a new feature.
  - Implement/improve a language support.
- Have you already help in any way?
  - **Many thanks from me, the contributors and everybody that uses this project!**


[tracker]: https://github.com/ApolloVM/apollovm_dart/issues

## Author

Graciliano M. Passos: [gmpassos@GitHub][github].

[github]: https://github.com/gmpassos

## License

[Apache License - Version 2.0][apache_license]

[apache_license]: https://www.apache.org/licenses/LICENSE-2.0.txt
