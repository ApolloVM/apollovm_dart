import 'package:apollovm/apollovm.dart';
import 'package:apollovm/src/apollovm_code_generator.dart';
import 'package:apollovm/src/apollovm_code_storage.dart';
import 'package:apollovm/src/apollovm_runner.dart';
import 'package:apollovm/src/languages/dart/dart_generator.dart';
import 'package:apollovm/src/languages/java/java8/java8_generator.dart';

class ApolloVM {
  ApolloParser? getParser(String language) {
    switch (language) {
      case 'dart':
        return ApolloParserDart.INSTANCE;
      case 'java8':
        return ApolloParserJava8.INSTANCE;
      default:
        return null;
    }
  }

  final Map<String, LanguageNamespaces> _languageNamespaces =
      <String, LanguageNamespaces>{};

  CodeNamespace? getNamespace(String language, String namespace) {
    var langNamespaces = getLanguageNamespaces(language);
    return langNamespaces.get(namespace);
  }

  LanguageNamespaces getLanguageNamespaces(String language) {
    return _languageNamespaces.putIfAbsent(
        language, () => LanguageNamespaces(language));
  }

  Future<bool> loadCodeUnit(CodeUnit codeUnit) async {
    var language = codeUnit.language;
    var parser = getParser(language);

    if (parser == null) return false;

    var result = await parser.parse(codeUnit);

    if (!result.isOK) return false;

    var root = result.root!;

    var langNamespaces = getLanguageNamespaces(language);

    var codeNamespace = langNamespaces.get(root.namespace);

    codeUnit.codeRoot = root;

    codeNamespace.addCodeUnit(codeUnit);

    return true;
  }

  ApolloLanguageRunner? createRunner(String language) {
    switch (language) {
      case 'dart':
        return ApolloRunnerDart(this);
      case 'java8':
        return ApolloRunnerJava8(this);
      default:
        return null;
    }
  }

  void generateAllCode(ApolloCodeGenerator codeGenerator) {
    for (var languageNamespace in _languageNamespaces.values) {
      languageNamespace.generateAllCode(codeGenerator);
    }
  }

  ApolloCodeGenerator? createCodeGenerator(
      String language, ApolloCodeStorage codeStorage) {
    switch (language) {
      case 'dart':
        return ApolloCodeGeneratorDart(codeStorage);
      case 'java8':
        return ApolloCodeGeneratorJava8(codeStorage);
      default:
        return null;
    }
  }

  ApolloCodeStorage generateAllCodeIn(String language,
      {ApolloCodeStorage? codeStorage}) {
    codeStorage ??= ApolloCodeStorageMemory();
    var codeGenerator = createCodeGenerator(language, codeStorage);
    if (codeGenerator == null) {
      throw StateError(
          "Can't find an ApolloCodeGenerator for language: $language");
    }
    generateAllCode(codeGenerator);
    return codeStorage;
  }
}

class LanguageNamespaces {
  final String language;

  LanguageNamespaces(this.language);

  final Map<String, CodeNamespace> _namespaces = <String, CodeNamespace>{};

  CodeNamespace get(String namespace) => _namespaces.putIfAbsent(
      namespace, () => CodeNamespace(language, namespace));

  void generateAllCode(ApolloCodeGenerator codeGenerator) {
    for (var namespace in _namespaces.values) {
      namespace.generateAllCode(codeGenerator);
    }
  }
}

class CodeNamespace {
  final String language;
  final String name;

  CodeNamespace(this.language, this.name);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CodeNamespace &&
          runtimeType == other.runtimeType &&
          language == other.language &&
          name == other.name;

  @override
  int get hashCode => language.hashCode ^ name.hashCode;

  final Set<CodeUnit> _codeUnits = {};

  void addCodeUnit(CodeUnit codeUnit) {
    _codeUnits.add(codeUnit);
  }

  CodeUnit? getCodeUnitWithClass(String className) {
    for (var cu in _codeUnits) {
      var clazz = cu.codeRoot!.getClass(className);
      if (clazz != null) return cu;
    }
    return null;
  }

