@TestOn('vm')
@Tags(['mcp'])
library;

import 'package:apollovm/apollovm_mcp.dart';
import 'package:test/test.dart';

void main() {
  group('isolate execution (apollo.execute)', () {
    test('a synchronous infinite loop is killed at the timeout', () async {
      final limits = const McpLimits(timeoutMs: 500);
      final sw = Stopwatch()..start();
      final result = await computeToolIsolated(
        'apollo.execute',
        {'language': 'dart', 'source': 'void main(List a){ while(true){} }'},
        limits,
      );
      sw.stop();

      expect(result['isError'], isTrue,
          reason: 'runaway loop must be reported as an error');
      final diag = (result['diagnostics'] as List).first as Map;
      expect('${diag['message']}', contains('timed out'));
      // The isolate kill must land promptly (well under a hang).
      expect(sw.elapsedMilliseconds, lessThan(4000));
    });

    test('a thrown error is isolated and reported', () async {
      final limits = const McpLimits(timeoutMs: 2000);
      final result = await computeToolIsolated(
        'apollo.execute',
        {
          'language': 'dart',
          'source': 'int main(List a){ throw StateError("boom"); }',
        },
        limits,
      );
      expect(result['isError'], isTrue);
      expect(result['diagnostics'], isNotEmpty);
    });
  });

  group('in-process execution', () {
    test('captured output is truncated at maxOutputChars', () async {
      final limits = const McpLimits(maxOutputChars: 10);
      final result = await computeTool(
        'apollo.execute',
        {
          'language': 'dart',
          'source':
              'void main(List a){ print("0123456789ABCDEF"); print("more"); }',
        },
        limits,
      );
      expect(result['truncated'], isTrue);
      final output = (result['output'] as List).join();
      expect(output.length, lessThanOrEqualTo(10));
    });

    test('source over maxSourceChars is rejected', () async {
      final limits = const McpLimits(maxSourceChars: 5);
      final result = await computeTool(
        'apollo.parse',
        {'language': 'dart', 'source': 'int main(List a){ return 1; }'},
        limits,
      );
      expect(result['isError'], isTrue);
      final diag = (result['diagnostics'] as List).first as Map;
      expect('${diag['message']}', contains('maxSourceChars'));
    });
  });
}
