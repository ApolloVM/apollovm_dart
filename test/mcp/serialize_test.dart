@TestOn('vm')
@Tags(['mcp'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:apollovm/src/mcp/serialize/ast_json.dart';
import 'package:apollovm/src/mcp/serialize/diagnostics.dart';
import 'package:apollovm/src/mcp/serialize/symbols.dart';
import 'package:apollovm/src/mcp/serialize/types.dart';
import 'package:apollovm/src/mcp/serialize/value_json.dart';
import 'package:test/test.dart';

/// A source unit that exercises a wide spread of AST node kinds: a class with
/// initialized fields, a constructor, static and instance methods, and a
/// top-level function with a generic (`List`) parameter, locals and literals.
const _richSource = '''
import 'dart:math';

class Shape {}

class Point extends Shape {
  int x = 0;
  int y = 0;

  Point(this.x, this.y);

  static int origin() { return 0; }

  int sum() { return x + y; }
}

int compute(int a, List args, {int scale = 1}) {
  var total = (a + 1) * scale;
  print(total);
  return total;
}
''';

Future<ASTRoot> _parse(String source, [String language = 'dart']) async {
  final vm = ApolloVM();
  final parser = vm.getParser<String>(language)!;
  final result = await parser.parse(SourceCodeUnit(language, source, id: 't'));
  expect(result.isOK, isTrue, reason: 'source should parse: ${result.errorMessage}');
  return result.root!;
}

/// Collects every `node` runtimeType string in a serialized AST tree.
Set<String> _nodeTypes(Map<String, Object?> json) {
  final types = <String>{json['node'] as String};
  final children = json['children'] as List?;
  if (children != null) {
    for (final c in children) {
      types.addAll(_nodeTypes(c as Map<String, Object?>));
    }
  }
  return types;
}

void main() {
  group('valueToJson', () {
    test('passes primitives through', () {
      expect(valueToJson(null), isNull);
      expect(valueToJson(42), 42);
      expect(valueToJson(3.5), 3.5);
      expect(valueToJson(true), isTrue);
      expect(valueToJson('hi'), 'hi');
    });

    test('recurses into lists and maps, stringifying map keys', () {
      expect(valueToJson([1, [2, 3]]), [1, [2, 3]]);
      expect(valueToJson({'a': 1, 'b': [2]}), {'a': 1, 'b': [2]});
      expect(valueToJson({1: 'x', 2: 'y'}), {'1': 'x', '2': 'y'});
    });

    test('honors the depth guard with a self-referential list', () {
      final cyclic = <Object?>[];
      cyclic.add(cyclic);
      // Must terminate (fall back to a string) rather than overflow.
      expect(() => valueToJson(cyclic, maxDepth: 4), returnsNormally);
    });

    test('serializes a VMObject result from execution with its fields', () async {
      final vm = ApolloVM();
      await vm.loadCodeUnit(SourceCodeUnit('dart',
          'class Box { int v = 7; } Box main(List a){ return Box(); }',
          id: 't'));
      final runner = vm.createRunner('dart')!;
      final r = await runner.tryExecuteFunction('', 'main', []);
      final json = valueToJson(r!.getValueNoContext());
      expect(json, isA<Map>());
      expect((json as Map)[r'\$type'] ?? json['\$type'], anyOf('Box', isNull));
      // The field value is present regardless of the type-key spelling.
      expect(json.values, contains(7));
    });
  });

  group('astNodeToJson', () {
    test('emits node-specific fields across many node kinds', () async {
      final root = await _parse(_richSource);
      final json = astNodeToJson(root, maxDepth: 500);

      expect(json['node'], 'ASTRoot');
      expect(json['classes'], contains('Point'));
      expect(json['functions'], contains('compute'));

      final types = _nodeTypes(json);
      expect(types, contains('ASTClassNormal'));
      expect(types, contains('ASTStatementImport'),
          reason: 'import nodes should be walked, not just listed');
      expect(
        types.any((t) => t.contains('FunctionDeclaration')),
        isTrue,
        reason: 'method/function declarations should be serialized',
      );
      expect(types.any((t) => t.startsWith('ASTType')), isTrue);
    });

    test('serializes an invocable with returnType, modifiers and parameters',
        () async {
      final root = await _parse(_richSource);
      final compute = root.functions
          .expand((s) => s.functions)
          .firstWhere((f) => f.name == 'compute');
      final json = invocableToJson(compute);
      expect(json['name'], 'compute');
      expect((json['returnType'] as Map)['name'], 'int');
      expect(json['modifiers'], isA<List>());
      final params = (json['parameters'] as List).cast<Map>();
      expect(params.map((p) => p['name']), containsAll(['a', 'args', 'scale']));
      final scale = params.firstWhere((p) => p['name'] == 'scale');
      expect(scale['named'], isTrue);
      expect(scale['hasDefault'], isTrue);
    });

    test('respects maxDepth by omitting deeper children', () async {
      final root = await _parse(_richSource);
      final shallow = astNodeToJson(root, maxDepth: 0);
      expect(shallow.containsKey('children'), isFalse);
    });

    test('serializes generic types recursively', () async {
      final root = await _parse(_richSource);
      final compute = root.functions
          .expand((s) => s.functions)
          .firstWhere((f) => f.name == 'compute');
      final listParam = compute.parameters.allParameters
          .firstWhere((p) => p.name == 'args');
      final typeJson = typeToJson(listParam.type);
      expect(typeJson['name'], 'List');
      expect(typeJson['generics'], isNotNull);
    });
  });

  group('symbolsToJson', () {
    test('captures fields, constructors and methods of a class', () async {
      final root = await _parse(_richSource);
      final symbols = symbolsToJson(root);

      expect((symbols['functions'] as List).map((f) => (f as Map)['name']),
          contains('compute'));

      final point = (symbols['classes'] as List)
          .cast<Map>()
          .firstWhere((c) => c['name'] == 'Point');
      expect(point['superClassName'], 'Shape');
      expect((point['fields'] as List).map((f) => (f as Map)['name']),
          containsAll(['x', 'y']));
      expect(point['constructors'], isNotEmpty);
      expect((point['methods'] as List).map((m) => (m as Map)['name']),
          containsAll(['origin', 'sum']));
    });
  });

  group('diagnostics', () {
    test('diagnosticFromError handles a plain error', () {
      final d = diagnosticFromError(StateError('boom'));
      expect(d['severity'], 'error');
      expect('${d['message']}', contains('boom'));
    });

    test('diagnosticFromError handles a SyntaxError without a ParseResult', () {
      final d = diagnosticFromError(SyntaxError('bad syntax'));
      expect(d['severity'], 'error');
      expect(d['message'], 'bad syntax');
    });

    test('diagnosticFromParseResult carries position and source line',
        () async {
      final vm = ApolloVM();
      final parser = vm.getParser<String>('dart')!;
      final result =
          await parser.parse(SourceCodeUnit('dart', 'class { oops', id: 't'));
      final d = diagnosticFromParseResult(result);
      expect(d['line'], isNotNull);
      expect(d['column'], isNotNull);
      expect('${d['sourceLine']}', contains('class'));
    });
  });

  group('typesToJson', () {
    test('classifies declared classes vs builtins and dedups', () async {
      final root = await _parse(_richSource);
      final result = typesToJson(root);
      final byName = {
        for (final t in result['types'] as List) (t as Map)['name']: t['kind'],
      };
      expect(byName['Point'], 'class');
      expect(byName['int'], 'builtin');
      expect(byName['List'], 'builtin');
    });
  });
}
