import 'dart:io';

import 'package:apollovm/apollovm.dart';
import 'package:apollovm/apollovm_lsp.dart';
import 'package:apollovm/apollovm_mcp_io.dart';
import 'package:apollovm/apollovm_pub.dart';
import 'package:apollovm/apollovm_serialization.dart';
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
        ..addCommand(CommandMcp())
        ..addCommand(CommandLsp());

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

  // A command returns `false` only when it rejected the source (today: a
  // `--null-safety` failure), which must be a non-zero exit so a build/CI step
  // fails. `run` yields `null` when no command executed (`--help`, usage).
  var ok = await commandRunner.run(args);
  if (ok == false) exitCode = 1;
}

void showVersion() {
  print('ApolloVM - ${ApolloVM.VERSION}');
}

abstract class CommandSourceFileBase extends Command<bool> {
  /// Whether options may follow the source file on the command line.
  ///
  /// `true` for the commands whose only positional argument is that file.
  /// `apollovm compile foo.dart --target=ast` is the natural way to write it,
  /// and with trailing options disabled the flag is not parsed at all: it lands
  /// in `rest`, `--target` keeps its default, and the command quietly compiles
  /// to Wasm instead of reporting that it ignored the argument.
  ///
  /// [CommandRun] overrides this to `false`, because there everything after the
  /// file belongs to the program being run and must reach it untouched.
  bool get allowTrailingOptions => true;

  late final _argParser = ArgParser(allowTrailingOptions: allowTrailingOptions);

  @override
  ArgParser get argParser => _argParser;

