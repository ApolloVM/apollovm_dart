import 'dart:convert';
import 'dart:io';

import 'package:apollovm/apollovm.dart';
import 'package:collection/collection.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

class TestDefinition implements Comparable<TestDefinition> {
  String fileName;

  String fileContent;

  late final XmlDocument xml;

  TestDefinition(this.fileName, this.fileContent) {
    xml = XmlDocument.parse(fileContent);
  }

  XmlElement get rootElement => xml.rootElement;

  String get title => rootElement.getAttribute('title')!;

  XmlElement get source => rootElement.findElements('source').first;

  String get language => source.getAttribute('language')!;

  String get sourceCode => source.text;

  List<XmlElement> get calls => rootElement.findElements('call').toList();

  List<XmlElement> get outputs => rootElement.findElements('output').toList();

  List<XmlElement> get sourcesGenerated =>
      rootElement.findElements('source-generated').toList();

  @override
  int compareTo(TestDefinition other) {
    return fileName.compareTo(other.fileName);
  }
}

Future<void> main() async {
  var definitionsDirectory = Directory('./test/tests_definitions');

  print('TESTS DEFINITIONS DIRECTORY: $definitionsDirectory');

  var envVars = Platform.environment;
  var singleTest = envVars['SINGLE_TEST'];

  if (singleTest != null) {
    print('SINGLE_TEST: $singleTest');
  }

  var definitions = await definitionsDirectory
      .list()
      .where((f) => f.path.endsWith('.xml'))
      .where((f) => singleTest == null || f.path.endsWith('/$singleTest'))
      .map((f) => File(f.path))
      .map((f) => TestDefinition(f.path, f.readAsStringSync()))
      .toList();

  definitions.sort();

  var definitionsByGroup =
      groupBy<TestDefinition, String>(definitions, (e) => e.language);

  print('FOUND TESTS DEFINITIONS: ${definitions.length}');

  for (var f in definitions) {
    print('- ${f.fileName}');
  }

  group('Pre Test', () {
    test('_parseJsonList', () async {
      expect(_parseJsonList('["a","b"]') is List<String>, isTrue);
      expect(_parseJsonList('["a","b"]') is List<int>, isFalse);

      expect(_parseJsonList('[1,2,3]') is List<int>, isTrue);
      expect(_parseJsonList('[1,2,3]') is List<String>, isFalse);

      expect(_parseJsonList('[1.1, 2.2, 3.3]') is List<double>, isTrue);
      expect(_parseJsonList('[1.1, 2.2, 3.3]') is List<int>, isFalse);

      expect(_parseJsonList('[ [1,2] , [3,4] ]') is List<List<int>>, isTrue);

      expect(
          _parseJsonList('[ [ [1,2] ] , [ [3,4] ] ]') is List<List<List<int>>>,
          isTrue);

      expect(
          _parseJsonList('[ [ [ [1,2] ] ] , [ [ [3,4] ] ] ]')
              is List<List<List<List<int>>>>,
          isTrue);
    });
  });

  for (var lang in definitionsByGroup.keys) {
    var langDefinitions = definitionsByGroup[lang]!;

    group(lang, () {
      for (var testDefinition in langDefinitions) {
        test(testDefinition.title, () async {
          print(
              '\n======================================================================\n');

          var language = testDefinition.language;
          var sourcesGenerated = testDefinition.sourcesGenerated;

          print('FILE: ${testDefinition.fileName}');
          print('');

          print('TEST: ${testDefinition.title}');

          print('  - language: $language ');
          print('  - sourcesGenerated: ${sourcesGenerated.length}');
          print('');
          print('SOURCE:');
          print(testDefinition.sourceCode);
          print('');

          var vm = ApolloVM();

          var codeUnit = CodeUnit(language, testDefinition.sourceCode, 'test');

          print('-- Loading source code');
          var loadOK = await vm.loadCodeUnit(codeUnit);

          expect(loadOK, isTrue, reason: "Error loading '$language ' code!");

          var runner = vm.createRunner(language)!;

          var calls = testDefinition.calls;
          var outputs = testDefinition.outputs;

          for (var i = 0; i < calls.length; ++i) {
            var call = calls[i];
            var output = outputs[i];
            var outputJson = _resolveLanguageOutput(output, language);
            await _testCall(call, i, outputJson, runner);
          }

          for (var sourceGen in sourcesGenerated) {
            print('---------------------------------------');
            var sourceGenLanguage = sourceGen.getAttribute('language')!;

            print(
                '-- Checking code generation for language: $sourceGenLanguage');

            var codeStorage = vm.generateAllCodeIn(sourceGenLanguage);
            var allSources = codeStorage.writeAllSources().toString();
            print(allSources);

            expect(allSources, equals(sourceGen.text));

            {
              print('.......................................');

              var vmCodeGen = ApolloVM();
              print('-- Testing generated code in VM: $vmCodeGen');

              for (var ns in codeStorage.getNamespaces()) {
                for (var id in codeStorage.getNamespaceCodeUnitsIDs(ns) ?? []) {
                  var source = codeStorage.getNamespaceCodeUnitSource(ns, id)!;
                  var cu = CodeUnit(sourceGenLanguage, source, id);

                  print('-- Loading generated code: $cu');
                  var ok = await vmCodeGen.loadCodeUnit(cu);
                  print(cu.source);
                  expect(ok, isTrue,
                      reason:
                          'Error loading generated code: $sourceGenLanguage');
                }
              }

              print('-- VM: $vmCodeGen');

              var runnerCodeGen = vmCodeGen.createRunner(sourceGenLanguage)!;

              for (var i = 0; i < calls.length; ++i) {
                var call = calls[i];
                var output = outputs[i];
                var outputJson =
                    _resolveLanguageOutput(output, sourceGenLanguage);

                await _testCall(call, i, outputJson, runnerCodeGen);
              }
            }
          }
        });
      }
    });
  }
}

