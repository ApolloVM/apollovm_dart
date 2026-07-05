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

  factory Position.fromJson(Map<String, Object?> json) => Position(
    (json['line'] as num).toInt(),
    (json['character'] as num).toInt(),
  );

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

  Map<String, Object?> toJson() => {
    'start': start.toJson(),
    'end': end.toJson(),
  };

  @override
  String toString() => '[$start..$end]';
}

/// A location inside a document (`uri` + `range`).
class Location {
  final String uri;
  final Range range;

  const Location(this.uri, this.range);

  factory Location.fromJson(Map<String, Object?> json) => Location(
    json['uri'] as String,
    Range.fromJson(json['range'] as Map<String, Object?>),
  );

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

  factory Diagnostic.fromJson(Map<String, Object?> json) => Diagnostic(
    range: Range.fromJson(json['range'] as Map<String, Object?>),
    message: (json['message'] ?? '').toString(),
    severity: (json['severity'] as num?)?.toInt() ?? DiagnosticSeverity.error,
    source: json['source'] as String? ?? 'apollovm',
    code: json['code']?.toString(),
  );

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

  /// Parses a `MarkupContent` object, or a bare string (`MarkedString`), into a
  /// [MarkupContent].
  factory MarkupContent.from(Object? contents) {
    if (contents is Map) {
      final value = (contents['value'] ?? '').toString();
      return contents['kind'] == 'markdown'
          ? MarkupContent.markdown(value)
          : MarkupContent.plaintext(value);
    }
    return MarkupContent.plaintext((contents ?? '').toString());
  }

  Map<String, Object?> toJson() => {'kind': kind, 'value': value};
}

/// LSP `Hover` response.
class Hover {
  final MarkupContent contents;
  final Range? range;

  const Hover(this.contents, {this.range});

  factory Hover.fromJson(Map<String, Object?> json) => Hover(
    MarkupContent.from(json['contents']),
    range: json['range'] is Map
        ? Range.fromJson(json['range'] as Map<String, Object?>)
        : null,
  );

  Map<String, Object?> toJson() => {
    'contents': contents.toJson(),
    if (range != null) 'range': range!.toJson(),
  };
}

/// LSP `DocumentHighlightKind`.
class DocumentHighlightKind {
  static const int text = 1;
  static const int read = 2;
  static const int write = 3;
}

/// A range to highlight in a document (`textDocument/documentHighlight`), e.g.
/// every occurrence of the identifier under the cursor.
class DocumentHighlight {
  final Range range;
  final int? kind;

  const DocumentHighlight(this.range, {this.kind});

  factory DocumentHighlight.fromJson(Map<String, Object?> json) =>
      DocumentHighlight(
        Range.fromJson(json['range'] as Map<String, Object?>),
        kind: (json['kind'] as num?)?.toInt(),
      );

  Map<String, Object?> toJson() => {
    'range': range.toJson(),
    if (kind != null) 'kind': kind,
  };
}

/// Result of `textDocument/prepareRename`: the [range] of the symbol that would
/// be renamed and a [placeholder] (its current text).
class PrepareRenameResult {
  final Range range;
  final String placeholder;

  const PrepareRenameResult(this.range, this.placeholder);

  factory PrepareRenameResult.fromJson(Map<String, Object?> json) =>
      PrepareRenameResult(
        Range.fromJson(json['range'] as Map<String, Object?>),
        json['placeholder'] as String? ?? '',
      );

  Map<String, Object?> toJson() => {
    'range': range.toJson(),
    'placeholder': placeholder,
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

  factory DocumentSymbol.fromJson(Map<String, Object?> json) => DocumentSymbol(
    name: json['name'] as String,
    detail: json['detail'] as String?,
    kind: (json['kind'] as num).toInt(),
    range: Range.fromJson(json['range'] as Map<String, Object?>),
    selectionRange: Range.fromJson(
      json['selectionRange'] as Map<String, Object?>,
    ),
    children: [
      for (final c in (json['children'] as List?) ?? const [])
        DocumentSymbol.fromJson(c as Map<String, Object?>),
    ],
  );

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

  factory CompletionItem.fromJson(Map<String, Object?> json) => CompletionItem(
    label: json['label'] as String,
    kind: (json['kind'] as num?)?.toInt() ?? CompletionItemKind.text,
    detail: json['detail'] as String?,
    sortText: json['sortText'] as String?,
    documentation: json['documentation'] == null
        ? null
        : MarkupContent.from(json['documentation']),
  );

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

  factory TextEdit.fromJson(Map<String, Object?> json) => TextEdit(
    Range.fromJson(json['range'] as Map<String, Object?>),
    json['newText'] as String? ?? '',
  );

  Map<String, Object?> toJson() => {
    'range': range.toJson(),
    'newText': newText,
  };
}

/// LSP `WorkspaceEdit` (document-scoped `changes` map).
class WorkspaceEdit {
  final Map<String, List<TextEdit>> changes;

