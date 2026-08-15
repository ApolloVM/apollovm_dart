// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:typed_data';

import 'package:data_serializer/data_serializer.dart';

import 'ast_binary_exception.dart';
import 'ast_binary_format.dart';
import 'ast_binary_signer.dart';
import 'crc32.dart';

/// One section of a binary AST file: an identifier and its payload.
///
/// The container treats every payload as opaque bytes; only the sections'
/// framing is its concern.
class ASTBinarySectionData {
  /// The section identifier. See [ASTBinarySection] for the ones this build
  /// knows; any other id is carried through and skipped on read.
  final int id;

  /// The section's bytes, excluding its id and length prefix.
  final Uint8List payload;

  const ASTBinarySectionData(this.id, this.payload);

  /// The known section this id maps to, or `null` when unrecognized.
  ASTBinarySection? get section => ASTBinarySection.byId(id);

  @override
  String toString() =>
      'ASTBinarySectionData{id: $id (${section?.name ?? 'unknown'}), '
      'size: ${payload.length}}';
}

/// The fixed header of a binary AST file.
class ASTBinaryHeader {
  /// The container revision that wrote this file.
  final int formatVersion;

  /// The oldest container revision that can decode this file correctly.
  final int minReaderVersion;

  /// The header flag bits. See [ASTBinaryFlags].
  final int flags;

  /// Byte length of the section stream.
  final int sectionsSize;

  const ASTBinaryHeader({
    required this.formatVersion,
    required this.minReaderVersion,
    required this.flags,
    required this.sectionsSize,
  });

  /// Whether a signature is present in the trailer.
  bool get isSigned => (flags & ASTBinaryFlags.signed) != 0;

  /// Whether a section index is present.
  bool get hasSectionIndex => (flags & ASTBinaryFlags.hasSectionIndex) != 0;

  /// Whether a source reference is present.
  bool get hasSourceRef => (flags & ASTBinaryFlags.hasSourceRef) != 0;

  @override
  String toString() =>
      'ASTBinaryHeader{formatVersion: $formatVersion, '
      'minReaderVersion: $minReaderVersion, '
      'flags: 0x${flags.toRadixString(16).padLeft(8, '0')}, '
      'sectionsSize: $sectionsSize}';
}

/// A decoded binary AST container: its header, its sections, and whichever
/// section ids this build did not recognize.
class ASTBinaryContainer {
  /// The file's fixed header.
  final ASTBinaryHeader header;

  /// Every section, in the order it appeared.
  final List<ASTBinarySectionData> sections;

  /// The signature from the trailer, or `null` when the file is unsigned.
  final Uint8List? signature;

  ASTBinaryContainer(this.header, this.sections, this.signature);

  /// Section ids this build does not know and therefore skipped.
  ///
  /// A non-empty list means the file was written by a newer ApolloVM carrying
  /// information this one ignores — which is expected, not an error.
  List<int> get unknownSectionIds => [
    for (var s in sections)
      if (s.section == null) s.id,
  ];

  /// The payload of the first section with [id], or `null` when absent.
  Uint8List? payloadOf(ASTBinarySection id) {
    for (var s in sections) {
      if (s.id == id.id) return s.payload;
    }
    return null;
  }

  /// The payload of the first section with [id].
  ///
  /// Throws an [ASTBinaryException] with [ASTBinaryError.malformedSection] when
  /// the section is absent.
  Uint8List requirePayloadOf(ASTBinarySection id) {
    var payload = payloadOf(id);
    if (payload == null) {
      throw ASTBinaryException(
        'Missing required section `${id.name}`.',
        ASTBinaryError.malformedSection,
        sectionId: id.id,
        formatVersion: header.formatVersion,
      );
    }
    return payload;
  }
}

/// Frames sections into the binary AST container layout, and reads them back.
///
/// This layer knows nothing about the AST: it owns the magic, the versions, the
/// section framing, the CRC-32 and the signature. See [ASTBinaryFormat] for the
/// byte layout.
class ASTBinaryContainerCodec {
  ASTBinaryContainerCodec._();

