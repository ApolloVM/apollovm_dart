import 'package:apollovm/apollovm.dart';

import 'apollovm_code_storage.dart';

abstract class ApolloCodeGenerator {
  final ApolloCodeStorage codeStorage;

  ApolloCodeGenerator(this.codeStorage);

  StringBuffer generateASTNode(ASTNode node,
      [String indent = '', StringBuffer? s]) {
    if (node is ASTValue) {
      return generateASTValue(node, indent, s);
    } else if (node is ASTExpression) {
      return generateASTExpression(node, indent, s);
    } else if (node is ASTRoot) {
      return generateASTRoot(node, indent, s);
    } else if (node is ASTClass) {
      return generateASTClass(node, indent, s);
    } else if (node is ASTBlock) {
      return generateASTBlock(node, indent, s);
    } else if (node is ASTStatement) {
      return generateASTStatement(node, indent, s);
    } else if (node is ASTFunctionDeclaration) {
      return generateASTFunctionDeclaration(node, indent, s);
    }

    throw UnsupportedError("Can't handle ASTNode: $node");
  }

  StringBuffer generateASTRoot(ASTRoot root,
      [String indent = '', StringBuffer? s, bool withBrackets = true]) {
    s ??= StringBuffer();

    generateASTBlock(root, '', s, false);

    for (var clazz in root.classes) {
      generateASTClass(clazz, '', s);
    }

    return s;
  }

  StringBuffer generateASTBlock(ASTBlock block,
      [String indent = '', StringBuffer? s, bool withBrackets = true]) {
    s ??= StringBuffer();

    var indent2 = indent + '  ';

    if (withBrackets) s.write('$indent{\n');

    for (var set in block.functions) {
      for (var f in set.functions) {
        generateASTFunctionDeclaration(f, indent2, s);
      }
    }

    for (var stm in block.statements) {
      generateASTStatement(stm, indent2, s);
      s.write('\n');
    }

    if (withBrackets) s.write('$indent}\n');

    return s;
  }

  StringBuffer generateASTClass(ASTClass clazz,
      [String indent = '', StringBuffer? s]);

  StringBuffer generateASTFunctionDeclaration(ASTFunctionDeclaration f,
      [String indent = '', StringBuffer? s]);

  StringBuffer generateASTParametersDeclaration(
      ASTParametersDeclaration parameters,
      [String indent = '',
      StringBuffer? s]);

  StringBuffer generateASTFunctionParameterDeclaration(
      ASTFunctionParameterDeclaration parameter,
      [String indent = '',
      StringBuffer? s]);

  StringBuffer generateASTParameterDeclaration(
      ASTParameterDeclaration parameter,
      [String indent = '',
      StringBuffer? s]) {
    s ??= StringBuffer();

    var typeStr = generateASTType(parameter.type);

    s.write(typeStr);
    s.write(' ');
    s.write(parameter.name);
    return s;
  }

  StringBuffer generateASTType(ASTType type,
      [String indent = '', StringBuffer? s]) {
    if (type is ASTTypeArray) {
      return generateASTTypeArray(type, indent, s);
    } else if (type is ASTTypeArray2D) {
      return generateASTTypeArray2D(type, indent, s);
    } else if (type is ASTTypeArray3D) {
      return generateASTTypeArray3D(type, indent, s);
    }

    return generateASTTypeDefault(type, indent, s);
  }

  StringBuffer generateASTTypeArray(ASTTypeArray type,
      [String indent = '', StringBuffer? s]);

  StringBuffer generateASTTypeArray2D(ASTTypeArray2D type,
      [String indent = '', StringBuffer? s]);

  StringBuffer generateASTTypeArray3D(ASTTypeArray3D type,
      [String indent = '', StringBuffer? s]);

  StringBuffer generateASTTypeDefault(ASTType type,
      [String indent = '', StringBuffer? s]) {
    s ??= StringBuffer();

    s.write(type.name);

    if (type.generics != null) {
      var generics = type.generics!;

      s.write('<');
      for (var i = 0; i < generics.length; ++i) {
        var g = generics[i];
        if (i > 0) s.write(', ');
        s.write(generateASTType(g));
      }
      s.write('>');
    }

    return s;
  }

