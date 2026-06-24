// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:swiss_knife/swiss_knife.dart';

import '../../apollovm_base.dart';
import '../../apollovm_runner.dart';
import '../../ast/apollovm_ast_toplevel.dart';
import '../../ast/apollovm_ast_type.dart';
import '../../ast/apollovm_ast_value.dart';
import 'wasm_runtime.dart';

/// WebAssembly (Wasm) implementation of an [ApolloRunner].
class ApolloRunnerWasm extends ApolloRunner {
  final _wasmRuntime = WasmRuntime();

  ApolloRunnerWasm(super.apolloVM, {super.importCorePackageMath});

  @override
  String get language => 'wasm';

  @override
  ApolloRunnerWasm copy() {
    return ApolloRunnerWasm(apolloVM);
  }

  @override
  Future<ASTValue> executeFunction(
    String namespace,
    String functionName, {
    List? positionalParameters,
    Map? namedParameters,
    bool allowClassMethod = false,
  }) async {
    var r = await getFunctionCodeUnit(
      namespace,
      functionName,
      allowClassMethod: allowClassMethod,
    );

    var codeUnit = r.codeUnit as CodeUnit<Uint8List>?;
    if (codeUnit == null) {
      throw StateError(
        "Can't find function to execute> functionName: $functionName ; language: $language",
      );
    }

    if (!_wasmRuntime.isSupported) {
      throw StateError(
        "`WasmRuntime` not supported on this platform: ${_wasmRuntime.platformVersion}",
      );
    }

    // Host imports the module may declare (only the declared ones are wired).
    WasmModule? loadedModule;
    String decodeString(int ptr) {
      var mem = loadedModule!.readMemory();
      if (mem == null) {
        throw StateError(
          "Wasm module has no exported memory to read a string.",
        );
      }
      var len =
          mem[ptr] |
          (mem[ptr + 1] << 8) |
          (mem[ptr + 2] << 16) |
          (mem[ptr + 3] << 24);
      return utf8.decode(mem.sublist(ptr + 4, ptr + 4 + len));
    }

    // Allocates `[len:i32][utf8]` for [s] in the module's memory (via the
    // exported `__alloc`) and returns its pointer.
    int allocAndWriteString(String s) {
      var m = loadedModule!;
      var bytes = utf8.encode(s);
      var ptr = m.invokeExport('__alloc', [bytes.length + 4]) as int;
      var mem = m.readMemory()!;
      mem[ptr] = bytes.length & 0xff;
      mem[ptr + 1] = (bytes.length >> 8) & 0xff;
      mem[ptr + 2] = (bytes.length >> 16) & 0xff;
      mem[ptr + 3] = (bytes.length >> 24) & 0xff;
      mem.setRange(ptr + 4, ptr + 4 + bytes.length, bytes);
      return ptr;
    }

    var hostImports = <String, Map<String, WasmHostFunction>>{
      'env': {
        'print': WasmHostFunction(
          params: const [WasmValueType.i32],
          results: const [],
          callback: (args) {
            externalPrintFunction(decodeString(args[0] as int));
            return null;
          },
        ),
        // Number-to-string, mirroring the interpreter's `'$v'` formatting.
        'int_to_str': WasmHostFunction(
          params: const [WasmValueType.i64],
          results: const [WasmValueType.i32],
          callback: (args) => allocAndWriteString('${args[0]}'),
        ),
        'double_to_str': WasmHostFunction(
          params: const [WasmValueType.f64],
          results: const [WasmValueType.i32],
          // `doubleToString` renders whole doubles as "5.0" deterministically
          // (plain `toString` yields "5" under dart2js).
          callback: (args) =>
              allocAndWriteString(ASTTypeDouble.doubleToString(args[0] as num)),
        ),
      },
    };

    var module = await _wasmRuntime.loadModule(
      codeUnit.id,
      codeUnit.code,
      hostImports: hostImports,
    );
    loadedModule = module;

    var f = module.getFunction(functionName);
    if (f == null) {
      throw StateError("Can't find function: $functionName");
    }

    var allParams = [...?positionalParameters, ...?namedParameters?.values];

    // Encode String arguments into module memory (via `__alloc`) BEFORE numeric
    // parameter resolution, which would otherwise mangle the String values. The
    // function receives the i32 pointer; String params are identified by the
    // `apollovm_sig` param tags.
    var paramTags = _signatures(codeUnit.code)[functionName]?.paramTags;
    if (paramTags != null) {
      for (var i = 0; i < allParams.length && i < paramTags.length; ++i) {
        if (paramTags[i] == _tagString && allParams[i] is String) {
          allParams[i] = allocAndWriteString(allParams[i] as String);
        }
      }
    }

    {
      var astFunction = _getASTFunction(codeUnit, functionName, allParams);
      if (astFunction != null) {
        var (allParamsNormalized, _) = normalizeParameters(
          positionalParameters: allParams,
          astFunctions: [astFunction],
        );
        allParams = allParamsNormalized ?? [];
      }
    }

    var astFunction = _getASTFunction(codeUnit, functionName, allParams);
    if (astFunction != null) {
      _resolveWasmCallParameters(astFunction, allParams);
    }

    final (function: function, varArgs: varArgs) = f;

    dynamic res;
    try {
      if (!varArgs) {
        if (function is Function(List)) {
          res = Function.apply(function, [allParams]);
        } else if (function is Function()) {
          if (allParams.isNotEmpty) {
            throw WasmModuleExecutionError(
              functionName,
              parameters: allParams,
              function: function,
              cause:
                  "Function expects no arguments, but ${allParams.length} were provided: $allParams",
            );
          }
          res = Function.apply(function, []);
        } else {
          res = Function.apply(function, allParams);
        }
      } else {
        res = Function.apply(function, allParams);
      }
    } catch (e) {
      throw WasmModuleExecutionError(
        functionName,
        parameters: allParams,
        function: function,
        cause: e,
      );
    }

    res = module.resolveReturnedValue(res, astFunction);

    // A `String` return is an i32 pointer into the module's memory; decode it.
    // The return type comes from the AST when available, else from the module's
    // `apollovm_sig` custom section (for modules loaded from raw bytes).
    var returnsString =
        astFunction?.returnType is ASTTypeString ||
        _signatures(codeUnit.code)[functionName]?.returnTag == _tagString;
    if (res != null && returnsString) {
      res = decodeString(res as int);
    }

    // A `bool` return is an i32 (0/1); decode it back to a Dart `bool`. From the
    // AST when available, else from the `apollovm_sig` custom section.
    var returnsBool =
        astFunction?.returnType is ASTTypeBool ||
        _signatures(codeUnit.code)[functionName]?.returnTag == _tagBool;
    if (res != null && returnsBool && res is! bool) {
      res = (res as num) != 0;
    }

    var astValue = res == null
        ? ASTValueNull.instance
        : ASTValue.fromValue(res);

    return astValue;
  }