  /// Assembles [sections] into a complete binary AST file.
  ///
  /// When [signer] is given, the header's [ASTBinaryFlags.signed] bit is set and
  /// the signature is appended to the trailer.
  static Uint8List encode({
    required List<ASTBinarySectionData> sections,
    int formatVersion = ASTBinaryFormat.version,
    int minReaderVersion = ASTBinaryFormat.version,
    int flags = 0,
    ASTBinarySigner? signer,
  }) {
    if (signer != null) flags |= ASTBinaryFlags.signed;

    var stream = BytesBuffer();
    for (var s in sections) {
      stream.writeLeb128UnsignedInt(s.id);
      stream.writeLeb128UnsignedInt(s.payload.length);
      stream.writeAllBytes(s.payload);
    }
    var streamBytes = stream.toBytes();

    if (streamBytes.length > ASTBinaryFormat.maxSectionsSize) {
      throw StateError(
        'Binary AST section stream is ${streamBytes.length} bytes, over the '
        '${ASTBinaryFormat.maxSectionsSize} byte format limit.',
      );
    }

    var out = BytesBuffer();
    out.writeAll(ASTBinaryFormat.magic);
    out.writeUint16(formatVersion);
    out.writeUint16(minReaderVersion);
    out.writeUint32(flags);
    out.writeUint32(streamBytes.length);
    out.writeAllBytes(streamBytes);

    // The CRC covers the header and every section, so tampering with a version,
    // a flag or a payload is all detected by the same check.
    var crc = Crc32.compute(out.toBytes());
    out.writeUint32(crc);

    if (signer == null) {
      out.writeUint16(0);
    } else {
      // The signature covers everything up to and including the CRC, so an
      // attacker who edits a section and recomputes the CRC still fails
      // verification. It deliberately stops before `signatureLength`, which is
      // not known until the signature exists; substituting that length instead
      // breaks the exact file-length check the reader does first.
      var signature = signer.sign(out.toBytes());

      if (signature.isEmpty ||
          signature.length > ASTBinaryFormat.maxSignatureLength) {
        throw StateError(
          'Signature is ${signature.length} bytes; must be 1..'
          '${ASTBinaryFormat.maxSignatureLength}.',
        );
      }

      out.writeUint16(signature.length);
      out.writeAllBytes(signature);
    }

    out.writeAll(ASTBinaryFormat.trailerMagic);

    return out.toBytes();
  }

  /// Parses [bytes] into a container, verifying its structure and integrity.
  ///
  /// The CRC-32 is checked unless [verifyChecksum] is `false` (an escape hatch
  /// for forensics and repair tooling, not for normal loading).
  ///
  /// When [verifier] is given, the file's signature must be present and valid.
  /// A signed file read *without* a verifier still loads — the signature is
  /// simply not checked, and [ASTBinaryHeader.isSigned] reports that it was
  /// there.
  static ASTBinaryContainer decode(
    Uint8List bytes, {
    bool verifyChecksum = true,
    ASTBinaryVerifier? verifier,
  }) {
    if (!ASTBinaryFormat.isASTBinary(bytes)) {
      throw ASTBinaryException(
        bytes.length < ASTBinaryFormat.magic.length
            ? 'Not a binary AST file: only ${bytes.length} bytes.'
            : 'Not a binary AST file: bad magic.',
        bytes.length < ASTBinaryFormat.magic.length
            ? ASTBinaryError.truncated
            : ASTBinaryError.badMagic,
        offset: 0,
      );
    }

    if (bytes.length < ASTBinaryFormat.headerSize) {
      throw ASTBinaryException(
        'Truncated binary AST file: ${bytes.length} bytes, header needs '
        '${ASTBinaryFormat.headerSize}.',
        ASTBinaryError.truncated,
        offset: bytes.length,
      );
    }

    var formatVersion = _uint16(bytes, 4);
    var minReaderVersion = _uint16(bytes, 6);
    var flags = _uint32(bytes, 8);
    var sectionsSize = _uint32(bytes, 12);

    if (minReaderVersion > ASTBinaryFormat.version) {
      throw ASTBinaryException(
        'This binary AST file needs a reader for format version '
        '$minReaderVersion; this build reads up to '
        '${ASTBinaryFormat.version}.',
        ASTBinaryError.unsupportedVersion,
        formatVersion: formatVersion,
        minReaderVersion: minReaderVersion,
      );
    }

    if (formatVersion < ASTBinaryFormat.minSupportedVersion) {
      throw ASTBinaryException(
        'Binary AST format version $formatVersion is older than the oldest '
        'supported (${ASTBinaryFormat.minSupportedVersion}).',
        ASTBinaryError.unsupportedVersion,
        formatVersion: formatVersion,
        minReaderVersion: minReaderVersion,
      );
    }

    // An unknown *flag* changes how the payload must be read, so it is refused;
    // an unknown *section* is merely extra information, so it is skipped.
    var unknownFlags = flags & ~ASTBinaryFlags.knownMask;
    if (unknownFlags != 0) {
      throw ASTBinaryException(
        'Binary AST header sets unknown flags '
        '0x${unknownFlags.toRadixString(16).padLeft(8, '0')}.',
        ASTBinaryError.unknownFlags,
        offset: 8,
        formatVersion: formatVersion,
        minReaderVersion: minReaderVersion,
      );
    }

    var trailerStart = ASTBinaryFormat.headerSize + sectionsSize;
    if (bytes.length < trailerStart + ASTBinaryFormat.minTrailerSize) {
      throw ASTBinaryException(
        'Truncated binary AST file: ${bytes.length} bytes, but the header '
        'declares $sectionsSize bytes of sections.',
        ASTBinaryError.truncated,
        offset: bytes.length,
        formatVersion: formatVersion,
      );
    }

    var signatureLength = _uint16(bytes, trailerStart + 4);
    var expectedLength =
        trailerStart + ASTBinaryFormat.minTrailerSize + signatureLength;

    if (bytes.length != expectedLength) {
      throw ASTBinaryException(
        'Binary AST file is ${bytes.length} bytes; its header and trailer '
        'describe exactly $expectedLength.',
        ASTBinaryError.truncated,
        offset: expectedLength,
        formatVersion: formatVersion,
      );
    }

    var trailerMagicOffset =
        expectedLength - ASTBinaryFormat.trailerMagic.length;
    for (var i = 0; i < ASTBinaryFormat.trailerMagic.length; ++i) {
      if (bytes[trailerMagicOffset + i] != ASTBinaryFormat.trailerMagic[i]) {
        throw ASTBinaryException(
          'Binary AST file has a bad trailer magic; it is truncated or was '
          'concatenated with other data.',
          ASTBinaryError.truncated,
          offset: trailerMagicOffset,
          formatVersion: formatVersion,
        );
      }
    }

    if (verifyChecksum) {
      var expected = _uint32(bytes, trailerStart);
      var actual = Crc32.compute(bytes, 0, trailerStart);
      if (expected != actual) {
        throw ASTBinaryIntegrityException(
          'Binary AST checksum mismatch: file declares '
          '0x${expected.toRadixString(16)}, content is '
          '0x${actual.toRadixString(16)}. The file is corrupted or was '
          'modified.',
          ASTBinaryError.checksumMismatch,
          offset: trailerStart,
          formatVersion: formatVersion,
        );
      }
    }

    var isSigned = (flags & ASTBinaryFlags.signed) != 0;
    Uint8List? signature;
    if (isSigned) {
      signature = _slice(bytes, trailerStart + 6, signatureLength);
    }

    if (verifier != null) {
      if (!isSigned || signature == null) {
        throw ASTBinaryIntegrityException(
          'Binary AST file is unsigned, but a verifier was supplied. Refusing '
          'to load it as verified.',
          ASTBinaryError.signatureMissing,
          formatVersion: formatVersion,
        );
      }

      var signaturePayload = _slice(bytes, 0, trailerStart + 4);
      if (!verifier.verify(signaturePayload, signature)) {
        throw ASTBinaryIntegrityException(
          'Binary AST signature is not valid for this content and key.',
          ASTBinaryError.signatureMismatch,
          offset: trailerStart + 6,
          formatVersion: formatVersion,
        );
      }
    }

    var header = ASTBinaryHeader(
      formatVersion: formatVersion,
      minReaderVersion: minReaderVersion,
      flags: flags,
      sectionsSize: sectionsSize,
    );

    var sections = _decodeSections(
      bytes,
      ASTBinaryFormat.headerSize,
      sectionsSize,
      formatVersion,
    );

    return ASTBinaryContainer(header, sections, signature);
  }

