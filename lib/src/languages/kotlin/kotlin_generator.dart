// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import '../../apollovm_code_generator.dart';
import '../../apollovm_code_storage.dart';
import '../../ast/apollovm_ast_expression.dart';
import '../../ast/apollovm_ast_statement.dart';
import '../../ast/apollovm_ast_toplevel.dart';
import '../../ast/apollovm_ast_type.dart';
import '../../ast/apollovm_ast_value.dart';
import '../../ast/apollovm_ast_variable.dart';

/// Kotlin implementation of an [ApolloCodeGenerator].
class ApolloCodeGeneratorKotlin extends ApolloCodeGenerator {
  ApolloCodeGeneratorKotlin(ApolloSourceCodeStorage codeStorage)
    : super('kotlin', codeStorage);

  @override
  StringBuffer generateASTExpressionLiteralFunction(
    ASTExpressionLiteralFunction expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);

    var f = expression.function;

    // Kotlin lambda: `{ params -> body }`. Parameters are listed without
    // parentheses; an empty list omits the `->`.
    out.write('{ ');
    if (f.parametersSize > 0) {
      generateASTParametersDeclaration(f.parameters, out: out);
      out.write(' -> ');
    }

    var single = singleReturnExpression(f);
    if (single != null) {
      generateASTExpression(single, out: out, headIndented: false);
      out.write(' }');
    } else {
      out.write('\n');
      var blockCode = generateASTBlock(f, indent: indent, withBrackets: false);
      out.write(blockCode);
      out.write(indent);
      out.write('}');
    }

