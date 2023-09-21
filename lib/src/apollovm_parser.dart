import 'package:petitparser/petitparser.dart';

import 'apollovm_base.dart';
import 'ast/apollovm_ast_toplevel.dart';

/// Base class for [ApolloVM] parsers.
abstract class ApolloParser {
  /// The [GrammarDefinition] of this parser.
  final GrammarDefinition _grammar;

  ApolloParser(this._grammar);

  /// The language of this parser.
  String get language;

  Parser<dynamic>? _grammarParserInstance;

  Parser<dynamic> get _grammarParser {
    _grammarParserInstance ??= _grammar.build();
    return _grammarParserInstance!;
  }

  /// Parses a [codeUnit] to an [ASTRoot] and returns a [ParseResult].
  ///
  /// If some error occurs, returns a [ParseResult] with an error message.
  Future<ParseResult> parse(CodeUnit codeUnit) async {
    check(codeUnit);

    var result = _grammarParser.parse(codeUnit.source);

    if (result is! Success) {
      return ParseResult(errorMessage: result.message);
    }

    var root = result.value;
    return ParseResult(root: root);
  }

  void check(CodeUnit codeUnit) {
    if (codeUnit.language != language) {
      throw StateError(
          "This parser is for the language '$language'. Trying to parse a CodeUnit of language: '${codeUnit.language}'");
    }
  }
}

class ParseResult {
  /// A parsed [ASTRoot]
  final ASTRoot? root;

  /// The error message if some parsing error occurred.
  final String? errorMessage;

  /// Returns true if this parse result is OK.
  bool get isOK => root != null;

  /// Returns true if this parse result has errors.
  bool get hasError => root == null;

  ParseResult({this.root, this.errorMessage});
}

/// Syntax [Error] while parsing.
class SyntaxError extends Error {
  String message;

  SyntaxError(this.message);

  @override
  String toString() {
    return '[SyntaxError] $message';
  }
}

/// Unsupported type [Error] while parsing.
class UnsupportedTypeError extends UnsupportedError {
  UnsupportedTypeError(String message) : super('[Unsupported Type] $message');
}

/// Unsupported syntax [Error] while parsing.
class UnsupportedSyntaxError extends UnsupportedError {
  UnsupportedSyntaxError(String message)
      : super('[Unsupported Syntax] $message');
}

/// Unsupported value operation [Error] while parsing.
class UnsupportedValueOperationError extends UnsupportedError {
  UnsupportedValueOperationError(String message)
      : super('[Unsupported Value operation] $message');
}

extension ListTypedExtension<T> on List<T> {
  /// Provide access to the generic type at runtime.
  Type get genericType => T;
}
