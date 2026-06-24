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

/// Loads [source] in [language] and translates it to [targetLanguage] source.
Future<String> _translate(
  String language,
  String source,
  String targetLanguage,
) async {
  var vm = ApolloVM();
  var codeUnit = SourceCodeUnit(language, source, id: 'test');
  await vm.loadCodeUnit(codeUnit);

  var storage = vm.generateAllCodeIn(targetLanguage);
  return (await storage.writeAllSources()).toString();
}

void main() {
  group('Kotlin', () {
    const kotlinTopLevel = r'''
fun sum(a: Int, b: Int): Int {
  return a + b
}

fun main() {
  val x = 10
  val y = 32
  val total = sum(x, y)
  println("total: $total")
  val msg = "x=" + x
  println(msg)
  var i = 0
  while (i < 3) {
    println("i=${i}")
    i += 1
  }
  val list = mutableListOf(1, 2, 3)
  for (e in list) {
    println("e=$e")
  }
}
''';

    const kotlinClass = r'''
class Calc {
  fun square(n: Int): Int {
    return n * n
  }

  fun main() {
    val r = square(9)
    println("square=$r")
  }
}
''';

    const expectedTopLevelOutput = [
      'total: 42',
      'x=10',
      'i=0',
      'i=1',
      'i=2',
      'e=1',
      'e=2',
      'e=3',
    ];

    test('parse + run top-level functions', () async {
      var output = await _run('kotlin', kotlinTopLevel);
      expect(output, equals(expectedTopLevelOutput));
    });

    test('parse + run class method', () async {
      var output = await _run(
        'kotlin',
        kotlinClass,
        className: 'Calc',
      );
      expect(output, equals(['square=81']));
    });

    test('translate Kotlin -> Dart and run', () async {
      var dartSource = await _translate('kotlin', kotlinTopLevel, 'dart');
      expect(dartSource, contains('int sum(int a, int b)'));
      expect(dartSource, contains('void main()'));

      // The generated Dart must run with the same observable behavior.
      var dartCode = _extractCodeUnit(dartSource);
      var output = await _run('dart', dartCode);
      expect(output, equals(expectedTopLevelOutput));
    });

    test('regenerate Kotlin -> Kotlin and run (round-trip)', () async {
      var kotlinSource = await _translate('kotlin', kotlinTopLevel, 'kotlin');
      expect(kotlinSource, contains('fun sum(a: Int, b: Int): Int'));
      expect(kotlinSource, contains('fun main()'));

      var kotlinCode = _extractCodeUnit(kotlinSource);
      var output = await _run('kotlin', kotlinCode);
      expect(output, equals(expectedTopLevelOutput));
    });

    test('translate Kotlin class -> Java / Dart', () async {
      var javaSource = await _translate('kotlin', kotlinClass, 'java');
      expect(javaSource, contains('class Calc'));
      expect(javaSource, contains('int square(int n)'));

      var dartSource = await _translate('kotlin', kotlinClass, 'dart');
      expect(dartSource, contains('class Calc'));
      expect(dartSource, contains('int square(int n)'));
    });
  });
}

/// Extracts the raw source of the single generated code unit from the
/// ApolloVM "sources" envelope produced by [writeAllSources].
String _extractCodeUnit(String allSources) {
  var lines = allSources.split('\n');
  var start = lines.indexWhere((l) => l.startsWith('<<<< CODE_UNIT_START'));
  var end = lines.indexWhere((l) => l.startsWith('<<<< CODE_UNIT_END'));
  return lines.sublist(start + 1, end).join('\n');
}