  ASTCodeClass? getClass(String className) {
    for (var cu in _codeUnits) {
      var clazz = cu.codeRoot!.getClass(className);
      if (clazz != null) return clazz;
    }
    return null;
  }

  CodeUnit? getCodeUnitWithFunction(String fName) {
    for (var cu in _codeUnits) {
      if (cu.codeRoot!.containsFunctionWithName(fName)) return cu;
    }
    return null;
  }

  ASTFunctionDeclaration? getFunction(String fName,
      ASTFunctionSignature parametersSignature, VMContext context) {
    for (var cu in _codeUnits) {
      var f = cu.codeRoot!.getFunction(fName, parametersSignature, context);
      if (f != null) return f;
    }
    return null;
  }

  void generateAllCode(ApolloCodeGenerator codeGenerator) {
    var codeStorage = codeGenerator.codeStorage;
    for (var cu in _codeUnits) {
      var cuSource = cu.generateCode(codeGenerator);
      codeStorage.addSource(name, cu.id, cuSource.toString());
    }
  }
}

class CodeUnit {
  final String language;
  final String source;
  final String id;

  CodeUnit(this.language, this.source, [this.id = '']);

  ASTCodeRoot? codeRoot;

  @override
  String toString() {
    return 'CodeUnit{language: $language, path: $id}';
  }

  StringBuffer generateCode(ApolloCodeGenerator codeGenerator) {
    if (codeRoot == null) {
      throw StateError(
          'No ASTCodeRoot! Ensure that this CodeUnit is loaded by ApolloVM!');
    }
    return codeGenerator.generateASTCodeRoot(codeRoot!);
  }
}

class ApolloExternalFunctionMapper {
  final Map<String, ASTCodeFunctionSet> _functions = {};

  ASTExternalFunction<R>? getMappedFunction<R>(VMContext context, String fName,
      [ASTFunctionSignature? parametersSignature]) {
    var fSet = _functions[fName];
    if (fSet == null) return null;

    if (parametersSignature != null) {
      return fSet.get(parametersSignature, false) as ASTExternalFunction<R>;
    } else {
      return fSet.firstFunction as ASTExternalFunction<R>;
    }
  }

  void addExternalFunction(ASTExternalFunction fExternal) {
    var fName = fExternal.name;
    var fSet = _functions[fName];

    if (fSet == null) {
      _functions[fName] = ASTCodeFunctionSetSingle(fExternal);
    } else {
      _functions[fName] = fSet.add(fExternal);
    }
  }

  void mapExternalFunction0<T, R>(
      ASTType<R> fReturn, String fName, Function() f) {
    var fParameters = ASTParametersDeclaration(null, null, null);

    var fExternal = ASTExternalFunction(fName, fParameters, fReturn, f);

    addExternalFunction(fExternal);
  }

  void mapExternalFunction1<T, R>(ASTType<R> fReturn, String fName,
      ASTType<T> pType1, String pName1, Function(T p1) f) {
    var fParameters = ASTParametersDeclaration(
        [ASTFunctionParameterDeclaration(pType1, pName1, 0, false)],
        null,
        null);

    var fExternal = ASTExternalFunction(fName, fParameters, fReturn, f);

    addExternalFunction(fExternal);
  }

  void mapExternalFunction2<A, B, R>(
      ASTType<R> fReturn,
      String fName,
      ASTType<A> pType1,
      String pName1,
      ASTType<B> pType2,
      String pName2,
      Function(A p1, B p2) f) {
    var fParameters = ASTParametersDeclaration([
      ASTFunctionParameterDeclaration(pType1, pName1, 0, false),
      ASTFunctionParameterDeclaration(pType2, pName2, 1, false),
    ], null, null);

    var fExternal = ASTExternalFunction(fName, fParameters, fReturn, f);

    addExternalFunction(fExternal);
  }

