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
/// A lenient sanity check that the *right* generator produced the output.
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

/// A translation program: a Dart [source] and a [token] it always names in
/// every generated language (a class/enum name preserved verbatim).
///
/// The [name] labels the generator surface it exercises. These programs
/// deliberately concentrate on the emit methods the broader translation matrix
/// tests (`apollovm_generator_matrix_test.dart`,
/// `apollovm_translation_coverage_test.dart`) do *not* emphasize: rich
/// (enhanced) enums, generic/array/map type emission, every string
/// interpolation/concatenation variant, generic constructors and fields,
/// function-typed values (lambdas) and import statements.
class _Program {
  final String name;
  final String token;
  final String source;

  const _Program(this.name, this.token, this.source);
}

const _programs = <_Program>[
  // Rich (enhanced) enum with constructor arguments, final fields, a const
  // constructor and a method, plus a simple enum and a class referencing it.
  // Drives `_generateRichEnum*`, `generateASTClassEnum`, `_generateEnumEntry`.
  _Program('richEnums', 'Planet', r'''
enum Planet {
  earth(5.97, 6371), mars(0.642, 3389);

  final double mass;
  final double radius;

  const Planet(this.mass, this.radius);

  double gravity() { return mass / (radius * radius); }
}

enum Color { red, green, blue }

class Sky {
  Color favorite() { return Color.blue; }
}
'''),

  // Generic and nested collection types on fields and locals: List<int>,
  // Map<String, int>, List<List<int>> with list/map/2D-array literals.
  // Drives `generateASTType`, `generateASTValueArray`,
  // `generateASTValueArray2D` and `generateASTExpressionMapLiteral`.
  _Program('generics', 'Store', r'''
class Store {
  List<int> nums = [1, 2, 3];
  Map<String, int> counts = {'a': 1, 'b': 2};
  List<List<int>> grid = [[1, 2], [3, 4]];

  List<int> numbers() {
    List<int> local = [10, 20];
    return local;
  }

  Map<String, int> mapping() {
    Map<String, int> m = {'x': 1};
    return m;
  }

  List<List<int>> matrix() {
    return [[1, 2], [3]];
  }
}
'''),

  // String interpolation with a bare variable and an embedded expression,
  // string concatenation and an interpolation mixing several fragments.
  // Drives `generateASTValueString`, `generateASTValueStringConcatenation`,
  // `generateASTValueStringVariable`, `generateASTValueStringExpression`.
  _Program('strings', 'Text', r'''
class Text {
  String interp(String name, int a, int b) {
    var s = 'v=$name sum=${a + b}';
    return s;
  }

  String concat(String a, String b) {
    return a + b;
  }

  String multi(int x, int y) {
    var s = 'x=$x y=$y total=${x + y}!';
    return s;
  }
}
'''),

  // A generic constructor binding fields through `this`, several typed fields
  // (including a double), and methods reading those fields. Drives
  // `generateASTClassConstructorDeclaration`, `generateASTClassField`,
  // `generateASTParameterDeclaration` and `generateASTParametersDeclaration`.
  _Program('constructors', 'Point', r'''
class Point {
  int x = 0;
  int y = 0;
  double scale = 1.0;

  Point(this.x, this.y);

  int sum() {
    return x + y;
  }

  double scaled() {
    return sum() * scale;
  }
}
'''),

  // A function-typed variable initialised with a lambda, and a lambda stored in
  // an inferred variable, both then invoked. Drives the function-type branch of
  // `generateASTType` and `generateASTExpressionLiteralFunction`.
  _Program('lambdas', 'Ops', r'''
class Ops {
  int apply(int a) {
    int Function(int) f = (int x) { return x * 2; };
    return f(a);
  }

  int combine(int a, int b) {
    var adder = (int x, int y) { return x + y; };
    return adder(a, b);
  }
}
'''),

  // Import statements plus a class holding a Map<String, List<int>> and a 2D
  // array field. Drives `generateASTStatementImport` alongside more
  // generic-type and nested-collection emission.
  _Program('imports', 'Grid', r'''
import 'dart:math';
import 'dart:collection';

class Grid {
  Map<String, List<int>> rows = {'top': [1, 2], 'bottom': [3, 4]};
  List<List<int>> cells = [[1, 2], [3, 4]];

  int firstCell(List<List<int>> m) {
    var row = m[0];
    return row[0];
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
  group('Generator emit coverage: translate construct-heavy programs', () {
    // Each (program, language) pair drives a distinct spread of otherwise
    // uncovered emit methods; each is verified to produce non-empty, plausibly
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
            contains(program.token),
            reason:
                '$language should name "${program.token}" '
                'for ${program.name}',
          );
          expect(
            generated,
            contains(_languageToken[language]!),
            reason:
                '$language output should contain '
                '"${_languageToken[language]}" for ${program.name}',
          );
        });
      }
    }

    // The full program set generates in every language without throwing: a
    // single assertion that this generator surface as a whole is crash-free.
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
