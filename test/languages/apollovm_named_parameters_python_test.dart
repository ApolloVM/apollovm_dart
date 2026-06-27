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
  group('Python keyword arguments', () {
    test('called by keyword in reverse order (order-independent)', () async {
      var src = '''
def sub(a, b):
    return a - b

def call_forward():
    return sub(a=10, b=3)

def call_reversed():
    return sub(b=3, a=10)
''';

      expect(await runFunction(src, 'call_forward'), equals(7));
      // Keyword arguments bind by name regardless of call-site order.
      expect(await runFunction(src, 'call_reversed'), equals(7));
    });

    test('mixed positional + keyword arguments', () async {
      var src = '''
def compute(base, factor, offset):
    return base * factor + offset

def run():
    return compute(5, offset=1, factor=3)
''';

      expect(await runFunction(src, 'run'), equals(16));
    });

    test(
      '`==` inside a positional argument is not a keyword separator',
      () async {
        var src = '''
def is_equal(a, b):
    return a == b

def run_true():
    return is_equal(1 == 1, True)
''';

        // `1 == 1` is a single positional equality expression (True), compared to
        // the positional `True` -> True. If `==` were consumed as a keyword
        // separator the call would not have two positional args.
        expect(await runFunction(src, 'run_true'), equals(true));
      },
    );

    group('round-trip code generation', () {
      test('regenerates keyword call as `name=value`', () async {
        var src = '''
def sub(a, b):
    return a - b

def run():
    return sub(b=10, a=3)
''';

        var regen = await regenPython(src);

        // Keyword argument syntax is preserved at the call site as `name=value`.
        expect(regen, contains('sub(b=10, a=3)'));

        // The regenerated source re-parses and runs to the same result.
        expect(await runFunction(regen, 'run'), equals(-7));
      });
    });
  });
}
