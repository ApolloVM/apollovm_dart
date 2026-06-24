// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import '../../apollovm_parser.dart';
import 'kotlin_grammar.dart';

/// Kotlin implementation of an [ApolloParser].
class ApolloParserKotlin extends ApolloSourceCodeParser {
  static final ApolloParserKotlin instance = ApolloParserKotlin();

  ApolloParserKotlin() : super(KotlinGrammarDefinition());

  @override
  String get language => 'kotlin';

  @override
  bool acceptsLanguage(String language) {
    language = language.toLowerCase().trim();

    if (this.language == language || language == 'kt') {
      return true;
    }

    return false;
  }
}
