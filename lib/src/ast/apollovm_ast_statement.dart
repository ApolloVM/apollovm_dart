import 'package:apollovm/apollovm.dart';

import 'apollovm_ast_expression.dart';
import 'apollovm_ast_toplevel.dart';
import 'apollovm_ast_type.dart';
import 'apollovm_ast_value.dart';
import 'apollovm_ast_variable.dart';

abstract class ASTStatement implements ASTCodeRunner, ASTNode {
  @override
  VMContext defineRunContext(VMContext parentContext) {
    return parentContext;
  }
}

class ASTCodeBlock extends ASTStatement {
  ASTCodeBlock? parentBlock;

  ASTCodeBlock(this.parentBlock);

  final Map<String, ASTCodeFunctionSet> _functions = {};

  List<ASTCodeFunctionSet> get functions => _functions.values.toList();

  void addFunction(ASTFunctionDeclaration f) {
    var name = f.name;
    f.parentBlock = this;

    var set = _functions[name];
    if (set == null) {
      _functions[name] = ASTCodeFunctionSetSingle(f);
    } else {
      var set2 = set.add(f);
      if (!identical(set, set2)) {
        _functions[name] = set2;
      }
    }
  }

  void addAllFunctions(Iterable<ASTFunctionDeclaration> fs) {
    for (var f in fs) {
      addFunction(f);
    }
  }

  bool containsFunctionWithName(
    String name,
  ) {
    var set = _functions[name];
    return set != null;
  }

  ASTFunctionDeclaration? getFunction(
    String fName,
    ASTFunctionSignature parametersSignature,
    VMContext context,
  ) {
    var set = _functions[fName];
    if (set != null) return set.get(parametersSignature, false);

    var fExternal =
        context.getMappedExternalFunction(fName, parametersSignature);
    return fExternal;
  }

  ASTType<T>? getFunctionReturnType<T>(String name,
          ASTFunctionSignature parametersTypes, VMContext context) =>
      getFunction(name, parametersTypes, context)?.returnType as ASTType<T>?;

  final List<ASTStatement> _statements = [];

  List<ASTStatement> get statements => _statements.toList();

  void set(ASTCodeBlock? other) {
    if (other == null) return;

    _functions.clear();
    addAllFunctions(other._functions.values.expand((e) => e.functions));

    _statements.clear();
    addAllStatements(other._statements);
  }

  void addStatement(ASTStatement statement) {
    _statements.add(statement);
    if (statement is ASTCodeBlock) {
      statement.parentBlock = this;
    }
  }

  void addAllStatements(Iterable<ASTStatement> statements) {
    for (var stm in statements) {
      addStatement(stm);
    }
  }

  ASTValue execute(String entryFunctionName, dynamic? positionalParameters,
      dynamic? namedParameters,
      {ApolloExternalFunctionMapper? externalFunctionMapper}) {
    var rootContext = VMContext(this);
    if (externalFunctionMapper != null) {
      rootContext.externalFunctionMapper = externalFunctionMapper;
    }

    var rootStatus = ASTRunStatus();

    var prevContext = VMContext.setCurrent(rootContext);
    try {
      run(rootContext, rootStatus);

      var fSignature =
          ASTFunctionSignature.from(positionalParameters, namedParameters);

      var f = getFunction(entryFunctionName, fSignature, rootContext);
      if (f == null) {
        throw StateError("Can't find entry function: $entryFunctionName");
      }
      return f.call(rootContext,
          positionalParameters: positionalParameters,
          namedParameters: namedParameters);
    } finally {
      VMContext.setCurrent(prevContext);
    }
  }

  @override
  VMContext defineRunContext(VMContext parentContext) {
    return parentContext;
  }

  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    var blockContext = defineRunContext(parentContext);

    ASTValue returnValue = ASTValueVoid.INSTANCE;

    for (var stm in _statements) {
      var ret = stm.run(blockContext, runStatus);

      if (runStatus.returned) {
        return runStatus.returnedValue!;
      }

      returnValue = ret;
    }

    return returnValue;
  }

  ASTClassField? getField(String name) =>
      parentBlock != null ? parentBlock!.getField(name) : null;
}

class ASTStatementValue extends ASTStatement {
  ASTValue value;

  ASTStatementValue(ASTCodeBlock block, this.value) : super();

  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    var context = defineRunContext(parentContext);
    return value.getValue(context);
  }
}

enum ASTAssignmentOperator { set, multiply, divide, sum, subtract }

