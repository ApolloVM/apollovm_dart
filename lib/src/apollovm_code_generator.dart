import 'apollovm_code_storage.dart';
import 'ast/apollovm_ast_base.dart';
import 'ast/apollovm_ast_expression.dart';
import 'ast/apollovm_ast_statement.dart';
import 'ast/apollovm_ast_toplevel.dart';
import 'ast/apollovm_ast_type.dart';
import 'ast/apollovm_ast_value.dart';
import 'ast/apollovm_ast_variable.dart';

/// Base class for code generators.
///
/// An [ASTRoot] loaded in [ApolloVM] can be converted to a code in a specific language.
abstract class ApolloCodeGenerator {
  /// Target programming language of this code generator implementation.
  final String language;

  /// The code storage for generated code.
  final ApolloCodeStorage codeStorage;

  ApolloCodeGenerator(String language, this.codeStorage)
      : language = language.trim().toLowerCase();

  StringBuffer generateASTNode(ASTNode node,
      {StringBuffer? out, String indent = '', bool headIndented = true}) {
    if (node is ASTValue) {
      return generateASTValue(node,
          out: out, indent: indent, headIndented: headIndented);
    } else if (node is ASTExpression) {
      return generateASTExpression(node,
          out: out, indent: indent, headIndented: headIndented);
    } else if (node is ASTRoot) {
      return generateASTRoot(node, out: out, indent: indent);
    } else if (node is ASTClassNormal) {
      return generateASTClass(node, out: out, indent: indent);
    } else if (node is ASTBlock) {
      return generateASTBlock(node, out: out, indent: indent);
    } else if (node is ASTStatement) {
      return generateASTStatement(node,
          out: out, indent: indent, headIndented: headIndented);
    } else if (node is ASTClassFunctionDeclaration) {
      return generateASTClassFunctionDeclaration(node,
          out: out, indent: indent);
    } else if (node is ASTFunctionDeclaration) {
      return generateASTFunctionDeclaration(node, out: out, indent: indent);
    }

    throw UnsupportedError("Can't handle ASTNode: $node");
  }

  StringBuffer generateASTRoot(ASTRoot root,
      {StringBuffer? out, String indent = '', bool withBrackets = true}) {
    out ??= StringBuffer();

    generateASTBlock(root, out: out, withBrackets: false);

    for (var clazz in root.classes) {
      generateASTClass(clazz, out: out);
    }

    return out;
  }

  StringBuffer generateASTBlock(ASTBlock block,
      {StringBuffer? out,
      String indent = '',
      bool withBrackets = true,
      bool withBlankHeadLine = false}) {
    out ??= StringBuffer();

    var indent2 = '$indent  ';

    if (withBrackets) out.write('$indent{\n');

    if (withBlankHeadLine) out.write('\n');

    if (block is ASTClassNormal) {
      for (var field in block.fields) {
        generateASTClassField(field, out: out, indent: indent2);
      }

      if (block.fields.isNotEmpty) {
        out.write('\n');
      }
    }

    for (var set in block.functions) {
      for (var f in set.functions) {
        if (f is ASTClassFunctionDeclaration) {
          generateASTClassFunctionDeclaration(f, out: out, indent: indent2);
        } else {
          generateASTFunctionDeclaration(f, out: out, indent: indent2);
        }
      }
    }

    for (var stm in block.statements) {
      generateASTStatement(stm, out: out, indent: indent2);
      out.write('\n');
    }

    if (withBrackets) out.write('$indent}\n');

    return out;
  }

  StringBuffer generateASTClass(ASTClassNormal clazz,
      {StringBuffer? out, String indent = ''});

  StringBuffer generateASTClassField(ASTClassField field,
      {StringBuffer? out, String indent = ''});

  StringBuffer generateASTClassFunctionDeclaration(
      ASTClassFunctionDeclaration f,
      {StringBuffer? out,
      String indent = ''});

  StringBuffer generateASTFunctionDeclaration(ASTFunctionDeclaration f,
      {StringBuffer? out, String indent = ''});

