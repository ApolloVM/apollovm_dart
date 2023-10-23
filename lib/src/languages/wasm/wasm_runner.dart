// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

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

  ApolloRunnerWasm(ApolloVM apolloVM) : super(apolloVM);

  @override
  String get language => 'wasm';

  @override
  ApolloRunnerWasm copy() {
    return ApolloRunnerWasm(apolloVM);
  }

  @override
  Future<ASTValue> executeFunction(String namespace, String functionName,
      {List? positionalParameters,
      Map? namedParameters,
      bool allowClassMethod = false}) async {
    var r = await getFunctionCodeUnit(namespace, functionName,
        allowClassMethod: allowClassMethod);

    var codeUnit = r.codeUnit as CodeUnit<Uint8List>?;
    if (codeUnit == null) {
      throw StateError(
          "Can't find function to execute> functionName: $functionName ; language: $language");
    }

    if (!_wasmRuntime.isSupported) {
      throw StateError(
          "`WasmRuntime` not supported on this platform: ${_wasmRuntime.platformVersion}");
    }

    var module = await _wasmRuntime.loadModule(codeUnit.id, codeUnit.code);

    var f = module.getFunction(functionName);
    if (f == null) {
      throw StateError("Can't find function: $functionName");
    }

    var allParams = [
      ...?positionalParameters,
      ...?namedParameters?.values,
    ];

    var astFunction = _getASTFunction(codeUnit, functionName, allParams);
    if (astFunction != null) {
      _resolveWasmCallParameters(astFunction, allParams);
    }

    dynamic res;
    try {
      res = Function.apply(f, allParams);
    } catch (e) {
      throw WasmModuleExecutionError(functionName,
          parameters: allParams, function: f, cause: e);
    }

    res = module.resolveReturnedValue(res, astFunction);

    var astValue =
        res == null ? ASTValueNull.instance : ASTValue.fromValue(res);

    return astValue;
  }

  void _resolveWasmCallParameters(
      ASTFunctionDeclaration astFunction, List parameters) {
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
      ASTFunctionParameterDeclaration p, Object? v) {
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
      CodeUnit<Uint8List> codeUnit, String functionName, List parameters) {
    var astFunctionSet = codeUnit.root?.getFunctionWithName(functionName);
    if (astFunctionSet == null) return null;

    if (astFunctionSet.functions.length <= 1) {
      return astFunctionSet.functions.firstOrNull;
    }

    var list = astFunctionSet.functions
        .where((f) => f.parameters.size == parameters.length);

    if (list.length <= 1) return list.firstOrNull;

    throw StateError(
        "Ambiguous AST functions. Can't determine function with name `$functionName` and with ${parameters.length} parameters");
  }
}
