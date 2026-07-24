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
}

/// Extracts the raw source of the single generated code unit from the
/// ApolloVM "sources" envelope produced by `writeAllSources`.
String _extractCodeUnit(String allSources) {
  var lines = allSources.split('\n');
  var start = lines.indexWhere((l) => l.startsWith('<<<< CODE_UNIT_START'));
  var end = lines.indexWhere((l) => l.startsWith('<<<< CODE_UNIT_END'));
  return lines.sublist(start + 1, end).join('\n');
}