  StringBuffer generateASTParametersDeclaration(
      ASTParametersDeclaration parameters,
      {StringBuffer? out,
      String indent = ''});

  StringBuffer generateASTFunctionParameterDeclaration(
      ASTFunctionParameterDeclaration parameter,
      {StringBuffer? out,
      String indent = ''});

  StringBuffer generateASTParameterDeclaration(
      ASTParameterDeclaration parameter,
      {StringBuffer? out,
      String indent = ''}) {
    out ??= StringBuffer();

    var typeStr = generateASTType(parameter.type);

    out.write(typeStr);
    out.write(' ');
    out.write(parameter.name);
    return out;
  }

  StringBuffer generateASTType(ASTType type,
      {StringBuffer? out, String indent = ''}) {
    if (type is ASTTypeArray) {
      return generateASTTypeArray(type, out: out, indent: indent);
    } else if (type is ASTTypeArray2D) {
      return generateASTTypeArray2D(type, out: out, indent: indent);
    } else if (type is ASTTypeArray3D) {
      return generateASTTypeArray3D(type, out: out, indent: indent);
    }

    return generateASTTypeDefault(type, out: out, indent: indent);
  }

  StringBuffer generateASTTypeArray(ASTTypeArray type,
      {StringBuffer? out, String indent = ''});

  StringBuffer generateASTTypeArray2D(ASTTypeArray2D type,
      {StringBuffer? out, String indent = ''});

  StringBuffer generateASTTypeArray3D(ASTTypeArray3D type,
      {StringBuffer? out, String indent = ''});

  String normalizeTypeName(String typeName, [String? callingFunction]) =>
      typeName;

  String normalizeTypeFunction(String typeName, String functionName) =>
      functionName;

  StringBuffer generateASTTypeDefault(ASTType type,
      {StringBuffer? out, String indent = ''}) {
    out ??= StringBuffer();

    var typeName = normalizeTypeName(type.name);

    out.write(typeName);

    if (type.generics != null) {
      var generics = type.generics!;

      out.write('<');
      for (var i = 0; i < generics.length; ++i) {
        var g = generics[i];
        if (i > 0) out.write(', ');
        out.write(generateASTType(g));
      }
      out.write('>');
    }

    return out;
  }

  StringBuffer generateASTStatement(ASTStatement statement,
      {StringBuffer? out, String indent = '', bool headIndented = true}) {
    if (statement is ASTStatementExpression) {
      return generateASTStatementExpression(statement,
          out: out, indent: indent, headIndented: headIndented);
    } else if (statement is ASTStatementVariableDeclaration) {
      return generateASTStatementVariableDeclaration(statement,
          out: out, indent: indent, headIndented: headIndented);
    } else if (statement is ASTBranch) {
      return generateASTBranch(statement,
          out: out, indent: indent, headIndented: headIndented);
    } else if (statement is ASTStatementForLoop) {
      return generateASTStatementForLoop(statement,
          out: out, indent: indent, headIndented: headIndented);
    } else if (statement is ASTStatementReturnNull) {
      return generateASTStatementReturnNull(statement,
          out: out, indent: indent, headIndented: headIndented);
    } else if (statement is ASTStatementReturnValue) {
      return generateASTStatementReturnValue(statement,
          out: out, indent: indent, headIndented: headIndented);
    } else if (statement is ASTStatementReturnVariable) {
      return generateASTStatementReturnVariable(statement,
          out: out, indent: indent, headIndented: headIndented);
    } else if (statement is ASTStatementReturnWithExpression) {
      return generateASTStatementReturnWithExpression(statement,
          out: out, indent: indent, headIndented: headIndented);
    } else if (statement is ASTStatementReturn) {
      return generateASTStatementReturn(statement,
          out: out, indent: indent, headIndented: headIndented);
    }

    throw UnsupportedError("Can't handle statement: $statement");
  }

