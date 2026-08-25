@TestOn('vm')
@Tags(['mcp'])
library;

import 'package:apollovm/apollovm_mcp.dart';
// `mcpCoerceBool` is an internal helper (like `mcpCoerceInt`, it is not part of
// the public MCP surface), so it is reached through its source library.
import 'package:apollovm/src/mcp/tools/apollo_tools.dart' show mcpCoerceBool;
import 'package:test/test.dart';

/// A nullable parameter used in arithmetic — a null-safety error inside a class
/// method, which is what the tools should surface.
const _bad = r'''
class Foo {
  static void main(int a, int? b) {
    print(a);
    var c = a + b;
    print(c);
  }
}
''';

const _clean = r'''
class Foo {
  static int main(int a, int? b) {
    return a + (b ?? 0);
  }
}
''';

const _limits = McpLimits();

List<Map<String, Object?>> _diagnostics(Map<String, Object?> result) =>
    ((result['diagnostics'] as List?) ?? const []).cast<Map<String, Object?>>();

bool _hasNullSafetyFinding(Map<String, Object?> result) =>
    _diagnostics(result).any((d) => d['code'] == 'unchecked-nullable-operand');

void main() {
  group('nullSafety argument — tools that load code', () {
    test(
      'execute rejects the source, reporting a diagnostic not a throw',
      () async {
        final result = await computeTool('apollovm.execute', {
          'language': 'dart',
          'source': _bad,
          'className': 'Foo',
          'nullSafety': true,
        }, _limits);

        expect(result['isError'], isTrue);
        expect(_hasNullSafetyFinding(result), isTrue);
        // Rejected at load: nothing ran, so nothing was printed.
        expect((result['output'] as List?) ?? const [], isEmpty);
      },
    );

    test('without the argument, execute behaves as before', () async {
      final result = await computeTool('apollovm.execute', {
        'language': 'dart',
        'source': _bad,
        'className': 'Foo',
      }, _limits);

      // It still fails, but at *runtime* — not as a null-safety finding.
      expect(_hasNullSafetyFinding(result), isFalse);
    });

    test('translate rejects the source', () async {
      final result = await computeTool('apollovm.translate', {
        'from': 'dart',
        'to': 'java',
        'source': _bad,
        'nullSafety': true,
      }, _limits);

      expect(result['isError'], isTrue);
      expect(result['generated'], isNull);
      expect(_hasNullSafetyFinding(result), isTrue);
    });

    test('wasm rejects the source', () async {
      final result = await computeTool('apollovm.wasm', {
        'language': 'dart',
        'source': _bad,
        'nullSafety': true,
      }, _limits);

      expect(result['isError'], isTrue);
      expect(_hasNullSafetyFinding(result), isTrue);
    });

    test('a clean source is unaffected', () async {
      final result = await computeTool('apollovm.execute', {
        'language': 'dart',
        'source': _clean,
        'className': 'Foo',
        'args': [5, null],
        'nullSafety': true,
      }, _limits);

      expect(result['isError'], isFalse);
      expect(result['result'], 5);
    });
  });

  group('nullSafety argument — parse-based tools report, never reject', () {
    test('parse lists the finding but still succeeds', () async {
      final result = await computeTool('apollovm.parse', {
        'language': 'dart',
        'source': _bad,
        'nullSafety': true,
      }, _limits);

      // A report, not a failure: the parse itself was fine.
      expect(result['isError'], isFalse);
      expect(result['summary'], isNotNull);
      expect(_hasNullSafetyFinding(result), isTrue);
    });

    test('parse without the argument reports nothing', () async {
      final result = await computeTool('apollovm.parse', {
        'language': 'dart',
        'source': _bad,
      }, _limits);

      expect(result['isError'], isFalse);
      expect(_diagnostics(result), isEmpty);
    });

    test('ast / symbols / types carry the findings too', () async {
      for (final tool in const [
        'apollovm.ast',
        'apollovm.symbols',
        'apollovm.types',
      ]) {
        final result = await computeTool(tool, {
          'language': 'dart',
          'source': _bad,
          'nullSafety': true,
        }, _limits);

        expect(result['isError'], isFalse, reason: tool);
        expect(_hasNullSafetyFinding(result), isTrue, reason: tool);
      }
    });
  });

  group('argument coercion', () {
    test('accepts a bool, and the string/number forms a client may send', () {
      expect(mcpCoerceBool(true), isTrue);
      expect(mcpCoerceBool(false), isFalse);
      expect(mcpCoerceBool('true'), isTrue);
      expect(mcpCoerceBool(' TRUE '), isTrue);
      expect(mcpCoerceBool('false'), isFalse);
      expect(mcpCoerceBool(1), isTrue);
      expect(mcpCoerceBool(0), isFalse);
    });

    test('a missing or unusable value yields null (never throws)', () {
      expect(mcpCoerceBool(null), isNull);
      expect(mcpCoerceBool('yes'), isNull);
      expect(mcpCoerceBool(<String>[]), isNull);
    });

    test('a string "true" enables the check end to end', () async {
      final result = await computeTool('apollovm.parse', {
        'language': 'dart',
        'source': _bad,
        'nullSafety': 'true',
      }, _limits);

      expect(_hasNullSafetyFinding(result), isTrue);
    });

    test('a garbage value falls back to off', () async {
      final result = await computeTool('apollovm.parse', {
        'language': 'dart',
        'source': _bad,
        'nullSafety': 'maybe',
      }, _limits);

      expect(_diagnostics(result), isEmpty);
    });
  });

  group('server default (--null-safety)', () {
    // The server merges its default into `args` at dispatch, so a per-call
    // value must still win. That merge is what makes the default reach a
    // spawned isolate at all.
    Map<String, Object?> merged(
      bool serverDefault,
      Map<String, Object?> call,
    ) => <String, Object?>{if (serverDefault) 'nullSafety': true, ...call};

    test('the default applies when the call omits the argument', () async {
      final result = await computeTool(
        'apollovm.parse',
        merged(true, {'language': 'dart', 'source': _bad}),
        _limits,
      );
      expect(_hasNullSafetyFinding(result), isTrue);
    });

    test('a per-call `false` overrides a server default of true', () async {
      final result = await computeTool(
        'apollovm.parse',
        merged(true, {'language': 'dart', 'source': _bad, 'nullSafety': false}),
        _limits,
      );
      expect(_diagnostics(result), isEmpty);
    });

    test('with the default off, an omitted argument stays off', () async {
      final result = await computeTool(
        'apollovm.parse',
        merged(false, {'language': 'dart', 'source': _bad}),
        _limits,
      );
      expect(_diagnostics(result), isEmpty);
    });
  });

  group('isolate path', () {
    // `apollovm.execute` defaults to isolate execution, and `_IsolateJob`
    // carries only `args`/`limits` — so the argument must survive the boundary.
    test('the argument crosses into the spawned isolate', () async {
      final result = await computeToolIsolated('apollovm.execute', {
        'language': 'dart',
        'source': _bad,
        'className': 'Foo',
        'nullSafety': true,
      }, _limits);

      expect(result['isError'], isTrue);
      expect(_hasNullSafetyFinding(result), isTrue);
    });
  });
}
