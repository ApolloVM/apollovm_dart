import 'package:apollovm/src/apollovm_ast.dart';
import 'package:apollovm/src/apollovm_parser.dart';

import 'java8_grammar.dart';

class ApolloParserJava8 extends ApolloParser {
  final Java8Grammar _grammar = Java8Grammar();

  @override
  Future<ASTCodeRoot?> parse(String source) async {
    var result = _grammar.parse(source);

    if (!result.isSuccess) {
      print('!!! ${result.message}');
      return null;
    }

    return result.value;
  }
}
