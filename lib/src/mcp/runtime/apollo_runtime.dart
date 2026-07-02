// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:convert';

import 'package:apollovm/apollovm.dart';

import '../mcp_config.dart';
import '../serialize/diagnostics.dart';
import '../serialize/value_json.dart';

/// Result of a parse request.
typedef ParseOutcome = ({ASTRoot? root, List<Diagnostic> diagnostics});

/// Result of an execute request.
typedef ExecuteOutcome = ({
  Object? result,
  bool hasResult,
  List<String> output,
  bool truncated,
  List<Diagnostic> diagnostics,
});

/// Result of a translate request.
typedef TranslateOutcome = ({String? generated, List<Diagnostic> diagnostics});

/// Result of a wasm compile request.
typedef WasmOutcome = ({
  List<Map<String, Object?>>? modules,
  List<Diagnostic> diagnostics,
});

/// In-process façade over [ApolloVM] used by the MCP tools.
///
/// Security model: only the `print` external is ever exposed to interpreted
/// code (no file/socket bridge is registered), and inputs are inline source
/// strings only — so file/network access is denied by construction. Execution
/// is bounded by [McpLimits.timeoutMs] via `Future.timeout`; input/output are
/// bounded by [McpLimits.maxSourceChars]/[McpLimits.maxOutputChars].
class ApolloRuntime {
  final McpLimits limits;

  ApolloRuntime({this.limits = const McpLimits()});

  Diagnostic _err(String message) =>
      <String, Object?>{'severity': 'error', 'message': message};

  /// Returns a source-too-large diagnostic list, or `null` if within limits.
  List<Diagnostic>? _checkSource(String source) {
    if (source.length > limits.maxSourceChars) {
      return [
        _err(
          'Source exceeds maxSourceChars (${source.length} > '
          '${limits.maxSourceChars})',
        ),
      ];
    }
    return null;
  }

  /// Parses [source] in [language] and returns its [ASTRoot] plus diagnostics.
  ///
  /// Uses the parser directly (not `loadCodeUnit`) so a parse failure yields
  /// structured line/column diagnostics instead of a thrown [SyntaxError].
  Future<ParseOutcome> parse(String language, String source) async {
    final tooLarge = _checkSource(source);
    if (tooLarge != null) return (root: null, diagnostics: tooLarge);

    final vm = ApolloVM();
    final parser = vm.getParser<String>(language);
    if (parser == null) {
      return (root: null, diagnostics: [_err('Unsupported language: $language')]);
    }

    final codeUnit = SourceCodeUnit(language, source, id: 'mcp');
    final result = await parser.parse(codeUnit);
    if (result.isOK) {
      return (root: result.root, diagnostics: const <Diagnostic>[]);
    }
    return (root: null, diagnostics: [diagnosticFromParseResult(result)]);
  }

  /// Loads [source] into a fresh [ApolloVM], returning `(vm, null)` on success
  /// or `(null, diagnostics)` on failure.
  Future<(ApolloVM?, List<Diagnostic>?)> _load(
    String language,
    String source,
  ) async {
    final vm = ApolloVM();
    // Reject unknown languages up front: `loadCodeUnit` throws a `StateError`
    // (rather than returning false) when there is no parser for the language.
    if (vm.getParser<String>(language) == null) {
      return (null, [_err('Unsupported language: $language')]);
    }
    final codeUnit = SourceCodeUnit(language, source, id: 'mcp');
    try {
      final ok = await vm.loadCodeUnit(codeUnit);
      if (!ok) {
        return (null, [_err('Unsupported language: $language')]);
      }
      return (vm, null);
    } on SyntaxError catch (e) {
      return (null, [diagnosticFromError(e)]);
    }
  }

  /// Executes [source]: loads it, calls [function] (default `main`) — optionally
  /// as a method of [className] — with [args], and returns the resolved result,
  /// captured console output, and diagnostics. Bounded by the configured
  /// timeout and output cap.
  Future<ExecuteOutcome> execute(
    String language,
    String source, {
    String function = 'main',
    String? className,
    List<Object?> args = const [],
    int? timeoutMs,
  }) async {
    final tooLarge = _checkSource(source);
    if (tooLarge != null) {
      return (
        result: null,
        hasResult: false,
        output: const <String>[],
        truncated: false,
        diagnostics: tooLarge,
      );
    }

    final (vm, loadDiagnostics) = await _load(language, source);
    if (vm == null) {
      return (
        result: null,
        hasResult: false,
        output: const <String>[],
        truncated: false,
        diagnostics: loadDiagnostics!,
      );
    }

    final output = <String>[];
    var outputChars = 0;
    var truncated = false;
    final cap = limits.maxOutputChars;

    void capture(Object? o) {
      if (truncated) return;
      final line = '$o';
      if (outputChars + line.length > cap) {
        final remaining = cap - outputChars;
        if (remaining > 0) output.add(line.substring(0, remaining));
        truncated = true;
        outputChars = cap;
      } else {
        output.add(line);
        outputChars += line.length;
      }
    }

    final runner = vm.createRunner(language)!;
    runner.externalPrintFunction = capture;

    final timeout = Duration(milliseconds: timeoutMs ?? limits.timeoutMs);

    try {
      final astValue = await _runEntry(
        vm,
        runner,
        language,
        function,
        className,
        args,
      ).timeout(timeout);

      Object? result;
      var hasResult = false;
      if (astValue != null) {
        var native = astValue.getValueNoContext();
        if (native is Future) native = await native;
        result = valueToJson(native);
        hasResult = true;
      }

      final diagnostics = <Diagnostic>[];
      if (!hasResult) {
        diagnostics.add(
          _err(
            "Entry function not found: ${className != null ? '$className.' : ''}"
            '$function',
          ),
        );
      }

      return (
        result: result,
        hasResult: hasResult,
        output: output,
        truncated: truncated,
        diagnostics: diagnostics,
      );
    } on TimeoutException {
      return (
        result: null,
        hasResult: false,
        output: output,
        truncated: truncated,
        diagnostics: [
          _err('Execution timed out after ${timeout.inMilliseconds}ms'),
        ],
      );
    } catch (e) {
      return (
        result: null,
        hasResult: false,
        output: output,
        truncated: truncated,
        diagnostics: [diagnosticFromError(e)],
      );
    }
  }

