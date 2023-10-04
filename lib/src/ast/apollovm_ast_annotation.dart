// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'apollovm_ast_base.dart';

class ASTAnnotation with ASTNode {
  String name;

  Map<String, ASTAnnotationParameter>? parameters;

  ASTAnnotation(this.name, [this.parameters]);

  @override
  Iterable<ASTNode> get children => [...?parameters?.values];

  ASTNode? _parentNode;

  @override
  ASTNode? get parentNode => _parentNode;

  @override
  void resolveNode(ASTNode? parentNode) {
    _parentNode = parentNode;

    cacheDescendantChildren();
  }

  @override
  ASTNode? getNodeIdentifier(String name, {ASTNode? requester}) =>
      parentNode?.getNodeIdentifier(name, requester: requester);
}

class ASTAnnotationParameter with ASTNode {
  String name;

  String value;

  bool defaultParameter;

  ASTAnnotationParameter(this.name, this.value,
      [this.defaultParameter = false]);

  @override
  Iterable<ASTNode> get children => [];

  ASTNode? _parentNode;

  @override
  ASTNode? get parentNode => _parentNode;

  @override
  void resolveNode(ASTNode? parentNode) {
    _parentNode = parentNode;

    cacheDescendantChildren();
  }

  @override
  ASTNode? getNodeIdentifier(String name, {ASTNode? requester}) =>
      parentNode?.getNodeIdentifier(name, requester: requester);
}
