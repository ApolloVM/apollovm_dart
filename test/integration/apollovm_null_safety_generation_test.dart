@TestOn('vm')
@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Every source language ApolloVM can both parse and generate.
const _languages = [
  'dart',
  'java11',
  'javascript',
  'typescript',
  'kotlin',
  'csharp',
  'python',
  'go',
  'lua',
];

/// Languages that can generate [_source] in full. Go is excluded because the
/// source uses `??=` and `?.`, which it reports as unsupported — it does
/// support plain `??` and nullable `T?` (as `*T`); see its own tests below.
final _languagesWithNullCoalesce = _languages.where((l) => l != 'go').toList();

/// A Dart program exercising the full null-safety surface: nullable types,
/// `??`, `??=`, `?.`, `?.method()`, `?[`, postfix `!` (standalone and before
/// access) and cascades (`..` / `?..`).
const _source = r'''
class A {
  int x = 1;
  int add(int d) { x = x + d; return x; }

  int coalesce(int? a, int b) { return a ?? b; }
  int coalesceAssign(int? a, int b) { a ??= b; return a; }
  int? field(A? a) { return a?.x; }
  int? call(A? a) { return a?.add(1); }
  int? index(List<int>? xs) { return xs?[0]; }
  int assertField(A? a) { return a!.x; }
  int assertIndex(List<int>? xs) { return xs![0]; }
  int bang(int? a, int b) { int? v = a ?? b; return v!; }
  A cascade(A a) { a..add(1)..add(2); return a; }

  String? name;
  List<String>? names;
  void Function()? cb;
}
''';

Future<ApolloVM> _load(String src) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', src, id: 'test'));
  expect(ok, isTrue, reason: "can't load Dart source");
  return vm;
}

Future<String> _generate(ApolloVM vm, String language) async {
  var storage = vm.generateAllCodeIn(language);
  await storage.writeAllSources();
  var out = StringBuffer();
  for (var ns in await storage.getNamespaces()) {
    for (var id in await storage.getNamespaceCodeUnitsIDs(ns)) {
      out.write((await storage.getNamespaceCodeUnit(ns, id))!);
    }
  }
  return out.toString();
}

