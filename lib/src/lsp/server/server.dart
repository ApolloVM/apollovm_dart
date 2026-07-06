// The LSP server: wires the transport to the analysis layer, translating each
// request into protocol responses. This is glue only — no parsing or position
// logic lives here.
import 'dart:async';

import 'package:apollovm/apollovm.dart' show ApolloVM;

import '../analysis/analyzer.dart';
import '../analysis/document_store.dart';
import '../analysis/symbols.dart';
import '../analysis/token_index.dart';
import '../protocol/protocol.dart';
import '../transport/json_rpc.dart';

class LspServer {
  final LspEndpoint _endpoint;
  final Analyzer _analyzer = Analyzer();
  final DocumentStore _store = DocumentStore();
  final Map<String, AnalyzedUnit> _cache = {};

  bool _shutdownRequested = false;

  /// Set when `exit` is received; the entrypoint uses it to choose exit code.
  bool cleanExit = false;

  /// Creates a server over any [LspEndpoint] — [StreamLspEndpoint] for stdio,
  /// or [MessageLspEndpoint] for a web IDE / AI-agent host.
  LspServer(this._endpoint) {
    _endpoint.onRequest = _handleRequest;
    _endpoint.onNotification = _handleNotification;
  }

  /// The underlying transport, e.g. to `receive()` messages on a
  /// [MessageLspEndpoint] host.
  LspEndpoint get endpoint => _endpoint;

  void start() => _endpoint.listen();

  Future<void> get done => _endpoint.done;

  // --- Requests ---

  Future<Object?> _handleRequest(String method, Object? params) async {
    final p = params is Map<String, Object?>
        ? params
        : const <String, Object?>{};
    switch (method) {
      case 'initialize':
        return _initialize();
      case 'shutdown':
        _shutdownRequested = true;
        return null;
      case 'textDocument/hover':
        return _hover(p);
      case 'textDocument/definition':
        return _definition(p);
      case 'textDocument/documentSymbol':
        return _documentSymbol(p);
      case 'textDocument/completion':
        return _completion(p);
      case 'textDocument/references':
        return _references(p);
      case 'textDocument/documentHighlight':
        return _documentHighlight(p);
      case 'textDocument/prepareRename':
        return _prepareRename(p);
      case 'textDocument/rename':
        return _rename(p);
      case 'workspace/symbol':
        return _workspaceSymbol(p);
      default:
        if (_shutdownRequested) {
          throw const ResponseError(
            ResponseError.invalidRequest,
            'Server is shutting down',
          );
        }
        throw ResponseError(
          ResponseError.methodNotFound,
          "Unhandled method '$method'",
        );
    }
  }

  Map<String, Object?> _initialize() {
    return {
      'capabilities': {
        // 2 = incremental text sync.
        'textDocumentSync': {'openClose': true, 'change': 2},
        'hoverProvider': true,
        'definitionProvider': true,
        'documentSymbolProvider': true,
        'referencesProvider': true,
        'documentHighlightProvider': true,
        // `prepareProvider` advertises `textDocument/prepareRename`.
        'renameProvider': {'prepareProvider': true},
        'workspaceSymbolProvider': true,
        'completionProvider': {
          'triggerCharacters': ['.'],
        },
      },
      'serverInfo': {'name': 'apollovm-lsp', 'version': ApolloVM.VERSION},
    };
  }

  // --- Notifications ---

  void _handleNotification(String method, Object? params) {
    final p = params is Map<String, Object?>
        ? params
        : const <String, Object?>{};
    switch (method) {
      case 'initialized':
        break;
      case 'textDocument/didOpen':
        final doc = p['textDocument'] as Map<String, Object?>?;
        if (doc == null) break;
        final uri = doc['uri'] as String;
        _store.open(
          uri,
          doc['text'] as String? ?? '',
          (doc['version'] as num?)?.toInt() ?? 0,
        );
        unawaited(_analyzeAndPublish(uri));
        break;
      case 'textDocument/didChange':
        final doc = p['textDocument'] as Map<String, Object?>?;
        if (doc == null) break;
        final uri = doc['uri'] as String;
        final changes = (p['contentChanges'] as List?) ?? const [];
        _store.applyChanges(uri, (doc['version'] as num?)?.toInt(), changes);
        _cache.remove(uri);
        unawaited(_analyzeAndPublish(uri));
        break;
      case 'textDocument/didClose':
        final doc = p['textDocument'] as Map<String, Object?>?;
        if (doc == null) break;
        final uri = doc['uri'] as String;
        _store.close(uri);
        _cache.remove(uri);
        _endpoint.sendNotification('textDocument/publishDiagnostics', {
          'uri': uri,
          'diagnostics': const [],
        });
        break;
      case 'exit':
        cleanExit = _shutdownRequested;
        break;
    }
  }

