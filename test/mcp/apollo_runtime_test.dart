@TestOn('vm')
@Tags(['mcp'])
library;

import 'package:apollovm/apollovm_mcp.dart';
import 'package:test/test.dart';

void main() {
  group('isolate execution (apollovm.execute)', () {
    test('a synchronous infinite loop is killed at the timeout', () async {
      final limits = const McpLimits(timeoutMs: 500);
      final sw = Stopwatch()..start();
      final result = await computeToolIsolated('apollovm.execute', {
        'language': 'dart',
        'source': 'void main(List a){ while(true){} }',
      }, limits);
      sw.stop();

      expect(
        result['isError'],
        isTrue,
        reason: 'runaway loop must be reported as an error',
      );
      final diag = (result['diagnostics'] as List).first as Map;
      expect('${diag['message']}', contains('timed out'));
      // The isolate kill must land promptly (well under a hang).
      expect(sw.elapsedMilliseconds, lessThan(4000));
    });

    test('a thrown error is isolated and reported', () async {
      final limits = const McpLimits(timeoutMs: 2000);
      final result = await computeToolIsolated('apollovm.execute', {
        'language': 'dart',
        'source': 'int main(List a){ throw StateError("boom"); }',
      }, limits);
      expect(result['isError'], isTrue);
      expect(result['diagnostics'], isNotEmpty);
    });
  });

  group('in-process execution', () {
    test('captured output is truncated at maxOutputChars', () async {
      final limits = const McpLimits(maxOutputChars: 10);
      final result = await computeTool('apollovm.execute', {
        'language': 'dart',
        'source':
            'void main(List a){ print("0123456789ABCDEF"); print("more"); }',
      }, limits);
      expect(result['truncated'], isTrue);
      final output = (result['output'] as List).join();
      expect(output.length, lessThanOrEqualTo(10));
    });

    test('source over maxSourceChars is rejected', () async {
      final limits = const McpLimits(maxSourceChars: 5);
      final result = await computeTool('apollovm.parse', {
        'language': 'dart',
        'source': 'int main(List a){ return 1; }',
      }, limits);
      expect(result['isError'], isTrue);
      final diag = (result['diagnostics'] as List).first as Map;
      expect('${diag['message']}', contains('maxSourceChars'));
    });

    test('executes a class method (non-static) via className', () async {
      final result = await computeTool('apollovm.execute', {
        'language': 'dart',
        'source': 'class Foo { int run(List a){ return 7; } }',
        'function': 'run',
        'className': 'Foo',
      }, const McpLimits());
      expect(result['isError'], isFalse);
      expect(result['result'], 7);
    });

    test('reports when the entry function is missing', () async {
      final result = await computeTool('apollovm.execute', {
        'language': 'dart',
        'source': 'int other(){ return 1; }',
      }, const McpLimits());
      expect(result['isError'], isTrue);
      expect(
        '${(result['diagnostics'] as List).first}',
        contains('Entry function not found'),
      );
    });
  });

  group('error paths', () {
    const src = 'int main(List a){ return 1; }';

    test('unsupported language is rejected by every tool', () async {
      for (final tool in [
        'apollovm.parse',
        'apollovm.execute',
        'apollovm.wasm',
      ]) {
        final r = await computeTool(tool, {
          'language': 'ruby',
          'source': src,
        }, const McpLimits());
        expect(r['isError'], isTrue, reason: '$tool should reject ruby');
        expect(
          '${(r['diagnostics'] as List).first}',
          contains('Unsupported language'),
        );
      }
    });

    test('translate to a language without a generator errors', () async {
      final r = await computeTool('apollovm.translate', {
        'from': 'dart',
        'to': 'ruby',
        'source': src,
      }, const McpLimits());
      expect(r['isError'], isTrue);
      expect(r['generated'], isNull);
      expect(r['diagnostics'], isNotEmpty);
    });

    test('an unknown tool name yields an error result', () async {
      final r = await computeTool(
        'apollovm.bogus',
        const {},
        const McpLimits(),
      );
      expect(r['isError'], isTrue);
      expect('${(r['diagnostics'] as List).first}', contains('Unknown tool'));
    });

    test(
      'execute on broken source returns parse diagnostics (in-process)',
      () async {
        final r = await computeTool('apollovm.execute', {
          'language': 'dart',
          'source': 'int main(List a){ return',
        }, const McpLimits());
        expect(r['isError'], isTrue);
        expect(r['diagnostics'], isNotEmpty);
      },
    );

    test('a runtime error during in-process execution is caught', () async {
      final r = await computeTool(
        'apollovm.execute',
        {
          'language': 'dart',
          'source': 'int main(List a){ throw StateError("kaboom"); }',
        },
        // in-process (not an isolate tool) so the execute() catch runs here.
        const McpLimits(isolateTools: {}),
      );
      expect(r['isError'], isTrue);
      expect('${(r['diagnostics'] as List).first}', contains('kaboom'));
    });

    test('execute passes a String[] arg list to a top-level main', () async {
      final r = await computeTool('apollovm.execute', {
        'language': 'dart',
        'source': 'void main(List<String> a){ print(a[0]); }',
        'args': ['hello', 'world'],
      }, const McpLimits(isolateTools: {}));
      expect(r['isError'], isFalse);
      expect(r['output'], ['hello']);
    });
  });

  group('McpLimits', () {
    test('defaults, runsInIsolate, copyWith and toString', () {
      const limits = McpLimits();
      expect(limits.timeoutMs, 5000);
      expect(limits.runsInIsolate('apollovm.execute'), isTrue);
      expect(limits.runsInIsolate('apollovm.parse'), isFalse);

      final custom = limits.copyWith(
        timeoutMs: 100,
        maxOutputChars: 10,
        maxSourceChars: 20,
        maxAstDepth: 5,
        isolateTools: const {'apollovm.wasm'},
      );
      expect(custom.timeoutMs, 100);
      expect(custom.maxOutputChars, 10);
      expect(custom.maxSourceChars, 20);
      expect(custom.maxAstDepth, 5);
      expect(custom.runsInIsolate('apollovm.wasm'), isTrue);
      expect(custom.runsInIsolate('apollovm.execute'), isFalse);
      expect(custom.toString(), contains('timeoutMs: 100'));

      // copyWith with no overrides preserves every field.
      final same = custom.copyWith();
      expect(same.timeoutMs, custom.timeoutMs);
      expect(same.maxOutputChars, custom.maxOutputChars);
      expect(same.maxSourceChars, custom.maxSourceChars);
      expect(same.maxAstDepth, custom.maxAstDepth);
      expect(same.isolateTools, custom.isolateTools);
    });
  });
}