  static List<ASTBinarySectionData> _decodeSections(
    Uint8List bytes,
    int start,
    int size,
    int formatVersion,
  ) {
    var sections = <ASTBinarySectionData>[];
    var end = start + size;
    var stream = BytesBuffer.from(_slice(bytes, start, size));

    while (stream.remaining > 0) {
      var sectionStart = start + stream.position;

      int id;
      int payloadSize;
      try {
        id = stream.readLeb128UnsignedInt();
        payloadSize = stream.readLeb128UnsignedInt();
      } catch (e) {
        throw ASTBinaryException(
          'Malformed section framing: $e',
          ASTBinaryError.malformedSection,
          offset: sectionStart,
          formatVersion: formatVersion,
        );
      }

      if (payloadSize < 0 || payloadSize > stream.remaining) {
        throw ASTBinaryException(
          'Section $id declares a $payloadSize byte payload, but only '
          '${stream.remaining} bytes remain before the end of the section '
          'stream (offset $end).',
          ASTBinaryError.truncated,
          offset: sectionStart,
          formatVersion: formatVersion,
          sectionId: id,
        );
      }

      // Every payload is length-prefixed, so an id this build does not know is
      // simply carried through — that is what keeps newer files readable.
      var payload = _slice(bytes, start + stream.position, payloadSize);
      stream.seek(stream.position + payloadSize);

      sections.add(ASTBinarySectionData(id, payload));
    }

    return sections;
  }

  /// A zero-copy view of `[start, start+length)` of [bytes].
  ///
  /// Goes through [Uint8List.offsetInBytes] deliberately: [bytes] may itself be
  /// a view into a larger buffer, and `bytes.buffer.asUint8List(start, …)`
  /// would then silently read from the wrong place.
  static Uint8List _slice(Uint8List bytes, int start, int length) {
    RangeError.checkValidRange(start, start + length, bytes.length);
    return Uint8List.view(bytes.buffer, bytes.offsetInBytes + start, length);
  }

  static int _uint16(Uint8List b, int o) => (b[o] << 8) | b[o + 1];

  static int _uint32(Uint8List b, int o) =>
      ((b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]) >>> 0;
}
