import '../../apollovm_code_generator.dart';
import '../../apollovm_code_storage.dart';
import '../../ast/apollovm_ast_expression.dart';
import '../../ast/apollovm_ast_toplevel.dart';
import '../../ast/apollovm_ast_type.dart';
import '../../ast/apollovm_ast_value.dart';
import '../../ast/apollovm_ast_variable.dart';

/// Dart implementation of an [ApolloCodeGenerator].
class ApolloCodeGeneratorDart extends ApolloCodeGenerator {
  ApolloCodeGeneratorDart(ApolloCodeStorage codeStorage)
      : super('dart', codeStorage);

  @override
  String normalizeTypeName(String typeName, [String? callingFunction]) {
    switch (typeName) {
      case 'Integer':
        return 'int';
      default:
        return typeName;
    }
  }

  @override
  String normalizeTypeFunction(String typeName, String functionName) {
    switch (typeName) {
      case 'int':
      case 'Integer':
        {
          switch (functionName) {
            case 'parse':
            case 'parseInt':
              return 'parse';
            default:
              return functionName;
          }
        }
      default:
        return functionName;
    }
  }

  @override
  StringBuffer generateASTClass(ASTClassNormal clazz,
      [String indent = '', StringBuffer? s]) {
    s ??= StringBuffer();

    var code = generateASTBlock(clazz, '', null, true, true);

    s.write('class ');
    s.write(clazz.name);
    s.write(' ');
    s.write(code);

    return s;
  }

  @override
  StringBuffer generateASTClassField(ASTClassField field,
      [String indent = '', StringBuffer? s]) {
    s ??= StringBuffer();

    var typeCode = generateASTType(field.type);

    s.write(indent);

    if (field.finalValue) {
      s.write('final ');
    }

    s.write(typeCode);
    s.write(' ');
    s.write(field.name);

    if (field is ASTClassFieldWithInitialValue) {
      var initialValueCode = generateASTExpression(field.initialValue);
      s.write(' = ');
      s.write(initialValueCode);
    }

    s.write(';\n');

    return s;
  }

  @override
  StringBuffer generateASTClassFunctionDeclaration(
      ASTClassFunctionDeclaration f,
      [String indent = '',
      StringBuffer? s]) {
    return _generateASTFunctionDeclarationImpl(f, indent, s);
  }

  @override
  StringBuffer generateASTFunctionDeclaration(ASTFunctionDeclaration f,
      [String indent = '', StringBuffer? s]) {
    return _generateASTFunctionDeclarationImpl(f, indent, s);
  }

  StringBuffer _generateASTFunctionDeclarationImpl(ASTFunctionDeclaration f,
      [String indent = '', StringBuffer? s]) {
    s ??= StringBuffer();

    var typeCode = generateASTType(f.returnType);

    var blockCode = generateASTBlock(f, indent, null, false);

    s.write(indent);

    if (f is ASTClassFunctionDeclaration) {
      if (f.modifiers.isStatic) {
        s.write('static ');
      }
    }

    s.write(typeCode);
    s.write(' ');
    s.write(f.name);
    s.write('(');

    if (f.parametersSize > 0) {
      generateASTParametersDeclaration(f.parameters, '', s);
    }

    s.write(') {\n');
    s.write(blockCode);
    s.write(indent);
    s.write('}\n\n');

    return s;
  }

  @override
  StringBuffer generateASTParametersDeclaration(
      ASTParametersDeclaration parameters,
      [String indent = '',
      StringBuffer? s]) {
    s ??= StringBuffer();

    var positionalParameters = parameters.positionalParameters;
    if (positionalParameters != null) {
      for (var i = 0; i < positionalParameters.length; ++i) {
        var p = positionalParameters[i];
        if (i > 0) s.write(', ');
        generateASTFunctionParameterDeclaration(p, '', s);
      }
    }

    var optionalParameters = parameters.optionalParameters;
    if (optionalParameters != null) {
      s.write('[');
      for (var i = 0; i < optionalParameters.length; ++i) {
        var p = optionalParameters[i];
        if (i > 0) s.write(', ');
        generateASTFunctionParameterDeclaration(p, '', s);
      }
      s.write(']');
    }

    var namedParameters = parameters.namedParameters;
    if (namedParameters != null) {
      s.write('{');
      for (var i = 0; i < namedParameters.length; ++i) {
        var p = namedParameters[i];
        if (i > 0) s.write(', ');
        generateASTFunctionParameterDeclaration(p, '', s);
      }
      s.write('}');
    }

    return s;
  }

