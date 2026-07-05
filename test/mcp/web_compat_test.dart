// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

// Cross-platform (VM + browser) test: the MCP tools and the LSP run entirely
// in-process on the web. Deliberately NOT `@TestOn('vm')` — it runs under
// `dart test --platform chrome` in CI, so a `dart:io` / `dart:isolate` leak
// into the web-safe surface (`apollovm_mcp.dart` / `apollovm_lsp.dart`) fails
// compilation here. The native transports/CLI live in `apollovm_mcp_io.dart`.
@Tags(['mcp'])
library;

import 'package:apollovm/apollovm_lsp.dart';
import 'package:apollovm/apollovm_mcp.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

const _src =
    'class Greeter {\n'
    '  final String name;\n'
    '  Greeter(this.name);\n'
    '  String greet() => \'Hello, \$name!\';\n'
    '}\n';

void main() {
  group('web-safe MCP surface', () {
    const limits = McpLimits();

    test('core tool (apollovm.parse) runs in-process', () async {
      final result = await computeTool('apollovm.parse', {
        'language': 'dart',
        'source': _src,
      }, limits);
      expect(result['isError'], isFalse);
    });

    test('the isolate-flagged tool degrades to in-process execution', () async {
      // `apollovm.execute` is in `limits.isolateTools`; on the web there is no
      // `dart:isolate`, so the generic executor runs it in-process.
      final result = await computeToolIsolated('apollovm.execute', {
        'language': 'dart',
        'source': 'int main() { return 21 + 21; }',
      }, limits);
      expect(result['isError'], isFalse);
      expect(result['result'], 42);
    });

    test(
      'LSP tool (apollovm.lsp.diagnostics) runs the in-process server',
      () async {
        expect(isLspTool('apollovm.lsp.diagnostics'), isTrue);
        final result = await computeLspTool('apollovm.lsp.diagnostics', {
          'language': 'dart',
          'source': _src,
        }, limits);
        expect(result['isError'], isFalse);
        expect(result['diagnostics'], isEmpty);
      },
    );

    test('all tool schemas build', () {
      expect(allToolNames, isNotEmpty);
      expect(lspToolNames, isNotEmpty);
      expect(buildLspTools().map((t) => t.name), containsAll(lspToolNames));
    });
  });

  test('LspClient.inProcess drives the server in one isolate', () async {
    final client = LspClient.inProcess();
    await client.initialize();
    client.initialized();
    client.didOpen('file:///main.dart', _src);

    final symbols = await client.documentSymbol('file:///main.dart');
    expect(symbols.map((s) => s.name), contains('Greeter'));

    await client.dispose();
  });

  test('ApolloMcpServer binds to a StreamChannel<String>', () {
    final controller = StreamChannelController<String>();
    final server = ApolloMcpServer(controller.local);
    expect(server, isNotNull);
  });
}
