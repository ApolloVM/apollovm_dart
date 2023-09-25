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
      {StringBuffer? s, String indent = '', bool headIndented = true}) {
    if (node is ASTValue) {
      return generateASTValue(node,
          s: s, indent: indent, headIndented: headIndented);
    } else if (node is ASTExpression) {
      return generateASTExpression(node,
          s: s, indent: indent, headIndented: headIndented);
    } else if (node is ASTRoot) {
      return generateASTRoot(node, s: s, indent: indent);
    } else if (node is ASTClassNormal) {
      return generateASTClass(node, s: s, indent: indent);
    } else if (node is ASTBlock) {
      return generateASTBlock(node, s: s, indent: indent);
    } else if (node is ASTStatement) {
      return generateASTStatement(node,
          s: s, indent: indent, headIndented: headIndented);
    } else if (node is ASTClassFunctionDeclaration) {
      return generateASTClassFunctionDeclaration(node, s: s, indent: indent);
    } else if (node is ASTFunctionDeclaration) {
      return generateASTFunctionDeclaration(node, s: s, indent: indent);
    }

    throw UnsupportedError("Can't handle ASTNode: $node");
  }

  StringBuffer generateASTRoot(ASTRoot root,
      {String indent = '', StringBuffer? s, bool withBrackets = true}) {
    s ??= StringBuffer();

    generateASTBlock(root, s: s, withBrackets: false);

    for (var clazz in root.classes) {
      generateASTClass(clazz, s: s);
    }

    return s;
  }

  StringBuffer generateASTBlock(ASTBlock block,
      {StringBuffer? s,
      String indent = '',
      bool withBrackets = true,
      bool withBlankHeadLine = false}) {
    s ??= StringBuffer();

    var indent2 = '$indent  ';

    if (withBrackets) s.write('$indent{\n');

    if (withBlankHeadLine) s.write('\n');

    if (block is ASTClassNormal) {
      for (var field in block.fields) {
        generateASTClassField(field, s: s, indent: indent2);
      }

      if (block.fields.isNotEmpty) {
        s.write('\n');
      }
    }

    for (var set in block.functions) {
      for (var f in set.functions) {
        if (f is ASTClassFunctionDeclaration) {
          generateASTClassFunctionDeclaration(f, s: s, indent: indent2);
        } else {
          generateASTFunctionDeclaration(f, s: s, indent: indent2);
        }
      }
    }

    for (var stm in block.statements) {
      generateASTStatement(stm, s: s, indent: indent2);
      s.write('\n');
    }

    if (withBrackets) s.write('$indent}\n');

    return s;
  }

  StringBuffer generateASTClass(ASTClassNormal clazz,
      {StringBuffer? s, String indent = ''});

  StringBuffer generateASTClassField(ASTClassField field,
      {StringBuffer? s, String indent = ''});

  StringBuffer generateASTClassFunctionDeclaration(
      ASTClassFunctionDeclaration f,
      {StringBuffer? s,
      String indent = ''});

  StringBuffer generateASTFunctionDeclaration(ASTFunctionDeclaration f,
      {StringBuffer? s, String indent = ''});

  StringBuffer generateASTParametersDeclaration(
      ASTParametersDeclaration parameters,
      {StringBuffer? s,
      String indent = ''});

  StringBuffer generateASTFunctionParameterDeclaration(
      ASTFunctionParameterDeclaration parameter,
      {StringBuffer? s,
      String indent = ''});

  StringBuffer generateASTParameterDeclaration(
      ASTParameterDeclaration parameter,
      {StringBuffer? s,
      String indent = ''}) {
    s ??= StringBuffer();

    var typeStr = generateASTType(parameter.type);

    s.write(typeStr);
    s.write(' ');
    s.write(parameter.name);
    return s;
  }

  StringBuffer generateASTType(ASTType type,
      {StringBuffer? s, String indent = ''}) {
    if (type is ASTTypeArray) {
      return generateASTTypeArray(type, s: s, indent: indent);
    } else if (type is ASTTypeArray2D) {
      return generateASTTypeArray2D(type, s: s, indent: indent);
    } else if (type is ASTTypeArray3D) {
      return generateASTTypeArray3D(type, s: s, indent: indent);
    }

    return generateASTTypeDefault(type, s: s, indent: indent);
  }

  StringBuffer generateASTTypeArray(ASTTypeArray type,
      {StringBuffer? s, String indent = ''});

  StringBuffer generateASTTypeArray2D(ASTTypeArray2D type,
      {StringBuffer? s, String indent = ''});

  StringBuffer generateASTTypeArray3D(ASTTypeArray3D type,
      {StringBuffer? s, String indent = ''});

  String normalizeTypeName(String typeName, [String? callingFunction]) =>
      typeName;

  String normalizeTypeFunction(String typeName, String functionName) =>
      functionName;

  StringBuffer generateASTTypeDefault(ASTType type,
      {StringBuffer? s, String indent = ''}) {
    s ??= StringBuffer();

    var typeName = normalizeTypeName(type.name);

    s.write(typeName);

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
      {String indent = '', StringBuffer? s, bool headIndented = true}) {
    if (statement is ASTStatementExpression) {
      return generateASTStatementExpression(statement,
          s: s, indent: indent, headIndented: headIndented);
    } else if (statement is ASTStatementVariableDeclaration) {
      return generateASTStatementVariableDeclaration(statement,
          s: s, indent: indent, headIndented: headIndented);
    } else if (statement is ASTBranch) {
      return generateASTBranch(statement,
          s: s, indent: indent, headIndented: headIndented);
    } else if (statement is ASTStatementForLoop) {
      return generateASTStatementForLoop(statement,
          s: s, indent: indent, headIndented: headIndented);
    } else if (statement is ASTStatementReturnNull) {
      return generateASTStatementReturnNull(statement,
          s: s, indent: indent, headIndented: headIndented);
    } else if (statement is ASTStatementReturnValue) {
      return generateASTStatementReturnValue(statement,
          s: s, indent: indent, headIndented: headIndented);
    } else if (statement is ASTStatementReturnVariable) {
      return generateASTStatementReturnVariable(statement,
          s: s, indent: indent, headIndented: headIndented);
    } else if (statement is ASTStatementReturnWithExpression) {
      return generateASTStatementReturnWithExpression(statement,
          s: s, indent: indent, headIndented: headIndented);
    } else if (statement is ASTStatementReturn) {
      return generateASTStatementReturn(statement,
          s: s, indent: indent, headIndented: headIndented);
    }

    throw UnsupportedError("Can't handle statement: $statement");
  }

  StringBuffer generateASTBranch(ASTBranch branch,
      {StringBuffer? s, String indent = '', bool headIndented = true}) {
    if (branch is ASTBranchIfBlock) {
      return generateASTBranchIfBlock(branch,
          s: s, indent: indent, headIndented: headIndented);
    } else if (branch is ASTBranchIfElseBlock) {
      return generateASTBranchIfElseBlock(branch,
          s: s, indent: indent, headIndented: headIndented);
    } else if (branch is ASTBranchIfElseIfsElseBlock) {
      return generateASTBranchIfElseIfsElseBlock(branch,
          s: s, indent: indent, headIndented: headIndented);
    }

    throw UnsupportedError("Can't handle branch: $branch");
  }

  StringBuffer generateASTStatementForLoop(ASTStatementForLoop forLoop,
      {StringBuffer? s, String indent = '', bool headIndented = true}) {
    s ??= StringBuffer();

    if (headIndented) s.write(indent);

    s.write('for (');
    generateASTStatement(forLoop.initStatement,
        s: s, indent: indent, headIndented: false);
    s.write(' ');
    generateASTExpression(forLoop.conditionExpression,
        s: s, indent: indent, headIndented: false);
    s.write(' ; ');
    generateASTExpression(forLoop.continueExpression,
        s: s, indent: indent, headIndented: false);

    s.write(') {\n');

    var blockCode = generateASTBlock(forLoop.loopBlock,
        indent: indent, withBrackets: false);

    s.write(blockCode);
    s.write(indent);
    s.write('}');

    return s;
  }

  StringBuffer generateASTBranchIfBlock(ASTBranchIfBlock branch,
      {StringBuffer? s, String indent = '', bool headIndented = true}) {
    s ??= StringBuffer();

    if (headIndented) s.write(indent);

    s.write('if (');
    generateASTExpression(branch.condition,
        s: s, indent: indent, headIndented: false);
    s.write(') {\n');
    generateASTBlock(branch.block,
        s: s, indent: '$indent  ', withBrackets: false);
    s.write(indent);
    s.write('}\n');

    return s;
  }

  StringBuffer generateASTBranchIfElseBlock(ASTBranchIfElseBlock branch,
      {StringBuffer? s, String indent = '', bool headIndented = true}) {
    s ??= StringBuffer();

    if (headIndented) s.write(indent);

    s.write('if (');
    generateASTExpression(branch.condition,
        s: s, indent: indent, headIndented: false);
    s.write(') {\n');
    generateASTBlock(branch.blockIf,
        s: s, indent: '$indent  ', withBrackets: false);
    s.write(indent);
    s.write('} else {\n');
    generateASTBlock(branch.blockElse,
        s: s, indent: '$indent  ', withBrackets: false);
    s.write(indent);
    s.write('}\n');

    return s;
  }

  StringBuffer generateASTBranchIfElseIfsElseBlock(
      ASTBranchIfElseIfsElseBlock branch,
      {StringBuffer? s,
      String indent = '',
      bool headIndented = true}) {
    s ??= StringBuffer();

    if (headIndented) s.write(indent);

    s.write('if (');
    generateASTExpression(branch.condition,
        s: s, indent: indent, headIndented: false);
    s.write(') {\n');
    generateASTBlock(branch.blockIf,
        s: s, indent: '$indent  ', withBrackets: false);

    for (var branchElseIf in branch.blocksElseIf) {
      s.write(indent);
      s.write('} else if (');
      generateASTExpression(branchElseIf.condition,
          s: s, indent: indent, headIndented: false);
      s.write(') {\n');
      generateASTBlock(branchElseIf.block,
          s: s, indent: '$indent  ', withBrackets: false);
    }

    s.write(indent);
    s.write('} else {\n');
    generateASTBlock(branch.blockElse,
        s: s, indent: '$indent  ', withBrackets: false);
    s.write(indent);
    s.write('}\n');

    return s;
  }

  StringBuffer generateASTStatementExpression(ASTStatementExpression statement,
      {StringBuffer? s, String indent = '', bool headIndented = true}) {
    s ??= StringBuffer();

    if (headIndented) s.write(indent);
    generateASTExpression(statement.expression, s: s);
    s.write(';');
    return s;
  }

  StringBuffer generateASTStatementVariableDeclaration(
      ASTStatementVariableDeclaration statement,
      {StringBuffer? s,
      String indent = '',
      bool headIndented = true}) {
    s ??= StringBuffer();

    if (headIndented) s.write(indent);

    generateASTType(statement.type, s: s);

    s.write(' ');
    s.write(statement.name);
    if (statement.value != null) {
      s.write(' = ');
      generateASTExpression(statement.value!,
          s: s, indent: indent, headIndented: false);
    }
    s.write(';');

    return s;
  }

  StringBuffer generateASTExpressionVariableAssignment(
      ASTExpressionVariableAssignment expression,
      {StringBuffer? s,
      String indent = '',
      bool headIndented = true}) {
    s ??= StringBuffer();

    if (headIndented) s.write(indent);

    generateASTVariable(expression.variable,
        s: s, indent: indent, headIndented: headIndented);

    var op = getASTAssignmentOperatorText(expression.operator);
    s.write(' ');
    s.write(op);
    s.write(' ');
    generateASTExpression(expression.expression,
        s: s, indent: '$indent  ', headIndented: false);

    return s;
  }

  StringBuffer generateASTStatementReturn(ASTStatementReturn statement,
      {StringBuffer? s, String indent = '', bool headIndented = true}) {
    s ??= StringBuffer();
    if (headIndented) s.write(indent);
    s.write('return;');
    return s;
  }

  StringBuffer generateASTStatementReturnNull(ASTStatementReturnNull statement,
      {StringBuffer? s, String indent = '', bool headIndented = true}) {
    s ??= StringBuffer();

    if (headIndented) s.write(indent);
    s.write('return null;');
    return s;
  }

  StringBuffer generateASTStatementReturnValue(
      ASTStatementReturnValue statement,
      {StringBuffer? s,
      String indent = '',
      bool headIndented = true}) {
    s ??= StringBuffer();

    if (headIndented) s.write(indent);
    s.write('return ');
    generateASTValue(statement.value,
        s: s, indent: indent, headIndented: false);
    s.write(';');
    return s;
  }

  StringBuffer generateASTStatementReturnVariable(
      ASTStatementReturnVariable statement,
      {StringBuffer? s,
      String indent = '',
      bool headIndented = true}) {
    s ??= StringBuffer();

    if (headIndented) s.write(indent);
    s.write('return ');
    generateASTVariable(statement.variable,
        s: s, indent: indent, headIndented: false);
    s.write(';');
    return s;
  }

  StringBuffer generateASTStatementReturnWithExpression(
      ASTStatementReturnWithExpression statement,
      {StringBuffer? s,
      String indent = '',
      bool headIndented = true}) {
    s ??= StringBuffer();

    if (headIndented) s.write(indent);
    s.write('return ');
    generateASTExpression(statement.expression,
        s: s, indent: indent, headIndented: false);
    s.write(';');
    return s;
  }

  StringBuffer generateASTExpression(ASTExpression expression,
      {StringBuffer? s, String indent = '', bool headIndented = true}) {
    if (expression is ASTExpressionVariableAccess) {
      return generateASTExpressionVariableAccess(expression,
          s: s, indent: indent, headIndented: headIndented);
    } else if (expression is ASTExpressionVariableAssignment) {
      return generateASTExpressionVariableAssignment(expression,
          s: s, indent: indent, headIndented: headIndented);
    } else if (expression is ASTExpressionVariableEntryAccess) {
      return generateASTExpressionVariableEntryAccess(expression,
          s: s, indent: indent, headIndented: headIndented);
    } else if (expression is ASTExpressionLiteral) {
      return generateASTExpressionLiteral(expression,
          s: s, indent: indent, headIndented: headIndented);
    } else if (expression is ASTExpressionListLiteral) {
      return generateASTExpressionListLiteral(expression,
          s: s, indent: indent, headIndented: headIndented);
    } else if (expression is ASTExpressionMapLiteral) {
      return generateASTExpressionMapLiteral(expression,
          s: s, indent: indent, headIndented: headIndented);
    } else if (expression is ASTExpressionNegation) {
      return generateASTExpressionNegation(expression,
          s: s, indent: indent, headIndented: headIndented);
    } else if (expression is ASTExpressionLocalFunctionInvocation) {
      return generateASTExpressionLocalFunctionInvocation(expression,
          s: s, indent: indent, headIndented: headIndented);
    } else if (expression is ASTExpressionObjectFunctionInvocation) {
      return generateASTExpressionFunctionInvocation(expression,
          s: s, indent: indent, headIndented: headIndented);
    } else if (expression is ASTExpressionOperation) {
      return generateASTExpressionOperation(expression,
          s: s, indent: indent, headIndented: headIndented);
    }

    throw UnsupportedError("Can't generate expression: $expression");
  }

  StringBuffer generateASTExpressionOperation(ASTExpressionOperation expression,
      {StringBuffer? s, String indent = '', bool headIndented = true}) {
    s ??= StringBuffer();

    if (headIndented) s.write(indent);

    var expression1 = expression.expression1;
    var expression2 = expression.expression2;

    var op = resolveASTExpressionOperatorText(
      expression.operator,
      expression1.literalNumType,
      expression2.literalNumType,
    );

    generateASTExpression(expression1,
        s: s, indent: '$indent  ', headIndented: false);

    s.write(' ');
    s.write(op);
    s.write(' ');

    generateASTExpression(expression2,
        s: s, indent: '$indent  ', headIndented: false);

    return s;
  }

  String resolveASTExpressionOperatorText(
      ASTExpressionOperator operator, ASTNumType aNumType, ASTNumType bNumType);

  StringBuffer generateASTExpressionLiteral(ASTExpressionLiteral expression,
      {String indent = '', StringBuffer? s, bool headIndented = true}) {
    s ??= StringBuffer();
    if (headIndented) s.write(indent);
    generateASTValue(expression.value,
        s: s, indent: indent, headIndented: false);
    return s;
  }

  StringBuffer generateASTExpressionListLiteral(
      ASTExpressionListLiteral expression,
      {StringBuffer? s,
      String indent = '',
      bool headIndented = true}) {
    s ??= StringBuffer();

    if (headIndented) s.write(indent);

    final type = expression.type;
    if (type != null) {
      s.write('<');
      generateASTType(type, s: s);
      s.write('>');
    }

    s.write('[');

    var valuesExpressions = expression.valuesExpressions;
    for (var i = 0; i < valuesExpressions.length; ++i) {
      var e = valuesExpressions[i];

      if (i > 0) {
        s.write(', ');
      }
      generateASTExpression(e, s: s);
    }

    s.write(']');

    return s;
  }

  StringBuffer generateASTExpressionMapLiteral(
      ASTExpressionMapLiteral expression,
      {StringBuffer? s,
      String indent = '',
      bool headIndented = true}) {
    s ??= StringBuffer();

    if (headIndented) s.write(indent);

    final keyType = expression.keyType;
    final valueType = expression.valueType;

    if (keyType != null && valueType != null) {
      s.write('<');
      generateASTType(keyType, s: s);
      s.write(',');
      generateASTType(valueType, s: s);
      s.write('>');
    }

    s.write('{');

    var entriesExpressions = expression.entriesExpressions;
    for (var i = 0; i < entriesExpressions.length; ++i) {
      var e = entriesExpressions[i];

      if (i > 0) {
        s.write(', ');
      }

      generateASTExpression(e.key, s: s);
      s.write(": ");
      generateASTExpression(e.value, s: s);
    }

    s.write('}');

    return s;
  }

  StringBuffer generateASTExpressionNegation(ASTExpressionNegation expression,
      {String indent = '', StringBuffer? s, bool headIndented = true}) {
    s ??= StringBuffer();

    if (headIndented) s.write(indent);

    s.write('!');

    generateASTExpression(expression.expression,
        s: s, indent: indent, headIndented: false);

    return s;
  }

  StringBuffer generateASTExpressionFunctionInvocation(
      ASTExpressionObjectFunctionInvocation expression,
      {String indent = '',
      StringBuffer? s,
      bool headIndented = true}) {
    s ??= StringBuffer();

    if (headIndented) s.write(indent);

    var functionName = expression.name;

    if (expression.variable.isTypeIdentifier) {
      var typeIdentifier = expression.variable.typeIdentifier;
      functionName = normalizeTypeFunction(typeIdentifier!.name, functionName);
    }

    generateASTVariable(expression.variable,
        callingFunction: functionName,
        s: s,
        indent: indent,
        headIndented: false);
    s.write('.');

    s.write(functionName);
    s.write('(');

    var arguments = expression.arguments;
    for (var i = 0; i < arguments.length; ++i) {
      var arg = arguments[i];
      if (i > 0) s.write(', ');
      generateASTExpression(arg,
          s: s, indent: '$indent  ', headIndented: false);
    }
    s.write(')');

    return s;
  }

  StringBuffer generateASTExpressionLocalFunctionInvocation(
      ASTExpressionLocalFunctionInvocation expression,
      {String indent = '',
      StringBuffer? s,
      bool headIndented = true}) {
    s ??= StringBuffer();

    if (headIndented) s.write(indent);

    s.write(expression.name);
    s.write('(');

    var arguments = expression.arguments;
    for (var i = 0; i < arguments.length; ++i) {
      var arg = arguments[i];
      if (i > 0) s.write(', ');

      generateASTExpression(arg,
          s: s, indent: '$indent  ', headIndented: false);
    }
    s.write(')');

    return s;
  }

  StringBuffer generateASTExpressionVariableAccess(
      ASTExpressionVariableAccess expression,
      {StringBuffer? s,
      String indent = '',
      bool headIndented = true}) {
    s ??= StringBuffer();

    if (headIndented) s.write(indent);
    generateASTVariable(expression.variable,
        s: s, indent: indent, headIndented: false);

    return s;
  }

  StringBuffer generateASTExpressionVariableEntryAccess(
      ASTExpressionVariableEntryAccess expression,
      {StringBuffer? s,
      String indent = '',
      bool headIndented = true}) {
    s ??= StringBuffer();

    if (headIndented) s.write(indent);

    generateASTVariable(expression.variable,
        s: s, indent: indent, headIndented: headIndented);
    s.write('[');
    generateASTExpression(expression.expression,
        s: s, indent: indent, headIndented: false);
    s.write(']');
    return s;
  }

  StringBuffer generateASTVariable(ASTVariable variable,
      {String? callingFunction,
      StringBuffer? s,
      String indent = '',
      bool headIndented = true}) {
    if (variable is ASTScopeVariable) {
      return generateASTScopeVariable(variable,
          callingFunction: callingFunction,
          s: s,
          indent: indent,
          headIndented: headIndented);
    } else {
      return generateASTVariableGeneric(variable,
          callingFunction: callingFunction,
          s: s,
          indent: indent,
          headIndented: headIndented);
    }
  }

  StringBuffer generateASTScopeVariable(ASTScopeVariable variable,
      {String? callingFunction,
      StringBuffer? s,
      String indent = '',
      bool headIndented = true}) {
    s ??= StringBuffer();

    if (headIndented) s.write(indent);

    var name = variable.name;

    if (variable.isTypeIdentifier) {
      var typeIdentifier = variable.typeIdentifier;
      name = typeIdentifier!.name;
      name = normalizeTypeName(name, callingFunction);
    }

    s.write(name);

    return s;
  }

  StringBuffer generateASTVariableGeneric(ASTVariable variable,
      {String? callingFunction,
      StringBuffer? s,
      String indent = '',
      bool headIndented = true}) {
    s ??= StringBuffer();

    if (headIndented) s.write(indent);
    s.write(variable.name);
    return s;
  }

  StringBuffer generateASTValue(ASTValue value,
      {StringBuffer? s, String indent = '', bool headIndented = true}) {
    if (value is ASTValueString) {
      return generateASTValueString(value,
          s: s, indent: indent, headIndented: headIndented);
    } else if (value is ASTValueInt) {
      return generateASTValueInt(value,
          s: s, indent: indent, headIndented: headIndented);
    } else if (value is ASTValueDouble) {
      return generateASTValueDouble(value,
          s: s, indent: indent, headIndented: headIndented);
    } else if (value is ASTValueNull) {
      return generateASTValueNull(value,
          s: s, indent: indent, headIndented: headIndented);
    } else if (value is ASTValueVar) {
      return generateASTValueVar(value,
          s: s, indent: indent, headIndented: headIndented);
    } else if (value is ASTValueObject) {
      return generateASTValueObject(value,
          s: s, indent: indent, headIndented: headIndented);
    } else if (value is ASTValueStatic) {
      return generateASTValueStatic(value,
          s: s, indent: indent, headIndented: headIndented);
    } else if (value is ASTValueStringVariable) {
      return generateASTValueStringVariable(value, s: s, indent: indent);
    } else if (value is ASTValueStringConcatenation) {
      return generateASTValueStringConcatenation(value, s: s, indent: indent);
    } else if (value is ASTValueStringExpression) {
      return generateASTValueStringExpression(value, indent: indent, s: s);
    } else if (value is ASTValueArray) {
      return generateASTValueArray(value,
          s: s, indent: indent, headIndented: headIndented);
    } else if (value is ASTValueArray2D) {
      return generateASTValueArray2D(value,
          s: s, indent: indent, headIndented: headIndented);
    } else if (value is ASTValueArray3D) {
      return generateASTValueArray3D(value,
          s: s, indent: indent, headIndented: headIndented);
    }

    throw UnsupportedError("Can't generate value: $value");
  }

  StringBuffer generateASTValueStringConcatenation(
      ASTValueStringConcatenation value,
      {StringBuffer? s,
      String indent = ''});

  StringBuffer generateASTValueStringVariable(ASTValueStringVariable value,
      {StringBuffer? s, String indent = '', bool precededByString = false});

  StringBuffer generateASTValueStringExpression(ASTValueStringExpression value,
      {StringBuffer? s, String indent = ''});

  StringBuffer generateASTValueString(ASTValueString value,
      {StringBuffer? s, String indent = '', bool headIndented = true});

  StringBuffer generateASTValueInt(ASTValueInt value,
      {StringBuffer? s, String indent = '', bool headIndented = true}) {
    s ??= StringBuffer();

    if (headIndented) s.write(indent);
    s.write(value.value);
    return s;
  }

  StringBuffer generateASTValueDouble(ASTValueDouble value,
      {StringBuffer? s, String indent = '', bool headIndented = true}) {
    s ??= StringBuffer();

    if (headIndented) s.write(indent);
    s.write(value.value);
    return s;
  }

  StringBuffer generateASTValueNull(ASTValueNull value,
      {StringBuffer? s, String indent = '', bool headIndented = true}) {
    s ??= StringBuffer();

    if (headIndented) s.write(indent);
    s.write('null');
    return s;
  }

  StringBuffer generateASTValueVar(ASTValueVar value,
      {StringBuffer? s, String indent = '', bool headIndented = true}) {
    s ??= StringBuffer();

    if (headIndented) s.write(indent);
    s.write(value.value);
    return s;
  }

  StringBuffer generateASTValueObject(ASTValueObject value,
      {StringBuffer? s, String indent = '', bool headIndented = true}) {
    s ??= StringBuffer();

    if (headIndented) s.write(indent);
    s.write(value.value);
    return s;
  }

  StringBuffer generateASTValueStatic(ASTValueStatic value,
      {StringBuffer? s, String indent = '', bool headIndented = true}) {
    var v = value.value;

    if (v is ASTNode) {
      return generateASTNode(v,
          s: s, indent: indent, headIndented: headIndented);
    }

    s ??= StringBuffer();
    s.write(value.value);
    return s;
  }

  StringBuffer generateASTValueArray(ASTValueArray value,
      {StringBuffer? s, String indent = '', bool headIndented = true});

  StringBuffer generateASTValueArray2D(ASTValueArray2D value,
      {StringBuffer? s, String indent = '', bool headIndented = true});

  StringBuffer generateASTValueArray3D(ASTValueArray3D value,
      {StringBuffer? s, String indent = '', bool headIndented = true});
}
