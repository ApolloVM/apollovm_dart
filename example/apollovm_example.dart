import 'package:apollovm/apollovm.dart';

void main() async {
  var vm = ApolloVM();

  var codeUnit = CodeUnit(
      'dart',
      r'''
      class Foo {
      
          int main(List<Object> args) {
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
            
            // Map:
            var map = <String,int>{
            'a': a,
            'b': b,
            'c': c,
            'sumAB': sumAB,
            "sumABC": sumABC,
            };
            
            print('Map: $map');
            print('Map `b`: ${map['b']}');
            
            return map['sumABC'];
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

  // Map the `print` function in the VM:
  dartRunner.externalPrintFunction = (o) => print("» $o");

  var astValue = await dartRunner
      .executeClassMethod('', 'Foo', 'main', positionalParameters: [
    ['Sums:', 10, 30, 50]
  ]);

  var result = astValue.getValueNoContext();
  print('Result: $result');

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

/////////////
// OUTPUT: //
/////////////
// ---------------------------------------
// » variables> a: 10 ; b: 15 ; c: 120
// » Sums:
// » 25
// » 145
// » Map: {a: 10, b: 15, c: 120, sumAB: 25, sumABC: 145}
// » Map `b`: 15
// Result: 145
// ---------------------------------------
// <<<< [SOURCES_BEGIN] >>>>
// <<<< NAMESPACE="" >>>>
// <<<< CODE_UNIT_START="/test" >>>>
// class Foo {
//
//   int main(List<Object> args) {
//     var title = args[0];
//     var a = args[1];
//     var b = args[2] ~/ 2;
//     var c = args[3] * 3;
//     if (c > 120) {
//         c = 120;
//     }
//
//     var str = 'variables> a: $a ; b: $b ; c: $c';
//     var sumAB = a + b;
//     var sumABC = a + b + c;
//     print(str);
//     print(title);
//     print(sumAB);
//     print(sumABC);
//     var map = <String,int>{'a': a, 'b': b, 'c': c, 'sumAB': sumAB, 'sumABC': sumABC};
//     print('Map: $map');
//     print('Map `b`: ${map['b']}');
//     return map['sumABC'];
//   }
//
// }
// <<<< CODE_UNIT_END="/test" >>>>
// <<<< [SOURCES_END] >>>>
//
// ---------------------------------------
// <<<< [SOURCES_BEGIN] >>>>
// <<<< NAMESPACE="" >>>>
// <<<< CODE_UNIT_START="/test" >>>>
// class Foo {
//
//   int main(Object[] args) {
//     var title = args[0];
//     var a = args[1];
//     var b = args[2] / 2;
//     var c = args[3] * 3;
//     if (c > 120) {
//         c = 120;
//     }
//
//     var str = "variables> a: " + a + " ; b: " + b + " ; c: " + c;
//     var sumAB = a + b;
//     var sumABC = a + b + c;
//     print(str);
//     print(title);
//     print(sumAB);
//     print(sumABC);
//     var map = new HashMap<String,int>(){{
//       put("a", a);
//       put("b", b);
//       put("c", c);
//       put("sumAB", sumAB);
//       put("sumABC", sumABC);
//     }};
//     print("Map: " + map);
//     print("Map `b`: " + String.valueOf( map["b"] ));
//     return map["sumABC"];
//   }
//
// }
// <<<< CODE_UNIT_END="/test" >>>>
// <<<< [SOURCES_END] >>>>
//