  // --- Analysis helpers ---

  /// Returns an up-to-date analysis for [uri], analyzing on demand so requests
  /// never observe a stale buffer.
  Future<AnalyzedUnit?> _unit(String uri) async {
    final doc = _store.get(uri);
    if (doc == null) return null;
    final cached = _cache[uri];
    if (cached != null && identical(cached.text, doc.text)) return cached;
    final unit = await _analyzer.analyze(uri, doc.text);
    _cache[uri] = unit;
    return unit;
  }

  Future<void> _analyzeAndPublish(String uri) async {
    final unit = await _unit(uri);
    if (unit == null) return;
    _endpoint.sendNotification('textDocument/publishDiagnostics', {
      'uri': uri,
      'diagnostics': unit.diagnostics.map((d) => d.toJson()).toList(),
    });
  }

  String? _containerAt(AnalyzedUnit unit, int offset) {
    String? best;
    int bestSpan = 1 << 30;
    for (final d in unit.tokenIndex.declarations) {
      if (d.kind != DeclKind.classDecl && d.kind != DeclKind.enumDecl) continue;
      if (offset >= d.fullStart && offset <= d.fullEnd) {
        final span = d.fullEnd - d.fullStart;
        if (span < bestSpan) {
          bestSpan = span;
          best = d.name;
        }
      }
    }
    return best;
  }

  ({int offset, IdentToken? ident, String? container})? _resolveCursor(
    AnalyzedUnit unit,
    Map<String, Object?> p,
  ) {
    final posJson = p['position'];
    if (posJson is! Map<String, Object?>) return null;
    final offset = unit.lineIndex.offsetAt(Position.fromJson(posJson));
    final ident = unit.tokenIndex.identifierAt(offset);
    return (
      offset: offset,
      ident: ident,
      container: _containerAt(unit, offset),
    );
  }

  String _uriOf(Map<String, Object?> p) =>
      (p['textDocument'] as Map<String, Object?>?)?['uri'] as String? ?? '';

  // --- Feature: hover ---

  Future<Map<String, Object?>?> _hover(Map<String, Object?> p) async {
    final unit = await _unit(_uriOf(p));
    if (unit == null) return null;
    final cur = _resolveCursor(unit, p);
    final ident = cur?.ident;
    if (ident == null) return null;

    final sym = unit.symbolFor(ident.name, container: cur!.container);
    final decl = unit.tokenIndex.findDeclaration(
      ident.name,
      container: cur.container,
    );

    final buf = StringBuffer();
    if (sym != null) {
      buf.writeln('```');
      buf.writeln('${_categoryLabel(sym.category)}:');
      buf.writeln(sym.signature);
      buf.writeln('```');
      if (sym.typeName != null && sym.typeName!.isNotEmpty) {
        buf.writeln('\nType: `${sym.typeName}`');
      }
    } else {
      buf.writeln('`${ident.name}`');
    }

    if (decl != null) {
      final doc = unit.docs.docFor(decl.fullStart);
      if (doc != null && doc.isNotEmpty) {
        buf.writeln('\n$doc');
      }
    }

    return Hover(
      MarkupContent.markdown(buf.toString().trimRight()),
      range: unit.lineIndex.rangeAt(ident.start, ident.end),
    ).toJson();
  }

  String _categoryLabel(SymbolCategory c) {
    switch (c) {
      case SymbolCategory.classSym:
        return 'Class';
      case SymbolCategory.enumSym:
        return 'Enum';
      case SymbolCategory.function:
        return 'Function';
      case SymbolCategory.method:
        return 'Method';
      case SymbolCategory.constructor:
        return 'Constructor';
      case SymbolCategory.getter:
        return 'Getter';
      case SymbolCategory.field:
        return 'Field';
      case SymbolCategory.enumMember:
        return 'Enum value';
    }
  }

  // --- Feature: definition ---

