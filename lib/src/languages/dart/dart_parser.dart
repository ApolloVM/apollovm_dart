import '../../apollovm_base.dart';
import '../../apollovm_parser.dart';
import '../../apollovm_runner.dart';
import 'dart_grammar.dart';

/// Dart implementation of an [ApolloParser].
class ApolloParserDart extends ApolloParser {
  static final ApolloParserDart instance = ApolloParserDart();

  ApolloParserDart() : super(DartGrammarDefinition());

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
