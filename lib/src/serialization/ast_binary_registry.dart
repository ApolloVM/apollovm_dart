// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'ast_binary_codecs_expression.dart';
import 'ast_binary_codecs_statement.dart';
import 'ast_binary_codecs_toplevel.dart';
import 'ast_binary_codecs_value.dart';
import 'ast_binary_codecs_variable.dart';
import 'ast_binary_exception.dart';
import 'ast_binary_node_codec.dart';
import 'ast_binary_tags.dart';

/// The one place a node kind is registered.
///
/// Writer dispatch, reader dispatch and the coverage test all derive from
/// [ordered], so a node kind cannot be half-registered.
class ASTCodecRegistry {
  ASTCodecRegistry._();

  /// The tag written where a node is absent.
  static const int nullTag = ASTNodeTag.nullNode;

  /// Every codec, **most derived first**.
  ///
  /// Order matters: dispatch walks this list with `is` tests, so a subclass
  /// must appear before any of its superclasses or the superclass would claim
  /// its instances. The coverage test parses the real hierarchy out of
  /// `lib/src/ast/` and fails if this ordering is ever violated.
  static final List<ASTNodeCodec> ordered = [
    ...valueCodecs,
    ...variableCodecs,
    ...expressionCodecs,
    // Declarations before plain statements: a class, a function, a getter and
    // the root are all `ASTBlock`s, and `ASTBlock`'s own codec has to lose to
    // every one of them.
    ...toplevelCodecs,
    ...statementCodecs,
    ...blockCodecs,
  ];

  static final Map<int, ASTNodeCodec> _byTag = {
    for (var c in ordered) c.tag: c,
  };

  /// Memoized dispatch, keyed on the concrete runtime type.
  ///
  /// A plain `Map<Type, codec>` alone would be wrong — around twenty AST
  /// classes are generic and every instantiation has its own `runtimeType` —
  /// so the ordered `is` scan is the source of truth and this only caches its
  /// answer, once per distinct runtime type.
  static final Map<Type, ASTNodeCodec> _resolved = {};

  /// The codec for [tag], or `null` when this build does not know it.
  static ASTNodeCodec? byTag(int tag) => _byTag[tag];

  /// The codec that handles [node].
  ///
  /// Throws [ASTNotSerializableException] when the node has no codec — which
  /// means it holds live Dart state (an external function's closure, a running
  /// future, a bound runtime value) and was injected by the VM rather than
  /// produced by a parser.
  static ASTNodeCodec codecFor(Object node, [String declarationPath = '']) {
    var cached = _resolved[node.runtimeType];
    if (cached != null) return cached;

    for (var c in ordered) {
      if (c.matches(node)) {
        return _resolved[node.runtimeType] = c;
      }
    }

    throw ASTNotSerializableException(
      node,
      _reasonFor(node),
      declarationPath: declarationPath.isEmpty ? null : declarationPath,
    );
  }

  /// Class names this format deliberately does not encode, and why.
  ///
  /// Every one of these holds live Dart state and is injected at run time by
  /// `ApolloExternalFunctionMapper`, `ApolloExternalGetterMapper` or
  /// `ApolloVMCore` — never produced by a parser. A parsed AST therefore never
  /// contains one, and the same bindings are re-injected after a binary load.
  static const Map<String, String> excluded = {
    'ASTExternalFunction':
        'it holds a Dart closure; external functions are mapped into the VM at '
        'run time, not parsed',
    'ASTExternalClassFunction':
        'it holds a Dart closure; external methods are mapped into the VM at '
        'run time, not parsed',
    'ASTExternalGetter':
        'it holds a Dart closure; external getters are mapped into the VM at '
        'run time, not parsed',
    'ASTExternalClassGetter':
        'it holds a Dart closure; external getters are mapped into the VM at '
        'run time, not parsed',
    'ASTValueFunction':
        'it holds a live Dart function and its captured closure context',
    'ASTValueFuture': 'it holds a pending Future',
    'ASTClassInstance': 'it is a live object instance, not source',
    'ASTClassStaticAccessor':
        'it is a runtime accessor built from a class, not source',
    'ASTStaticClassAccessorVariable':
        'it is only ever built by ASTClassStaticAccessor at run time',
    'ASTRuntimeVariable': 'it is a variable bound to a running context',
    'ASTStaticFieldVariable':
        'it is unreachable: no parser or runtime path constructs one',
    'ASTClassPrimitive':
        'it is a core class registered by ApolloVMCore, not parsed',
    'ASTValueReadIndex':
        'it is unreachable: no parser or runtime path constructs one',
    'ASTValueReadKey':
        'it is unreachable: no parser or runtime path constructs one',
    'ASTRunStatus': 'it is per-execution control state, not part of the tree',
  };

  static String _reasonFor(Object node) {
    var name = node.runtimeType.toString();
    // Generic instantiations print as `ASTValueFunction<void Function()>`.
    var generic = name.indexOf('<');
    if (generic > 0) name = name.substring(0, generic);

    return excluded[name] ?? 'this node kind has no binary encoding';
  }
}
