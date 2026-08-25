// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:typed_data';

import 'package:data_serializer/data_serializer.dart';

import '../apollovm_base.dart';
import '../apollovm_generated_output.dart';
import '../ast/apollovm_ast_toplevel.dart';
import 'ast_binary_container.dart';
import 'ast_binary_context.dart';
import 'ast_binary_format.dart';
import 'ast_binary_pool.dart';
import 'ast_binary_signer.dart';
import 'ast_binary_type_pool.dart';

/// Encodes a parsed [ASTRoot] into a binary AST image — `.avma`, for *Apollo
/// Virtual Machine Archive*.
///
/// The point of the format is to skip the parser: an application parses once —
/// at build time, or on first run — and afterwards loads the same code unit by
/// decoding bytes, with no grammar and no backtracking.
///
/// ```dart
/// var bytes = ASTBinaryWriter().writeCodeUnit(codeUnit);
/// ```
///
/// Output is deterministic: the same AST always produces the same bytes, so an
/// image can be content-addressed or compared byte for byte. Nothing
/// time-dependent is recorded.
///
/// Signing is optional and pluggable — see [ASTBinarySigner]. Without it the
/// image still carries a CRC-32, which detects corruption but proves nothing
/// against a deliberate edit.
class ASTBinaryWriter {
  /// Signs the image, when tamper-evidence is wanted.
  final ASTBinarySigner? signer;

  const ASTBinaryWriter({this.signer});

  /// Encodes the AST of [codeUnit], which must already be loaded.
  ///
  /// Throws a [StateError] when `codeUnit.root` is `null` — the same contract
  /// as [CodeUnit.generateCode].
  Uint8List writeCodeUnit(CodeUnit codeUnit) {
    var root = codeUnit.root;
    if (root == null) {
      throw StateError(
        "Can't write a binary AST for a `CodeUnit` that has not been loaded: "
        '${codeUnit.id} (${codeUnit.language})',
      );
    }

    return writeRoot(
      root,
      language: codeUnit.language,
      namespace: codeUnit.namespace ?? root.namespace,
      id: codeUnit.id,
    );
  }

  /// Encodes [root] directly.
  ///
  /// [language] is recorded so the image knows which runner to use; pass the
  /// parser's own language id (`java11`, not the `java` alias), since a
  /// deserialized unit never goes through a parser to have it normalized.
  Uint8List writeRoot(
    ASTRoot root, {
    required String language,
    String? namespace,
    String id = '',
  }) {
    var strings = ASTStringPoolWriter();
    var types = ASTTypePoolWriter(strings);
    var ast = ASTBinaryWriteContext(strings, types);

    // The AST is encoded first: it is what fills the pools, and the pool
    // sections have to be written already complete.
    ast.node(root);
    var astBytes = ast.toBytes();

    var metadata = BytesBuffer();
    metadata.writeLeb128String(ApolloVM.VERSION);
    metadata.writeLeb128String(language);
    metadata.writeLeb128String(id);
    metadata.writeLeb128String(namespace ?? root.namespace);

    return ASTBinaryContainerCodec.encode(
      sections: [
        ASTBinarySectionData(ASTBinarySection.metadata.id, metadata.toBytes()),
        ASTBinarySectionData(ASTBinarySection.stringTable.id, strings.encode()),
        ASTBinarySectionData(ASTBinarySection.typeTable.id, types.encode()),
        ASTBinarySectionData(ASTBinarySection.astRoot.id, astBytes),
      ],
      signer: signer,
    );
  }

  /// Encodes [codeUnit] as an annotated [BytesOutput].
  ///
  /// `toString()` on the result is a section-labelled hexdump, which is how a
  /// format problem actually gets diagnosed. The bytes are identical to
  /// [writeCodeUnit].
  BytesOutput writeCodeUnitOutput(CodeUnit codeUnit) {
    var bytes = writeCodeUnit(codeUnit);
    return BytesOutput(data: bytes, description: 'Binary AST: ${codeUnit.id}');
  }
}
