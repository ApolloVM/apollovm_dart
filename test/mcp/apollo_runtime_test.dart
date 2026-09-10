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

  group('apollo language', () {
    test('parses and executes through the MCP tools', () async {
      const source = r'''
class Greeter {
  String name
  Greeter(this.name)
  String hello() { return "hi $name" }
}

main(List a) {
  print(new Greeter("world").hello())
}
''';

      final parsed = await computeTool('apollovm.parse', {
        'language': 'apollo',
        'source': source,
      }, const McpLimits());
      expect(parsed['ok'], isTrue);

      final executed = await computeTool('apollovm.execute', {
        'language': 'apollo',
        'source': source,
      }, const McpLimits());
      expect(executed['output'], equals(['hi world']));
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

  group('blank entry names', () {
    // A client that always fills every field sends `""` (or a padded name)
    // rather than omitting it. A blank name must mean "not specified", not a
    // lookup for a class/function whose name is empty.
    const limits = McpLimits(isolateTools: {});
    const topLevel = 'int main(List a){ return 7; }';
    const classOnly = 'class Foo { int run(List a){ return 7; } }';

    test('a blank className is treated as absent', () async {
      for (final className in ['', '   ']) {
        final r = await computeTool('apollovm.execute', {
          'language': 'dart',
          'source': topLevel,
          'className': className,
        }, limits);
        expect(
          r['isError'],
          isFalse,
          reason: 'className "$className" should not scope the lookup',
        );
        expect(r['result'], 7);
      }
    });

    test('a blank className still reaches a class method', () async {
      final r = await computeTool('apollovm.execute', {
        'language': 'dart',
        'source': classOnly,
        'function': 'run',
        'className': '',
      }, limits);
      expect(r['isError'], isFalse);
      expect(r['result'], 7);
    });

    test('a blank function name falls back to main', () async {
      final r = await computeTool('apollovm.execute', {
        'language': 'dart',
        'source': topLevel,
        'function': '',
      }, limits);
      expect(r['isError'], isFalse);
      expect(r['result'], 7);
    });

    test('a padded function name is trimmed', () async {
      final r = await computeTool('apollovm.execute', {
        'language': 'dart',
        'source': topLevel,
        'function': '  main  ',
      }, limits);
      expect(r['isError'], isFalse);
      expect(r['result'], 7);
    });

    test('a padded className and function resolve the class method', () async {
      final r = await computeTool('apollovm.execute', {
        'language': 'dart',
        'source': classOnly,
        'function': ' run ',
        'className': ' Foo ',
      }, limits);
      expect(r['isError'], isFalse);
      expect(r['result'], 7);
    });

    test('a genuinely missing entry is still reported', () async {
      final r = await computeTool('apollovm.execute', {
        'language': 'dart',
        'source': topLevel,
        'function': '  nope  ',
        'className': '  ',
      }, limits);
      expect(r['isError'], isTrue);
      expect(
        '${(r['diagnostics'] as List).first}',
        contains('Entry function not found: nope'),
      );
    });
  });

  group('entry signature mismatch', () {
    // A name that exists but rejects the passed arguments must not be reported
    // as a missing entry: the message has to show what was passed and what is
    // declared, otherwise the caller has no way to fix the call.
    const limits = McpLimits(isolateTools: {});

    Future<String> messageOf(Map<String, Object?> input) async {
      final r = await computeTool('apollovm.execute', input, limits);
      expect(r['isError'], isTrue);
      final diag = (r['diagnostics'] as List).first as Map;
      return '${diag['message']}';
    }

    test(
      'a top-level function with a different signature is described',
      () async {
        final message = await messageOf({
          'language': 'dart',
          'source': 'int main(int a, String b){ return 1; }',
          'args': [1, 2, 3],
        });
        expect(message, contains('No entry function matching'));
        expect(message, contains('`main(int, int, int)`'));
        expect(message, contains('`int main(int a, String b)`'));
        expect(message, isNot(contains('Entry function not found')));
      },
    );

    test('a class method mismatch is qualified with the class', () async {
      final message = await messageOf({
        'language': 'dart',
        'source': 'class Foo { int run(int a){ return 7; } }',
        'function': 'run',
        'className': 'Foo',
        'args': ['x', 'y'],
      });
      expect(message, contains('`Foo.run(String, String)`'));
      expect(message, contains('`int Foo.run(int a)`'));
    });

    test('a method reached by auto-discovery names its class', () async {
      final message = await messageOf({
        'language': 'dart',
        'source': 'class Foo { int run(int a, int b){ return 7; } }',
        'function': 'run',
        'args': ['x'],
      });
      expect(message, contains('`int Foo.run(int a, int b)`'));
    });

    test('every declaration of the name is listed', () async {
      final message = await messageOf({
        'language': 'dart',
        'source':
            'class A { int run(int a){ return 1; } } '
            'class B { int run(bool x, bool y){ return 2; } }',
        'function': 'run',
        'args': [1.5, 2.5, 3.5],
      });
      expect(message, contains('2 functions named `run` exist'));
      expect(message, contains('different signatures'));
      expect(message, contains('`int A.run(int a)`'));
      expect(message, contains('`int B.run(bool x, bool y)`'));
    });

    test('an unknown className is reported as a missing class', () async {
      final message = await messageOf({
        'language': 'dart',
        'source': 'class Foo { int run(int a){ return 7; } }',
        'function': 'run',
        'className': 'Bar',
      });
      expect(message, contains('Entry class not found: Bar'));
      expect(message, contains('`run`'));
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