    return out;
  }

  @override
  StringBuffer generateASTExpressionConditional(
    ASTExpressionConditional expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);

    // Kotlin has no `?:` ternary; `if/else` is an expression that yields a
    // value: `if (cond) valueIfTrue else valueIfFalse`.
    out.write('if (');
    generateASTExpression(expression.condition, out: out, headIndented: false);
    out.write(') ');
    generateASTExpression(
      expression.valueIfTrue,
      out: out,
      headIndented: false,
    );
    out.write(' else ');
    generateASTExpression(
      expression.valueIfFalse,
      out: out,
      headIndented: false,
    );

    return out;
  }

  @override
  String normalizeTypeName(String typeName, [String? callingFunction]) {
    switch (typeName) {
      case 'int':
      case 'Integer':
        return 'Int';
      case 'double':
        return 'Double';
      case 'num':
        return 'Double';
      case 'bool':
        return 'Boolean';
      case 'void':
        return 'Unit';
      case 'dynamic':
      case 'Object':
        return 'Any';
      default:
        return typeName;
    }
  }

  @override
  String generateASTCatchClauseHeader(ASTCatchClause catchClause) {
    var name = catchClause.variableName ?? 'e';
    var type = catchClause.exceptionType;
    var typeStr = type != null ? '${generateASTType(type)}' : 'Throwable';
    return 'catch ($name: $typeStr)';
  }

  @override
  String normalizeTypeFunction(String typeName, String functionName) {
    switch (typeName) {
      case 'int':
      case 'Int':
      case 'Integer':
        {
          switch (functionName) {
            case 'parse':
            case 'parseInt':
              return 'toInt';
            default:
              return functionName;
          }
        }
      default:
        return functionName;
    }
  }

  @override
  StringBuffer generateASTStatementImport(
    ASTStatementImport import, {
    StringBuffer? out,
    String indent = '',
  }) {
    final path = import.path;

    out ??= newOutput();

    out.write('import ');
    out.write(path);
    out.write('\n');

    return out;
  }

  @override
  StringBuffer generateASTClass(
    ASTClassNormal clazz, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    if (clazz is ASTClassEnum) {
      return generateASTClassEnum(clazz, out: out, indent: indent);
    }

    var code = generateASTBlock(
      clazz,
      withBrackets: true,
      withBlankHeadLine: true,
    );

    out.write('class ');
    out.write(clazz.name);
    out.write(' ');
    out.write(code);

    return out;
  }

  /// Generates a Kotlin `enum class` declaration.
  StringBuffer generateASTClassEnum(
    ASTClassEnum clazz, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    out.write(indent);
    out.write('enum class ');
    out.write(clazz.name);
    out.write(' {\n');

    var entries = clazz.entries;
    for (var i = 0; i < entries.length; ++i) {
      out.write('$indent  ');
      out.write(entries[i].name);
      if (i < entries.length - 1) out.write(',');
      out.write('\n');
    }

    out.write('$indent}\n');

    return out;
  }

  @override
  StringBuffer generateASTClassField(
    ASTClassField field, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    var typeCode = generateASTType(field.type);

    out.write(indent);

    out.write(field.finalValue ? 'val ' : 'var ');
    out.write(field.name);
    out.write(': ');
    out.write(typeCode);

    if (field is ASTClassFieldWithInitialValue) {
      var initialValueCode = generateASTExpression(
        field.initialValue,
        indent: "$indent  ",
        headIndented: false,
      );
      out.write(' = ');
      out.write(initialValueCode);
    }

    out.write('\n');

    return out;
  }

  @override
  StringBuffer generateASTClassConstructorDeclaration(
    ASTClassConstructorDeclaration c, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    var blockCode = generateASTBlock(c, indent: indent, withBrackets: false);

    out.write(indent);

    out.write('constructor');
    _generateFunctionParamsAndBlock(c, blockCode, out, indent);

    return out;
  }

  @override
  StringBuffer generateASTFunctionDeclaration(
    ASTFunctionDeclaration f, {
    StringBuffer? out,
    String indent = '',
  }) {
    return _generateASTFunctionDeclarationImpl(f, out, indent);
  }

  @override
  StringBuffer generateASTClassFunctionDeclaration(
    ASTClassFunctionDeclaration f, {
    StringBuffer? out,
    String indent = '',
  }) {
    return _generateASTFunctionDeclarationImpl(f, out, indent);
  }

  StringBuffer _generateASTFunctionDeclarationImpl(
    ASTFunctionDeclaration f,
    StringBuffer? out,
    String indent,
  ) {
    out ??= newOutput();

    var blockCode = generateASTBlock(f, indent: indent, withBrackets: false);

    out.write(indent);

    // Dart `async` maps to a Kotlin `suspend fun`; `Future<T>` collapses to `T`
    // (suspension is implicit in coroutines — see [generateASTExpressionAwait]).
    var returnType = f.returnType;
    if (f.modifiers.isAsync) {
      out.write('suspend ');
      if (returnType is ASTTypeFuture) {
        returnType = returnType.futureValueType;
      }
    }

    out.write('fun ');
    out.write(f.name);
    _generateFunctionParamsAndBlock(f, blockCode, out, indent, returnType);

    return out;
  }

  @override
  StringBuffer generateASTExpressionAwait(
    ASTExpressionAwait expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    // Kotlin suspends implicitly when calling a `suspend` function, so `await e`
    // becomes just `e`.
    return generateASTExpression(
      expression.expression,
      out: out,
      indent: indent,
      headIndented: headIndented,
    );
  }

  void _generateFunctionParamsAndBlock(
    ASTInvocableDeclaration f,
    StringBuffer blockCode,
    StringBuffer out,
    String indent, [
    ASTType? returnType,
  ]) {
    out.write('(');

    if (f.parametersSize > 0) {
      generateASTParametersDeclaration(f.parameters, out: out);
    }

    out.write(')');

    if (returnType != null &&
        returnType is! ASTTypeVoid &&
        normalizeTypeName(returnType.name) != 'Unit') {
      out.write(': ');
      generateASTType(returnType, out: out);
    }

    out.write(' {\n');
    out.write(blockCode);
    out.write(indent);
    out.write('}\n\n');
  }

  @override
  StringBuffer generateASTParametersDeclaration(
    ASTParametersDeclaration parameters, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    var positionalParameters = parameters.positionalParameters;
    if (positionalParameters != null) {
      for (var i = 0; i < positionalParameters.length; ++i) {
        var p = positionalParameters[i];
        if (i > 0) out.write(', ');
        generateASTParameterDeclaration(p, out: out);
      }
    }

    var optionalParameters = parameters.optionalParameters;
    if (optionalParameters != null) {
      for (var i = 0; i < optionalParameters.length; ++i) {
        var p = optionalParameters[i];
        if (i > 0) out.write(', ');
        generateASTParameterDeclaration(p, out: out);
      }
    }

    var namedParameters = parameters.namedParameters;
    if (namedParameters != null) {
      for (var i = 0; i < namedParameters.length; ++i) {
        var p = namedParameters[i];
        if (i > 0) out.write(', ');
        generateASTParameterDeclaration(p, out: out);
      }
    }

    return out;
  }

  @override
  StringBuffer generateASTParameterDeclaration(
    ASTParameterDeclaration parameter, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    out.write(parameter.name);
    out.write(': ');
    generateASTType(parameter.type, out: out);

    return out;
  }

  @override
  StringBuffer generateASTFunctionParameterDeclaration(
    ASTFunctionParameterDeclaration parameter, {
    StringBuffer? out,
    String indent = '',
  }) {
    return generateASTParameterDeclaration(parameter, out: out, indent: indent);
  }

  @override
  StringBuffer generateASTStatementVariableDeclaration(
    ASTStatementVariableDeclaration statement, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    out.write(statement.unmodifiable ? 'val ' : 'var ');
    out.write(statement.name);

    final type = statement.type;
    if (type is! ASTTypeVar) {
      out.write(': ');
      generateASTType(type, out: out);
    }

    if (statement.value != null) {
      out.write(' = ');
      generateASTExpression(
        statement.value!,
        out: out,
        indent: indent,
        headIndented: false,
      );
    }

    return out;
  }

  @override
  StringBuffer generateASTStatementExpression(
    ASTStatementExpression statement, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);
    generateASTExpression(statement.expression, out: out);
    return out;
  }

  @override
  StringBuffer generateASTStatementForEach(
    ASTStatementForEach forEach, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    out.write('for (');
    out.write(forEach.variableName);
    out.write(' in ');

    generateASTExpression(
      forEach.iterableExpression,
      out: out,
      indent: indent,
      headIndented: false,
    );

    out.write(') {\n');

    var blockCode = generateASTBlock(
      forEach.loopBlock,
      indent: indent,
      withBrackets: false,
    );

    out.write(blockCode);
    out.write(indent);
    out.write('}');

    return out;
  }

  /// Kotlin uses `when` instead of `switch` (no fall-through).
  @override
  StringBuffer generateASTStatementSwitch(
    ASTStatementSwitch statement, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    var indent2 = '$indent  ';

    out.write('when (');
    generateASTExpression(
      statement.expression,
      out: out,
      indent: indent,
      headIndented: false,
    );
    out.write(') {\n');

    for (var c in statement.cases) {
      out.write(indent2);
      if (c.isDefault) {
        out.write('else -> {\n');
      } else {
        generateASTExpression(c.value!, out: out, headIndented: false);
        out.write(' -> {\n');
      }
      out.write(
        generateASTBlock(c.block, indent: indent2, withBrackets: false),
      );
      out.write(indent2);
      out.write('}\n');
    }

    out.write(indent);
    out.write('}');

    return out;
  }

  @override
  StringBuffer generateASTStatementReturnValue(
    ASTStatementReturnValue statement, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);
    out.write('return ');
    generateASTValue(
      statement.value,
      out: out,
      indent: indent,
      headIndented: false,
    );
    return out;
  }

  @override
  StringBuffer generateASTStatementReturn(
    ASTStatementReturn statement, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);
    out.write('return');
    return out;
  }

  @override
  StringBuffer generateASTStatementReturnNull(
    ASTStatementReturnNull statement, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);
    out.write('return null');
    return out;
  }

  @override
  StringBuffer generateASTStatementReturnVariable(
    ASTStatementReturnVariable statement, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);
    out.write('return ');
    generateASTVariable(
      statement.variable,
      out: out,
      indent: indent,
      headIndented: false,
    );
    return out;
  }

  @override
  StringBuffer generateASTStatementReturnWithExpression(
    ASTStatementReturnWithExpression statement, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);
    out.write('return ');
    generateASTExpression(
      statement.expression,
      out: out,
      indent: indent,
      headIndented: false,
    );
    return out;
  }

  @override
  String resolveASTExpressionOperatorText(
    ASTExpressionOperator operator,
    ASTNumType aNumType,
    ASTNumType bNumType,
  ) {
    if (operator == ASTExpressionOperator.divideAsInt) {
      return getASTExpressionOperatorText(ASTExpressionOperator.divide);
    }
    return getASTExpressionOperatorText(operator);
  }

  @override
  StringBuffer generateASTExpressionListLiteral(
    ASTExpressionListLiteral expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    out.write('mutableListOf(');

    var valuesExpressions = expression.valuesExpressions;
    for (var i = 0; i < valuesExpressions.length; ++i) {
      var e = valuesExpressions[i];
      if (i > 0) out.write(', ');
      generateASTExpression(e, out: out, headIndented: false);
    }

    out.write(')');

    return out;
  }

  @override
  StringBuffer generateASTExpressionMapLiteral(
    ASTExpressionMapLiteral expression, {
    String indent = '',
    StringBuffer? out,
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    out.write('mutableMapOf(');

    var entriesExpressions = expression.entriesExpressions;
    for (var i = 0; i < entriesExpressions.length; ++i) {
      var e = entriesExpressions[i];
      if (i > 0) out.write(', ');
      generateASTExpression(e.key, out: out, headIndented: false);
      out.write(' to ');
      generateASTExpression(e.value, out: out, headIndented: false);
    }

    out.write(')');

    return out;
  }

  @override
  StringBuffer generateASTTypeArray(
    ASTTypeArray type, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();
    out.write(indent);
    out.write('List<');
    generateASTType(type.elementType, out: out);
    out.write('>');
    return out;
  }

  @override
  StringBuffer generateASTTypeArray2D(
    ASTTypeArray2D type, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();
    out.write(indent);
    out.write('List<List<');
    generateASTType(type.elementType, out: out);
    out.write('>>');
    return out;
  }

  @override
  StringBuffer generateASTTypeArray3D(
    ASTTypeArray3D type, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();
    out.write(indent);
    out.write('List<List<List<');
    generateASTType(type.elementType, out: out);
    out.write('>>>');
    return out;
  }

  @override
  StringBuffer generateASTValueString(
    ASTValueString value, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    var str = value.value;
    str = _escapeString(str);
    out.write('"$str"');

    return out;
  }

  String _escapeString(String str) {
    return str
        .replaceAll('\\', r'\\')
        .replaceAll('\t', r'\t')
        .replaceAll('"', r'\"')
        .replaceAll(r'$', r'\$')
        .replaceAll('\r', r'\r')
        .replaceAll('\n', r'\n')
        .replaceAll('\b', r'\b');
  }

  @override
  StringBuffer generateASTValueStringConcatenation(
    ASTValueStringConcatenation value, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    out.write('"');

    for (var v in value.values) {
      if (v is ASTValueStringVariable) {
        out.write(r'$');
        out.write(v.variable.name);
      } else if (v is ASTValueStringExpression) {
        var exp = generateASTExpression(v.expression).toString();
        out.write(r'${');
        out.write(exp);
        out.write('}');
      } else if (v is ASTValueStringConcatenation) {
        var s2 = generateASTValueStringConcatenation(v).toString();
        // Strip surrounding quotes of the nested concatenation:
        out.write(s2.substring(1, s2.length - 1));
      } else if (v is ASTValueString) {
        out.write(_escapeString(v.value));
      }
    }

    out.write('"');

    return out;
  }

  @override
  StringBuffer generateASTValueStringVariable(
    ASTValueStringVariable value, {
    StringBuffer? out,
    String indent = '',
    bool precededByString = false,
  }) {
    out ??= newOutput();

    out.write(r'"$');
    out.write(value.variable.name);
    out.write('"');

    return out;
  }

  @override
  StringBuffer generateASTValueStringExpression(
    ASTValueStringExpression value, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    var exp = generateASTExpression(value.expression).toString();
    out.write(r'"${');
    out.write(exp);
    out.write('}"');

    return out;
  }

  @override
  StringBuffer generateASTValueArray(
    ASTValueArray value, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    out.write(value.value);
    return out;
  }

  @override
  StringBuffer generateASTValueArray2D(
    ASTValueArray2D value, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    out.write(value.value);
    return out;
  }

  @override
  StringBuffer generateASTValueArray3D(
    ASTValueArray3D value, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    out.write(value.value);
    return out;
  }
}
