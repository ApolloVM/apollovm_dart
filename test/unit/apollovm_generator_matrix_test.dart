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

/// A program exercising a wide spread of AST node kinds: fields, loops of every
/// shape, branches, the ternary, unary and bitwise operators, string
/// interpolation, collection literals and a lambda.
const _richSource = r'''
class Calc {

  int base = 10;

  int loops(int n) {
    var total = 0;
    for (var i = 0; i < n; ++i) { total += i; }
    var j = 0;
    while (j < 2) { j++; }
    do { j--; } while (j > 0);
    for (var e in [1, 2]) { total += e; }
    return total;
  }

  int branches(int a) {
    if (a > 10) { return 1; } else if (a > 5) { return 2; } else { return 3; }
  }

  int ops(int a) {
    var b = a * 2 + 1 - 3;
    var c = a > 1 ? 1 : 0;
    var neg = -a;
    var not = !(a > 1);
    var bits = (a & 3) | (a ^ 1);
    return b + c + neg + bits;
  }

  String strings(String s) {
    var t = 'x: $s';
    return t + s.toUpperCase();
  }

  int lambdas(int a) {
    var f = (int x) { return x * 2; };
    return f(a);
  }
}
''';

/// Constructs every language both generates *and* parses back, so the generated
/// source can be re-loaded.
///
/// Deliberately narrower than [_richSource]: several grammars parse only a
/// subset of what their own generator emits. Known gaps, each reproducible by
/// moving the construct into this source:
///  - Loops: Lua has no `for`/`while` rule, Python no `do`/`while`, and Kotlin
///    and Go no `for` loop.
///  - Python cannot parse the lambda it generates; JS and TS cannot parse the
///    map literal they generate.
///  - The Lua generator emits `a + b` for string concatenation and `s.m()` for
///    a method call, where Lua wants `a .. b` and `s:m()`.
const _roundTripSource = r'''
class Calc {

  int base = 10;

  int branches(int a) {
    if (a > 10) { return 1; } else if (a > 5) { return 2; } else { return 3; }
  }

  int ops(int a) {
    var c = a > 1 ? 1 : 0;
    var neg = -a;
    var bits = (a & 3) | (a ^ 1);
    return c + neg + bits;
  }

  List lists() {
    return [1, 2];
  }
}
''';

Future<ApolloVM> _loadDart(String src) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', src, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source");
  return vm;
}

/// Generates [vm]'s AST as [language] and returns each generated code unit.
Future<List<String>> _generate(ApolloVM vm, String language) async {
  var storage = vm.generateAllCodeIn(language);
  await storage.writeAllSources();

  var sources = <String>[];
  for (var ns in await storage.getNamespaces()) {
    for (var id in await storage.getNamespaceCodeUnitsIDs(ns)) {
      sources.add((await storage.getNamespaceCodeUnit(ns, id))!);
    }
  }
  return sources;
}

void main() {
  group('code generation across every language', () {
    test('a rich program generates without error in every language', () async {
      var vm = await _loadDart(_richSource);

      for (var language in _languages) {
        var sources = await _generate(vm, language);
        expect(sources, isNotEmpty, reason: '$language generated nothing');
        expect(
          sources.single,
          contains('class Calc'.split(' ').last),
          reason: '$language should name the generated class',
        );
      }
    });

    test('generated source parses back in its own language', () async {
      var vm = await _loadDart(_roundTripSource);

      for (var language in _languages) {
        for (var source in await _generate(vm, language)) {
          var reloaded = ApolloVM();
          var ok = await reloaded.loadCodeUnit(
            SourceCodeUnit(language, source, id: 'test'),
          );
          expect(
            ok,
            isTrue,
            reason: '$language generated source it cannot parse:\n$source',
          );
        }
      }
    });
  });

  group('Java 11 collection literals', () {
    Future<bool> parseJava(String body) async {
      var src = 'class C {\n  Object m() {\n    return $body;\n  }\n}\n';
      return ApolloVM().loadCodeUnit(SourceCodeUnit('java11', src, id: 'test'));
    }

    // The diamond alternative used to hand the `'>'` character to a cast
    // expecting an `ASTType`, throwing a raw `TypeError` instead of parsing.
    test('the diamond form of a list literal parses', () async {
      expect(await parseJava('new ArrayList<>()'), isTrue);
      expect(await parseJava('new ArrayList<>(){{ add(1); }}'), isTrue);
    });

    test('the diamond form of a map literal parses', () async {
      expect(await parseJava('new HashMap<>()'), isTrue);
      expect(await parseJava('new HashMap<>(){{ put("a", 1); }}'), isTrue);
    });

    test('the explicitly typed forms still parse', () async {
      expect(await parseJava('new ArrayList<Integer>(){{ add(1); }}'), isTrue);
      expect(
        await parseJava('new HashMap<String, Integer>(){{ put("a", 1); }}'),
        isTrue,
      );
    });

    test('a Dart map literal round-trips through Java', () async {
      var vm = await _loadDart(
        "class C { Map m() { return {'a': 1, 'b': 2}; } }",
      );
      var java = (await _generate(vm, 'java11')).single;
      expect(java, contains('new HashMap<'));

      var reloaded = ApolloVM();
      expect(
        await reloaded.loadCodeUnit(SourceCodeUnit('java11', java, id: 'test')),
        isTrue,
      );
    });
  });
}