  // High-level type tags from the `apollovm_sig` custom section.
  static const int _tagBool = 3;
  static const int _tagString = 4;

  /// Per-module signature cache, keyed by the wasm binary's identity.
  final Map<Uint8List, Map<String, ({int returnTag, List<int> paramTags})>>
  _signaturesCache = {};

  Map<String, ({int returnTag, List<int> paramTags})> _signatures(
    Uint8List wasmBytes,
  ) => _signaturesCache[wasmBytes] ??= _parseSignatures(wasmBytes);

  /// Parses the `apollovm_sig` custom section (function name -> return/param
  /// type tags). Returns an empty map if absent.
  static Map<String, ({int returnTag, List<int> paramTags})> _parseSignatures(
    Uint8List b,
  ) {
    var sigs = <String, ({int returnTag, List<int> paramTags})>{};
    if (b.length < 8) return sigs;

    var pos = 8; // skip magic (4) + version (4)

    int readLeb() {
      var result = 0, shift = 0;
      while (true) {
        var byte = b[pos++];
        result |= (byte & 0x7f) << shift;
        if ((byte & 0x80) == 0) break;
        shift += 7;
      }
      return result;
    }

    String readName() {
      var len = readLeb();
      var s = utf8.decode(b.sublist(pos, pos + len));
      pos += len;
      return s;
    }

    while (pos < b.length) {
      var id = b[pos++];
      var size = readLeb();
      var sectionEnd = pos + size;
      if (id == 0) {
        var name = readName();
        if (name == 'apollovm_sig') {
          var count = readLeb();
          for (var i = 0; i < count; ++i) {
            var fname = readName();
            var returnTag = b[pos++];
            var paramCount = readLeb();
            var paramTags = b.sublist(pos, pos + paramCount).toList();
            pos += paramCount;
            sigs[fname] = (returnTag: returnTag, paramTags: paramTags);
          }
        }
      }
      pos = sectionEnd;
    }

    return sigs;
  }

  void _resolveWasmCallParameters(
    ASTFunctionDeclaration astFunction,
    List parameters,
  ) {
    var astParameters = astFunction.parameters.allParameters;
    var limit = math.min(parameters.length, astParameters.length);

    for (var i = 0; i < limit; ++i) {
      var p = astParameters[i];
      var v = parameters[i];

      var v2 = _resolveParameterValueType(p, v);
      parameters[i] = v2;
    }
  }

  Object? _resolveParameterValueType(
    ASTFunctionParameterDeclaration p,
    Object? v,
  ) {
    var t = p.type;

    if (t is ASTTypeInt) {
      var n = parseInt(v);

      if (n != null && t.bits == 64) {
        return BigInt.from(n);
      } else {
        return n ?? v;
      }
    } else if (t is ASTTypeDouble) {
      var n = parseDouble(v);
      return n ?? v;
    }

    return v;
  }

  ASTFunctionDeclaration? _getASTFunction(
    CodeUnit<Uint8List> codeUnit,
    String functionName,
    List parameters,
  ) {
    var astFunctionSet = codeUnit.root?.getFunctionWithName(functionName);
    if (astFunctionSet == null) return null;

    if (astFunctionSet.functions.length <= 1) {
      return astFunctionSet.functions.firstOrNull;
    }

    var list = astFunctionSet.functions.where(
      (f) => f.parameters.size == parameters.length,
    );

    if (list.length <= 1) return list.firstOrNull;

    throw StateError(
      "Ambiguous AST functions. Can't determine function with name `$functionName` and with ${parameters.length} parameters",
    );
  }
}