  StringBuffer generateASTBranch(ASTBranch branch,
      {StringBuffer? out, String indent = '', bool headIndented = true}) {
    if (branch is ASTBranchIfBlock) {
      return generateASTBranchIfBlock(branch,
          out: out, indent: indent, headIndented: headIndented);
    } else if (branch is ASTBranchIfElseBlock) {
      return generateASTBranchIfElseBlock(branch,
          out: out, indent: indent, headIndented: headIndented);
    } else if (branch is ASTBranchIfElseIfsElseBlock) {
      return generateASTBranchIfElseIfsElseBlock(branch,
          out: out, indent: indent, headIndented: headIndented);
    }

    throw UnsupportedError("Can't handle branch: $branch");
  }

  StringBuffer generateASTStatementForLoop(ASTStatementForLoop forLoop,
      {StringBuffer? out, String indent = '', bool headIndented = true}) {
    out ??= StringBuffer();

    if (headIndented) out.write(indent);

    out.write('for (');
    generateASTStatement(forLoop.initStatement,
        out: out, indent: indent, headIndented: false);
    out.write(' ');
    generateASTExpression(forLoop.conditionExpression,
        out: out, indent: indent, headIndented: false);
    out.write(' ; ');
    generateASTExpression(forLoop.continueExpression,
        out: out, indent: indent, headIndented: false);

    out.write(') {\n');

    var blockCode = generateASTBlock(forLoop.loopBlock,
        indent: indent, withBrackets: false);

    out.write(blockCode);
    out.write(indent);
    out.write('}');

    return out;
  }

  StringBuffer generateASTBranchIfBlock(ASTBranchIfBlock branch,
      {StringBuffer? out, String indent = '', bool headIndented = true}) {
    out ??= StringBuffer();

    if (headIndented) out.write(indent);

    out.write('if (');
    generateASTExpression(branch.condition,
        out: out, indent: indent, headIndented: false);
    out.write(') {\n');
    generateASTBlock(branch.block,
        out: out, indent: '$indent  ', withBrackets: false);
    out.write(indent);
    out.write('}\n');

    return out;
  }

  StringBuffer generateASTBranchIfElseBlock(ASTBranchIfElseBlock branch,
      {StringBuffer? out, String indent = '', bool headIndented = true}) {
    out ??= StringBuffer();

    if (headIndented) out.write(indent);

    out.write('if (');
    generateASTExpression(branch.condition,
        out: out, indent: indent, headIndented: false);
    out.write(') {\n');
    generateASTBlock(branch.blockIf,
        out: out, indent: '$indent  ', withBrackets: false);
    out.write(indent);
    out.write('} else {\n');
    generateASTBlock(branch.blockElse,
        out: out, indent: '$indent  ', withBrackets: false);
    out.write(indent);
    out.write('}\n');

    return out;
  }

  StringBuffer generateASTBranchIfElseIfsElseBlock(
      ASTBranchIfElseIfsElseBlock branch,
      {StringBuffer? out,
      String indent = '',
      bool headIndented = true}) {
    out ??= StringBuffer();

    if (headIndented) out.write(indent);

    out.write('if (');
    generateASTExpression(branch.condition,
        out: out, indent: indent, headIndented: false);
    out.write(') {\n');
    generateASTBlock(branch.blockIf,
        out: out, indent: '$indent  ', withBrackets: false);

    for (var branchElseIf in branch.blocksElseIf) {
      out.write(indent);
      out.write('} else if (');
      generateASTExpression(branchElseIf.condition,
          out: out, indent: indent, headIndented: false);
      out.write(') {\n');
      generateASTBlock(branchElseIf.block,
          out: out, indent: '$indent  ', withBrackets: false);
    }

    out.write(indent);
    out.write('} else {\n');
    generateASTBlock(branch.blockElse,
        out: out, indent: '$indent  ', withBrackets: false);
    out.write(indent);
    out.write('}\n');

    return out;
  }

  StringBuffer generateASTStatementExpression(ASTStatementExpression statement,
      {StringBuffer? out, String indent = '', bool headIndented = true}) {
    out ??= StringBuffer();

    if (headIndented) out.write(indent);
    generateASTExpression(statement.expression, out: out);
    out.write(';');
    return out;
  }