  @override
  StringBuffer generateASTFunctionParameterDeclaration(
      ASTFunctionParameterDeclaration parameter,
      [String indent = '',
      StringBuffer? s]) {
    return generateASTParameterDeclaration(parameter, indent, s);
  }

  @override
  String resolveASTExpressionOperatorText(ASTExpressionOperator operator,
      ASTNumType aNumType, ASTNumType bNumType) {
    return getASTExpressionOperatorText(operator);
  }

  @override
  StringBuffer generateASTTypeArray(ASTTypeArray type,
          [String indent = '', StringBuffer? s]) =>
      generateASTTypeDefault(type, indent, s);

  @override
  StringBuffer generateASTTypeArray2D(ASTTypeArray2D type,
          [String indent = '', StringBuffer? s]) =>
      generateASTTypeDefault(type, indent, s);

  @override
  StringBuffer generateASTTypeArray3D(ASTTypeArray3D type,
          [String indent = '', StringBuffer? s]) =>
      generateASTTypeDefault(type, indent, s);

  @override
  StringBuffer generateASTValueString(ASTValueString value,
      [String indent = '', StringBuffer? s]) {
    s ??= StringBuffer();

    s.write(indent);

    var strRaw = value.value;

    var containsSingleQuote = strRaw.contains("'");
    var containsDoubleQuote = strRaw.contains('"');
    var containsBackslash = strRaw.contains('\\');

    var escapedBackslashCount = 0;

    var strEscaped = strRaw
        .replaceAllMapped('\\', (m) {
          escapedBackslashCount++;
          return r'\\';
        })
        .replaceAll('\t', r'\t')
        .replaceAll('\r', r'\r')
        .replaceAll('\n', r'\n')
        .replaceAll('\$', r'\$')
        .replaceAll('\b', r'\b');

    var noEscapedChar =
        (strEscaped.length - escapedBackslashCount) == strRaw.length;

    if (noEscapedChar && containsBackslash) {
      if (containsSingleQuote) {
        if (!containsDoubleQuote) {
          s.write('r"$strRaw"');
          return s;
        }
      } else if (containsDoubleQuote) {
        if (!containsSingleQuote) {
          s.write("r'$strRaw'");
          return s;
        }
      } else {
        s.write("r'$strRaw'");
        return s;
      }
    }

    if (containsSingleQuote) {
      if (containsDoubleQuote) strEscaped = strEscaped.replaceAll('"', r'\"');
      s.write('"$strEscaped"');
    } else {
      s.write("'$strEscaped'");
    }

    return s;
  }

  @override
  StringBuffer generateASTValueStringConcatenation(
      ASTValueStringConcatenation value,
      [String indent = '',
      StringBuffer? s]) {
    var list = <dynamic>[];

    var prevString = '';
    for (var v in value.values) {
      if (v is ASTValueStringVariable) {
        var prevDoubleQuote = prevString.endsWith('"');
        var s2 =
            generateASTValueStringVariable(v, '', null, false, prevDoubleQuote);
        list.add(prevString = s2.toString());
      } else if (v is ASTValueStringExpression) {
        var s2 = generateASTValueStringExpresion(v, '');
        list.add(prevString = s2.toString());
      } else if (v is ASTValueStringConcatenation) {
        var s2 = generateASTValueStringConcatenation(v, '');
        list.add(prevString = s2.toString());
      } else if (v is ASTValueString) {
        var s2 = generateASTValueString(v, '');
        list.add(prevString = s2.toString());
      }
    }

    var generatedStrings = list.whereType<String>().toList();

    s ??= StringBuffer();

    if (generatedStrings.every((s) => s.startsWith("'''")) ||
        generatedStrings.every((s) => s.startsWith('"""'))) {
      // will generate concatenation at end...
    } else if (generatedStrings.every((s) => s.startsWith("'"))) {
      s.write("'");

      for (var e in list) {
        if (e is String) {
          s.write(e.substring(1, e.length - 1));
        } else {
          var s2 = e.toString();
          s.write(s2.substring(1, s2.length - 1));
        }
      }

      s.write("'");

      return s;
    } else if (generatedStrings.every((s) => s.startsWith('"'))) {
      s.write('"');

      for (var e in list) {
        if (e is String) {
          s.write(e.substring(1, s.length - 1));
        } else {
          var s2 = e.toString();
          s.write(s2.substring(1, s2.length - 1));
        }
      }

      s.write('"');

      return s;
    }

    for (var i = 0; i < list.length; ++i) {
      var e = list[i];

      if (e is String) {
        var multiline = e.startsWith("'''") ||
            e.startsWith('"""') ||
            e.startsWith("r'''") ||
            e.startsWith('r"""');
        if (multiline && i > 0) {
          s.write('\n');
        }
        s.write(e);
      } else {
        var s2 = e.toString();
        s.write(s2);
      }
    }

    return s;
  }

