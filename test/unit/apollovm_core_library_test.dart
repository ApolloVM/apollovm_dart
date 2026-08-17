@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Runs the top-level `run()` of [body] and returns its value.
///
/// [body] is the *body* of `run()`, so each case reads as the expression under
/// test rather than as a whole program.
Future<Object?> _run(String body, {bool math = false}) async {
  var src = 'dynamic run() { $body }';
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', src, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source: $src");

  var runner = vm.createRunner('dart', importCorePackageMath: math)!;
  var value = await runner.executeFunction('', 'run');
  return value.getValueNoContext();
}

void main() {
  group('dart:math package', () {
    test('pow, sqrt, exp and log', () async {
      expect(await _run('return pow(2, 10);', math: true), equals(1024));
      expect(await _run('return sqrt(16);', math: true), equals(4.0));
      expect(await _run('return exp(0);', math: true), equals(1.0));
      expect(await _run('return log(1);', math: true), equals(0.0));
    });

    test('trigonometric functions', () async {
      expect(await _run('return sin(0);', math: true), equals(0.0));
      expect(await _run('return cos(0);', math: true), equals(1.0));
      expect(await _run('return tan(0);', math: true), equals(0.0));
      expect(await _run('return asin(0);', math: true), equals(0.0));
      expect(await _run('return atan(0);', math: true), equals(0.0));
      expect(await _run('return atan2(0, 1);', math: true), equals(0.0));

      // acos(1) == 0, avoiding a float literal comparison for acos(0) == pi/2.
      expect(await _run('return acos(1);', math: true), equals(0.0));
    });

    test('abs, min and max', () async {
      expect(await _run('return abs(-3);', math: true), equals(3));
      expect(await _run('return min(2, 7);', math: true), equals(2));
      expect(await _run('return max(2, 7);', math: true), equals(7));
    });

    test('an unknown math function is an error', () async {
      expect(
        () => _run('return nope(1);', math: true),
        throwsA(isA<ApolloVMRuntimeError>()),
      );
    });
  });

  group('core String', () {
    test('length, isEmpty and isNotEmpty as getters', () async {
      expect(await _run("var s = 'abc'; return s.length;"), equals(3));
      expect(await _run("var s = ''; return s.isEmpty;"), isTrue);
      expect(await _run("var s = 'a'; return s.isNotEmpty;"), isTrue);
    });

    test('length, isEmpty and isNotEmpty as methods', () async {
      // Java-style `s.length()` must keep working alongside the getter form.
      expect(await _run("var s = 'abc'; return s.length();"), equals(3));
      expect(await _run("var s = ''; return s.isEmpty();"), isTrue);
      expect(await _run("var s = 'a'; return s.isNotEmpty();"), isTrue);
    });

    test('case conversion and contains', () async {
      expect(await _run("var s = 'aB'; return s.toUpperCase();"), equals('AB'));
      expect(await _run("var s = 'aB'; return s.toLowerCase();"), equals('ab'));
      expect(await _run("var s = 'abc'; return s.contains('b');"), isTrue);
    });

    test('substring, indexOf, lastIndexOf and codeUnitAt', () async {
      expect(await _run("var s = 'abcd'; return s.substring(1, 3);"), 'bc');
      expect(await _run("var s = 'aba'; return s.indexOf('a');"), equals(0));
      expect(
        await _run("var s = 'aba'; return s.lastIndexOf('a');"),
        equals(2),
      );
      expect(await _run("var s = 'A'; return s.codeUnitAt(0);"), equals(65));
    });

    test('startsWith and endsWith', () async {
      expect(await _run("var s = 'abc'; return s.startsWith('ab');"), isTrue);
      expect(await _run("var s = 'abc'; return s.endsWith('bc');"), isTrue);
    });

    test('trim, trimLeft and trimRight', () async {
      expect(await _run("var s = ' a '; return s.trim();"), equals('a'));
      expect(await _run("var s = ' a '; return s.trimLeft();"), equals('a '));
      expect(await _run("var s = ' a '; return s.trimRight();"), equals(' a'));
    });

    test('split, replaceAll and replaceFirst', () async {
      expect(await _run("var s = 'a,b'; return s.split(',');"), ['a', 'b']);
      expect(await _run("var s = 'aa'; return s.replaceAll('a', 'b');"), 'bb');
      expect(
        await _run("var s = 'aa'; return s.replaceFirst('a', 'b');"),
        'ba',
      );
    });

    test('toString', () async {
      expect(await _run("var s = 'a'; return s.toString();"), equals('a'));
    });

    test('an unknown String member is an error', () async {
      expect(
        () => _run("var s = 'a'; return s.nope();"),
        throwsA(isA<Error>()),
      );
      expect(() => _run("var s = 'a'; return s.nope;"), throwsA(isA<Error>()));
    });
  });

  group('core int', () {
    test('parse, tryParse and valueOf', () async {
      expect(await _run("return int.parse('42');"), equals(42));
      expect(await _run("return int.tryParse('42');"), equals(42));
      expect(await _run("return int.tryParse('x');"), isNull);
    });

    test('sign as a getter and as a method', () async {
      expect(await _run('var a = -5; return a.sign;'), equals(-1));
      expect(await _run('var a = -5; return a.sign();'), equals(-1));
    });

    test('abs, compareTo and remainder', () async {
      expect(await _run('var a = -5; return a.abs();'), equals(5));
      expect(await _run('var a = 1; return a.compareTo(2);'), equals(-1));
      expect(await _run('var a = 10; return a.remainder(3);'), equals(1));
    });

    test('clamp, toRadixString and toDouble', () async {
      expect(await _run('var a = 10; return a.clamp(1, 5);'), equals(5));
      expect(await _run('var a = 255; return a.toRadixString(16);'), 'ff');
      expect(await _run('var a = 3; return a.toDouble();'), equals(3.0));
    });

    test('toInt is an identity', () async {
      // Inherited from `num`, where `toInt()` returns `this` for an `int`.
      expect(await _run('var a = 7; return a.toInt();'), equals(7));
      expect(await _run('var a = -5; return a.toInt();'), equals(-5));
      expect(await _run('var a = 0; return a.toInt();'), equals(0));
    });

    test('rounding: round, floor, ceil and truncate', () async {
      // All four are identities on `int`, negatives included.
      expect(await _run('var a = 7; return a.round();'), equals(7));
      expect(await _run('var a = 7; return a.floor();'), equals(7));
      expect(await _run('var a = 7; return a.ceil();'), equals(7));
      expect(await _run('var a = 7; return a.truncate();'), equals(7));
      expect(await _run('var a = -5; return a.round();'), equals(-5));
      expect(await _run('var a = -5; return a.floor();'), equals(-5));
      expect(await _run('var a = -5; return a.ceil();'), equals(-5));
      expect(await _run('var a = -5; return a.truncate();'), equals(-5));
    });

    test('string formatting', () async {
      expect(await _run('var a = 10; return a.toStringAsFixed(2);'), '10.00');
      expect(
        await _run('var a = 10; return a.toStringAsPrecision(3);'),
        equals('10.0'),
      );
      expect(
        await _run('var a = 1000; return a.toStringAsExponential(1);'),
        equals('1.0e+3'),
      );
    });

    test('toString', () async {
      expect(await _run('var a = 7; return a.toString();'), equals('7'));
    });

    test('an unknown int member is an error', () async {
      expect(() => _run('var a = 1; return a.nope();'), throwsA(isA<Error>()));
      expect(() => _run('var a = 1; return a.nope;'), throwsA(isA<Error>()));
    });
  });

  group('core double', () {
    test('parse, tryParse and valueOf', () async {
      expect(await _run("return double.parse('1.5');"), equals(1.5));
      expect(await _run("return double.tryParse('1.5');"), equals(1.5));
      expect(await _run("return double.tryParse('x');"), isNull);
    });

    test('sign as a getter and as a method', () async {
      expect(await _run('var d = -1.5; return d.sign;'), equals(-1.0));
      expect(await _run('var d = -1.5; return d.sign();'), equals(-1.0));
    });

    test('abs, compareTo and remainder', () async {
      expect(await _run('var d = -1.5; return d.abs();'), equals(1.5));
      expect(await _run('var d = 1.0; return d.compareTo(2.0);'), equals(-1));
      expect(await _run('var d = 5.5; return d.remainder(2.0);'), equals(1.5));
    });

    test('rounding: round, floor, ceil, truncate and toInt', () async {
      expect(await _run('var d = 2.6; return d.round();'), equals(3));
      expect(await _run('var d = 2.6; return d.floor();'), equals(2));
      expect(await _run('var d = 2.1; return d.ceil();'), equals(3));
      expect(await _run('var d = 2.9; return d.truncate();'), equals(2));
      expect(await _run('var d = 2.9; return d.toInt();'), equals(2));
    });

    test('toDouble is an identity', () async {
      // Inherited from `num`, where `toDouble()` returns `this` for a `double`.
      expect(await _run('var d = 1.5; return d.toDouble();'), equals(1.5));
      expect(await _run('var d = -2.5; return d.toDouble();'), equals(-2.5));
      expect(await _run('var d = 0.0; return d.toDouble();'), equals(0.0));
    });

    test('string formatting', () async {
      expect(await _run('var d = 1.5; return d.toStringAsFixed(2);'), '1.50');
      expect(
        await _run('var d = 1.23456; return d.toStringAsPrecision(3);'),
        equals('1.23'),
      );
      expect(
        await _run('var d = 1000.0; return d.toStringAsExponential(1);'),
        equals('1.0e+3'),
      );
    });

    test('clamp and toString', () async {
      expect(await _run('var d = 9.0; return d.clamp(1.0, 5.0);'), equals(5.0));
      expect(await _run('var d = 1.5; return d.toString();'), equals('1.5'));
    });
  });

  group('core num', () {
    // There is no `num` core class: a `num`-declared variable dispatches on the
    // runtime value's class, so `int` and `double` must each carry the whole
    // `num` surface, not just the half that converts to the other type.
    test('conversions on a num holding an int', () async {
      expect(await _run('num n = 3; return n.toInt();'), equals(3));
      expect(await _run('num n = 3; return n.toDouble();'), equals(3.0));
    });

    test('conversions on a num holding a double', () async {
      expect(await _run('num n = 2.5; return n.toInt();'), equals(2));
      expect(await _run('num n = 2.5; return n.toDouble();'), equals(2.5));
    });

    test('rounding on a num holding an int', () async {
      expect(await _run('num n = 3; return n.round();'), equals(3));
      expect(await _run('num n = 3; return n.floor();'), equals(3));
      expect(await _run('num n = 3; return n.ceil();'), equals(3));
      expect(await _run('num n = 3; return n.truncate();'), equals(3));
    });

    test('string formatting on a num holding an int', () async {
      expect(await _run('num n = 2; return n.toStringAsFixed(1);'), '2.0');
      expect(await _run('num n = 2; return n.toStringAsPrecision(2);'), '2.0');
      expect(
        await _run('num n = 2; return n.toStringAsExponential(1);'),
        equals('2.0e+0'),
      );
    });

    test('conversions chain in both directions', () async {
      expect(await _run('var a = 4; return a.toDouble().toInt();'), equals(4));
      expect(
        await _run('var d = 4.5; return d.toInt().toDouble();'),
        equals(4.0),
      );
      expect(await _run('var a = 4; return a.toInt().toInt();'), equals(4));
      expect(
        await _run('var d = 4.5; return d.toDouble().toDouble();'),
        equals(4.5),
      );
    });

    test('toNum() is not a Dart method and stays unsupported', () async {
      expect(() => _run('var a = 1; return a.toNum();'), throwsA(isA<Error>()));
      expect(
        () => _run('var d = 1.5; return d.toNum();'),
        throwsA(isA<Error>()),
      );
      expect(() => _run('num n = 1; return n.toNum();'), throwsA(isA<Error>()));
    });
  });

  group('core List', () {
    test('length, isEmpty, isNotEmpty, first and last as getters', () async {
      expect(await _run('var l = [1, 2]; return l.length;'), equals(2));
      expect(await _run('var l = []; return l.isEmpty;'), isTrue);
      expect(await _run('var l = [1]; return l.isNotEmpty;'), isTrue);
      expect(await _run('var l = [7, 8]; return l.first;'), equals(7));
      expect(await _run('var l = [7, 8]; return l.last;'), equals(8));
    });

    test('add, addAll and insert', () async {
      expect(await _run('var l = [1]; l.add(2); return l;'), [1, 2]);
      expect(await _run('var l = [1]; l.addAll([2, 3]); return l;'), [1, 2, 3]);
      expect(await _run('var l = [1, 3]; l.insert(1, 2); return l;'), [
        1,
        2,
        3,
      ]);
    });

    test('remove, removeAt and clear', () async {
      expect(await _run('var l = [1, 2]; return l.remove(2);'), isTrue);
      expect(await _run('var l = [1, 2]; l.removeAt(0); return l;'), [2]);
      expect(await _run('var l = [1, 2]; l.clear(); return l;'), isEmpty);
    });

    test('contains, indexOf and sublist', () async {
      expect(await _run('var l = [1, 2]; return l.contains(2);'), isTrue);
      expect(await _run('var l = [1, 2]; return l.indexOf(2);'), equals(1));
      expect(await _run('var l = [1, 2, 3]; return l.sublist(1);'), [2, 3]);
      expect(await _run('var l = [1, 2, 3]; return l.sublist(0, 2);'), [1, 2]);
    });

    test('an unknown List member is an error', () async {
      expect(() => _run('var l = []; return l.nope();'), throwsA(isA<Error>()));
      expect(() => _run('var l = []; return l.nope;'), throwsA(isA<Error>()));
    });
  });

  group('core Map', () {
    test('length, isEmpty and isNotEmpty as getters', () async {
      expect(await _run("var m = {'a': 1}; return m.length;"), equals(1));
      expect(await _run('var m = {}; return m.isEmpty;'), isTrue);
      expect(await _run("var m = {'a': 1}; return m.isNotEmpty;"), isTrue);
    });

    test('keys and values as getters', () async {
      expect(await _run("var m = {'a': 1}; return m.keys;"), ['a']);
      expect(await _run("var m = {'a': 1}; return m.values;"), [1]);
    });

    test('containsKey, remove and clear', () async {
      expect(
        await _run("var m = {'a': 1}; return m.containsKey('a');"),
        isTrue,
      );
      expect(
        await _run("var m = {'a': 1}; m.remove('a'); return m.length;"),
        0,
      );
      expect(
        await _run("var m = {'a': 1}; m.clear(); return m.isEmpty;"),
        true,
      );
    });

    test('an unknown Map member is an error', () async {
      expect(() => _run('var m = {}; return m.nope();'), throwsA(isA<Error>()));
      expect(() => _run('var m = {}; return m.nope;'), throwsA(isA<Error>()));
    });
  });
}
