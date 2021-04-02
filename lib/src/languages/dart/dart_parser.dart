import 'package:apollovm/src/apollovm_ast.dart';
import 'package:apollovm/src/apollovm_parser.dart';

import 'dart_grammar.dart';

class ApolloParserDart extends ApolloParser {
  final DartGrammar _grammar = DartGrammar();

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
