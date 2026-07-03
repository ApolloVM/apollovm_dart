import 'package:apollovm/apollovm_lsp.dart';
import 'package:test/test.dart';

void main() {
  group('DocumentStore', () {
    late DocumentStore store;
    setUp(() => store = DocumentStore());

    test('open/get/close tracks documents', () {
      store.open('file:///a.dart', 'hello', 1);
      expect(store.get('file:///a.dart')?.text, 'hello');
      expect(store.get('file:///a.dart')?.version, 1);
      expect(store.openUris, contains('file:///a.dart'));
      store.close('file:///a.dart');
      expect(store.get('file:///a.dart'), isNull);
    });

    test('applyChanges returns null for an unopened document', () {
      expect(store.applyChanges('file:///none.dart', 2, const []), isNull);
    });

    test('incremental range edit replaces text', () {
      store.open('u', 'abcdef', 1);
      final updated = store.applyChanges('u', 2, [
        {
          'range': {
            'start': {'line': 0, 'character': 1},
            'end': {'line': 0, 'character': 3},
          },
          'text': 'XY',
        },
      ]);
      expect(updated, 'aXYdef');
      expect(store.get('u')?.version, 2);
    });

    test('incremental insert (zero-width range) and delete', () {
      store.open('u', 'abc', 1);
      store.applyChanges('u', 2, [
        {
          'range': {
            'start': {'line': 0, 'character': 3},
            'end': {'line': 0, 'character': 3},
          },
          'text': 'X',
        },
      ]);
      expect(store.get('u')?.text, 'abcX');
      store.applyChanges('u', 3, [
        {
          'range': {
            'start': {'line': 0, 'character': 0},
            'end': {'line': 0, 'character': 1},
          },
          'text': '',
        },
      ]);
      expect(store.get('u')?.text, 'bcX');
    });

    test('edits a specific line in a multi-line document', () {
      store.open('u', 'foo\nbar\nbaz', 1);
      final updated = store.applyChanges('u', 2, [
        {
          'range': {
            'start': {'line': 1, 'character': 0},
            'end': {'line': 1, 'character': 3},
          },
          'text': 'BAR',
        },
      ]);
      expect(updated, 'foo\nBAR\nbaz');
    });

    test('full-document sync when a change has no range', () {
      store.open('u', 'old', 1);
      final updated = store.applyChanges('u', 5, [
        {'text': 'brand new'},
      ]);
      expect(updated, 'brand new');
      expect(store.get('u')?.version, 5);
    });

    test('applies multiple sequential changes in order', () {
      store.open('u', 'abc', 1);
      store.applyChanges('u', 2, [
        {
          'range': {
            'start': {'line': 0, 'character': 3},
            'end': {'line': 0, 'character': 3},
          },
          'text': 'd',
        },
        {
          'range': {
            'start': {'line': 0, 'character': 0},
            'end': {'line': 0, 'character': 0},
          },
          'text': 'Z',
        },
      ]);
      expect(store.get('u')?.text, 'Zabcd');
    });
  });
}
