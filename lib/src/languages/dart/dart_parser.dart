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

  /// Report parse errors at the farthest point the grammar reached, close to
  /// the real syntax error, instead of a generic top-level failure at offset 0.
  @override
  bool get trackFarthestFailure => true;
}
