@TestOn('vm')
@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

Future<ApolloRunner> _runner(String source) async {
  var vm = ApolloVM();
  expect(
    await vm.loadCodeUnit(SourceCodeUnit('dart', source, id: 'test')),
    isTrue,
  );
  return vm.createRunner('dart')!;
}

void main() {
  group('tryExecuteFunction', () {
    test('matches a function by its direct positional parameter', () async {
      var runner = await _runner('int run(int a) { return a + 1; }');
      var r = await runner.tryExecuteFunction('', 'run', [41]);
      expect(r?.getValueNoContext(), equals(42));
    });

    test('falls back to wrapping the args in a single List', () async {
      var runner = await _runner('int run(List a) { return a[0]; }');
      // No `run(int)` exists, so the [args]-as-one-List fallback is used.
      var r = await runner.tryExecuteFunction('', 'run', [7]);
      expect(r?.getValueNoContext(), equals(7));
    });

    test('returns null when no matching function exists', () async {
      var runner = await _runner('int run() { return 1; }');
      var r = await runner.tryExecuteFunction('', 'nope', [1, 2]);
      expect(r, isNull);
    });

    test('defaults missing positional parameters to empty', () async {
      var runner = await _runner('int run() { return 5; }');
      var r = await runner.tryExecuteFunction('', 'run');
      expect(r?.getValueNoContext(), equals(5));
    });
  });

  group('tryExecuteClassFunction', () {
    test('matches a class method by direct positional parameter', () async {
      var runner = await _runner(
        'class C { static int run(int a) { return a * 2; } }',
      );
      var r = await runner.tryExecuteClassFunction('', 'C', 'run', [21]);
      expect(r?.getValueNoContext(), equals(42));
    });

    test('falls back to wrapping args in a List for a List method', () async {
      var runner = await _runner(
        'class C { static int run(List a) { return a[1]; } }',
      );
      var r = await runner.tryExecuteClassFunction('', 'C', 'run', [10, 20]);
      expect(r?.getValueNoContext(), equals(20));
    });

    test('returns null for an unknown method', () async {
      var runner = await _runner('class C { static int run() { return 1; } }');
      var r = await runner.tryExecuteClassFunction('', 'C', 'missing', [1]);
      expect(r, isNull);
    });
  });

  group('resolveType', () {
    test(
      'resolves a user class type by name for the runner language',
      () async {
        var runner = await _runner('class Widget { int x = 0; }');
        var t = await runner.resolveType('Widget', language: 'dart');
        expect(t, isNotNull);
        expect(t!.name, equals('Widget'));
      },
    );

    test('resolves a core type', () async {
      var runner = await _runner('class C {}');
      var t = await runner.resolveType('int', language: 'dart');
      expect(t, isNotNull);
    });
  });
}