  StringBuffer generateASTStatement(ASTStatement statement,
      [String indent = '', StringBuffer? s]) {
    if (statement is ASTStatementExpression) {
      return generateASTStatementExpression(statement, indent, s);
    } else if (statement is ASTStatementVariableDeclaration) {
      return generateASTStatementVariableDeclaration(statement, indent, s);
    } else if (statement is ASTBranch) {
      return generateASTBranch(statement, indent, s);
    } else if (statement is ASTStatementReturn) {
      return generateASTStatementReturn(statement, indent, s);
    } else if (statement is ASTStatementReturnNull) {
      return generateASTStatementReturnNull(statement, indent, s);
    } else if (statement is ASTStatementReturnValue) {
      return generateASTStatementReturnValue(statement, indent, s);
    } else if (statement is ASTStatementReturnVariable) {
      return generateASTStatementReturnVariable(statement, indent, s);
    } else if (statement is ASTStatementReturnWithExpression) {
      return generateASTStatementReturnWithExpression(statement, indent, s);
    }

    throw UnsupportedError("Can't handle statement: $statement");
  }

  StringBuffer generateASTBranch(ASTBranch branch,
      [String indent = '', StringBuffer? s]) {
    if (branch is ASTBranchIfBlock) {
      return generateASTBranchIfBlock(branch, indent, s);
    } else if (branch is ASTBranchIfElseBlock) {
      return generateASTBranchIfElseBlock(branch, indent, s);
    } else if (branch is ASTBranchIfElseIfsElseBlock) {
      return generateASTBranchIfElseIfsElseBlock(branch, indent, s);
    }

    throw UnsupportedError("Can't handle branch: $branch");
  }

  StringBuffer generateASTBranchIfBlock(ASTBranchIfBlock branch,
      [String indent = '', StringBuffer? s]) {
    s ??= StringBuffer();

    s.write(indent);
    s.write('if (');
    generateASTExpression(branch.condition, '', s);
    s.write(') {\n');
    generateASTBlock(branch.block, indent + '  ', s, false);
    s.write(indent);
    s.write('}\n');

    return s;
  }

  StringBuffer generateASTBranchIfElseBlock(ASTBranchIfElseBlock branch,
      [String indent = '', StringBuffer? s]) {
    s ??= StringBuffer();

    s.write(indent);
    s.write('if (');
    generateASTExpression(branch.condition, '', s);
    s.write(') {\n');
    generateASTBlock(branch.blockIf, indent + '  ', s, false);
    s.write(indent);
    s.write('} else {\n');
    generateASTBlock(branch.blockElse, indent + '  ', s, false);
    s.write(indent);
    s.write('}\n');

    return s;
  }

  StringBuffer generateASTBranchIfElseIfsElseBlock(
      ASTBranchIfElseIfsElseBlock branch,
      [String indent = '',
      StringBuffer? s]) {
    s ??= StringBuffer();

    s.write(indent);
    s.write('if (');
    generateASTExpression(branch.condition, '', s);
    s.write(') {\n');
    generateASTBlock(branch.blockIf, indent + '  ', s, false);

    for (var branchElseIf in branch.blocksElseIf) {
      s.write(indent);
      s.write('} else if (');
      generateASTExpression(branchElseIf.condition, indent + '  ', s);
      s.write(') {\n');
      generateASTBlock(branchElseIf.block, indent + '  ', s, false);
    }

    s.write(indent);
    s.write('} else {\n');
    generateASTBlock(branch.blockElse, indent + '  ', s, false);
    s.write(indent);
    s.write('}\n');

    return s;
  }

  StringBuffer generateASTStatementExpression(ASTStatementExpression statement,
      [String indent = '', StringBuffer? s]) {
    s ??= StringBuffer();
    s.write(indent);
    generateASTExpression(statement.expression, '', s);
    s.write(';');
    return s;
  }

  StringBuffer generateASTStatementVariableDeclaration(
      ASTStatementVariableDeclaration statement,
      [String indent = '',
      StringBuffer? s]) {
    s ??= StringBuffer();

    s.write(indent);
    generateASTType(statement.type, '', s);

    s.write(' ');
    s.write(statement.name);
    if (statement.value != null) {
      s.write(' = ');
      generateASTExpression(statement.value!, '', s);
    }
    s.write(';');

    return s;
  }

  StringBuffer generateASTExpressionVariableAssignment(
      ASTExpressionVariableAssignment expression,
      [String indent = '',
      StringBuffer? s]) {
    s ??= StringBuffer();

    s.write(indent);

    generateASTVariable(expression.variable, '', s);
    var op = getASTAssignmentOperatorText(expression.operator);
    s.write(op);
    generateASTExpression(expression.expression, '', s);

    s.write(';');

    return s;
  }

