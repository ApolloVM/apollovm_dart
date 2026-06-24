// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import '../../../apollovm_parser.dart';
import 'javascript_grammar.dart';

/// JavaScript (modern ES) implementation of an [ApolloParser].
class ApolloParserJavaScript extends ApolloSourceCodeParser {
  static final ApolloParserJavaScript instance = ApolloParserJavaScript();

  ApolloParserJavaScript() : super(JavaScriptGrammarDefinition());

  @override
  String get language => 'javascript';

  @override
  bool acceptsLanguage(String language) {
    language = language.toLowerCase().trim();

    if (this.language == language || language == 'js') {
      return true;
    }

    return false;
  }
}
