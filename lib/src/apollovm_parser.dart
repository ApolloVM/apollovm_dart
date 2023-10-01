// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:petitparser/petitparser.dart';
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
          "This parser is for the language '$language'. Trying to parse a CodeUnit of language: '${codeUnit.language}'");
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

  /// Parses a [codeUnit] to an [ASTRoot] and returns a [ParseResult].
  ///
  /// If some error occurs, returns a [ParseResult] with an error message.
  @override
  Future<ParseResult<String>> parse(CodeUnit<String> codeUnit) async {
    check(codeUnit);

    var result = _grammarParser.parse(codeUnit.code);

    if (result is! Success) {
      var lineAndColumn = result
          .toPositionString()
          .split(':')
          .map((e) => parseInt(e)!)
          .toList();

      return ParseResult(codeUnit,
          errorMessage: result.message,
          errorPosition: result.position,
          errorLineAndColumn: lineAndColumn);
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

  ParseResult(this.codeUnit,
      {this.root,
      this.errorMessage,
      this.errorPosition,
      this.errorLineAndColumn});

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
