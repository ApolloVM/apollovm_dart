import 'package:apollovm/src/languages/dart/dart_parser.dart';
import 'package:test/test.dart';

void main() {
  group('Dart', () {
    test('Basic main()', () async {
      var parser = ApolloParserDart();

      var root = await parser.parse(r'''
          void main(List<String> args) {
            var s = args[0] ;
            print(s);
          }
      ''');

      expect(root, isNotNull);

      print('<<<<<<<<<<<<<<<<<<<< REGENERATE PARSED DART CODE:');
      print(root!.generateCode());
      print('>>>>>>>>>>>>>>>>>>>>');

      root.execute('main', [
        ['foo!', 'abc']
      ]);
    });
  });
}
