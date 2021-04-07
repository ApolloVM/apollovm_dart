import 'package:apollovm/apollovm.dart';

import 'apollovm_ast_value.dart';

abstract class ASTNode {}

class ASTRunStatus {
  static final ASTRunStatus DUMMY = ASTRunStatus();

  bool returned = false;

  ASTValue? returnedValue;

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

  bool continued = false;

  bool broke = false;
}

abstract class ASTCodeRunner {
  VMContext defineRunContext(VMContext parentContext) {
    return parentContext;
  }

  ASTValue run(VMContext parentContext, ASTRunStatus runStatus);
}
