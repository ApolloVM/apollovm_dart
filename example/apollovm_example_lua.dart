import 'package:apollovm/apollovm.dart';

void main() async {
  var vm = ApolloVM();

  var codeUnit = SourceCodeUnit('lua', r'''
      Foo = {}
      Foo.__index = Foo

      function Foo:main(title, a, b, c)
        local sumAB = a + b
        local sumABC = a + b + c
        print(title)
        print(sumAB)
        print(sumABC)
      end
      ''', id: 'test');

  var loadOK = await vm.loadCodeUnit(codeUnit);

  if (!loadOK) {
    print("Can't load source!");
    return;
  }

  print('---------------------------------------');

  var luaRunner = vm.createRunner('lua')!;

  // Map the `print` function in the VM:
  luaRunner.externalPrintFunction = (o) => print("» $o");

  await luaRunner.executeClassMethod(
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
//   void main(dynamic title, dynamic a, dynamic b, dynamic c) {
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