  StringBuffer generateASTStatementReturn(ASTStatementReturn statement,
      [String indent = '', StringBuffer? s]) {
    s ??= StringBuffer();
    s.write('return;');
    return s;
  }

  StringBuffer generateASTStatementReturnNull(ASTStatementReturnNull statement,
      [String indent = '', StringBuffer? s]) {
    s ??= StringBuffer();
    s.write('return null;');
    return s;
  }

  StringBuffer generateASTStatementReturnValue(
      ASTStatementReturnValue statement,
      [String indent = '',
      StringBuffer? s]) {
    s ??= StringBuffer();
    s.write(indent);
    s.write('return ');
    generateASTValue(statement.value, '', s);
    s.write(';');
    return s;
  }

  StringBuffer generateASTStatementReturnVariable(
      ASTStatementReturnVariable statement,
      [String indent = '',
      StringBuffer? s]) {
    s ??= StringBuffer();
    s.write(indent);
    s.write('return ');
    generateASTVariable(statement.variable, '', s);
    s.write(';');
    return s;
  }

  StringBuffer generateASTStatementReturnWithExpression(
      ASTStatementReturnWithExpression statement,
      [String indent = '',
      StringBuffer? s]) {
    s ??= StringBuffer();
    s.write(indent);
    s.write('return ');
    generateASTExpression(statement.expression, '', s);
    s.write(';');
    return s;
  }

  StringBuffer generateASTExpression(ASTExpression expression,
      [String indent = '', StringBuffer? s]) {
    if (expression is ASTExpressionVariableAccess) {
      return generateASTExpressionVariableAccess(expression, indent, s);
    } else if (expression is ASTExpressionVariableAssignment) {
      return generateASTExpressionVariableAssignment(expression, indent, s);
    } else if (expression is ASTExpressionVariableEntryAccess) {
      return generateASTExpressionVariableEntryAccess(expression, indent, s);
    } else if (expression is ASTExpressionLiteral) {
      return generateASTExpressionLiteral(expression, indent, s);
    } else if (expression is ASTExpressionLocalFunctionInvocation) {
      return generateASTExpressionLocalFunctionInvocation(
          expression, indent, s);
    } else if (expression is ASTExpressionObjectFunctionInvocation) {
      return generateASTExpressionFunctionInvocation(expression, indent, s);
    } else if (expression is ASTExpressionOperation) {
      return generateASTExpressionOperation(expression, indent, s);
    }

    throw UnsupportedError("Can't generate expression: $expression");
  }

  StringBuffer generateASTExpressionOperation(ASTExpressionOperation expression,
      [String indent = '', StringBuffer? s]) {
    s ??= StringBuffer();
    s.write(indent);
    generateASTExpression(expression.expression1, '', s);
    s.write(' ');
    s.write(resolveASTExpressionOperatorText(expression.operator));
    s.write(' ');
    generateASTExpression(expression.expression2, '', s);
    return s;
  }

  String resolveASTExpressionOperatorText(ASTExpressionOperator operator);

  StringBuffer generateASTExpressionLiteral(ASTExpressionLiteral expression,
      [String indent = '', StringBuffer? s]) {
    s ??= StringBuffer();
    s.write(indent);
    generateASTValue(expression.value, '', s);
    return s;
  }

  StringBuffer generateASTExpressionFunctionInvocation(
      ASTExpressionObjectFunctionInvocation expression,
      [String indent = '',
      StringBuffer? s]) {
    s ??= StringBuffer();
    s.write(indent);

    generateASTVariable(expression.variable, '', s);
    s.write('.');

    s.write(expression.name);
    s.write('(');

    var arguments = expression.arguments;
    for (var i = 0; i < arguments.length; ++i) {
      var arg = arguments[i];
      if (i > 0) s.write(', ');
      generateASTExpression(arg, '', s);
    }
    s.write(')');

    return s;
  }

  StringBuffer generateASTExpressionLocalFunctionInvocation(
      ASTExpressionLocalFunctionInvocation expression,
      [String indent = '',
      StringBuffer? s]) {
    s ??= StringBuffer();
    s.write(indent);

    s.write(expression.name);
    s.write('(');

    var arguments = expression.arguments;
    for (var i = 0; i < arguments.length; ++i) {
      var arg = arguments[i];
      if (i > 0) s.write(', ');

      generateASTExpression(arg, '', s);
    }
    s.write(')');

    return s;
  }

