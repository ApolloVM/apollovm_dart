import 'package:apollovm/apollovm.dart';

void main() async {
  var vm = ApolloVM();

  var codeUnit = CodeUnit(
      'dart',
      r'''
      class Foo {
          void main(List<String> args) {
            var s = args[0] ;
            print(s);
          }
      }
      ''',
      'test');

  var loadOK = await vm.loadCodeUnit(codeUnit);

  if (!loadOK) {
    print("Can't load source!");
    return;
  }

  var dartRunner = vm.getRunner('dart')!;
  dartRunner.executeClassMethod('', 'Foo', 'main', [
    ['foo!', 'abc']
  ]);

  print('---------------------------------------');
  // Regenerate code in Dart:
  var codeStorageDart = vm.generateAllCodeIn('dart');
  var allSourcesDart = codeStorageDart.writeAllSources();
  print(allSourcesDart);

  print('---------------------------------------');
  // Regenerate code Java8:
  var codeStorageJava8 = vm.generateAllCodeIn('java8');
  var allSourcesJava8 = codeStorageJava8.writeAllSources();
  print(allSourcesJava8);
}
