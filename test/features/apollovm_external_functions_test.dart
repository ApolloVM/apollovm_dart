@TestOn('vm')
@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Loads [source], wires external functions via [wire], then runs top-level
/// [func] returning its resolved value plus captured `print` output.
Future<({Object? value, List output})> _run(
  String source,
  String func, {
  void Function(ApolloRunner runner)? wire,
  List args = const [],
}) async {
  var vm = ApolloVM();
  expect(
    await vm.loadCodeUnit(SourceCodeUnit('dart', source, id: 'test')),
    isTrue,
  );
  var runner = vm.createRunner('dart')!;
  var output = [];
  runner.externalPrintFunction = output.add;
  wire?.call(runner);
  var r = await runner.executeFunction('', func, positionalParameters: args);
  return (value: await r.getValueNoContext(), output: output);
}

void main() {
  group('External function mapping', () {
    test('0-parameter external function is callable from VM code', () async {
      var r = await _run(
        'int run() { return magic(); }',
        'run',
        wire: (runner) =>
            runner.externalFunctionMapper!.mapExternalFunction0<dynamic, int>(
              ASTTypeInt.instance,
              'magic',
              () => 42,
            ),
      );
      expect(r.value, equals(42));
    });

    test('1-parameter external function receives its argument', () async {
      var r = await _run(
        'int run() { return twice(21); }',
        'run',
        wire: (runner) =>
            runner.externalFunctionMapper!.mapExternalFunction1<dynamic, int>(
              ASTTypeInt.instance,
              'twice',
              ASTTypeDynamic.instance,
              'n',
              (n) => (n as int) * 2,
            ),
      );
      expect(r.value, equals(42));
    });

    test('2-parameter external function combines its arguments', () async {
      var r = await _run(
        "String run() { return join('a', 'b'); }",
        'run',
        wire: (runner) => runner.externalFunctionMapper!
            .mapExternalFunction2<dynamic, dynamic, String>(
              ASTTypeString.instance,
              'join',
              ASTTypeDynamic.instance,
              'a',
              ASTTypeDynamic.instance,
              'b',
              (a, b) => '$a$b',
            ),
      );
      expect(r.value, equals('ab'));
    });

    test('external function coexists with a print side effect', () async {
      var r = await _run(
        'int run() { var v = inc(9); print(v); return v; }',
        'run',
        wire: (runner) =>
            runner.externalFunctionMapper!.mapExternalFunction1<dynamic, int>(
              ASTTypeInt.instance,
              'inc',
              ASTTypeDynamic.instance,
              'n',
              (n) => (n as int) + 1,
            ),
      );
      expect(r.value, equals(10));
      expect(r.output, equals([10]));
    });

    test('3- and 4-parameter mappers register without error', () async {
      // These overloads take a 2-arg callback in the current API; we exercise
      // the registration path (parameter-declaration construction) directly.
      var mapper = ApolloExternalFunctionMapper();
      mapper.mapExternalFunction3<int, int, int, int>(
        ASTTypeInt.instance,
        'f3',
        ASTTypeInt.instance,
        'a',
        ASTTypeInt.instance,
        'b',
        ASTTypeInt.instance,
        'c',
        (a, b) => a + b,
      );
      mapper.mapExternalFunction4<int, int, int, int, int>(
        ASTTypeInt.instance,
        'f4',
        ASTTypeInt.instance,
        'a',
        ASTTypeInt.instance,
        'b',
        ASTTypeInt.instance,
        'c',
        ASTTypeInt.instance,
        'd',
        (a, b) => a + b,
      );
      // Registered functions are resolvable by name via the mapper.
      var ctx = VMScopeContext(ASTBlock(null));
      expect(mapper.getMappedFunction(ctx, 'f3'), isNotNull);
      expect(mapper.getMappedFunction(ctx, 'f4'), isNotNull);
    });
  });

  group('External getter mapping', () {
    test('addExternalGetter then getMappedGetter resolves', () {
      var mapper = ApolloExternalGetterMapper();
      mapper.mapExternalGetter<dynamic, int>(
        ASTTypeInt.instance,
        'answer',
        () => 42,
      );
      var ctx = VMScopeContext(ASTBlock(null));
      expect(mapper.getMappedGetter<int>(ctx, 'answer'), isNotNull);
      expect(mapper.getMappedGetter<int>(ctx, 'missing'), isNull);
    });
  });
}
