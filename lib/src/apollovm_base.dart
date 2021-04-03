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

  final Map<String, ApolloLanguageRunner> _languageRunners =
      <String, ApolloLanguageRunner>{};

  ApolloLanguageRunner? getRunner(String language) {
    language = language.toLowerCase().trim();

    var runner = _languageRunners[language];
    if (runner == null) {
      runner = _getRunnerImpl(language);
      if (runner != null) {
        _languageRunners[language] = runner;
      }
    }
    return runner;
  }

  ApolloLanguageRunner? _getRunnerImpl(String language) {
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
      ASTFunctionSignature parametersSignature, ASTContext context) {
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
