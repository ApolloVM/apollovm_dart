import 'package:apollovm/apollovm.dart';

void main() async {
  var vm = ApolloVM();

  var codeUnit = SourceCodeUnit('typescript', r'''
      class Foo {
        static main(title: string, a: number, b: number, c: number): void {
          let sumAB: number = a + b;
          let sumABC: number = a + b + c;
          print(title);
          print(sumAB);
          print(sumABC);
        }
      }
      ''', id: 'test');

  var loadOK = await vm.loadCodeUnit(codeUnit);

  if (!loadOK) {
    print("Can't load source!");
    return;
  }

  print('---------------------------------------');

  var tsRunner = vm.createRunner('typescript')!;

  // Map the `print` function in the VM:
  tsRunner.externalPrintFunction = (o) => print("» $o");

  await tsRunner.executeClassMethod(
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
//   void main(String title, num a, num b, num c) {
//     num sumAB = a + b;
//     num sumABC = (a + b) + c;
//     print(title);
//     print(sumAB);
//     print(sumABC);
//   }
//
// }
// <<<< CODE_UNIT_END="/test" >>>>
// <<<< [SOURCES_END] >>>>
//
