@TestOn('vm')
@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// The reported case: a nullable parameter used in arithmetic. It loads and runs
/// today, failing only once the null actually flows — after `print(a)` and
/// `print(b)` have already produced output.
const _nullSafetyError = r'''
class Foo {

  static void main(int a, int? b) {
     print(a);
     print(b);

     var c = a + b;
     print(c);
  }

}
''';

Future<bool> _load(
  String src, {
  required bool checks,
  String language = 'dart',
}) {
  var vm = ApolloVM(nullSafetyChecks: checks);
  return vm.loadCodeUnit(SourceCodeUnit(language, src, id: 't'));
}

void main() {
  group('nullSafetyChecks: false (default)', () {
    test('is the default', () {
      expect(ApolloVM().nullSafetyChecks, isFalse);
    });

    test('a null-safety error still loads', () async {
      expect(await _load(_nullSafetyError, checks: false), isTrue);
    });

    test('and still fails at runtime, after earlier statements ran', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(SourceCodeUnit('dart', _nullSafetyError, id: 't'));

      var printed = <Object?>[];
      var runner = vm.createRunner('dart')!
        ..externalPrintFunction = printed.add;

      await expectLater(
        runner.executeClassMethod(
          '',
          'Foo',
          'main',
          positionalParameters: [5, null],
        ),
        throwsA(isA<ApolloVMNullPointerException>()),
      );
      // The failure lands mid-run: the first two prints already happened.
      expect(printed, [5, null]);
    });
  });

  group('nullSafetyChecks: true', () {
    test('a null-safety error fails the load', () async {
      await expectLater(
        _load(_nullSafetyError, checks: true),
        throwsA(isA<NullSafetyError>()),
      );
    });

    test('the error carries the findings', () async {
      try {
        await _load(_nullSafetyError, checks: true);
        fail('expected a NullSafetyError');
      } on NullSafetyError catch (e) {
        expect(e.findings, isNotEmpty);
        expect(
          e.findings.map((f) => f.code),
          contains('unchecked-nullable-operand'),
        );
        expect(
          e.findings.every((f) => f.severity == NullSafetySeverity.error),
          isTrue,
        );
        expect(e.toString(), contains('Null Safety'));
      }
    });

    test('nothing runs: the failure precedes execution', () async {
      var vm = ApolloVM(nullSafetyChecks: true);
      var printed = <Object?>[];

      await expectLater(
        vm.loadCodeUnit(SourceCodeUnit('dart', _nullSafetyError, id: 't')),
        throwsA(isA<NullSafetyError>()),
      );

      // The unit was never registered, so there is nothing to run.
      expect(printed, isEmpty);
      expect(vm.createRunner('dart'), isNotNull);
    });

    test('a clean program loads', () async {
      expect(
        await _load(
          'class Foo { static int run(int? a, int b) { return (a ?? 0) + b; } }',
          checks: true,
        ),
        isTrue,
      );
    });

    test('a warning-severity finding does not block', () async {
      // `null!` always throws, but it is a *warning* — only errors are fatal.
      var vm = ApolloVM(nullSafetyChecks: true);
      var findings = NullSafetyAnalyzer().analyze(
        (await ApolloVM()
                .getParser<String>('dart')!
                .parse(
                  SourceCodeUnit(
                    'dart',
                    'void run() { var x = null!; }',
                    id: 'w',
                  ),
                ))
            .root!,
      );
      expect(
        findings.map((f) => f.severity),
        contains(NullSafetySeverity.warning),
        reason: 'this source must produce a warning for the test to be valid',
      );
      expect(
        findings.any((f) => f.severity == NullSafetySeverity.error),
        isFalse,
      );

      expect(
        await vm.loadCodeUnit(
          SourceCodeUnit('dart', 'void run() { var x = null!; }', id: 'w'),
        ),
        isTrue,
      );
    });

    test('an error inside a class method is caught', () async {
      await expectLater(
        _load('class Foo { void run() { int x = null; } }', checks: true),
        throwsA(isA<NullSafetyError>()),
      );
    });

    test('a non-Dart source loads (no false positives)', () async {
      // Only the Dart grammar parses `?`, so other languages have no nullable
      // types and must never trip the check.
      expect(
        await _load(
          'class Foo { static int run(int a, int b) { return a + b; } }',
          checks: true,
          language: 'java11',
        ),
        isTrue,
      );
    });

    test('a syntax error still reports as a SyntaxError', () async {
      await expectLater(
        _load('class Foo { void run(', checks: true),
        throwsA(isA<SyntaxError>()),
      );
    });
  });
}
