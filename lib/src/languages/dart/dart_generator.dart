import 'package:apollovm/apollovm.dart';
import 'package:apollovm/src/apollovm_code_generator.dart';
import 'package:apollovm/src/apollovm_code_storage.dart';

class ApolloCodeGeneratorDart extends ApolloCodeGenerator {
  ApolloCodeGeneratorDart(ApolloCodeStorage codeStorage) : super(codeStorage);

  @override
  StringBuffer generateASTClass(ASTClass clazz,
      [String indent = '', StringBuffer? s]) {
    s ??= StringBuffer();

    var code = generateASTBlock(clazz);

    s.write('class ');
    s.write(clazz.name);
    s.write(' ');
    s.write(code);

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
    s.write('}\n');

    return blockCode;
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
  String resolveASTExpressionOperatorText(ASTExpressionOperator operator) =>
      getASTExpressionOperatorText(operator);

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

    for (var v in value.values) {
      if (v is ASTValueStringVariable) {
        var s2 = generateASTValueStringVariable(v, '', null, list.isNotEmpty);
        list.add(s2);
      } else if (v is ASTValueStringExpresion) {
        var s2 = generateASTValueStringExpresion(v, '');
        list.add(s2.toString());
      } else if (v is ASTValueStringConcatenation) {
        var s2 = generateASTValueStringConcatenation(v, '');
        list.add(s2.toString());
      } else if (v is ASTValueString) {
        var s2 = generateASTValueString(v, '');
        list.add(s2.toString());
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
      [String indent = '', StringBuffer? s, bool precededByString = false]) {
    s ??= StringBuffer();
    s.write("'");
    s.write(r'$');
    s.write(value.variable.name);
    s.write("'");
    return s;
  }

  @override
  StringBuffer generateASTValueStringExpresion(ASTValueStringExpresion value,
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
}
