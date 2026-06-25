@TestOn('vm')
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Loads [source] in [language] and runs the top-level function [function],
/// returning the resolved native return value and the collected `print` output.
Future<({Object? value, List output})> _run(
  String language,
  String source,
  String function, {
  List positionalParameters = const [],
}) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit(language, source, id: 'test'));
  expect(ok, isTrue, reason: "Can't load $language source!");

  var runner = vm.createRunner(language)!;
  var output = [];
  runner.externalPrintFunction = (o) => output.add(o);

  var astValue = await runner.executeFunction(
    '',
    function,
    positionalParameters: positionalParameters,
  );

  return (value: astValue.getValueNoContext(), output: output);
}

/// Translates a loaded Dart [source] into [language], returning the generated
/// source (single concatenated unit).
Future<String> _translateDart(String source, String language) async {
  var vm = ApolloVM();
  await vm.loadCodeUnit(SourceCodeUnit('dart', source, id: 'test'));
  var codeStorage = vm.generateAllCodeIn(language);
  var buffer = StringBuffer();
  for (var ns in await codeStorage.getNamespaces()) {
    for (var id in await codeStorage.getNamespaceCodeUnitsIDs(ns)) {
      buffer.write(await codeStorage.getNamespaceCodeUnit(ns, id));
    }
  }
  return buffer.toString();
}

