// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

@Tags(['dart', 'java', 'go'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Loads [source] in [language], runs an entry point and returns the captured
/// `print` output.
Future<List<Object?>> _run(
  String language,
  String source, {
  String function = 'run',
  String? className,
  List positionalParameters = const [],
}) async {
  var vm = ApolloVM();
  var codeUnit = SourceCodeUnit(language, source, id: 'test');

  var loaded = await vm.loadCodeUnit(codeUnit);
  expect(loaded, isTrue, reason: "Failed to load $language code");

  var runner = vm.createRunner(language)!;

  var output = <Object?>[];
  runner.externalPrintFunction = (o) => output.add(o);

  if (className != null) {
    // Entry methods here are non-static, so run them against a (field-less)
    // instance — only `static` methods run without an instance.
    await runner.executeClassMethod(
      '',
      className,
      function,
      positionalParameters: positionalParameters,
      classInstanceFields: const {},
    );
  } else {
    await runner.executeFunction(
      '',
      function,
      positionalParameters: positionalParameters,
    );
  }

  return output;
}

/// Loads [source] in [language] and returns the value of calling [function].
Future<ASTValue> _call(
  String language,
  String source,
  String function, {
  List positionalParameters = const [],
}) async {
  var vm = ApolloVM();
  await vm.loadCodeUnit(SourceCodeUnit(language, source, id: 'test'));
  var runner = vm.createRunner(language)!;
  return runner.executeFunction(
    '',
    function,
    positionalParameters: positionalParameters,
  );
}

/// Loads [source] in [language] and translates it to [targetLanguage] source.
Future<String> _translate(
  String language,
  String source,
  String targetLanguage,
) async {
  var vm = ApolloVM();
  await vm.loadCodeUnit(SourceCodeUnit(language, source, id: 'test'));
  var storage = vm.generateAllCodeIn(targetLanguage);
  return (await storage.writeAllSources()).toString();
}

/// Extracts the raw source of the single generated code unit from the
/// ApolloVM "sources" envelope produced by `writeAllSources`.
String _extractCodeUnit(String allSources) {
  var lines = allSources.split('\n');
  var start = lines.indexWhere((l) => l.startsWith('<<<< CODE_UNIT_START'));
  var end = lines.indexWhere((l) => l.startsWith('<<<< CODE_UNIT_END'));
  return lines.sublist(start + 1, end).join('\n');
}

/// A Go program that is parsed, executed, and translated+re-executed in every
/// [translateTargets] language, asserting identical observable output.
class _GoCase {
  final String name;
  final String source;
  final List<Object?> expectedOutput;
  final String? className;
  final List positionalParameters;
  final List<String> translateTargets;

  const _GoCase(
    this.name,
    this.source,
    this.expectedOutput, {
    this.className,
    this.positionalParameters = const [],
    this.translateTargets = const ['dart', 'go'],
  });
}

// Portable programs: only constructs whose semantics are identical across Dart,
// Java and Go (no integer division, fields written before read), so the
// translated source must produce exactly the same output.
const _portableCases = <_GoCase>[
  _GoCase(
    'control flow: if / else-if / else',
    r'''
func classify(n int) string {
  if n < 0 {
    return "neg"
  } else if n == 0 {
    return "zero"
  } else {
    return "pos"
  }
}

func run() {
  fmt.Println(classify(-3))
  fmt.Println(classify(0))
  fmt.Println(classify(8))
}
''',
    ['neg', 'zero', 'pos'],
  ),
  _GoCase(
    'loops: while + for-range over slice',
    r'''
type C struct {
}

func (o *C) run() {
  sum := 0
  i := 1
  for i <= 5 {
    sum = sum + i
    i = i + 1
  }
  fmt.Println("sum=" + sum)
  items := []int{10, 20, 30}
  total := 0
  for _, x := range items {
    total = total + x
  }
  fmt.Println("total=" + total)
}
''',
    ['sum=15', 'total=60'],
    className: 'C',
  ),
  _GoCase(
    'c-style for loop',
    r'''
type C struct {
}

func (o *C) run(n int) {
  total := 0
  for i := 0; i < n; i = i + 1 {
    total = total + i
  }
  fmt.Println("total=" + total)
}
''',
    ['total=10'],
    className: 'C',
    positionalParameters: [5],
  ),
  _GoCase(
    'strings: concatenation',
    r'''
func greet(name string) string {
  return "Hello, " + name + "!"
}

func run() {
  who := "Go"
  fmt.Println(greet(who))
  x := 42
  fmt.Println("x is " + x + " doubled " + (x * 2))
}
''',
    ['Hello, Go!', 'x is 42 doubled 84'],
  ),
  _GoCase(
    'recursion: factorial',
    r'''
func fact(n int) int {
  if n <= 1 {
    return 1
  }
  return n * fact(n - 1)
}

func run() {
  fmt.Println("fact5=" + fact(5))
}
''',
    ['fact5=120'],
    // Top-level funcs cannot translate to Java (all Java code lives in a class).
    translateTargets: ['dart', 'go'],
  ),
  _GoCase(
    'struct: methods + nested receiver calls',
    r'''
type Calc struct {
}

func (o *Calc) square(n int) int {
  return n * n
}

func (o *Calc) cube(n int) int {
  return n * o.square(n)
}

func (o *Calc) run() {
  fmt.Println("square=" + o.square(9))
  fmt.Println("cube=" + o.cube(3))
}
''',
    ['square=81', 'cube=27'],
    className: 'Calc',
    translateTargets: ['dart', 'java', 'go'],
  ),
  _GoCase(
    'struct: field written then read',
    r'''
type Acc struct {
  total int
}

func (o *Acc) run(a int, b int) {
  o.total = a + b
  fmt.Println("total=" + o.total)
}
''',
    ['total=30'],
    className: 'Acc',
    positionalParameters: [10, 20],
    translateTargets: ['dart', 'java', 'go'],
  ),
];

void main() {
  group('Go parse + execute', () {
    for (var c in _portableCases) {
      test(c.name, () async {
        var output = await _run(
          'go',
          c.source,
          className: c.className,
          positionalParameters: c.positionalParameters,
        );
        expect(output, equals(c.expectedOutput));
      });
    }

    test('arithmetic + comparison + logic', () async {
      var output = await _run('go', r'''
func run() {
  a := 7
  b := 3
  fmt.Println("add=" + (a + b))
  fmt.Println("sub=" + (a - b))
  fmt.Println("mul=" + (a * b))
  fmt.Println("mod=" + (a % b))
  fmt.Println("lt=" + (a < b))
  fmt.Println("ge=" + (a >= b))
}
''');
      expect(
        output,
        equals(['add=10', 'sub=4', 'mul=21', 'mod=1', 'lt=false', 'ge=true']),
      );
    });

    test('bitwise operators', () async {
      var ret = await _call(
        'go',
        r'''
func f(a int, b int) int {
  return ((a & b) | (a ^ b)) + (a << 1) + (a >> 1)
}
''',
        'f',
        positionalParameters: [6, 3],
      );
      expect(ret.getValueNoContext(), equals(22));
    });

    test('switch (no fall-through)', () async {
      var ret = await _call(
        'go',
        r'''
func f(x int) int {
  r := 0
  switch x {
  case 1:
    r = 10
  case 2:
    r = 20
  default:
    r = 99
  }
  return r
}
''',
        'f',
        positionalParameters: [2],
      );
      expect(ret.getValueNoContext(), equals(20));
    });

    test('closure captured and invoked', () async {
      var ret = await _call(
        'go',
        r'''
func f(a int) int {
  double := func(x int) int {
    return x * 2
  }
  return double(a) + 1
}
''',
        'f',
        positionalParameters: [20],
      );
      expect(ret.getValueNoContext(), equals(41));
    });

    test('function returning String', () async {
      var ret = await _call(
        'go',
        r'''
func greet(name string) string {
  return "Hi " + name
}
''',
        'greet',
        positionalParameters: ['Go'],
      );
      expect(ret.getValueNoContext(), equals('Hi Go'));
    });
  });

  group('Go translate + re-execute', () {
    for (var c in _portableCases) {
      for (var target in c.translateTargets) {
        test('${c.name} -> $target', () async {
          var generated = await _translate('go', c.source, target);
          var code = _extractCodeUnit(generated);

          var output = await _run(
            target,
            code,
            className: c.className,
            positionalParameters: c.positionalParameters,
          );
          expect(
            output,
            equals(c.expectedOutput),
            reason: 'Translated $target output mismatch',
          );
        });
      }
    }

    test('Go -> Dart emits idiomatic Dart', () async {
      var dart = await _translate('go', _portableCases[0].source, 'dart');
      expect(dart, contains('String classify(int n)'));
      expect(dart, contains('void run()'));
    });

    test('Go -> Go round-trip emits idiomatic Go', () async {
      var go = await _translate('go', _portableCases[5].source, 'go');
      expect(go, contains('package main'));
      expect(go, contains('type Calc struct'));
      expect(go, contains('func (o *Calc) square(n int) int'));
    });

    test('Go struct -> Java emits a class with typed methods', () async {
      var java = await _translate('go', _portableCases[5].source, 'java');
      expect(java, contains('class Calc'));
      expect(java, contains('int square(int n)'));
      expect(java, contains('int cube(int n)'));
    });
  });

  // Cross-language into Go: other languages regenerate as idiomatic Go.
  group('into Go (translate from other languages)', () {
    test('Kotlin class -> Go struct + receiver method', () async {
      const kt = r'''
class Greeter {
  fun greet(name: String, count: Int) {
    val msg = "Hello " + name + ", you have " + count + " messages."
    println(msg)
  }
}
''';
      var go = await _translate('kotlin', kt, 'go');
      expect(go, contains('type Greeter struct'));
      expect(go, contains('func (o *Greeter) greet(name string, count int)'));
      expect(go, contains('fmt.Println(msg)'));
      expect(go, contains('import "fmt"'));
    });

    test('Dart function -> Go func with typed params', () async {
      const dart = r'''
int add(int a, int b) {
  return a + b;
}
''';
      var go = await _translate('dart', dart, 'go');
      expect(go, contains('func add(a int, b int) int'));
    });

    test('Go slice + map literals translate to Dart', () async {
      const src = r'''
func build() int {
  xs := []int{1, 2, 3}
  m := map[string]int{"a": 1, "b": 2}
  return xs[0] + m["b"]
}
''';
      var dart = await _translate('go', src, 'dart');
      expect(dart, contains('build()'));
      var ret = await _call('go', src, 'build');
      expect(ret.getValueNoContext(), equals(3));
    });
  });

  // Exercises the Go-specific code-generation idioms that come from other
  // languages' AST shapes: struct factory constructors, the ternary IIFE,
  // prefix bitwise-NOT, `nil`, `map[...]...` literals and `+`-based string
  // interpolation.
  group('Go idiom generation (from other languages)', () {
    test('Dart class + constructor -> Go struct + factory', () async {
      const dart = r'''
class Point {
  int x;
  int y = 7;
  Point(int a, int b) {
    this.x = a;
    this.y = b;
  }
  int sum() {
    return this.x + this.y;
  }
}
''';
      var go = _extractCodeUnit(await _translate('dart', dart, 'go'));
      expect(go, contains('type Point struct'));
      expect(go, contains('x int'));
      expect(go, contains('func NewPoint(a int, b int) *Point'));
      expect(go, contains(r'o := &Point{}'));
      expect(go, contains('o.y = 7')); // field initializer moved to factory
      expect(go, contains('o.x = a'));
      expect(go, contains('return o'));
      expect(go, contains('func (o *Point) sum() int'));
    });

    test('Dart class field initializer -> Go default factory', () async {
      const dart = r'''
class Counter {
  int n = 5;
  int get() {
    return this.n;
  }
}
''';
      var go = _extractCodeUnit(await _translate('dart', dart, 'go'));
      expect(go, contains('func NewCounter() *Counter'));
      expect(go, contains('o.n = 5'));
    });

    test('Dart ternary -> Go IIFE (and runs)', () async {
      const dart = r'''
int pick(int a) {
  var r = a > 5 ? 100 : 1;
  return r;
}
''';
      var go = _extractCodeUnit(await _translate('dart', dart, 'go'));
      expect(
        go,
        contains('func() any { if a > 5 { return 100 } else { return 1 } }()'),
      );
      var ret = await _call('go', go, 'pick', positionalParameters: [10]);
      expect(ret.getValueNoContext(), equals(100));
    });

    test('Dart bitwise-NOT -> Go prefix `^` (and runs)', () async {
      const dart = r'''
int f(int a) {
  return ~a;
}
''';
      var go = _extractCodeUnit(await _translate('dart', dart, 'go'));
      expect(go, contains('return ^a'));
      var ret = await _call('go', go, 'f', positionalParameters: [6]);
      expect(ret.getValueNoContext(), equals(-7)); // ^6 == -7
    });

    test('Dart null -> Go nil', () async {
      const dart = r'''
int f() {
  return null;
}
''';
      var go = _extractCodeUnit(await _translate('dart', dart, 'go'));
      expect(go, contains('return nil'));
    });

    test('Go map literal round-trips through Go generation', () async {
      const src = r'''
func build() int {
  m := map[string]int{"a": 1, "b": 2}
  return m["b"]
}
''';
      var go = _extractCodeUnit(await _translate('go', src, 'go'));
      expect(go, contains('map[string]int{'));
      var ret = await _call('go', go, 'build');
      expect(ret.getValueNoContext(), equals(2));
    });

    test('Kotlin string templates -> Go `+` concatenation', () async {
      const kt = r'''
fun f(x: Int): String {
  val a = "$x"
  val b = "${x * 2}"
  return a + "=" + b
}
''';
      var go = _extractCodeUnit(await _translate('kotlin', kt, 'go'));
      // Lone `"$x"` -> `"" + x`; `"${x * 2}"` -> `"" + (x * 2)`.
      expect(go, contains('"" + x'));
      expect(go, contains('"" + (x * 2)'));
    });

    test('runner copy() yields a Go runner', () {
      var vm = ApolloVM();
      var runner = vm.createRunner('go')!;
      var copy = runner.copy();
      expect(copy.language, equals('go'));
    });
  });
}