  const WorkspaceEdit(this.changes);

  factory WorkspaceEdit.fromJson(Map<String, Object?> json) {
    final changes = <String, List<TextEdit>>{};
    final raw = json['changes'];
    if (raw is Map) {
      raw.forEach((uri, edits) {
        changes[uri as String] = [
          for (final e in (edits as List?) ?? const [])
            TextEdit.fromJson(e as Map<String, Object?>),
        ];
      });
    }
    return WorkspaceEdit(changes);
  }

  Map<String, Object?> toJson() => {
    'changes': changes.map(
      (uri, edits) => MapEntry(uri, edits.map((e) => e.toJson()).toList()),
    ),
  };
}

/// Result of the `initialize` request: the server's advertised
/// [capabilities] and optional [serverInfo].
class InitializeResult {
  final Map<String, Object?> capabilities;
  final ServerInfo? serverInfo;

  const InitializeResult({this.capabilities = const {}, this.serverInfo});

  factory InitializeResult.fromJson(Map<String, Object?> json) =>
      InitializeResult(
        capabilities:
            (json['capabilities'] as Map?)?.cast<String, Object?>() ?? const {},
        serverInfo: json['serverInfo'] is Map
            ? ServerInfo.fromJson(json['serverInfo'] as Map<String, Object?>)
            : null,
      );

  /// Whether the server advertised support for [capability] (e.g.
  /// `hoverProvider`), meaning a truthy value in [capabilities].
  bool supports(String capability) {
    final v = capabilities[capability];
    return v == true || (v != null && v != false);
  }
}

/// The server's self-description returned by `initialize`.
class ServerInfo {
  final String name;
  final String? version;

  const ServerInfo(this.name, {this.version});

  factory ServerInfo.fromJson(Map<String, Object?> json) => ServerInfo(
    json['name'] as String? ?? '',
    version: json['version'] as String?,
  );
}

/// Parameters of a `textDocument/publishDiagnostics` notification.
class PublishDiagnosticsParams {
  final String uri;
  final int? version;
  final List<Diagnostic> diagnostics;

  const PublishDiagnosticsParams({
    required this.uri,
    this.version,
    this.diagnostics = const [],
  });

  factory PublishDiagnosticsParams.fromJson(Map<String, Object?> json) =>
      PublishDiagnosticsParams(
        uri: json['uri'] as String,
        version: (json['version'] as num?)?.toInt(),
        diagnostics: [
          for (final d in (json['diagnostics'] as List?) ?? const [])
            Diagnostic.fromJson(d as Map<String, Object?>),
        ],
      );

  Map<String, Object?> toJson() => {
    'uri': uri,
    if (version != null) 'version': version,
    'diagnostics': diagnostics.map((d) => d.toJson()).toList(),
  };
}

/// An entry returned by `workspace/symbol`: a named declaration and where it
/// lives.
class WorkspaceSymbol {
  final String name;
  final int kind;
  final Location location;
  final String? containerName;

  const WorkspaceSymbol({
    required this.name,
    required this.kind,
    required this.location,
    this.containerName,
  });

  factory WorkspaceSymbol.fromJson(Map<String, Object?> json) =>
      WorkspaceSymbol(
        name: json['name'] as String,
        kind: (json['kind'] as num?)?.toInt() ?? 0,
        location: Location.fromJson(json['location'] as Map<String, Object?>),
        containerName: json['containerName'] as String?,
      );

  Map<String, Object?> toJson() => {
    'name': name,
    'kind': kind,
    'location': location.toJson(),
    if (containerName != null) 'containerName': containerName,
  };
}

/// Result of `textDocument/completion`: the [items] and whether the list is
/// [isIncomplete] (should be recomputed as the user keeps typing).
class CompletionList {
  final bool isIncomplete;
  final List<CompletionItem> items;

  const CompletionList({this.isIncomplete = false, this.items = const []});

  factory CompletionList.fromJson(Map<String, Object?> json) => CompletionList(
    isIncomplete: json['isIncomplete'] == true,
    items: [
      for (final i in (json['items'] as List?) ?? const [])
        CompletionItem.fromJson(i as Map<String, Object?>),
    ],
  );

  Map<String, Object?> toJson() => {
    'isIncomplete': isIncomplete,
    'items': items.map((i) => i.toJson()).toList(),
  };
}
