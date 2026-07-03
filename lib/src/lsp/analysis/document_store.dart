// Tracks the in-memory text of open documents and applies incremental edits
// from `textDocument/didChange`, so re-analysis after each keystroke works on
// the current buffer without a disk round-trip.
import '../protocol/protocol.dart';
import 'line_index.dart';

class OpenDocument {
  final String uri;
  String text;
  int version;

  OpenDocument(this.uri, this.text, this.version);
}

class DocumentStore {
  final Map<String, OpenDocument> _docs = {};

  Iterable<String> get openUris => _docs.keys;

  OpenDocument? get(String uri) => _docs[uri];

  void open(String uri, String text, int version) {
    _docs[uri] = OpenDocument(uri, text, version);
  }

  void close(String uri) => _docs.remove(uri);

  /// Applies `contentChanges` (full or incremental) to the open document and
  /// returns the updated text, or null if the document is not open.
  String? applyChanges(String uri, int? version, List<Object?> contentChanges) {
    final doc = _docs[uri];
    if (doc == null) return null;

    for (final change in contentChanges) {
      if (change is! Map<String, Object?>) continue;
      final rangeJson = change['range'];
      final newText = change['text'] as String? ?? '';
      if (rangeJson is Map<String, Object?>) {
        final range = Range.fromJson(rangeJson);
        final index = LineIndex(doc.text);
        final start = index.offsetAt(range.start);
        final end = index.offsetAt(range.end);
        doc.text = doc.text.replaceRange(start, end, newText);
      } else {
        // Full-document sync.
        doc.text = newText;
      }
    }
    if (version != null) doc.version = version;
    return doc.text;
  }
}
