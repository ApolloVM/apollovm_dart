// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'ast_binary_context.dart';

/// How one concrete AST class is written and read.
///
/// Both halves live in the same object on purpose. The long-term risk in a
/// hand-written codec is drift — a field added to the writer and forgotten in
/// the reader — and keeping the pair adjacent is what makes that visible in
/// review. `ASTNodeTag` numbers are append-only and never reused, which is what
/// keeps files written by older builds readable.
class ASTNodeCodec<N extends Object> {
  /// The wire tag for this node kind. Stable forever once shipped.
  final int tag;

  /// The concrete class name, e.g. `'ASTExpressionOperation'`.
  ///
  /// This is the key the coverage test matches against the AST sources, so it
  /// must be spelled exactly as the class is declared.
  final String className;

  /// Writes [N]'s fields. The tag has already been written.
  final void Function(ASTBinaryWriteContext w, N node) encode;

  /// Rebuilds an [N]. The tag has already been consumed.
  final N Function(ASTBinaryReadContext r) decode;

  const ASTNodeCodec(
    this.tag,
    this.className, {
    required this.encode,
    required this.decode,
  });

  /// Whether [node] is handled by this codec.
  ///
  /// An `is` test rather than a `runtimeType` lookup: around twenty AST classes
  /// are generic, and every instantiation of one has a distinct `runtimeType`.
  bool matches(Object node) => node is N;

  /// [encode] without a static type, for the registry's dispatch.
  void encodeAny(ASTBinaryWriteContext w, Object node) => encode(w, node as N);

  @override
  String toString() => 'ASTNodeCodec($tag, $className)';
}
