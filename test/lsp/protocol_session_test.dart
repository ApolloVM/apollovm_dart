import 'dart:async';
import 'dart:convert';

import 'package:apollovm/apollovm_lsp.dart';
import 'package:test/test.dart';

const _uri = 'file:///workspace/models.dart';
const _content = '''
/// A user of the system.
class User {
  int id;
  String name;

  /// Returns a greeting for this user.
  String greeting() {
    return name;
  }
}

/// Finds a user by identifier.
User findUser(int id) {
  var u = User();
  return u;
}
''';

void main() {
  test(
    'full LSP session: initialize → open → symbols/hover/definition → shutdown',
    () async {
      final input = StreamController<List<int>>();
      final output = _OutputSink();
      final conn = StreamLspEndpoint(input.stream, output);
      LspServer(conn).start();

      final line = LineIndex(_content);
      Map<String, Object?> posOf(String needle) {
        final p = line.positionAt(_content.indexOf(needle));
        return {'line': p.line, 'character': p.character};
      }

      Future<Map<String, Object?>> request(
        int id,
        String method, [
        Map<String, Object?>? params,
      ]) async {
        _send(input, {
          'jsonrpc': '2.0',
          'id': id,
          'method': method,
          'params': params,
        });
        return output.waitFor((m) => m['id'] == id);
      }

      void notify(String method, Map<String, Object?> params) =>
          _send(input, {'jsonrpc': '2.0', 'method': method, 'params': params});

      // initialize
      final init = await request(1, 'initialize', {'capabilities': {}});
      final caps = (init['result'] as Map)['capabilities'] as Map;
      expect(caps['hoverProvider'], isTrue);
      expect(caps['definitionProvider'], isTrue);
      expect(caps['documentSymbolProvider'], isTrue);

      notify('initialized', {});

      // didOpen
      notify('textDocument/didOpen', {
        'textDocument': {
          'uri': _uri,
          'languageId': 'dart',
          'version': 1,
          'text': _content,
        },
      });

      // Diagnostics published (empty — the source is valid).
      final diag = await output.waitFor(
        (m) =>
            m['method'] == 'textDocument/publishDiagnostics' &&
            (m['params'] as Map)['uri'] == _uri,
      );
      expect((diag['params'] as Map)['diagnostics'], isEmpty);

      // documentSymbol
      final symResp = await request(2, 'textDocument/documentSymbol', {
        'textDocument': {'uri': _uri},
      });
      final symbols = (symResp['result'] as List).cast<Map>();
      final names = symbols.map((s) => s['name']).toList();
      expect(names, containsAll(['User', 'findUser']));
      final user = symbols.firstWhere((s) => s['name'] == 'User');
      final userChildren = (user['children'] as List).cast<Map>();
      expect(userChildren.map((c) => c['name']), contains('greeting'));

      // hover over the `findUser` declaration.
      final hoverResp = await request(3, 'textDocument/hover', {
        'textDocument': {'uri': _uri},
        'position': posOf('findUser'),
      });
      final hover = hoverResp['result'] as Map;
      final value = (hover['contents'] as Map)['value'] as String;
      expect(value, contains('User findUser(int id)'));
      expect(value, contains('Finds a user by identifier'));

      // definition of `findUser`.
      final defResp = await request(4, 'textDocument/definition', {
        'textDocument': {'uri': _uri},
        'position': posOf('findUser'),
      });
      final def = defResp['result'] as Map;
      expect(def['uri'], _uri);
      final defStart = (def['range'] as Map)['start'] as Map;
      // Definition points at the declaration line of `findUser`.
      final declPos = line.positionAt(_content.indexOf('findUser'));
      expect(defStart['line'], declPos.line);

      // shutdown / exit
      final sh = await request(5, 'shutdown');
      expect(sh['result'], isNull);
      notify('exit', {});

      await input.close();
    },
  );
}

void _send(StreamController<List<int>> input, Map<String, Object?> msg) {
  final body = utf8.encode(json.encode(msg));
  input.add(utf8.encode('Content-Length: ${body.length}\r\n\r\n'));
  input.add(body);
}

/// Captures framed output and lets the test await specific messages.
class _OutputSink implements StreamSink<List<int>> {
  final _bytes = <int>[];
  final _received = <Map<String, Object?>>[];
  final _done = Completer<void>();
  var _cursor = 0;

  @override
  void add(List<int> data) {
    _bytes.addAll(data);
    _drain();
  }

  void _drain() {
    while (true) {
      final headerEnd = _indexOfHeaderEnd(_bytes, _cursor);
      if (headerEnd < 0) return;
      final header = utf8.decode(_bytes.sublist(_cursor, headerEnd));
      final len = _contentLength(header);
      final bodyStart = headerEnd + 4;
      if (len == null || _bytes.length < bodyStart + len) return;
      final body = utf8.decode(_bytes.sublist(bodyStart, bodyStart + len));
      _received.add(json.decode(body) as Map<String, Object?>);
      _cursor = bodyStart + len;
    }
  }

  Future<Map<String, Object?>> waitFor(
    bool Function(Map<String, Object?>) pred, {
    int maxTicks = 2000,
  }) async {
    var seen = 0;
    for (var tick = 0; tick < maxTicks; tick++) {
      while (seen < _received.length) {
        final m = _received[seen++];
        if (pred(m)) return m;
      }
      await Future<void>.delayed(Duration.zero);
    }
    throw StateError('Expected message not received');
  }

  static int _indexOfHeaderEnd(List<int> b, int from) {
    for (var i = from; i + 3 < b.length; i++) {
      if (b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  static int? _contentLength(String header) {
    for (final l in header.split('\r\n')) {
      final idx = l.indexOf(':');
      if (idx < 0) continue;
      if (l.substring(0, idx).trim().toLowerCase() == 'content-length') {
        return int.tryParse(l.substring(idx + 1).trim());
      }
    }
    return null;
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      add(chunk);
    }
  }

  @override
  Future<void> close() {
    if (!_done.isCompleted) _done.complete();
    return _done.future;
  }

  @override
  Future<void> get done => _done.future;
}
