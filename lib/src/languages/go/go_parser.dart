// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import '../../apollovm_parser.dart';
import 'go_grammar.dart';

/// Go implementation of an [ApolloParser].
class ApolloParserGo extends ApolloSourceCodeParser {
  static final ApolloParserGo instance = ApolloParserGo();

  ApolloParserGo() : super(GoGrammarDefinition());

  @override
  String get language => 'go';

  /// Report parse errors at the farthest point the grammar reached, close to
  /// the real syntax error, instead of a generic top-level failure at offset 0.
  @override
  bool get trackFarthestFailure => true;

  @override
  bool acceptsLanguage(String language) {
    language = language.toLowerCase().trim();

    if (this.language == language || language == 'golang') {
      return true;
    }

    return false;
  }
}
