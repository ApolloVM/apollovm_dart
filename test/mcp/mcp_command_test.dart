@TestOn('vm')
@Tags(['mcp'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:apollovm/apollovm.dart' show ApolloVM;
import 'package:apollovm/apollovm_mcp.dart';
import 'package:args/command_runner.dart';
import 'package:test/test.dart';

/// Runs `apollovm mcp <args...>` through a real [CommandRunner], capturing
/// everything written to stdout via `print`.
Future<String> runMcp(List<String> args) async {
  final out = StringBuffer();
  final runner = CommandRunner<bool>('apollovm', 'test')
    ..addCommand(CommandMcp());
  await runZoned(
    () => runner.run(['mcp', ...args]),
    zoneSpecification: ZoneSpecification(
      print: (_, _, _, line) => out.writeln(line),
    ),
  );
  return out.toString();
}

void main() {
  group('mcp list', () {
    test('emits all seven tool definitions with input schemas', () async {
      final tools = jsonDecode(await runMcp(['list'])) as List;
      expect(tools.map((t) => (t as Map)['name']), containsAll(allToolNames));
      for (final t in tools) {
        expect((t as Map)['inputSchema'], isA<Map>());
        expect((t['inputSchema'] as Map)['properties'], isNotEmpty);
      }
    });
  });

  group('mcp info', () {
    test('reports server, protocol, languages and limits as JSON', () async {
      final info = jsonDecode(await runMcp(['info', '--json'])) as Map;
      expect(info['server'], 'apollovm-mcp');
      expect(info['version'], ApolloVM.VERSION);
      expect(info['transports'], containsAll(['stdio', 'http-sse']));
      expect(info['languages'], contains('go'));
      expect((info['limits'] as Map)['timeoutMs'], 5000);
    });
  });

  group('mcp schema', () {
    test('prints a single tool schema (bare name accepted)', () async {
      final schema = jsonDecode(await runMcp(['schema', 'execute'])) as Map;
      expect(
        (schema['properties'] as Map).keys,
        containsAll(['language', 'source']),
      );
      expect(schema['required'], containsAll(['language', 'source']));
    });

    test('rejects an unknown tool', () {
      expect(runMcp(['schema', 'nope']), throwsA(isA<StateError>()));
    });
  });

  group('mcp call', () {
    test('executes source passed via --source', () async {
      final r =
          jsonDecode(
                await runMcp([
                  'call',
                  'execute',
                  '-l',
                  'dart',
                  '-s',
                  'int main(List a){ print("cli"); return 7; }',
                ]),
              )
              as Map;
      expect(r['isError'], isFalse);
      expect(r['result'], 7);
      expect(r['output'], ['cli']);
    });

    test('translates go->dart', () async {
      final r =
          jsonDecode(
                await runMcp([
                  'call',
                  'translate',
                  '--from',
                  'go',
                  '--to',
                  'dart',
                  '-s',
                  'package main\nfunc Add(a int, b int) int { return a + b }\n',
                ]),
              )
              as Map;
      expect(r['isError'], isFalse);
      expect(r['generated'], contains('int Add(int a, int b)'));
    });

    test('errors on an unknown tool', () {
      expect(runMcp(['call', 'bogus', '-s', 'x']), throwsA(isA<StateError>()));
    });
  });

  group('mcp doctor', () {
    test('runs the capability checks and reports the tool count', () async {
      final output = await runMcp(['doctor']);
      expect(output, contains('7 tools registered'));
      expect(output, contains('apollo.execute'));
      expect(output, contains('apollo.wasm'));
    });
  });
}
