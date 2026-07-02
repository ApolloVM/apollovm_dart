@TestOn('vm')
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

void main() {
  group('Cross-module execution', () {
    test('Dart: import class + function from other modules and run', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(
        SourceCodeUnit('dart', '''
class User {
  String name;
  User(this.name);
  String greet() { return 'Hi ' + name; }
}
''', id: 'user.dart'),
      );
      await vm.loadCodeUnit(
        SourceCodeUnit(
          'dart',
          'String shout(String s) { return s.toUpperCase(); }',
          id: 'helpers.dart',
        ),
      );
      await vm.loadCodeUnit(
        SourceCodeUnit('dart', '''
import 'user.dart' show User;
import 'helpers.dart';

String run() {
  var u = User('bob');
  return shout(u.greet());
}
''', id: 'main.dart'),
      );

      expect(vm.resolve(language: 'dart'), isEmpty);

      var runner = vm.createRunner('dart')!;
      var output = <Object?>[];
      runner.externalPrintFunction = output.add;

      var r = await runner.executeFunction('', 'run', positionalParameters: []);
      expect(r.getValueNoContext(), equals('HI BOB'));
    });

    test('Dart: whole-module prefix alias executes', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(
        SourceCodeUnit(
          'dart',
          'int square(int x) { return x * x; }',
          id: 'math_utils.dart',
        ),
      );
      await vm.loadCodeUnit(
        SourceCodeUnit('dart', '''
import 'math_utils.dart' as mu;
int run() { return mu.square(7); }
''', id: 'main.dart'),
      );

      expect(vm.resolve(language: 'dart'), isEmpty);

      var runner = vm.createRunner('dart')!;
      var r = await runner.executeFunction('', 'run', positionalParameters: []);
      expect(r.getValueNoContext(), equals(49));
    });

    test('TypeScript: named import resolves and runs', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(
        SourceCodeUnit('typescript', '''
class User {
  name: string;
  constructor(name: string) { this.name = name; }
  greet(): string { return 'Hi ' + this.name; }
}
''', id: 'user.ts'),
      );
      await vm.loadCodeUnit(
        SourceCodeUnit('typescript', '''
import { User } from './user';
function run(): string {
  let u = new User('bob');
  return u.greet();
}
''', id: 'main.ts'),
      );

      expect(vm.resolve(language: 'typescript'), isEmpty);

      var runner = vm.createRunner('typescript')!;
      var r = await runner.executeFunction('', 'run', positionalParameters: []);
      expect(r.getValueNoContext(), equals('Hi bob'));
    });

    test('Python: from-import with alias resolves and runs', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(
        SourceCodeUnit(
          'python',
          'def add(a, b):\n    return a + b\n',
          id: 'helpers.py',
        ),
      );
      await vm.loadCodeUnit(
        SourceCodeUnit(
          'python',
          'from helpers import add as plus\n\ndef run():\n    return plus(2, 3)\n',
          id: 'main.py',
        ),
      );

      expect(vm.resolve(language: 'python'), isEmpty);

      var runner = vm.createRunner('python')!;
      var r = await runner.executeFunction('', 'run', positionalParameters: []);
      expect(r.getValueNoContext(), equals(5));
    });
  });
}
