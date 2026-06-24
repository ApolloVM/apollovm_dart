import 'package:apollovm/apollovm.dart';

void main() async {
  var vm = ApolloVM();

  var codeUnit = SourceCodeUnit('kotlin', r'''
      class Foo {
          fun main(title: String, a: Int, b: Int, c: Int) {
            val sumAB = a + b
            val sumABC = a + b + c
            println(title)
            println(sumAB)
            println(sumABC)
          }
      }
      ''', id: 'test');

  var loadOK = await vm.loadCodeUnit(codeUnit);

  if (!loadOK) {
    print("Can't load source!");
    return;
  }

  print('---------------------------------------');

  var kotlinRunner = vm.createRunner('kotlin')!;

  // Map the `print` function in the VM:
  kotlinRunner.externalPrintFunction = (o) => print("» $o");

  await kotlinRunner.executeClassMethod(
    '',
    'Foo',
    'main',
    positionalParameters: ['Sums:', 10, 20, 30],
  );

  print('---------------------------------------');

  // Regenerate code in Dart:
  var codeStorageDart = vm.generateAllCodeIn('dart');
  var allSourcesDart = await codeStorageDart.writeAllSources();
  print(allSourcesDart);
}

/////////////
// OUTPUT: //
/////////////
// ---------------------------------------
// » Sums:
// » 30
// » 60
// ---------------------------------------
// <<<< [SOURCES_BEGIN] >>>>
// <<<< NAMESPACE="" >>>>
// <<<< CODE_UNIT_START="/test" >>>>
// class Foo {
//
//   void main(String title, int a, int b, int c) {
//     final sumAB = a + b;
//     final sumABC = (a + b) + c;
//     print(title);
//     print(sumAB);
//     print(sumABC);
//   }
//
// }
// <<<< CODE_UNIT_END="/test" >>>>
// <<<< [SOURCES_END] >>>>
//
