// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:async_extension/async_extension.dart';

import 'apollovm_base.dart';
import 'apollovm_utils.dart';
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

  ApolloImportManager? importManager;

  ApolloExternalFunctionMapper? externalFunctionMapper;

  final bool importCorePackageMath;

  ApolloRunner(this.apolloVM, {this.importCorePackageMath = false}) {
    _languageNamespaces = apolloVM.getLanguageNamespaces(language);
    importManager = createDefaultApolloImportManager();
    externalFunctionMapper = createDefaultApolloExternalFunctionMapper();
  }

  /// Returns a copy of this instance.
  ApolloRunner copy();

  /// Ensures [codeUnit]'s module is resolved so its `ASTRoot.importScope`
  /// (consulted by scoped cross-module symbol resolution) is populated before
  /// execution. Recursively resolves the modules it imports as well.
  void _ensureModuleResolved(CodeUnit codeUnit) {
    var root = codeUnit.root;
    if (root == null || root.importScope != null) return;
    apolloVM.resolutionEngine.resolveModule(codeUnit.id, language: language);
  }

  ApolloImportManager? createDefaultApolloImportManager() {
    var apolloImportManager = ApolloImportManager();

    if (importCorePackageMath) {
      var ok = apolloImportManager.import('dart:math') as bool;
      if (!ok) {
        throw ApolloVMRuntimeError("Can't auto import `dart:math`");
      }
    }

    return apolloImportManager;
  }

  /// The default [ApolloExternalFunctionMapper] for this target language runner.
  ///
  /// Useful to mimic the behavior of the target language runtime.
  ApolloExternalFunctionMapper? createDefaultApolloExternalFunctionMapper() {
    var externalFunctionMapper = ApolloExternalFunctionMapper();

    // `print` accepts any value, including `null`: force the parameter generic
    // to be nullable (`Object?`) so the external call doesn't reject `null`.
    // A `parameterResolver` invokes a class instance's user-defined `toString()`
    // (if any) so `print(obj)` prints `obj.toString()` rather than the default
    // `Class{…}` representation.
    externalFunctionMapper.mapExternalFunction1<Object?, void>(
      ASTTypeVoid.instance,
      'print',
      ASTTypeObject.instance,
      'o',
      (o) => externalPrintFunction(o),
      parameterResolver: _resolvePrintArgument,
    );

    return externalFunctionMapper;
  }

  /// Resolves a `print` argument: if it is a class instance with a user-defined
  /// `toString()`, invokes it and returns the resulting String; otherwise
  /// returns the argument's plain value (the default behavior).
  static FutureOr<Object?> _resolvePrintArgument(
    ASTValue? paramVal,
    VMContext context,
  ) {
    if (paramVal is ASTClassInstance) {
      var f = paramVal.clazz.getFunction(
        'toString',
        ASTFunctionSignature.from(null, null),
        context,
      );
      if (f is ASTClassFunctionDeclaration) {
        return f
            .objectCall(context, paramVal, positionalParameters: const [])
            .resolveMapped((ret) => ret.getValue(context));
      }
    }
    return paramVal?.getValue(context);
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
  Future<ASTValue> executeClassMethod(
    String namespace,
    String className,
    String methodName, {
    List? positionalParameters,
    Map? namedParameters,
    VMObject? classInstanceObject,
    Map<String, ASTValue>? classInstanceFields,
  }) async {
    var codeNamespace = _languageNamespaces.get(namespace);

    var codeUnit = codeNamespace.getCodeUnitWithClass(className);
    if (codeUnit == null) {
      throw StateError("Can't find class to execute: $className->$methodName");
    }

    _ensureModuleResolved(codeUnit);

    var clazz = codeUnit.root!.getClass(className);
    if (clazz == null) {
      throw StateError(
        "Can't find class method to execute: $className->$methodName",
      );
    }

    var astFunctionSet = clazz.getFunctionWithName(methodName);
    if (astFunctionSet != null) {
      (positionalParameters, namedParameters) = normalizeParameters(
        positionalParameters: positionalParameters,
        namedParameters: namedParameters,
        astFunctions: astFunctionSet.functions,
      );
    }

    var result = await clazz.execute(
      methodName,
      positionalParameters,
      namedParameters,
      classInstanceObject: classInstanceObject,
      classInstanceFields: classInstanceFields,
      importManager: importManager,
      externalFunctionMapper: externalFunctionMapper,
      typeResolver: this,
    );
    return result;
  }

  (List?, Map?) normalizeParameters({
    List? positionalParameters,
    Map? namedParameters,
    List<ASTFunctionDeclaration>? astFunctions,
  }) {
    if (astFunctions != null && astFunctions.isNotEmpty) {
      final astFunction = astFunctions.resolveBestMatchBySignature(
        positionalParameters: positionalParameters,
        namedParameters: namedParameters,
      );

      if (astFunction != null) {
        (positionalParameters, namedParameters) = astFunction
            .normalizeParameters(
              positionalParameters: positionalParameters,
              namedParameters: namedParameters,
            );

        return (positionalParameters, namedParameters);
      }
    }

    positionalParameters = positionalParameters?.toListOfType();

    return (positionalParameters, namedParameters);
  }

  /// Returns an [ASTClassNormal] for [className] in [namespace] (optional).
  FutureOr<ASTClassNormal?> getClass(
    String className, {
    String? namespace,
    bool caseInsensitive = false,
  }) {
    return _languageNamespaces.getClass(
      className,
      namespace: namespace,
      caseInsensitive: caseInsensitive,
    );
  }

  /// Returns a class method.
  ///
  /// - [positionalParameters] and [namedParameters] are used to
  /// determine the method parameters signature.
  FutureOr<ASTInvocableDeclaration?> getClassMethod(
    String namespace,
    String className,
    String methodName, [
    dynamic positionalParameters,
    dynamic namedParameters,
  ]) async {
    var clazz = await getClass(className, namespace: namespace);
    if (clazz == null) return null;

    return clazz.getFunctionWithParameters(
      methodName,
      positionalParameters,
      namedParameters,
      importManager: importManager,
      externalFunctionMapper: externalFunctionMapper,
      typeResolver: this,
    );
  }

  FutureOr<({CodeUnit? codeUnit, String? className})> getFunctionCodeUnit(
    String namespace,
    String functionName, {
    bool allowClassMethod = false,
  }) {
    var codeNamespace = _languageNamespaces.get(namespace);

    var codeUnit = codeNamespace.getCodeUnitWithFunction(functionName);

    if (codeUnit == null && allowClassMethod) {
      var codeUnitWithMethod = codeNamespace.getCodeUnitWithClassMethod(
        functionName,
      );

      if (codeUnitWithMethod != null) {
        var classWithMethod = codeUnitWithMethod.root?.getClassWithMethod(
          functionName,
        );

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
  Future<ASTValue> executeFunction(
    String namespace,
    String functionName, {
    List? positionalParameters,
    Map? namedParameters,
    bool allowClassMethod = false,
  }) async {
    var r = await getFunctionCodeUnit(
      namespace,
      functionName,
      allowClassMethod: allowClassMethod,
    );

    var codeUnit = r.codeUnit;
    if (codeUnit == null) {
      throw StateError(
        "Can't find function to execute> functionName: $functionName ; language: $language",
      );
    }

    var className = r.className;
    if (className != null) {
      return executeClassMethod(
        namespace,
        className,
        functionName,
        positionalParameters: positionalParameters,
        namedParameters: namedParameters,
      );
    } else {
      _ensureModuleResolved(codeUnit);

      final astRoot = codeUnit.root!;

      var astFunctionSet = astRoot.getFunctionWithName(functionName);
      if (astFunctionSet != null) {
        (positionalParameters, namedParameters) = normalizeParameters(
          positionalParameters: positionalParameters,
          namedParameters: namedParameters,
          astFunctions: astFunctionSet.functions,
        );
      }

      var result = await astRoot.execute(
        functionName,
        positionalParameters,
        namedParameters,
        importManager: importManager,
        externalFunctionMapper: externalFunctionMapper,
        typeResolver: this,
      );

      return result;
    }
  }

  /// Returns a function in [namespace] and with name [functionName].
  ///
  /// - [positionalParameters] and [namedParameters] are used to
  /// determine the function parameters signature.
  FutureOr<ASTInvocableDeclaration?> getFunction(
    String namespace,
    String functionName, [
    List? positionalParameters,
    Map? namedParameters,
  ]) {
    var codeNamespace = _languageNamespaces.get(namespace);

    var codeUnit = codeNamespace.getCodeUnitWithFunction(functionName);
    if (codeUnit == null) return null;

    return codeUnit.root!.getFunctionWithParameters(
      functionName,
      positionalParameters,
      namedParameters,
      importManager: importManager,
      externalFunctionMapper: externalFunctionMapper,
      typeResolver: this,
    );
  }

  /// Tries to execute a function with variations of [positionalParameters].
  Future<ASTValue?> tryExecuteFunction(
    String namespace,
    String functionName, [
    List? positionalParameters,
  ]) async {
    positionalParameters ??= [];

    if (await getFunction(namespace, functionName, positionalParameters) !=
        null) {
      return await executeFunction(
        namespace,
        functionName,
        positionalParameters: positionalParameters,
      );
    } else if (await getFunction(namespace, functionName, [
          positionalParameters,
        ]) !=
        null) {
      return await executeFunction(
        namespace,
        functionName,
        positionalParameters: [positionalParameters],
      );
    } else if (await getFunction(namespace, functionName, [
          ASTTypeArray.instanceOfString,
        ]) !=
        null) {
      return await executeFunction(
        namespace,
        functionName,
        positionalParameters: [positionalParameters.map((e) => '$e').toList()],
      );
    } else if (await getFunction(namespace, functionName, [
          ASTTypeArray.instanceOfDynamic,
        ]) !=
        null) {
      return await executeFunction(
        namespace,
        functionName,
        positionalParameters: [positionalParameters],
      );
    }
    return null;
  }

  /// Tries to execute a class function with variations of [positionalParameters].
  Future<ASTValue?> tryExecuteClassFunction(
    String namespace,
    String className,
    String functionName, [
    List? positionalParameters,
  ]) async {
    positionalParameters ??= [];

    if (await getClassMethod(
          namespace,
          className,
          functionName,
          positionalParameters,
        ) !=
        null) {
      return await executeClassMethod(
        namespace,
        className,
        functionName,
        positionalParameters: positionalParameters,
      );
    } else if (await getClassMethod(namespace, className, functionName, [
          positionalParameters,
        ]) !=
        null) {
      return await executeClassMethod(
        namespace,
        className,
        functionName,
        positionalParameters: [positionalParameters],
      );
    } else if (await getClassMethod(namespace, className, functionName, [
          ASTTypeArray.instanceOfString,
        ]) !=
        null) {
      return await executeClassMethod(
        namespace,
        className,
        functionName,
        positionalParameters: [positionalParameters.map((e) => '$e').toList()],
      );
    } else if (await getClassMethod(namespace, className, functionName, [
          ASTTypeArray.instanceOfDynamic,
        ]) !=
        null) {
      return await executeClassMethod(
        namespace,
        className,
        functionName,
        positionalParameters: [positionalParameters],
      );
    }
    return null;
  }

  @override
  FutureOr<ASTType?> resolveType(
    String typeName, {
    String? namespace,
    String? language,
    bool caseInsensitive = false,
  }) {
    if (language != null) {
      if (this.language == language) {
        var ret = getClass(
          typeName,
          namespace: namespace,
          caseInsensitive: caseInsensitive,
        );

        return ret.resolveMapped(
          (clazz) =>
              clazz?.type ??
              apolloVM.resolveCoreType(
                typeName,
                namespace: namespace,
                language: language,
                caseInsensitive: caseInsensitive,
              ),
        );
      }
    }

    return apolloVM.resolveType(
      typeName,
      namespace: namespace,
      language: language,
      caseInsensitive: caseInsensitive,
    );
  }

  void reset() {
    externalFunctionMapper = createDefaultApolloExternalFunctionMapper();
  }

  @override
  String toString() {
    return 'ApolloRunner{ language: $language, apolloVM: $apolloVM }';
  }
}