  StringBuffer generateASTStatementVariableDeclaration(
      ASTStatementVariableDeclaration statement,
      {StringBuffer? out,
      String indent = '',
      bool headIndented = true}) {
    out ??= StringBuffer();

    if (headIndented) out.write(indent);

    generateASTType(statement.type, out: out);

    out.write(' ');
    out.write(statement.name);
    if (statement.value != null) {
      out.write(' = ');
      generateASTExpression(statement.value!,
          out: out, indent: indent, headIndented: false);
    }
    out.write(';');

    return out;
  }

  StringBuffer generateASTExpressionVariableAssignment(
      ASTExpressionVariableAssignment expression,
      {StringBuffer? out,
      String indent = '',
      bool headIndented = true}) {
    out ??= StringBuffer();

    if (headIndented) out.write(indent);

    generateASTVariable(expression.variable,
        out: out, indent: indent, headIndented: headIndented);

    var op = getASTAssignmentOperatorText(expression.operator);
    out.write(' ');
    out.write(op);
    out.write(' ');
    generateASTExpression(expression.expression,
        out: out, indent: '$indent  ', headIndented: false);

    return out;
  }

  StringBuffer generateASTStatementReturn(ASTStatementReturn statement,
      {StringBuffer? out, String indent = '', bool headIndented = true}) {
    out ??= StringBuffer();
    if (headIndented) out.write(indent);
    out.write('return;');
    return out;
  }

  StringBuffer generateASTStatementReturnNull(ASTStatementReturnNull statement,
      {StringBuffer? out, String indent = '', bool headIndented = true}) {
    out ??= StringBuffer();

    if (headIndented) out.write(indent);
    out.write('return null;');
    return out;
  }

  StringBuffer generateASTStatementReturnValue(
      ASTStatementReturnValue statement,
      {StringBuffer? out,
      String indent = '',
      bool headIndented = true}) {
    out ??= StringBuffer();

    if (headIndented) out.write(indent);
    out.write('return ');
    generateASTValue(statement.value,
        out: out, indent: indent, headIndented: false);
    out.write(';');
    return out;
  }

  StringBuffer generateASTStatementReturnVariable(
      ASTStatementReturnVariable statement,
      {StringBuffer? out,
      String indent = '',
      bool headIndented = true}) {
    out ??= StringBuffer();

    if (headIndented) out.write(indent);
    out.write('return ');
    generateASTVariable(statement.variable,
        out: out, indent: indent, headIndented: false);
    out.write(';');
    return out;
  }

  StringBuffer generateASTStatementReturnWithExpression(
      ASTStatementReturnWithExpression statement,
      {StringBuffer? out,
      String indent = '',
      bool headIndented = true}) {
    out ??= StringBuffer();

    if (headIndented) out.write(indent);
    out.write('return ');
    generateASTExpression(statement.expression,
        out: out, indent: indent, headIndented: false);
    out.write(';');
    return out;
  }

  StringBuffer generateASTExpression(ASTExpression expression,
      {StringBuffer? out, String indent = '', bool headIndented = true}) {
    if (expression is ASTExpressionVariableAccess) {
      return generateASTExpressionVariableAccess(expression,
          out: out, indent: indent, headIndented: headIndented);
    } else if (expression is ASTExpressionVariableAssignment) {
      return generateASTExpressionVariableAssignment(expression,
          out: out, indent: indent, headIndented: headIndented);
    } else if (expression is ASTExpressionVariableEntryAccess) {
      return generateASTExpressionVariableEntryAccess(expression,
          out: out, indent: indent, headIndented: headIndented);
    } else if (expression is ASTExpressionLiteral) {
      return generateASTExpressionLiteral(expression,
          out: out, indent: indent, headIndented: headIndented);
    } else if (expression is ASTExpressionListLiteral) {
      return generateASTExpressionListLiteral(expression,
          out: out, indent: indent, headIndented: headIndented);
    } else if (expression is ASTExpressionMapLiteral) {
      return generateASTExpressionMapLiteral(expression,
          out: out, indent: indent, headIndented: headIndented);
    } else if (expression is ASTExpressionNegation) {
      return generateASTExpressionNegation(expression,
          out: out, indent: indent, headIndented: headIndented);
    } else if (expression is ASTExpressionLocalFunctionInvocation) {
      return generateASTExpressionLocalFunctionInvocation(expression,
          out: out, indent: indent, headIndented: headIndented);
    } else if (expression is ASTExpressionObjectFunctionInvocation) {
      return generateASTExpressionFunctionInvocation(expression,
          out: out, indent: indent, headIndented: headIndented);
    } else if (expression is ASTExpressionOperation) {
      return generateASTExpressionOperation(expression,
          out: out, indent: indent, headIndented: headIndented);
    }

    throw UnsupportedError("Can't generate expression: $expression");
  }

