@TestOn('vm')
@Tags(['mcp'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:apollovm/apollovm.dart' show ApolloVM;
import 'package:apollovm/apollovm_mcp.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

/// Drives an [ApolloMcpServer] over an in-memory [StreamChannel], speaking raw
/// JSON-RPC 2.0 so the tests exercise the real protocol surface.
class McpTestClient {
  final StreamChannelController<String> _ctrl;
  int _id = 0;
  final Map<int, Completer<Map<String, Object?>>> _pending = {};

  McpTestClient._(this._ctrl) {
    _ctrl.foreign.stream.listen((line) {
      final msg = jsonDecode(line) as Map<String, Object?>;
      final id = msg['id'];
      if (id is int) _pending.remove(id)?.complete(msg);
    });
  }

  factory McpTestClient(McpLimits limits) {
    final ctrl = StreamChannelController<String>(allowForeignErrors: false);
    ApolloMcpServer(ctrl.local, limits: limits);
    return McpTestClient._(ctrl);
  }

  Future<Map<String, Object?>> request(
    String method, [
    Map<String, Object?>? params,
  ]) {
    final id = ++_id;
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    _ctrl.foreign.sink.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': ?params,
      }),
    );
    return completer.future.timeout(const Duration(seconds: 15));
  }

  Future<void> initialize() async {
    await request('initialize', {
      'protocolVersion': '2024-11-05',
      'capabilities': <String, Object?>{},
      'clientInfo': {'name': 'test', 'version': '1.0'},
    });
    _ctrl.foreign.sink.add(
      jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}),
    );
  }

  /// Calls a tool and returns its decoded JSON payload (the text content).
  Future<Map<String, Object?>> callTool(
    String name,
    Map<String, Object?> arguments,
  ) async {
    final resp = await request('tools/call', {
      'name': name,
      'arguments': arguments,
    });
    final result = resp['result'] as Map<String, Object?>;
    final content = (result['content'] as List).first as Map<String, Object?>;
    return <String, Object?>{
      '_isError': result['isError'] ?? false,
      ...jsonDecode(content['text'] as String) as Map<String, Object?>,
    };
  }

  Future<void> close() => _ctrl.local.sink.close();
}

