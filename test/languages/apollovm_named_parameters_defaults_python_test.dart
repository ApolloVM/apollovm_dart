@TestOn('vm')
@Tags(['python'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Loads a single Python [source] and runs the top-level [function], returning
/// the resolved native return value.
Future<Object?> runFunction(
  String source,
  String function, {
  List positionalParameters = const [],
  Map? namedParameters,
}) async {
  var vm = ApolloVM();
  var loadOK = await vm.loadCodeUnit(
    SourceCodeUnit('python', source, id: 'test'),
  );
  expect(loadOK, isTrue, reason: "Can't load Python source!");

  var runner = vm.createRunner('python')!;

  var astValue = await runner.executeFunction(
    '',
    function,
    positionalParameters: positionalParameters,
    namedParameters: namedParameters,
  );

  return astValue.getValueNoContext();
}

/// Translates a loaded Python [source] back into Python, returning the single
/// generated source unit (raw, loadable code — not the multi-source wrapper).
Future<String> regenPython(String source) async {
  var vm = ApolloVM();
  await vm.loadCodeUnit(SourceCodeUnit('python', source, id: 'test'));

  var codeStorage = vm.generateAllCodeIn('python');

  var buffer = StringBuffer();
  for (var ns in await codeStorage.getNamespaces()) {
    for (var id in await codeStorage.getNamespaceCodeUnitsIDs(ns)) {
      buffer.write(await codeStorage.getNamespaceCodeUnit(ns, id));
    }
  }
  return buffer.toString();
}

void main() {
  group('Python parameter default values', () {
    test('default used when the argument is omitted', () async {
      var src = '''
def greet(a=7):
    return a

def use_default():
    return greet()

def positional():
    return greet(10)

def keyword():
    return greet(a=10)
''';

      // Omitted -> the parameter default (7) is evaluated.
      expect(await runFunction(src, 'use_default'), equals(7));
      // Provided positionally or by keyword -> the supplied value (10).
      expect(await runFunction(src, 'positional'), equals(10));
      expect(await runFunction(src, 'keyword'), equals(10));
    });

    test('default value can be an expression', () async {
      var src = '''
def f(a=2 + 3):
    return a

def run():
    return f()
''';

      expect(await runFunction(src, 'run'), equals(5));
    });

    group('round-trip code generation', () {
      test('default survives regeneration with no spaces around `=`', () async {
        var src = '''
def greet(a=7):
    return a

def use_default():
    return greet()

def given():
    return greet(10)
''';

        var regen = await regenPython(src);

        // The default round-trips and is emitted with no spaces (`a=7`).
        expect(regen, contains('def greet(a=7)'));

        // The regenerated source re-parses and runs to the same results.
        expect(await runFunction(regen, 'use_default'), equals(7));
        expect(await runFunction(regen, 'given'), equals(10));
      });
    });
  });
}