  Future<Object?> _definition(Map<String, Object?> p) async {
    final uri = _uriOf(p);
    final unit = await _unit(uri);
    if (unit == null) return null;
    final cur = _resolveCursor(unit, p);
    final ident = cur?.ident;
    if (ident == null) return null;

    final decl =
        unit.tokenIndex.findDeclaration(
          ident.name,
          container: cur!.container,
        ) ??
        unit.tokenIndex.findDeclaration(ident.name);
    if (decl == null) return null;

    return Location(
      uri,
      unit.lineIndex.rangeAt(decl.nameStart, decl.nameEnd),
    ).toJson();
  }

  // --- Feature: document symbols ---

  Future<List<Object?>> _documentSymbol(Map<String, Object?> p) async {
    final unit = await _unit(_uriOf(p));
    if (unit == null) return const [];

    final containers = <String, DocumentSymbolBuilder>{};
    final roots = <DocumentSymbolBuilder>[];

    // First pass: class/enum containers.
    for (final d in unit.tokenIndex.declarations) {
      if (d.kind == DeclKind.classDecl || d.kind == DeclKind.enumDecl) {
        final b = _builderFor(unit, d);
        containers[d.name] = b;
        if (d.container == null) roots.add(b);
      }
    }
    // Second pass: members and top-level members.
    for (final d in unit.tokenIndex.declarations) {
      if (d.kind == DeclKind.classDecl || d.kind == DeclKind.enumDecl) continue;
      final b = _builderFor(unit, d);
      final parent = d.container != null ? containers[d.container] : null;
      if (parent != null) {
        parent.children.add(b);
      } else {
        roots.add(b);
      }
    }

    return roots.map((b) => b.build().toJson()).toList();
  }

  DocumentSymbolBuilder _builderFor(AnalyzedUnit unit, DeclSite d) {
    final sym = unit.symbolFor(d.name, container: d.container);
    return DocumentSymbolBuilder(
      name: d.name,
      detail: sym?.signature,
      kind: _symbolKind(d.kind),
      range: unit.lineIndex.rangeAt(d.fullStart, d.fullEnd),
      selectionRange: unit.lineIndex.rangeAt(d.nameStart, d.nameEnd),
    );
  }

  int _symbolKind(DeclKind k) {
    switch (k) {
      case DeclKind.classDecl:
        return SymbolKind.classKind;
      case DeclKind.enumDecl:
        return SymbolKind.enumKind;
      case DeclKind.function:
        return SymbolKind.function;
      case DeclKind.method:
        return SymbolKind.method;
      case DeclKind.constructor:
        return SymbolKind.constructor;
      case DeclKind.field:
        return SymbolKind.field;
      case DeclKind.variable:
        return SymbolKind.variable;
      case DeclKind.enumMember:
        return SymbolKind.enumMember;
    }
  }

  // --- Feature: completion (basic; ranking demonstrated) ---

  Future<Map<String, Object?>> _completion(Map<String, Object?> p) async {
    final unit = await _unit(_uriOf(p));
    if (unit == null) return {'isIncomplete': false, 'items': const []};
    final cur = _resolveCursor(unit, p);
    final container = cur?.container;
    final cursorOffset = cur?.offset ?? -1;

    final decls = unit.tokenIndex.declarations;

    final items = <CompletionItem>[];
    final seen = <String>{};

    void add(String label, int kind, {String? detail, required String rank}) {
      if (label.isEmpty || !seen.add(label)) return;
      items.add(
        CompletionItem(
          label: label,
          kind: kind,
          detail: detail,
          sortText: '${rank}_$label',
        ),
      );
    }

    Map<String, Object?> result() => {
      'isIncomplete': false,
      'items': items.map((i) => i.toJson()).toList(),
    };

    // Member access `<receiver>.<partial>`: for `this`/`super`, propose only
    // the enclosing type's members (with their real kinds) — never keywords or
    // unrelated globals. This works even while the buffer does not parse (the
    // usual state right after typing `.`), because it reads the token-index
    // declarations rather than the AST.
    final receiver = _memberAccessReceiver(unit.text, cursorOffset);
    if (receiver == 'this' || receiver == 'super') {
      for (final d in decls) {
        if (d.kind == DeclKind.constructor) continue; // not reached via `this.`
        final isMember = container != null
            ? d.container == container
            : d.container != null;
        if (!isMember) continue;
        add(d.name, _declCompletionKind(d.kind), rank: '0');
      }
      // Only commit to member-only results if we actually found members;
      // otherwise fall through to the general proposals below.
      if (items.isNotEmpty) return result();
    }

    // 1. Declared symbols from the AST (richest: real kind + signature).
    //    Rank local scope (same container) first, then the rest.
    for (final s in unit.symbols) {
      final isLocal = container != null && s.container == container;
      add(
        s.name,
        _completionKind(s.category),
        detail: s.signature,
        rank: isLocal ? '0' : '1',
      );
    }

    // 2. Token-index declarations. Unlike the AST symbols these survive a
    //    *failed* parse — the common case while typing — so methods and fields
    //    keep their real kinds instead of degrading to plain identifiers.
    for (final d in decls) {
      final isLocal = container != null && d.container == container;
      add(d.name, _declCompletionKind(d.kind), rank: isLocal ? '0' : '1');
    }

    // 3. Identifiers harvested from the raw token stream: local variables and
    //    parameters the symbol table omits. Skip the partial token under the
    //    cursor (the word being typed).
    for (final t in unit.tokenIndex.identifiers) {
      if (cursorOffset >= t.start && cursorOffset <= t.end) continue;
      if (_keywordSet.contains(t.name)) continue;
      add(t.name, CompletionItemKind.variable, rank: '2');
    }

    // 4. Language keywords.
    for (final kw in _keywords) {
      add(kw, CompletionItemKind.keyword, rank: '3');
    }

    return result();
  }

