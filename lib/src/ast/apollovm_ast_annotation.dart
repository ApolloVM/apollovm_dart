import 'package:apollovm/apollovm.dart';

class ASTAnnotation implements ASTNode {
  String name;

  Map<String, ASTAnnotationParameter>? parameters;

  ASTAnnotation(this.name, [this.parameters]);
}

class ASTAnnotationParameter implements ASTNode {
  String name;

  String value;

  bool defaultParameter;

  ASTAnnotationParameter(this.name, this.value,
      [this.defaultParameter = false]);
}
