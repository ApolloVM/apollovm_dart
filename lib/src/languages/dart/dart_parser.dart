// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import '../../apollovm_parser.dart';
import 'dart_grammar.dart';

/// Dart implementation of an [ApolloParser].
class ApolloParserDart extends ApolloSourceCodeParser {
  static final ApolloParserDart instance = ApolloParserDart();

  ApolloParserDart() : super(DartGrammarDefinition());

  @override
  String get language => 'dart';
}
