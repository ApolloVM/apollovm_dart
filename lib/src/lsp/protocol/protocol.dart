// LSP 3.17 protocol data types used by the ApolloVM language server.
//
// Only the subset of the specification this server exercises is modelled here,
// hand-written to keep the package dependency-light. All `Position`/`Range`
// character offsets are UTF-16 code units, per the LSP specification.
//
// This layer is pure data: it contains no analysis or transport logic.
library;

/// A zero-based `(line, character)` position. `character` counts UTF-16 code
/// units within the line.
class Position {
  final int line;
  final int character;

  const Position(this.line, this.character);

  factory Position.fromJson(Map<String, Object?> json) =>
      Position((json['line'] as num).toInt(), (json['character'] as num).toInt());

  Map<String, Object?> toJson() => {'line': line, 'character': character};

  @override
  String toString() => '$line:$character';
}

/// A half-open `[start, end)` text range.
class Range {
  final Position start;
  final Position end;

  const Range(this.start, this.end);

  factory Range.fromJson(Map<String, Object?> json) => Range(
        Position.fromJson(json['start'] as Map<String, Object?>),
        Position.fromJson(json['end'] as Map<String, Object?>),
      );

  Map<String, Object?> toJson() => {'start': start.toJson(), 'end': end.toJson()};

  @override
  String toString() => '[$start..$end]';
}

/// A location inside a document (`uri` + `range`).
class Location {
  final String uri;
  final Range range;

  const Location(this.uri, this.range);

  Map<String, Object?> toJson() => {'uri': uri, 'range': range.toJson()};
}

/// LSP `DiagnosticSeverity`.
class DiagnosticSeverity {
  static const int error = 1;
  static const int warning = 2;
  static const int information = 3;
  static const int hint = 4;
}

/// A single diagnostic (error/warning/…) at a [range].
class Diagnostic {
  final Range range;
  final int severity;
  final String message;
  final String source;
  final String? code;

  const Diagnostic({
    required this.range,
    required this.message,
    this.severity = DiagnosticSeverity.error,
    this.source = 'apollovm',
    this.code,
  });

  Map<String, Object?> toJson() => {
        'range': range.toJson(),
        'severity': severity,
        'message': message,
        'source': source,
        if (code != null) 'code': code,
      };
}

/// LSP `MarkupContent` (`plaintext` or `markdown`).
class MarkupContent {
  final String kind;
  final String value;

  const MarkupContent.markdown(this.value) : kind = 'markdown';
  const MarkupContent.plaintext(this.value) : kind = 'plaintext';

  Map<String, Object?> toJson() => {'kind': kind, 'value': value};
}

/// LSP `Hover` response.
class Hover {
  final MarkupContent contents;
  final Range? range;

  const Hover(this.contents, {this.range});

  Map<String, Object?> toJson() => {
        'contents': contents.toJson(),
        if (range != null) 'range': range!.toJson(),
      };
}

/// LSP `SymbolKind` (subset used by this server).
class SymbolKind {
  static const int file = 1;
  static const int namespace = 3;
  static const int classKind = 5;
  static const int method = 6;
  static const int property = 7;
  static const int field = 8;
  static const int constructor = 9;
  static const int enumKind = 10;
  static const int function = 12;
  static const int variable = 13;
  static const int enumMember = 22;
}

/// LSP hierarchical `DocumentSymbol`.
class DocumentSymbol {
  final String name;
  final String? detail;
  final int kind;
  final Range range;
  final Range selectionRange;
  final List<DocumentSymbol> children;

  const DocumentSymbol({
    required this.name,
    required this.kind,
    required this.range,
    required this.selectionRange,
    this.detail,
    this.children = const [],
  });

  Map<String, Object?> toJson() => {
        'name': name,
        if (detail != null) 'detail': detail,
        'kind': kind,
        'range': range.toJson(),
        'selectionRange': selectionRange.toJson(),
        if (children.isNotEmpty)
          'children': children.map((c) => c.toJson()).toList(),
      };
}

/// LSP `CompletionItemKind` (subset).
class CompletionItemKind {
  static const int text = 1;
  static const int method = 2;
  static const int function = 3;
  static const int constructor = 4;
  static const int field = 5;
  static const int variable = 6;
  static const int classKind = 7;
  static const int property = 10;
  static const int keyword = 14;
  static const int enumKind = 13;
  static const int enumMember = 20;
}

/// LSP `CompletionItem`. `sortText` drives ranking (lower sorts first).
class CompletionItem {
  final String label;
  final int kind;
  final String? detail;
  final String? sortText;
  final MarkupContent? documentation;

  const CompletionItem({
    required this.label,
    required this.kind,
    this.detail,
    this.sortText,
    this.documentation,
  });

  Map<String, Object?> toJson() => {
        'label': label,
        'kind': kind,
        if (detail != null) 'detail': detail,
        if (sortText != null) 'sortText': sortText,
        if (documentation != null) 'documentation': documentation!.toJson(),
      };
}

/// LSP `TextEdit`.
class TextEdit {
  final Range range;
  final String newText;

  const TextEdit(this.range, this.newText);

  Map<String, Object?> toJson() =>
      {'range': range.toJson(), 'newText': newText};
}

/// LSP `WorkspaceEdit` (document-scoped `changes` map).
class WorkspaceEdit {
  final Map<String, List<TextEdit>> changes;

  const WorkspaceEdit(this.changes);

  Map<String, Object?> toJson() => {
        'changes': changes.map(
          (uri, edits) => MapEntry(uri, edits.map((e) => e.toJson()).toList()),
        ),
      };
}
