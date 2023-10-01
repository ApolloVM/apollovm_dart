// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:typed_data';

import '../../apollovm_base.dart';
import '../../apollovm_runner.dart';
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

    var res = Function.apply(f, allParams);

    var astValue =
        res == null ? ASTValueNull.instance : ASTValue.fromValue(res);

    return astValue;
  }
}