void main() {
  const dartSource = '''
class Calc {
  int add(int a, int b) { return a + b; }
  int main(List args) {
    print('running');
    return add(40, 2);
  }
}
''';

  late McpTestClient client;

  setUp(() => client = McpTestClient(const McpLimits(timeoutMs: 2000)));
  tearDown(() => client.close());

  group('protocol', () {
    test('initialize returns serverInfo with the ApolloVM version', () async {
      final resp = await client.request('initialize', {
        'protocolVersion': '2024-11-05',
        'capabilities': <String, Object?>{},
        'clientInfo': {'name': 'test', 'version': '1.0'},
      });
      final result = resp['result'] as Map<String, Object?>;
      final serverInfo = result['serverInfo'] as Map<String, Object?>;
      expect(serverInfo['name'], 'apollovm-mcp');
      expect(serverInfo['version'], ApolloVM.VERSION);
    });

    test('tools/list returns the 7 tools each with an inputSchema', () async {
      await client.initialize();
      final resp = await client.request('tools/list');
      final tools = (resp['result'] as Map)['tools'] as List;
      final names = tools.map((t) => (t as Map)['name']).toSet();
      expect(names, {
        'apollo.parse',
        'apollo.execute',
        'apollo.translate',
        'apollo.ast',
        'apollo.symbols',
        'apollo.types',
        'apollo.wasm',
      });
      for (final t in tools) {
        final schema = (t as Map)['inputSchema'] as Map;
        expect(schema['properties'], isNotEmpty);
      }
    });
  });

  group('tools', () {
    setUp(() => client.initialize());

    test('apollo.parse returns a summary for valid source', () async {
      final r = await client.callTool('apollo.parse', {
        'language': 'dart',
        'source': dartSource,
      });
      expect(r['_isError'], isFalse);
      expect(r['ok'], isTrue);
      final summary = r['summary'] as Map;
      expect(summary['classes'], contains('Calc'));
    });

    test('apollo.parse on broken source returns line/column diagnostics',
        () async {
      final r = await client.callTool('apollo.parse', {
        'language': 'dart',
        'source': 'class { oops',
      });
      expect(r['_isError'], isTrue);
      expect(r['ok'], isFalse);
      final diag = (r['diagnostics'] as List).first as Map;
      expect(diag['severity'], 'error');
      expect(diag['line'], isNotNull);
      expect(diag['column'], isNotNull);
      expect(diag['sourceLine'], contains('class'));
    });

    test('apollo.execute returns result and captured output', () async {
      final r = await client.callTool('apollo.execute', {
        'language': 'dart',
        'source': dartSource,
      });
      expect(r['_isError'], isFalse);
      expect(r['result'], 42);
      expect(r['output'], ['running']);
    });

    test('apollo.translate dart->python produces source', () async {
      final r = await client.callTool('apollo.translate', {
        'from': 'dart',
        'to': 'python',
        'source': dartSource,
      });
      expect(r['_isError'], isFalse);
      expect(r['generated'], contains('def add'));
    });

    test('apollo.ast returns the root node', () async {
      final r = await client.callTool('apollo.ast', {
        'language': 'dart',
        'source': dartSource,
      });
      expect(r['_isError'], isFalse);
      final ast = r['ast'] as Map;
      expect(ast['node'], 'ASTRoot');
      expect(ast['classes'], contains('Calc'));
    });

    test('apollo.symbols returns the symbol graph', () async {
      final r = await client.callTool('apollo.symbols', {
        'language': 'dart',
        'source': dartSource,
      });
      expect(r['_isError'], isFalse);
      final symbols = r['symbols'] as Map;
      final classes = symbols['classes'] as List;
      final calc = classes.first as Map;
      expect(calc['name'], 'Calc');
      final methods = (calc['methods'] as List).map((m) => (m as Map)['name']);
      expect(methods, containsAll(['add', 'main']));
    });

    test('apollo.types returns a classified type table', () async {
      final r = await client.callTool('apollo.types', {
        'language': 'dart',
        'source': dartSource,
      });
      expect(r['_isError'], isFalse);
      final types = r['types'] as List;
      final byName = {
        for (final t in types) (t as Map)['name']: t['kind'],
      };
      expect(byName['Calc'], 'class');
      expect(byName['int'], 'builtin');
    });

    test('apollo.wasm returns a base64 module with the \\0asm magic', () async {
      final r = await client.callTool('apollo.wasm', {
        'language': 'dart',
        'source': 'int run(int a, int b) { return a + b; }',
      });
      expect(r['_isError'], isFalse);
      final modules = r['modules'] as List;
      final bytes = base64.decode((modules.first as Map)['base64'] as String);
      expect(bytes.sublist(0, 4), [0x00, 0x61, 0x73, 0x6D]);
    });

    test('supports Go: execute and translate go->dart', () async {
      const goSource = '''
package main
import "fmt"
func Add(a int, b int) int {
	return a + b
}
func main() {
	fmt.Println(Add(40, 2))
}
''';

      final exec = await client.callTool('apollo.execute', {
        'language': 'go',
        'source': goSource,
      });
      expect(exec['_isError'], isFalse);
      expect(exec['output'], contains('42'));

      final translated = await client.callTool('apollo.translate', {
        'from': 'go',
        'to': 'dart',
        'source': goSource,
      });
      expect(translated['_isError'], isFalse);
      expect(translated['generated'], contains('int Add(int a, int b)'));
    });

    test('unknown tool name yields an error result', () async {
      final resp = await client.request('tools/call', {
        'name': 'apollo.nope',
        'arguments': <String, Object?>{},
      });
      final result = resp['result'] as Map<String, Object?>;
      expect(result['isError'], isTrue);
    });
  });
}
