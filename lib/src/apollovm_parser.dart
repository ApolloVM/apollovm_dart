import 'package:apollovm/apollovm.dart';
import 'package:apollovm/src/apollovm_ast.dart';
import 'package:petitparser/petitparser.dart';

abstract class ApolloParser {
  final GrammarDefinition _grammar;

  ApolloParser(this._grammar);

  String get language;

  Parser<dynamic>? _grammarParserInstance;

  Parser<dynamic> get _grammarParser {
    _grammarParserInstance ??= _grammar.build();
    return _grammarParserInstance!;
  }

  Future<ParseResult> parse(CodeUnit codeUnit) async {
    check(codeUnit);

    var result = _grammarParser.parse(codeUnit.source);

    if (!result.isSuccess) {
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
  final ASTCodeRoot? root;
  final String? errorMessage;

  bool get isOK => root != null;
  bool get hasError => root == null;

  ParseResult({this.root, this.errorMessage});
}

class UnsupportedTypeError extends UnsupportedError {
  UnsupportedTypeError(String message) : super('[Unsupported Type] $message');
}

class UnsupportedSyntaxError extends UnsupportedError {
  UnsupportedSyntaxError(String message)
      : super('[Unsupported Syntax] $message');
}

class UnsupportedValueOperationError extends UnsupportedError {
  UnsupportedValueOperationError(String message)
      : super('[Unsupported Value operation] $message');
}

extension ListTypedExtension<T> on List<T> {
  /// Provide access to the generic type at runtime.
  Type get genericType => T;
}
