import 'package:apollovm/apollovm.dart';
import 'package:apollovm/src/apollovm_base.dart';
import 'package:apollovm/src/apollovm_parser.dart';
import 'package:apollovm/src/apollovm_runner.dart';

import 'dart_grammar.dart';

class ApolloParserDart extends ApolloParser {
  static final ApolloParserDart INSTANCE = ApolloParserDart();

  ApolloParserDart() : super(DartGrammar());

  @override
  String get language => 'dart';
}

class ApolloRunnerDart extends ApolloLanguageRunner {
  ApolloRunnerDart(ApolloVM apolloVM) : super(apolloVM);

  @override
  String get language => 'dart';

  @override
  ApolloRunnerDart copy() {
    return ApolloRunnerDart(apolloVM);
  }
}