  /// If the caret sits in a member-access position `<receiver>.<partial>`,
  /// returns the receiver identifier (e.g. `this`, `super`, a variable name, or
  /// `''` for a non-identifier receiver). Returns `null` when the caret is not
  /// after a `.`.
  static String? _memberAccessReceiver(String text, int offset) {
    if (offset < 0 || offset > text.length) return null;
    var i = offset;
    // Skip the partial member identifier being typed.
    while (i > 0 && _isIdentChar(text.codeUnitAt(i - 1))) {
      i--;
    }
    // Require a '.' (possibly after inline spaces) immediately to the left.
    var j = i;
    while (j > 0 && _isInlineSpace(text.codeUnitAt(j - 1))) {
      j--;
    }
    if (j == 0 || text.codeUnitAt(j - 1) != 0x2e /* . */ ) return null;
    j--; // consume the '.'
    while (j > 0 && _isInlineSpace(text.codeUnitAt(j - 1))) {
      j--;
    }
    final end = j;
    while (j > 0 && _isIdentChar(text.codeUnitAt(j - 1))) {
      j--;
    }
    return text.substring(j, end);
  }

  static bool _isIdentChar(int c) =>
      c == 0x5f || // _
      (c >= 0x30 && c <= 0x39) || // 0-9
      (c >= 0x41 && c <= 0x5a) || // A-Z
      (c >= 0x61 && c <= 0x7a); // a-z

  static bool _isInlineSpace(int c) => c == 0x20 || c == 0x09;

  int _declCompletionKind(DeclKind k) {
    switch (k) {
      case DeclKind.classDecl:
        return CompletionItemKind.classKind;
      case DeclKind.enumDecl:
        return CompletionItemKind.enumKind;
      case DeclKind.function:
        return CompletionItemKind.function;
      case DeclKind.method:
        return CompletionItemKind.method;
      case DeclKind.constructor:
        return CompletionItemKind.constructor;
      case DeclKind.field:
        return CompletionItemKind.field;
      case DeclKind.variable:
        return CompletionItemKind.variable;
      case DeclKind.enumMember:
        return CompletionItemKind.enumMember;
    }
  }

  int _completionKind(SymbolCategory c) {
    switch (c) {
      case SymbolCategory.classSym:
        return CompletionItemKind.classKind;
      case SymbolCategory.enumSym:
        return CompletionItemKind.enumKind;
      case SymbolCategory.function:
        return CompletionItemKind.function;
      case SymbolCategory.method:
        return CompletionItemKind.method;
      case SymbolCategory.constructor:
        return CompletionItemKind.constructor;
      case SymbolCategory.getter:
        return CompletionItemKind.property;
      case SymbolCategory.field:
        return CompletionItemKind.field;
      case SymbolCategory.enumMember:
        return CompletionItemKind.enumMember;
    }
  }

  // --- Feature: references (in-file, name-scoped) ---

