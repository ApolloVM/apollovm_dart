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
  ApolloCodeGeneratorJava11(ApolloCodeStorage codeStorage)
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
      {StringBuffer? s, String indent = ''}) {
    s ??= StringBuffer();

    var code =
        generateASTBlock(clazz, withBrackets: true, withBlankHeadLine: true);

    s.write('class ');
    s.write(clazz.name);
    s.write(' ');
    s.write(code);

    return s;
  }

  @override
  StringBuffer generateASTClassField(ASTClassField field,
      {StringBuffer? s, String indent = ''}) {
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
      var initialValueCode = generateASTExpression(field.initialValue,
          indent: "$indent  ", headIndented: false);
      s.write(' = ');
      s.write(initialValueCode);
    }

    s.write(';\n');

    return s;
  }

  @override
  StringBuffer generateASTFunctionDeclaration(ASTFunctionDeclaration f,
      {StringBuffer? s, String indent = ''}) {
    throw UnsupportedSyntaxError('All functions in Java are from a class: $f');
  }

  @override
  StringBuffer generateASTClassFunctionDeclaration(
      ASTClassFunctionDeclaration f,
      {StringBuffer? s,
      String indent = ''}) {
    s ??= StringBuffer();

    var typeCode = generateASTType(f.returnType);

    var blockCode = generateASTBlock(f, indent: indent, withBrackets: false);

    s.write(indent);

    if (f.modifiers.isStatic) {
      s.write('static ');
    }

    if (f.modifiers.isFinal) {
      s.write('final ');
    }

    s.write(typeCode);
    s.write(' ');
    s.write(f.name);
    s.write('(');

    if (f.parametersSize > 0) {
      generateASTParametersDeclaration(f.parameters, s: s);
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
      {StringBuffer? s,
      String indent = ''}) {
    s ??= StringBuffer();

    var positionalParameters = parameters.positionalParameters;
    if (positionalParameters != null) {
      for (var i = 0; i < positionalParameters.length; ++i) {
        var p = positionalParameters[i];
        if (i > 0) s.write(', ');
        generateASTFunctionParameterDeclaration(p, s: s);
      }
    }

    var optionalParameters = parameters.optionalParameters;
    if (optionalParameters != null) {
      for (var i = 0; i < optionalParameters.length; ++i) {
        var p = optionalParameters[i];
        if (i > 0) s.write(', ');
        generateASTFunctionParameterDeclaration(p, s: s);
      }
    }

    var namedParameters = parameters.namedParameters;
    if (namedParameters != null) {
      for (var i = 0; i < namedParameters.length; ++i) {
        var p = namedParameters[i];
        if (i > 0) s.write(', ');
        generateASTFunctionParameterDeclaration(p, s: s);
      }
    }

    return s;
  }

  @override
  StringBuffer generateASTFunctionParameterDeclaration(
      ASTFunctionParameterDeclaration parameter,
      {StringBuffer? s,
      String indent = ''}) {
    return generateASTParameterDeclaration(parameter, s: s, indent: indent);
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
      {StringBuffer? s,
      String indent = '',
      bool headIndented = true}) {
    s ??= StringBuffer();

    if (headIndented) s.write(indent);

    final type = expression.type;

    s.write('new ArrayList');

    if (type != null) {
      s.write('<');
      generateASTType(type, s: s);
      s.write('>');
    } else {
      s.write('<>');
    }

    s.write('(){{\n');

    var valuesExpressions = expression.valuesExpressions;
    for (var i = 0; i < valuesExpressions.length; ++i) {
      var e = valuesExpressions[i];

      s.write('$indent  add(');
      generateASTExpression(e, s: s);
      s.write(');\n');
    }

    s.write('$indent}}');

    return s;
  }

  @override
  StringBuffer generateASTExpressionMapLiteral(
      ASTExpressionMapLiteral expression,
      {String indent = '',
      StringBuffer? s,
      bool headIndented = true}) {
    s ??= StringBuffer();

    if (headIndented) s.write(indent);

    final keyType = expression.keyType;
    final valueType = expression.valueType;

    s.write('new HashMap');

    if (keyType != null && valueType != null) {
      s.write('<');
      generateASTType(keyType, s: s);
      s.write(',');
      generateASTType(valueType, s: s);
      s.write('>');
    } else {
      s.write('<>');
    }

    s.write('(){{\n');

    var entriesExpressions = expression.entriesExpressions;
    for (var i = 0; i < entriesExpressions.length; ++i) {
      var e = entriesExpressions[i];

      s.write("$indent  put(");
      generateASTExpression(e.key, s: s);
      s.write(", ");
      generateASTExpression(e.value, s: s);
      s.write(");\n");
    }

    s.write('$indent}}');

    return s;
  }

  @override
  StringBuffer generateASTTypeArray(ASTTypeArray type,
      {StringBuffer? s, String indent = ''}) {
    s ??= StringBuffer();
    s.write(indent);
    generateASTType(type.elementType, s: s);
    s.write('[]');
    return s;
  }

  @override
  StringBuffer generateASTTypeArray2D(ASTTypeArray2D type,
      {StringBuffer? s, String indent = ''}) {
    s ??= StringBuffer();
    s.write(indent);
    generateASTType(type.elementType, s: s);
    s.write('[][]');
    return s;
  }

  @override
  StringBuffer generateASTTypeArray3D(ASTTypeArray3D type,
      {StringBuffer? s, String indent = ''}) {
    s ??= StringBuffer();
    s.write(indent);
    generateASTType(type.elementType, s: s);
    s.write('[][][]');
    return s;
  }

  @override
  StringBuffer generateASTValueString(ASTValueString value,
      {StringBuffer? s, String indent = '', bool headIndented = true}) {
    s ??= StringBuffer();

    if (headIndented) s.write(indent);

    var str = value.value;
    str = _escapeString(str);
    s.write('"$str"');

    return s;
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
      {StringBuffer? s,
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

    s ??= StringBuffer();

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
      if (i > 0) s.write(' + ');
      s.write(e);
    }

    return s;
  }

  @override
  StringBuffer generateASTValueStringVariable(ASTValueStringVariable value,
      {StringBuffer? s, String indent = '', bool precededByString = false}) {
    s ??= StringBuffer();

    if (precededByString) {
      s.write(value.variable.name);
    } else {
      s.write('String.valueOf( ${value.variable.name} )');
    }

    return s;
  }

  @override
  StringBuffer generateASTValueStringExpression(ASTValueStringExpression value,
      {StringBuffer? s, String indent = ''}) {
    s ??= StringBuffer();

    var exp = generateASTExpression(value.expression).toString();
    s.write('String.valueOf( $exp )');

    return s;
  }

  @override
  StringBuffer generateASTValueArray(ASTValueArray value,
      {StringBuffer? s, String indent = '', bool headIndented = true}) {
    s ??= StringBuffer();
    s.write(value.value);
    return s;
  }

  @override
  StringBuffer generateASTValueArray2D(ASTValueArray2D value,
      {StringBuffer? s, String indent = '', bool headIndented = true}) {
    s ??= StringBuffer();
    s.write(value.value);
    return s;
  }

  @override
  StringBuffer generateASTValueArray3D(ASTValueArray3D value,
      {StringBuffer? s, String indent = '', bool headIndented = true}) {
    s ??= StringBuffer();
    s.write(value.value);
    return s;
  }
}
