@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:apollovm/src/apollovm_code_storage.dart';
import 'package:test/test.dart';

Future<ApolloVM> _load(String src, {String language = 'dart'}) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit(language, src, id: 'test'));
  expect(ok, isTrue, reason: "Can't load $language source");
  return vm;
}

/// Runs the top-level `run()` of [src] and returns its value.
Future<Object?> _run(String src) async {
  var vm = await _load(src);
  var res = await vm.createRunner('dart')!.executeFunction('', 'run');
  return res.getValueNoContext();
}

/// Parses [src] and returns its resolved [ASTRoot].
Future<ASTRoot> _parseRoot(String src, {String language = 'dart'}) async {
  var vm = ApolloVM();
  var result = await vm
      .getParser<String>(language)!
      .parse(SourceCodeUnit(language, src, id: 'test'));
  expect(result.isOK, isTrue, reason: 'should parse: ${result.errorMessage}');
  return result.root!;
}

void main() {
  group('ASTExtension resolution', () {
    test('binds members to the extended core class', () async {
      var root = await _parseRoot(
        'extension NumExt on int { int doubled() { return this * 2; } }',
      );

      var extension = root.extensions.single;
      expect(extension.name, equals('NumExt'));

      var targetClass = extension.targetClass;
      expect(targetClass, isNotNull);
      expect(targetClass!.name, equals('int'));
      expect(extension.matchesReceiver(targetClass), isTrue);

      // Dispatch relies on each member's `clazz` pointing at the extended
      // class, so `objectCall` binds `this` to the receiver.
      var doubled = extension.functions.single.functions.single;
      expect(doubled, isA<ASTClassFunctionDeclaration>());
      expect(
        identical((doubled as ASTClassFunctionDeclaration).clazz, targetClass),
        isTrue,
      );
    });

    test('binds members to the extended user class', () async {
      var root = await _parseRoot('''
        class Point { int x; Point(int x) { this.x = x; } }
        extension PointExt on Point { int twiceX() { return this.x * 2; } }
      ''');

      var extension = root.extensions.single;
      expect(identical(extension.targetClass, root.getClass('Point')), isTrue);
    });

    test('an unknown extended type resolves to no class', () async {
      var root = await _parseRoot(
        'extension E on Missing { int m() { return 1; } }',
      );
      expect(root.extensions.single.targetClass, isNull);
    });

    test(
      'a named extension is an exported symbol; an unnamed one is not',
      () async {
        var named = await _parseRoot(
          'extension NumExt on int { int m() { return 1; } }',
        );
        expect(named.exportedSymbolNames, contains('NumExt'));

        var unnamed = await _parseRoot(
          'extension on int { int m() { return 1; } }',
        );
        expect(unnamed.extensions.single.name, isNull);
        expect(unnamed.exportedSymbolNames, isEmpty);
      },
    );

    test(
      'two modules extending `int` do not pollute the shared core class',
      () async {
        var a = await _parseRoot(
          'extension A on int { int m() { return 1; } }',
        );
        var b = await _parseRoot(
          'extension B on int { int m() { return 2; } }',
        );

        // Both resolve to the same `CoreClassInt` singleton, but neither injected
        // `m` into it: the core class knows no member named `m`.
        var classA = a.extensions.single.targetClass!;
        var classB = b.extensions.single.targetClass!;
        expect(identical(classA, classB), isTrue);
        expect(classA.getFunctionWithName('m'), isNull);
      },
    );
  });

  group('Extension dispatch', () {
    test('method on a primitive receiver', () async {
      expect(
        await _run(
          'extension NumExt on int { int doubled() { return this * 2; } }\n'
          'int run() { var a = 21; return a.doubled(); }',
        ),
        equals(42),
      );
    });

    test('method on a String receiver', () async {
      expect(
        await _run(
          "extension StrExt on String { String twice() { return this + this; } }\n"
          "String run() { var s = 'ab'; return s.twice(); }",
        ),
        equals('abab'),
      );
    });

    test('getter on a primitive receiver', () async {
      expect(
        await _run(
          'extension NumExt on int { int get twice { return this * 2; } }\n'
          'int run() { var a = 21; return a.twice; }',
        ),
        equals(42),
      );
    });

    test('method on a user class instance', () async {
      expect(
        await _run('''
          class Point { int x; Point(int x) { this.x = x; } }
          extension PointExt on Point { int twiceX() { return this.x * 2; } }
          int run() { var p = Point(21); return p.twiceX(); }
        '''),
        equals(42),
      );
    });

    test('overload resolution picks by signature', () async {
      expect(
        await _run('''
          extension NumExt on int {
            int plus(int a) { return this + a; }
            int plus(int a, int b) { return this + a + b; }
          }
          int run() { var a = 10; return a.plus(1) + a.plus(1, 2); }
        '''),
        equals(11 + 13),
      );
    });

    test(
      'a class member wins over an extension member of the same name',
      () async {
        expect(
          await _run('''
          class Point { int x; Point(int x) { this.x = x; } int get v { return 1; } }
          extension PointExt on Point { int get v { return 2; } }
          int run() { var p = Point(0); return p.v; }
        '''),
          equals(1),
        );
      },
    );

    test(
      'an extension member can call another, qualified and unqualified',
      () async {
        expect(
          await _run('''
          extension NumExt on int {
            int doubled() { return this * 2; }
            int quad() { return this.doubled() * 2; }
            int get octo { return quad() * 2; }
          }
          int run() { var a = 2; return a.octo; }
        '''),
          equals(16),
        );
      },
    );

    test(
      'an unknown member of a core type still reports the original error',
      () async {
        expect(
          () => _run(
            'extension NumExt on int { int doubled() { return this * 2; } }\n'
            'int run() { var a = 1; return a.nope(); }',
          ),
          throwsA(isA<StateError>()),
        );
      },
    );

    test('an extension does not apply to an unrelated receiver', () async {
      expect(
        () => _run(
          'extension NumExt on int { int doubled() { return this * 2; } }\n'
          "int run() { var s = 'a'; return s.doubled(); }",
        ),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'a call no extension overload accepts reports the original error',
      () async {
        // The sole `plus(int)` declaration rejects a `String` argument, so the
        // receiver's own class-lookup error surfaces instead.
        expect(
          () => _run(
            'extension NumExt on int { int plus(int a) { return this + a; } }\n'
            "int run() { var a = 1; return a.plus('x'); }",
          ),
          throwsA(isA<StateError>()),
        );
      },
    );

    test(
      'getter on a receiver whose core class throws on unknown getters',
      () async {
        // `CoreClassList.getGetter` throws (rather than returning null) for an
        // unknown getter; the extension must still be found.
        expect(
          await _run('''
          extension ListExt on List {
            int get doubledLength { return this.length * 2; }
          }
          int run() { var l = [1, 2, 3]; return l.doubledLength; }
        '''),
          equals(6),
        );
      },
    );

    test(
      'an unknown getter on such a receiver reports the original error',
      () async {
        expect(
          () => _run(
            'extension ListExt on List { int get doubledLength { return 1; } }\n'
            'int run() { var l = [1]; return l.nope; }',
          ),
          throwsA(isA<StateError>()),
        );
      },
    );
  });

  group('Extension code generation', () {
    test('a language without extensions rejects them', () async {
      var vm = await _load(
        'extension NumExt on int { int doubled() { return this * 2; } }',
      );

      for (var language in ['java11', 'javascript', 'python', 'go', 'lua']) {
        expect(
          () => vm.generateAllCodeIn(language).writeAllSources(),
          throwsA(isA<UnsupportedSyntaxError>()),
          reason: '$language should not silently emit an extension',
        );
      }
    });

    test('Wasm rejects an extension', () async {
      var vm = await _load(
        'extension NumExt on int { int doubled() { return this * 2; } }',
      );
      expect(
        () => vm.generateAllIn<BytesOutput>('wasm'),
        throwsA(isA<UnsupportedSyntaxError>()),
      );
    });

    test('a language without getters rejects a class getter', () async {
      var vm = await _load('class C { int get x { return 1; } }');
      expect(
        () => vm.generateAllCodeIn('java11').writeAllSources(),
        throwsA(isA<UnsupportedSyntaxError>()),
      );
    });

    test('an unnamed extension round-trips and is named for C#', () async {
      var vm = await _load(
        'extension on int { int doubled() { return this * 2; } }',
      );

      var dart = (await vm.generateAllCodeIn('dart').writeAllSources())
          .toString();
      expect(dart, contains('extension on int {'));

      var kotlin = (await vm.generateAllCodeIn('kotlin').writeAllSources())
          .toString();
      expect(kotlin, contains('fun Int.doubled(): Int {'));

      // C# needs a class name; one is synthesized from the extended type.
      var csharp = (await vm.generateAllCodeIn('csharp').writeAllSources())
          .toString();
      expect(csharp, contains('static class intExtension {'));
      expect(csharp, contains('public static int doubled(this int self) {'));
    });

    test('generateASTNode dispatches an ASTExtension', () async {
      var root = await _parseRoot(
        'extension NumExt on int { int doubled() { return this * 2; } }',
      );
      var generator = ApolloVM().createCodeGenerator(
        'dart',
        ApolloSourceCodeStorageMemory(),
      )!;

      // No `out` buffer: the generator must create one.
      var code = generator.generateASTNode(root.extensions.single).toString();
      expect(code, startsWith('extension NumExt on int {'));
    });

    test(
      'C# rejects an extension getter (it has no extension property)',
      () async {
        var vm = await _load(
          'extension NumExt on int { int get twice { return this * 2; } }',
        );
        expect(
          () => vm.generateAllCodeIn('csharp').writeAllSources(),
          throwsA(isA<UnsupportedSyntaxError>()),
        );
      },
    );
  });

  group('C# extension class', () {
    Future<ParseResult<String>> parseCSharp(String src) => ApolloVM()
        .getParser<String>('csharp')!
        .parse(SourceCodeUnit('csharp', src, id: 'test'));

    // A malformed extension aborts the parse (as `modifiers()` already does for
    // duplicated modifiers) rather than silently falling back to a plain class.
    test('a `this` parameter requires a `static` class', () async {
      expect(
        () => parseCSharp('''
          class NumExt {
            public static int Doubled(this int self) { return self * 2; }
          }
        '''),
        throwsA(
          isA<SyntaxError>().having(
            (e) => e.toString(),
            'message',
            contains('must be `static`'),
          ),
        ),
      );
    });

    test('one static class may not extend several types', () async {
      expect(
        () => parseCSharp('''
          static class Ext {
            public static int Doubled(this int self) { return self * 2; }
            public static string Shout(this string self) { return self; }
          }
        '''),
        throwsA(
          isA<SyntaxError>().having(
            (e) => e.toString(),
            'message',
            contains('extends multiple types'),
          ),
        ),
      );
    });

    test('a plain static class is still a class, not an extension', () async {
      var result = await parseCSharp('''
        static class Util {
          public static int Twice(int a) { return a * 2; }
        }
      ''');
      expect(result.isOK, isTrue, reason: result.errorMessage);
      expect(result.root!.extensions, isEmpty);
      expect(result.root!.classesNames, equals(['Util']));
    });

    test(
      'a local named `self` outside an extension is a normal variable',
      () async {
        var vm = await _load('''
        static class Ext {
          public static int Doubled(this int self) { return self * 2; }
        }
        class Foo {
          int test(int a) { var self = a; return self + 1; }
        }
      ''', language: 'csharp');

        var res = await vm
            .createRunner('csharp')!
            .executeClassMethod(
              '',
              'Foo',
              'test',
              positionalParameters: [41],
              classInstanceFields: const {},
            );
        expect(res.getValueNoContext(), equals(42));
      },
    );
  });
}
