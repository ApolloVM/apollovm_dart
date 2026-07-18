@TestOn('vm')
@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Runs `[className].[method]` (a `static` method) and returns its value.
Future<Object?> _runStatic(
  String language,
  String source,
  String className,
  String method,
) async {
  var vm = ApolloVM();
  expect(
    await vm.loadCodeUnit(SourceCodeUnit(language, source, id: 'test')),
    isTrue,
    reason: '$language: cannot parse',
  );
  var r = await vm
      .createRunner(language)!
      .executeClassMethod(
        '',
        className,
        method,
        positionalParameters: const [[]],
        classInstanceFields: const {},
      );
  return r.getValueNoContext();
}

void main() {
  group('Dart static fields', () {
    test('bare read inside a static method', () async {
      expect(
        await _runStatic(
          'dart',
          'class C { static int count = 7; static int run() { return count; } }',
          'C',
          'run',
        ),
        equals(7),
      );
    });

    test('bare write inside a static method persists', () async {
      expect(
        await _runStatic(
          'dart',
          'class C { static int count = 7;'
              ' static int run() { count = count + 5; return count; } }',
          'C',
          'run',
        ),
        equals(12),
      );
    });

    test('qualified read (ClassName.field) from another class', () async {
      expect(
        await _runStatic(
          'dart',
          'class C { static int count = 7; }'
              ' class M { static int run() { return C.count; } }',
          'M',
          'run',
        ),
        equals(7),
      );
    });

    test('qualified write (ClassName.field = v)', () async {
      expect(
        await _runStatic(
          'dart',
          'class C { static int count = 7; }'
              ' class M { static int run() { C.count = 20; return C.count; } }',
          'M',
          'run',
        ),
        equals(20),
      );
    });

    test('qualified compound assignment (ClassName.field += v)', () async {
      expect(
        await _runStatic(
          'dart',
          'class C { static int count = 7; }'
              ' class M { static int run() { C.count += 5; return C.count; } }',
          'M',
          'run',
        ),
        equals(12),
      );
    });

    test('a static field without an initializer defaults to null', () async {
      expect(
        await _runStatic(
          'dart',
          'class C { static int x; static bool run() { return x == null; } }',
          'C',
          'run',
        ),
        isTrue,
      );
    });

    test('static and instance fields of the same class coexist', () async {
      // The instance field `n` is per-instance; the static `total` is shared.
      var r = await _runStatic(
        'dart',
        'class C {'
            ' int n = 3;'
            ' static int total = 100;'
            ' static int run() { C.total = C.total + 1; return C.total; }'
            ' }',
        'C',
        'run',
      );
      expect(r, equals(101));
    });

    test(
      'static writes are visible across qualified and bare access',
      () async {
        expect(
          await _runStatic(
            'dart',
            'class C {'
                ' static int v = 1;'
                ' static int bump() { v = v + 10; return v; }'
                ' static int run() { bump(); return C.v; }'
                ' }',
            'C',
            'run',
          ),
          equals(11),
        );
      },
    );
  });

  group('Cross-language static fields', () {
    test('Java: static field read/write', () async {
      expect(
        await _runStatic(
          'java11',
          'class C {'
              ' static int count = 7;'
              ' static int run() { count = count + 5; return count; }'
              ' }',
          'C',
          'run',
        ),
        equals(12),
      );
    });

    test('C#: static field read/write', () async {
      expect(
        await _runStatic(
          'csharp',
          'class C {'
              ' static int count = 7;'
              ' static int run() { count = count + 5; return count; }'
              ' }',
          'C',
          'run',
        ),
        equals(12),
      );
    });
  });
}
