import 'package:apollovm/apollovm.dart';

void main() async {
  var vm = ApolloVM();

  var codeUnit = SourceCodeUnit('python', r'''
      def main(title, a, b, c):
          sum_ab = a + b
          sum_abc = a + b + c
          print(title)
          print(sum_ab)
          print(sum_abc)
          if sum_abc > sum_ab:
              print(f'{title} sum_abc > sum_ab')
      ''', id: 'test');

  var loadOK = await vm.loadCodeUnit(codeUnit);

  if (!loadOK) {
    print("Can't load source!");
    return;
  }

  print('---------------------------------------');

  var pythonRunner = vm.createRunner('python')!;

  // Map the `print` function in the VM:
  pythonRunner.externalPrintFunction = (o) => print("» $o");

  await pythonRunner.executeFunction(
    '',
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
// » Sums: sum_abc > sum_ab
// ---------------------------------------
// <<<< [SOURCES_BEGIN] >>>>
// <<<< NAMESPACE="" >>>>
// <<<< CODE_UNIT_START="/test" >>>>
//   void main(dynamic title, dynamic a, dynamic b, dynamic c) {
//     var sum_ab = a + b;
//     var sum_abc = (a + b) + c;
//     print(title);
//     print(sum_ab);
//     print(sum_abc);
//     if (sum_abc > sum_ab) {
//         print('${title} sum_abc > sum_ab');
//     }
//
//   }
//
// <<<< CODE_UNIT_END="/test" >>>>
// <<<< [SOURCES_END] >>>>
//