  void mapExternalFunction3<A, B, C, R>(
      ASTType<R> fReturn,
      String fName,
      ASTType<A> pType1,
      String pName1,
      ASTType<B> pType2,
      String pName2,
      ASTType<B> pType3,
      String pName3,
      Function(A p1, B p2) f) {
    var fParameters = ASTParametersDeclaration([
      ASTFunctionParameterDeclaration(pType1, pName1, 0, false),
      ASTFunctionParameterDeclaration(pType2, pName2, 1, false),
      ASTFunctionParameterDeclaration(pType3, pName3, 1, false),
    ], null, null);

    var fExternal = ASTExternalFunction(fName, fParameters, fReturn, f);

    addExternalFunction(fExternal);
  }

  void mapExternalFunction4<A, B, C, D, R>(
      ASTType<R> fReturn,
      String fName,
      ASTType<A> pType1,
      String pName1,
      ASTType<B> pType2,
      String pName2,
      ASTType<B> pType3,
      String pName3,
      ASTType<B> pType4,
      String pName4,
      Function(A p1, B p2) f) {
    var fParameters = ASTParametersDeclaration([
      ASTFunctionParameterDeclaration(pType1, pName1, 0, false),
      ASTFunctionParameterDeclaration(pType2, pName2, 1, false),
      ASTFunctionParameterDeclaration(pType3, pName3, 1, false),
      ASTFunctionParameterDeclaration(pType4, pName4, 1, false),
    ], null, null);

    var fExternal = ASTExternalFunction(fName, fParameters, fReturn, f);

    addExternalFunction(fExternal);
  }
}

class VMContext {
  final VMContext? parent;
  final ASTCodeBlock block;
  final ASTObjectInstance? objectInstance;

  final ExternalFunctionSet? externalFunctionSet;

  VMContext(this.block,
      {this.parent, this.objectInstance, this.externalFunctionSet});

  final Map<String, ASTTypedVariable> _variables = {};

  ASTVariable? getVariable(String name, bool allowField) {
    var variable = _variables[name];
    if (variable != null) return variable;
    if (allowField) {
      var field = block.getField(name);
      return field;
    }
    return parent?.getVariable(name, allowField);
  }

  bool setVariable(String name, ASTValue value, bool allowField) {
    var variable = _variables[name];
    if (variable != null) {
      variable.setValue(this, value);
      return true;
    }
    var field = block.getField(name);

    if (field != null) {
      field.setValue(this, value);
      return true;
    }

    return false;
  }

  bool declareVariableWithValue(ASTType type, String name, ASTValue? value) {
    value ??= ASTValueNull.INSTANCE;
    var variable = ASTRuntimeVariable(type, name, value);
    return declareVariable(variable);
  }

  bool declareVariable(ASTTypedVariable variable) {
    var name = variable.name;
    if (_variables.containsKey(name)) {
      throw StateError("Variable '$name' already declared: $variable");
    }
    _variables[name] = variable;
    return false;
  }

  ASTVariable? getField(String name) {
    return block.getField(name);
  }

  ASTObjectInstance? getASTObjectInstance() {
    if (objectInstance != null) {
      return objectInstance!;
    }
    return parent?.getASTObjectInstance();
  }

  ExternalFunctionSet? getExternalFunctionSet() {
    if (externalFunctionSet != null) {
      return externalFunctionSet;
    }

    if (parent != null) {
      return parent!.getExternalFunctionSet();
    }

    return null;
  }

  ASTFunctionDeclaration? getFunction(
    String name,
    ASTFunctionSignature parametersSignature, [
    VMContext? context,
  ]) {
    var f = block.getFunction(name, parametersSignature, this);
    if (f != null) return f;
    return parent?.getFunction(name, parametersSignature);
  }

  ApolloExternalFunctionMapper? externalFunctionMapper;

  ASTExternalFunction<R>? getMappedExternalFunction<R>(String fName,
      [ASTFunctionSignature? parametersSignature]) {
    if (externalFunctionMapper != null) {
      var f = externalFunctionMapper!
          .getMappedFunction(this, fName, parametersSignature);
      if (f != null) return f as ASTExternalFunction<R>;
    }

    if (parent != null) {
      return parent!.getMappedExternalFunction(fName, parametersSignature);
    }
  }
}
