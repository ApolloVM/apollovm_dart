// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import '../../apollovm_parser.dart';
import 'apollo_grammar.dart';

/// Apollo implementation of an [ApolloParser].
class ApolloParserApollo extends ApolloSourceCodeParser {
  static final ApolloParserApollo instance = ApolloParserApollo();

  ApolloParserApollo() : super(ApolloGrammarDefinition());

  @override
  String get language => 'apollo';

  /// Report parse errors at the farthest point the grammar reached, close to
  /// the real syntax error, instead of a generic top-level failure at offset 0.
  @override
  bool get trackFarthestFailure => true;
}
