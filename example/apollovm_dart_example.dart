import 'package:apollovm/apollovm.dart';

void main() async {
  var vm = ApolloVM();

  var codeUnit = CodeUnit(
      'dart',
      r'''
      class Foo {
          void main(List<String> args) {
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
    print("Can't load source!");
    return;
  }

  var dartRunner = vm.createRunner('dart')!;
  dartRunner.executeClassMethod('', 'Foo', 'main', [
    ['Sums:', 10, 20, 50]
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
