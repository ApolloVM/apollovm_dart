import 'dart:convert';

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

  String get sourceCode => source.innerText;

  List<XmlElement> get calls => rootElement.findElements('call').toList();

  List<XmlElement> get outputs => rootElement.findElements('output').toList();

  List<XmlElement> get sourcesGenerated =>
      rootElement.findElements('source-generated').toList();

  @override
  int compareTo(TestDefinition other) {
    return fileName.compareTo(other.fileName);
  }
}

Future<void> runTestDefinitions(List<TestDefinition> testDefinitions) async {
  print('TESTS DEFINITIONS: ${testDefinitions.length}');

  testDefinitions.sort();

  var definitionsByGroup = groupBy<TestDefinition, String>(
    testDefinitions,
    (e) => e.language,
  );

  print('FOUND TESTS DEFINITIONS: ${testDefinitions.length}');

  for (var f in testDefinitions) {
    print('- ${f.fileName}');
  }

  group('Pre Test', () {
    test('_parseJsonList', () async {
      expect(
        _parseJsonList('["a","b"]').toListOfType() is List<String>,
        isTrue,
      );
      expect(_parseJsonList('["a","b"]').toListOfType() is List<int>, isFalse);

      expect(_parseJsonList('[1,2,3]').toListOfType() is List<int>, isTrue);
      expect(_parseJsonList('[1,2,3]').toListOfType() is List<String>, isFalse);

      expect(
        _parseJsonList('[1.1, 2.2, 3.3]').toListOfType() is List<double>,
        isTrue,
      );
      expect(
        _parseJsonList('[1.1, 2.2, 3.3]').toListOfType() is List<int>,
        isFalse,
      );

      expect(
        _parseJsonList('[ [1,2] , [3,4] ]').toListOfType() is List<List<int>>,
        isTrue,
      );

      expect(
        _parseJsonList('[ [ [1,2] ] , [ [3,4] ] ]').toListOfType()
            is List<List<List<int>>>,
        isTrue,
      );

      expect(
        _parseJsonList('[ [ [ [1,2] ] ] , [ [ [3,4] ] ] ]').toListOfType()
            is List<List<List<List<int>>>>,
        isTrue,
      );
    });
  });

  for (var lang in definitionsByGroup.keys) {
    var langDefinitions = definitionsByGroup[lang]!;

    group(lang, () {
      for (var testDefinition in langDefinitions) {
        test(testDefinition.title, () async {
          print(
            '\n======================================================================\n',
          );

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

          var codeUnit = SourceCodeUnit(
            language,
            testDefinition.sourceCode,
            id: 'test',
          );

          print('-- Loading source code');
          var loadOK = await vm.loadCodeUnit(codeUnit);

          expect(loadOK, isTrue, reason: "Error loading '$language ' code!");

          var runner = vm.createRunner(language, importCorePackageMath: true)!;

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
              '-- Checking code generation for language: $sourceGenLanguage',
            );

            var codeStorage = vm.generateAllCodeIn(sourceGenLanguage);
            var allSources = (await codeStorage.writeAllSources()).toString();
            print(allSources);

            expect(allSources, equals(sourceGen.innerText));

            {
              print('.......................................');

              var vmCodeGen = ApolloVM();
              print('-- Testing generated code in VM: $vmCodeGen');

              for (var ns in await codeStorage.getNamespaces()) {
                for (var id in await codeStorage.getNamespaceCodeUnitsIDs(ns)) {
                  var source = await codeStorage.getNamespaceCodeUnit(ns, id);
                  var cu = SourceCodeUnit(sourceGenLanguage, source!, id: id);

                  print('-- Loading generated code: $cu');
                  var ok = await vmCodeGen.loadCodeUnit(cu);
                  print(cu.code);
                  expect(
                    ok,
                    isTrue,
                    reason: 'Error loading generated code: $sourceGenLanguage',
                  );
                }
              }

              print('-- VM: $vmCodeGen');

              var runnerCodeGen = vmCodeGen.createRunner(
                sourceGenLanguage,
                importCorePackageMath: true,
              )!;

              for (var i = 0; i < calls.length; ++i) {
                var call = calls[i];
                var output = outputs[i];
                var outputJson = _resolveLanguageOutput(
                  output,
                  sourceGenLanguage,
                );

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
    var child = output.children.firstWhereOrNull(
      (e) => e.getAttribute('language') == language,
    );
    child ??= output.children.firstWhereOrNull(
      (e) => e is XmlElement && e.getAttribute('language') == null,
    );
    print(child);
    outputJson = child?.innerText ?? output.innerText;
  } else {
    outputJson = output.innerText;
  }
  return outputJson;
}

Future<void> _testCall(
  XmlElement call,
  int callIndex,
  String outputJson,
  ApolloRunner runner,
) async {
  var callClass = call.getAttribute('class');
  var callFunction = call.getAttribute('function')!;
  var callReturn = call.getAttribute('return');
  var callReturnType = call.getAttribute('returnType');

  var callParametersJson = call.innerText;
  var callParameters = _parseJsonList(callParametersJson);

  var output = _parseJsonList(outputJson);

  var outputList = [];
  runner.externalPrintFunction = (o) => outputList.add(o);

  print('---------------------------------------');
  print(runner);

  if (callReturn != null) {
    print(
      'EXPECTED RETURN[$callIndex]: (${callReturnType ?? '?'}) $callReturn',
    );
  }

  print('EXPECTED OUTPUT[$callIndex]');
  print(output);
  print('');

  ASTValue executionReturn;
  if (callClass != null) {
    print('EXECUTING[$callIndex]: $callClass.$callFunction( $callParameters )');
    executionReturn = await runner.executeClassMethod(
      '',
      callClass,
      callFunction,
      positionalParameters: callParameters,
    );
  } else {
    print('EXECUTING[$callIndex]: $callFunction( $callParameters )');
    executionReturn = await runner.executeFunction(
      '',
      callFunction,
      positionalParameters: callParameters,
    );
  }

  print('RETURN[$callIndex]: $executionReturn');

  if (callReturn != null) {
    expect(
      executionReturn.getValueNoContext().toString(),
      equals(callReturn),
      reason: 'Return error',
    );
  }

  if (callReturnType != null) {
    expect(
      executionReturn.type.name,
      equals(callReturnType),
      reason: 'Return type error',
    );
  }

  expect(outputList, equals(output), reason: 'Output error');

  print('OUTPUT[$callIndex]:');

  for (var o in outputList) {
    print('>> $o');
  }
}

List _parseJsonList(String callParametersJson) {
  return json.decode(callParametersJson) as List;
}
