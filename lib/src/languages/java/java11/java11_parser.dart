// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import '../../../apollovm_parser.dart';
import 'java11_grammar.dart';

/// Java11 implementation of an [ApolloParser].
class ApolloParserJava11 extends ApolloSourceCodeParser {
  static final ApolloParserJava11 instance = ApolloParserJava11();

  ApolloParserJava11() : super(Java11GrammarDefinition());

  @override
  String get language => 'java11';

  /// Report parse errors at the farthest point the grammar reached, close to
  /// the real syntax error, instead of a generic top-level failure at offset 0.
  @override
  bool get trackFarthestFailure => true;

  @override
  bool acceptsLanguage(String language) {
    language = language.toLowerCase().trim();

    if (this.language == language || language == 'java') {
      return true;
    }

    return false;
  }
}
