// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:apollovm/apollovm_lsp.dart';

import '../mcp_config.dart';

/// In-process façade over the ApolloVM Language Server ([LspService]) used by
/// the MCP `apollovm.lsp.*` tools, so an AI agent can inspect code the way an
/// editor does: diagnostics, outline, hover, go-to-definition, references,
/// completion and workspace-wide symbol search.
///
/// Web-safe and stateless: each call spins up an in-process server (no socket,
/// no `dart:io`), answers the query against the given source, and disposes. The
/// parser is selected from the source [language] (via a matching document URI),
/// so results never depend on ambient state.
class LspRuntime {
  final McpLimits limits;

  LspRuntime({this.limits = const McpLimits()});

  /// Canonical language name -> file extension, so the LSP analyzer (which
  /// infers the language from the document URI) selects the right parser.
  static const _extensions = <String, String>{
    'dart': 'dart',
    'java': 'java',
    'kotlin': 'kt',
    'go': 'go',
    'csharp': 'cs',
    'javascript': 'js',
    'typescript': 'ts',
    'lua': 'lua',
    'python': 'py',
  };

  /// The languages the LSP tools can analyze (all supported languages except
  /// `wasm`, which is a compile target rather than a parsed source language).
  static List<String> get supportedLanguages => _extensions.keys.toList();

  Map<String, Object?> _error(String message) => <String, Object?>{
    'diagnostics': [
      <String, Object?>{'severity': 'error', 'message': message},
    ],
    'isError': true,
  };

  /// Validates [language]/[source] and returns the document URI to analyze
  /// under, or an error map (checked via the `isError` key) when invalid.
  Object _prepare(String language, String source, {String? uri}) {
    if (source.length > limits.maxSourceChars) {
      return _error(
        'Source exceeds maxSourceChars '
        '(${source.length} > ${limits.maxSourceChars})',
      );
    }
    final ext = _extensions[language];
    if (ext == null) {
      return _error(
        'Unsupported language: $language '
        '(LSP languages: ${supportedLanguages.join(', ')})',
      );
    }
    // Honor a caller URI only when its extension already selects this language;
    // otherwise synthesize one so the parser matches [language].
    if (uri != null && Analyzer.languageOf(uri) == language) return uri;
    return 'file:///mcp/source.$ext';
  }

  /// Runs [query] against a fresh in-process service with [source] open at the
  /// resolved URI, disposing the service afterwards.
  Future<Map<String, Object?>> _withDoc(
    String language,
    String source,
    Future<Map<String, Object?>> Function(LspService lsp, String uri) query, {
    String? uri,
  }) async {
    final prepared = _prepare(language, source, uri: uri);
    if (prepared is Map<String, Object?>) return prepared; // error
    final docUri = prepared as String;

    final lsp = LspService();
    try {
      lsp.open(docUri, source);
      return await query(lsp, docUri);
    } finally {
      await lsp.dispose();
    }
  }

  /// Diagnostics (errors/warnings) for [source], with precise LSP ranges.
  Future<Map<String, Object?>> diagnostics(
    String language,
    String source, {
    String? uri,
  }) => _withDoc(language, source, uri: uri, (lsp, docUri) async {
    final diags = await lsp.analyze(docUri, source);
    return <String, Object?>{
      'diagnostics': diags.map((d) => d.toJson()).toList(),
      'ok': diags.every((d) => d.severity != DiagnosticSeverity.error),
      'isError': false,
    };
  });

  /// The document outline: hierarchical symbols with their source ranges.
  Future<Map<String, Object?>> documentSymbols(
    String language,
    String source, {
    String? uri,
  }) => _withDoc(language, source, uri: uri, (lsp, docUri) async {
    final symbols = await lsp.documentSymbols(docUri);
    return <String, Object?>{
      'symbols': symbols.map((s) => s.toJson()).toList(),
      'isError': false,
    };
  });

  /// Hover information (signature + documentation) at [line]:[character].
  Future<Map<String, Object?>> hover(
    String language,
    String source,
    int line,
    int character, {
    String? uri,
  }) => _withDoc(language, source, uri: uri, (lsp, docUri) async {
    final hover = await lsp.hover(docUri, Position(line, character));
    return <String, Object?>{'hover': hover?.toJson(), 'isError': false};
  });

  /// The declaration location for the symbol at [line]:[character].
  Future<Map<String, Object?>> definition(
    String language,
    String source,
    int line,
    int character, {
    String? uri,
  }) => _withDoc(language, source, uri: uri, (lsp, docUri) async {
    final def = await lsp.definition(docUri, Position(line, character));
    return <String, Object?>{'definition': def?.toJson(), 'isError': false};
  });

  /// All references to the symbol at [line]:[character].
  Future<Map<String, Object?>> references(
    String language,
    String source,
    int line,
    int character, {
    bool includeDeclaration = true,
    String? uri,
  }) => _withDoc(language, source, uri: uri, (lsp, docUri) async {
    final refs = await lsp.references(
      docUri,
      Position(line, character),
      includeDeclaration: includeDeclaration,
    );
    return <String, Object?>{
      'references': refs.map((l) => l.toJson()).toList(),
      'isError': false,
    };
  });

  /// Completion proposals at [line]:[character].
  Future<Map<String, Object?>> completion(
    String language,
    String source,
    int line,
    int character, {
    String? uri,
  }) => _withDoc(language, source, uri: uri, (lsp, docUri) async {
    final list = await lsp.completion(docUri, Position(line, character));
    return <String, Object?>{'completion': list.toJson(), 'isError': false};
  });

  /// Searches declarations matching [query] across a set of in-memory [files]
  /// (`{uri, source, language?}`), enabling codebase-wide symbol lookup.
  Future<Map<String, Object?>> workspaceSymbols(
    String query,
    List<Object?> files,
  ) async {
    final entries = <({String uri, String source})>[];
    var totalChars = 0;
    for (final raw in files) {
      if (raw is! Map) continue;
      final source = (raw['source'] as String?) ?? '';
      totalChars += source.length;
      if (totalChars > limits.maxSourceChars) {
        return _error(
          'Combined sources exceed maxSourceChars '
          '($totalChars > ${limits.maxSourceChars})',
        );
      }
      final language = raw['language'] as String?;
      final uri = _fileUri(raw['uri'] as String?, language, entries.length);
      entries.add((uri: uri, source: source));
    }

    final lsp = LspService();
    try {
      // Analyze each file so its symbols are cached before the query.
      for (final e in entries) {
        await lsp.analyze(e.uri, e.source);
      }
      final symbols = await lsp.workspaceSymbols(query);
      return <String, Object?>{
        'symbols': symbols.map((s) => s.toJson()).toList(),
        'files': entries.map((e) => e.uri).toList(),
        'isError': false,
      };
    } finally {
      await lsp.dispose();
    }
  }

  /// Resolves a workspace file's URI, synthesizing one from [language] when the
  /// given [uri] is absent or its extension does not select a known language.
  String _fileUri(String? uri, String? language, int index) {
    if (uri != null && Analyzer.languageOf(uri) != null) return uri;
    final ext = _extensions[language] ?? 'dart';
    if (uri != null) return 'file:///mcp/$uri.$ext';
    return 'file:///mcp/file$index.$ext';
  }
}