  StringBuffer generateASTExpressionOperation(ASTExpressionOperation expression,
      {StringBuffer? out, String indent = '', bool headIndented = true}) {
    out ??= StringBuffer();

    if (headIndented) out.write(indent);

    var expression1 = expression.expression1;
    var expression2 = expression.expression2;

    var op = resolveASTExpressionOperatorText(
      expression.operator,
      expression1.literalNumType,
      expression2.literalNumType,
    );

    generateASTExpression(expression1,
        out: out, indent: '$indent  ', headIndented: false);

    out.write(' ');
    out.write(op);
    out.write(' ');

    generateASTExpression(expression2,
        out: out, indent: '$indent  ', headIndented: false);

    return out;
  }

  String resolveASTExpressionOperatorText(
      ASTExpressionOperator operator, ASTNumType aNumType, ASTNumType bNumType);

  StringBuffer generateASTExpressionLiteral(ASTExpressionLiteral expression,
      {StringBuffer? out, String indent = '', bool headIndented = true}) {
    out ??= StringBuffer();
    if (headIndented) out.write(indent);
    generateASTValue(expression.value,
        out: out, indent: indent, headIndented: false);
    return out;
  }

  StringBuffer generateASTExpressionListLiteral(
      ASTExpressionListLiteral expression,
      {StringBuffer? out,
      String indent = '',
      bool headIndented = true}) {
    out ??= StringBuffer();

    if (headIndented) out.write(indent);

    final type = expression.type;
    if (type != null) {
      out.write('<');
      generateASTType(type, out: out);
      out.write('>');
    }

    out.write('[');

    var valuesExpressions = expression.valuesExpressions;
    for (var i = 0; i < valuesExpressions.length; ++i) {
      var e = valuesExpressions[i];

      if (i > 0) {
        out.write(', ');
      }
      generateASTExpression(e, out: out);
    }

    out.write(']');

    return out;
  }

  StringBuffer generateASTExpressionMapLiteral(
      ASTExpressionMapLiteral expression,
      {StringBuffer? out,
      String indent = '',
      bool headIndented = true}) {
    out ??= StringBuffer();

    if (headIndented) out.write(indent);

    final keyType = expression.keyType;
    final valueType = expression.valueType;

    if (keyType != null && valueType != null) {
      out.write('<');
      generateASTType(keyType, out: out);
      out.write(',');
      generateASTType(valueType, out: out);
      out.write('>');
    }

    out.write('{');

    var entriesExpressions = expression.entriesExpressions;
    for (var i = 0; i < entriesExpressions.length; ++i) {
      var e = entriesExpressions[i];

      if (i > 0) {
        out.write(', ');
      }

      generateASTExpression(e.key, out: out);
      out.write(": ");
      generateASTExpression(e.value, out: out);
    }

    out.write('}');

    return out;
  }

  StringBuffer generateASTExpressionNegation(ASTExpressionNegation expression,
      {StringBuffer? out, String indent = '', bool headIndented = true}) {
    out ??= StringBuffer();

    if (headIndented) out.write(indent);

    out.write('!');

    generateASTExpression(expression.expression,
        out: out, indent: indent, headIndented: false);

    return out;
  }

