@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
// Serialization internals are not re-exported from the public library.
import 'package:apollovm/src/serialization/ast_binary_reader.dart';
import 'package:apollovm/src/serialization/ast_binary_writer.dart';
import 'package:test/test.dart';

/// Parses [source], and returns the code unit alongside the source the
/// generator produces from the freshly parsed AST.
Future<(ApolloVM, CodeUnit, String)> _parse(
  String source, {
  String language = 'dart',
}) async {
  var vm = ApolloVM();
  var codeUnit = SourceCodeUnit(language, source, id: 'test');

  var ok = await vm.loadCodeUnit(codeUnit);
  expect(ok, isTrue, reason: "Error loading '$language' source");

  var generated = (await vm.generateAllCodeIn(language).writeAllSources())
      .toString();

  return (vm, codeUnit, generated);
}

/// Parses [source], encodes its AST, decodes it into a fresh VM, and asserts
/// the regenerated source is byte-identical to what the parsed AST produced.
///
/// Comparing regenerated source is the strongest cheap check available here: it
/// exercises every field the code generator reads, across the whole tree, so a
/// dropped field shows up as a diff rather than going unnoticed.
Future<ApolloVM> _assertRoundTrip(
  String source, {
  String language = 'dart',
}) async {
  var (_, codeUnit, expected) = await _parse(source, language: language);

  var bytes = ASTBinaryWriter().writeCodeUnit(codeUnit);

  var decodedUnit = const ASTBinaryReader().readCodeUnit(bytes);
  var vm2 = ApolloVM();
  var ok = await vm2.loadCodeUnit(decodedUnit);
  expect(ok, isTrue, reason: 'Error loading the decoded binary AST');

  var actual = (await vm2.generateAllCodeIn(language).writeAllSources())
      .toString();

  expect(
    actual,
    equals(expected),
    reason: 'Regenerated source diverged after a binary AST round trip',
  );

  return vm2;
}

/// Encoding is deterministic, so re-encoding a decoded AST must reproduce the
/// original bytes exactly. This is the cheapest possible detector for an
/// encode/decode asymmetry that still happens to produce readable source.
Future<void> _assertByteIdempotent(
  String source, {
  String language = 'dart',
}) async {
  var (_, codeUnit, _) = await _parse(source, language: language);

  var first = ASTBinaryWriter().writeCodeUnit(codeUnit);
  var decoded = const ASTBinaryReader().readCodeUnit(first);
  var second = ASTBinaryWriter().writeCodeUnit(decoded);

  expect(
    second,
    equals(first),
    reason: 'encode(decode(encode(ast))) differed from encode(ast)',
  );
}

void main() {
  group('round trip', () {
    test('a class with a method and a static entry point', () async {
      await _assertRoundTrip(r'''
class Foo {
  int sum(int a, int b) {
    var t = a + b;
    return t;
  }

  static void main(List<String> args) {
    var f = Foo();
    print(f.sum(10, 20));
  }
}
''');
    });

    test('control flow', () async {
      await _assertRoundTrip(r'''
class Ctrl {
  void run(int n) {
    if (n > 10) {
      print('big');
    } else if (n > 5) {
      print('mid');
    } else {
      print('small');
    }

    for (var i = 0; i < n; ++i) {
      if (i == 2) continue;
      if (i == 5) break;
      print(i);
    }

    var j = 0;
    while (j < 3) {
      j++;
    }

    do {
      j--;
    } while (j > 0);
  }
}
''');
    });

    test('for-each, switch, try/catch and throw', () async {
      await _assertRoundTrip(r'''
class Flow {
  void run(List<int> items) {
    for (var i in items) {
      print(i);
    }

    switch (items.length) {
      case 0:
        print('empty');
        break;
      default:
        print('some');
    }

    try {
      throw 'boom';
    } catch (e) {
      print(e);
    } finally {
      print('done');
    }
  }
}
''');
    });

    test('literals of every kind', () async {
      await _assertRoundTrip(r'''
class Lits {
  void run() {
    var a = 1;
    var b = -2;
    var c = 3.5;
    var d = 'text';
    var e = true;
    var f = null;
    var g = [1, 2, 3];
    var h = {'k': 'v'};
    print('$a $b $c $d $e $f $g $h');
  }
}
''');
    });

    test('fields, constructors and inheritance', () async {
      await _assertRoundTrip(r'''
class Base {
  int x = 0;

  Base(this.x);

  int get doubled => x * 2;
}

class Derived extends Base {
  String label;

  Derived(this.label);

  set renamed(String v) {
    label = v;
  }
}
''');
    });

    test('operators and null handling', () async {
      await _assertRoundTrip(r'''
class Ops {
  void run(int? a, int b) {
    var c = a ?? b;
    var d = a != null ? a : b;
    var e = !(b > 1) && (b < 10 || b == 5);
    var f = ~b;
    var g = -b;
    print('$c $d $e $f $g');
  }
}
''');
    });

    test('async and await', () async {
      await _assertRoundTrip(r'''
class Aw {
  Future<int> value() async {
    return 42;
  }

  Future<void> run() async {
    var v = await value();
    print(v);
  }
}
''');
    });

    test('imports and enums', () async {
      await _assertRoundTrip(r'''
import 'dart:math';

enum Color { red, green, blue }

class UsesEnum {
  void run() {
    var c = Color.red;
    print(c);
  }
}
''');
    });
  });

  group('byte idempotence', () {
    test('re-encoding a decoded AST reproduces the same bytes', () async {
      await _assertByteIdempotent(r'''
class Foo {
  int sum(int a, int b) => a + b;

  static void main(List<String> args) {
    print(Foo().sum(1, 2));
  }
}
''');
    });
  });

  group('execution', () {
    test('a decoded AST runs and produces the same output', () async {
      var vm = await _assertRoundTrip(r'''
class Calc {
  int sum(List<int> ns) {
    var total = 0;
    for (var n in ns) {
      total = total + n;
    }
    return total;
  }

  static void main(List<String> args) {
    var c = Calc();
    print('total: ${c.sum([1, 2, 3, 4])}');
  }
}
''');

      var runner = vm.createRunner('dart')!;
      var output = <Object?>[];
      runner.externalPrintFunction = output.add;

      await runner.executeClassMethod(
        '',
        'Calc',
        'main',
        positionalParameters: [<String>[]],
      );

      expect(output, equals(['total: 10']));
    });
  });

  group('image metadata', () {
    test('records language, namespace and id', () async {
      var (_, codeUnit, _) = await _parse('class A { void f() {} }');

      var bytes = ASTBinaryWriter().writeCodeUnit(codeUnit);
      var info = const ASTBinaryReader().readInfo(bytes);

      expect(info.language, equals('dart'));
      expect(info.codeUnitId, equals('test'));
      expect(info.namespace, equals(codeUnit.namespace));
      expect(info.writerVersion, equals(ApolloVM.VERSION));
      expect(info.isSigned, isFalse);
      expect(info.unknownSectionIds, isEmpty);
      expect(info.fileSize, equals(bytes.length));
    });

    test('the image is recognizable by its magic', () async {
      var (_, codeUnit, _) = await _parse('class A { void f() {} }');
      var bytes = ASTBinaryWriter().writeCodeUnit(codeUnit);

      expect(ASTBinaryReader.isASTBinary(bytes), isTrue);
    });

    test('refuses to write a code unit that was never loaded', () {
      var codeUnit = SourceCodeUnit('dart', 'class A {}', id: 'x');
      expect(
        () => ASTBinaryWriter().writeCodeUnit(codeUnit),
        throwsA(isA<StateError>()),
      );
    });
  });
}
