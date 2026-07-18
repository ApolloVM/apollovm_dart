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

    test('qualified read of a null-default static field', () async {
      expect(
        await _runStatic(
          'dart',
          'class C { static int x; }'
              ' class M { static bool run() { return C.x == null; } }',
          'M',
          'run',
        ),
        isTrue,
      );
    });

    test('every qualified compound operator on a static field', () async {
      Future<Object?> op(String stmt) => _runStatic(
        'dart',
        'class C { static int v = 12; }'
            ' class M { static int run() { $stmt; return C.v; } }',
        'M',
        'run',
      );
      expect(await op('C.v -= 2'), equals(10));
      expect(await op('C.v *= 3'), equals(36));
      expect(await op('C.v ~/= 5'), equals(2));

      // `/=` yields a double, so use a double-typed static field.
      expect(
        await _runStatic(
          'dart',
          'class C { static double v = 12.0; }'
              ' class M { static double run() { C.v /= 5; return C.v; } }',
          'M',
          'run',
        ),
        equals(2.4),
      );
    });

    test('a static field carries its declared type', () async {
      // Assigning `C.v` to a typed local exercises static-field type resolution.
      expect(
        await _runStatic(
          'dart',
          'class C { static int v = 42; }'
              ' class M { static int run() { int y = C.v; return y; } }',
          'M',
          'run',
        ),
        equals(42),
      );
    });
  });

  group('Static-field internals (direct)', () {
    Future<ASTClassNormal> loadClass(String src) async {
      var vm = ApolloVM();
      expect(
        await vm.loadCodeUnit(SourceCodeUnit('dart', src, id: 't')),
        isTrue,
      );
      return vm
          .getNamespaceWithClass('C', language: 'dart')
          .first
          .getClass('C')!;
    }

    test(
      'ASTStaticFieldVariable read/write/resolveType/resolveVariable',
      () async {
        var clazz = await loadClass('class C { static int count = 7; }');
        var v = ASTStaticFieldVariable(clazz, 'count');
        var ctx = VMScopeContext(ASTBlock(null));

        expect(v.resolveVariable(ctx), same(v));
        expect(await v.resolveType(ctx), isA<ASTTypeInt>());
        var read = await v.getValue(ctx);
        expect(read.getValueNoContext(), equals(7));
        await v.setValue(ctx, ASTValueInt(99));
        expect((await v.getValue(ctx)).getValueNoContext(), equals(99));
      },
    );

    test('resolveType of an unknown field falls back to dynamic', () async {
      var clazz = await loadClass('class C { static int count = 7; }');
      var v = ASTStaticFieldVariable(clazz, 'missing');
      var ctx = VMScopeContext(ASTBlock(null));
      expect(await v.resolveType(ctx), isA<ASTTypeDynamic>());
    });

    test('getStaticFieldValue resolves a name case-insensitively', () async {
      var clazz = await loadClass('class C { static int count = 7; }');
      var ctx = VMScopeContext(ASTBlock(null));
      expect(clazz.hasStaticField('COUNT', caseInsensitive: true), isTrue);
      var v = await clazz.getStaticFieldValue(
        ctx,
        'COUNT',
        caseInsensitive: true,
      );
      expect(v?.getValueNoContext(), equals(7));
    });
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
