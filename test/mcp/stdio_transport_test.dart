@TestOn('vm')
@Tags(['mcp'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:apollovm/apollovm.dart' show ApolloVM;
import 'package:apollovm/apollovm_mcp.dart';
import 'package:test/test.dart';

void main() {
  test('serveStdio answers initialize + a tool call over the given streams',
      () async {
    final input = StreamController<List<int>>();
    final output = StreamController<List<int>>();

    final server = serveStdio(input: input.stream, output: output.sink);

    final responses = StreamIterator(
      output.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .where((l) => l.trim().isNotEmpty)
          .map((l) => jsonDecode(l) as Map<String, Object?>),
    );

    void send(Map<String, Object?> msg) =>
        input.add(utf8.encode('${jsonEncode(msg)}\n'));

    send({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': {
        'protocolVersion': '2024-11-05',
        'capabilities': <String, Object?>{},
        'clientInfo': {'name': 'stdio', 'version': '1.0'},
      },
    });

    expect(await responses.moveNext(), isTrue);
    final serverInfo =
        (responses.current['result'] as Map)['serverInfo'] as Map;
    expect(serverInfo['name'], 'apollovm-mcp');
    expect(serverInfo['version'], ApolloVM.VERSION);

    send({'jsonrpc': '2.0', 'method': 'notifications/initialized'});
    send({
      'jsonrpc': '2.0',
      'id': 2,
      'method': 'tools/call',
      'params': {
        'name': 'apollo.execute',
        'arguments': {
          'language': 'dart',
          'source': 'int main(List a){ return 5; }',
        },
      },
    });

    expect(await responses.moveNext(), isTrue);
    final result = responses.current['result'] as Map<String, Object?>;
    final text = (result['content'] as List).first as Map<String, Object?>;
    final payload = jsonDecode(text['text'] as String) as Map<String, Object?>;
    expect(payload['result'], 5);

    await responses.cancel();
    await server.shutdown();
    await input.close();
  });
}
