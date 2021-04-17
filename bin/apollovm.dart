import 'dart:async';
import 'dart:io';

import 'package:apollovm/apollovm.dart';
import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:swiss_knife/swiss_knife.dart';

void _log(String ns, String message) {
  print('## [$ns]\t$message');
}

void main(List<String> args) async {
  var commandRunner = CommandRunner<bool>('apollovm',
      'ApolloVM/${ApolloVM.VERSION} - a compact VM for Dart and Java.')
    ..addCommand(CommandRun())
    ..addCommand(CommandTranslate());

  commandRunner.argParser.addFlag('version',
      abbr: 'v',
      negatable: false,
      defaultsTo: false,
      help: 'Show ApolloVM version.');

  {
    var argsResult = commandRunner.argParser.parse(args);
    if (argsResult['version']) {
      showVersion();
      return;
    }
  }

  await commandRunner.run(args);
}

void showVersion() {
  print('ApolloVM - ${ApolloVM.VERSION}');
}

abstract class CommandSourceFileBase extends Command<bool> {
  final _argParser = ArgParser(allowTrailingOptions: false);

  @override
  ArgParser get argParser => _argParser;

  CommandSourceFileBase() {
    argParser.addFlag('verbose',
        abbr: 'v',
        help: 'VM in Verbose mode',
        defaultsTo: false,
        negatable: false);
    argParser.addOption('language',
        help: 'Programming language of source file.\n'
            '(defaults to language of the file extension)',
        valueHelp: 'dart|java');
  }

  bool? _verbose;

  bool get verbose {
    _verbose ??= argResults!['verbose'] as bool;
    return _verbose!;
  }

  String get sourceFilePath {
    var argResults = this.argResults!;

    if (argResults.rest.isEmpty) {
      throw StateError('Empty arguments: no source file path!');
    }

    return argResults.rest[0];
  }

  File get sourceFile => File(sourceFilePath);

  String get sourceFileExtension {
    var ext = getPathExtension(sourceFilePath) ?? '';
    return ext.trim().toLowerCase();
  }

  String get language {
    var lang = argResults!['language'];
    return lang != null
        ? lang.toString().toLowerCase()
        : ApolloVM.parseLanguageFromFilePathExtension(sourceFilePath);
  }

  String get source => sourceFile.readAsStringSync();
}

class CommandRun extends CommandSourceFileBase {
  @override
  final String description = 'Run a source file.';

  @override
  final String name = 'run';

  CommandRun() {
    argParser.addOption('function',
        abbr: 'f',
        help: 'Named of the main function to call',
        defaultsTo: 'main',
        valueHelp: 'main|start');
  }

  String get mainFunction => argResults!['function'] ?? 'main';

  List<String> get parameters => argResults!.rest.sublist(1).toList();

  @override
  FutureOr<bool> run() async {
    var parameters = this.parameters;

    if (verbose) {
      _log('RUN',
          '$sourceFile ; language: $language > $mainFunction( $parameters )');
    }

    var vm = ApolloVM();

    var codeUnit = CodeUnit(language, source, sourceFilePath);

    var loadOK = await vm.loadCodeUnit(codeUnit);

    if (!loadOK) {
      throw StateError(
          "Can't parse source! language: $language ; sourceFilePath: $sourceFilePath");
    }

    var runner = vm.createRunner(language)!;

    var namespaces = vm.getLanguageNamespaces(language).namespaces;
    if (!namespaces.contains('')) namespaces.insert(0, '');

    ASTValue? result;

    for (var namespace in namespaces) {
      result =
          await runner.tryExecuteFunction(namespace, mainFunction, parameters);
      if (result != null) break;
    }

    if (result == null) {
      LOOP_NS:
      for (var namespace in namespaces) {
        var classes =
            vm.getLanguageNamespaces(language).get(namespace).classesNames;
        for (var clazz in classes) {
          result = await runner.tryExecuteClassFunction(
              namespace, clazz, mainFunction, parameters);
          if (result != null) break LOOP_NS;
        }
      }
    }

    if (result == null) {
      throw StateError("Can't find main function: $mainFunction");
    }

    return true;
  }
}

class CommandTranslate extends CommandSourceFileBase {
  @override
  final String description = 'Translate a source file.';

  @override
  final String name = 'translate';

  CommandTranslate() {
    argParser.addOption('target',
        help: 'Target Programming language for translation.\n'
            '(defaults to the opposite of the source language)',
        valueHelp: 'dart|java');
    ;
  }

  String get targetLanguage {
    var target = argResults!['target'];
    if (target == null) {
      if (language == 'dart') {
        target = 'java';
      } else {
        target = 'dart';
      }
    }
    return target;
  }

  @override
  FutureOr<bool> run() async {
    if (verbose) {
      _log('TRANSLATE',
          '$sourceFile ; language: $language > targetLanguage: $targetLanguage');
    }

    var vm = ApolloVM();

    var codeUnit = CodeUnit(language, source, sourceFilePath);

    var loadOK = await vm.loadCodeUnit(codeUnit);

    if (!loadOK) {
      throw StateError(
          "Can't parse source! language: $language ; sourceFilePath: $sourceFilePath");
    }

    var codeStorage = vm.generateAllCodeIn(targetLanguage);

    var allSources = codeStorage.writeAllSources().toString();

    print(allSources);

    return true;
  }
}
