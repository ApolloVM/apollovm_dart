import 'package:apollovm/apollovm.dart';
import 'package:apollovm/src/apollovm_code_generator.dart';
import 'package:apollovm/src/apollovm_code_storage.dart';

class ApolloCodeGeneratorJava8 extends ApolloCodeGenerator {
  ApolloCodeGeneratorJava8(ApolloCodeStorage codeStorage) : super(codeStorage);

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
    s.write("'$str'");

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
