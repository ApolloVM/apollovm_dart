@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// A Dart class whose constructor initializes its field with an initializing
/// formal (`User(this.email)`), and whose `toString` reads that field without
/// a receiver.
const _userSource = r'''
class User {
  final String email;

  User(this.email);

  String toString() => "User[$email]";
}

void main(List<Object> args) {
  var u1 = User("foo@mail.com");

  print(u1);
}
''';

Future<ApolloVM> _load(String language, String src) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit(language, src, id: 'test'));
  expect(ok, isTrue, reason: "Can't load $language source");
  return vm;
}

/// The single code unit [vm] generates in [language].
Future<String> _generate(ApolloVM vm, String language) async {
  var storage = vm.generateAllCodeIn(language);
  await storage.writeAllSources();
  for (var ns in await storage.getNamespaces()) {
    for (var id in await storage.getNamespaceCodeUnitsIDs(ns)) {
      return (await storage.getNamespaceCodeUnit(ns, id))!;
    }
  }
  throw StateError('no generated source');
}

/// What `main([])` prints when [src] (in [language]) runs in ApolloVM.
Future<List<Object?>> _runMain(String language, String src) async {
  var vm = await _load(language, src);
  var printed = <Object?>[];
  var runner = vm.createRunner(language)!;
  runner.externalPrintFunction = (o) => printed.add(o);
  await runner.executeFunction('', 'main', positionalParameters: [<Object>[]]);
  return printed;
}

void main() {
  group('Initializing formals (`User(this.email)`)', () {
    test('the Dart source runs', () async {
      expect(
        await _runMain('dart', _userSource),
        equals(['User[foo@mail.com]']),
      );
    });

    // Each target must assign the field in the constructor and read it back
    // with the receiver its language requires; the generated source is then
    // parsed and run again, and must print what the Dart source prints.
    const expectations = <String, List<String>>{
      'dart': ['User(this.email);', r"return 'User[$email]';"],
      'kotlin': ['this.email = email', r'return "User[$email]"'],
      'javascript': ['this.email = email;', r'return `User[${this.email}]`;'],
      'typescript': ['this.email = email;', r'return `User[${this.email}]`;'],
      'python': ['self.email = email', "return f'User[{self.email}]'"],
      'go': ['o.email = email', 'return "User[" + o.email + "]"'],
    };

    for (var MapEntry(key: language, value: snippets) in expectations.entries) {
      test('translates to $language and runs there', () async {
        var vm = await _load('dart', _userSource);
        var code = await _generate(vm, language);
        for (var snippet in snippets) {
          expect(code, contains(snippet));
        }
        expect(await _runMain(language, code), equals(['User[foo@mail.com]']));
      });
    }

    test('a private named formal assigns the private field', () async {
      var vm = await _load('dart', r'''
class Account {
  final String _id;
  Account({required this._id});
  String describe() => '#$_id';
}
''');
      expect(await _generate(vm, 'javascript'), contains('this._id = id;'));
      expect(await _generate(vm, 'python'), contains('self._id = id'));
    });

    test('the formals are assigned before the constructor body', () async {
      var vm = await _load('dart', r'''
class Point {
  int x;
  int sum = 0;
  Point(this.x) {
    sum = x + 1;
  }
}
''');
      var js = await _generate(vm, 'javascript');
      // `x` in the body is the parameter, so it stays unqualified.
      expect(js, contains('    this.x = x;\n    this.sum = x + 1;\n'));
    });
  });

  group('Implicit field reads in a receiver-explicit target', () {
    const counterSource = r'''
class Counter {
  int count = 0;
  String label;

  Counter(this.label);

  int hit() {
    count++;
    return count;
  }

  String rename(String label) => '$label was ${this.label}';

  String local() {
    var label = 'mine';
    return 'local $label';
  }
}
''';

    test('an increment of a field is qualified', () async {
      var vm = await _load('dart', counterSource);
      expect(await _generate(vm, 'javascript'), contains('this.count++;'));
      expect(await _generate(vm, 'python'), contains('self.count += 1'));
      expect(await _generate(vm, 'go'), contains('o.count++'));
    });

    test('a parameter that shadows the field is left alone', () async {
      var vm = await _load('dart', counterSource);
      expect(
        await _generate(vm, 'javascript'),
        contains(r'return `${label} was ${this.label}`;'),
      );
      expect(
        await _generate(vm, 'python'),
        contains("return f'{label} was {self.label}'"),
      );
    });

    // A local is not a parameter: Go and Lua used to check only parameters,
    // and wrote `o.label` / `self.label` for the local here.
    const localRead = <String, String>{
      'javascript': r'return `local ${label}`;',
      'python': "return f'local {label}'",
      'go': 'return "local " + label',
      'lua': 'return "local " .. label',
    };

    for (var MapEntry(key: language, value: expected) in localRead.entries) {
      test(
        'a local that shadows the field is left alone ($language)',
        () async {
          var vm = await _load('dart', counterSource);
          expect(await _generate(vm, language), contains(expected));
        },
      );
    }

    test('an interpolated field is qualified in Lua', () async {
      var vm = await _load('dart', _userSource);
      expect(
        await _generate(vm, 'lua'),
        contains('return "User[" .. self.email .. "]"'),
      );
    });
  });
}
