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

  /// When set (the `when:` argument), this codec handles only the [N]s it
  /// accepts — a second layout for one class, picked by content.
  ///
  /// It is how a node kind gains fields without changing its original layout:
  /// the nodes that use the new fields get their own tag, and every other node
  /// keeps the old one byte for byte.
  ///
  /// Private because its type mentions [N] in a parameter position: read
  /// through an `ASTNodeCodec<Object>` it would fail a runtime type check. Use
  /// [isConditional] and [matches].
  final bool Function(N node)? _when;

  const ASTNodeCodec(
    this.tag,
    this.className, {
    required this.encode,
    required this.decode,
    this._when,
  });

  /// Whether this codec handles only some instances of [N] (see `when:`).
  bool get isConditional => _when != null;

  /// Whether [node] is handled by this codec.
  ///
  /// An `is` test rather than a `runtimeType` lookup: around twenty AST classes
  /// are generic, and every instantiation of one has a distinct `runtimeType`.
  bool matches(Object node) {
    if (node is! N) return false;
    final when = _when;
    return when == null || when(node);
  }

  /// [encode] without a static type, for the registry's dispatch.
  void encodeAny(ASTBinaryWriteContext w, Object node) => encode(w, node as N);

  @override
  String toString() => 'ASTNodeCodec($tag, $className)';
}
