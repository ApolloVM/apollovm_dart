// The analysis brain: parses a document via `package:apollovm`, builds the
// position index and symbol table, and produces diagnostics. All ApolloVM
// access is read-only; the parser/AST are never modified.
import 'package:apollovm/apollovm.dart';

import '../protocol/protocol.dart';
import 'doc_extractor.dart';
import 'line_index.dart';
import 'symbols.dart';
import 'token_index.dart';

/// The cached analysis of one document version.
class AnalyzedUnit {
  final String uri;
  final String language;
  final String text;
  final LineIndex lineIndex;
  final TokenIndex tokenIndex;
  final DocExtractor docs;

  /// Null when the source failed to parse.
  final ASTRoot? ast;
  final List<SymbolInfo> symbols;
  final List<Diagnostic> diagnostics;

  AnalyzedUnit({
    required this.uri,
    required this.language,
    required this.text,
    required this.lineIndex,
    required this.tokenIndex,
    required this.docs,
    required this.ast,
    required this.symbols,
    required this.diagnostics,
  });

  /// Finds the semantic symbol for [name], preferring one in [container].
  SymbolInfo? symbolFor(String name, {String? container}) {
    SymbolInfo? fallback;
    for (final s in symbols) {
      if (s.name != name) continue;
      if (container != null && s.container == container) return s;
      fallback ??= s;
    }
    return fallback;
  }
}

class Analyzer {
  final ApolloVM _vm = ApolloVM();

  /// Maps a document URI/path extension to an ApolloVM language id.
  static String? languageOf(String uri) {
    final dot = uri.lastIndexOf('.');
    if (dot < 0) return null;
    switch (uri.substring(dot + 1).toLowerCase()) {
      case 'dart':
        return 'dart';
      case 'java':
        return 'java';
      case 'kt':
      case 'kts':
        return 'kotlin';
      case 'cs':
        return 'csharp';
      case 'js':
        return 'javascript';
      case 'ts':
        return 'typescript';
      case 'lua':
        return 'lua';
      case 'py':
        return 'python';
      default:
        return null;
    }
  }

  Future<AnalyzedUnit> analyze(String uri, String text) async {
    final lineIndex = LineIndex(text);
    final tokenIndex = TokenIndex.scan(text);
    final docs = DocExtractor(text);
    final language = languageOf(uri) ?? 'dart';

    final parser = _vm.getParser<String>(language);
    final diagnostics = <Diagnostic>[];
    ASTRoot? ast;
    var symbols = const <SymbolInfo>[];

    if (parser == null) {
      diagnostics.add(
        Diagnostic(
          range: lineIndex.rangeAt(0, 0),
          message: "No ApolloVM parser for language '$language'.",
          severity: DiagnosticSeverity.warning,
        ),
      );
    } else {
      ParseResult<String> result;
      try {
        result = await parser.parse(SourceCodeUnit(language, text, id: uri));
      } catch (e) {
        result = ParseResult(
          SourceCodeUnit(language, text, id: uri),
          errorMessage: e.toString(),
        );
      }

      if (result.isOK) {
        ast = result.root;
        symbols = collectSymbols(ast!);
        diagnostics.addAll(_importDiagnostics(ast, text, lineIndex));
      } else {
        diagnostics.add(_parseErrorDiagnostic(result, lineIndex, text));
      }
    }

    return AnalyzedUnit(
      uri: uri,
      language: language,
      text: text,
      lineIndex: lineIndex,
      tokenIndex: tokenIndex,
      docs: docs,
      ast: ast,
      symbols: symbols,
      diagnostics: diagnostics,
    );
  }

  Diagnostic _parseErrorDiagnostic(
    ParseResult<String> result,
    LineIndex lineIndex,
    String text,
  ) {
    final pos = result.errorPosition;
    Range range;
    if (pos != null && pos >= 0 && pos <= text.length) {
      final start = lineIndex.positionAt(pos);
      // Highlight to end of the token/line for visibility.
      var end = pos;
      while (end < text.length &&
          text.codeUnitAt(end) != 0x0a &&
          end < pos + 1) {
        end++;
      }
      range = Range(start, lineIndex.positionAt(end == pos ? pos + 1 : end));
    } else {
      range = lineIndex.rangeAt(0, 1);
    }
    return Diagnostic(
      range: range,
      message: result.errorMessage ?? 'Parse error.',
      code: 'parse-error',
    );
  }

  /// Flags `dart:`-style core imports that ApolloVM cannot resolve. Relative and
  /// package imports are left unflagged pending a static import graph.
  List<Diagnostic> _importDiagnostics(
    ASTRoot ast,
    String text,
    LineIndex lineIndex,
  ) {
    final out = <Diagnostic>[];
    final importManager = ApolloImportManager();
    for (final import in ast.imports) {
      final path = import.path;
      if (path.startsWith('dart:') &&
          importManager.resolveCorePackage(path) == null) {
        final range = _locate(text, path, lineIndex);
        out.add(
          Diagnostic(
            range: range,
            message:
                "Unresolved core import '$path' (ApolloVM resolves only known "
                "core packages such as 'dart:math').",
            severity: DiagnosticSeverity.warning,
            code: 'unresolved-import',
          ),
        );
      }
    }
    return out;
  }

  Range _locate(String text, String needle, LineIndex lineIndex) {
    final idx = text.indexOf(needle);
    if (idx < 0) return lineIndex.rangeAt(0, 1);
    return lineIndex.rangeAt(idx, idx + needle.length);
  }
}
