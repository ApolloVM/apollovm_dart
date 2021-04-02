import 'package:apollovm/apollovm.dart';

void main() async {
  var parser = ApolloParserDart();

  var root = await parser.parse(r'''
          void main(List<String> args) {
            var s = args[0] ;
            print(s);
          }
      ''');

  if (root == null) {
    throw StateError('Error parsing Dart code!');
  }

  print('<<<<<<<<<<<<<<<<<<<< REGENERATE PARSED DART CODE:');
  print(root.generateCode());
  print('>>>>>>>>>>>>>>>>>>>>');

  // Execute parsed code, calling function `main`:
  root.execute('main', [
    ['foo!', 'abc']
  ]);
}
