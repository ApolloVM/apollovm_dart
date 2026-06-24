// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Loads [source] in [language], runs an entry point and returns the captured
/// `print` output.
Future<List<Object?>> _run(
  String language,
  String source, {
  String function = 'main',
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

/// A Kotlin program that is parsed, executed, and translated+re-executed in
/// every [translateTargets] language, asserting identical observable output.
class _KtCase {
  final String name;
  final String source;
  final List<Object?> expectedOutput;
  final String? className;
  final List<String> translateTargets;

  const _KtCase(
    this.name,
    this.source,
    this.expectedOutput, {
    this.className,
    this.translateTargets = const ['dart', 'kotlin'],
  });
}

// Portable programs: only use constructs whose semantics are identical across
// Dart, Java and Kotlin (no integer division, no instance-field mutation), so
// the translated source must produce exactly the same output.
const _portableCases = <_KtCase>[
  _KtCase(
    'control flow: if / else-if / logic',
    r'''
fun classify(n: Int): String {
  if (n < 0) {
    return "neg"
  } else if (n == 0) {
    return "zero"
  } else {
    return "pos"
  }
}

fun main() {
  println(classify(-3))
  println(classify(0))
  println(classify(8))
  val t = true
  val f = false
  println("and=${t && f}")
  println("or=${t || f}")
  println("not=${!t}")
}
''',
    ['neg', 'zero', 'pos', 'and=false', 'or=true', 'not=false'],
  ),
  _KtCase(
    'loops: while + for-in over list',
    r'''
fun main() {
  var sum = 0
  var i = 1
  while (i <= 5) {
    sum += i
    i += 1
  }
  println("sum=$sum")

  val items = mutableListOf(10, 20, 30)
  var total = 0
  for (x in items) {
    total += x
  }
  println("total=$total")
}
''',
    ['sum=15', 'total=60'],
  ),
  _KtCase(
    'strings: concatenation + templates',
    r'''
fun greet(name: String): String {
  return "Hello, " + name + "!"
}

fun main() {
  val who = "Kotlin"
  println(greet(who))
  val x = 42
  println("x is ${x} and doubled is ${x * 2}")
}
''',
    ['Hello, Kotlin!', 'x is 42 and doubled is 84'],
  ),
  _KtCase(
    'recursion: factorial',
    r'''
fun fact(n: Int): Int {
  if (n <= 1) {
    return 1
  }
  return n * fact(n - 1)
}

fun main() {
  println("fact5=${fact(5)}")
}
''',
    ['fact5=120'],
  ),
  _KtCase(
    'class: methods + nested calls',
    r'''
class Calc {
  fun square(n: Int): Int {
    return n * n
  }

  fun cube(n: Int): Int {
    return n * square(n)
  }

  fun main() {
    println("square=${square(9)}")
    println("cube=${cube(3)}")
  }
}
''',
    ['square=81', 'cube=27'],
    className: 'Calc',
    translateTargets: ['dart', 'java', 'kotlin'],
  ),
  _KtCase(
    'class: field read in method',
    r'''
class Greeter {
  var name: String = "World"

  fun main() {
    println("Hello " + name)
  }
}
''',
    ['Hello World'],
    className: 'Greeter',
    translateTargets: ['dart', 'java', 'kotlin'],
  ),
];

void main() {
  group('Kotlin parse + execute', () {
    for (var c in _portableCases) {
      test(c.name, () async {
        var output = await _run('kotlin', c.source, className: c.className);
        expect(output, equals(c.expectedOutput));
      });
    }

    test('arithmetic operators (Kotlin int/double semantics)', () async {
      var output = await _run('kotlin', r'''
fun main() {
  val a = 7
  val b = 3
  println("add=${a + b}")
  println("sub=${a - b}")
  println("mul=${a * b}")
  println("div=${a / b}")
  println("mod=${a % b}")
  println("dbl=${7.0 / 2.0}")
}
''');
      expect(
        output,
        equals(['add=10', 'sub=4', 'mul=21', 'div=2', 'mod=1', 'dbl=3.5']),
      );
    });

    test('unary minus and logical negation', () async {
      var output = await _run('kotlin', r'''
fun main() {
  val a = -5
  println("neg=${-a}")
  val b = true
  println("not=${!b}")
}
''');
      expect(output, equals(['neg=5', 'not=false']));
    });

    test('function return value', () async {
      var ret = await _call(
        'kotlin',
        r'''
fun fact(n: Int): Int {
  if (n <= 1) {
    return 1
  }
  return n * fact(n - 1)
}
''',
        'fact',
        positionalParameters: [5],
      );

      expect(ret.getValueNoContext(), equals(120));
    });

    test('function returning String', () async {
      var ret = await _call(
        'kotlin',
        r'''
fun greet(name: String): String {
  return "Hi " + name
}
''',
        'greet',
        positionalParameters: ['Kt'],
      );

      expect(ret.getValueNoContext(), equals('Hi Kt'));
    });
  });

  group('Kotlin translate + re-execute', () {
    for (var c in _portableCases) {
      for (var target in c.translateTargets) {
        test('${c.name} -> $target', () async {
          var generated = await _translate('kotlin', c.source, target);
          var code = _extractCodeUnit(generated);

          var output = await _run(target, code, className: c.className);
          expect(
            output,
            equals(c.expectedOutput),
            reason: 'Translated $target output mismatch',
          );
        });
      }
    }

    test('Kotlin -> Dart emits idiomatic Dart', () async {
      var dart = await _translate('kotlin', _portableCases[0].source, 'dart');
      expect(dart, contains('String classify(int n)'));
      expect(dart, contains('void main()'));
    });

    test('Kotlin -> Kotlin round-trip emits idiomatic Kotlin', () async {
      var kotlin = await _translate(
        'kotlin',
        _portableCases[3].source, // recursion
        'kotlin',
      );
      expect(kotlin, contains('fun fact(n: Int): Int'));
      expect(kotlin, contains(r'${fact(5)}'));
    });

    test('Kotlin class -> Java emits a class with typed methods', () async {
      var java = await _translate('kotlin', _portableCases[4].source, 'java');
      expect(java, contains('class Calc'));
      expect(java, contains('int square(int n)'));
      expect(java, contains('int cube(int n)'));
    });
  });

  // Map literals parse and translate; runtime map support is a separate,
  // pre-existing VM concern (Dart map literals do not execute either), so
  // these only assert parsing + code generation.
  group('Kotlin maps (parse + translate)', () {
    const mapSource = r'''
fun build(): Map<String, Int> {
  return mapOf("a" to 1, "b" to 2)
}
''';

    test('translate map literal -> Dart', () async {
      var dart = await _translate('kotlin', mapSource, 'dart');
      expect(dart, contains('build()'));
      expect(dart, contains("'a': 1"));
      expect(dart, contains("'b': 2"));
    });

    test('translate map literal -> Kotlin', () async {
      var kotlin = await _translate('kotlin', mapSource, 'kotlin');
      expect(kotlin, contains('mutableMapOf('));
      expect(kotlin, contains('"a" to 1'));
      expect(kotlin, contains('"b" to 2'));
    });
  });
}
