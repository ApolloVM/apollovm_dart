// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:data_serializer/data_serializer.dart';

import '../../apollovm_base.dart';
import '../../apollovm_parser.dart';
import '../../ast/apollovm_ast_toplevel.dart';
import '../../ast/apollovm_ast_type.dart';
import 'wasm.dart';

/// Dart implementation of an [ApolloParser].
/// - This only parses the exported [Function]s into an [ASTRoot],
///   so that the [ApolloRunnerWasm] can know what functions can be called.
/// - There are NO plans to parse the entire Wasm code into an full AST tree
///   because decompiling it in this way is not an efficient process.
class ApolloParserWasm extends ApolloCodeParser<Uint8List> {
  static final ApolloParserWasm instance = ApolloParserWasm();

  ApolloParserWasm() : super();

  @override
  String get language => 'wasm';

  @override
  Future<ParseResult<Uint8List>> parse(CodeUnit<Uint8List> codeUnit) async {
    var bytes = BytesBuffer.from(codeUnit.code);

    bytes.seek(0);

    var magic = bytes.readBytes(4);
    if (!magic.equals(Wasm.magicModuleHeader.asUint8List)) {
      throw StateError("Binary not starting with Wasm magic!");
    }

    var version = bytes.readBytes(4);
    if (!version.equals(Wasm.moduleVersion.asUint8List)) {
      throw StateError("Binary version unsupported: $version");
    }

    List<_TypeFunction>? typeFunctions;
    List<ASTFunctionDeclaration>? astFunctions;

    while (bytes.remaining > 0) {
      var sectionID = bytes.readByte();
      var block = bytes.readLeb128Block();

      // Section Type:
      if (sectionID == 0x01) {
        typeFunctions = _parseSectionType(block);
      }
      // Section Export:
      else if (sectionID == 0x07) {
        astFunctions = _parseSectionExport(block, typeFunctions);
      }
    }

    var astRoot = ASTRoot();

    if (astFunctions != null) {
      astRoot.addAllFunctions(astFunctions);
    }

    var parseResult = ParseResult<Uint8List>(codeUnit, root: astRoot);
    return parseResult;
  }

  List<_TypeFunction> _parseSectionType(Uint8List block) {
    var bytes = BytesBuffer.from(block);

    var count = bytes.readLeb128UnsignedInt();

    var typeFunctions = <_TypeFunction>[];

    for (var i = 0; i < count; ++i) {
      var type = bytes.readByte();

      // Function:
      if (type == 96) {
        var parameters = bytes.readLeb128Block();
        var results = bytes.readLeb128Block();

        typeFunctions.add(_TypeFunction(parameters, results));
      }
    }

    return typeFunctions;
  }

  List<ASTFunctionDeclaration> _parseSectionExport(
      Uint8List block, List<_TypeFunction>? typeFunctions) {
    typeFunctions ??= [];

    var bytes = BytesBuffer.from(block);

    var count = bytes.readLeb128UnsignedInt();

    var functions = <ASTFunctionDeclaration>[];

    for (var i = 0; i < count; ++i) {
      var name = bytes.readLeb128String();
      var type = bytes.readByte();
      var index = bytes.readLeb128UnsignedInt();

      // Function:
      if (type == 0) {
        var typeFunction = typeFunctions[index];

        var astParameters = typeFunction.toASTParametersDeclaration();

        var astReturn = typeFunction.results.toASTTypes().firstOrNull ??
            ASTTypeVoid.instance;

        var astFunction =
            ASTFunctionDeclaration(name, astParameters, astReturn);

        functions.add(astFunction);
      }
    }

    return functions;
  }
}

class _TypeFunction {
  List<int> parameters;

  List<int> results;

  _TypeFunction(this.parameters, this.results);

  List<ASTFunctionParameterDeclaration> toASTFunctionParameterDeclaration() =>
      parameters
          .mapIndexed((i, p) =>
              ASTFunctionParameterDeclaration(p.toASTType(), 'p$i', i, false))
          .toList();

  ASTParametersDeclaration toASTParametersDeclaration() =>
      ASTParametersDeclaration(toASTFunctionParameterDeclaration());
}

extension _ListIntExtension on List<int> {
  List<ASTType> toASTTypes() => map((t) => t.toASTType()).toList();
}

final _astTypeInt32 = ASTTypeInt(bits: 32);
final _astTypeInt64 = ASTTypeInt(bits: 64);
final _astTypeDouble32 = ASTTypeDouble(bits: 32);
final _astTypeDouble64 = ASTTypeDouble(bits: 64);

extension _IntExtension on int {
  ASTType toASTType() {
    final t = this;

    if (t == WasmType.i32Type.value) {
      return _astTypeInt32;
    } else if (t == WasmType.i64Type.value) {
      return _astTypeInt64;
    } else if (t == WasmType.f32Type.value) {
      return _astTypeDouble32;
    } else if (t == WasmType.f64Type.value) {
      return _astTypeDouble64;
    } else {
      throw StateError("Can't handle type: $t");
    }
  }
}