  StringBuffer generateASTExpressionVariableAccess(
      ASTExpressionVariableAccess expression,
      [String indent = '',
      StringBuffer? s]) {
    s ??= StringBuffer();
    s.write(indent);
    generateASTVariable(expression.variable, '', s);
    return s;
  }

  StringBuffer generateASTExpressionVariableEntryAccess(
      ASTExpressionVariableEntryAccess expression,
      [String indent = '',
      StringBuffer? s]) {
    s ??= StringBuffer();
    s.write(indent);
    generateASTVariable(expression.variable, '', s);
    s.write('[');
    generateASTExpression(expression.expression, '', s);
    s.write(']');
    return s;
  }

  StringBuffer generateASTVariable(ASTVariable variable,
      [String indent = '', StringBuffer? s]) {
    s ??= StringBuffer();
    s.write(indent);
    s.write(variable.name);
    return s;
  }

  StringBuffer generateASTValue(ASTValue value,
      [String indent = '', StringBuffer? s]) {
    if (value is ASTValueString) {
      return generateASTValueString(value, indent, s);
    } else if (value is ASTValueInt) {
      return generateASTValueInt(value, indent, s);
    } else if (value is ASTValueDouble) {
      return generateASTValueDouble(value, indent, s);
    } else if (value is ASTValueNull) {
      return generateASTValueNull(value, indent, s);
    } else if (value is ASTValueVar) {
      return generateASTValueVar(value, indent, s);
    } else if (value is ASTValueObject) {
      return generateASTValueObject(value, indent, s);
    } else if (value is ASTValueStatic) {
      return generateASTValueStatic(value, indent, s);
    } else if (value is ASTValueStringVariable) {
      return generateASTValueStringVariable(value, indent, s);
    } else if (value is ASTValueStringConcatenation) {
      return generateASTValueStringConcatenation(value, indent, s);
    } else if (value is ASTValueStringExpresion) {
      return generateASTValueStringExpresion(value, indent, s);
    } else if (value is ASTValueArray) {
      return generateASTValueArray(value, indent, s);
    } else if (value is ASTValueArray2D) {
      return generateASTValueArray2D(value, indent, s);
    } else if (value is ASTValueArray3D) {
      return generateASTValueArray3D(value, indent, s);
    }

    throw UnsupportedError("Can't generate value: $value");
  }

  StringBuffer generateASTValueStringConcatenation(
      ASTValueStringConcatenation value,
      [String indent = '',
      StringBuffer? s]);

  StringBuffer generateASTValueStringVariable(ASTValueStringVariable value,
      [String indent = '', StringBuffer? s]);

  StringBuffer generateASTValueStringExpresion(ASTValueStringExpresion value,
      [String indent = '', StringBuffer? s]);

  StringBuffer generateASTValueString(ASTValueString value,
      [String indent = '', StringBuffer? s]);

  StringBuffer generateASTValueInt(ASTValueInt value,
      [String indent = '', StringBuffer? s]) {
    s ??= StringBuffer();
    s.write(indent);
    s.write(value.value);
    return s;
  }

  StringBuffer generateASTValueDouble(ASTValueDouble value,
      [String indent = '', StringBuffer? s]) {
    s ??= StringBuffer();
    s.write(indent);
    s.write(value.value);
    return s;
  }

  StringBuffer generateASTValueNull(ASTValueNull value,
      [String indent = '', StringBuffer? s]) {
    s ??= StringBuffer();
    s.write(indent);
    s.write('null');
    return s;
  }

  StringBuffer generateASTValueVar(ASTValueVar value,
      [String indent = '', StringBuffer? s]) {
    s ??= StringBuffer();
    s.write(indent);
    s.write(value.value);
    return s;
  }

  StringBuffer generateASTValueObject(ASTValueObject value,
      [String indent = '', StringBuffer? s]) {
    s ??= StringBuffer();
    s.write(indent);
    s.write(value.value);
    return s;
  }

  StringBuffer generateASTValueStatic(ASTValueStatic value,
      [String indent = '', StringBuffer? s]) {
    var v = value.value;

    if (v is ASTNode) {
      return generateASTNode(v, indent, s);
    }

    s ??= StringBuffer();
    s.write(value.value);
    return s;
  }

  StringBuffer generateASTValueArray(ASTValueArray value,
      [String indent = '', StringBuffer? s]);

  StringBuffer generateASTValueArray2D(ASTValueArray2D value,
      [String indent = '', StringBuffer? s]);

  StringBuffer generateASTValueArray3D(ASTValueArray3D value,
      [String indent = '', StringBuffer? s]);
}
