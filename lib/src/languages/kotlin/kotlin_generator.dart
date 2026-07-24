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

  /// Kotlin uses `name = value` for named arguments at call sites.
  @override
  String get namedArgumentSeparator => ' = ';

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
  bool get supportsNullableTypeSuffix => true;

  @override
  bool get supportsNullAwareOperators => true;

  @override
  String get nullAssertionSuffix => '!!';

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

  /// Kotlin has no extension *block*: each member is emitted as a top-level
  /// declaration qualified by the receiver type — `fun Int.doubled(): Int` and
  /// `val Int.twice: Int get()`. The extension's name is therefore dropped.
  @override
  StringBuffer generateASTExtension(
    ASTExtension extension, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    var receiver = generateASTType(extension.targetType).toString();

    for (var set in extension.functions) {
      for (var f in set.functions) {
        _generateASTFunctionDeclarationImpl(f, out, indent, receiver);
      }
    }

    for (var g in extension.getter) {
      if (g is ASTClassGetterDeclaration) {
        generateASTClassGetterDeclaration(
          g,
          out: out,
          indent: indent,
          receiver: receiver,
        );
      }
    }

    return out;
  }

  @override
  StringBuffer generateASTClassGetterDeclaration(
    ASTClassGetterDeclaration getter, {
    StringBuffer? out,
    String indent = '',
    String? receiver,
  }) {
    out ??= newOutput();

    var blockCode = generateASTBlock(
      getter,
      indent: indent,
      withBrackets: false,
    );

    out.write(indent);
    out.write('val ');
    if (receiver != null) {
      out.write(receiver);
      out.write('.');
    }
    out.write(getter.name);
    out.write(': ');
    generateASTType(getter.returnType, out: out);
    out.write(' get() {\n');
    out.write(blockCode);
    out.write(indent);
    out.write('}\n\n');

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

  /// Generates a Kotlin `enum class` declaration (simple or rich).
  ///
  /// Kotlin places the constructor parameters in the class header
  /// (`enum class Planet(val mass: Double, ...)`); the enum constants then
  /// pass their arguments, and any methods follow after a `;`.
  StringBuffer generateASTClassEnum(
    ASTClassEnum clazz, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    var fields = clazz.fields;
    var constructors = clazz.constructors;
    var functions = clazz.functions;

    // Primary-constructor parameters (go in the enum class header).
    var ctorParams = <ASTConstructorParameterDeclaration>[];
    if (constructors.isNotEmpty) {
      var c = constructors.first.functions.first;
      ctorParams = c.parameters.positionalParameters ?? [];
    }
    var ctorParamNames = ctorParams.map((p) => p.name).toSet();

    out.write(indent);
    out.write('enum class ');
    out.write(clazz.name);

    if (ctorParams.isNotEmpty) {
      out.write('(');
      for (var i = 0; i < ctorParams.length; ++i) {
        var p = ctorParams[i];
        if (i > 0) out.write(', ');
        out.write('val ');
        out.write(p.name);
        out.write(': ');
        generateASTType(p.type, out: out);
      }
      out.write(')');
    }

    out.write(' {\n');

    var indent2 = '$indent  ';

    // Fields already declared as constructor params live in the header; any
    // remaining fields stay as body properties.
    var bodyFields = fields
        .where((f) => !ctorParamNames.contains(f.name))
        .toList();
    var hasMembers = bodyFields.isNotEmpty || functions.isNotEmpty;

    var entries = clazz.entries;
    for (var i = 0; i < entries.length; ++i) {
      out.write('$indent  ');
      _generateEnumEntry(entries[i], out);
      if (i < entries.length - 1) {
        out.write(',');
      } else if (hasMembers) {
        out.write(';');
      }
      out.write('\n');
    }

    if (hasMembers) {
      for (var field in bodyFields) {
        generateASTClassField(field, out: out, indent: indent2);
      }

      for (var set in functions) {
        for (var f in set.functions) {
          if (f is ASTClassFunctionDeclaration) {
            generateASTClassFunctionDeclaration(f, out: out, indent: indent2);
          }
        }
      }
    }

    out.write('$indent}\n');

    return out;
  }

  /// Generates a single enum entry: a bare name or constructor arguments
  /// (`EARTH(5.97, 6371)`).
  void _generateEnumEntry(ASTEnumEntry entry, StringBuffer out) {
    out.write(entry.name);

    var arguments = entry.arguments;
    if (arguments != null) {
      out.write('(');
      for (var i = 0; i < arguments.length; ++i) {
        if (i > 0) out.write(', ');
        generateASTExpression(arguments[i], out: out, headIndented: false);
      }
      out.write(')');
    }
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

  /// [receiver] is set only for extension functions, where the name is
  /// qualified by the extended type: `fun Int.doubled()`.
  StringBuffer _generateASTFunctionDeclarationImpl(
    ASTFunctionDeclaration f,
    StringBuffer? out,
    String indent, [
    String? receiver,
  ]) {
    out ??= newOutput();

    var blockCode = generateASTBlock(f, indent: indent, withBrackets: false);

    out.write(indent);

    // Visibility modifier (Kotlin defaults to `public`, so only emit when set).
    if (f.modifiers.isPrivate) {
      out.write('private ');
    } else if (f.modifiers.isPublic) {
      out.write('public ');
    }

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
    if (receiver != null) {
      out.write(receiver);
      out.write('.');
    }
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

    // Kotlin declares all parameters positionally (any can be passed by name at
    // the call site), so positional + optional + named are emitted as a single
    // flat, comma-separated list.
    var wrote = 0;
    for (var p in parameters.allParameters) {
      if (wrote > 0) out.write(', ');
      generateASTParameterDeclaration(p, out: out);
      ++wrote;
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

    // Appends ` = <default>` when the parameter has a default value
    // (Kotlin syntax: `name: Type = expr`).
    appendParameterDefaultValue(parameter, out, indent);

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
    // Kotlin uses named infix functions for bitwise operators instead of the
    // C-family symbols (`&`, `|`, `^`, `<<`, `>>`). The operation formatter
    // surrounds the operator with spaces, producing e.g. `a and b`.
    switch (operator) {
      case ASTExpressionOperator.bitwiseAnd:
        return 'and';
      case ASTExpressionOperator.bitwiseOr:
        return 'or';
      case ASTExpressionOperator.bitwiseXor:
        return 'xor';
      case ASTExpressionOperator.shiftLeft:
        return 'shl';
      case ASTExpressionOperator.shiftRight:
        return 'shr';
      // Kotlin's null-coalescing is the Elvis operator `?:`, not `??`.
      case ASTExpressionOperator.nullCoalesce:
        return '?:';
      default:
        return getASTExpressionOperatorText(operator);
    }
  }

  /// Kotlin writes bitwise-not as `x.inv()` (a method call), not `~x`.
  @override
  StringBuffer generateASTExpressionBitwiseNot(
    ASTExpressionBitwiseNot expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    out.write('(');
    generateASTExpression(
      expression.expression,
      out: out,
      indent: indent,
      headIndented: false,
    );
    out.write(').inv()');

    return out;
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
