import 'dart:convert';

import 'package:apollovm/apollovm.dart';
// Serialization internals are not re-exported from the public library.
import 'package:apollovm/src/serialization/ast_binary_reader.dart';
import 'package:apollovm/src/serialization/ast_binary_writer.dart';
import 'package:collection/collection.dart';
import 'package:swiss_knife/swiss_knife.dart';
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

  /// All `<source>` elements (a test may declare several for multi-file /
  /// cross-module scenarios). Single-source tests have exactly one.
  List<XmlElement> get sources => rootElement.findElements('source').toList();

  XmlElement get source => sources.first;

  String get language => source.getAttribute('language')!;

  /// The `id` (usually a file path / module id) of a `<source>`, or `'test'`.
  static String sourceId(XmlElement source) =>
      source.getAttribute('id') ?? 'test';

  bool get autoImportDartMath =>
      parseBool(source.getAttribute('auto-import-dart-math')) ?? false;

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

          final language = testDefinition.language;
          final autoImportDartMath = testDefinition.autoImportDartMath;
          final sourcesGenerated = testDefinition.sourcesGenerated;

          print('FILE: ${testDefinition.fileName}');
          print('');

          print('TEST: ${testDefinition.title}');

          print('  - language: $language ');
          print('  - autoImportDartMath: $autoImportDartMath ');
          print('  - sourcesGenerated: ${sourcesGenerated.length}');
          print('');
          print('SOURCE:');
          print(testDefinition.sourceCode);
          print('');

          var vm = ApolloVM();

          // Load every `<source>` (one for single-file tests, several for
          // multi-file/cross-module tests). Each is filed under its `id`.
          for (var source in testDefinition.sources) {
            var codeUnit = SourceCodeUnit(
              language,
              source.innerText,
              id: TestDefinition.sourceId(source),
            );

            print('-- Loading source code: ${codeUnit.id}');
            var loadOK = await vm.loadCodeUnit(codeUnit);

            expect(loadOK, isTrue, reason: "Error loading '$language ' code!");
          }

          var calls = testDefinition.calls;
          var outputs = testDefinition.outputs;

          // Before anything runs. Executing an AST mutates it — local function
          // declarations get registered on their block, and `var` declarations
          // cache an inferred type — so a post-execution AST is not the same
          // object a fresh parse produces. Encoding here compares like with
          // like, and matches the real use case: an image is written by a build
          // step that never runs the code.
          await _testBinaryASTRoundTrip(
            vm,
            language,
            calls,
            outputs,
            autoImportDartMath: autoImportDartMath,
          );

          var runner = vm.createRunner(
            language,
            importCorePackageMath: autoImportDartMath,
          )!;

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

/// Encodes every code unit loaded in [vm] as a binary AST, decodes the images
/// into a fresh VM, and re-runs the whole test against it.
///
/// This reuses the language fixtures as binary round-trip coverage: every
/// construct any fixture exercises has to survive encode/decode, in every
/// language, or the fixture fails. The generated-source comparison is the
/// strongest part — it exercises every field the code generator reads across
/// the whole tree, so a field dropped by a codec shows up as a diff rather than
/// going unnoticed.
Future<void> _testBinaryASTRoundTrip(
  ApolloVM vm,
  String language,
  List<XmlElement> calls,
  List<XmlElement> outputs, {
  required bool autoImportDartMath,
}) async {
  print('.......................................');
  print('-- Binary AST round trip');

  var expectedSources = (await vm.generateAllCodeIn(language).writeAllSources())
      .toString();

  var vmBin = ApolloVM();

  for (var codeUnit in vm.allCodeUnitsAllLanguages()) {
    var image = const ASTBinaryWriter().writeCodeUnit(codeUnit);

    print(
      '-- Encoded ${codeUnit.id}: ${image.length} bytes '
      '(source: ${codeUnit.code is String ? (codeUnit.code as String).length : '?'})',
    );

    var decoded = const ASTBinaryReader().readCodeUnit(image);

    var ok = await vmBin.loadCodeUnit(decoded);
    expect(
      ok,
      isTrue,
      reason: 'Error loading the decoded binary AST: ${codeUnit.id}',
    );
  }

  var binSources = (await vmBin.generateAllCodeIn(language).writeAllSources())
      .toString();

  expect(
    binSources,
    equals(expectedSources),
    reason: 'Regenerated source diverged after a binary AST round trip',
  );

  var runnerBin = vmBin.createRunner(
    language,
    importCorePackageMath: autoImportDartMath,
  )!;

  for (var i = 0; i < calls.length; ++i) {
    var outputJson = _resolveLanguageOutput(outputs[i], language);
    await _testCall(calls[i], i, outputJson, runnerBin);
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
    // Definition entry methods are declared non-static, so run them against a
    // (field-less) instance — only `static` methods run without an instance.
    executionReturn = await runner.executeClassMethod(
      '',
      callClass,
      callFunction,
      positionalParameters: callParameters,
      classInstanceFields: const {},
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

  print('OUTPUT[$callIndex]:');

  print(JsonEncoder.withIndent('  ').convert(outputList));

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
}

List _parseJsonList(String callParametersJson) {
  return json.decode(callParametersJson) as List;
}
