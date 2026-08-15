// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:typed_data';

import 'package:data_serializer/data_serializer.dart';

import '../apollovm_base.dart';
import '../ast/apollovm_ast_toplevel.dart';
import 'ast_binary_container.dart';
import 'ast_binary_context.dart';
import 'ast_binary_exception.dart';
import 'ast_binary_format.dart';
import 'ast_binary_pool.dart';
import 'ast_binary_signer.dart';
import 'ast_binary_type_pool.dart';

/// What a binary AST image says about itself, without decoding its AST.
class ASTBinaryInfo {
  /// The file's fixed header.
  final ASTBinaryHeader header;

  /// The `ApolloVM.VERSION` that wrote the image. Informational only — it never
  /// gates decoding; [ASTBinaryHeader.formatVersion] does.
  final String writerVersion;

  /// The language of the code unit, already normalized (`java11`, not `java`).
  final String language;

  /// The code unit id, usually a file path. May be empty.
  final String codeUnitId;

  /// The namespace the code unit belongs to.
  final String namespace;

  /// Section ids this build did not recognize and skipped.
  ///
  /// Non-empty means the image was written by a newer ApolloVM carrying
  /// information this one ignores, which is expected rather than an error.
  final List<int> unknownSectionIds;

  /// The total size of the image, in bytes.
  final int fileSize;

  const ASTBinaryInfo({
    required this.header,
    required this.writerVersion,
    required this.language,
    required this.codeUnitId,
    required this.namespace,
    required this.unknownSectionIds,
    required this.fileSize,
  });

  /// Whether the image carries a signature.
  bool get isSigned => header.isSigned;

  @override
  String toString() =>
      'ASTBinaryInfo{language: $language, namespace: $namespace, '
      'id: $codeUnitId, writer: $writerVersion, '
      'format: ${header.formatVersion}, signed: $isSigned, '
      'size: $fileSize}';
}

/// Decodes a binary AST image — `.avma`, for *Apollo Virtual Machine Archive* —
/// back into a parsed [ASTRoot].
///
/// The CRC-32 is verified on every read. It detects corruption — a truncated
/// write, bit rot, a mangled transfer — but it is not a defence against anyone:
/// an attacker who edits the file recomputes it in microseconds. Pass a
/// [verifier] to require a signature made with a key they do not have.
///
/// An unsigned image deserves exactly as much trust as the source it came from;
/// loading one and running it is equivalent to running arbitrary code from that
/// source.
class ASTBinaryReader {
  /// Checks the image's signature. When given, the image **must** be signed and
  /// the signature must verify.
  final ASTBinaryVerifier? verifier;

  /// Whether to verify the CRC-32. On by default; turning it off is for
  /// forensics and repair tooling, not for loading.
  final bool verifyChecksum;

  const ASTBinaryReader({this.verifier, this.verifyChecksum = true});

  /// Whether [bytes] looks like a binary AST image, by its magic.
  static bool isASTBinary(Uint8List bytes) =>
      ASTBinaryFormat.isASTBinary(bytes);

  /// Reads the header and metadata without decoding the AST.
  ///
  /// Cheap enough to run over a cache directory, and the basis of
  /// `apollovm inspect`.
  ASTBinaryInfo readInfo(Uint8List bytes) => _read(bytes).info;

  /// Decodes [bytes] into a fully resolved [ASTRoot].
  ///
  /// `resolveNode` has already been called on the result, so parent links and
  /// name resolution are in place exactly as after a parse.
  ASTRoot readRoot(Uint8List bytes) => _read(bytes).root;

  /// Decodes [bytes] into a [CodeUnit] whose `root` is already populated.
  ///
  /// Handing the result to [ApolloVM.loadCodeUnit] registers it without going
  /// near a parser: that method only parses when `root` is null.
  ///
  /// [id] and [namespace] override what the image recorded, for re-homing a
  /// cached unit.
  BinaryCodeUnit readCodeUnit(
    Uint8List bytes, {
    String? id,
    String? namespace,
  }) {
    var decoded = _read(bytes);
    var info = decoded.info;

    var codeUnit = BinaryCodeUnit(
      info.language,
      bytes,
      id: id ?? info.codeUnitId,
      namespace: namespace ?? info.namespace,
    );
    codeUnit.root = decoded.root;
    return codeUnit;
  }

  _DecodedImage _read(Uint8List bytes) {
    var container = ASTBinaryContainerCodec.decode(
      bytes,
      verifyChecksum: verifyChecksum,
      verifier: verifier,
    );

    var formatVersion = container.header.formatVersion;

    var metadata = BytesBuffer.from(
      container.requirePayloadOf(ASTBinarySection.metadata),
    );

    String writerVersion;
    String language;
    String codeUnitId;
    String namespace;
    try {
      writerVersion = metadata.readLeb128String();
      language = metadata.readLeb128String();
      codeUnitId = metadata.readLeb128String();
      namespace = metadata.readLeb128String();
      // Anything a newer writer appended past here is deliberately ignored:
      // the section is read from a bounded view, so trailing fields are extra
      // information rather than a decode failure.
    } catch (e) {
      throw ASTBinaryException(
        'Malformed metadata section: $e',
        ASTBinaryError.malformedSection,
        formatVersion: formatVersion,
        sectionId: ASTBinarySection.metadata.id,
      );
    }

    var info = ASTBinaryInfo(
      header: container.header,
      writerVersion: writerVersion,
      language: language,
      codeUnitId: codeUnitId,
      namespace: namespace,
      unknownSectionIds: container.unknownSectionIds,
      fileSize: bytes.length,
    );

    var strings = ASTStringPoolReader.decode(
      container.requirePayloadOf(ASTBinarySection.stringTable),
    );
    var types = ASTTypePoolReader.decode(
      container.requirePayloadOf(ASTBinarySection.typeTable),
      strings,
    );

    var ast = ASTBinaryReadContext(
      BytesBuffer.from(container.requirePayloadOf(ASTBinarySection.astRoot)),
      strings,
      types,
      formatVersion: formatVersion,
    );

    var root = ast.node<ASTRoot>();

    // Exactly what every grammar does after building a tree. Parent links,
    // scope-variable resolution, superclass and extension targets, and the
    // `this.field` constructor-parameter promotion are all re-derived here,
    // which is why none of them are stored in the file.
    root.resolveNode(null);

    return _DecodedImage(info, root);
  }
}

class _DecodedImage {
  final ASTBinaryInfo info;
  final ASTRoot root;

  _DecodedImage(this.info, this.root);
}