ASTAssignmentOperator getASTAssignmentOperator(String op) {
  op = op.trim();

  switch (op) {
    case '=':
      return ASTAssignmentOperator.set;
    case '*=':
      return ASTAssignmentOperator.multiply;
    case '/=':
      return ASTAssignmentOperator.divide;
    case '+=':
      return ASTAssignmentOperator.sum;
    case '-=':
      return ASTAssignmentOperator.subtract;
    default:
      throw UnsupportedError('$op');
  }
}

String getASTAssignmentOperatorText(ASTAssignmentOperator op) {
  switch (op) {
    case ASTAssignmentOperator.set:
      return '=';
    case ASTAssignmentOperator.multiply:
      return '*=';
    case ASTAssignmentOperator.divide:
      return '/=';
    case ASTAssignmentOperator.sum:
      return '+=';
    case ASTAssignmentOperator.subtract:
      return '-=';
    default:
      throw UnsupportedError('$op');
  }
}

class ASTStatementExpression extends ASTStatement {
  ASTExpression expression;

  ASTStatementExpression(this.expression);

  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    var context = defineRunContext(parentContext);
    return expression.run(context, runStatus);
  }
}

class ASTStatementReturn extends ASTStatement {
  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    return runStatus.returnVoid();
  }
}

class ASTStatementReturnNull extends ASTStatementReturn {
  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    return runStatus.returnNull();
  }
}

class ASTStatementReturnValue extends ASTStatementReturn {
  ASTValue value;

  ASTStatementReturnValue(this.value);

  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    return runStatus.returnValue(value);
  }
}

class ASTStatementReturnVariable extends ASTStatementReturn {
  ASTVariable variable;

  ASTStatementReturnVariable(this.variable);

  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    var value = variable.getValue(parentContext);
    return runStatus.returnValue(value);
  }
}

class ASTStatementReturnWithExpression extends ASTStatementReturn {
  ASTExpression expression;

  ASTStatementReturnWithExpression(this.expression);

  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    var value = expression.run(parentContext, runStatus);
    return runStatus.returnValue(value);
  }
}

class ASTStatementVariableDeclaration<V> extends ASTStatement {
  ASTType<V> type;

  String name;

  ASTExpression? value;

  ASTStatementVariableDeclaration(this.type, this.name, this.value);

  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    var result = value?.run(parentContext, runStatus) ?? ASTValueNull.INSTANCE;
    parentContext.declareVariableWithValue(type, name, result);
    return ASTValueVoid.INSTANCE;
  }
}

abstract class ASTBranch extends ASTStatement {
  bool evaluateCondition(VMContext parentContext, ASTRunStatus runStatus,
      ASTExpression condition) {
    var evaluation = condition.run(parentContext, runStatus);
    var evalValue = evaluation.getValue(parentContext);
    if (evalValue is! bool) {
      throw StateError(
          'A branch condition should return a boolean: $evalValue');
    }

    return evalValue;
  }
}

class ASTBranchIfBlock extends ASTBranch {
  ASTExpression condition;
  ASTCodeBlock block;

  ASTBranchIfBlock(this.condition, this.block);

  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    var evalValue = evaluateCondition(parentContext, runStatus, condition);

    if (evalValue) {
      block.run(parentContext, runStatus);
    }

    return ASTValueVoid.INSTANCE;
  }
}

class ASTBranchIfElseBlock extends ASTBranch {
  ASTExpression condition;
  ASTCodeBlock blockIf;
  ASTCodeBlock blockElse;

  ASTBranchIfElseBlock(this.condition, this.blockIf, this.blockElse);

  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    var evalValue = evaluateCondition(parentContext, runStatus, condition);

    if (evalValue) {
      blockIf.run(parentContext, runStatus);
    } else {
      blockElse.run(parentContext, runStatus);
    }

    return ASTValueVoid.INSTANCE;
  }
}

class ASTBranchIfElseIfsElseBlock extends ASTBranch {
  ASTExpression condition;
  ASTCodeBlock blockIf;
  List<ASTBranchIfBlock> blocksElseIf;
  ASTCodeBlock blockElse;

  ASTBranchIfElseIfsElseBlock(
      this.condition, this.blockIf, this.blocksElseIf, this.blockElse);

  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    var evalValue = evaluateCondition(parentContext, runStatus, condition);
    if (evalValue) {
      blockIf.run(parentContext, runStatus);
      return ASTValueVoid.INSTANCE;
    } else {
      for (var branch in blocksElseIf) {
        evalValue =
            evaluateCondition(parentContext, runStatus, branch.condition);

        if (evalValue) {
          branch.block.run(parentContext, runStatus);
          return ASTValueVoid.INSTANCE;
        }
      }

      blockElse.run(parentContext, runStatus);
      return ASTValueVoid.INSTANCE;
    }
  }
}
