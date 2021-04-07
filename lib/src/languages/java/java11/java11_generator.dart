import 'package:apollovm/apollovm.dart';

import 'package:apollovm/src/apollovm_code_generator.dart';
import 'package:apollovm/src/apollovm_code_storage.dart';

class ApolloCodeGeneratorJava11 extends ApolloCodeGenerator {
  ApolloCodeGeneratorJava11(ApolloCodeStorage codeStorage) : super(codeStorage);

  @override
  StringBuffer generateASTCodeClass(ASTCodeClass codeClass,
      [String indent = '', StringBuffer? s]) {
    s ??= StringBuffer();

    var code = generateASTCodeBlock(codeClass);

    s.write('class ');
    s.write(codeClass.name);
    s.write(' ');
    s.write(code);

    return s;
  }

  @override
  StringBuffer generateASTFunctionDeclaration(ASTFunctionDeclaration f,
      [String indent = '', StringBuffer? s]) {
    s ??= StringBuffer();

    var typeCode = generateASTType(f.returnType);

    var blockCode = generateASTCodeBlock(f, indent, null, false);

    s.write(indent);
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
      for (var i = 0; i < optionalParameters.length; ++i) {
        var p = optionalParameters[i];
        if (i > 0) s.write(', ');
        generateASTFunctionParameterDeclaration(p, '', s);
      }
    }

    var namedParameters = parameters.namedParameters;
    if (namedParameters != null) {
      for (var i = 0; i < namedParameters.length; ++i) {
        var p = namedParameters[i];
        if (i > 0) s.write(', ');
        generateASTFunctionParameterDeclaration(p, '', s);
      }
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
  String resolveASTExpressionOperatorText(ASTExpressionOperator operator) {
    if (operator == ASTExpressionOperator.divideAsInt) {
      return getASTExpressionOperatorText(ASTExpressionOperator.divide);
    }
    return getASTExpressionOperatorText(operator);
  }

  @override
  StringBuffer generateASTTypeArray(ASTTypeArray type,
      [String indent = '', StringBuffer? s]) {
    s ??= StringBuffer();
    s.write(indent);
    generateASTType(type.elementType, '', s);
    s.write('[]');
    return s;
  }

  @override
  StringBuffer generateASTTypeArray2D(ASTTypeArray2D type,
      [String indent = '', StringBuffer? s]) {
    s ??= StringBuffer();
    s.write(indent);
    generateASTType(type.elementType, '', s);
    s.write('[][]');
    return s;
  }

  @override
  StringBuffer generateASTTypeArray3D(ASTTypeArray3D type,
      [String indent = '', StringBuffer? s]) {
    s ??= StringBuffer();
    s.write(indent);
    generateASTType(type.elementType, '', s);
    s.write('[][][]');
    return s;
  }

  @override
  StringBuffer generateASTValueString(ASTValueString value,
      [String indent = '', StringBuffer? s]) {
    s ??= StringBuffer();

    s.write(indent);

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
      [String indent = '',
      StringBuffer? s]) {
    var list = <dynamic>[];

    for (var v in value.values) {
      if (v is ASTValueStringVariable) {
        var s2 = generateASTValueStringVariable(v, '');
        list.add(s2);
      } else if (v is ASTValueStringExpresion) {
        var s2 = generateASTValueStringExpresion(v, '');
        list.add(s2);
      } else if (v is ASTValueStringConcatenation) {
        var s2 = generateASTValueStringConcatenation(v, '');
        list.add(s2.toString());
      } else if (v is ASTValueString) {
        var s2 = generateASTValueString(v, '');
        list.add(s2.toString());
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
      [String indent = '', StringBuffer? s]) {
    s ??= StringBuffer();
    s.write('String.valueOf( ${value.variable.name} )');
    return s;
  }

  @override
  StringBuffer generateASTValueStringExpresion(ASTValueStringExpresion value,
      [String indent = '', StringBuffer? s]) {
    s ??= StringBuffer();

    var exp = generateASTExpression(value.expression, '').toString();
    s.write('String.valueOf( $exp )');

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
