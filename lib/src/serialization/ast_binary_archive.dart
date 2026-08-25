// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:typed_data';

import 'package:data_serializer/data_serializer.dart';

import '../apollovm_base.dart';
import 'ast_binary_container.dart';
import 'ast_binary_exception.dart';
import 'ast_binary_format.dart';
import 'ast_binary_reader.dart';
import 'ast_binary_signer.dart';
import 'ast_binary_writer.dart';

/// Bundles several binary AST images into one file.
///
/// Each entry is a complete, self-contained single-unit image nested inside an
/// [ASTBinarySection.archiveEntry] section. Nesting whole images rather than
/// merging their string and type pools costs about 26 bytes per unit and buys a
/// great deal: the archive needs no decoding logic of its own, every unit keeps
/// its own checksum, and one unit can be extracted and verified without
/// touching the rest. The archive then adds its own CRC — and, optionally, its
/// own signature — over the whole thing.
class ASTBinaryArchiveWriter {
  /// Signs the archive as a whole. Entries may be signed independently.
  final ASTBinarySigner? signer;

  const ASTBinaryArchiveWriter({this.signer});

  /// Bundles the AST of every loaded code unit in [vm].
  ///
  /// With [language], only that language's units are included.
  Uint8List writeVM(ApolloVM vm, {String? language}) => writeCodeUnits(
    language == null
        ? vm.allCodeUnitsAllLanguages()
        : vm.allCodeUnits(language),
  );

  /// Bundles [codeUnits], each of which must already be loaded.
  Uint8List writeCodeUnits(Iterable<CodeUnit> codeUnits) {
    const entryWriter = ASTBinaryWriter();

    var entries = [
      for (var codeUnit in codeUnits)
        ASTBinarySectionData(
          ASTBinarySection.archiveEntry.id,
          entryWriter.writeCodeUnit(codeUnit),
        ),
    ];

    var metadata = BytesBuffer();
    metadata.writeLeb128String(ApolloVM.VERSION);
    metadata.writeLeb128UnsignedInt(entries.length);

    return ASTBinaryContainerCodec.encode(
      sections: [
        ASTBinarySectionData(ASTBinarySection.metadata.id, metadata.toBytes()),
        ...entries,
      ],
      flags: ASTBinaryFlags.archive,
      signer: signer,
    );
  }
}

/// Reads a file written by [ASTBinaryArchiveWriter].
class ASTBinaryArchiveReader {
  /// Checks the archive's own signature.
  final ASTBinaryVerifier? verifier;

  /// Checks each entry's signature.
  final ASTBinaryVerifier? entryVerifier;

  /// Whether to verify checksums. On by default.
  final bool verifyChecksum;

  const ASTBinaryArchiveReader({
    this.verifier,
    this.entryVerifier,
    this.verifyChecksum = true,
  });

  /// Whether [bytes] is an archive rather than a single-unit image.
  static bool isArchive(Uint8List bytes) {
    if (!ASTBinaryFormat.isASTBinary(bytes) ||
        bytes.length < ASTBinaryFormat.headerSize) {
      return false;
    }
    var flags =
        ((bytes[8] << 24) | (bytes[9] << 16) | (bytes[10] << 8) | bytes[11]) >>>
        0;
    return (flags & ASTBinaryFlags.archive) != 0;
  }

  /// The images this archive holds, in order, without decoding their ASTs.
  List<Uint8List> entriesOf(Uint8List bytes) {
    var container = ASTBinaryContainerCodec.decode(
      bytes,
      verifyChecksum: verifyChecksum,
      verifier: verifier,
    );

    if (!container.header.hasArchiveFlag) {
      throw ASTBinaryException(
        'This is a single binary AST image, not an archive.',
        ASTBinaryError.malformedSection,
        formatVersion: container.header.formatVersion,
      );
    }

    return [
      for (var s in container.sections)
        if (s.id == ASTBinarySection.archiveEntry.id) s.payload,
    ];
  }

  /// What each entry says about itself, without decoding its AST.
  List<ASTBinaryInfo> listEntries(Uint8List bytes) {
    var reader = ASTBinaryReader(
      verifier: entryVerifier,
      verifyChecksum: verifyChecksum,
    );
    return [for (var e in entriesOf(bytes)) reader.readInfo(e)];
  }

  /// Decodes every entry into a [CodeUnit] with its `root` populated.
  List<BinaryCodeUnit> readCodeUnits(Uint8List bytes) {
    var reader = ASTBinaryReader(
      verifier: entryVerifier,
      verifyChecksum: verifyChecksum,
    );
    return [for (var e in entriesOf(bytes)) reader.readCodeUnit(e)];
  }

  /// Decodes every entry and loads it into [vm], returning how many were
  /// loaded.
  Future<int> loadInto(ApolloVM vm, Uint8List bytes) async {
    var loaded = 0;
    for (var codeUnit in readCodeUnits(bytes)) {
      if (await vm.loadCodeUnit(codeUnit)) loaded++;
    }
    return loaded;
  }
}
