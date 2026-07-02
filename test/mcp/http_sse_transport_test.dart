@TestOn('vm')
@Tags(['mcp'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:apollovm/apollovm_mcp.dart';
import 'package:test/test.dart';

void main() {
  late HttpSseTransport transport;
  late HttpClient http;

  setUp(() async {
    transport = HttpSseTransport(limits: const McpLimits());
    await transport.start(port: 0);
    http = HttpClient();
  });

  tearDown(() async {
    http.close(force: true);
    await transport.stop();
  });

  test(
    'SSE endpoint event + POST initialize replies over the stream',
    () async {
      final port = transport.port!;
      final endpoint = Completer<String>();
      final initResult = Completer<Map<String, Object?>>();

      // Open the SSE stream.
      final sseResp = await (await http.getUrl(
        Uri.parse('http://127.0.0.1:$port/sse'),
      )).close();
      expect(sseResp.statusCode, 200);

      late StreamSubscription<String> sub;
      sub = sseResp
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (!line.startsWith('data: ')) return;
            final data = line.substring(6);
            if (data.contains('sessionId') && !endpoint.isCompleted) {
              endpoint.complete(data);
            } else if (data.startsWith('{')) {
              final msg = jsonDecode(data) as Map<String, Object?>;
              if (msg['id'] == 1 && !initResult.isCompleted) {
                initResult.complete(msg['result'] as Map<String, Object?>);
              }
            }
          });

      final endpointPath = await endpoint.future.timeout(
        const Duration(seconds: 5),
      );
      expect(endpointPath, contains('/message?sessionId='));

      // POST initialize to the advertised endpoint.
      final postReq = await http.postUrl(
        Uri.parse('http://127.0.0.1:$port$endpointPath'),
      );
      postReq.headers.contentType = ContentType.json;
      postReq.write(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
          'params': {
            'protocolVersion': '2024-11-05',
            'capabilities': <String, Object?>{},
            'clientInfo': {'name': 'http-test', 'version': '1.0'},
          },
        }),
      );
      final postResp = await postReq.close();
      expect(postResp.statusCode, HttpStatus.accepted);
      await postResp.drain<void>();

      final result = await initResult.future.timeout(
        const Duration(seconds: 5),
      );
      final serverInfo = result['serverInfo'] as Map<String, Object?>;
      expect(serverInfo['name'], 'apollovm-mcp');

      // Clean teardown: stop listening before closing the client.
      await sub.cancel();
    },
  );

  test('unknown path returns 404', () async {
    final port = transport.port!;
    final resp = await (await http.getUrl(
      Uri.parse('http://127.0.0.1:$port/nope'),
    )).close();
    expect(resp.statusCode, HttpStatus.notFound);
    await resp.drain<void>();
  });

  test('POST to an unknown session returns 404', () async {
    final port = transport.port!;
    final req = await http.postUrl(
      Uri.parse('http://127.0.0.1:$port/message?sessionId=does-not-exist'),
    );
    req.headers.contentType = ContentType.json;
    req.write('{"jsonrpc":"2.0","id":1,"method":"ping"}');
    final resp = await req.close();
    expect(resp.statusCode, HttpStatus.notFound);
    await resp.drain<void>();
  });
}
