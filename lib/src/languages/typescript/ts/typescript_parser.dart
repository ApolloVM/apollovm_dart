// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import '../../../apollovm_parser.dart';
import 'typescript_grammar.dart';

/// TypeScript implementation of an [ApolloParser].
class ApolloParserTypeScript extends ApolloSourceCodeParser {
  static final ApolloParserTypeScript instance = ApolloParserTypeScript();

  ApolloParserTypeScript() : super(TypeScriptGrammarDefinition());

  @override
  String get language => 'typescript';

  @override
  bool acceptsLanguage(String language) {
    language = language.toLowerCase().trim();

    if (this.language == language || language == 'ts') {
      return true;
    }

    return false;
  }
}
