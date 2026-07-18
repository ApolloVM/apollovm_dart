// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:petitparser/petitparser.dart';
import 'package:petitparser/reflection.dart';
import 'package:swiss_knife/swiss_knife.dart';

import 'apollovm_base.dart';
import 'ast/apollovm_ast_toplevel.dart';

/// Base class for [ApolloVM] parsers.
abstract class ApolloCodeParser<T extends Object> {
  /// The language of this parser.
  String get language;

  /// Parses a [codeUnit] to an [ASTRoot] and returns a [ParseResult].
  ///
  /// If some error occurs, returns a [ParseResult] with an error message.
  Future<ParseResult<T>> parse(CodeUnit<T> codeUnit);

  void check(CodeUnit codeUnit) {
    if (!acceptsLanguage(codeUnit.language)) {
      throw StateError(
        "This parser is for the language '$language'. Trying to parse a CodeUnit of language: '${codeUnit.language}'",
      );
    }
  }

  bool acceptsLanguage(String language) {
    return this.language == language;
  }
}

/// Base class for [ApolloVM] source code parsers.
abstract class ApolloSourceCodeParser extends ApolloCodeParser<String> {
  /// The [GrammarDefinition] of this parser.
  final GrammarDefinition _grammar;

  ApolloSourceCodeParser(this._grammar);

  Parser<dynamic>? _grammarParserInstance;

  Parser<dynamic> get _grammarParser {
    _grammarParserInstance ??= _grammar.build();
    return _grammarParserInstance!;
  }

  /// Whether this parser, upon a parse failure, should re-parse with a
  /// farthest-failure tracker to report the error at the deepest point the
  /// grammar actually reached (instead of petitparser's top-level
  /// `end()`-at-offset-0 failure). Opt-in per language; defaults to `false`.
  bool get trackFarthestFailure => false;

  /// The farthest [Failure] observed during the last diagnostic re-parse.
  /// Only used when [trackFarthestFailure] is `true`. Parsing is synchronous,
  /// so this single mutable field is safe to reset per [parse] call.
  Failure? _farthestFailure;

  Parser<dynamic>? _diagParserInstance;

  /// A copy of the grammar where every parser is wrapped so that each [Failure]
  /// it produces updates [_farthestFailure] if it is the farthest seen. This
  /// captures failures that a surrounding `star()`/`optional()` would otherwise
  /// discard — exactly what plain `parse()` loses.
  Parser<dynamic> get _diagParser {
    _diagParserInstance ??= transformParser(_grammar.build(), <R>(
      Parser<R> parser,
    ) {
      return parser.callCC<R>((continuation, context) {
        final result = continuation(context);
        if (result is Failure) {
          final best = _farthestFailure;
          if (best == null || result.position >= best.position) {
            _farthestFailure = result;
          }
        }
        return result;
      });
    });
    return _diagParserInstance!;
  }

  /// Parses a [codeUnit] to an [ASTRoot] and returns a [ParseResult].
  ///
  /// If some error occurs, returns a [ParseResult] with an error message.
  @override
  Future<ParseResult<String>> parse(CodeUnit<String> codeUnit) async {
    check(codeUnit);

    final Result<dynamic> result;
    try {
      result = _grammarParser.parse(codeUnit.code);
    } on SyntaxError {
      // Intentional grammar-action validation error — preserve the established
      // contract of propagating it to the caller.
      rethrow;
    } on UnsupportedSyntaxError {
      // Intentional "unsupported syntax" grammar-action error — also propagates.
      rethrow;
    } catch (e) {
      // Any OTHER error from a grammar action (a `.map` callback) — e.g. the
      // grammar matched a compound operator (`%=`, `<<=`, …) the AST builder
      // doesn't support yet, which threw a raw `UnsupportedError`. Surface it as
      // a clean parse error instead of letting it escape `loadCodeUnit` as an
      // uncaught Dart exception.
      return ParseResult(
        codeUnit,
        errorMessage: "Can't parse code: $e",
        errorPosition: 0,
        errorLineAndColumn: const [1, 1],
      );
    }

    if (result is! Success) {
      Result<dynamic> errorResult = result;

      // Re-parse to locate the farthest point the grammar reached, which is at
      // or immediately adjacent to the real syntax error. Only the deeper of
      // the two is used, so this never worsens the reported position.
      if (trackFarthestFailure) {
        _farthestFailure = null;
        _diagParser.parse(codeUnit.code);
        final farthest = _farthestFailure;
        if (farthest != null && farthest.position >= result.position) {
          errorResult = farthest;
        }
      }

      var lineAndColumn = errorResult
          .toPositionString()
          .split(':')
          .map((e) => parseInt(e)!)
          .toList();

      return ParseResult(
        codeUnit,
        errorMessage: errorResult.message,
        errorPosition: errorResult.position,
        errorLineAndColumn: lineAndColumn,
      );
    }

    var root = result.value;
    return ParseResult(codeUnit, root: root);
  }
}

class ParseResult<T> {
  /// The parsed code.
  final CodeUnit<T> codeUnit;

  /// The parsed [codeUnit] code.
  T get source => codeUnit.code;

  /// A parsed [ASTRoot]
  final ASTRoot? root;

  /// The error message if some parsing error occurred.
  final String? errorMessage;

  /// The position of the error in the [codeUnit] [source].
  final int? errorPosition;

  /// The line and column of the error in the [codeUnit] [source].
  final List<int>? errorLineAndColumn;

  /// Returns true if this parse result is OK.
  bool get isOK => root != null;

  /// Returns true if this parse result has errors.
  bool get hasError => root == null;

  /// The error line at [codeUnit].
  String? get errorLine {
    var lineAndColumn = errorLineAndColumn;
    if (lineAndColumn != null && lineAndColumn.isNotEmpty) {
      final codeUnit = this.codeUnit;
      if (codeUnit is SourceCodeUnit) {
        var sourceCodeUnit = codeUnit as SourceCodeUnit;
        return sourceCodeUnit.getLine(lineAndColumn[0]);
      }
    }

    return null;
  }

  ParseResult(
    this.codeUnit, {
    this.root,
    this.errorMessage,
    this.errorPosition,
    this.errorLineAndColumn,
  });

  /// Returns the [errorMessage] with the error line information.
  String get errorMessageExtended {
    final errorLine = this.errorLine;

    if (errorLine != null && errorLine.isNotEmpty) {
      final errorLineAndColumn = this.errorLineAndColumn;

      if (errorLineAndColumn != null && errorLineAndColumn.length >= 2) {
        var line = errorLineAndColumn[0].toString();
        var column = errorLineAndColumn[1];

        var errorCursor = column < 0
            ? ''
            : '\n${' '.padLeft(line.length)} ${'^'.padLeft(column)}';

        return "$errorMessage @$errorPosition$errorLineAndColumn:\n$line>$errorLine$errorCursor";
      } else {
        return "$errorMessage @$errorPosition$errorLineAndColumn:\n$errorLine";
      }
    } else {
      return "$errorMessage @$errorPosition$errorLineAndColumn";
    }
  }

  @override
  String toString() {
    if (isOK) {
      return 'ParseResult[OK]: $root';
    } else {
      return 'ParseResult[ERROR]: $errorMessageExtended';
    }
  }
}

/// Syntax [Error] while parsing.
class SyntaxError extends Error {
  final String message;

  final ParseResult? parseResult;

  SyntaxError(this.message, {this.parseResult});

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
