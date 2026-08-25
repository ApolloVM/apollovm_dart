// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:typed_data';

import '../apollovm_base.dart';
import 'ast_binary_archive.dart';
import 'ast_binary_reader.dart';
import 'ast_binary_signer.dart';
import 'ast_binary_writer.dart';

/// Binary AST convenience methods on [ApolloVM].
///
/// Thin wrappers over [ASTBinaryWriter], [ASTBinaryReader] and the archive
/// pair; reach for those directly when more control is wanted.
extension ApolloVMBinaryAST on ApolloVM {
  /// Encodes the AST of [codeUnit], which must already be loaded.
  Uint8List saveCodeUnitAST(CodeUnit codeUnit, {ASTBinarySigner? signer}) =>
      ASTBinaryWriter(signer: signer).writeCodeUnit(codeUnit);

  /// Decodes a binary AST image and loads it, skipping the parser entirely.
  ///
  /// This goes through the ordinary [ApolloVM.loadCodeUnit], which only parses
  /// when a code unit has no AST yet — so namespace registration, the
  /// null-safety check and incremental-resolution invalidation all behave
  /// exactly as they do for parsed source.
  ///
  /// Pass a [verifier] to require the image be signed with a key it accepts.
  /// Without one, a signed image still loads and its signature is not checked.
  Future<bool> loadCodeUnitAST(
    Uint8List image, {
    ASTBinaryVerifier? verifier,
    String? id,
    String? namespace,
  }) {
    var codeUnit = ASTBinaryReader(
      verifier: verifier,
    ).readCodeUnit(image, id: id, namespace: namespace);

    return loadCodeUnit(codeUnit);
  }

  /// Bundles the AST of every loaded code unit into a single archive.
  ///
  /// With [language], only that language's units are included.
  Uint8List saveAllAST({String? language, ASTBinarySigner? signer}) =>
      ASTBinaryArchiveWriter(signer: signer).writeVM(this, language: language);

  /// Loads every code unit in an archive, returning how many were loaded.
  Future<int> loadAllAST(
    Uint8List archive, {
    ASTBinaryVerifier? verifier,
    ASTBinaryVerifier? entryVerifier,
  }) => ASTBinaryArchiveReader(
    verifier: verifier,
    entryVerifier: entryVerifier,
  ).loadInto(this, archive);
}

/// Binary AST convenience methods on [CodeUnit].
extension CodeUnitBinaryAST on CodeUnit {
  /// Encodes this unit's AST. Throws a [StateError] when it has not been
  /// loaded.
  Uint8List toBinaryAST({ASTBinarySigner? signer}) =>
      ASTBinaryWriter(signer: signer).writeCodeUnit(this);
}
