import 'dart:async';

import 'apollovm_base.dart';
import 'ast/apollovm_ast_toplevel.dart';
import 'ast/apollovm_ast_type.dart';
import 'ast/apollovm_ast_value.dart';

abstract class ApolloLanguageRunner {
  final ApolloVM apolloVM;

  String get language;

  late LanguageNamespaces _languageNamespaces;

  ApolloExternalFunctionMapper? externalFunctionMapper;

  ApolloLanguageRunner(this.apolloVM) {
    _languageNamespaces = apolloVM.getLanguageNamespaces(language);
    externalFunctionMapper = createDefaultApolloExternalFunctionMapper();
  }

  ApolloLanguageRunner copy();

  ApolloExternalFunctionMapper? createDefaultApolloExternalFunctionMapper() {
    var externalFunctionMapper = ApolloExternalFunctionMapper();

    externalFunctionMapper.mapExternalFunction1(ASTTypeVoid.INSTANCE, 'print',
        ASTTypeObject.INSTANCE, 'o', (o) => externalPrintFunction(o));

    return externalFunctionMapper;
  }

  void Function(Object? o) externalPrintFunction = print;

  FutureOr<ASTValue> executeClassMethod(
      String namespace, String className, String methodName,
      [dynamic? positionalParameters, dynamic? namedParameters]) async {
    var codeNamespace = _languageNamespaces.get(namespace);

    var codeUnit = codeNamespace.getCodeUnitWithClass(className);
    if (codeUnit == null) {
      throw StateError("Can't find class to execute: $className->$methodName");
    }

    var clazz = codeUnit.root!.getClass(className);
    if (clazz == null) {
      throw StateError(
          "Can't find class method to execute: $className->$methodName");
    }

    var result = await clazz.execute(
        methodName, positionalParameters, namedParameters,
        externalFunctionMapper: externalFunctionMapper);
    return result;
  }

  FutureOr<ASTClass?> getClass(String namespace, String className) async {
    var codeNamespace = _languageNamespaces.get(namespace);

    var codeUnit = codeNamespace.getCodeUnitWithClass(className);
    if (codeUnit == null) return null;

    var clazz = codeUnit.root!.getClass(className);
    return clazz;
  }

  FutureOr<ASTFunctionDeclaration?> getClassMethod(
      String namespace, String className, String methodName,
      [dynamic? positionalParameters, dynamic? namedParameters]) async {
    var clazz = await getClass(namespace, className);
    if (clazz == null) return null;

    return clazz.getFunctionWithParameters(
        methodName, positionalParameters, namedParameters,
        externalFunctionMapper: externalFunctionMapper);
  }

  FutureOr<ASTValue> executeFunction(String namespace, String functionName,
      [dynamic? positionalParameters, dynamic? namedParameters]) async {
    var codeNamespace = _languageNamespaces.get(namespace);

    var codeUnit = codeNamespace.getCodeUnitWithFunction(functionName);
    if (codeUnit == null) {
      throw StateError("Can't find function to execute: $functionName");
    }

    var result = await codeUnit.root!.execute(
        functionName, positionalParameters, namedParameters,
        externalFunctionMapper: externalFunctionMapper);

    return result;
  }

  FutureOr<ASTFunctionDeclaration?> getFunction(
      String namespace, String functionName,
      [dynamic? positionalParameters, dynamic? namedParameters]) async {
    var codeNamespace = _languageNamespaces.get(namespace);

    var codeUnit = codeNamespace.getCodeUnitWithFunction(functionName);
    if (codeUnit == null) return null;

    return await codeUnit.root!.getFunctionWithParameters(
        functionName, positionalParameters, namedParameters,
        externalFunctionMapper: externalFunctionMapper);
  }

  void reset() {
    externalFunctionMapper = createDefaultApolloExternalFunctionMapper();
  }
}
