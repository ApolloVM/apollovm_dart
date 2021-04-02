import 'package:apollovm/src/apollovm_ast.dart';

abstract class ApolloParser {
  Future<ASTCodeRoot?> parse(String source);
}

class UnsupportedTypeError extends UnsupportedError {
  UnsupportedTypeError(String message) : super('[Unsupported Type] $message');
}

class UnsupportedSyntaxError extends UnsupportedError {
  UnsupportedSyntaxError(String message)
      : super('[Unsupported Syntax] $message');
}

class UnsupportedValueOperationError extends UnsupportedError {
  UnsupportedValueOperationError(String message)
      : super('[Unsupported Value operation] $message');
}

extension ListTypedExtension<T> on List<T> {
  /// Provide access to the generic type at runtime.
  Type get genericType => T;
}
