import 'package:apollovm/apollovm.dart';

void main() async {
  var vm = ApolloVM();

  var codeUnit = CodeUnit(
      'dart',
      r'''
      class Foo {
      
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
  await dartRunner.executeClassMethod('', 'Foo', 'main', positionalParameters: [
    ['Sums:', 10, 30, 50]
  ]);

  print('---------------------------------------');
  // Regenerate code in Dart:
  var codeStorageDart = vm.generateAllCodeIn('dart');
  var allSourcesDart = codeStorageDart.writeAllSources();
  print(allSourcesDart);

  print('---------------------------------------');
  // Regenerate code in Java11:
  var codeStorageJava = vm.generateAllCodeIn('java11');
  var allSourcesJava = codeStorageJava.writeAllSources();
  print(allSourcesJava);
}
