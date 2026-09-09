@TestOn('vm')
@Tags(['mcp'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:apollovm/apollovm.dart' show ApolloVM;
import 'package:apollovm/apollovm_mcp_io.dart';
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
    test(
      'emits the core + LSP tools (no repo tools without a workspace)',
      () async {
        final tools = jsonDecode(await runMcp(['list'])) as List;
        final names = tools.map((t) => (t as Map)['name']);
        expect(names, containsAll(allToolNames));
        // The repository tools are only surfaced when a workspace is configured.
        expect(names, isNot(contains('apollovm.fs.read')));
        for (final t in tools) {
          // Every tool advertises an object input schema (properties may be empty
          // for no-argument tools such as apollovm.git.status).
          expect((t as Map)['inputSchema'], isA<Map>());
          expect((t['inputSchema'] as Map)['properties'], isA<Map>());
        }
      },
    );

    test('includes the repository tools with --workspace', () async {
      final tools =
          jsonDecode(await runMcp(['list', '--workspace', '.'])) as List;
      final names = tools.map((t) => (t as Map)['name']);
      expect(names, containsAll(allToolNames));
      expect(names, containsAll(repoToolNames));
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
      expect(output, contains('${allToolNames.length} tools registered'));
      expect(output, contains('apollovm.execute'));
      expect(output, contains('apollovm.wasm'));
    });
  });

  group('mcp with no subcommand', () {
    test('is a usage error that lists every subcommand', () async {
      await expectLater(
        runMcp([]),
        throwsA(
          isA<UsageException>().having(
            (e) => e.toString(),
            'usage',
            allOf([
              contains('Available subcommands:'),
              for (final sub in ['serve', 'list', 'call', 'info', 'schema'])
                contains(sub),
            ]),
          ),
        ),
      );
    });

    test('the command itself falls back to printing its usage', () {
      // `args` rejects a bare parent command before dispatching, so this
      // fallback is only reachable by invoking the command directly.
      final runner = CommandRunner<bool>('apollovm', 'test')
        ..addCommand(CommandMcp());
      final mcp = runner.commands['mcp'] as CommandMcp;

      final out = StringBuffer();
      final ok = runZoned(
        mcp.run,
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, line) => out.writeln(line),
        ),
      );

      expect(ok, isTrue);
      expect(out.toString(), contains('Available subcommands:'));
    });
  });

  group('mcp schema without a tool name', () {
    test('prints every tool schema, keyed by tool name', () async {
      final schemas = jsonDecode(await runMcp(['schema'])) as Map;
      expect(schemas.keys, containsAll(allToolNames));
      for (final schema in schemas.values) {
        expect((schema as Map)['properties'], isA<Map>());
      }
    });

    test('includes the repository tools with --workspace', () async {
      final schemas =
          jsonDecode(await runMcp(['schema', '--workspace', '.'])) as Map;
      expect(schemas.keys, containsAll(repoToolNames));
    });
  });

  group('mcp info as text', () {
    test(
      'prints the server, protocol, transports, languages and limits',
      () async {
        final out = await runMcp(['info']);
        expect(out, contains('server:     apollovm-mcp ${ApolloVM.VERSION}'));
        expect(out, contains('protocol:   '));
        expect(out, contains('transports: stdio, http-sse'));
        expect(out, contains('languages:  '));
        expect(out, contains('limits:     timeoutMs='));
        // Without a workspace, the repo tools are only advertised as available.
        expect(out, contains('available with --workspace'));
      },
    );

    test('lists the repository tools when a workspace is given', () async {
      final out = await runMcp(['info', '--workspace', '.']);
      expect(out, contains('repo tools: '));
      expect(out, contains(repoToolNames.first));
    });

    test('the JSON form names the repository tools too', () async {
      final info =
          jsonDecode(await runMcp(['info', '--json', '--workspace', '.']))
              as Map;
      expect(info['repositoryTools'], containsAll(repoToolNames));
    });
  });

  group('resource-limit options', () {
    test('a non-integer limit is rejected, naming the option', () {
      expect(
        runMcp([
          'call',
          'parse',
          '-l',
          'dart',
          '-s',
          'x',
          '--timeout-ms',
          'abc',
        ]),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Invalid integer for --timeout-ms'),
          ),
        ),
      );
    });
  });

  group('mcp call --null-safety', () {
    // The flag is the same server default the serve path applies; `call` builds
    // its own args map, so it has to set it explicitly.
    const bad =
        'class Foo { static void main(int a, int? b) { var c = a + b; } }';

    test('reports the finding on a parse-based tool', () async {
      final out = await runMcp([
        'call',
        'parse',
        '-l',
        'dart',
        '-s',
        bad,
        '--null-safety',
      ]);
      expect(out, contains('unchecked-nullable-operand'));
    });

    test('reports nothing without the flag', () async {
      final out = await runMcp(['call', 'parse', '-l', 'dart', '-s', bad]);
      expect(out, isNot(contains('unchecked-nullable-operand')));
    });
  });
}
