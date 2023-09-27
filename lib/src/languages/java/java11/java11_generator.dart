import '../../../apollovm_code_generator.dart';
import '../../../apollovm_code_storage.dart';
import '../../../apollovm_parser.dart';
import '../../../ast/apollovm_ast_expression.dart';
import '../../../ast/apollovm_ast_toplevel.dart';
import '../../../ast/apollovm_ast_type.dart';
import '../../../ast/apollovm_ast_value.dart';
import '../../../ast/apollovm_ast_variable.dart';

/// Java11 implementation of an [ApolloCodeGenerator].
class ApolloCodeGeneratorJava11 extends ApolloCodeGenerator {
  ApolloCodeGeneratorJava11(ApolloSourceCodeStorage codeStorage)
      : super('java11', codeStorage);

  @override
  String normalizeTypeName(String typeName, [String? callingFunction]) {
    switch (typeName) {
      case 'int':
        return callingFunction != null ? 'Integer' : typeName;
      case 'dynamic':
        return 'Object';
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
              return 'parseInt';
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
    out ??= newOutput();

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
    out ??= newOutput();

    var typeCode = generateASTType(field.type);

    out.write(indent);

    if (field.finalValue) {
      out.write('final ');
    }

    out.write(typeCode);
    out.write(' ');
    out.write(field.name);

    if (field is ASTClassFieldWithInitialValue) {
      var initialValueCode = generateASTExpression(field.initialValue,
          indent: "$indent  ", headIndented: false);
      out.write(' = ');
      out.write(initialValueCode);
    }

    out.write(';\n');

    return out;
  }

  @override
  StringBuffer generateASTFunctionDeclaration(ASTFunctionDeclaration f,
      {StringBuffer? out, String indent = ''}) {
    throw UnsupportedSyntaxError('All functions in Java are from a class: $f');
  }

  @override
  StringBuffer generateASTClassFunctionDeclaration(
      ASTClassFunctionDeclaration f,
      {StringBuffer? out,
      String indent = ''}) {
    out ??= newOutput();

    var typeCode = generateASTType(f.returnType);

    var blockCode = generateASTBlock(f, indent: indent, withBrackets: false);

    out.write(indent);

    if (f.modifiers.isStatic) {
      out.write('static ');
    }

    if (f.modifiers.isFinal) {
      out.write('final ');
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
    out ??= newOutput();

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
      for (var i = 0; i < optionalParameters.length; ++i) {
        var p = optionalParameters[i];
        if (i > 0) out.write(', ');
        generateASTFunctionParameterDeclaration(p, out: out);
      }
    }

    var namedParameters = parameters.namedParameters;
    if (namedParameters != null) {
      for (var i = 0; i < namedParameters.length; ++i) {
        var p = namedParameters[i];
        if (i > 0) out.write(', ');
        generateASTFunctionParameterDeclaration(p, out: out);
      }
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
    if (operator == ASTExpressionOperator.divideAsInt) {
      return getASTExpressionOperatorText(ASTExpressionOperator.divide);
    }
    return getASTExpressionOperatorText(operator);
  }

  @override
  StringBuffer generateASTExpressionListLiteral(
      ASTExpressionListLiteral expression,
      {StringBuffer? out,
      String indent = '',
      bool headIndented = true}) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    final type = expression.type;

    out.write('new ArrayList');

    if (type != null) {
      out.write('<');
      generateASTType(type, out: out);
      out.write('>');
    } else {
      out.write('<>');
    }

    out.write('(){{\n');

    var valuesExpressions = expression.valuesExpressions;
    for (var i = 0; i < valuesExpressions.length; ++i) {
      var e = valuesExpressions[i];

      out.write('$indent  add(');
      generateASTExpression(e, out: out);
      out.write(');\n');
    }

    out.write('$indent}}');

    return out;
  }

  @override
  StringBuffer generateASTExpressionMapLiteral(
      ASTExpressionMapLiteral expression,
      {String indent = '',
      StringBuffer? out,
      bool headIndented = true}) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    final keyType = expression.keyType;
    final valueType = expression.valueType;

    out.write('new HashMap');

    if (keyType != null && valueType != null) {
      out.write('<');
      generateASTType(keyType, out: out);
      out.write(',');
      generateASTType(valueType, out: out);
      out.write('>');
    } else {
      out.write('<>');
    }

    out.write('(){{\n');

    var entriesExpressions = expression.entriesExpressions;
    for (var i = 0; i < entriesExpressions.length; ++i) {
      var e = entriesExpressions[i];

      out.write("$indent  put(");
      generateASTExpression(e.key, out: out);
      out.write(", ");
      generateASTExpression(e.value, out: out);
      out.write(");\n");
    }

    out.write('$indent}}');

    return out;
  }

