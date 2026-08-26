// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

@TestOn('vm')
@Tags(['mcp'])
library;

import 'package:apollovm/apollovm_mcp.dart';
import 'package:test/test.dart';

const _src = '''
class Foo {
  /// Doubles [x] and adds [y].
  static int calc(int x, int y) {
    var doubled = x * 2;
    return doubled + y;
  }

  static int run() {
    return calc(10, 5);
  }
}
''';

/// `computeTool` with default limits.
Future<Map<String, Object?>> _call(String name, Map<String, Object?> args) =>
    computeTool(name, args, const McpLimits());

void main() {
  group('LSP MCP tools — registration', () {
    test('all lsp tools are advertised and registered', () {
      expect(allToolNames, containsAll(lspToolNames));
      final built = buildLspTools().map((t) => t.name).toSet();
      expect(built, equals(lspToolNames.toSet()));
      expect(lspToolNames, hasLength(7));
      for (final n in lspToolNames) {
        expect(isLspTool(n), isTrue, reason: n);
      }
      expect(isLspTool('apollovm.parse'), isFalse);
    });

    test('supported languages exclude wasm', () {
      expect(LspRuntime.supportedLanguages, contains('dart'));
      expect(LspRuntime.supportedLanguages, contains('python'));
      expect(LspRuntime.supportedLanguages, contains('apollo'));
      expect(LspRuntime.supportedLanguages, isNot(contains('wasm')));
    });

    test('apollo source analyzes through the LSP runtime', () async {
      var result = await LspRuntime().diagnostics('apollo', r'''
class Greeter {
  String name
  Greeter(this.name)
  String hello() { return "hi $name" }
}
''');

      expect(result['ok'], isTrue);
      expect(result['diagnostics'], isEmpty);
    });
  });

  group('apollovm.lsp.diagnostics', () {
    test('clean source reports no diagnostics', () async {
      final r = await _call('apollovm.lsp.diagnostics', {
        'language': 'dart',
        'source': _src,
      });
      expect(r['isError'], isFalse);
      expect(r['ok'], isTrue);
      expect(r['diagnostics'], isEmpty);
    });

    test('broken source reports an error with a range', () async {
      final r = await _call('apollovm.lsp.diagnostics', {
        'language': 'dart',
        'source': 'class Foo {\n  static int calc( {\n}\n',
      });
      expect(r['isError'], isFalse);
      expect(r['ok'], isFalse);
      final diags = r['diagnostics'] as List;
      expect(diags, isNotEmpty);
      expect((diags.first as Map)['severity'], 1); // error
      expect((diags.first as Map)['range'], isA<Map>());
    });
  });

  test('apollovm.lsp.symbols returns a nested outline', () async {
    final r = await _call('apollovm.lsp.symbols', {
      'language': 'dart',
      'source': _src,
    });
    final symbols = (r['symbols'] as List).cast<Map>();
    final foo = symbols.firstWhere((s) => s['name'] == 'Foo');
    expect(foo['kind'], isNotNull);
    final children = (foo['children'] as List).cast<Map>();
    expect(children.map((c) => c['name']), containsAll(['calc', 'run']));
    expect(foo['range'], isA<Map>());
  });

  group('apollovm.lsp.hover', () {
    test('returns markup with signature and doc', () async {
      // `calc` is the method name on line 2.
      final r = await _call('apollovm.lsp.hover', {
        'language': 'dart',
        'source': _src,
        'line': 2,
        'character': 13,
      });
      final hover = r['hover'] as Map;
      final value = (hover['contents'] as Map)['value'] as String;
      expect(value, contains('calc'));
      expect(value, contains('Doubles'));
    });

    test('off an identifier returns null hover', () async {
      final r = await _call('apollovm.lsp.hover', {
        'language': 'dart',
        'source': _src,
        'line': 6,
        'character': 0,
      });
      expect(r['isError'], isFalse);
      expect(r['hover'], isNull);
    });
  });

  test('apollovm.lsp.definition resolves a call to its declaration', () async {
    // 2nd `calc` (the call inside `run`) is on line 8.
    final r = await _call('apollovm.lsp.definition', {
      'language': 'dart',
      'source': _src,
      'line': 8,
      'character': 11,
    });
    final def = r['definition'] as Map;
    final start = (def['range'] as Map)['start'] as Map;
    expect(start['line'], 2); // declaration line
  });

  test('apollovm.lsp.references finds all occurrences', () async {
    final r = await _call('apollovm.lsp.references', {
      'language': 'dart',
      'source': _src,
      'line': 2,
      'character': 13,
    });
    final refs = r['references'] as List;
    expect(refs.length, 2); // declaration + call site
  });

  test('apollovm.lsp.completion proposes symbols and keywords', () async {
    final r = await _call('apollovm.lsp.completion', {
      'language': 'dart',
      'source': _src,
      'line': 4,
      'character': 8,
    });
    final items = ((r['completion'] as Map)['items'] as List).cast<Map>();
    final labels = items.map((i) => i['label']).toSet();
    expect(labels, contains('calc'));
    expect(labels, contains('return'));
  });

  group('apollovm.lsp.workspaceSymbols', () {
    test('searches declarations across multiple files', () async {
      final r = await _call('apollovm.lsp.workspaceSymbols', {
        'query': 'calc',
        'files': [
          {'uri': 'file:///a.dart', 'source': 'class A { int calc() => 1; }'},
          {'uri': 'file:///b.dart', 'source': 'int helper() => 0;'},
        ],
      });
      expect(r['isError'], isFalse);
      final names = (r['symbols'] as List).map((s) => (s as Map)['name']);
      expect(names, contains('calc'));
      expect(names, isNot(contains('helper')));
      expect(r['files'], ['file:///a.dart', 'file:///b.dart']);
    });

    test('infers a language for a file lacking a known extension', () async {
      final r = await _call('apollovm.lsp.workspaceSymbols', {
        'query': '',
        'files': [
          {'uri': 'snippet', 'source': 'int total() => 0;', 'language': 'dart'},
        ],
      });
      final names = (r['symbols'] as List).map((s) => (s as Map)['name']);
      expect(names, contains('total'));
    });

    test('synthesizes a URI for a file with no uri', () async {
      final r = await _call('apollovm.lsp.workspaceSymbols', {
        'query': 'total',
        'files': [
          {'source': 'int total() => 0;', 'language': 'dart'},
        ],
      });
      expect(r['isError'], isFalse);
      expect((r['files'] as List).single, 'file:///mcp/file0.dart');
      final names = (r['symbols'] as List).map((s) => (s as Map)['name']);
      expect(names, contains('total'));
    });

    test('rejects a workspace exceeding maxSourceChars', () async {
      final r = await computeTool('apollovm.lsp.workspaceSymbols', {
        'query': '',
        'files': [
          {'uri': 'file:///a.dart', 'source': 'class A {}'},
          {'uri': 'file:///b.dart', 'source': 'class B {}'},
        ],
      }, const McpLimits(maxSourceChars: 12));
      expect(r['isError'], isTrue);
    });
  });

  group('language selection & limits', () {
    test('parser is chosen from the language, not a mismatched URI', () async {
      // A `.py` URI must not force the Python parser when language is dart.
      final r = await _call('apollovm.lsp.symbols', {
        'language': 'dart',
        'source': _src,
        'uri': 'file:///thing.py',
      });
      final names = (r['symbols'] as List).map((s) => (s as Map)['name']);
      expect(names, contains('Foo'));
    });

    test('unsupported language is a tool error', () async {
      final r = await _call('apollovm.lsp.hover', {
        'language': 'brainfuck',
        'source': '++',
        'line': 0,
        'character': 0,
      });
      expect(r['isError'], isTrue);
      expect((r['diagnostics'] as List), isNotEmpty);
    });

    test('source exceeding maxSourceChars is rejected', () async {
      final r = await computeTool('apollovm.lsp.diagnostics', {
        'language': 'dart',
        'source': 'class A {}',
      }, const McpLimits(maxSourceChars: 4));
      expect(r['isError'], isTrue);
    });
  });

  test('computeLspTool rejects an unknown lsp tool name', () async {
    final r = await computeLspTool(
      'apollovm.lsp.bogus',
      const {},
      const McpLimits(),
    );
    expect(r['isError'], isTrue);
    expect((r['diagnostics'] as List), isNotEmpty);
  });

  test('runs identically inside an isolate', () async {
    final r = await computeToolIsolated('apollovm.lsp.symbols', {
      'language': 'dart',
      'source': _src,
    }, const McpLimits());
    final names = (r['symbols'] as List).map((s) => (s as Map)['name']);
    expect(names, contains('Foo'));
  });
}
