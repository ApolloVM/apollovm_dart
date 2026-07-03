import 'dart:async';

import 'package:apollovm/apollovm_lsp.dart';
import 'package:test/test.dart';

const _uri = 'file:///ws/user.dart';
const _content = '''
/// A user.
class User {
  int id;
  String greet(String name) {
    return name;
  }
}

/// Builds an id.
int makeId(int seed) {
  return seed;
}
''';

/// A tiny in-process LSP client over [MessageLspEndpoint].
class _Client {
  final outgoing = <Map<String, Object?>>[];
  late final MessageLspEndpoint endpoint = MessageLspEndpoint(outgoing.add);
  var _id = 0;

  _Client() {
    LspServer(endpoint);
  }

  Future<Map<String, Object?>> request(
    String method, [
    Map<String, Object?>? params,
  ]) {
    final id = ++_id;
    endpoint.receive({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });
    return _waitFor((m) => m['id'] == id);
  }

  void notify(String method, Map<String, Object?> params) =>
      endpoint.receive({'jsonrpc': '2.0', 'method': method, 'params': params});

  Future<Map<String, Object?>> _waitFor(
    bool Function(Map<String, Object?>) pred,
  ) async {
    var seen = 0;
    for (var i = 0; i < 3000; i++) {
      while (seen < outgoing.length) {
        final m = outgoing[seen++];
        if (pred(m)) return m;
      }
      await Future<void>.delayed(Duration.zero);
    }
    throw StateError('message not received');
  }

  Future<void> open(String uri, String text) async {
    notify('textDocument/didOpen', {
      'textDocument': {'uri': uri, 'text': text},
    });
    await _waitFor(
      (m) =>
          m['method'] == 'textDocument/publishDiagnostics' &&
          (m['params'] as Map)['uri'] == uri,
    );
  }

  Map<String, Object?> pos(int line, int ch) => {'line': line, 'character': ch};
}

Map<String, Object?> _td(String uri) => {'uri': uri};

void main() {
  test('completion returns ranked symbols and keywords', () async {
    final c = _Client();
    await c.open(_uri, _content);
    final resp = await c.request('textDocument/completion', {
      'textDocument': _td(_uri),
      'position': c.pos(4, 6),
    });
    final result = resp['result'] as Map;
    final items = (result['items'] as List).cast<Map>();
    final labels = items.map((i) => i['label']).toSet();
    expect(labels, containsAll(['User', 'makeId', 'greet']));
    expect(labels, contains('class')); // keyword
    // Keywords sort last.
    final kw = items.firstWhere((i) => i['label'] == 'class');
    expect((kw['sortText'] as String).startsWith('2_'), isTrue);
  });

  test('references finds all same-name occurrences in the file', () async {
    final c = _Client();
    await c.open(_uri, _content);
    final resp = await c.request('textDocument/references', {
      'textDocument': _td(_uri),
      'position': c.pos(3, 24), // the `name` parameter
      'context': {'includeDeclaration': true},
    });
    final locs = (resp['result'] as List).cast<Map>();
    // `name` appears as the parameter and in `return name;`.
    expect(locs.length, 2);
    expect(locs.every((l) => l['uri'] == _uri), isTrue);
  });

  test('rename edits every same-name occurrence', () async {
    final c = _Client();
    await c.open(_uri, _content);
    final resp = await c.request('textDocument/rename', {
      'textDocument': _td(_uri),
      'position': c.pos(3, 24),
      'newName': 'label',
    });
    final changes = (resp['result'] as Map)['changes'] as Map;
    final edits = (changes[_uri] as List).cast<Map>();
    expect(edits.length, 2);
    expect(edits.every((e) => e['newText'] == 'label'), isTrue);
  });

  test('workspace/symbol matches declarations by query', () async {
    final c = _Client();
    await c.open(_uri, _content);
    final resp = await c.request('workspace/symbol', {'query': 'make'});
    final syms = (resp['result'] as List).cast<Map>();
    expect(syms.map((s) => s['name']), contains('makeId'));
  });

  test(
    'hover on a non-symbol identifier falls back to the bare name',
    () async {
      final c = _Client();
      await c.open(_uri, _content);
      final resp = await c.request('textDocument/hover', {
        'textDocument': _td(_uri),
        'position': c.pos(3, 24), // `name` param — not a collected symbol
      });
      final value = ((resp['result'] as Map)['contents'] as Map)['value'];
      expect(value, contains('`name`'));
    },
  );

  test(
    'definition returns null when nothing declares the identifier',
    () async {
      final c = _Client();
      await c.open(_uri, _content);
      final resp = await c.request('textDocument/definition', {
        'textDocument': _td(_uri),
        'position': c.pos(3, 24), // `name` has no declaration site
      });
      expect(resp['result'], isNull);
    },
  );

  test(
    'didChange re-analyzes; a new error is published, then cleared on close',
    () async {
      final c = _Client();
      await c.open(_uri, _content);
      c.notify('textDocument/didChange', {
        'textDocument': {'uri': _uri, 'version': 2},
        'contentChanges': [
          {'text': 'int broken( {\n'},
        ],
      });
      final bad = await c._waitFor(
        (m) =>
            m['method'] == 'textDocument/publishDiagnostics' &&
            (m['params'] as Map)['uri'] == _uri &&
            ((m['params'] as Map)['diagnostics'] as List).isNotEmpty,
      );
      expect(((bad['params'] as Map)['diagnostics'] as List), isNotEmpty);

      c.notify('textDocument/didClose', {'textDocument': _td(_uri)});
      final cleared = await c._waitFor(
        (m) =>
            m['method'] == 'textDocument/publishDiagnostics' &&
            (m['params'] as Map)['uri'] == _uri &&
            ((m['params'] as Map)['diagnostics'] as List).isEmpty,
      );
      expect(((cleared['params'] as Map)['diagnostics'] as List), isEmpty);
    },
  );

  test('an unknown request method yields a methodNotFound error', () async {
    final c = _Client();
    final resp = await c.request('foo/bar');
    final error = resp['error'] as Map;
    expect(error['code'], ResponseError.methodNotFound);
  });
}