  @override
  StringBuffer generateASTTypeArray(ASTTypeArray type,
      {StringBuffer? out, String indent = ''}) {
    out ??= newOutput();
    out.write(indent);
    generateASTType(type.elementType, out: out);
    out.write('[]');
    return out;
  }

  @override
  StringBuffer generateASTTypeArray2D(ASTTypeArray2D type,
      {StringBuffer? out, String indent = ''}) {
    out ??= newOutput();
    out.write(indent);
    generateASTType(type.elementType, out: out);
    out.write('[][]');
    return out;
  }

  @override
  StringBuffer generateASTTypeArray3D(ASTTypeArray3D type,
      {StringBuffer? out, String indent = ''}) {
    out ??= newOutput();
    out.write(indent);
    generateASTType(type.elementType, out: out);
    out.write('[][][]');
    return out;
  }

  @override
  StringBuffer generateASTValueString(ASTValueString value,
      {StringBuffer? out, String indent = '', bool headIndented = true}) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    var str = value.value;
    str = _escapeString(str);
    out.write('"$str"');

    return out;
  }

  String _escapeString(String str) {
    return str
        .replaceAll('\t', r'\t')
        .replaceAll('"', r'\"')
        .replaceAll('\r', r'\r')
        .replaceAll('\n', r'\n')
        .replaceAll('\b', r'\b');
  }

  @override
  StringBuffer generateASTValueStringConcatenation(
      ASTValueStringConcatenation value,
      {StringBuffer? out,
      String indent = ''}) {
    var list = <dynamic>[];

    var prevIsString = false;
    for (var v in value.values) {
      if (v is ASTValueStringVariable) {
        var s2 =
            generateASTValueStringVariable(v, precededByString: prevIsString);
        list.add(s2);
        prevIsString = !prevIsString;
      } else if (v is ASTValueStringExpression) {
        var s2 = generateASTValueStringExpression(v);
        list.add(s2);
        prevIsString = true;
      } else if (v is ASTValueStringConcatenation) {
        var s2 = generateASTValueStringConcatenation(v);
        var string = s2.toString();
        list.add(string);
        prevIsString = string.endsWith('"');
      } else if (v is ASTValueString) {
        var s2 = generateASTValueString(v);
        list.add(s2.toString());
        prevIsString = true;
      }
    }

    out ??= newOutput();

    for (var i = 1; i < list.length;) {
      var prev = list[i - 1];
      var e = list[i];

      if (prev is String && e is String) {
        var merge = prev.substring(0, prev.length - 1) + e.substring(1);
        list[i - 1] = merge;
        list.removeAt(i);
      } else {
        ++i;
      }
    }

    for (var i = 0; i < list.length; ++i) {
      var e = list[i];
      if (i > 0) out.write(' + ');
      out.write(e);
    }

    return out;
  }

  @override
  StringBuffer generateASTValueStringVariable(ASTValueStringVariable value,
      {StringBuffer? out, String indent = '', bool precededByString = false}) {
    out ??= newOutput();

    if (precededByString) {
      out.write(value.variable.name);
    } else {
      out.write('String.valueOf( ${value.variable.name} )');
    }

    return out;
  }

  @override
  StringBuffer generateASTValueStringExpression(ASTValueStringExpression value,
      {StringBuffer? out, String indent = ''}) {
    out ??= newOutput();

    var exp = generateASTExpression(value.expression).toString();
    out.write('String.valueOf( $exp )');

    return out;
  }

  @override
  StringBuffer generateASTValueArray(ASTValueArray value,
      {StringBuffer? out, String indent = '', bool headIndented = true}) {
    out ??= newOutput();
    out.write(value.value);
    return out;
  }

  @override
  StringBuffer generateASTValueArray2D(ASTValueArray2D value,
      {StringBuffer? out, String indent = '', bool headIndented = true}) {
    out ??= newOutput();
    out.write(value.value);
    return out;
  }

  @override
  StringBuffer generateASTValueArray3D(ASTValueArray3D value,
      {StringBuffer? out, String indent = '', bool headIndented = true}) {
    out ??= newOutput();
    out.write(value.value);
    return out;
  }
}
