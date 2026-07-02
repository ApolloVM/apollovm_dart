// Verifies the web/embedded usage path: a host (web IDE, AI agent) drives the
// server through decoded JSON-RPC *messages* via [MessageLspEndpoint] — no byte
// framing and no `dart:io`, exactly what a browser or in-process bridge needs.
import 'dart:async';

import 'package:apollovm/apollovm_lsp.dart';
import 'package:test/test.dart';

void main() {
  test('drives the server via decoded messages (no byte framing)', () async {
    final outgoing = <Map<String, Object?>>[];
    final endpoint = MessageLspEndpoint(outgoing.add);
    LspServer(endpoint); // no start(): message endpoints are push-based.

    Future<Map<String, Object?>> waitFor(
        bool Function(Map<String, Object?>) pred) async {
      var seen = 0;
      for (var i = 0; i < 2000; i++) {
        while (seen < outgoing.length) {
          final m = outgoing[seen++];
          if (pred(m)) return m;
        }
        await Future<void>.delayed(Duration.zero);
      }
      throw StateError('Expected message not received');
    }

    // initialize
    endpoint.receive({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': {'capabilities': {}},
    });
    final init = await waitFor((m) => m['id'] == 1);
    final caps = (init['result'] as Map)['capabilities'] as Map;
    expect(caps['hoverProvider'], isTrue);
    expect((init['result'] as Map)['serverInfo'], isNotNull);

    // didOpen → diagnostics published
    const uri = 'file:///web/answer.dart';
    endpoint.receive({
      'jsonrpc': '2.0',
      'method': 'textDocument/didOpen',
      'params': {
        'textDocument': {
          'uri': uri,
          'text': '/// The answer.\nint answer() {\n  return 42;\n}\n',
        }
      },
    });
    final diag = await waitFor((m) =>
        m['method'] == 'textDocument/publishDiagnostics' &&
        (m['params'] as Map)['uri'] == uri);
    expect((diag['params'] as Map)['diagnostics'], isEmpty);

    // documentSymbol
    endpoint.receive({
      'jsonrpc': '2.0',
      'id': 2,
      'method': 'textDocument/documentSymbol',
      'params': {
        'textDocument': {'uri': uri}
      },
    });
    final sym = await waitFor((m) => m['id'] == 2);
    final names =
        (sym['result'] as List).cast<Map>().map((s) => s['name']).toList();
    expect(names, contains('answer'));
  });
}
