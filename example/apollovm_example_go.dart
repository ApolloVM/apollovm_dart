import 'package:apollovm/apollovm.dart';

void main() async {
  var vm = ApolloVM();

  var codeUnit = SourceCodeUnit('go', r'''
      type Foo struct {
      }

      func (o *Foo) main(title string, a int, b int, c int) {
        sumAB := a + b
        sumABC := a + b + c
        fmt.Println(title)
        fmt.Println(sumAB)
        fmt.Println(sumABC)
      }
      ''', id: 'test');

  var loadOK = await vm.loadCodeUnit(codeUnit);

  if (!loadOK) {
    print("Can't load source!");
    return;
  }

  print('---------------------------------------');

  var goRunner = vm.createRunner('go')!;

  // Map the `print` function in the VM:
  goRunner.externalPrintFunction = (o) => print("» $o");

  // `Foo.main` is a struct method (needs a receiver instance);
  // `classInstanceFields` provides one (here with no fields).
  await goRunner.executeClassMethod(
    '',
    'Foo',
    'main',
    positionalParameters: ['Sums:', 10, 20, 30],
    classInstanceFields: const {},
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
//     var sumAB = a + b;
//     var sumABC = (a + b) + c;
//     print(title);
//     print(sumAB);
//     print(sumABC);
//   }
//
// }
// <<<< CODE_UNIT_END="/test" >>>>
// <<<< [SOURCES_END] >>>>
//
