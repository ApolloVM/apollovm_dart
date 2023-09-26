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
      {StringBuffer? out, String indent = ''}) {
    out ??= StringBuffer();

    var code =
        generateASTBlock(clazz, withBrackets: true, withBlankHeadLine: true);

    out.write('class ');
    out.write(clazz.name);
    out.write(' ');
    out.write(code);

    return out;
  }

  @override
  StringBuffer generateASTClassField(ASTClassField field,
      {StringBuffer? out, String indent = ''}) {
    out ??= StringBuffer();

    var typeCode = generateASTType(field.type);

    out.write(indent);

    if (field.finalValue) {
      out.write('final ');
    }

    out.write(typeCode);
    out.write(' ');
    out.write(field.name);

    if (field is ASTClassFieldWithInitialValue) {
      var initialValueCode = generateASTExpression(field.initialValue);
      out.write(' = ');
      out.write(initialValueCode);
    }

    out.write(';\n');

    return out;
  }

  @override
  StringBuffer generateASTClassFunctionDeclaration(
      ASTClassFunctionDeclaration f,
      {StringBuffer? out,
      String indent = ''}) {
    return _generateASTFunctionDeclarationImpl(f, out, indent);
  }

  @override
  StringBuffer generateASTFunctionDeclaration(ASTFunctionDeclaration f,
      {StringBuffer? out, String indent = ''}) {
    return _generateASTFunctionDeclarationImpl(f, out, indent);
  }

  StringBuffer _generateASTFunctionDeclarationImpl(
      ASTFunctionDeclaration f, StringBuffer? out, String indent) {
    out ??= StringBuffer();

    var typeCode = generateASTType(f.returnType);

    var blockCode = generateASTBlock(f, indent: indent, withBrackets: false);

    out.write(indent);

    if (f is ASTClassFunctionDeclaration) {
      if (f.modifiers.isStatic) {
        out.write('static ');
      }
    }

    out.write(typeCode);
    out.write(' ');
    out.write(f.name);
    out.write('(');

    if (f.parametersSize > 0) {
      generateASTParametersDeclaration(f.parameters, out: out);
    }

    out.write(') {\n');
    out.write(blockCode);
    out.write(indent);
    out.write('}\n\n');

    return out;
  }

  @override
  StringBuffer generateASTParametersDeclaration(
      ASTParametersDeclaration parameters,
      {StringBuffer? out,
      String indent = ''}) {
    out ??= StringBuffer();

    var positionalParameters = parameters.positionalParameters;
    if (positionalParameters != null) {
      for (var i = 0; i < positionalParameters.length; ++i) {
        var p = positionalParameters[i];
        if (i > 0) out.write(', ');
        generateASTFunctionParameterDeclaration(p, out: out);
      }
    }

    var optionalParameters = parameters.optionalParameters;
    if (optionalParameters != null) {
      out.write('[');
      for (var i = 0; i < optionalParameters.length; ++i) {
        var p = optionalParameters[i];
        if (i > 0) out.write(', ');
        generateASTFunctionParameterDeclaration(p, out: out);
      }
      out.write(']');
    }

    var namedParameters = parameters.namedParameters;
    if (namedParameters != null) {
      out.write('{');
      for (var i = 0; i < namedParameters.length; ++i) {
        var p = namedParameters[i];
        if (i > 0) out.write(', ');
        generateASTFunctionParameterDeclaration(p, out: out);
      }
      out.write('}');
    }

    return out;
  }

  @override
  StringBuffer generateASTFunctionParameterDeclaration(
      ASTFunctionParameterDeclaration parameter,
      {StringBuffer? out,
      String indent = ''}) {
    return generateASTParameterDeclaration(parameter, out: out, indent: indent);
  }

  @override
  String resolveASTExpressionOperatorText(ASTExpressionOperator operator,
      ASTNumType aNumType, ASTNumType bNumType) {
    return getASTExpressionOperatorText(operator);
  }

  @override
  StringBuffer generateASTTypeArray(ASTTypeArray type,
          {StringBuffer? out, String indent = ''}) =>
      generateASTTypeDefault(type, out: out, indent: indent);

  @override
  StringBuffer generateASTTypeArray2D(ASTTypeArray2D type,
          {StringBuffer? out, String indent = ''}) =>
      generateASTTypeDefault(type, out: out, indent: indent);

  @override
  StringBuffer generateASTTypeArray3D(ASTTypeArray3D type,
          {StringBuffer? out, String indent = ''}) =>
      generateASTTypeDefault(type, out: out, indent: indent);

  @override
  StringBuffer generateASTValueString(ASTValueString value,
      {StringBuffer? out, String indent = '', bool headIndented = true}) {
    out ??= StringBuffer();

    if (headIndented) out.write(indent);

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
          out.write('r"$strRaw"');
          return out;
        }
      } else if (containsDoubleQuote) {
        if (!containsSingleQuote) {
          out.write("r'$strRaw'");
          return out;
        }
      } else {
        out.write("r'$strRaw'");
        return out;
      }
    }

    if (containsSingleQuote) {
      if (containsDoubleQuote) strEscaped = strEscaped.replaceAll('"', r'\"');
      out.write('"$strEscaped"');
    } else {
      out.write("'$strEscaped'");
    }

    return out;
  }

  @override
  StringBuffer generateASTValueStringConcatenation(
      ASTValueStringConcatenation value,
      {StringBuffer? out,
      String indent = ''}) {
    var list = <dynamic>[];

    var prevString = '';
    for (var v in value.values) {
      if (v is ASTValueStringVariable) {
        var prevDoubleQuote = prevString.endsWith('"');
        var s2 = generateASTValueStringVariable(v,
            precededByString: false, prevDoubleQuote: prevDoubleQuote);
        list.add(prevString = s2.toString());
      } else if (v is ASTValueStringExpression) {
        var prevDoubleQuote = prevString.endsWith('"');
        var s2 = generateASTValueStringExpression(v,
            prevDoubleQuote: prevDoubleQuote);
        list.add(prevString = s2.toString());
      } else if (v is ASTValueStringConcatenation) {
        var s2 = generateASTValueStringConcatenation(v);
        list.add(prevString = s2.toString());
      } else if (v is ASTValueString) {
        var s2 = generateASTValueString(v);
        list.add(prevString = s2.toString());
      }
    }

    var generatedStrings = list.whereType<String>().toList();

    out ??= StringBuffer();

    if (generatedStrings.every((s) => s.startsWith("'''")) ||
        generatedStrings.every((s) => s.startsWith('"""'))) {
      // will generate concatenation at end...
    } else if (generatedStrings.every((s) => s.startsWith("'"))) {
      out.write("'");

      for (var e in list) {
        if (e is String) {
          out.write(e.substring(1, e.length - 1));
        } else {
          var s2 = e.toString();
          out.write(s2.substring(1, s2.length - 1));
        }
      }

      out.write("'");

      return out;
    } else if (generatedStrings.every((s) => s.startsWith('"'))) {
      out.write('"');

      for (var e in list) {
        if (e is String) {
          out.write(e.substring(1, out.length - 1));
        } else {
          var s2 = e.toString();
          out.write(s2.substring(1, s2.length - 1));
        }
      }

      out.write('"');

      return out;
    }

    for (var i = 0; i < list.length; ++i) {
      var e = list[i];

      if (e is String) {
        var multiline = e.startsWith("'''") ||
            e.startsWith('"""') ||
            e.startsWith("r'''") ||
            e.startsWith('r"""');
        if (multiline && i > 0) {
          out.write('\n');
        }
        out.write(e);
      } else {
        var s2 = e.toString();
        out.write(s2);
      }
    }

    return out;
  }

  @override
  StringBuffer generateASTValueStringVariable(ASTValueStringVariable value,
      {StringBuffer? out,
      String indent = '',
      bool precededByString = false,
      bool prevDoubleQuote = false}) {
    out ??= StringBuffer();

    if (prevDoubleQuote) {
      out.write(r'"$');
      out.write(value.variable.name);
      out.write('"');
    } else {
      out.write(r"'$");
      out.write(value.variable.name);
      out.write("'");
    }

    return out;
  }

  @override
  StringBuffer generateASTValueStringExpression(ASTValueStringExpression value,
      {StringBuffer? out, String indent = '', bool prevDoubleQuote = false}) {
    out ??= StringBuffer();

    var exp = generateASTExpression(value.expression).toString();

    if (exp.contains("'") && prevDoubleQuote) {
      out.write('"');
      out.write(r'${');
      out.write(exp);
      out.write(r'}');
      out.write('"');
    } else {
      out.write("'");
      out.write(r'${');
      out.write(exp);
      out.write(r'}');
      out.write("'");
    }

    return out;
  }

  @override
  StringBuffer generateASTValueArray(ASTValueArray value,
      {StringBuffer? out, String indent = '', bool headIndented = true}) {
    out ??= StringBuffer();
    out.write(value.value);
    return out;
  }

  @override
  StringBuffer generateASTValueArray2D(ASTValueArray2D value,
      {StringBuffer? out, String indent = '', bool headIndented = true}) {
    out ??= StringBuffer();
    out.write(value.value);
    return out;
  }

  @override
  StringBuffer generateASTValueArray3D(ASTValueArray3D value,
      {StringBuffer? out, String indent = '', bool headIndented = true}) {
    out ??= StringBuffer();
    out.write(value.value);
    return out;
  }

  @override
  StringBuffer generateASTExpressionOperation(ASTExpressionOperation expression,
      {StringBuffer? out, String indent = '', bool headIndented = true}) {
    out ??= StringBuffer();

    if (headIndented) out.write(indent);

    // Merge into string template:
    if (expression.operator == ASTExpressionOperator.add) {
      if (expression.expression1.isVariableAccess) {
        var s1 = generateASTExpression(expression.expression1).toString();
        var s2 = generateASTExpression(expression.expression2).toString();

        if (_isVariable(s1) &&
            (_isSingleQuoteString(s2) || _isDoubleQuoteString(s2))) {
          var sMerge = '${s2.substring(0, 1)}\$$s1${s2.substring(1)}';
          out.write(sMerge);
          return out;
        }
      } else if (expression.expression1.isLiteralString) {
        var s1 = generateASTExpression(expression.expression1).toString();
        var s2 = generateASTExpression(expression.expression2).toString();

        if ((_isSingleQuoteString(s1) && _isSingleQuoteString(s2)) ||
            (_isDoubleQuoteString(s1) && _isDoubleQuoteString(s2))) {
          var sMerge = s1.substring(0, s1.length - 1) + s2.substring(1);
          out.write(sMerge);
          return out;
        } else if ((_isSingleQuoteString(s1) || _isDoubleQuoteString(s1)) &&
            _isVariable(s2)) {
          var sMerge =
              '${s1.substring(0, s1.length - 1)}\$$s2${s1.substring(s1.length - 1)}';
          out.write(sMerge);
          return out;
        }
      }
    }

    var op = resolveASTExpressionOperatorText(
      expression.operator,
      expression.expression1.literalNumType,
      expression.expression2.literalNumType,
    );

    generateASTExpression(expression.expression1, out: out);
    out.write(' ');
    out.write(op);
    out.write(' ');
    generateASTExpression(expression.expression2, out: out);

    return out;
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
