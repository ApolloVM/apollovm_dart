// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:async';
import 'dart:collection';

import '../apollovm_base.dart';
import 'apollovm_ast_type.dart';
import 'apollovm_ast_value.dart';

/// An AST (Abstract Syntax Tree) Node.
abstract mixin class ASTNode {
  ASTNode? get parentNode;

  void resolveNode(ASTNode? parentNode);

  ASTNode? getNodeIdentifier(String name, {ASTNode? requester}) =>
      parentNode?.getNodeIdentifier(name, requester: requester);

  /// The children nodes of this node.
  Iterable<ASTNode> get children;

  UnmodifiableListView<ASTNode>? _descendantChildren;

  /// Return the [children] and it's descendant children (unmodifiable).
  List<ASTNode> get descendantChildren {
    var descendantChildren = _descendantChildren;
    if (descendantChildren != null) return descendantChildren;

    if (_cacheDescendantChildren) {
      return _descendantChildren =
          UnmodifiableListView(_computeDescendantChildren());
    } else {
      return _computeDescendantChildren();
    }
  }

  bool _cacheDescendantChildren = false;

  /// Mark that this node can cache it's [descendantChildren].
  void cacheDescendantChildren() {
    _cacheDescendantChildren = true;
  }

  /// Compute [descendantChildren] in DFS order.
  List<ASTNode> _computeDescendantChildren() {
    final processed = <ASTNode>{};
    final queue = ListQueue<ASTNode>()..add(this);

    while (queue.isNotEmpty) {
      var node = queue.removeFirst();

      if (processed.add(node)) {
        var children = node.children.toList(growable: false);

        for (var e in children.reversed) {
          queue.addFirst(e);
        }
      }
    }

    processed.remove(this);

    return processed.toList();
  }
}

/// The runtime status of execution.
///
/// Used to indicate:
/// - If a function have returned.
/// - If a loop have continued or broke.
class ASTRunStatus {
  static final ASTRunStatus dummy = ASTRunStatus();

  bool returned = false;

  ASTValue? returnedValue;
  FutureOr<ASTValue>? returnedFutureValue;

  ASTValueVoid returnVoid() {
    returned = true;
    returnedValue = ASTValueVoid.instance;
    return ASTValueVoid.instance;
  }

  ASTValueNull returnNull() {
    returned = true;
    returnedValue = ASTValueNull.instance;
    return ASTValueNull.instance;
  }

  ASTValue returnValue(ASTValue value) {
    returned = true;
    returnedValue = value;
    return value;
  }

  FutureOr<ASTValue> returnFutureOrValue(FutureOr<ASTValue> futureValue) {
    returned = true;
    returnedFutureValue = futureValue;
    return futureValue;
  }

  /// Returns true if some statement demands continue of loop (next iteration).
  bool continued = false;

  /// Returns true if some statement demands loop interruption (break).
  bool broke = false;
}

abstract class ASTTypedNode {
  FutureOr<ASTType> resolveType(VMContext? context);

  void associateToType(ASTTypedNode node) {}
}

/// An AST that can be [run].
abstract class ASTCodeRunner extends ASTTypedNode {
  VMContext defineRunContext(VMContext parentContext) {
    return parentContext;
  }

  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus);
}

/// Modifiers of an [ASTNode] element.
class ASTModifiers {
  static final ASTModifiers modifiersNone = ASTModifiers();
  static final ASTModifiers modifierStatic = ASTModifiers(isStatic: true);
  static final ASTModifiers modifierFinal = ASTModifiers(isFinal: true);
  static final ASTModifiers modifiersStaticFinal =
      ASTModifiers(isStatic: true, isFinal: true);

  final bool isStatic;

  final bool isFinal;

  final bool isPrivate;

  final bool isPublic;

  ASTModifiers(
      {this.isStatic = false,
      this.isFinal = false,
      this.isPrivate = false,
      this.isPublic = false}) {
    if (isPrivate && isPublic) {
      throw StateError("Can't be private and public at the same time!");
    }
  }

  ASTModifiers copyWith(
      {bool? isStatic, bool? isFinal, bool? isPrivate, bool? isPublic}) {
    return ASTModifiers(
      isStatic: isStatic ?? this.isStatic,
      isFinal: isFinal ?? this.isFinal,
      isPrivate: isPrivate ?? this.isPrivate,
      isPublic: isPublic ?? this.isPublic,
    );
  }

  List<String> get modifiers => [
        if (isPublic) 'public',
        if (isPrivate) 'private',
        if (isStatic) 'static',
        if (isFinal) 'final',
      ];

  @override
  String toString() {
    return modifiers.join(' ');
  }
}
