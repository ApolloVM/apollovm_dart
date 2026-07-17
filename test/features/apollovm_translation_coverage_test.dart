@TestOn('vm')
@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Every language ApolloVM can generate source in.
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

/// A token every generated class-with-methods emits in the given language.
/// Used as a lenient sanity check that the *right* generator produced output.
const _languageToken = {
  'dart': 'class',
  'java11': 'class',
  'javascript': 'class',
  'typescript': 'class',
  'kotlin': 'fun ',
  'csharp': 'class',
  'python': 'def ',
  'go': 'func ',
  'lua': 'function ',
};

/// A translation program: a Dart [source] and the [className] it declares.
///
/// The [name] labels the generator surface it exercises. Together the programs
/// drive nearly every emit method in the base [ApolloCodeGenerator] and each
/// language generator: loops of every shape, branches, the ternary, the full
/// operator set, string interpolation/concatenation, collection literals,
/// index access, recursion, lambdas, default/named parameters, static members,
/// switch, try/catch/finally/throw, constructors and double literals.
class _Program {
  final String name;
  final String className;
  final String source;

  const _Program(this.name, this.className, this.source);
}

const _programs = <_Program>[
  // Loops (for / while / do-while / for-in), break, continue, if/else-if/else,
  // nested branches and the ternary operator.
  _Program('controlFlow', 'Flow', r'''
class Flow {
  int base = 3;

  int loops(int n) {
    var total = 0;
    for (var i = 0; i < n; ++i) {
      total += i;
      if (i == 5) { continue; }
      if (i > 20) { break; }
    }
    var j = 0;
    while (j < 3) { j = j + 1; total += j; }
    do { total = total + 1; j = j - 1; } while (j > 0);
    for (var e in [1, 2, 3]) { total += e; }
    return total;
  }

  int branches(int a) {
    if (a > 10) { return 1; } else if (a > 5) { return 2; } else { return 3; }
  }

  String ternary(int a) {
    return a > 0 ? 'pos' : 'neg';
  }

  int nested(int a) {
    var r = 0;
    for (var i = 0; i < a; ++i) {
      if (i > 2) { r += i; } else { r -= i; }
    }
    return r;
  }
}
'''),

  // Arithmetic (+ - * ~/ %), bitwise (& | ^ << >> ~), logical (&& || !),
  // comparisons (< <= > >= == !=), unary minus and increment/decrement.
  _Program('operators', 'Ops', r'''
class Ops {
  int arithmetic(int a, int b) {
    var r = a + b - a * b;
    r = r ~/ 2;
    r = r % 3;
    return r;
  }

  int bitwise(int a, int b) {
    var r = (a & b) | (a ^ b);
    r = a << 2;
    r = a >> 1;
    r = ~a;
    return r;
  }

  bool logic(int a, int b) {
    return (a > 0 && b > 0) || !(a == b);
  }

  int unary(int a) {
    var n = -a;
    a++;
    --a;
    return n + a;
  }

  bool comparisons(int a, int b) {
    return a < b && a <= b && a > b || a >= b && a != b;
  }
}
'''),

  // String interpolation (with an embedded expression), concatenation and
  // instance-method calls on a string.
  _Program('strings', 'Strings', r'''
class Strings {
  String interpolate(String name, int age) {
    var next = age + 1;
    var msg = 'Name: $name, Age: $age, Next: $next';
    return msg;
  }

  String concat(String a, String b) {
    return a + ' ' + b;
  }

  String methods(String s) {
    return s.toUpperCase() + s.toLowerCase();
  }
}
'''),

  // List and map literals, nested lists, index access and collection methods.
  _Program('collections', 'Collections', r'''
class Collections {
  List makeList() {
    return [1, 2, 3, 4];
  }

  Map makeMap() {
    return {'a': 1, 'b': 2};
  }

  int indexAccess(List items) {
    return items[0];
  }

  int listOps(List items) {
    items.add(5);
    return items.length;
  }

  List nested() {
    return [[1, 2], [3, 4]];
  }
}
'''),

  // Recursion, a lambda stored in a variable and invoked, default and named
  // parameters, a static method and a void method calling `print`.
  _Program('functions', 'Functions', r'''
class Functions {
  int recurse(int n) {
    if (n <= 1) { return 1; }
    return n * recurse(n - 1);
  }

  int lambdas(int a) {
    var f = (int x) { return x * 2; };
    return f(a);
  }

  int defaults(int a, [int b = 10]) {
    return a + b;
  }

  int named(int a, {int b = 5}) {
    return a + b;
  }

  static int staticMethod(int a) {
    return a * a;
  }

  void doPrint(String s) {
    print(s);
  }
}
'''),

  // switch/case/default, try/catch/finally, throw and an early return.
  _Program('exceptions', 'Exceptions', r'''
class Exceptions {
  int classify(int a) {
    switch (a) {
      case 0: return 100;
      case 1: return 200;
      default: return 300;
    }
  }

  String guarded(int a) {
    try {
      if (a < 0) { throw 'negative'; }
      return 'ok';
    } catch (e) {
      return 'caught';
    } finally {
      print('done');
    }
  }

  int maybeNull(int a) {
    if (a > 0) { return a; }
    return 0;
  }
}
'''),

  // A constructor assigning through `this`, double literals and `this`-scoped
  // field access.
  _Program('constructor', 'Point', r'''
class Point {
  int x = 0;
  int y = 0;

  Point(int x, int y) {
    this.x = x;
    this.y = y;
  }

  double distance() {
    var dx = x * 1.0;
    var dy = y * 2.5;
    return dx + dy;
  }

  bool isOrigin() {
    return x == 0 && y == 0;
  }

  int sum() {
    return this.x + this.y;
  }
}
'''),
];

/// Loads [dartSource] and generates its AST as [language], returning the
/// concatenated generated source of every code unit.
Future<String> _translate(String dartSource, String language) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(
    SourceCodeUnit('dart', dartSource, id: 'test'),
  );
  expect(ok, isTrue, reason: 'Dart source failed to load');

  var storage = vm.generateAllCodeIn(language);
  await storage.writeAllSources();

  var buf = StringBuffer();
  for (var ns in await storage.getNamespaces()) {
    for (var id in await storage.getNamespaceCodeUnitsIDs(ns)) {
      buf.write(await storage.getNamespaceCodeUnit(ns, id));
    }
  }
  return buf.toString();
}

void main() {
  group('Translate rich Dart programs into every target language', () {
    // Every (program, language) pair drives a distinct spread of generator
    // emit methods; each pair is verified to produce non-empty, plausibly
    // correct source without crashing the generator.
    for (var program in _programs) {
      for (var language in _languages) {
        test('${program.name} -> $language generates valid source', () async {
          var generated = await _translate(program.source, language);

          expect(
            generated.trim(),
            isNotEmpty,
            reason: '$language generated nothing for ${program.name}',
          );
          expect(
            generated,
            contains(program.className),
            reason: '$language should name the ${program.className} class',
          );
          expect(
            generated,
            contains(_languageToken[language]!),
            reason:
                '$language output should contain '
                '"${_languageToken[language]}"',
          );
        });
      }
    }

    // The full program set generates in every language without throwing:
    // a single assertion that the generator surface as a whole is crash-free.
    test(
      'every program generates in every language without throwing',
      () async {
        for (var program in _programs) {
          for (var language in _languages) {
            await expectLater(
              _translate(program.source, language),
              completes,
              reason: '${program.name} -> $language threw during generation',
            );
          }
        }
      },
    );
  });
}
