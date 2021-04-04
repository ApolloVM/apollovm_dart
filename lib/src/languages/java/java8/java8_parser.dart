import 'package:apollovm/src/apollovm_base.dart';
import 'package:apollovm/src/apollovm_parser.dart';
import 'package:apollovm/src/apollovm_runner.dart';

import 'java8_grammar.dart';

class ApolloParserJava8 extends ApolloParser {
  static final ApolloParserJava8 INSTANCE = ApolloParserJava8();

  ApolloParserJava8() : super(Java8Grammar());

  @override
  String get language => 'java8';
}

class ApolloRunnerJava8 extends ApolloLanguageRunner {
  ApolloRunnerJava8(ApolloVM apolloVM) : super(apolloVM);

  @override
  String get language => 'java8';

  @override
  ApolloRunnerJava8 copy() {
    return ApolloRunnerJava8(apolloVM);
  }
}
