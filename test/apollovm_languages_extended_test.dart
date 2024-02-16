@TestOn('vm')
import 'dart:io';

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

import 'apollovm_languages_test_definition.dart';

Future<void> main() async {
  var definitionsDirectory = Directory('./test/tests_definitions');

  print('TESTS DEFINITIONS DIRECTORY: $definitionsDirectory');

  var envVars = Platform.environment;
  var singleTest = envVars['SINGLE_TEST'];

  // ENV: SINGLE_TEST=java11_basic_for_loop_increment.test.xml

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

  await runTestDefinitions(definitions);
}