  Future<List<Object?>> _references(Map<String, Object?> p) async {
    final uri = _uriOf(p);
    final unit = await _unit(uri);
    if (unit == null) return const [];
    final cur = _resolveCursor(unit, p);
    final ident = cur?.ident;
    if (ident == null) return const [];

    return [
      for (final t in unit.tokenIndex.identifiers)
        if (t.name == ident.name)
          Location(uri, unit.lineIndex.rangeAt(t.start, t.end)).toJson(),
    ];
  }

  // --- Feature: document highlight (occurrences of the cursor's name) ---

  Future<List<Object?>> _documentHighlight(Map<String, Object?> p) async {
    final unit = await _unit(_uriOf(p));
    if (unit == null) return const [];
    final cur = _resolveCursor(unit, p);
    final ident = cur?.ident;
    if (ident == null) return const [];

    // Occurrences that coincide with a declaration's name are `Write`; the rest
    // are `Read`.
    final declStarts = <int>{
      for (final d in unit.tokenIndex.declarations)
        if (d.name == ident.name) d.nameStart,
    };

    return [
      for (final t in unit.tokenIndex.identifiers)
        if (t.name == ident.name)
          DocumentHighlight(
            unit.lineIndex.rangeAt(t.start, t.end),
            kind: declStarts.contains(t.start)
                ? DocumentHighlightKind.write
                : DocumentHighlightKind.read,
          ).toJson(),
    ];
  }

  // --- Feature: prepare rename (validate the target under the cursor) ---

  Future<Map<String, Object?>?> _prepareRename(Map<String, Object?> p) async {
    final unit = await _unit(_uriOf(p));
    if (unit == null) return null;
    final cur = _resolveCursor(unit, p);
    final ident = cur?.ident;
    if (ident == null) return null;

    return {
      'range': unit.lineIndex.rangeAt(ident.start, ident.end).toJson(),
      'placeholder': ident.name,
    };
  }

  // --- Feature: rename (in-file, name-scoped) ---

  Future<Map<String, Object?>?> _rename(Map<String, Object?> p) async {
    final uri = _uriOf(p);
    final unit = await _unit(uri);
    if (unit == null) return null;
    final cur = _resolveCursor(unit, p);
    final ident = cur?.ident;
    if (ident == null) return null;
    final newName = p['newName'] as String?;
    if (newName == null || newName.isEmpty) return null;

    final edits = <TextEdit>[
      for (final t in unit.tokenIndex.identifiers)
        if (t.name == ident.name)
          TextEdit(unit.lineIndex.rangeAt(t.start, t.end), newName),
    ];
    return WorkspaceEdit({uri: edits}).toJson();
  }

  // --- Feature: workspace symbols (follow-up: needs workspace index) ---

  Future<List<Object?>> _workspaceSymbol(Map<String, Object?> p) async {
    final query = (p['query'] as String? ?? '').toLowerCase();
    final out = <Object?>[];
    for (final unit in _cache.values) {
      for (final d in unit.tokenIndex.declarations) {
        if (query.isEmpty || d.name.toLowerCase().contains(query)) {
          out.add({
            'name': d.name,
            'kind': _symbolKind(d.kind),
            'location': Location(
              unit.uri,
              unit.lineIndex.rangeAt(d.nameStart, d.nameEnd),
            ).toJson(),
            if (d.container != null) 'containerName': d.container,
          });
        }
      }
    }
    return out;
  }

  static final Set<String> _keywordSet = _keywords.toSet();

  static const _keywords = [
    'class',
    'enum',
    'void',
    'int',
    'double',
    'String',
    'bool',
    'var',
    'final',
    'const',
    'return',
    'if',
    'else',
    'for',
    'while',
    'switch',
    'case',
    'break',
    'continue',
    'new',
    'this',
    'super',
    'true',
    'false',
    'null',
    'import',
  ];
}

/// Mutable builder so nested [DocumentSymbol] children can be attached in a
/// second pass before the immutable tree is produced.
class DocumentSymbolBuilder {
  final String name;
  final String? detail;
  final int kind;
  final Range range;
  final Range selectionRange;
  final List<DocumentSymbolBuilder> children = [];

  DocumentSymbolBuilder({
    required this.name,
    required this.kind,
    required this.range,
    required this.selectionRange,
    this.detail,
  });

  DocumentSymbol build() => DocumentSymbol(
    name: name,
    detail: detail,
    kind: kind,
    range: range,
    selectionRange: selectionRange,
    children: children.map((c) => c.build()).toList(),
  );
}