  StringBuffer generateASTExpressionFunctionInvocation(
      ASTExpressionObjectFunctionInvocation expression,
      {StringBuffer? out,
      String indent = '',
      bool headIndented = true}) {
    out ??= StringBuffer();

    if (headIndented) out.write(indent);

    var functionName = expression.name;

    if (expression.variable.isTypeIdentifier) {
      var typeIdentifier = expression.variable.typeIdentifier;
      functionName = normalizeTypeFunction(typeIdentifier!.name, functionName);
    }

    generateASTVariable(expression.variable,
        callingFunction: functionName,
        out: out,
        indent: indent,
        headIndented: false);
    out.write('.');

    out.write(functionName);
    out.write('(');

    var arguments = expression.arguments;
    for (var i = 0; i < arguments.length; ++i) {
      var arg = arguments[i];
      if (i > 0) out.write(', ');
      generateASTExpression(arg,
          out: out, indent: '$indent  ', headIndented: false);
    }
    out.write(')');

    return out;
  }

  StringBuffer generateASTExpressionLocalFunctionInvocation(
      ASTExpressionLocalFunctionInvocation expression,
      {String indent = '',
      StringBuffer? out,
      bool headIndented = true}) {
    out ??= StringBuffer();

    if (headIndented) out.write(indent);

    out.write(expression.name);
    out.write('(');

    var arguments = expression.arguments;
    for (var i = 0; i < arguments.length; ++i) {
      var arg = arguments[i];
      if (i > 0) out.write(', ');

      generateASTExpression(arg,
          out: out, indent: '$indent  ', headIndented: false);
    }
    out.write(')');

    return out;
  }

  StringBuffer generateASTExpressionVariableAccess(
      ASTExpressionVariableAccess expression,
      {StringBuffer? out,
      String indent = '',
      bool headIndented = true}) {
    out ??= StringBuffer();

    if (headIndented) out.write(indent);
    generateASTVariable(expression.variable,
        out: out, indent: indent, headIndented: false);

    return out;
  }

  StringBuffer generateASTExpressionVariableEntryAccess(
      ASTExpressionVariableEntryAccess expression,
      {StringBuffer? out,
      String indent = '',
      bool headIndented = true}) {
    out ??= StringBuffer();

    if (headIndented) out.write(indent);

    generateASTVariable(expression.variable,
        out: out, indent: indent, headIndented: headIndented);
    out.write('[');
    generateASTExpression(expression.expression,
        out: out, indent: indent, headIndented: false);
    out.write(']');
    return out;
  }

  StringBuffer generateASTVariable(ASTVariable variable,
      {String? callingFunction,
      StringBuffer? out,
      String indent = '',
      bool headIndented = true}) {
    if (variable is ASTScopeVariable) {
      return generateASTScopeVariable(variable,
          callingFunction: callingFunction,
          out: out,
          indent: indent,
          headIndented: headIndented);
    } else {
      return generateASTVariableGeneric(variable,
          callingFunction: callingFunction,
          out: out,
          indent: indent,
          headIndented: headIndented);
    }
  }

  StringBuffer generateASTScopeVariable(ASTScopeVariable variable,
      {String? callingFunction,
      StringBuffer? out,
      String indent = '',
      bool headIndented = true}) {
    out ??= StringBuffer();

    if (headIndented) out.write(indent);

    var name = variable.name;

    if (variable.isTypeIdentifier) {
      var typeIdentifier = variable.typeIdentifier;
      name = typeIdentifier!.name;
      name = normalizeTypeName(name, callingFunction);
    }

    out.write(name);

    return out;
  }

  StringBuffer generateASTVariableGeneric(ASTVariable variable,
      {String? callingFunction,
      StringBuffer? out,
      String indent = '',
      bool headIndented = true}) {
    out ??= StringBuffer();

    if (headIndented) out.write(indent);
    out.write(variable.name);
    return out;
  }