void main() {
  group('null-safety generation', () {
    test(
      'every language generates without error and names the class',
      () async {
        var vm = await _load(_source);
        for (var language in _languagesWithNullCoalesce) {
          var code = await _generate(vm, language);
          expect(code, isNotEmpty, reason: '$language generated nothing');
          expect(
            code,
            contains('A'),
            reason: '$language should name the generated class',
          );
        }
      },
    );

    test('Go supports `??` but not `??=`', () async {
      // `a ?? b` lowers to a nil-checking inline function over the `*T`.
      // `a ??= b` would need the target's element type to build that function's
      // return type, which is not available at the text-level assignment hook.
      var ok = await _load(
        'class K { int f(int? a, int b) { return a ?? b; } }',
      );
      expect(await _generate(ok, 'go'), contains('a != nil'));

      var bad = await _load(
        'class K { int f(int? a, int b) { a ??= b; return a; } }',
      );
      expect(
        () => _generate(bad, 'go'),
        throwsA(isA<UnsupportedSyntaxError>()),
      );
    });

    test('Go still generates a program with no null-coalescing', () async {
      var vm = await _load(
        'class B { int add(int a, int b) { return a + b; } }',
      );
      var go = await _generate(vm, 'go');
      expect(go, contains('func'));
      expect(go, isNot(contains('??')));
    });

    test('Dart round-trips every operator exactly', () async {
      var vm = await _load(_source);
      var dart = await _generate(vm, 'dart');

      expect(dart, contains('int coalesce(int? a, int b)'));
      expect(dart, contains('return a ?? b;'));
      expect(dart, contains('a ??= b;'));
      expect(dart, contains('return a?.x;'));
      expect(dart, contains('return a?.add(1);'));
      expect(dart, contains('return xs?[0];'));
      expect(dart, contains('return a!.x;'));
      expect(dart, contains('return xs![0];'));
      expect(dart, contains('return v!;'));
      expect(dart, contains('a..add(1)..add(2);'));
      expect(dart, contains('String? name;'));
      expect(dart, contains('List<String>? names;'));
      expect(dart, contains('void Function()? cb;'));
    });

    test('Dart generated source parses back', () async {
      var vm = await _load(_source);
      var dart = await _generate(vm, 'dart');
      var reloaded = ApolloVM();
      var ok = await reloaded.loadCodeUnit(
        SourceCodeUnit('dart', dart, id: 'test'),
      );
      expect(ok, isTrue, reason: 'Dart generated source it cannot parse');
    });

    test('Kotlin emits native null-aware forms (?:, ?., !!)', () async {
      var vm = await _load(_source);
      var kotlin = await _generate(vm, 'kotlin');
      expect(kotlin, contains('a ?: b')); // Elvis, not `??`
      expect(kotlin, contains('a?.x'));
      expect(kotlin, contains('a!!.x'));
      expect(kotlin, contains('Int?')); // nullable type suffix
    });

    test('TypeScript emits native null-aware forms (??, ?., ?.[, !)', () async {
      var vm = await _load(_source);
      var ts = await _generate(vm, 'typescript');
      expect(ts, contains('a ?? b'));
      expect(ts, contains('a?.x'));
      expect(ts, contains('xs?.[0]')); // element access is `?.[`, not `?[`
      expect(ts, contains('a!.x'));
    });

    test('C# emits `??` (native null-coalescing)', () async {
      var vm = await _load(_source);
      var csharp = await _generate(vm, 'csharp');
      expect(csharp, contains('a ?? b'));
    });

    test('no target leaks a literal `??` or `??=` it cannot compile', () async {
      var vm = await _load(_source);
      // Targets that genuinely have the operators keep them.
      const native = {'dart', 'javascript', 'typescript', 'csharp'};

      for (var language in _languagesWithNullCoalesce) {
        var code = await _generate(vm, language);
        if (native.contains(language)) continue;

        expect(
          code,
          isNot(contains('??')),
          reason: '$language has no `??`/`??=` and must desugar them',
        );
      }
    });

    test('Go emits a nullable `T?` as a pointer `*T`', () async {
      var vm = await _load(
        'class K { int f() { int? x = null; if (x == null) { return 1; } return 0; } }',
      );
      var go = await _generate(vm, 'go');
      expect(go, contains('*int'));
      expect(go, contains('nil'));
    });

    test('Go derefs a nullable read and nil-checks `??`', () async {
      var vm = await _load(
        'class K { int f(int? a, int b) { return a ?? b; } }',
      );
      var go = await _generate(vm, 'go');
      expect(go, contains('a *int')); // pointer parameter
      expect(go, contains('a != nil')); // nil check, not a bare deref
      expect(go, contains('*a')); // deref on the non-nil path
    });

    test('Go takes the address of a non-null value via `goPtr`', () async {
      var vm = await _load('class K { int f() { int? x = 5; return x + 1; } }');
      var go = await _generate(vm, 'go');
      // Go cannot write `&5`, so the helper is emitted and used.
      expect(go, contains('func goPtr[T any](v T) *T'));
      expect(go, contains('goPtr(5)'));
    });

    test('Go leaves a nilable List/Map as a slice/map', () async {
      var vm = await _load(
        'class K { int f() { List<int>? xs = null; if (xs == null) { return 1; } return 0; } }',
      );
      var go = await _generate(vm, 'go');
      expect(go, contains('[]int'));
      expect(go, isNot(contains('*[]int')));
    });

    test('Go reports null-aware access (`?.`) as unsupported', () async {
      // Degrading `?.` to `.` would skip the nil check *and* yield a value
      // where a `*T` is expected, so it must not be emitted.
      var vm = await _load(
        'class A { int x = 1; int? f(A? a) { return a?.x; } }',
      );
      expect(() => _generate(vm, 'go'), throwsA(isA<UnsupportedSyntaxError>()));
    });

    group('Kotlin null-aware index', () {
      // Kotlin has no `?[` operator; the shared default spelling is invalid
      // there. Null-aware element access is the call `a?.get(i)`.
      test('a list index becomes `?.get(i)`', () async {
        var vm = await _load(
          'class K { int? f(List<int>? xs) { return xs?[0]; } }',
        );
        var kotlin = await _generate(vm, 'kotlin');
        expect(kotlin, contains('xs?.get(0)'));
        expect(kotlin, isNot(contains('?[')));
      });

      test('a map key becomes `?.get(k)`', () async {
        var vm = await _load(
          "class K { int? f(Map<String,int>? m) { return m?['a']; } }",
        );
        var kotlin = await _generate(vm, 'kotlin');
        expect(kotlin, contains('?.get('));
        expect(kotlin, isNot(contains('?[')));
      });

      test('a non-null index keeps `[i]`', () async {
        var vm = await _load(
          'class K { int f(List<int> xs) { return xs[0]; } }',
        );
        var kotlin = await _generate(vm, 'kotlin');
        expect(kotlin, contains('xs[0]'));
        expect(kotlin, isNot(contains('.get(')));
      });

      test('other targets keep their own spelling', () async {
        var vm = await _load(
          'class K { int? f(List<int>? xs) { return xs?[0]; } }',
        );
        // The close token is per-target: Dart `?[i]`, TypeScript `?.[i]`.
        expect(await _generate(vm, 'dart'), contains('xs?[0]'));
        expect(await _generate(vm, 'typescript'), contains('xs?.[0]'));
      });
    });

    group('Lua null literal', () {
      // `null` is not a Lua value. Emitting it verbatim referenced an undefined
      // global, so `a == null` was always false rather than a nil test.
      test('a null comparison uses `nil`', () async {
        var vm = await _load(
          'class K { int f(int? a) { if (a == null) { return -1; } return 1; } }',
        );
        var lua = await _generate(vm, 'lua');
        expect(lua, contains('== nil'));
        expect(lua, isNot(contains('null')));
      });

      test('a null initializer uses `nil`', () async {
        var vm = await _load(
          'class K { int f() { int? a = null; if (a == null) { return -1; } '
          'return 1; } }',
        );
        var lua = await _generate(vm, 'lua');
        expect(lua, contains('nil'));
        expect(lua, isNot(contains('null')));
      });

      test('a returned null uses `nil`', () async {
        var vm = await _load('class K { int? f() { return null; } }');
        var lua = await _generate(vm, 'lua');
        expect(lua, contains('return nil'));
        expect(lua, isNot(contains('null')));
      });

      test('a null inside a list/map literal uses `nil`', () async {
        // Collection elements are resolved AST *values*, so these reach the
        // `ASTValueNull` hook rather than the null-*expression* one.
        var list = await _load(
          'class K { int f() { var xs = [1, null, 3]; return 0; } }',
        );
        var luaList = await _generate(list, 'lua');
        expect(luaList, contains('{1, nil, 3}'));
        expect(luaList, isNot(contains('null')));

        var map = await _load(
          "class K { int f() { var m = {'a': null}; return 0; } }",
        );
        var luaMap = await _generate(map, 'lua');
        expect(luaMap, contains('nil'));
        expect(luaMap, isNot(contains('null')));
      });

      test('a null field initializer uses `nil`', () async {
        var vm = await _load(
          'class K { String? name = null; int f() { return 0; } }',
        );
        var lua = await _generate(vm, 'lua');
        expect(lua, contains('name = nil'));
        expect(lua, isNot(contains('null')));
      });

      test('other targets keep their own null spelling', () async {
        var vm = await _load('class K { int? f() { return null; } }');
        expect(await _generate(vm, 'dart'), contains('return null'));
        expect(await _generate(vm, 'python'), contains('return None'));
        expect(await _generate(vm, 'go'), contains('return nil'));
      });
    });

    test('Java desugars `??` and `??=` into ternaries', () async {
      var vm = await _load(_source);
      var java = await _generate(vm, 'java11');
      expect(java, contains('(a != null ? a : b)'));
      // `a ??= b` becomes `a = (a != null ? a : b)`.
      expect(java, contains('a = (a != null ? a : b)'));
    });

    test(
      'Python desugars `??` and `??=` into conditional expressions',
      () async {
        var vm = await _load(_source);
        var python = await _generate(vm, 'python');
        expect(python, contains('(a if a is not None else b)'));
        expect(python, contains('a = (a if a is not None else b)'));
      },
    );

    test('Lua desugars `??` with an explicit nil test (not `or`)', () async {
      var vm = await _load(_source);
      var lua = await _generate(vm, 'lua');
      // `a or b` would be wrong: Lua treats `false` as falsy, so a non-nil
      // `false` must NOT fall through to `b`.
      expect(lua, contains('~= nil'));
      expect(lua, isNot(contains('a or b')));
    });

    test('Kotlin lowers `??=` to `t = t ?: v` (it has no `??=`)', () async {
      var vm = await _load(_source);
      var kotlin = await _generate(vm, 'kotlin');
      expect(kotlin, contains('a = a ?: b'));
    });

    group('`x == null` / `x != null`', () {
      const src =
          'class K { int f(int? a) { if (a == null) { return -1; } '
          'if (a != null) { return 1; } return 0; } }';

      test('Python compares by identity, not equality', () async {
        // `==` dispatches through `__eq__`, which a class can redefine to
        // return True for None; `is` cannot be intercepted.
        var python = await _generate(await _load(src), 'python');
        expect(python, contains('a is None'));
        expect(python, contains('a is not None'));
        expect(python, isNot(contains('== None')));
      });

      test('JavaScript/TypeScript keep strict equality', () async {
        for (var lang in ['javascript', 'typescript']) {
          var code = await _generate(await _load(src), lang);
          expect(code, contains('a === null'), reason: lang);
          expect(code, contains('a !== null'), reason: lang);
        }
      });

      test('Lua uses `nil` and `~=`', () async {
        var lua = await _generate(await _load(src), 'lua');
        expect(lua, contains('a == nil'));
        expect(lua, contains('a ~= nil'));
      });

      test('Go compares the pointer without dereferencing it', () async {
        var go = await _generate(await _load(src), 'go');
        expect(go, contains('a == nil'));
        expect(go, contains('a != nil'));
        // A deref would read the value, defeating the nil test.
        expect(go, isNot(contains('(*a) == nil')));
      });
    });

    group('null-aware access is lowered, not dropped', () {
      const src =
          'class A { int x = 1; int m() { return 2; } }\n'
          'class K {\n'
          '  int getter(A? a) { return a?.x; }\n'
          '  int chain(A? a) { return a?.m().toInt(); }\n'
          '  int index(List<int>? xs) { return xs?[0]; }\n'
          '}';

      test('Java guards the access with a ternary', () async {
        var java = await _generate(await _load(src), 'java11');
        expect(java, contains('(a != null ? a.x : null)'));
        expect(java, contains('(xs != null ? xs[0] : null)'));
      });

      test('Python guards the access with `is not None`', () async {
        var python = await _generate(await _load(src), 'python');
        expect(python, contains('(a.x if a is not None else None)'));
        expect(python, contains('(xs[0] if xs is not None else None)'));
      });

      test('Lua guards the access with an explicit nil test', () async {
        var lua = await _generate(await _load(src), 'lua');
        expect(lua, contains('if a ~= nil then return a.x end'));
      });

      test('Lua guards a null-aware index, keeping the 1-based shift', () async {
        // Lua tables are 1-indexed, so `xs?[0]` is both guarded *and* shifted.
        // The shift has to stay inside the guard.
        var lua = await _generate(await _load(src), 'lua');
        expect(lua, contains('if xs ~= nil then return xs[1] end'));
      });

      test('the whole chain stays inside the guard', () async {
        // `a?.m().toInt()` nests as an invocation of `toInt` whose receiver is
        // the null-aware call to `m`. Guarding only the null-aware link would
        // leave `.toInt()` outside it, still dereferencing null.
        expect(
          await _generate(await _load(src), 'java11'),
          contains('(a != null ? a.m().toInt() : null)'),
        );
        expect(
          await _generate(await _load(src), 'python'),
          contains('(a.m().toInt() if a is not None else None)'),
        );
      });

      test('C# and JavaScript use their native operators', () async {
        var csharp = await _generate(await _load(src), 'csharp');
        expect(csharp, contains('a?.x'));
        expect(csharp, contains('xs?[0]'));

        var js = await _generate(await _load(src), 'javascript');
        expect(js, contains('a?.x'));
        // JS spells null-aware element access `?.[`, not `?[`.
        expect(js, contains('xs?.[0]'));
      });

      test('JavaScript never emits a postfix `!`', () async {
        // JS has no null-assertion operator; a postfix `!` would be logical NOT.
        var js = await _generate(
          await _load('class K { int f(int? a) { return a!; } }'),
          'javascript',
        );
        expect(js, contains('return a;'));
        expect(js, isNot(contains('a!')));
      });

      test(
        'Go reports null-aware access rather than mis-emitting it',
        () async {
          var vm = await _load(
            'class A { int x = 1; }\n'
            'class K { int f(A? a) { return a?.x; } }',
          );
          expect(
            () => _generate(vm, 'go'),
            throwsA(isA<UnsupportedSyntaxError>()),
          );
        },
      );

      test('Go reports a null-aware index too', () async {
        var vm = await _load(
          'class K { int? f(List<int>? xs) { return xs?[0]; } }',
        );
        expect(
          () => _generate(vm, 'go'),
          throwsA(isA<UnsupportedSyntaxError>()),
        );
      });

      test('C# emits the null-forgiving `!` natively', () async {
        var vm = await _load(
          'class A { int x = 1; }\n'
          'class K { int f(A? a) { return a!.x; } }',
        );
        expect(await _generate(vm, 'csharp'), contains('a!.x'));
      });

      test('a nested chain nests the guards soundly', () async {
        // `a?.next?.v` has two null-aware links: the outer guard tests the
        // inner guard's *result*, so a null at either link yields null rather
        // than dereferencing.
        const nested =
            'class C { int v = 5; C? next; }\n'
            'class K { int? f(C? a) { return a?.next?.v; } }';

        expect(
          await _generate(await _load(nested), 'java11'),
          contains('((a != null ? a.next : null) != null ? a.next.v : null)'),
        );
        expect(
          await _generate(await _load(nested), 'python'),
          contains(
            '(a.next.v if (a.next if a is not None else None) '
            'is not None else None)',
          ),
        );
      });

      test('a non-nullable receiver takes a single guard', () async {
        // `c.next?.v` has one null-aware link on a non-nullable receiver, so
        // one guard on `c.next` is all that is needed.
        var vm = await _load(
          'class C { int v = 5; C? next; }\n'
          'class K { int? f(C c) { return c.next?.v; } }',
        );
        expect(
          await _generate(vm, 'java11'),
          contains('(c.next != null ? c.next.v : null)'),
        );
      });
    });
  });
}