  @override
  StringBuffer generateASTValueStringVariable(ASTValueStringVariable value,
      [String indent = '',
      StringBuffer? s,
      bool precededByString = false,
      bool prevDoubleQuote = false]) {
    s ??= StringBuffer();

    if (prevDoubleQuote) {
      s.write(r'"$');
      s.write(value.variable.name);
      s.write('"');
    } else {
      s.write(r"'$");
      s.write(value.variable.name);
      s.write("'");
    }

    return s;
  }

  @override
  StringBuffer generateASTValueStringExpresion(ASTValueStringExpression value,
      [String indent = '', StringBuffer? s]) {
    s ??= StringBuffer();

    var exp = generateASTExpression(value.expression, '').toString();

    if (exp.contains("'")) {
      s.write('"');
      s.write(r'${');
      s.write(exp);
      s.write(r'}');
      s.write('"');
    } else {
      s.write("'");
      s.write(r'${');
      s.write(exp);
      s.write(r'}');
      s.write("'");
    }

    return s;
  }

  @override
  StringBuffer generateASTValueArray(ASTValueArray value,
      [String indent = '', StringBuffer? s]) {
    s ??= StringBuffer();
    s.write(value.value);
    return s;
  }

  @override
  StringBuffer generateASTValueArray2D(ASTValueArray2D value,
      [String indent = '', StringBuffer? s]) {
    s ??= StringBuffer();
    s.write(value.value);
    return s;
  }

  @override
  StringBuffer generateASTValueArray3D(ASTValueArray3D value,
      [String indent = '', StringBuffer? s]) {
    s ??= StringBuffer();
    s.write(value.value);
    return s;
  }

  @override
  StringBuffer generateASTExpressionOperation(ASTExpressionOperation expression,
      [String indent = '', StringBuffer? s]) {
    s ??= StringBuffer();
    s.write(indent);

    // Merge into string template:
    if (expression.operator == ASTExpressionOperator.add) {
      if (expression.expression1.isVariableAccess) {
        var s1 = generateASTExpression(expression.expression1, '').toString();
        var s2 = generateASTExpression(expression.expression2, '').toString();

        if (_isVariable(s1) &&
            (_isSingleQuoteString(s2) || _isDoubleQuoteString(s2))) {
          var sMerge = '${s2.substring(0, 1)}\$$s1${s2.substring(1)}';
          s.write(sMerge);
          return s;
        }
      } else if (expression.expression1.isLiteralString) {
        var s1 = generateASTExpression(expression.expression1, '').toString();
        var s2 = generateASTExpression(expression.expression2, '').toString();

        if ((_isSingleQuoteString(s1) && _isSingleQuoteString(s2)) ||
            (_isDoubleQuoteString(s1) && _isDoubleQuoteString(s2))) {
          var sMerge = s1.substring(0, s1.length - 1) + s2.substring(1);
          s.write(sMerge);
          return s;
        } else if ((_isSingleQuoteString(s1) || _isDoubleQuoteString(s1)) &&
            _isVariable(s2)) {
          var sMerge =
              '${s1.substring(0, s1.length - 1)}\$$s2${s1.substring(s1.length - 1)}';
          s.write(sMerge);
          return s;
        }
      }
    }

    var op = resolveASTExpressionOperatorText(
      expression.operator,
      expression.expression1.literalNumType,
      expression.expression2.literalNumType,
    );

    generateASTExpression(expression.expression1, '', s);
    s.write(' ');
    s.write(op);
    s.write(' ');
    generateASTExpression(expression.expression2, '', s);

    return s;
  }

  static final RegExp _regexpWORD = RegExp(r'^[a-zA-Z]\w*$');

  static bool _isVariable(String s) {
    return _regexpWORD.hasMatch(s);
  }

  static bool _isSingleQuoteString(String s) {
    var quoted = s.startsWith("'") &&
        !s.startsWith("'''") &&
        s.endsWith("'") &&
        !s.endsWith("'''");

    if (!quoted) return false;
    var idx = s.indexOf("'", 1);
    if (idx < s.length - 1) return false;

    return true;
  }

  static bool _isDoubleQuoteString(String s) {
    var quoted = s.startsWith('"') &&
        !s.startsWith('"""') &&
        s.endsWith('"') &&
        !s.endsWith('"""');

    if (!quoted) return false;
    var idx = s.indexOf('"', 1);
    if (idx < s.length - 1) return false;

    return true;
  }
}