  /// Finds and runs the entry point, mirroring the CLI's discovery order:
  /// an explicit [className] method, then a top-level function across
  /// namespaces, then any class method of that name.
  Future<ASTValue?> _runEntry(
    ApolloVM vm,
    ApolloRunner runner,
    String language,
    String function,
    String? className,
    List<Object?> args,
  ) async {
    final namespaces = vm.getLanguageNamespaces(language).namespaces;
    if (!namespaces.contains('')) namespaces.insert(0, '');

    if (className != null) {
      for (var ns in namespaces) {
        final r = await _tryClassMethod(runner, ns, className, function, args);
        if (r != null) return r;
      }
      return null;
    }

    for (var ns in namespaces) {
      final r = await runner.tryExecuteFunction(ns, function, args);
      if (r != null) return r;
    }

    for (var ns in namespaces) {
      final classes = vm.getLanguageNamespaces(language).get(ns).classesNames;
      for (var clazz in classes) {
        final r = await _tryClassMethod(runner, ns, clazz, function, args);
        if (r != null) return r;
      }
    }

    return null;
  }

  /// Invokes a class method providing a fresh (field-less) instance, so that
  /// non-static entry methods run — `tryExecuteClassFunction` alone omits the
  /// instance and fails for non-static methods. Mirrors that method's
  /// argument-shape variations.
  Future<ASTValue?> _tryClassMethod(
    ApolloRunner runner,
    String namespace,
    String className,
    String function,
    List<Object?> args,
  ) async {
    Future<ASTValue?> call(List positional) => runner.executeClassMethod(
      namespace,
      className,
      function,
      positionalParameters: positional,
      classInstanceFields: const {},
    );

    if (await runner.getClassMethod(namespace, className, function, args) !=
        null) {
      return call(args);
    }
    if (await runner.getClassMethod(namespace, className, function, [args]) !=
        null) {
      return call([args]);
    }
    if (await runner.getClassMethod(namespace, className, function, [
          ASTTypeArray.instanceOfString,
        ]) !=
        null) {
      return call([args.map((e) => '$e').toList()]);
    }
    if (await runner.getClassMethod(namespace, className, function, [
          ASTTypeArray.instanceOfDynamic,
        ]) !=
        null) {
      return call([args]);
    }
    return null;
  }

  /// Translates [source] from [from] to [to], returning the concatenated raw
  /// generated source (without the `<<<< SOURCES >>>>` markers).
  Future<TranslateOutcome> translate(
    String from,
    String to,
    String source,
  ) async {
    final tooLarge = _checkSource(source);
    if (tooLarge != null) return (generated: null, diagnostics: tooLarge);

    final (vm, loadDiagnostics) = await _load(from, source);
    if (vm == null) return (generated: null, diagnostics: loadDiagnostics!);

    try {
      final storage = vm.generateAllCodeIn(to);
      final buf = StringBuffer();
      for (var ns in await storage.getNamespaces()) {
        for (var id in await storage.getNamespaceCodeUnitsIDs(ns)) {
          final src = await storage.getNamespaceCodeUnit(ns, id);
          if (src != null) buf.write(src);
        }
      }
      return (generated: buf.toString(), diagnostics: const <Diagnostic>[]);
    } catch (e) {
      return (generated: null, diagnostics: [diagnosticFromError(e)]);
    }
  }

  /// Compiles [source] to WebAssembly, returning each produced module as
  /// `{name, base64}` (the module bytes, base64-encoded for JSON transport).
  Future<WasmOutcome> compileWasm(String language, String source) async {
    final tooLarge = _checkSource(source);
    if (tooLarge != null) return (modules: null, diagnostics: tooLarge);

    final (vm, loadDiagnostics) = await _load(language, source);
    if (vm == null) return (modules: null, diagnostics: loadDiagnostics!);

    try {
      final storage = vm.generateAllIn<BytesOutput>('wasm');
      final entries = await storage.allEntries();
      final modules = <Map<String, Object?>>[];
      entries.forEach((namespace, moduleMap) {
        moduleMap.forEach((moduleName, output) {
          modules.add(<String, Object?>{
            'name': moduleName,
            'base64': base64.encode(output.output()),
          });
        });
      });
      if (modules.isEmpty) {
        return (modules: null, diagnostics: [_err('No Wasm modules generated')]);
      }
      return (modules: modules, diagnostics: const <Diagnostic>[]);
    } catch (e) {
      return (modules: null, diagnostics: [diagnosticFromError(e)]);
    }
  }
}
