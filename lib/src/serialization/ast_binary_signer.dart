// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'ast_binary_format.dart';

/// Produces the signature stored in a binary AST file's trailer.
///
/// The container treats a signature as opaque length-prefixed bytes, so any
/// scheme fits: an HMAC, a public-key signature, or a call out to a hardware
/// key store. [HmacSha256Signer] is the built-in implementation.
///
/// ## What signing buys, and what it does not
///
/// The CRC-32 every file carries detects accidental corruption. It is not a
/// defence against anyone: an attacker who edits the file recomputes the CRC in
/// microseconds. **Only a signature made with a key the attacker does not have
/// makes a binary AST file tamper-evident.**
///
/// An unsigned file deserves exactly as much trust as the source it was
/// produced from — loading one and running it is equivalent to running
/// arbitrary code from that source.
abstract class ASTBinarySigner {
  /// Signs [payload], returning at most
  /// [ASTBinaryFormat.maxSignatureLength] bytes.
  ///
  /// [payload] covers the header, every section and the CRC-32 — so an attacker
  /// cannot edit the content, recompute the CRC, and leave a signature that
  /// still verifies.
  Uint8List sign(Uint8List payload);
}

/// Checks the signature in a binary AST file's trailer.
abstract class ASTBinaryVerifier {
  /// Whether [signature] is valid for [payload].
  ///
  /// Implementations comparing bytes directly should use
  /// [ASTBinaryFormat.constantTimeEquals] rather than a plain list comparison,
  /// which returns sooner for a nearly-correct guess and so leaks how much of
  /// the signature an attacker got right.
  bool verify(Uint8List payload, Uint8List signature);
}

/// Signs binary AST files with HMAC-SHA256.
///
/// This is symmetric: the same secret signs and verifies, so anyone able to
/// verify is also able to sign. It fits the case this format was built for —
/// a build step signs a compiled AST and the application that loads it holds
/// the same secret. It does not fit distributing files to parties that must
/// verify but not sign; use a public-key [ASTBinarySigner] for that.
///
/// ```dart
/// var signer = HmacSha256Signer.fromString(secret);
/// var bytes = vm.saveCodeUnitAST(codeUnit, signer: signer);
/// ```
class HmacSha256Signer implements ASTBinarySigner {
  final Hmac _hmac;

  /// Signs with the raw key bytes [key].
  HmacSha256Signer(List<int> key) : _hmac = Hmac(sha256, key);

  /// Signs with the UTF-8 encoding of [key].
  HmacSha256Signer.fromString(String key) : this(utf8.encode(key));

  @override
  Uint8List sign(Uint8List payload) =>
      Uint8List.fromList(_hmac.convert(payload).bytes);
}

/// Verifies binary AST files signed with [HmacSha256Signer].
class HmacSha256Verifier implements ASTBinaryVerifier {
  final Hmac _hmac;

  /// Verifies with the raw key bytes [key].
  HmacSha256Verifier(List<int> key) : _hmac = Hmac(sha256, key);

  /// Verifies with the UTF-8 encoding of [key].
  HmacSha256Verifier.fromString(String key) : this(utf8.encode(key));

  @override
  bool verify(Uint8List payload, Uint8List signature) =>
      ASTBinaryFormat.constantTimeEquals(
        _hmac.convert(payload).bytes,
        signature,
      );
}