void main() {
  group('Dart try/catch/finally runtime', () {
    test('catch a user-thrown String', () async {
      var r = await _run('dart', '''
String main() {
  try {
    throw 'boom';
  } catch (e) {
    return 'caught: \$e';
  }
}
''', 'main');
      expect(r.value, equals('caught: boom'));
    });

    test('catch a user-thrown int value', () async {
      var r = await _run('dart', '''
int main() {
  try {
    throw 42;
  } catch (e) {
    return e;
  }
}
''', 'main');
      expect(r.value, equals(42));
    });

    test('finally runs on normal completion', () async {
      var r = await _run('dart', '''
void main() {
  try {
    print('try');
  } finally {
    print('finally');
  }
}
''', 'main');
      expect(r.output, equals(['try', 'finally']));
    });

    test('finally runs after a caught throw', () async {
      var r = await _run('dart', '''
void main() {
  try {
    print('try');
    throw 'x';
  } catch (e) {
    print('catch');
  } finally {
    print('finally');
  }
}
''', 'main');
      expect(r.output, equals(['try', 'catch', 'finally']));
    });

    test('typed `on T catch` matches by type', () async {
      var r = await _run('dart', '''
String main() {
  try {
    throw 'boom';
  } on String catch (e) {
    return 'string: \$e';
  } catch (e) {
    return 'other: \$e';
  }
}
''', 'main');
      expect(r.value, equals('string: boom'));
    });

    test(
      'typed `on T catch` falls through to catch-all when type mismatches',
      () async {
        var r = await _run('dart', '''
String main() {
  try {
    throw 123;
  } on String catch (e) {
    return 'string: \$e';
  } catch (e) {
    return 'other: \$e';
  }
}
''', 'main');
        expect(r.value, equals('other: 123'));
      },
    );

    test('catches a built-in VM error (integer division by zero)', () async {
      var r = await _run('dart', '''
String main() {
  try {
    var x = 1 ~/ 0;
    return 'no error: \$x';
  } catch (e) {
    return 'caught vm error';
  }
}
''', 'main');
      expect(r.value, equals('caught vm error'));
    });

    test('return inside try still runs finally', () async {
      var r = await _run('dart', '''
int main() {
  try {
    return 1;
  } finally {
    print('finally');
  }
}
''', 'main');
      expect(r.value, equals(1));
      expect(r.output, equals(['finally']));
    });

    test('return inside finally overrides return inside try', () async {
      var r = await _run('dart', '''
int main() {
  try {
    return 1;
  } finally {
    return 2;
  }
}
''', 'main');
      expect(r.value, equals(2));
    });

    test('nested try/catch: inner rethrows, outer catches', () async {
      var r = await _run('dart', '''
String main() {
  try {
    try {
      throw 'inner';
    } on String catch (e) {
      throw 'wrapped: \$e';
    }
  } catch (e) {
    return 'outer: \$e';
  }
}
''', 'main');
      expect(r.value, equals('outer: wrapped: inner'));
    });

    test('throw from a called function is caught by the caller', () async {
      var r = await _run('dart', '''
void boom() {
  throw 'from boom';
}
String main() {
  try {
    boom();
    return 'unreachable';
  } catch (e) {
    return 'caught: \$e';
  }
}
''', 'main');
      expect(r.value, equals('caught: from boom'));
    });
  });

  group('Java try/catch/finally runtime', () {
    test('catch a typed user throw and run finally', () async {
      var vm = ApolloVM();
      var ok = await vm.loadCodeUnit(
        SourceCodeUnit('java11', '''
class Foo {
  static void run() {
    try {
      print("try");
      throw "boom";
    } catch (String e) {
      print("caught: " + e);
    } finally {
      print("finally");
    }
  }
}
''', id: 'test'),
      );
      expect(ok, isTrue);
      var runner = vm.createRunner('java11')!;
      var output = [];
      runner.externalPrintFunction = (o) => output.add(o);
      await runner.executeClassMethod('', 'Foo', 'run');
      expect(output, equals(['try', 'caught: boom', 'finally']));
    });
  });

  group('Kotlin try/catch/finally runtime', () {
    test('catch a typed user throw and run finally', () async {
      var r = await _run('kotlin', '''
fun main() {
  try {
    print("try")
    throw "boom"
  } catch (e: String) {
    print("caught: \$e")
  } finally {
    print("finally")
  }
}
''', 'main');
      expect(r.output, equals(['try', 'caught: boom', 'finally']));
    });
  });

  group('JavaScript / TypeScript try/catch/finally runtime', () {
    test('JS catches a user throw and runs finally', () async {
      var r = await _run('javascript', '''
function main() {
  try {
    print("try");
    throw "boom";
  } catch (e) {
    print("caught: " + e);
  } finally {
    print("finally");
  }
}
''', 'main');
      expect(r.output, equals(['try', 'caught: boom', 'finally']));
    });

    test('TS catches a user throw and runs finally', () async {
      var r = await _run('typescript', '''
function main(): void {
  try {
    print("try");
    throw "boom";
  } catch (e) {
    print("caught: " + e);
  } finally {
    print("finally");
  }
}
''', 'main');
      expect(r.output, equals(['try', 'caught: boom', 'finally']));
    });
  });

  group('Translation Dart -> *', () {
    var src = '''
class Foo {
  void run() {
    try {
      throw 'boom';
    } on String catch (e) {
      print(e);
    } finally {
      print('done');
    }
  }
}
''';

    test('-> Dart keeps `on T catch (e)` and `finally`', () async {
      var out = await _translateDart(src, 'dart');
      expect(out, contains("throw 'boom';"));
      expect(out, contains('on String catch (e)'));
      expect(out, contains('finally {'));
    });

    test('-> Java uses `catch (T e)`', () async {
      var out = await _translateDart(src, 'java11');
      expect(out, contains('catch (String e)'));
      expect(out, contains('finally {'));
    });

    test('-> Kotlin uses `catch (e: T)`', () async {
      var out = await _translateDart(src, 'kotlin');
      expect(out, contains('catch (e: String)'));
      expect(out, contains('finally {'));
    });

    test('-> JavaScript uses untyped `catch (e)`', () async {
      var out = await _translateDart(src, 'javascript');
      expect(out, contains('catch (e)'));
      expect(out, contains('finally {'));
    });

    test('-> TypeScript uses untyped `catch (e)`', () async {
      var out = await _translateDart(src, 'typescript');
      expect(out, contains('catch (e)'));
      expect(out, contains('finally {'));
    });

    test('untyped Dart catch -> Java `catch (Exception e)`', () async {
      var out = await _translateDart('''
class Foo {
  void run() {
    try {
      throw 'x';
    } catch (e) {
      print(e);
    }
  }
}
''', 'java11');
      expect(out, contains('catch (Exception e)'));
    });

    test('untyped Dart catch -> Kotlin `catch (e: Throwable)`', () async {
      var out = await _translateDart('''
class Foo {
  void run() {
    try {
      throw 'x';
    } catch (e) {
      print(e);
    }
  }
}
''', 'kotlin');
      expect(out, contains('catch (e: Throwable)'));
    });
  });
}
