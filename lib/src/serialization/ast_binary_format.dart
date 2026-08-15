// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:typed_data';

/// Constants describing the ApolloVM binary AST container format.
///
/// A binary AST file (`.avma`) stores an already-parsed [ASTRoot] so that a
/// code unit can be loaded without running a parser. The layout is:
///
/// ```text
/// offset  size  field
///  0       4    magic             \0AVM
///  4       2    formatVersion     uint16 BE — the container revision that wrote this file
///  6       2    minReaderVersion  uint16 BE — oldest reader that can decode it correctly
///  8       4    flags             uint32 BE — see [ASTBinaryFlags]
/// 12       4    sectionsSize      uint32 BE — byte length of the section stream
/// 16      ..    sections          repeated: leb128 id, leb128 size, size bytes
///  T+0     4    crc32             uint32 BE — over bytes [0, T)
///  T+4     2    signatureLength   uint16 BE — 0 when unsigned
///  T+6    ..    signature         signatureLength bytes
///  ..      4    trailerMagic      AVM\0
/// ```
///
/// where `T = headerSize + sectionsSize`. The total file length is always
/// `headerSize + sectionsSize + minTrailerSize + signatureLength`, which lets a
/// reader detect truncation and trailing garbage structurally, before doing any
/// integrity arithmetic.
///
/// Every fixed-width field is big-endian. Sections are length-prefixed, so a
/// reader skips any section id it does not recognize — that is what lets a file
/// written by a newer ApolloVM keep loading in an older one.
class ASTBinaryFormat {
  ASTBinaryFormat._();

  /// File magic: `\0AVM`. The leading NUL marks the file as binary so no tool
  /// mistakes it for text, in the spirit of WebAssembly's `\0asm`.
  static const List<int> magic = [0x00, 0x41, 0x56, 0x4D];

  /// Trailer magic: `AVM\0` (the [magic] reversed).
  ///
  /// It turns a truncated or garbage file into an accurate "truncated"
  /// diagnostic instead of a confusing checksum mismatch.
  static const List<int> trailerMagic = [0x41, 0x56, 0x4D, 0x00];

  /// The container revision this build writes, and the newest it fully
  /// understands.
  static const int version = 1;

  /// The oldest container revision this build can still read.
  static const int minSupportedVersion = 1;

  /// Size of the fixed header, in bytes.
  static const int headerSize = 16;

  /// Size of the trailer excluding the signature: crc32 + signatureLength +
  /// [trailerMagic].
  static const int minTrailerSize = 10;

  /// The conventional file extension, without a leading dot.
  static const String fileExtension = 'avma';

  /// The largest section stream this format can address (`sectionsSize` is a
  /// uint32).
  static const int maxSectionsSize = 0xFFFFFFFF;

  /// The largest signature this format can hold (`signatureLength` is a
  /// uint16).
  static const int maxSignatureLength = 0xFFFF;

  /// Whether [bytes] begins with the binary AST [magic].
  ///
  /// A cheap sniff for callers that dispatch on content rather than on a file
  /// extension. It says nothing about whether the rest of the file is valid.
  static bool isASTBinary(Uint8List bytes) {
    if (bytes.length < magic.length) return false;
    for (var i = 0; i < magic.length; ++i) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }

  /// Compares [a] and [b] without an early exit on the first differing byte.
  ///
  /// Use this when comparing a computed signature against one read from a file:
  /// a plain element-by-element comparison returns sooner for a nearly-correct
  /// guess, which leaks how much of the signature an attacker got right.
  ///
  /// The comparison is constant-time only for equal-length inputs; a length
  /// mismatch is reported immediately, since the length is not a secret.
  static bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; ++i) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

/// Bit flags in the binary AST header.
///
/// Unlike an unknown section — which a reader skips — an unknown flag bit is
/// **rejected**. Flags are reserved for options that change how the payload
/// must be interpreted, so ignoring one would mean mis-decoding. Purely
/// additive information belongs in a new section instead.
class ASTBinaryFlags {
  ASTBinaryFlags._();

  /// A signature is present in the trailer.
  static const int signed = 0x00000001;

  /// A [ASTBinarySection.sectionIndex] section is present.
  static const int hasSectionIndex = 0x00000002;

  /// A [ASTBinarySection.sourceRef] section is present.
  static const int hasSourceRef = 0x00000004;

  /// The file is an archive of several code units rather than a single one.
  static const int archive = 0x00000008;

  /// Every flag bit this build understands.
  static const int knownMask =
      signed | hasSectionIndex | hasSourceRef | archive;
}

/// Section identifiers in the binary AST section stream.
///
/// Ids are never reused. A reader skips any id it does not know, using the
/// section's length prefix.
enum ASTBinarySection {
  /// An application-defined section, always ignored by ApolloVM.
  ///
  /// Payload: a LEB128-prefixed name, then arbitrary bytes. Mirrors
  /// WebAssembly's custom section, and lets third parties attach data without
  /// registering an id.
  custom(0x00),

  /// Language, namespace, code unit id and writer provenance. Required, and
  /// must be the first section.
  metadata(0x01),

  /// The shared string pool that the AST section indexes into.
  stringTable(0x02),

  /// The pooled [ASTType] descriptors that the AST section indexes into.
  typeTable(0x03),

  /// The encoded [ASTRoot]. Required.
  astRoot(0x04),

  /// Length and CRC-32 of the source this file was produced from, so a caller
  /// can tell whether a cached image is stale without decoding it.
  sourceRef(0x05),

  /// Offsets and sizes of the other sections, for random access.
  sectionIndex(0x06),

  /// One code unit of an archive: a complete, self-contained single-unit image.
  ///
  /// Nesting whole images rather than merging their pools means an archive
  /// needs no decoding logic of its own — each entry is read by the ordinary
  /// reader — and each unit keeps its own checksum, so one can be extracted
  /// and verified without touching the rest.
  archiveEntry(0x07);

  const ASTBinarySection(this.id);

  /// The on-disk identifier for this section.
  final int id;

  /// The section with the given [id], or `null` when this build does not know
  /// it (in which case the reader skips it).
  static ASTBinarySection? byId(int id) {
    for (var s in values) {
      if (s.id == id) return s;
    }
    return null;
  }
}
