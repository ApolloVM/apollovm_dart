import 'package:apollovm/apollovm.dart';

abstract class ApolloLanguageRunner {
  final ApolloVM apolloVM;

  String get language;

  late LanguageNamespaces _languageNamespaces;

  ApolloLanguageRunner(this.apolloVM) {
    _languageNamespaces = apolloVM.getLanguageNamespaces(language);
  }

  ASTValue executeClassMethod(String namespace, String className,
      String methodName, dynamic? positionalParameters,
      [dynamic? namedParameters]) {
    var codeNamespace = _languageNamespaces.get(namespace);

    var codeUnit = codeNamespace.getCodeUnitWithClass(className);
    if (codeUnit == null) {
      throw StateError("Can't find class to execute: $className->$methodName");
    }

    var clazz = codeUnit.codeRoot!.getClass(className);
    if (clazz == null) {
      throw StateError(
          "Can't find class method to execute: $className->$methodName");
    }

    var result =
        clazz.execute(methodName, positionalParameters, namedParameters);
    return result;
  }

  ASTValue executeFunction(
      String namespace, String functionName, dynamic? positionalParameters,
      [dynamic? namedParameters]) {
    var codeNamespace = _languageNamespaces.get(namespace);

    var codeUnit = codeNamespace.getCodeUnitWithFunction(functionName);
    if (codeUnit == null) {
      throw StateError("Can't find function to execute: $functionName");
    }

    var result = codeUnit.codeRoot!
        .execute(functionName, positionalParameters, namedParameters);
    return result;
  }
}
