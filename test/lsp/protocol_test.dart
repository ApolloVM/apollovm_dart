import 'package:apollovm/apollovm_lsp.dart';
import 'package:test/test.dart';

void main() {
  group('protocol JSON', () {
    test('Position round-trips', () {
      final p = Position.fromJson({'line': 3, 'character': 7});
      expect(p.line, 3);
      expect(p.character, 7);
      expect(p.toJson(), {'line': 3, 'character': 7});
      expect(p.toString(), '3:7');
    });

    test('Range round-trips', () {
      final r = Range.fromJson({
        'start': {'line': 1, 'character': 2},
        'end': {'line': 1, 'character': 5},
      });
      expect(r.start.character, 2);
      expect(r.end.character, 5);
      expect(r.toJson(), {
        'start': {'line': 1, 'character': 2},
        'end': {'line': 1, 'character': 5},
      });
      expect(r.toString(), '[1:2..1:5]');
    });

    test('Location.toJson', () {
      final loc = Location(
        'file:///a.dart',
        const Range(Position(0, 0), Position(0, 4)),
      );
      expect(loc.toJson()['uri'], 'file:///a.dart');
      expect(loc.toJson()['range'], isA<Map>());
    });

    test('Diagnostic.toJson includes severity/source/code', () {
      final d = Diagnostic(
        range: const Range(Position(0, 0), Position(0, 1)),
        message: 'boom',
        severity: DiagnosticSeverity.warning,
        code: 'x-code',
      );
      final j = d.toJson();
      expect(j['message'], 'boom');
      expect(j['severity'], DiagnosticSeverity.warning);
      expect(j['source'], 'apollovm');
      expect(j['code'], 'x-code');
    });

    test('MarkupContent markdown and plaintext', () {
      expect(const MarkupContent.markdown('**x**').toJson(), {
        'kind': 'markdown',
        'value': '**x**',
      });
      expect(const MarkupContent.plaintext('x').toJson(), {
        'kind': 'plaintext',
        'value': 'x',
      });
    });

    test('Hover with and without range', () {
      const contents = MarkupContent.markdown('doc');
      expect(const Hover(contents).toJson().containsKey('range'), isFalse);
      final withRange = const Hover(
        contents,
        range: Range(Position(0, 0), Position(0, 2)),
      );
      expect(withRange.toJson()['range'], isA<Map>());
    });

    test('DocumentSymbol nests children and detail', () {
      const child = DocumentSymbol(
        name: 'm',
        kind: SymbolKind.method,
        range: Range(Position(1, 2), Position(1, 3)),
        selectionRange: Range(Position(1, 2), Position(1, 3)),
      );
      const parent = DocumentSymbol(
        name: 'C',
        detail: 'class C',
        kind: SymbolKind.classKind,
        range: Range(Position(0, 0), Position(2, 0)),
        selectionRange: Range(Position(0, 6), Position(0, 7)),
        children: [child],
      );
      final j = parent.toJson();
      expect(j['name'], 'C');
      expect(j['detail'], 'class C');
      expect((j['children'] as List).single, isA<Map>());
    });

    test('CompletionItem.toJson with all fields', () {
      final item = CompletionItem(
        label: 'foo',
        kind: CompletionItemKind.function,
        detail: 'int foo()',
        sortText: '0_foo',
        documentation: const MarkupContent.markdown('docs'),
      );
      final j = item.toJson();
      expect(j['label'], 'foo');
      expect(j['kind'], CompletionItemKind.function);
      expect(j['detail'], 'int foo()');
      expect(j['sortText'], '0_foo');
      expect(j['documentation'], isA<Map>());
    });

    test('TextEdit and WorkspaceEdit', () {
      final edit = TextEdit(const Range(Position(0, 0), Position(0, 3)), 'new');
      expect(edit.toJson()['newText'], 'new');
      final ws = WorkspaceEdit({
        'file:///a.dart': [edit],
      });
      final changes = ws.toJson()['changes'] as Map;
      expect((changes['file:///a.dart'] as List).single['newText'], 'new');
    });
  });

  group('protocol fromJson', () {
    test('Location round-trips', () {
      final loc = Location(
        'file:///a.dart',
        const Range(Position(0, 0), Position(0, 3)),
      );
      final back = Location.fromJson(loc.toJson());
      expect(back.uri, 'file:///a.dart');
      expect(back.range.end.character, 3);
    });

    test('Diagnostic applies defaults and stringifies a numeric code', () {
      final back = Diagnostic.fromJson({
        'range': const Range(Position(0, 0), Position(0, 1)).toJson(),
      });
      expect(back.message, '');
      expect(back.severity, DiagnosticSeverity.error);
      expect(back.source, 'apollovm');
      expect(back.code, isNull);
      expect(Diagnostic.fromJson({...back.toJson(), 'code': 42}).code, '42');
    });

    test('MarkupContent.from parses objects, strings and null', () {
      expect(
        MarkupContent.from({'kind': 'markdown', 'value': '# hi'}).kind,
        'markdown',
      );
      expect(
        MarkupContent.from({'kind': 'plaintext', 'value': 'hi'}).kind,
        'plaintext',
      );
      final bare = MarkupContent.from('text');
      expect(bare.kind, 'plaintext');
      expect(bare.value, 'text');
      expect(MarkupContent.from(null).value, '');
    });

    test('Hover parses a range, no range, and string contents', () {
      final withRange = Hover.fromJson(
        Hover(
          const MarkupContent.markdown('**x**'),
          range: const Range(Position(0, 0), Position(0, 1)),
        ).toJson(),
      );
      expect(withRange.contents.value, '**x**');
      expect(withRange.range!.end.character, 1);

      final noRange = Hover.fromJson(
        const Hover(MarkupContent.plaintext('y')).toJson(),
      );
      expect(noRange.range, isNull);

      final stringContents = Hover.fromJson({'contents': 'plain'});
      expect(stringContents.contents.value, 'plain');
    });

    test('DocumentSymbol round-trips with nested children', () {
      const sym = DocumentSymbol(
        name: 'Foo',
        detail: 'class Foo',
        kind: SymbolKind.classKind,
        range: Range(Position(0, 0), Position(5, 1)),
        selectionRange: Range(Position(0, 6), Position(0, 9)),
        children: [
          DocumentSymbol(
            name: 'calc',
            kind: SymbolKind.method,
            range: Range(Position(1, 2), Position(3, 3)),
            selectionRange: Range(Position(1, 6), Position(1, 10)),
          ),
        ],
      );
      final back = DocumentSymbol.fromJson(sym.toJson());
      expect(back.name, 'Foo');
      expect(back.detail, 'class Foo');
      expect(back.children.single.name, 'calc');
      expect(back.children.single.children, isEmpty);
    });

    test('CompletionItem parses markup/string/absent documentation', () {
      final markup = CompletionItem.fromJson(
        const CompletionItem(
          label: 'calc',
          kind: CompletionItemKind.method,
          documentation: MarkupContent.markdown('does math'),
        ).toJson(),
      );
      expect(markup.documentation?.value, 'does math');

      final str = CompletionItem.fromJson({
        'label': 'x',
        'kind': CompletionItemKind.variable,
        'documentation': 'a var',
      });
      expect(str.documentation?.value, 'a var');

      final bare = CompletionItem.fromJson({'label': 'x'});
      expect(bare.kind, CompletionItemKind.text);
      expect(bare.documentation, isNull);
    });

    test('CompletionList round-trips and tolerates missing fields', () {
      final back = CompletionList.fromJson(
        const CompletionList(
          isIncomplete: true,
          items: [CompletionItem(label: 'a', kind: CompletionItemKind.keyword)],
        ).toJson(),
      );
      expect(back.isIncomplete, isTrue);
      expect(back.items.single.label, 'a');

      final empty = CompletionList.fromJson(const {});
      expect(empty.isIncomplete, isFalse);
      expect(empty.items, isEmpty);
    });

    test('WorkspaceEdit round-trips and tolerates absent changes', () {
      final back = WorkspaceEdit.fromJson(
        WorkspaceEdit({
          'file:///a.dart': [
            TextEdit(const Range(Position(0, 0), Position(0, 4)), 'newName'),
          ],
        }).toJson(),
      );
      final edits = back.changes['file:///a.dart']!;
      expect(edits.single.newText, 'newName');
      expect(edits.single.range.end.character, 4);
      expect(WorkspaceEdit.fromJson(const {}).changes, isEmpty);
    });

    test('InitializeResult.supports handles bool/object/absent', () {
      final result = InitializeResult.fromJson({
        'capabilities': {
          'hoverProvider': true,
          'renameProvider': {'prepareProvider': true},
          'documentHighlightProvider': false,
        },
        'serverInfo': {'name': 'apollovm-lsp', 'version': '9.9.9'},
      });
      expect(result.serverInfo?.name, 'apollovm-lsp');
      expect(result.serverInfo?.version, '9.9.9');
      expect(result.supports('hoverProvider'), isTrue);
      expect(result.supports('renameProvider'), isTrue); // object → truthy
      expect(result.supports('documentHighlightProvider'), isFalse);
      expect(result.supports('definitionProvider'), isFalse); // absent

      final empty = InitializeResult.fromJson(const {});
      expect(empty.serverInfo, isNull);
      expect(empty.capabilities, isEmpty);
      expect(empty.supports('anything'), isFalse);
    });

    test('PublishDiagnosticsParams round-trips with and without version', () {
      final back = PublishDiagnosticsParams.fromJson(
        PublishDiagnosticsParams(
          uri: 'file:///a.dart',
          version: 3,
          diagnostics: [
            Diagnostic(
              range: const Range(Position(0, 0), Position(0, 1)),
              message: 'oops',
            ),
          ],
        ).toJson(),
      );
      expect(back.uri, 'file:///a.dart');
      expect(back.version, 3);
      expect(back.diagnostics.single.message, 'oops');

      final noVer = PublishDiagnosticsParams.fromJson({
        'uri': 'file:///b.dart',
        'diagnostics': const [],
      });
      expect(noVer.version, isNull);
      expect(noVer.toJson().containsKey('version'), isFalse);
    });

    test('WorkspaceSymbol round-trips with and without container', () {
      final sym = WorkspaceSymbol(
        name: 'calc',
        kind: SymbolKind.method,
        location: Location(
          'file:///a.dart',
          const Range(Position(1, 2), Position(1, 6)),
        ),
        containerName: 'Foo',
      );
      final back = WorkspaceSymbol.fromJson(sym.toJson());
      expect(back.name, 'calc');
      expect(back.location.uri, 'file:///a.dart');
      expect(back.containerName, 'Foo');

      final top = WorkspaceSymbol.fromJson({
        'name': 'main',
        'kind': SymbolKind.function,
        'location': sym.location.toJson(),
      });
      expect(top.containerName, isNull);
      expect(top.toJson().containsKey('containerName'), isFalse);
    });

    test('DocumentHighlight round-trips with/without a kind', () {
      final withKind = DocumentHighlight.fromJson(
        DocumentHighlight(
          const Range(Position(0, 0), Position(0, 4)),
          kind: DocumentHighlightKind.write,
        ).toJson(),
      );
      expect(withKind.kind, DocumentHighlightKind.write);
      expect(withKind.range.end.character, 4);

      final noKind = DocumentHighlight(
        const Range(Position(0, 0), Position(0, 1)),
      );
      expect(noKind.toJson().containsKey('kind'), isFalse);
      expect(DocumentHighlight.fromJson(noKind.toJson()).kind, isNull);

      expect(DocumentHighlightKind.text, 1);
      expect(DocumentHighlightKind.read, 2);
      expect(DocumentHighlightKind.write, 3);
    });

    test('PrepareRenameResult round-trips and defaults placeholder', () {
      final prep = PrepareRenameResult(
        const Range(Position(2, 13), Position(2, 17)),
        'calc',
      );
      final back = PrepareRenameResult.fromJson(prep.toJson());
      expect(back.placeholder, 'calc');
      expect(back.range.start.character, 13);
      expect(
        PrepareRenameResult.fromJson({
          'range': prep.range.toJson(),
        }).placeholder,
        '',
      );
    });

    test('ResponseError exposes code, message and JSON', () {
      const err = ResponseError(ResponseError.invalidParams, 'bad');
      expect(err.code, ResponseError.invalidParams);
      expect(err.toJson(), {
        'code': ResponseError.invalidParams,
        'message': 'bad',
      });
      expect(err.toString(), contains('bad'));
    });
  });
}
