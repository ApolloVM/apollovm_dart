import 'package:apollovm/apollovm_lsp.dart';
import 'package:test/test.dart';

const _uri = 'file:///ws/Foo.dart';
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
  group('LspService', () {
    late LspService lsp;

    setUp(() => lsp = LspService());
    tearDown(() => lsp.dispose());

    test('is ready with server capabilities (no handshake by hand)', () async {
      final info = await lsp.ready;
      expect(info.serverInfo?.name, 'apollovm-lsp');
      expect(info.supports('hoverProvider'), isTrue);
      // The underlying client is reachable as an escape hatch.
      expect(lsp.client, isA<LspClient>());
    });

    test('analyze() returns diagnostics for a buffer in one call', () async {
      final clean = await lsp.analyze(_uri, _source);
      expect(clean, isEmpty);
      expect(lsp.isOpen(_uri), isTrue);

      final broken = await lsp.analyze(_uri, 'class Foo {\n  int calc( {\n}\n');
      expect(broken, isNotEmpty);
      expect(broken.first.severity, DiagnosticSeverity.error);
    });

    test('open() accepts an explicit languageId', () async {
      final first = lsp.diagnostics.first;
      lsp.open(_uri, _source, languageId: 'dart');
      expect((await first).diagnostics, isEmpty);
    });

    test('diagnostics are also pushed on the stream', () async {
      final first = lsp.diagnostics.first;
      lsp.open(_uri, _source);
      final published = await first;
      expect(published.uri, _uri);
      expect(published.diagnostics, isEmpty);
    });

    test('hover resolves against the current buffer', () async {
      lsp.open(_uri, _source);
      final hover = await lsp.hover(_uri, _posOf('calc'));
      expect(hover, isNotNull);
      expect(hover!.contents.value, contains('calc'));
      expect(hover.contents.value, contains('Doubles'));
    });

    test('definition resolves a call to its declaration', () async {
      lsp.open(_uri, _source);
      final def = await lsp.definition(_uri, _posOf('calc', occurrence: 2));
      expect(def, isNotNull);
      final decl = _posOf('calc');
      expect(def!.range.start.line, decl.line);
      expect(def.range.start.character, decl.character);
    });

    test('documentSymbols returns the outline', () async {
      lsp.open(_uri, _source);
      final symbols = await lsp.documentSymbols(_uri);
      final foo = symbols.firstWhere((s) => s.name == 'Foo');
      expect(foo.kind, SymbolKind.classKind);
      expect(foo.children.map((c) => c.name), containsAll(['calc', 'run']));
    });

    test('completion proposes symbols and keywords', () async {
      lsp.open(_uri, _source);
      final list = await lsp.completion(_uri, _posOf('doubled'));
      final labels = list.items.map((i) => i.label).toSet();
      expect(labels, contains('calc'));
      expect(labels, contains('return'));
    });

    test('references, documentHighlight, prepareRename and rename', () async {
      lsp.open(_uri, _source);

      final refs = await lsp.references(_uri, _posOf('calc'));
      expect(refs.length, 2);

      final highlights = await lsp.documentHighlight(_uri, _posOf('calc'));
      expect(
        highlights.map((h) => h.kind),
        contains(DocumentHighlightKind.write),
      );

      final prep = await lsp.prepareRename(_uri, _posOf('calc'));
      expect(prep?.placeholder, 'calc');

      final edit = await lsp.rename(_uri, _posOf('calc'), 'compute');
      expect(edit!.changes[_uri], hasLength(2));
    });

    test('workspaceSymbols matches across open documents', () async {
      lsp.open(_uri, _source);
      await lsp.diagnostics.first; // ensure the doc is analyzed/cached
      final syms = await lsp.workspaceSymbols('calc');
      expect(syms.map((s) => s.name), contains('calc'));
    });

    test('change() updates what queries see', () async {
      lsp.open(_uri, _source);
      await lsp.hover(_uri, _posOf('calc'));

      lsp.change(_uri, 'class Bar {\n  static int go() { return 1; }\n}\n');
      final symbols = await lsp.documentSymbols(_uri);
      expect(symbols.map((s) => s.name), contains('Bar'));
      expect(symbols.map((s) => s.name), isNot(contains('Foo')));
    });

    test('close() clears diagnostics for the document', () async {
      await lsp.analyze(_uri, _source);
      final cleared = lsp.diagnostics.first;
      lsp.close(_uri);
      final published = await cleared;
      expect(published.uri, _uri);
      expect(published.diagnostics, isEmpty);
      expect(lsp.isOpen(_uri), isFalse);
    });
  });

  test('LspService.wrap does not dispose a caller-owned client', () async {
    final client = LspClient.inProcess();
    final lsp = LspService.wrap(client);

    final diags = await lsp.analyze(_uri, _source);
    expect(diags, isEmpty);

    await lsp.dispose(); // must NOT dispose the wrapped client
    // The client is still usable.
    final hover = await client.hover(_uri, _posOf('calc'));
    expect(hover, isNotNull);

    await client.dispose();
  });
}
