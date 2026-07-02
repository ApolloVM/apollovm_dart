import 'dart:io';

import 'package:apollovm/apollovm.dart';
import 'package:apollovm/apollovm_mcp.dart';
import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:swiss_knife/swiss_knife.dart';

void _log(String ns, String message) {
  print('## [$ns]\t$message');
}

void main(List<String> args) async {
  var commandRunner =
      CommandRunner<bool>(
          'apollovm',
          'ApolloVM/${ApolloVM.VERSION} - A compact VM for Dart, Java, Kotlin, Go, C#, JavaScript, TypeScript, Lua and Python.',
        )
        ..addCommand(CommandRun())
        ..addCommand(CommandTranslate())
        ..addCommand(CommandCompile())
        ..addCommand(CommandMcp());

  commandRunner.argParser.addFlag(
    'version',
    abbr: 'v',
    negatable: false,
    defaultsTo: false,
    help: 'Show ApolloVM version.',
  );

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
    argParser.addFlag(
      'verbose',
      abbr: 'v',
      help: 'VM in Verbose mode',
      defaultsTo: false,
      negatable: false,
    );
    argParser.addOption(
      'language',
      help:
          'Programming language of source file.\n'
          '(defaults to language of the file extension)',
      valueHelp: 'dart|java|kotlin|go|javascript|typescript|lua|python',
    );
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
    argParser.addOption(
      'function',
      abbr: 'f',
      help: 'Named of the main function to call',
      defaultsTo: 'main',
      valueHelp: 'main|start',
    );
  }

  String get mainFunction => argResults!['function'] ?? 'main';

  List<String> get parameters => argResults!.rest.sublist(1).toList();

  @override
  FutureOr<bool> run() async {
    var parameters = this.parameters;

    if (verbose) {
      _log(
        'RUN',
        '$sourceFile ; language: $language > $mainFunction( $parameters )',
      );
    }

    var vm = ApolloVM();

    // A `.wasm` file is a binary module: load its bytes as a `BinaryCodeUnit`
    // (parsed by `ApolloParserWasm` into its exported functions) and run it
    // through the Wasm runtime, rather than decoding the binary as UTF-8 source.
    CodeUnit<Object> codeUnit;
    if (language == 'wasm') {
      var bytes = sourceFile.readAsBytesSync();
      codeUnit = BinaryCodeUnit(
        'wasm',
        bytes,
        id: sourceFilePath,
        namespace: '',
      );
    } else {
      codeUnit = SourceCodeUnit(language, source, id: sourceFilePath);
    }

    var loadOK = await vm.loadCodeUnit(codeUnit);

    if (!loadOK) {
      throw StateError(
        "Can't parse source! language: $language ; sourceFilePath: $sourceFilePath",
      );
    }

    var runner = vm.createRunner(language)!;

    var namespaces = vm.getLanguageNamespaces(language).namespaces;
    if (!namespaces.contains('')) namespaces.insert(0, '');

    ASTValue? result;

    for (var namespace in namespaces) {
      result = await runner.tryExecuteFunction(
        namespace,
        mainFunction,
        parameters,
      );
      if (result != null) break;
    }

    if (result == null) {
      LOOP_NS:
      for (var namespace in namespaces) {
        var classes = vm
            .getLanguageNamespaces(language)
            .get(namespace)
            .classesNames;
        for (var clazz in classes) {
          result = await runner.tryExecuteClassFunction(
            namespace,
            clazz,
            mainFunction,
            parameters,
          );
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
    argParser.addOption(
      'target',
      help:
          'Target Programming language for translation.\n'
          '(defaults to the opposite of the source language)',
      valueHelp: 'dart|java|kotlin|go|javascript|typescript|lua|python',
    );
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
      _log(
        'TRANSLATE',
        '$sourceFile ; language: $language > targetLanguage: $targetLanguage',
      );
    }

    var vm = ApolloVM();

    var codeUnit = SourceCodeUnit(language, source, id: sourceFilePath);

    var loadOK = await vm.loadCodeUnit(codeUnit);

    if (!loadOK) {
      throw StateError(
        "Can't parse source! language: $language ; sourceFilePath: $sourceFilePath",
      );
    }

    var codeStorage = vm.generateAllCodeIn(targetLanguage);

    var allSources = (await codeStorage.writeAllSources()).toString();

    print(allSources);

    return true;
  }
}

class CommandCompile extends CommandSourceFileBase {
  @override
  final String description =
      'Compile a source file to a binary target (WebAssembly).';

  @override
  final String name = 'compile';

  CommandCompile() {
    argParser.addOption(
      'output',
      abbr: 'o',
      help:
          'Output file path (defaults to <source>.wasm, alongside the source file).\n'
          'If multiple modules are produced, the module name is inserted before `.wasm`.',
      valueHelp: 'file.wasm',
    );
    argParser.addOption(
      'target',
      help: 'Binary target (currently: wasm).',
      defaultsTo: 'wasm',
      valueHelp: 'wasm',
    );
  }

  String get target =>
      (argResults!['target'] as String? ?? 'wasm').toLowerCase();

  String? get output => argResults!['output'] as String?;

  @override
  FutureOr<bool> run() async {
    var target = this.target;

    if (verbose) {
      _log('COMPILE', '$sourceFile ; language: $language > target: $target');
    }

    if (target != 'wasm') {
      throw StateError('Unsupported compile target: $target');
    }

    var vm = ApolloVM();

    var codeUnit = SourceCodeUnit(language, source, id: sourceFilePath);

    var loadOK = await vm.loadCodeUnit(codeUnit);

    if (!loadOK) {
      throw StateError(
        "Can't parse source! language: $language ; sourceFilePath: $sourceFilePath",
      );
    }

    var storageWasm = vm.generateAllIn<BytesOutput>('wasm');
    var wasmModules = await storageWasm.allEntries();

    var modules = <MapEntry<String, BytesOutput>>[];
    for (var namespace in wasmModules.entries) {
      for (var module in namespace.value.entries) {
        modules.add(MapEntry(module.key, module.value));
      }
    }

    if (modules.isEmpty) {
      throw StateError(
        "No Wasm modules generated! language: $language ; sourceFilePath: $sourceFilePath",
      );
    }

    var outputPath = output ?? _defaultOutputPath();

    var single = modules.length == 1;

    for (var module in modules) {
      var moduleName = module.key;
      var wasmBytes = module.value.output();

      var filePath = single
          ? outputPath
          : _insertModuleName(outputPath, moduleName);

      File(filePath).writeAsBytesSync(wasmBytes);

      print('Wrote: $filePath (${wasmBytes.length} bytes)');
    }

    return true;
  }

  String _defaultOutputPath() {
    var path = sourceFilePath;
    // Strip the extension from the FILE NAME only — `getPathExtension` keys off
    // the last `.` anywhere in the path, which would wrongly truncate when the
    // file has no extension but a parent directory contains a `.` (e.g.
    // `proj.v2/main` -> `proj.wasm`). Operate on the final path segment instead.
    var sep = path.lastIndexOf('/');
    var name = sep >= 0 ? path.substring(sep + 1) : path;
    var dot = name.lastIndexOf('.');
    if (dot > 0) {
      // The file name has a real extension to replace.
      return '${path.substring(0, path.length - (name.length - dot))}.wasm';
    }
    return '$path.wasm';
  }

  String _insertModuleName(String outputPath, String moduleName) {
    const suffix = '.wasm';
    if (outputPath.toLowerCase().endsWith(suffix)) {
      var base = outputPath.substring(0, outputPath.length - suffix.length);
      return '$base.$moduleName$suffix';
    }
    return '$outputPath.$moduleName$suffix';
  }
}
