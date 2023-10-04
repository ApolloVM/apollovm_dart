// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:async_extension/async_extension.dart';

import 'apollovm_base.dart';
import 'ast/apollovm_ast_toplevel.dart';
import 'ast/apollovm_ast_type.dart';
import 'ast/apollovm_ast_value.dart';

@Deprecated("Renamed to `ApolloRunner`")
typedef ApolloLanguageRunner = ApolloRunner;

/// Base class for [ApolloVM] runners.
///
/// Implementations of this class allows the execution of an [ASTRoot]
/// in a specific [language].
abstract class ApolloRunner implements VMTypeResolver {
  /// The [ApolloVM] of this runner.
  final ApolloVM apolloVM;

  /// The target programing language of this runner.
  String get language;

  late LanguageNamespaces _languageNamespaces;

  ApolloExternalFunctionMapper? externalFunctionMapper;

  ApolloRunner(this.apolloVM) {
    _languageNamespaces = apolloVM.getLanguageNamespaces(language);
    externalFunctionMapper = createDefaultApolloExternalFunctionMapper();
  }

  /// Returns a copy of this instance.
  ApolloRunner copy();

  /// The default [ApolloExternalFunctionMapper] for this target language runner.
  ///
  /// Useful to mimic the behavior of the target language runtime.
  ApolloExternalFunctionMapper? createDefaultApolloExternalFunctionMapper() {
    var externalFunctionMapper = ApolloExternalFunctionMapper();

    externalFunctionMapper.mapExternalFunction1(ASTTypeVoid.instance, 'print',
        ASTTypeObject.instance, 'o', (o) => externalPrintFunction(o));

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
        externalFunctionMapper: externalFunctionMapper,
        typeResolver: this);
    return result;
  }

  /// Returns an [ASTClassNormal] for [className] in [namespace] (optional).
  FutureOr<ASTClassNormal?> getClass(String className,
      {String? namespace, bool caseInsensitive = false}) {
    return _languageNamespaces.getClass(className,
        namespace: namespace, caseInsensitive: caseInsensitive);
  }

  /// Returns a class method.
  ///
  /// - [positionalParameters] and [namedParameters] are used to
  /// determine the method parameters signature.
  FutureOr<ASTFunctionDeclaration?> getClassMethod(
      String namespace, String className, String methodName,
      [dynamic positionalParameters, dynamic namedParameters]) async {
    var clazz = await getClass(className, namespace: namespace);
    if (clazz == null) return null;

    return clazz.getFunctionWithParameters(
        methodName, positionalParameters, namedParameters,
        externalFunctionMapper: externalFunctionMapper, typeResolver: this);
  }

  FutureOr<({CodeUnit? codeUnit, String? className})> getFunctionCodeUnit(
      String namespace, String functionName,
      {bool allowClassMethod = false}) {
    var codeNamespace = _languageNamespaces.get(namespace);

    var codeUnit = codeNamespace.getCodeUnitWithFunction(functionName);

    if (codeUnit == null && allowClassMethod) {
      var codeUnitWithMethod =
          codeNamespace.getCodeUnitWithClassMethod(functionName);

      if (codeUnitWithMethod != null) {
        var classWithMethod =
            codeUnitWithMethod.root?.getClassWithMethod(functionName);

        if (classWithMethod != null) {
          return (
            codeUnit: codeUnitWithMethod,
            className: classWithMethod.name,
          );
        }
      }
    }

    return (codeUnit: codeUnit, className: null);
  }

  /// Executes a function in [namespace] and with name [functionName].
  ///
  /// - [positionalParameters] Positional parameters to pass to the function.
  /// - [namedParameters] Named parameters to pass to the function.
  Future<ASTValue> executeFunction(String namespace, String functionName,
      {List? positionalParameters,
      Map? namedParameters,
      bool allowClassMethod = false}) async {
    var r = await getFunctionCodeUnit(namespace, functionName,
        allowClassMethod: allowClassMethod);

    var codeUnit = r.codeUnit;
    if (codeUnit == null) {
      throw StateError(
          "Can't find function to execute> functionName: $functionName ; language: $language");
    }

    var className = r.className;
    if (className != null) {
      return executeClassMethod(namespace, className, functionName,
          positionalParameters: positionalParameters,
          namedParameters: namedParameters);
    }

    var result = await codeUnit.root!.execute(
        functionName, positionalParameters, namedParameters,
        externalFunctionMapper: externalFunctionMapper, typeResolver: this);

    return result;
  }

  /// Returns a function in [namespace] and with name [functionName].
  ///
  /// - [positionalParameters] and [namedParameters] are used to
  /// determine the function parameters signature.
  FutureOr<ASTFunctionDeclaration?> getFunction(
      String namespace, String functionName,
      [List? positionalParameters, Map? namedParameters]) async {
    var codeNamespace = _languageNamespaces.get(namespace);

    var codeUnit = codeNamespace.getCodeUnitWithFunction(functionName);
    if (codeUnit == null) return null;

    return await codeUnit.root!.getFunctionWithParameters(
        functionName, positionalParameters, namedParameters,
        externalFunctionMapper: externalFunctionMapper, typeResolver: this);
  }

  /// Tries to execute a function with variations of [positionalParameters].
  Future<ASTValue?> tryExecuteFunction(String namespace, String functionName,
      [List? positionalParameters]) async {
    positionalParameters ??= [];

    if (await getFunction(namespace, functionName, positionalParameters) !=
        null) {
      return await executeFunction(namespace, functionName,
          positionalParameters: positionalParameters);
    } else if (await getFunction(
            namespace, functionName, [positionalParameters]) !=
        null) {
      return await executeFunction(namespace, functionName,
          positionalParameters: [positionalParameters]);
    } else if (await getFunction(
            namespace, functionName, [ASTTypeArray.instanceOfString]) !=
        null) {
      return await executeFunction(namespace, functionName,
          positionalParameters: [
            positionalParameters.map((e) => '$e').toList()
          ]);
    } else if (await getFunction(
            namespace, functionName, [ASTTypeArray.instanceOfDynamic]) !=
        null) {
      return await executeFunction(namespace, functionName,
          positionalParameters: [positionalParameters]);
    }
    return null;
  }

  /// Tries to execute a class function with variations of [positionalParameters].
  Future<ASTValue?> tryExecuteClassFunction(
      String namespace, String className, String functionName,
      [List? positionalParameters]) async {
    positionalParameters ??= [];

    if (await getClassMethod(
            namespace, className, functionName, positionalParameters) !=
        null) {
      return await executeClassMethod(namespace, className, functionName,
          positionalParameters: positionalParameters);
    } else if (await getClassMethod(
            namespace, className, functionName, [positionalParameters]) !=
        null) {
      return await executeClassMethod(namespace, className, functionName,
          positionalParameters: [positionalParameters]);
    } else if (await getClassMethod(namespace, className, functionName,
            [ASTTypeArray.instanceOfString]) !=
        null) {
      return await executeClassMethod(namespace, className, functionName,
          positionalParameters: [
            positionalParameters.map((e) => '$e').toList()
          ]);
    } else if (await getClassMethod(namespace, className, functionName,
            [ASTTypeArray.instanceOfDynamic]) !=
        null) {
      return await executeClassMethod(namespace, className, functionName,
          positionalParameters: [positionalParameters]);
    }
    return null;
  }

  @override
  FutureOr<ASTType?> resolveType(String typeName,
      {String? namespace, String? language, bool caseInsensitive = false}) {
    if (language != null) {
      if (this.language == language) {
        var ret = getClass(typeName,
            namespace: namespace, caseInsensitive: caseInsensitive);

        return ret.resolveMapped((clazz) =>
            clazz?.type ??
            apolloVM.resolveCoreType(typeName,
                namespace: namespace,
                language: language,
                caseInsensitive: caseInsensitive));
      }
    }

    return apolloVM.resolveType(typeName,
        namespace: namespace,
        language: language,
        caseInsensitive: caseInsensitive);
  }

  void reset() {
    externalFunctionMapper = createDefaultApolloExternalFunctionMapper();
  }

  @override
  String toString() {
    return 'ApolloRunner{ language: $language, apolloVM: $apolloVM }';
  }
}
