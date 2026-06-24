import 'package:apollovm/apollovm.dart';

void main() async {
  var vm = ApolloVM();

  var codeUnit = SourceCodeUnit('java11', r'''
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
         }
      }
      ''', id: 'test');

  var loadOK = await vm.loadCodeUnit(codeUnit);

  if (!loadOK) {
    print("Can't load source!");
    return;
  }

  print('---------------------------------------');

  var javaRunner = vm.createRunner('java11')!;

  // Map the `print` function in the VM:
  javaRunner.externalPrintFunction = (o) => print("» $o");

  await javaRunner.executeClassMethod(
    '',
    'Foo',
    'main',
    positionalParameters: [
      ['Sums:', 10, 20, 30],
    ],
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
//   static void main(List<Object> args) {
//     var title = args[0];
//     var a = args[1];
//     var b = args[2];
//     var c = args[3];
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
