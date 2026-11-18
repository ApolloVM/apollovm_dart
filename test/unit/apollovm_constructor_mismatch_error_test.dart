@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Loads [src] as Dart and runs `main()`, returning the error it throws.
Future<Object> _runMainError(String src) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', src, id: 'test'));
  expect(ok, isTrue, reason: "Can't load the source");
  try {
    await vm.createRunner('dart')!.executeFunction('', 'main');
  } catch (e) {
    return e;
  }
  fail('main() did not throw');
}

void main() {
  group('A failed constructor call', () {
    test('names a field type that does not exist', () async {
      // `Sring` is a typo for `String`: the initializing formal takes the
      // field's type, so no argument matches it. Dart rejects this with
      // "Type 'Sring' not found".
      var error = await _runMainError(r'''
class User {
  final Sring email;

  User(this.email);

  String toString() => "User[$email]";
}

void main() {
  var u1 = User("foo@mail.com");
  print(u1);
}
''');

      expect(error, isA<ApolloVMRuntimeError>());
      var message = error.toString();
      expect(message, contains("Type 'Sring' not found"));
      expect(message, contains('`User(Sring email)`'));
      expect(message, contains('the field `User.email`'));
      expect(message, isNot(contains("Can't find function")));
    });

    test('names an unknown type of a plain parameter', () async {
      var error = await _runMainError('''
class Box {
  Box(Widget w);
}

void main() {
  Box(1);
}
''');

      var message = error.toString();
      expect(message, contains("Type 'Widget' not found"));
      expect(message, isNot(contains('the field')));
    });

    test('reports the declared constructor when the types exist', () async {
      var error = await _runMainError('''
class P {
  int x;
  P(this.x);
}

void main() {
  var p = P("a");
  print(p.x);
}
''');

      expect(
        error.toString(),
        contains(
          'No constructor of `P` matches the arguments '
          '{positionalTypes: [String]}: declared `P(int x)`.',
        ),
      );
    });

    test('a user class used as a parameter type is a known type', () async {
      var error = await _runMainError('''
class A {}

class B {
  B(A a);
}

void main() {
  B(1);
}
''');

      var message = error.toString();
      expect(message, contains('No constructor of `B` matches'));
      expect(message, isNot(contains('not found')));
    });
  });

  test('a missing function that is not a class keeps its message', () async {
    var error = await _runMainError('''
void main() {
  missing(1);
}
''');

    expect(error.toString(), contains('Can\'t find function "missing"'));
  });
}
