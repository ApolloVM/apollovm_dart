import 'apollovm_ast_base.dart';

class ASTAnnotation implements ASTNode {
  String name;

  Map<String, ASTAnnotationParameter>? parameters;

  ASTAnnotation(this.name, [this.parameters]);

  ASTNode? _parentNode;

  @override
  ASTNode? get parentNode => _parentNode;

  @override
  void resolveNode(ASTNode? parentNode) {
    _parentNode = parentNode;
  }

  @override
  ASTNode? getNodeIdentifier(String name) =>
      parentNode?.getNodeIdentifier(name);
}

class ASTAnnotationParameter implements ASTNode {
  String name;

  String value;

  bool defaultParameter;

  ASTAnnotationParameter(this.name, this.value,
      [this.defaultParameter = false]);

  ASTNode? _parentNode;

  @override
  ASTNode? get parentNode => _parentNode;

  @override
  void resolveNode(ASTNode? parentNode) {
    _parentNode = parentNode;
  }

  @override
  ASTNode? getNodeIdentifier(String name) =>
      parentNode?.getNodeIdentifier(name);
}
