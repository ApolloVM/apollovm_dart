import 'dart:async';

import 'apollovm_base.dart';
import 'ast/apollovm_ast_toplevel.dart';
import 'ast/apollovm_ast_type.dart';
import 'ast/apollovm_ast_value.dart';

/// Base class for [ApolloVM] runners.
///
/// Implementations of this class allows the execution of an [ASTRoot]
/// in a specific [language].
abstract class ApolloLanguageRunner {
  /// The [ApolloVM] of this runner.
  final ApolloVM apolloVM;

  /// The target programing language of this runner.
  String get language;

  late LanguageNamespaces _languageNamespaces;

  ApolloExternalFunctionMapper? externalFunctionMapper;

  ApolloLanguageRunner(this.apolloVM) {
    _languageNamespaces = apolloVM.getLanguageNamespaces(language);
    externalFunctionMapper = createDefaultApolloExternalFunctionMapper();
  }

  /// Returns a copy of this instance.
  ApolloLanguageRunner copy();

  /// The default [ApolloExternalFunctionMapper] for this target language runner.
  ///
  /// Useful to mimic the behavior of the target language runtime.
  ApolloExternalFunctionMapper? createDefaultApolloExternalFunctionMapper() {
    var externalFunctionMapper = ApolloExternalFunctionMapper();

    externalFunctionMapper.mapExternalFunction1(ASTTypeVoid.INSTANCE, 'print',
        ASTTypeObject.INSTANCE, 'o', (o) => externalPrintFunction(o));

    return externalFunctionMapper;
  }

  /// The external [print] function to map.
  ///
  /// Can be overwritten by any kind of function.
  void Function(Object? o) externalPrintFunction = print;

  /// Executes a class method.
  ///
  /// - [namespace] Namespace/package of the target class.
  /// - [className] Name of the target class.
  /// - [methodName] Name of the target method.
  /// - [positionalParameters] Positional parameters to pass to the method.
  /// - [namedParameters] Named parameters to pass to the method.
  FutureOr<ASTValue> executeClassMethod(
      String namespace, String className, String methodName,
      {List? positionalParameters,
      Map? namedParameters,
      VMObject? classInstanceObject,
      Map<String, ASTValue>? classInstanceFields}) async {
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
        classInstanceObject: classInstanceObject,
        classInstanceFields: classInstanceFields,
        externalFunctionMapper: externalFunctionMapper);
    return result;
  }

  /// Returns an [ASTClass] in [namespace] and with name [className].
  FutureOr<ASTClass?> getClass(String namespace, String className) async {
    var codeNamespace = _languageNamespaces.get(namespace);

    var codeUnit = codeNamespace.getCodeUnitWithClass(className);
    if (codeUnit == null) return null;

    var clazz = codeUnit.root!.getClass(className);
    return clazz;
  }

  /// Returns a class method.
  ///
  /// - [positionalParameters] and [namedParameters] are used to
  /// determine the method parameters signature.
  FutureOr<ASTFunctionDeclaration?> getClassMethod(
      String namespace, String className, String methodName,
      [dynamic? positionalParameters, dynamic? namedParameters]) async {
    var clazz = await getClass(namespace, className);
    if (clazz == null) return null;

    return clazz.getFunctionWithParameters(
        methodName, positionalParameters, namedParameters,
        externalFunctionMapper: externalFunctionMapper);
  }

  /// Executes a function in [namespace] and with name [functionName].
  ///
  /// - [positionalParameters] Positional parameters to pass to the function.
  /// - [namedParameters] Named parameters to pass to the function.
  FutureOr<ASTValue> executeFunction(String namespace, String functionName,
      {List? positionalParameters, Map? namedParameters}) async {
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

  /// Returns a function in [namespace] and with name [functionName].
  ///
  /// - [positionalParameters] and [namedParameters] are used to
  /// determine the function parameters signature.
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
