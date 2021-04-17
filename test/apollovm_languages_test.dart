import 'dart:convert';
import 'dart:io';

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

Future<void> main() async {
  var definitionsDirectory = Directory('./test/tests_definitions');

  print('TESTS DEFINITIONS DIRECTORY: $definitionsDirectory');

  var definitionsFiles = await definitionsDirectory
      .list()
      .where((f) => f.path.endsWith('.xml'))
      .map((f) => File(f.path))
      .map((f) => [f.path, f.readAsStringSync()])
      .toList();

  print('FOUND TESTS DEFINITIONS: ${definitionsFiles.length}');

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

  group('Dart', () {
    for (var fileEntry in definitionsFiles) {
      var fileName = fileEntry[0];
      var fileContent = fileEntry[1];

      final xml = XmlDocument.parse(fileContent);

      var rootElement = xml.rootElement;

      var title = rootElement.getAttribute('title')!;

      test(title, () async {
        print(
            '\n======================================================================\n');
        print('FILE: $fileName');
        print('');

        var source = rootElement.findElements('source').first;
        var language = source.getAttribute('language')!;
        var sourceCode = source.text;

        var calls = rootElement.findElements('call').toList();
        var outputs = rootElement.findElements('output').toList();

        var sourcesGenerated = rootElement.findElements('source-generated');

        print('TEST: $title');
        print('  - language: $language');
        print('  - sourcesGenerated: ${sourcesGenerated.length}');
        print('');
        print('SOURCE:');
        print(sourceCode);
        print('');

        var vm = ApolloVM();

        var codeUnit = CodeUnit(language, sourceCode, 'test');

        print('-- Loading source code');
        var loadOK = await vm.loadCodeUnit(codeUnit);

        expect(loadOK, isTrue, reason: "Error loading '$language' code!");

        var runner = vm.createRunner(language)!;

        for (var i = 0; i < calls.length; ++i) {
          var call = calls[i];
          var outputJson = outputs[i].text;

          var callClass = call.getAttribute('class');
          var callFunction = call.getAttribute('function')!;
          var callParametersJson = call.text;
          var callParameters = _parseJsonList(callParametersJson);

          var output = _parseJsonList(outputJson);

          var outputList = [];
          runner.externalPrintFunction = (o) => outputList.add(o);

          print('---------------------------------------');
          print('EXPECTED OUTPUT[$i]');
          print(output);
          print('');

          if (callClass != null) {
            print('EXECUTING[$i]: $callClass.$callFunction( $callParameters )');
            await runner.executeClassMethod('', callClass, callFunction,
                positionalParameters: callParameters);
          } else {
            print('EXECUTING[$i]: $callFunction( $callParameters )');
            await runner.executeFunction('', callFunction,
                positionalParameters: callParameters);
          }

          expect(outputList, equals(output));

          print('OUTPUT[$i]:');
          outputList.forEach((o) => print('>> $o'));
        }

        for (var sourceGen in sourcesGenerated) {
          print('---------------------------------------');
          var sourceGenLanguage = sourceGen.getAttribute('language')!;

          print('-- Checking code generation for language: $sourceGenLanguage');

          var codeStorage = vm.generateAllCodeIn(sourceGenLanguage);
          var allSources = codeStorage.writeAllSources().toString();
          print(allSources);

          expect(allSources, equals(sourceGen.text));
        }
      });
    }
  });
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
