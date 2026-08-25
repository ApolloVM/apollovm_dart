// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

/// Binary serialization of a parsed ApolloVM AST.
///
/// Parsing dominates the cost of loading code. This library stores an
/// already-parsed [ASTRoot] as a compact **`.avma`** image — *Apollo Virtual
/// Machine Archive* — so an application can parse once, at build time or on
/// first run, and afterwards load the same code unit by decoding bytes, with no
/// grammar and no backtracking.
///
/// ```dart
/// // Once, wherever the source is available:
/// var vm = ApolloVM();
/// var codeUnit = SourceCodeUnit('dart', source, id: 'calc.dart');
/// await vm.loadCodeUnit(codeUnit);
/// var image = vm.saveCodeUnitAST(codeUnit);
///
/// // Afterwards, with no parser involved:
/// var vm2 = ApolloVM();
/// await vm2.loadCodeUnitAST(image);
/// ```
///
/// Everything here is `Uint8List` in and `Uint8List` out: reading and writing
/// files is left to the caller, so the library is web-safe and has no `dart:io`
/// variant.
///
/// ## Integrity
///
/// Every image carries a CRC-32, which is verified on load. It detects
/// corruption — a truncated write, bit rot, a mangled transfer — and nothing
/// more: an attacker who edits an image recomputes the checksum in
/// microseconds.
///
/// Only a signature made with a key the attacker does not have makes an image
/// tamper-evident. Signing is optional and pluggable ([ASTBinarySigner]), with
/// [HmacSha256Signer] built in. **An unsigned image deserves exactly as much
/// trust as the source it came from** — loading one and running it is
/// equivalent to running arbitrary code from that source, so do not load an
/// unsigned image from an untrusted origin.
///
/// ## Compatibility
///
/// An image records the container revision that wrote it and the oldest
/// revision that can decode it correctly. Sections are length-prefixed, so a
/// reader skips any section it does not recognize, and each section is read
/// from a bounded view, so fields a newer writer appended are ignored rather
/// than misread. A newer ApolloVM's output therefore keeps loading in an older
/// one for as long as the additions are purely additive, and an older image
/// keeps loading in every later ApolloVM. When a change genuinely cannot be
/// understood, the reader fails with [ASTBinaryException] naming both versions
/// instead of producing a wrong AST.
library;

import 'src/ast/apollovm_ast_toplevel.dart';

export 'src/serialization/ast_binary_archive.dart';
export 'src/serialization/ast_binary_container.dart'
    show ASTBinaryHeader, ASTBinarySectionData;
export 'src/serialization/ast_binary_exception.dart';
export 'src/serialization/ast_binary_format.dart';
export 'src/serialization/ast_binary_reader.dart';
export 'src/serialization/ast_binary_signer.dart';
export 'src/serialization/ast_binary_vm_extension.dart';
export 'src/serialization/ast_binary_writer.dart';
