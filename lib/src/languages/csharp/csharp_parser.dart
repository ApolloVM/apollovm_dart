// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import '../../apollovm_parser.dart';
import 'csharp_grammar.dart';

/// C# implementation of an [ApolloParser].
class ApolloParserCSharp extends ApolloSourceCodeParser {
  static final ApolloParserCSharp instance = ApolloParserCSharp();

  ApolloParserCSharp() : super(CSharpGrammarDefinition());

  @override
  String get language => 'csharp';

  /// Report parse errors at the farthest point the grammar reached, close to
  /// the real syntax error, instead of a generic top-level failure at offset 0.
  @override
  bool get trackFarthestFailure => true;

  @override
  bool acceptsLanguage(String language) {
    language = language.toLowerCase().trim();

    if (this.language == language || language == 'c#' || language == 'cs') {
      return true;
    }

    return false;
  }
}
