// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

@Tags(['apollo', 'dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:apollovm/src/apollovm_code_storage.dart';
import 'package:apollovm/src/languages/apollo/apollo_generator.dart';
import 'package:test/test.dart';

/// Loads [source] in [language] and returns the generated Apollo source of the
/// single code unit (without the `writeAllSources` envelope).
Future<String> _gen(String source, {String language = 'apollo'}) async {
  var vm = ApolloVM();
  var loaded = await vm.loadCodeUnit(
    SourceCodeUnit(language, source, id: 'test'),
  );
  expect(loaded, isTrue, reason: 'Failed to load $language code');

  var storage = vm.generateAllCodeIn('apollo');
  var allSources = (await storage.writeAllSources()).toString();

  var lines = allSources.split('\n');
  var start = lines.indexWhere((l) => l.startsWith('<<<< CODE_UNIT_START'));
  var end = lines.indexWhere((l) => l.startsWith('<<<< CODE_UNIT_END'));
  return lines.sublist(start + 1, end).join('\n');
}

/// Runs `run()` in [source] and returns the captured `print` output.
Future<List<Object?>> _run(String source, {String language = 'apollo'}) async {
  var vm = ApolloVM();
  await vm.loadCodeUnit(SourceCodeUnit(language, source, id: 'test'));

  var runner = vm.createRunner(language)!;
  var output = <Object?>[];
  runner.externalPrintFunction = (o) => output.add(o);

  await runner.executeFunction('', 'run');
  return output;
}

/// Generates Apollo from [source], runs both, and asserts they print the same
/// thing — the property that makes the generator's output trustworthy.
///
/// Returns the generated source so a test can also assert on its text.
Future<String> _roundTrip(String source, {String language = 'apollo'}) async {
  var generated = await _gen(source, language: language);

  expect(
    await _run(generated),
    equals(await _run(source, language: language)),
    reason: 'Regenerated Apollo behaves differently:\n$generated',
  );

  return generated;
}

void main() {
  group('Apollo generator: directives', () {
    test('import with prefix and combinators', () async {
      var apollo = await _gen(r'''
import 'math.apollo' as m show sqrt, pow
import 'plain.apollo'
import 'hidden.apollo' hide Secret, Other

run() { print(1) }
''');

      expect(apollo, contains("import 'math.apollo' as m show sqrt, pow;"));
      expect(apollo, contains("import 'plain.apollo';"));
      expect(apollo, contains("import 'hidden.apollo' hide Secret, Other;"));
    });

    test('export with combinators', () async {
      var apollo = await _gen(r'''
export 'api.apollo' show A, B
export 'internal.apollo' hide Hidden

run() { print(1) }
''');

      expect(apollo, contains("export 'api.apollo' show A, B;"));
      expect(apollo, contains("export 'internal.apollo' hide Hidden;"));
    });

    test('typedef of a plain and a generic type', () async {
      var apollo = await _gen(r'''
typedef Id = Int;
typedef Names = List<String>;

run() { print(1) }
''');

      expect(apollo, contains('typedef Id = Int;'));
      expect(apollo, contains('typedef Names = List<String>;'));
    });

    test('typedef without a trailing semicolon', () async {
      // Apollo semicolons are optional; `typedef` used to require one, and a
      // generic target type failed with an internal cast error rather than a
      // syntax error.
      var apollo = await _gen(r'''
typedef Id = Int
typedef Names = List<String>
typedef Mapper = Int Function(Int)

run() { print(1) }
''');

      expect(apollo, contains('typedef Id = Int;'));
      expect(apollo, contains('typedef Names = List<String>;'));
      expect(apollo, contains('typedef Mapper = Int Function(Int);'));
    });

    test('typedef of function types', () async {
      var apollo = await _gen(r'''
typedef Mapper = Int Function(Int);
typedef TwoArgs = String Function(Int, Bool);
typedef Bare = Function;
typedef DynamicReturn = Function(Int);

run() { print(1) }
''');

      // `<returnType> Function(<params>)`, with a `dynamic` return omitted.
      expect(apollo, contains('typedef Mapper = Int Function(Int);'));
      expect(apollo, contains('typedef TwoArgs = String Function(Int, Bool);'));
      expect(apollo, contains('typedef Bare = Function;'));
      expect(apollo, contains('typedef DynamicReturn = Function(Int);'));
    });
  });

  group('Apollo generator: classes', () {
    test('abstract class with a body-less method', () async {
      var apollo = await _gen(r'''
abstract class Shape {
  Double area();
}

run() { print(1) }
''');

      expect(apollo, contains('abstract class Shape {'));
      expect(apollo, contains('Double area();'));
    });

    test('a Dart interface becomes an abstract class', () async {
      var apollo = await _gen(r'''
abstract class Shape {
  double area();
}

void run() { print(1); }
''', language: 'dart');

      expect(apollo, contains('abstract class Shape {'));
      expect(apollo, contains('Double area();'));
    });

    test(
      'extends + implements, fields, constructor, getter, methods',
      () async {
        var apollo = await _gen(r'''
abstract class Shape {
  Double area();
}

class Circle extends Shape implements Comparable {
  static Int count = 0
  static final Int MAX = 100
  final Double r
  Double scale = 1.0

  Circle(this.r)

  Double get diameter { return r * 2 }

  static Int total() { return count }

  Double area() { return 3.14 * r * r }
}

run() { print(1) }
''');

        expect(
          apollo,
          contains('class Circle extends Shape implements Comparable {'),
        );
        expect(apollo, contains('static Int count = 0;'));
        expect(apollo, contains('static final Int MAX = 100;'));
        expect(apollo, contains('final Double r;'));
        expect(apollo, contains('Double scale = 1.0;'));
        // A constructor with an empty body is emitted body-less.
        expect(apollo, contains('Circle(this.r);'));
        expect(apollo, contains('Double get diameter {'));
        expect(apollo, contains('static Int total() {'));
        expect(apollo, contains('Double area() {'));
      },
    );

    test('named and anonymous extensions', () async {
      var apollo = await _gen(r'''
extension Doubler on Int {
  Int twice() { return this * 2 }
}

extension on Double {
  Double half() { return this / 2 }
}

run() { print(1) }
''');

      expect(apollo, contains('extension Doubler on Int {'));
      expect(apollo, contains('extension on Double {'));
      expect(apollo, contains('Int twice() {'));
      expect(apollo, contains('Double half() {'));
    });
  });

  group('Apollo generator: enums', () {
    test('simple enum', () async {
      var apollo = await _gen(r'''
enum Color {
  red,
  green,
  blue
}

run() { print(1) }
''');

      expect(apollo, contains('enum Color {\n  red,\n  green,\n  blue\n}'));
    });

    test('enum entries with explicit values', () async {
      var apollo = await _gen(r'''
enum Code {
  ok = 1,
  bad = 2
}

run() { print(1) }
''');

      expect(apollo, contains('ok = 1,'));
      expect(apollo, contains('bad = 2'));
    });

    test(
      'rich enum: entry arguments, fields, const constructor, method',
      () async {
        var apollo = await _gen(r'''
enum Planet {
  earth(5.97, 6371),
  mars(0.642, 3390)
  ;
  final Double mass
  final Int radius
  Planet(this.mass, this.radius)
  Double density() { return mass / radius }
}

run() { print(1) }
''');

        expect(apollo, contains('earth(5.97, 6371),'));
        expect(apollo, contains('mars(0.642, 3390)'));
        // The `;` separating entries from members, then the members themselves.
        expect(apollo, contains('  ;\n'));
        expect(apollo, contains('final Double mass;'));
        expect(apollo, contains('final Int radius;'));
        // An enum constructor is always emitted `const`.
        expect(apollo, contains('const Planet(this.mass, this.radius);'));
        expect(apollo, contains('Double density() {'));
      },
    );
  });

  group('Apollo generator: functions and parameters', () {
    test('optional positional parameters', () async {
      var apollo = await _gen(r'''
Int f(Int a, [Int b, Int c]) { return a }

run() { print(f(1)) }
''');

      expect(apollo, contains('Int f(Int a, [Int b, Int c]) {'));
    });

    test('named parameters', () async {
      var apollo = await _gen(r'''
Int g(Int a, {Int b, Int c}) { return a }

run() { print(g(1)) }
''');

      expect(apollo, contains('Int g(Int a, {Int b, Int c}) {'));
    });

    test('async is emitted as a leading modifier', () async {
      var apollo = await _gen(r'''
async Int slow() { return 1 }

class C {
  async Int m() { return 2 }
}

run() { print(1) }
''');

      expect(apollo, contains('async Int slow() {'));
      expect(apollo, contains('async Int m() {'));
    });

    test('literal function: arrow body and block body', () async {
      var apollo = await _roundTrip(r'''
Int apply(Int Function(Int) f, Int v) { return f(v) }

run() {
  var double = (Int x) => x * 2
  var shout = (Int x) { print(x) }
  print(apply(double, 4))
  shout(7)
}
''');

      // A single-expression body becomes `=>`; anything else keeps a block.
      expect(apollo, contains('(Int x) => x * 2'));
      expect(apollo, contains('(Int x) {'));
    });
  });

  group('Apollo generator: types', () {
    test('primitive types are capitalized', () async {
      var apollo = await _gen(r'''
int i(int a) { return a; }
double d(double a) { return a; }
bool b(bool a) { return a; }
num n(num a) { return a; }
void v() {}

void run() { print(1); }
''', language: 'dart');

      expect(apollo, contains('Int i(Int a)'));
      expect(apollo, contains('Double d(Double a)'));
      expect(apollo, contains('Bool b(Bool a)'));
      expect(apollo, contains('Num n(Num a)'));
      expect(apollo, contains('Void v()'));
    });

    test('array and map types keep their generics', () async {
      var apollo = await _roundTrip(r'''
List<Int> nums(List<Int> xs) { return xs }

run() {
  List<Int> a = [1, 2, 3]
  Map<String, Int> m = {"k": 9}
  List<Int> b = nums(a)
  print(b[0])
  print(m["k"])
}
''');

      expect(apollo, contains('List<Int> nums(List<Int> xs)'));
      expect(apollo, contains('List<Int> a = <Int>[1, 2, 3];'));
      expect(apollo, contains("Map<String, Int> m = {'k': 9};"));
    });

    test('`int.parse` normalizes to `Int.parse`', () async {
      var apollo = await _gen(r'''
void run() {
  print(int.parse("5"));
}
''', language: 'dart');

      expect(apollo, contains("Int.parse('5')"));
    });
  });

  group('Apollo generator: catch clauses', () {
    test('untyped and typed catch', () async {
      var apollo = await _roundTrip(r'''
run() {
  try {
    throw "boom"
  } catch e {
    print(e)
  }
  try {
    throw "bang"
  } catch String s {
    print(s)
  }
}
''');

      expect(apollo, contains('} catch (e) {'));
      expect(apollo, contains('} catch (String s) {'));
    });
  });

  group('Apollo generator: strings', () {
    test('quote choice avoids escaping', () async {
      var apollo = await _roundTrip(r'''
run() {
  print("plain")
  print("has ' single")
  print('has " double')
}
''');

      expect(apollo, contains("print('plain');"));
      // A single quote inside forces double quotes, and vice versa.
      expect(apollo, contains("""print("has ' single");"""));
      expect(apollo, contains("""print('has " double');"""));
    });

    test('a backslash-only string is emitted raw', () async {
      var apollo = await _roundTrip(r'''
run() {
  print("has \\ backslash")
}
''');

      expect(apollo, contains(r"print(r'has \ backslash');"));
    });

    test(r'control characters and `$` are escaped', () async {
      var apollo = await _roundTrip(r'''
run() {
  print("line\nbreak")
  print("tab\there")
  print("dollar \$sign")
}
''');

      expect(apollo, contains(r"print('line\nbreak');"));
      expect(apollo, contains(r"print('tab\there');"));
      expect(apollo, contains(r"print('dollar \$sign');"));
    });

    test('adjacent literals merge into one string', () async {
      var apollo = await _roundTrip(r'''
run() {
  print("a" + "b")
  print("num " + "1" + " end")
}
''');

      expect(apollo, contains("print('ab');"));
      expect(apollo, contains("print('num 1 end');"));
    });

    test('literals of different quotes merge by converting one', () async {
      var apollo = await _roundTrip(r'''
run() {
  print("it's " + "ok")
  print("say \"hi\"" + " there")
}
''');

      expect(apollo, contains("""print("it's ok");"""));
      expect(apollo, contains("""print('say "hi" there');"""));
    });

    test(
      'a variable concatenated with a literal becomes interpolation',
      () async {
        var apollo = await _roundTrip(r'''
run() {
  var n = "X"
  print("a" + n)
  print("a" + n + "!")
  print(n + " tail")
}
''');

        expect(apollo, contains(r"print('a$n');"));
        expect(apollo, contains(r"print('a$n!');"));
        expect(apollo, contains(r"print('$n tail');"));
      },
    );

    test('interpolation is brace-delimited when a name would run on', () async {
      // `'a' + n + 'b'` merges into one literal; spliced bare it would read as
      // a variable named `nb`.
      var apollo = await _roundTrip(r'''
run() {
  var n = "X"
  print("a" + n + "b")
  print(n + "b")
}
''');

      expect(apollo, contains(r"print('a${n}b');"));
      expect(apollo, contains(r"print('${n}b');"));
      expect(apollo, isNot(contains(r'$nb')));
    });

    test(r'an escaped `$` is not mistaken for an interpolation', () async {
      var apollo = await _roundTrip(r'''
run() {
  print("\$" + "b")
  print("cost \$" + "9")
}
''');

      expect(apollo, contains(r"print('\$b');"));
      expect(apollo, contains(r"print('cost \$9');"));
    });

    test('source interpolation stays undelimited where it can', () async {
      var apollo = await _roundTrip(r'''
run() {
  var name = "world"
  var n = 2
  print("hello $name")
  print("n=$n done")
  print("${n + 1} x")
}
''');

      expect(apollo, contains(r"print('hello $name');"));
      expect(apollo, contains(r"print('n=$n done');"));
      expect(apollo, contains(r"print('${n + 1} x');"));
    });

    test(r'an escaped `$` before a name is left undelimited', () async {
      // The `$` is escaped, so `\$namex` is the literal text — brace-delimiting
      // it would invent an interpolation that was never there.
      var apollo = await _roundTrip(r'''
run() {
  print("\$name" + "x")
  print("\$name" + "!")
}
''');

      expect(apollo, contains(r"print('\$namex');"));
      expect(apollo, contains(r"print('\$name!');"));
    });

    test(
      'a string with an escaped quote merges by converting quotes',
      () async {
        var apollo = await _roundTrip(r'''
run() {
  print("a \" b" + "c")
  print('a \' b' + 'c')
}
''');

        expect(apollo, contains("""print('a " bc');"""));
        expect(apollo, contains('''print("a ' bc");'''));
      },
    );

    test('parts that cannot share a quote stay a `+`', () async {
      // Neither side can be converted without escaping, so no merge happens.
      var apollo = await _roundTrip(r'''
run() {
  print("a \" b" + 'c \' d')
}
''');

      expect(apollo, contains("""print('a " b' + "c ' d");"""));
    });

    test('raw form is chosen per the quotes the text contains', () async {
      var apollo = await _roundTrip(r'''
run() {
  print("back \\ slash")
  print("back \\ and ' quote")
  print("back \\ and \" quote")
  print("back \\ both ' and \" quotes")
}
''');

      // A lone backslash goes raw, quoted so nothing inside needs escaping;
      // with both quote kinds present raw is impossible, so it escapes instead.
      expect(apollo, contains(r"print(r'back \ slash');"));
      expect(apollo, contains("""print(r"back \\ and ' quote");"""));
      expect(apollo, contains("""print(r'back \\ and " quote');"""));
      expect(apollo, contains("""print("back \\\\ both ' and \\" quotes");"""));
    });

    test(
      'multiline strings collapse to an escaped single-line literal',
      () async {
        var apollo = await _roundTrip('''
run() {
  var s = """line1
line2"""
  print(s)
}
''');

        expect(apollo, contains(r"var s = 'line1\nline2';"));
      },
    );
  });

  group('Apollo generator: expressions', () {
    test('binary, bitwise and shift operators', () async {
      var apollo = await _roundTrip(r'''
run() {
  var a = 5
  var b = 3
  print(a % b)
  print(a | b)
  print(a ^ b)
  print(a & b)
  print(a << 1)
  print(a >> 1)
}
''');

      expect(apollo, contains('print(a % b);'));
      expect(apollo, contains('print(a | b);'));
      expect(apollo, contains('print(a ^ b);'));
      expect(apollo, contains('print(a & b);'));
      expect(apollo, contains('print(a << 1);'));
      expect(apollo, contains('print(a >> 1);'));
    });

    test('complex operands are parenthesized', () async {
      var apollo = await _roundTrip(r'''
run() {
  var a = 5
  var b = 3
  print((a + b) * (a - b))
  print(a > b && a != b)
}
''');

      expect(apollo, contains('print((a + b) * (a - b));'));
      expect(apollo, contains('print((a > b) && (a != b));'));
    });

    test('a grouped operand keeps its parentheses beside a string', () async {
      // Without them the expression re-associates: `("q " + n) + 1`.
      var apollo = await _roundTrip(r'''
run() {
  var n = 5
  print("q " + (n + 1))
  print("q " + (n * 2))
}
''');

      expect(apollo, contains("print('q ' + (n + 1));"));
      expect(apollo, contains("print('q ' + (n * 2));"));
    });

    test('a string operand sheds redundant parentheses', () async {
      var apollo = await _roundTrip(r'''
run() {
  var xs = [10, 20, 30]
  var m = {"b": 2}
  print(xs[0] + xs[2] + m["b"])
}
''');

      expect(apollo, contains("print(xs[0] + xs[2] + m['b']);"));
    });
  });

  // Emit methods reached by driving the generator directly, for AST shapes the
  // Apollo grammar has no surface syntax for (array values) or that the parser
  // never builds on its own (a hand-assembled string concatenation).
  group('Apollo generator: direct emit API', () {
    late ApolloCodeGeneratorApollo generator;

    setUp(() {
      generator = ApolloCodeGeneratorApollo(ApolloSourceCodeStorageMemory());
    });

    test('array values of 1, 2 and 3 dimensions', () {
      expect(
        generator
            .generateASTValueArray(
              ASTValueArray<ASTTypeInt, int>(ASTTypeInt.instance, [1, 2, 3]),
            )
            .toString(),
        equals('[1, 2, 3]'),
      );

      expect(
        generator
            .generateASTValueArray2D(
              ASTValueArray2D<ASTTypeInt, int>(ASTTypeInt.instance, [
                [1, 2],
                [3],
              ]),
            )
            .toString(),
        equals('[[1, 2], [3]]'),
      );

      expect(
        generator
            .generateASTValueArray3D(
              ASTValueArray3D<ASTTypeInt, int>(ASTTypeInt.instance, [
                [
                  [1],
                ],
              ]),
            )
            .toString(),
        equals('[[[1]]]'),
      );
    });

    test('an interpolated variable follows the surrounding quote', () {
      var value = ASTValueStringVariable(ASTScopeVariable('name'));

      expect(
        generator.generateASTValueStringVariable(value).toString(),
        equals(r"'$name'"),
      );
      expect(
        generator
            .generateASTValueStringVariable(value, prevDoubleQuote: true)
            .toString(),
        equals(r'"$name"'),
      );
    });

    test('an interpolated expression is always brace-delimited', () {
      expect(
        generator
            .generateASTValueStringExpression(
              ASTValueStringExpression(ASTExpressionLiteral(ASTValueInt(5))),
            )
            .toString(),
        equals(r"'${5}'"),
      );

      // A single quote in the expression keeps the double-quoted context.
      expect(
        generator
            .generateASTValueStringExpression(
              ASTValueStringExpression(
                ASTExpressionLiteral(ASTValueString("it's")),
              ),
              prevDoubleQuote: true,
            )
            .toString(),
        startsWith('"'),
      );
    });

    test('concatenation of like-quoted parts collapses to one literal', () {
      expect(
        generator
            .generateASTValueStringConcatenation(
              ASTValueStringConcatenation([
                ASTValueString('a'),
                ASTValueString('b'),
              ]),
            )
            .toString(),
        equals("'ab'"),
      );

      // A nested concatenation is flattened along with the rest.
      expect(
        generator
            .generateASTValueStringConcatenation(
              ASTValueStringConcatenation([
                ASTValueString('x'),
                ASTValueStringConcatenation([
                  ASTValueString('y'),
                  ASTValueString('z'),
                ]),
              ]),
            )
            .toString(),
        equals("'xyz'"),
      );
    });

    test('concatenation of unlike-quoted parts stays adjacent literals', () {
      // `'plain'` and `"has ' quote"` cannot share a quote, so they are emitted
      // as Apollo adjacent-string concatenation instead of being merged.
      expect(
        generator
            .generateASTValueStringConcatenation(
              ASTValueStringConcatenation([
                ASTValueString('plain'),
                ASTValueString("has ' quote"),
              ]),
            )
            .toString(),
        equals("""'plain'"has ' quote\""""),
      );

      // A raw part is likewise kept separate rather than merged.
      expect(
        generator
            .generateASTValueStringConcatenation(
              ASTValueStringConcatenation([
                ASTValueString(r'back \ slash'),
                ASTValueString('plain'),
              ]),
            )
            .toString(),
        equals(r"r'back \ slash''plain'"),
      );
    });

    test('a concatenated variable is delimited only when it must be', () {
      expect(
        generator
            .generateASTValueStringConcatenation(
              ASTValueStringConcatenation([
                ASTValueString('n='),
                ASTValueStringVariable(ASTScopeVariable('n')),
                ASTValueString('!'),
              ]),
            )
            .toString(),
        equals(r"'n=$n!'"),
      );

      // `'a' 'n' 'b'` merged bare would read as a variable named `nb`.
      expect(
        generator
            .generateASTValueStringConcatenation(
              ASTValueStringConcatenation([
                ASTValueString('a'),
                ASTValueStringVariable(ASTScopeVariable('n')),
                ASTValueString('b'),
              ]),
            )
            .toString(),
        equals(r"'a${n}b'"),
      );
    });

    test('parts that share one quote style merge under it', () {
      // Each `every(...)` opener case: all raw-single, all double, all
      // raw-double. Merging keeps the shared opener and drops the inner quotes.
      expect(
        generator
            .generateASTValueStringConcatenation(
              ASTValueStringConcatenation([
                ASTValueString(r'a \ b'),
                ASTValueString(r'c \ d'),
              ]),
            )
            .toString(),
        equals(r"r'a \ bc \ d'"),
      );

      expect(
        generator
            .generateASTValueStringConcatenation(
              ASTValueStringConcatenation([
                ASTValueString("a ' b"),
                ASTValueString("c ' d"),
              ]),
            )
            .toString(),
        equals('''"a ' bc ' d"'''),
      );

      expect(
        generator
            .generateASTValueStringConcatenation(
              ASTValueStringConcatenation([
                ASTValueString("a \\ ' b"),
                ASTValueString("c \\ ' d"),
              ]),
            )
            .toString(),
        equals("""r"a \\ ' bc \\ ' d\""""),
      );
    });

    test('a concatenated expression keeps its braces', () {
      expect(
        generator
            .generateASTValueStringConcatenation(
              ASTValueStringConcatenation([
                ASTValueString('v='),
                ASTValueStringExpression(ASTExpressionLiteral(ASTValueInt(7))),
              ]),
            )
            .toString(),
        equals(r"'v=${7}'"),
      );
    });
  });
}