  StringBuffer generateASTValue(ASTValue value,
      {StringBuffer? out, String indent = '', bool headIndented = true}) {
    if (value is ASTValueString) {
      return generateASTValueString(value,
          out: out, indent: indent, headIndented: headIndented);
    } else if (value is ASTValueInt) {
      return generateASTValueInt(value,
          out: out, indent: indent, headIndented: headIndented);
    } else if (value is ASTValueDouble) {
      return generateASTValueDouble(value,
          out: out, indent: indent, headIndented: headIndented);
    } else if (value is ASTValueNull) {
      return generateASTValueNull(value,
          out: out, indent: indent, headIndented: headIndented);
    } else if (value is ASTValueVar) {
      return generateASTValueVar(value,
          out: out, indent: indent, headIndented: headIndented);
    } else if (value is ASTValueObject) {
      return generateASTValueObject(value,
          out: out, indent: indent, headIndented: headIndented);
    } else if (value is ASTValueStatic) {
      return generateASTValueStatic(value,
          out: out, indent: indent, headIndented: headIndented);
    } else if (value is ASTValueStringVariable) {
      return generateASTValueStringVariable(value, out: out, indent: indent);
    } else if (value is ASTValueStringConcatenation) {
      return generateASTValueStringConcatenation(value,
          out: out, indent: indent);
    } else if (value is ASTValueStringExpression) {
      return generateASTValueStringExpression(value, indent: indent, out: out);
    } else if (value is ASTValueArray) {
      return generateASTValueArray(value,
          out: out, indent: indent, headIndented: headIndented);
    } else if (value is ASTValueArray2D) {
      return generateASTValueArray2D(value,
          out: out, indent: indent, headIndented: headIndented);
    } else if (value is ASTValueArray3D) {
      return generateASTValueArray3D(value,
          out: out, indent: indent, headIndented: headIndented);
    }

    throw UnsupportedError("Can't generate value: $value");
  }

  StringBuffer generateASTValueStringConcatenation(
      ASTValueStringConcatenation value,
      {StringBuffer? out,
      String indent = ''});

  StringBuffer generateASTValueStringVariable(ASTValueStringVariable value,
      {StringBuffer? out, String indent = '', bool precededByString = false});

  StringBuffer generateASTValueStringExpression(ASTValueStringExpression value,
      {StringBuffer? out, String indent = ''});

  StringBuffer generateASTValueString(ASTValueString value,
      {StringBuffer? out, String indent = '', bool headIndented = true});

  StringBuffer generateASTValueInt(ASTValueInt value,
      {StringBuffer? out, String indent = '', bool headIndented = true}) {
    out ??= StringBuffer();

    if (headIndented) out.write(indent);
    out.write(value.value);
    return out;
  }

  StringBuffer generateASTValueDouble(ASTValueDouble value,
      {StringBuffer? out, String indent = '', bool headIndented = true}) {
    out ??= StringBuffer();

    if (headIndented) out.write(indent);
    out.write(value.value);
    return out;
  }

  StringBuffer generateASTValueNull(ASTValueNull value,
      {StringBuffer? out, String indent = '', bool headIndented = true}) {
    out ??= StringBuffer();

    if (headIndented) out.write(indent);
    out.write('null');
    return out;
  }

  StringBuffer generateASTValueVar(ASTValueVar value,
      {StringBuffer? out, String indent = '', bool headIndented = true}) {
    out ??= StringBuffer();

    if (headIndented) out.write(indent);
    out.write(value.value);
    return out;
  }

  StringBuffer generateASTValueObject(ASTValueObject value,
      {StringBuffer? out, String indent = '', bool headIndented = true}) {
    out ??= StringBuffer();

    if (headIndented) out.write(indent);
    out.write(value.value);
    return out;
  }

  StringBuffer generateASTValueStatic(ASTValueStatic value,
      {StringBuffer? out, String indent = '', bool headIndented = true}) {
    var v = value.value;

    if (v is ASTNode) {
      return generateASTNode(v,
          out: out, indent: indent, headIndented: headIndented);
    }

    out ??= StringBuffer();
    out.write(value.value);
    return out;
  }

  StringBuffer generateASTValueArray(ASTValueArray value,
      {StringBuffer? out, String indent = '', bool headIndented = true});

  StringBuffer generateASTValueArray2D(ASTValueArray2D value,
      {StringBuffer? out, String indent = '', bool headIndented = true});

  StringBuffer generateASTValueArray3D(ASTValueArray3D value,
      {StringBuffer? out, String indent = '', bool headIndented = true});
}
