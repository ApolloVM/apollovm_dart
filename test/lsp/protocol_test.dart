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
}