  /// Rejects anything after the source file.
  ///
  /// With trailing options parsed, a leftover positional argument is a genuine
  /// mistake — a typo, or a flag for a different command — and saying so beats
  /// ignoring it.
  void checkNoExtraArguments() {
    var extra = argResults!.rest.skip(1).toList();
    if (extra.isEmpty) return;

    throw StateError(
      'Unexpected argument${extra.length > 1 ? 's' : ''} after the source '
      'file: ${extra.join(' ')}',
    );
  }

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
    argParser.addFlag(
      'null-safety',
      help:
          'Reject source with null-safety errors while loading it, instead of\n'
          'failing partway through the run.',
      defaultsTo: false,
      negatable: false,
    );
    argParser.addFlag(
      'pub',
      help:
          'Resolve Dart `package:` imports through the optional package '
          'importer (pub.dev-compatible).',
      defaultsTo: false,
      negatable: false,
    );
    argParser.addOption(
      'pub-host',
      help:
          'Package host for `--pub` (enables the network downloader).\n'
          'When omitted, resolves via `.dart_tool/package_config.json`.',
      valueHelp: 'https://pub.dev',
    );
    argParser.addOption(
      'pub-cache',
      help: 'Cache directory for downloaded packages (with `--pub-host`).',
      valueHelp: 'dir',
    );
  }

  bool get usePub => argResults!['pub'] as bool;

  String? get pubHost => argResults!['pub-host'] as String?;

  String? get pubCache => argResults!['pub-cache'] as String?;

  /// Whether `--null-safety` was passed: the VM then rejects a code unit whose
  /// AST has null-safety errors while loading it.
  bool get nullSafetyChecks => argResults!['null-safety'] as bool;

  /// Set when [loadCodeUnitReporting] rejected the source for null-safety
  /// errors, so the caller reports nothing further (it was already printed, and
  /// it is not a parse failure).
  bool nullSafetyRejected = false;

  /// Loads [codeUnit] into [vm], reporting a [NullSafetyError] as a clean
  /// message instead of letting it escape as an unhandled error with a stack
  /// trace — `--null-safety` is user-facing, so its failure should read like a
  /// diagnostic.
  Future<bool> loadCodeUnitReporting<T extends Object>(
    ApolloVM vm,
    CodeUnit<T> codeUnit,
  ) async {
    try {
      return await vm.loadCodeUnit(codeUnit);
    } on NullSafetyError catch (e) {
      nullSafetyRejected = true;
      print('** NULL SAFETY: ${e.message}');
      for (var f in e.findings) {
        print('   - ${f.message}');
      }
      return false;
    }
  }

  /// Installs the optional Dart package importer on [vm] and pre-loads all
  /// reachable `package:` imports. No-op unless `--pub` is set (and Dart).
  Future<void> installPackageImporter(ApolloVM vm) async {
    if (!usePub || language != 'dart') return;

    final host = pubHost;
    final PackageProvider provider;
    if (host != null) {
      var cacheDir = pubCache;
      var pubspecFile = File('pubspec.yaml');
      provider = PubDevProvider(
        host: host,
        cache: cacheDir != null
            ? FilePackageCache(cacheDir)
            : MemoryPackageCache(),
        pubspecYaml: pubspecFile.existsSync()
            ? pubspecFile.readAsStringSync()
            : null,
      );
    } else {
      provider = PackageConfigProvider(runPubGetIfMissing: true);
    }

    var loader = DartPackageLoader(vm, provider);
    vm.moduleLoader = loader;

    var diagnostics = await loader.provision();
    if (verbose && diagnostics.isNotEmpty) {
      for (var d in diagnostics) {
        _log('PUB', d.toString());
      }
    }
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

  @override
  String get usageFooter => '''

Examples:
  apollovm run script.dart
  apollovm run app.py --function start
  apollovm run prog.java main foo bar      # call `main` with args foo, bar
  apollovm run module.wasm
  apollovm run calc.avma                   # a binary AST image; no parsing''';

  // Everything after the source file is passed to the program being run, so it
  // must not be interpreted as options for `apollovm` itself.
  @override
  bool get allowTrailingOptions => false;

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

    var vm = ApolloVM(nullSafetyChecks: nullSafetyChecks);

    // A binary AST image already holds a parsed program, and records which
    // language it came from — so it is detected by its magic bytes rather than
    // by its extension, and the recorded language wins over anything the file
    // name suggests.
    var fileBytes = sourceFile.readAsBytesSync();
    var isBinaryAST = ASTBinaryReader.isASTBinary(fileBytes);

    CodeUnit<Object> codeUnit;
    String effectiveLanguage;

    if (isBinaryAST) {
      codeUnit = const ASTBinaryReader().readCodeUnit(fileBytes);
      effectiveLanguage = codeUnit.language;
    } else if (language == 'wasm') {
      // A `.wasm` file is a binary module: load its bytes as a
      // `BinaryCodeUnit` (parsed by `ApolloParserWasm` into its exported
      // functions) and run it through the Wasm runtime, rather than decoding
      // the binary as UTF-8 source.
      effectiveLanguage = 'wasm';
      codeUnit = BinaryCodeUnit(
        'wasm',
        fileBytes,
        id: sourceFilePath,
        namespace: '',
      );
    } else {
      effectiveLanguage = language;
      codeUnit = SourceCodeUnit(language, source, id: sourceFilePath);
    }

    if (verbose) {
      _log(
        'RUN',
        '$sourceFile ; language: $effectiveLanguage'
            '${isBinaryAST ? ' (binary AST)' : ''} > '
            '$mainFunction( $parameters )',
      );
    }

    var loadOK = await loadCodeUnitReporting(vm, codeUnit);

    if (!loadOK) {
      // A null-safety rejection was already reported in full; it is not a parse
      // failure, so do not restate it as one.
      if (nullSafetyRejected) return false;
      throw StateError(
        "Can't parse source! language: $language ; sourceFilePath: $sourceFilePath",
      );
    }

    await installPackageImporter(vm);

    var runner = vm.createRunner(effectiveLanguage)!;

    var namespaces = vm.getLanguageNamespaces(effectiveLanguage).namespaces;
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
            .getLanguageNamespaces(effectiveLanguage)
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

  @override
  String get usageFooter => '''

Examples:
  apollovm translate Foo.java --target dart
  apollovm translate script.py --target javascript
  apollovm translate app.go --target kotlin''';

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
    checkNoExtraArguments();

    if (verbose) {
      _log(
        'TRANSLATE',
        '$sourceFile ; language: $language > targetLanguage: $targetLanguage',
      );
    }

    var vm = ApolloVM(nullSafetyChecks: nullSafetyChecks);

    var codeUnit = SourceCodeUnit(language, source, id: sourceFilePath);

    var loadOK = await loadCodeUnitReporting(vm, codeUnit);

    if (!loadOK) {
      // A null-safety rejection was already reported in full; it is not a parse
      // failure, so do not restate it as one.
      if (nullSafetyRejected) return false;
      throw StateError(
        "Can't parse source! language: $language ; sourceFilePath: $sourceFilePath",
      );
    }

    await installPackageImporter(vm);

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

  @override
  String get usageFooter => '''

Examples:
  apollovm compile calc.dart               # writes calc.wasm
  apollovm compile calc.dart -o build/calc.wasm
  apollovm compile calc.dart --target=ast  # writes calc.avma (binary AST)''';

  CommandCompile() {
    argParser.addOption(
      'output',
      abbr: 'o',
      help:
          'Output file path (defaults to <source>.wasm or <source>.avma,\n'
          'alongside the source file).\n'
          'If multiple Wasm modules are produced, the module name is inserted before `.wasm`.',
      valueHelp: 'file.wasm',
    );
    argParser.addOption(
      'target',
      help:
          'Binary target:\n'
          '  wasm  WebAssembly module.\n'
          '  ast   Binary AST image (`.avma`, an Apollo Virtual Machine\n'
          '        Archive) — the parsed program, so it can be loaded later\n'
          '        without running a parser.',
      defaultsTo: 'wasm',
      valueHelp: 'wasm|ast',
    );
  }

  String get target =>
      (argResults!['target'] as String? ?? 'wasm').toLowerCase();

  String? get output => argResults!['output'] as String?;

  @override
  FutureOr<bool> run() async {
    checkNoExtraArguments();

    var target = this.target;

    if (verbose) {
      _log('COMPILE', '$sourceFile ; language: $language > target: $target');
    }

    if (target != 'wasm' && target != 'ast') {
      throw StateError('Unsupported compile target: $target');
    }

    var vm = ApolloVM(nullSafetyChecks: nullSafetyChecks);

    var codeUnit = SourceCodeUnit(language, source, id: sourceFilePath);

    var loadOK = await loadCodeUnitReporting(vm, codeUnit);

    if (!loadOK) {
      // A null-safety rejection was already reported in full; it is not a parse
      // failure, so do not restate it as one.
      if (nullSafetyRejected) return false;
      throw StateError(
        "Can't parse source! language: $language ; sourceFilePath: $sourceFilePath",
      );
    }

    await installPackageImporter(vm);

    if (target == 'ast') {
      var image = vm.saveCodeUnitAST(codeUnit);
      var filePath =
          output ?? _defaultOutputPath(ASTBinaryFormat.fileExtension);

      File(filePath).writeAsBytesSync(image);

      print(
        'Wrote: $filePath (${image.length} bytes, '
        'source: ${source.length} bytes)',
      );
      return true;
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

    var outputPath = output ?? _defaultOutputPath('wasm');

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

  String _defaultOutputPath(String extension) {
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
      return '${path.substring(0, path.length - (name.length - dot))}'
          '.$extension';
    }
    return '$path.$extension';
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

/// Runs the ApolloVM Language Server over stdio (JSON-RPC 2.0 with
/// `Content-Length` framing), for local editors/agents:
///
/// ```sh
/// apollovm lsp
/// ```
///
/// Note: stdout is the LSP channel, so this command must not print anything
/// else to it.
class CommandLsp extends Command<bool> {
  @override
  final String description =
      'Start the ApolloVM Language Server (LSP) over stdin/stdout.';

  @override
  final String name = 'lsp';

  @override
  FutureOr<bool> run() async {
    // Keep stdout raw so binary framing isn't mangled by line translation.
    stdout.encoding = SystemEncoding();

    final endpoint = StreamLspEndpoint(stdin, stdout);
    final server = LspServer(endpoint);
    server.start();
    await server.done;
    return server.cleanExit;
  }
}
