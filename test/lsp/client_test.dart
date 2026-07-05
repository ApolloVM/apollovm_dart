import 'package:apollovm/apollovm_lsp.dart';
import 'package:test/test.dart';

const _uri = 'file:///workspace/Foo.dart';
const _source = '''
class Foo {
  /// Doubles [x] and adds [y].
  static int calc(int x, int y) {
    var doubled = x * 2;
    return doubled + y;
  }

  static int run() {
    return calc(10, 5);
  }
}
''';

/// Locates the LSP position of a substring in [_source].
Position _posOf(String needle, {int occurrence = 1}) {
  final line = LineIndex(_source);
  var index = -1;
  for (var i = 0; i < occurrence; i++) {
    index = _source.indexOf(needle, index + 1);
  }
  final p = line.positionAt(index);
  return Position(p.line, p.character);
}

void main() {
  group('LspClient (in-process)', () {
    late LspClient client;

    setUp(() => client = LspClient.inProcess());
    tearDown(() => client.dispose());

    test('initialize advertises server capabilities', () async {
      final result = await client.initialize();
      expect(result.serverInfo?.name, 'apollovm-lsp');
      expect(result.serverInfo?.version, isNotEmpty);
      expect(result.supports('hoverProvider'), isTrue);
      expect(result.supports('definitionProvider'), isTrue);
      expect(result.supports('renameProvider'), isTrue);
      expect(result.supports('documentHighlightProvider'), isTrue);
      // rename advertises prepareProvider (an object, still truthy).
      expect(
        (result.capabilities['renameProvider'] as Map)['prepareProvider'],
        isTrue,
      );
    });

    test('didOpen publishes diagnostics on the stream', () async {
      await client.initialize();
      client.initialized();

      final first = client.diagnostics.first;
      client.didOpen(_uri, _source);
      final published = await first;

      expect(published.uri, _uri);
      expect(published.diagnostics, isEmpty); // clean source
    });

    test('didChange re-publishes diagnostics for a broken source', () async {
      await client.initialize();
      client.didOpen(_uri, _source);
      await client.diagnostics.first;

      final next = client.diagnostics.firstWhere(
        (d) => d.diagnostics.isNotEmpty,
      );
      client.didChange(
        _uri,
        'class Foo {\n  static int calc( {\n}\n',
        version: 2,
      );
      final broken = await next;

      expect(broken.diagnostics, isNotEmpty);
      expect(broken.diagnostics.first.severity, DiagnosticSeverity.error);
    });

    test('documentSymbol returns the outline', () async {
      await client.initialize();
      client.didOpen(_uri, _source);
      await client.diagnostics.first;

      final symbols = await client.documentSymbol(_uri);
      expect(symbols.map((s) => s.name), contains('Foo'));
      final foo = symbols.firstWhere((s) => s.name == 'Foo');
      expect(foo.kind, SymbolKind.classKind);
      expect(foo.children.map((c) => c.name), containsAll(['calc', 'run']));
    });

    test('hover returns a typed markup for a method', () async {
      await client.initialize();
      client.didOpen(_uri, _source);
      await client.diagnostics.first;

      final hover = await client.hover(_uri, _posOf('calc'));
      expect(hover, isNotNull);
      expect(hover!.contents.value, contains('calc'));
      expect(hover.contents.value, contains('Doubles'));
    });

    test('definition resolves a call to its declaration', () async {
      await client.initialize();
      client.didOpen(_uri, _source);
      await client.diagnostics.first;

      // 2nd `calc` is the call site inside `run`.
      final def = await client.definition(_uri, _posOf('calc', occurrence: 2));
      expect(def, isNotNull);
      // 1st `calc` is the declaration name.
      final declStart = _posOf('calc');
      expect(def!.range.start.line, declStart.line);
      expect(def.range.start.character, declStart.character);
    });

    test('completion proposes symbols and keywords', () async {
      await client.initialize();
      client.didOpen(_uri, _source);
      await client.diagnostics.first;

      final list = await client.completion(_uri, _posOf('doubled'));
      final labels = list.items.map((i) => i.label).toSet();
      expect(labels, contains('calc'));
      expect(labels, contains('return')); // a keyword
    });

    test('references finds every occurrence of a name', () async {
      await client.initialize();
      client.didOpen(_uri, _source);
      await client.diagnostics.first;

      final refs = await client.references(_uri, _posOf('calc'));
      // Declaration + call site.
      expect(refs.length, 2);
      expect(refs.every((l) => l.uri == _uri), isTrue);
    });

    test('rename produces a workspace edit for every occurrence', () async {
      await client.initialize();
      client.didOpen(_uri, _source);
      await client.diagnostics.first;

      final edit = await client.rename(_uri, _posOf('calc'), 'compute');
      expect(edit, isNotNull);
      final edits = edit!.changes[_uri]!;
      expect(edits.length, 2);
      expect(edits.every((e) => e.newText == 'compute'), isTrue);
    });

    test('documentHighlight marks the declaration write, uses read', () async {
      await client.initialize();
      client.didOpen(_uri, _source);
      await client.diagnostics.first;

      final highlights = await client.documentHighlight(_uri, _posOf('calc'));
      expect(highlights.length, 2); // declaration + call site
      final kinds = highlights.map((h) => h.kind).toList();
      expect(kinds, containsAll([DocumentHighlightKind.write]));
      expect(kinds, containsAll([DocumentHighlightKind.read]));

      // The write highlight sits on the declaration name.
      final write = highlights.firstWhere(
        (h) => h.kind == DocumentHighlightKind.write,
      );
      final decl = _posOf('calc');
      expect(write.range.start.line, decl.line);
      expect(write.range.start.character, decl.character);
    });

    test('documentHighlight is empty off any identifier', () async {
      await client.initialize();
      client.didOpen(_uri, _source);
      await client.diagnostics.first;

      // The blank line between the two methods is not an identifier.
      final highlights = await client.documentHighlight(_uri, Position(6, 0));
      expect(highlights, isEmpty);
    });

    test('prepareRename returns the target range and placeholder', () async {
      await client.initialize();
      client.didOpen(_uri, _source);
      await client.diagnostics.first;

      final prep = await client.prepareRename(
        _uri,
        _posOf('calc', occurrence: 2),
      );
      expect(prep, isNotNull);
      expect(prep!.placeholder, 'calc');
      // Range covers the call-site occurrence.
      final call = _posOf('calc', occurrence: 2);
      expect(prep.range.start.line, call.line);
      expect(prep.range.start.character, call.character);
      expect(prep.range.end.character, call.character + 'calc'.length);
    });

    test('prepareRename is null when not on an identifier', () async {
      await client.initialize();
      client.didOpen(_uri, _source);
      await client.diagnostics.first;

      final prep = await client.prepareRename(_uri, Position(6, 0));
      expect(prep, isNull);
    });

    test('workspaceSymbol matches declarations by query', () async {
      await client.initialize();
      client.didOpen(_uri, _source);
      await client.diagnostics.first;

      final syms = await client.workspaceSymbol('calc');
      expect(syms.map((s) => s.name), contains('calc'));
    });

    test('didClose clears the document diagnostics', () async {
      await client.initialize();
      client.didOpen(_uri, _source);
      await client.diagnostics.first;

      final cleared = client.diagnostics.first;
      client.didClose(_uri);
      final published = await cleared;
      expect(published.uri, _uri);
      expect(published.diagnostics, isEmpty);
    });

    test('onNotification receives raw server notifications', () async {
      final methods = <String>[];
      client.onNotification = (method, _) => methods.add(method);

      await client.initialize();
      client.didOpen(_uri, _source);
      await client.diagnostics.first;

      expect(methods, contains('textDocument/publishDiagnostics'));
    });

    test('dispose fails in-flight requests and rejects further use', () async {
      await client.initialize();
      final pending = client.hover(_uri, _posOf('calc'));
      // Attach the expectation before disposing so the rejection is handled.
      final rejected = expectLater(pending, throwsA(isA<StateError>()));
      await client.dispose();
      await rejected;

      expect(() => client.sendRequest('initialize'), throwsStateError);
    });

    test('an unknown request completes with a ResponseError', () async {
      await client.initialize();
      expect(
        () => client.sendRequest('textDocument/nonsense'),
        throwsA(
          isA<ResponseError>().having(
            (e) => e.code,
            'code',
            ResponseError.methodNotFound,
          ),
        ),
      );
    });

    test('shutdown then exit completes the session', () async {
      await client.initialize();
      await client.shutdown();
      client.exit();
      // No throw; the server accepted the lifecycle messages.
    });
  });

  test(
    'LspClient wraps an external endpoint pair (transport-agnostic)',
    () async {
      // Simulate an out-of-process link with two message endpoints.
      late final MessageLspEndpoint serverEndpoint;
      final clientEndpoint = MessageLspEndpoint(
        (m) => serverEndpoint.receive(m),
      );
      serverEndpoint = MessageLspEndpoint((m) => clientEndpoint.receive(m));
      LspServer(serverEndpoint).start();

      final client = LspClient(clientEndpoint)..start();
      addTearDown(client.dispose);

      final result = await client.initialize();
      expect(result.serverInfo?.name, 'apollovm-lsp');
    },
  );
}