String _resolveLanguageOutput(XmlElement output, String language) {
  String outputJson;
  if (output.children.isNotEmpty) {
    var child = output.children
        .firstWhereOrNull((e) => e.getAttribute('language') == language);
    child ??= output.children.firstWhereOrNull(
        (e) => e is XmlElement && e.getAttribute('language') == null);
    print(child);
    outputJson = child?.text ?? output.text;
  } else {
    outputJson = output.text;
  }
  return outputJson;
}

Future<void> _testCall(XmlElement call, int callIndex, String outputJson,
    ApolloLanguageRunner runner) async {
  var callClass = call.getAttribute('class');
  var callFunction = call.getAttribute('function')!;
  var callParametersJson = call.text;
  var callParameters = _parseJsonList(callParametersJson);

  var output = _parseJsonList(outputJson);

  var outputList = [];
  runner.externalPrintFunction = (o) => outputList.add(o);

  print('---------------------------------------');
  print(runner);
  print('EXPECTED OUTPUT[$callIndex]');
  print(output);
  print('');

  if (callClass != null) {
    print('EXECUTING[$callIndex]: $callClass.$callFunction( $callParameters )');
    await runner.executeClassMethod('', callClass, callFunction,
        positionalParameters: callParameters);
  } else {
    print('EXECUTING[$callIndex]: $callFunction( $callParameters )');
    await runner.executeFunction('', callFunction,
        positionalParameters: callParameters);
  }

  expect(outputList, equals(output), reason: 'Output error');

  print('OUTPUT[$callIndex]:');
  outputList.forEach((o) => print('>> $o'));
}

List _parseJsonList(String callParametersJson) {
  var list = json.decode(callParametersJson) as List;
  var l2 = _toListWithGenericType(list);
  return l2;
}

List _toListWithGenericType<T>(List list) {
  var l2 = list.map((e) => e is List ? _toListWithGenericType(e) : e).toList();

  var lString = _toListElementsOfType<String>(l2);
  if (lString != null) return lString;

  var lInt = _toListElementsOfType<int>(l2);
  if (lInt != null) return lInt;

  var lDouble = _toListElementsOfType<double>(l2);
  if (lDouble != null) return lDouble;

  var lNum = _toListElementsOfType<num>(l2);
  if (lNum != null) return lNum;

  var lBoll = _toListElementsOfType<bool>(l2);
  if (lBoll != null) return lBoll;

  // 1D

  var lListString = _toListElementsOfType<List<String>>(l2);
  if (lListString != null) return lListString;

  var lListInt = _toListElementsOfType<List<int>>(l2);
  if (lListInt != null) return lListInt;

  var lListDouble = _toListElementsOfType<List<double>>(l2);
  if (lListDouble != null) return lListDouble;

  var lListNum = _toListElementsOfType<List<num>>(l2);
  if (lListNum != null) return lListNum;

  var lListBool = _toListElementsOfType<List<bool>>(l2);
  if (lListBool != null) return lListBool;

  // 2D

  var lListString2 = _toListElementsOfType<List<List<String>>>(l2);
  if (lListString2 != null) return lListString2;

  var lListInt2 = _toListElementsOfType<List<List<int>>>(l2);
  if (lListInt2 != null) return lListInt2;

  var lListDouble2 = _toListElementsOfType<List<List<double>>>(l2);
  if (lListDouble2 != null) return lListDouble2;

  var lListNum2 = _toListElementsOfType<List<List<num>>>(l2);
  if (lListNum2 != null) return lListNum2;

  var lListBool2 = _toListElementsOfType<List<List<bool>>>(l2);
  if (lListBool2 != null) return lListBool2;

  // 3D

  var lListString3 = _toListElementsOfType<List<List<List<String>>>>(l2);
  if (lListString3 != null) return lListString3;

  var lListInt3 = _toListElementsOfType<List<List<List<int>>>>(l2);
  if (lListInt3 != null) return lListInt3;

  var lListDouble3 = _toListElementsOfType<List<List<List<double>>>>(l2);
  if (lListDouble3 != null) return lListDouble3;

  var lListNum3 = _toListElementsOfType<List<List<List<num>>>>(l2);
  if (lListNum3 != null) return lListNum3;

  var lListBool3 = _toListElementsOfType<List<List<List<bool>>>>(l2);
  if (lListBool3 != null) return lListBool3;

  //

  var lListObject3 = _toListElementsOfType<List<List<List<Object>>>>(l2);
  if (lListObject3 != null) return lListObject3;

  var lListObject2 = _toListElementsOfType<List<List<Object>>>(l2);
  if (lListObject2 != null) return lListObject2;

  var lListObject = _toListElementsOfType<List<Object>>(l2);
  if (lListObject != null) return lListObject;

  //

  var lObject = _toListElementsOfType<Object>(l2);
  if (lObject != null) return lObject;

  return l2;
}

List<T>? _toListElementsOfType<T>(List list) {
  if (_isListElementsAllOfType<T>(list)) {
    var l2 = list.cast<T>().toList();
    return l2;
  }
  return null;
}

bool _isListElementsAllOfType<T>(List list) {
  if (list is List<T>) return true;
  return list.whereType<T>().length == list.length;
}

class TypeHelper<T> {
  final Type type;

  TypeHelper(this.type);

  List<T> emptyList() => <T>[];
}

extension ListTypedExtension2<T> on List<T> {
  List<T> createListOfType() => <T>[];

  List<List<T>> createListOfType2D() => <List<T>>[];

  TypeHelper<T> get typeHelper => TypeHelper<T>(genericType);
}
