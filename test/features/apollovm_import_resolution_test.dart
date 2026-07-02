@TestOn('vm')
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Loads [sources] (`id` → code) into a fresh Dart [ApolloVM] and resolves.
Future<ApolloVM> _loadDart(Map<String, String> sources) async {
  var vm = ApolloVM();
  for (var e in sources.entries) {
    await vm.loadCodeUnit(SourceCodeUnit('dart', e.value, id: e.key));
  }
  return vm;
}

void main() {
  group('Module resolution', () {
    test('plain import exposes exported class and function', () async {
      var vm = await _loadDart({
        'user.dart': '''
class User {
  String name;
  User(this.name);
  String greet() { return 'Hi ' + name; }
}
''',
        'helpers.dart': 'String shout(String s) { return s.toUpperCase(); }',
        'main.dart': '''
import 'user.dart';
import 'helpers.dart';
String run() {
  var u = User('bob');
  return shout(u.greet());
}
''',
      });

      var diagnostics = vm.resolve(language: 'dart');
      expect(diagnostics, isEmpty);

      var scope = vm.resolutionEngine.importScopeFor('main.dart')!;
      expect(scope.resolveClass('User'), isNotNull);
      expect(scope.resolveFunctionSet('shout'), isNotNull);

      var runner = vm.createRunner('dart')!;
      var r = await runner.executeFunction('', 'run', positionalParameters: []);
      expect(r.getValueNoContext(), equals('HI BOB'));
    });

    test('show restricts imported symbols', () async {
      var vm = await _loadDart({
        'lib.dart': '''
class A { A(); }
class B { B(); }
''',
        'main.dart': "import 'lib.dart' show A;\n",
      });

      vm.resolve(language: 'dart');
      var scope = vm.resolutionEngine.importScopeFor('main.dart')!;
      expect(scope.resolveClass('A'), isNotNull);
      expect(scope.resolveClass('B'), isNull);
    });

    test('hide excludes imported symbols', () async {
      var vm = await _loadDart({
        'lib.dart': '''
class A { A(); }
class B { B(); }
''',
        'main.dart': "import 'lib.dart' hide B;\n",
      });

      vm.resolve(language: 'dart');
      var scope = vm.resolutionEngine.importScopeFor('main.dart')!;
      expect(scope.resolveClass('A'), isNotNull);
      expect(scope.resolveClass('B'), isNull);
    });

    test('whole-module prefix alias binds under prefix', () async {
      var vm = await _loadDart({
        'math_utils.dart': 'int square(int x) { return x * x; }',
        'main.dart': '''
import 'math_utils.dart' as mu;
int run() { return mu.square(6); }
''',
      });

      vm.resolve(language: 'dart');
      var scope = vm.resolutionEngine.importScopeFor('main.dart')!;
      expect(scope.hasPrefix('mu'), isTrue);
      expect(scope.resolve('square'), isNull, reason: 'not unprefixed');
      expect(scope.resolvePrefixedFunctionSet('mu', 'square'), isNotNull);

      var runner = vm.createRunner('dart')!;
      var r = await runner.executeFunction('', 'run', positionalParameters: []);
      expect(r.getValueNoContext(), equals(36));
    });

    test('re-export (barrel) forwards symbols', () async {
      var vm = await _loadDart({
        'user.dart': 'class User { User(); String tag() { return \'u\'; } }',
        'barrel.dart': "export 'user.dart';\n",
        'main.dart': "import 'barrel.dart';\n",
      });

      vm.resolve(language: 'dart');
      var scope = vm.resolutionEngine.importScopeFor('main.dart')!;
      expect(scope.resolveClass('User'), isNotNull);
    });
  });
}
