// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

@Tags(['apollo', 'dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Loads [source] in [language], runs an entry point and returns the captured
/// `print` output.
Future<List<Object?>> _run(
  String source, {
  String language = 'apollo',
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
  String source,
  String function, {
  String language = 'apollo',
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
  String source,
  String targetLanguage, {
  String language = 'apollo',
}) async {
  var vm = ApolloVM();
  await vm.loadCodeUnit(SourceCodeUnit(language, source, id: 'test'));
  var storage = vm.generateAllCodeIn(targetLanguage);
  return (await storage.writeAllSources()).toString();
}

/// Whether [source] parses/loads in [language] without a syntax error.
Future<bool> _loads(String source, {String language = 'apollo'}) async {
  var vm = ApolloVM();
  try {
    return await vm.loadCodeUnit(SourceCodeUnit(language, source, id: 'test'));
  } catch (_) {
    return false;
  }
}

void main() {
  group('Apollo parse + execute', () {
    test('paren-less if / else-if / else', () async {
      var output = await _run(r'''
String classify(Int n) {
  if n < 0 {
    return "neg"
  } else if n == 0 {
    return "zero"
  } else {
    return "pos"
  }
}

run() {
  print(classify(-3))
  print(classify(0))
  print(classify(8))
}
''');
      expect(output, equals(['neg', 'zero', 'pos']));
    });

    test('parenthesized conditions still parse (Dart-compatible)', () async {
      var output = await _run(r'''
run() {
  if (1 < 2) { print("a") }
  var i = 0
  while (i < 2) { print("b") i = i + 1 }
}
''');
      expect(output, equals(['a', 'b', 'b']));
    });

    test('while loop + string interpolation, no semicolons', () async {
      var output = await _run(r'''
run() {
  var sum = 0
  var i = 1
  while i <= 5 {
    sum = sum + i
    i = i + 1
  }
  print("sum=$sum")
}
''');
      expect(output, equals(['sum=15']));
    });

    test('switch without parentheses', () async {
      var ret = await _call(
        r'''
Int f(Int x) {
  var r = 0
  switch x {
    case 1: r = 10 break
    case 2: r = 20 break
    default: r = 99
  }
  return r
}
''',
        'f',
        positionalParameters: [2],
      );
      expect(ret.getValueNoContext(), equals(20));
    });

    test('try / catch (paren-less, untyped)', () async {
      var output = await _run(r'''
run() {
  try {
    throw "boom"
  } catch error {
    print("caught: $error")
  }
}
''');
      expect(output, equals(['caught: boom']));
    });

    test('typed catch (paren-less)', () async {
      var output = await _run(r'''
run() {
  try {
    throw "io"
  } catch String error {
    print("string error: $error")
  }
}
''');
      expect(output, equals(['string error: io']));
    });

    test('parenthesized catch still parses', () async {
      var output = await _run(r'''
run() {
  try { throw "x" } catch (error) { print("c=$error") }
}
''');
      expect(output, equals(['c=x']));
    });

    test('all Dart string forms', () async {
      var output = await _run(r'''
run() {
  var who = "S"
  print('single')
  print("double")
  print("Hi $who")
  print("Hi ${who}!")
}
''');
      expect(output, equals(['single', 'double', 'Hi S', 'Hi S!']));
    });

    test('adjacent string concatenation', () async {
      var ret = await _call(r'''
String join() {
  return "Hello "
      "World"
}
''', 'join');
      expect(ret.getValueNoContext(), equals('Hello World'));
    });

    test('raw string', () async {
      var ret = await _call(r'''
String p() {
  return r'C:\temp\file.txt'
}
''', 'p');
      expect(ret.getValueNoContext(), equals(r'C:\temp\file.txt'));
    });

    test('capitalized primitive types', () async {
      var ret = await _call(
        r'''
Int add(Int a, Int b) {
  return a + b
}
''',
        'add',
        positionalParameters: [4, 5],
      );
      expect(ret.getValueNoContext(), equals(9));
    });

    test('leading async + await', () async {
      var output = await _run(r'''
async Int loadUser(Int id) {
  return id * 2
}

async run() {
  var u = await loadUser(21)
  print("user=$u")
}
''');
      expect(output, equals(['user=42']));
    });

    test('class: return-type-less method + typed method', () async {
      var output = await _run(r'''
class Calc {
  Int square(Int n) { return n * n }
  run() { print("sq=" + square(9)) }
}
''', className: 'Calc');
      expect(output, equals(['sq=81']));
    });

    test('class: field + constructor', () async {
      var output = await _run(
        r'''
class Greeter {
  String name

  Greeter(String n) {
    this.name = n
  }

  static run() {
    var g = Greeter("World")
    print("Hi " + g.name)
  }
}
''',
        className: 'Greeter',
        function: 'run',
      );
      expect(output, equals(['Hi World']));
    });

    test('recursion: factorial', () async {
      var ret = await _call(
        r'''
Int fact(Int n) {
  if n <= 1 { return 1 }
  return n * fact(n - 1)
}
''',
        'fact',
        positionalParameters: [5],
      );
      expect(ret.getValueNoContext(), equals(120));
    });
  });

  group('Apollo for loops', () {
    // sum(k for k in range) via each range-`for` form.
    Future<int> sum(String header, {int n = 3}) async {
      var ret = await _call(
        '''
Int f(Int n) {
  var s = 0
  $header {
    s = s + i
  }
  return s
}
''',
        'f',
        positionalParameters: [n],
      );
      return ret.getValueNoContext() as int;
    }

    test('ascending inclusive `for i++ from 0..n`', () async {
      expect(await sum('for i++ from 0..n', n: 3), equals(0 + 1 + 2 + 3));
    });

    test('descending inclusive `for i-- from n..0`', () async {
      expect(await sum('for i-- from n..0', n: 3), equals(3 + 2 + 1 + 0));
    });

    test('ascending exclusive upper `for i++ from 0..<n`', () async {
      expect(await sum('for i++ from 0..<n', n: 3), equals(0 + 1 + 2));
    });

    test('descending exclusive lower `for i-- from n..>0`', () async {
      expect(await sum('for i-- from n..>0', n: 3), equals(3 + 2 + 1));
    });

    test('ascending custom step `for i += 2 from 0..n`', () async {
      expect(await sum('for i += 2 from 0..n', n: 6), equals(0 + 2 + 4 + 6));
    });

    test('descending custom step `for i -= 2 from n..0`', () async {
      expect(await sum('for i -= 2 from n..0', n: 6), equals(6 + 4 + 2 + 0));
    });

    test('classic `for` with parentheses still works', () async {
      expect(
        await sum('for (var i = 0; i <= n; i++)', n: 3),
        equals(0 + 1 + 2 + 3),
      );
    });

    test('classic `for` without parentheses is a syntax error', () async {
      Object? error;
      try {
        await _run('run() { for var i = 0; i < 3; i++ { print(i) } }\n');
      } catch (e) {
        error = e;
      }
      expect(error, isNotNull);
      expect(
        error.toString(),
        contains('Classic for loops require parentheses'),
      );
    });

    test('range `for` round-trips back to the range sugar', () async {
      var apollo = _extractCodeUnit(
        await _translate(r'''
run(Int n) {
  for i++ from 0..n { print(i) }
}
''', 'apollo'),
      );
      expect(apollo, contains('for i++ from 0..n'));
      expect(apollo, isNot(contains('for (')));
    });

    test('a canonical classic `for` is regenerated as range sugar', () async {
      var apollo = _extractCodeUnit(
        await _translate(r'''
run(Int n) {
  for (var i = 0; i < n; i++) { print(i) }
}
''', 'apollo'),
      );
      expect(apollo, contains('for i++ from 0..<n'));
    });

    test('a typed/non-counting classic `for` stays classic', () async {
      // A typed loop variable can't be expressed by the range sugar.
      var typed = _extractCodeUnit(
        await _translate(r'''
run(Int n) {
  for (Int i = 0; i <= n; i++) { print(i) }
}
''', 'apollo'),
      );
      expect(typed, contains('for (Int i = 0'));
      // A non-unit, non-additive step is not a counting loop.
      var multiplic = _extractCodeUnit(
        await _translate(r'''
run(Int n) {
  for (var i = 1; i <= n; i = i * 2) { print(i) }
}
''', 'apollo'),
      );
      expect(multiplic, contains('for (var i = 1'));
      expect(multiplic, contains('i = i * 2'));
    });
  });

  group('Apollo language features', () {
    test('break / continue inside a range for', () async {
      var ret = await _call(
        r'''
Int f(Int n) {
  var s = 0
  for i++ from 0..n {
    if i == 2 { continue }
    if i == 5 { break }
    s = s + i
  }
  return s
}
''',
        'f',
        positionalParameters: [10],
      );
      // 0 + 1 + (skip 2) + 3 + 4, then break at 5 => 8.
      expect(ret.getValueNoContext(), equals(8));
    });

    test('nested range for', () async {
      var ret = await _call(r'''
Int f() {
  var s = 0
  for i++ from 1..3 {
    for j++ from 1..3 {
      s = s + i * j
    }
  }
  return s
}
''', 'f');
      expect(ret.getValueNoContext(), equals(36)); // (1+2+3)^2
    });

    test('do / while', () async {
      var ret = await _call(r'''
Int f() {
  var i = 0
  var s = 0
  do {
    s = s + i
    i = i + 1
  } while i < 3
  return s
}
''', 'f');
      expect(ret.getValueNoContext(), equals(3));
    });

    test('ternary conditional', () async {
      var ret = await _call(
        'Int f(Int a) { return a > 5 ? 100 : 1 }\n',
        'f',
        positionalParameters: [9],
      );
      expect(ret.getValueNoContext(), equals(100));
    });

    test('bitwise + shift operators', () async {
      var ret = await _call(
        'Int f(Int a, Int b) { return ((a & b) | (a ^ b)) + (a << 1) + (a >> 1) }\n',
        'f',
        positionalParameters: [6, 3],
      );
      expect(ret.getValueNoContext(), equals(22));
    });

    test('unary negation', () async {
      var ret = await _call(
        'Int f(Int a) { return -a }\n',
        'f',
        positionalParameters: [7],
      );
      expect(ret.getValueNoContext(), equals(-7));
    });

    test('closure captured and invoked', () async {
      var ret = await _call(
        r'''
Int f(Int a) {
  var double = (Int x) { return x * 2 }
  return double(a) + 1
}
''',
        'f',
        positionalParameters: [20],
      );
      expect(ret.getValueNoContext(), equals(41));
    });

    test('list literal + index access', () async {
      var ret = await _call(
        'Int f() { var xs = [10, 20, 30] return xs[0] + xs[2] }\n',
        'f',
      );
      expect(ret.getValueNoContext(), equals(40));
    });

    test('map literal + key access', () async {
      var ret = await _call(
        'Int f() { var m = {"a": 1, "b": 2} return m["b"] }\n',
        'f',
      );
      expect(ret.getValueNoContext(), equals(2));
    });

    test('for-in over a list literal', () async {
      var output = await _run(r'''
run() {
  for Int x in [1, 2, 3] {
    print(x)
  }
}
''');
      expect(output, equals([1, 2, 3]));
    });

    test('getter', () async {
      var output = await _run(r'''
class C {
  Int x = 10
  Int get twice => x * 2
  static run() {
    var c = C()
    print(c.twice)
  }
}
''', className: 'C');
      expect(output, equals([20]));
    });

    test('named / default parameters', () async {
      var ret = await _call(
        'Int area({Int w = 2, Int h = 3}) { return w * h }\n',
        'area',
      );
      expect(ret.getValueNoContext(), equals(6));
    });

    test('enum + switch on enum value', () async {
      var output = await _run(r'''
enum Role { admin, user }

String label(Role r) {
  switch r {
    case Role.admin: return "A"
    case Role.user: return "U"
  }
  return "?"
}

run() {
  print(label(Role.admin))
  print(label(Role.user))
}
''');
      expect(output, equals(['A', 'U']));
    });

    test('rich enum body parses without semicolons', () async {
      // The enhanced-enum body (fields + a body-less `const` constructor) parses
      // even though Apollo statement semicolons are optional.
      expect(
        await _loads(r'''
enum Planet {
  earth(5.97, 6371),
  mars(0.642, 3389)
  ;

  Double mass
  Double radius

  const Planet(Double mass, Double radius)

  Double surfaceGravity() {
    return mass / (radius * radius)
  }
}
'''),
        isTrue,
      );
    });
  });

  group('Apollo async spellings (Dart-compatibility)', () {
    // The canonical form is a leading `async` with the unwrapped return type;
    // the two Dart-flavoured spellings are accepted and normalized to it.
    const forms = {
      'canonical (async User)': 'async User foo(Int id) { return id }',
      'leading Future (async Future<User>)':
          'async Future<User> foo(Int id) { return id }',
      'trailing (Future<User> ... async)':
          'Future<User> foo(Int id) async { return id }',
      'trailing (User ... async)': 'User foo(Int id) async { return id }',
    };

    for (var e in forms.entries) {
      test('${e.key} loads and regenerates as `async User`', () async {
        expect(await _loads('${e.value}\n'), isTrue);
        var apollo = _extractCodeUnit(
          await _translate('${e.value}\n', 'apollo'),
        );
        expect(apollo, contains('async User foo(Int id)'));
        // A Future<T> return type is unwrapped to T on an async function.
        expect(apollo, isNot(contains('Future')));
      });
    }

    test('leading-async form is the canonical / regenerated one', () async {
      var apollo = _extractCodeUnit(
        await _translate('async run() { print("x") }\n', 'apollo'),
      );
      expect(apollo, contains('async dynamic run()'));
    });

    test(
      'trailing `async` (Dart form) is accepted for a plain function',
      () async {
        expect(await _loads('main() async {\n}\n'), isTrue);
        var output = await _run('run() async { print("x") }\n');
        expect(output, equals(['x']));
      },
    );
  });

  group('Apollo translate + re-execute', () {
    test('Apollo -> Apollo round-trip runs identically', () async {
      const src = r'''
String classify(Int n) {
  if n < 0 { return "neg" } else { return "pos" }
}

run() {
  print(classify(-3))
  print(classify(8))
}
''';
      var generated = await _translate(src, 'apollo');
      var code = _extractCodeUnit(generated);
      var output = await _run(code);
      expect(output, equals(['neg', 'pos']));
    });

    test('Apollo -> Dart emits trailing async + lowercase types', () async {
      var dart = _extractCodeUnit(
        await _translate(r'''
async Int loadUser(Int id) {
  return id * 2
}
''', 'dart'),
      );
      expect(dart, contains('int loadUser(int id) async'));
    });

    test('Apollo -> Dart translates capitalized types', () async {
      var dart = _extractCodeUnit(
        await _translate(r'''
Double half(Double n) {
  return n / 2
}

Bool positive(Int n) {
  return n > 0
}
''', 'dart'),
      );
      expect(dart, contains('double half(double n)'));
      expect(dart, contains('bool positive(int n)'));
    });

    test('Apollo -> Dart runs correctly', () async {
      var dart = _extractCodeUnit(
        await _translate(r'''
Int addOne(Int n) {
  return n + 1
}
''', 'dart'),
      );
      var ret = await _call(
        dart,
        'addOne',
        language: 'dart',
        positionalParameters: [41],
      );
      expect(ret.getValueNoContext(), equals(42));
    });

    test('Dart -> Apollo emits leading async + capitalized types', () async {
      var apollo = _extractCodeUnit(
        await _translate(
          r'''
int loadUser(int id) async {
  return id * 2;
}
''',
          'apollo',
          language: 'dart',
        ),
      );
      expect(apollo, contains('async Int loadUser(Int id)'));
    });

    test('runner copy() yields an Apollo runner', () {
      var vm = ApolloVM();
      var runner = vm.createRunner('apollo')!;
      var copy = runner.copy();
      expect(copy.language, equals('apollo'));
    });

    test('.apollo file extension maps to the apollo language', () {
      expect(
        ApolloVM.parseLanguageFromFilePathExtension('main.apollo'),
        equals('apollo'),
      );
    });
  });

  group('Apollo statement surface', () {
    test('a function declared inside a body', () async {
      var output = await _run(r'''
run() {
  Int twice(Int x) { return x * 2 }
  print(twice(21))
}
''');
      expect(output, equals([42]));
    });

    test('final and const locals, typed and untyped', () async {
      var output = await _run(r'''
run() {
  final Int a = 1
  const Int b = 2
  final c = 3
  const d = 4
  print(a + b + c + d)
}
''');
      expect(output, equals([10]));
    });

    test('a bare `return` leaves the function', () async {
      var output = await _run(r'''
Void guard(Int n) {
  if n > 0 {
    return
  }
  print("negative")
}

run() {
  guard(1)
  guard(-1)
}
''');
      expect(output, equals(['negative']));
    });

    test('try / catch / finally runs the finally block', () async {
      var output = await _run(r'''
run() {
  try {
    print("body")
  } catch e {
    print("caught")
  } finally {
    print("finally")
  }

  try {
    throw "x"
  } catch e {
    print("caught")
  } finally {
    print("finally")
  }
}
''');
      expect(output, equals(['body', 'finally', 'caught', 'finally']));
    });
  });

  group('Apollo expression surface', () {
    test('`null`, `true` and `false` literals', () async {
      var output = await _run(r'''
run() {
  var n = null
  var t = true
  var f = false
  print(n)
  print(t)
  print(f)
}
''');
      expect(output, equals([null, true, false]));
    });

    test('prefix increment and decrement yield the updated value', () async {
      var output = await _run(r'''
run() {
  var i = 1
  print(++i)
  print(--i)
  print(i)
}
''');
      expect(output, equals([2, 1, 1]));
    });

    test('empty list and map literals', () async {
      var output = await _run(r'''
run() {
  var xs = []
  var m = {}
  print(xs)
  print(m)
}
''');
      expect(output, equals([[], {}]));
    });

    test('assigning into a list index and a map key', () async {
      var output = await _run(r'''
run() {
  var xs = [1, 2, 3]
  var m = {"k": 1}
  xs[0] = 9
  m["k"] = 5
  print(xs[0])
  print(m["k"])
}
''');
      expect(output, equals([9, 5]));
    });

    test('a nested list literal is indexed twice', () async {
      var output = await _run(r'''
run() {
  List<List<Int>> grid = [[1, 2], [3, 4]]
  print(grid[0][1])
  print(grid[1][0])
}
''');
      expect(output, equals([2, 3]));
    });

    test('`new` instantiates, and a field can be assigned', () async {
      var output = await _run(r'''
class P {
  Int x
  P(this.x)
}

run() {
  var p = new P(7)
  print(p.x)
  p.x = 8
  print(p.x)
}
''');
      expect(output, equals([7, 8]));
    });

    test('invocations chain across returned instances', () async {
      var output = await _run(r'''
class B {
  Int v
  B(this.v)
  B plus(Int n) { return new B(v + n) }
  Int value() { return v }
}

run() {
  var b = new B(1)
  print(b.plus(2).plus(3).value())
}
''');
      expect(output, equals([6]));
    });
  });

  group('Apollo statement surface: regeneration', () {
    test('the statement surface round-trips and reruns identically', () async {
      var source = r'''
run() {
  Int twice(Int x) { return x * 2 }

  var xs = [1, 2, 3]
  xs[0] = 9

  var m = {"k": 0}
  m["k"] = twice(4)

  var i = 1
  print(++i)
  print(xs[0])
  print(m["k"])

  try {
    throw "x"
  } catch e {
    print(e)
  } finally {
    print("done")
  }
}
''';

      var apollo = _extractCodeUnit(await _translate(source, 'apollo'));

      expect(apollo, contains('Int twice(Int x) {'));
      expect(apollo, contains('xs[0] = 9;'));
      expect(apollo, contains("m['k'] = twice(4);"));
      expect(apollo, contains('print(++i);'));
      expect(apollo, contains('} finally {'));

      expect(await _run(apollo), equals(await _run(source)));
    });
  });
}

/// Extracts the raw source of the single generated code unit from the
/// ApolloVM "sources" envelope produced by `writeAllSources`.
String _extractCodeUnit(String allSources) {
  var lines = allSources.split('\n');
  var start = lines.indexWhere((l) => l.startsWith('<<<< CODE_UNIT_START'));
  var end = lines.indexWhere((l) => l.startsWith('<<<< CODE_UNIT_END'));
  return lines.sublist(start + 1, end).join('\n');
}
