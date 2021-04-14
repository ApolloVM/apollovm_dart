import 'dart:async';

import 'package:apollovm/apollovm.dart';

import 'apollovm_ast_value.dart';

/// An AST (Abstract Syntax Tree) Node.
abstract class ASTNode {}

/// The runtime status of execution.
///
/// Used to indicate:
/// - If a function have returned.
/// - If a loop have continued or broke.
class ASTRunStatus {
  static final ASTRunStatus DUMMY = ASTRunStatus();

  bool returned = false;

  ASTValue? returnedValue;
  FutureOr<ASTValue>? returnedFutureValue;

  ASTValueVoid returnVoid() {
    returned = true;
    returnedValue = ASTValueVoid.INSTANCE;
    return ASTValueVoid.INSTANCE;
  }

  ASTValueNull returnNull() {
    returned = true;
    returnedValue = ASTValueNull.INSTANCE;
    return ASTValueNull.INSTANCE;
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

/// An AST that can be [run].
abstract class ASTCodeRunner {
  VMContext defineRunContext(VMContext parentContext) {
    return parentContext;
  }

  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus);
}

/// Modifiers of an [AST] element.
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

  @override
  String toString() {
    return 'ASTModifier{isStatic: $isStatic, isFinal: $isFinal, isPrivate: $isPrivate, isPublic: $isPublic}';
  }
}
