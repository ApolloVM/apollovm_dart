import 'package:apollovm/apollovm.dart';

void main() async {
  var vm = ApolloVM();

  // Apollo is Dart with a few divergences: control-flow parentheses are
  // optional, `async` is a leading modifier, statement semicolons are optional
  // and primitive types are capitalized (`Int`, `Double`, `Bool`).
  var codeUnit = SourceCodeUnit('apollo', r'''
      class Greeter {
        String name

        Greeter(String name) {
          this.name = name
        }

        greet(Int count) {
          if count <= 0 {
            print("Nothing to greet")
            return
          }

          var i = 0
          while i < count {
            print("Hello, $name! (${i + 1})")
            i = i + 1
          }
        }

        static run() {
          var greeter = Greeter("Apollo")
          greeter.greet(2)
        }
      }
      ''', id: 'test');

  var loadOK = await vm.loadCodeUnit(codeUnit);

  if (!loadOK) {
    print("Can't load source!");
    return;
  }

  print('---------------------------------------');

  var apolloRunner = vm.createRunner('apollo')!;

  // Map the `print` function in the VM:
  apolloRunner.externalPrintFunction = (o) => print("» $o");

  await apolloRunner.executeClassMethod(
    '',
    'Greeter',
    'run',
    positionalParameters: const [],
    classInstanceFields: const {},
  );

  print('---------------------------------------');

  // Regenerate code in Dart (capitalized types become lowercase; a leading
  // `async` would move after the parameter list):
  var codeStorageDart = vm.generateAllCodeIn('dart');
  var allSourcesDart = await codeStorageDart.writeAllSources();
  print(allSourcesDart);
}

/////////////
// OUTPUT: //
/////////////
// ---------------------------------------
// » Hello, Apollo! (1)
// » Hello, Apollo! (2)
// ---------------------------------------
// <<<< [SOURCES_BEGIN] >>>>
// <<<< NAMESPACE="" >>>>
// <<<< CODE_UNIT_START="/test" >>>>
// class Greeter {
//
//   String name;
//
//   Greeter(String name) {
//     this.name = name;
//   }
//
//   dynamic greet(int count) {
//     if (count <= 0) {
//         print('Nothing to greet');
//         return;
//     }
//
//     var i = 0;
//     while( i < count ) {
//       print('Hello, $name! (${i + 1})');
//       i = i + 1;
//     }
//   }
//
//   static dynamic run() {
//     var greeter = Greeter('Apollo');
//     greeter.greet(2);
//   }
//
// }
// <<<< CODE_UNIT_END="/test" >>>>
// <<<< [SOURCES_END] >>>>
//
