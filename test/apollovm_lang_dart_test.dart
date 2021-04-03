import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

void main() {
  group('Dart', () {
    test('Basic main()', () async {
      var vm = ApolloVM();

      var codeUnit = CodeUnit(
          'dart',
          r'''
            void main(List<String> args) {
              var s = args[0] ;
              print(s);
            }
          ''',
          'test');

      var loadOK = await vm.loadCodeUnit(codeUnit);

      expect(loadOK, isTrue);

      var dartRunner = vm.getRunner('dart')!;
      dartRunner.executeFunction('', 'main', [
        ['foo!', 'abc']
      ]);

      print('---------------------------------------');
      // Regenerate code:
      var codeStorageDart = vm.generateAllCodeIn('dart');
      var allSourcesDart = codeStorageDart.writeAllSources().toString();
      print(allSourcesDart);
    });
  });
}
