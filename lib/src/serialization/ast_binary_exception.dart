// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

/// Why a binary AST file could not be read.
enum ASTBinaryError {
  /// The file does not start with the binary AST magic.
  badMagic,

  /// The file is shorter than its own header claims, has trailing garbage, or a
  /// section overruns the section stream.
  truncated,

  /// The file requires a newer reader, or is older than this build supports.
  unsupportedVersion,

  /// The header sets a flag bit this build does not understand, so the payload
  /// cannot be interpreted safely.
  unknownFlags,

  /// A required section is missing, out of order, or malformed.
  malformedSection,

  /// A node encoding this build does not know. Unlike an unknown section, an
  /// unknown node tag is never skipped — skipping would yield a wrong AST.
  unsupportedNode,

  /// The CRC-32 does not match the file contents.
  checksumMismatch,

  /// A verifier was supplied but the file carries no signature.
  signatureMissing,

  /// The signature was rejected by the verifier.
  signatureMismatch,
}

/// A binary AST file could not be read.
///
/// This is an [Exception], not an [Error]: a malformed or corrupted input file
/// is an expected, recoverable condition that callers catch and report — unlike
/// `SyntaxError`, which reports a mistake in code the programmer supplied.
class ASTBinaryException implements Exception {
  /// A human-readable description of the failure.
  final String message;

  /// The machine-readable cause.
  final ASTBinaryError error;

  /// Byte offset of the failure, when known.
  final int? offset;

  /// The `formatVersion` the file declared, when it could be read.
  final int? formatVersion;

  /// The `minReaderVersion` the file declared, when it could be read.
  final int? minReaderVersion;

  /// The section being decoded when the failure occurred, when applicable.
  final int? sectionId;

  const ASTBinaryException(
    this.message,
    this.error, {
    this.offset,
    this.formatVersion,
    this.minReaderVersion,
    this.sectionId,
  });

  @override
  String toString() {
    var b = StringBuffer('ASTBinaryException(${error.name}): $message');
    if (offset != null) b.write(' ; offset: $offset');
    if (sectionId != null) b.write(' ; section: $sectionId');
    if (formatVersion != null) b.write(' ; formatVersion: $formatVersion');
    if (minReaderVersion != null) {
      b.write(' ; minReaderVersion: $minReaderVersion');
    }
    return b.toString();
  }
}

/// The file is structurally valid but does not verify.
///
/// Thrown for [ASTBinaryError.checksumMismatch],
/// [ASTBinaryError.signatureMissing] and [ASTBinaryError.signatureMismatch], so
/// a caller can distinguish "this file is damaged or tampered with" from "this
/// file is the wrong shape".
class ASTBinaryIntegrityException extends ASTBinaryException {
  const ASTBinaryIntegrityException(
    super.message,
    super.error, {
    super.offset,
    super.formatVersion,
    super.minReaderVersion,
    super.sectionId,
  });
}

/// An AST node cannot be represented in a binary AST file.
///
/// Thrown by the writer for nodes that hold live Dart state — external
/// functions and getters (which carry a Dart closure), and runtime-only values
/// such as a class instance, a pending future or a bound runtime variable.
/// These are injected by the VM at run time rather than produced by a parser,
/// and are re-injected the same way after a binary load, so a parsed AST never
/// contains them.
class ASTNotSerializableException implements Exception {
  /// The node that could not be encoded.
  final Object node;

  /// Why it could not be encoded.
  final String reason;

  /// Where in the program the node lives, e.g. `ASTRoot > class Foo > bar`.
  final String? declarationPath;

  const ASTNotSerializableException(
    this.node,
    this.reason, {
    this.declarationPath,
  });

  @override
  String toString() {
    var at = declarationPath == null ? '' : ' (at $declarationPath)';
    return "ASTNotSerializableException: can't serialize "
        '`${node.runtimeType}`$at: $reason';
  }
}
