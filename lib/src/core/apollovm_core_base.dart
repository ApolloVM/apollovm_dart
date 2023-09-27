// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:swiss_knife/swiss_knife.dart';

import '../apollovm_base.dart';
import '../ast/apollovm_ast_toplevel.dart';
import '../ast/apollovm_ast_type.dart';
import '../ast/apollovm_ast_value.dart';

class ApolloVMCore {
  static ASTClass<V>? getClass<V>(String className) {
    switch (className) {
      case 'String':
        return CoreClassString.instance as ASTClass<V>;
      case 'int':
      case 'Integer':
        return CoreClassInt.instance as ASTClass<V>;
      default:
        return null;
    }
  }
}

abstract class CoreClassPrimitive<T> extends ASTClassPrimitive<T> {
  final String coreName;

  CoreClassPrimitive(ASTTypePrimitive<T> type, this.coreName) : super(type) {
    type.setClass(this);
  }

  ASTExternalClassFunction<R> _externalClassFunctionArgs0<R>(
      String name, ASTType<R> returnType, Function externalFunction,
      [ParameterValueResolver? parameterValueResolver]) {
    return ASTExternalClassFunction<R>(
        this,
        name,
        ASTParametersDeclaration(null, null, null),
        returnType,
        externalFunction,
        parameterValueResolver);
  }

  ASTExternalClassFunction<R> _externalClassFunctionArgs1<R>(
      String name,
      ASTType<R> returnType,
      ASTFunctionParameterDeclaration param1,
      Function externalFunction,
      [ParameterValueResolver? parameterValueResolver]) {
    return ASTExternalClassFunction<R>(
        this,
        name,
        ASTParametersDeclaration([param1], null, null),
        returnType,
        externalFunction,
        parameterValueResolver);
  }

  // ignore: unused_element
  ASTExternalFunction<R> _externalStaticFunctionArgs0<R>(
      String name, ASTType<R> returnType, Function externalFunction,
      [ParameterValueResolver? parameterValueResolver]) {
    return ASTExternalFunction<R>(
        name,
        ASTParametersDeclaration(null, null, null),
        returnType,
        externalFunction,
        parameterValueResolver);
  }

  ASTExternalFunction<R> _externalStaticFunctionArgs1<R>(
      String name,
      ASTType<R> returnType,
      ASTFunctionParameterDeclaration param1,
      Function externalFunction,
      [ParameterValueResolver? parameterValueResolver]) {
    return ASTExternalFunction<R>(
        name,
        ASTParametersDeclaration([param1], null, null),
        returnType,
        externalFunction,
        parameterValueResolver);
  }
}

class CoreClassString extends CoreClassPrimitive<String> {
  static final CoreClassString instance = CoreClassString._();

  late final ASTExternalClassFunction _functionContains;

  late final ASTExternalClassFunction _functionToUpperCase;

  late final ASTExternalClassFunction _functionToLowerCase;

  late final ASTExternalFunction _functionValueOf;

  CoreClassString._() : super(ASTTypeString.instance, 'String') {
    _functionContains = _externalClassFunctionArgs1(
      'contains',
      ASTTypeBool.instance,
      ASTFunctionParameterDeclaration(ASTTypeString.instance, 's', 0, false),
      (String o, String p1) => o.contains(p1),
    );

    _functionToUpperCase = _externalClassFunctionArgs0(
      'toUpperCase',
      ASTTypeString.instance,
      (String o) => o.toUpperCase(),
    );

    _functionToLowerCase = _externalClassFunctionArgs0(
      'toLowerCase',
      ASTTypeString.instance,
      (String o) => o.toLowerCase(),
    );

    _functionValueOf = _externalStaticFunctionArgs1(
      'valueOf',
      ASTTypeString.instance,
      ASTFunctionParameterDeclaration(ASTTypeDynamic.instance, 'obj', 0, false),
      (dynamic o) => o?.toString() ?? 'null',
      resolveValueToString,
    );
  }

  String resolveValueToString(ASTValue? paramVal, VMContext context) {
    if (paramVal == null) return 'null';

    if (paramVal is VMObject) {
      return paramVal.toString();
    }

    var val = paramVal.getValue(context);
    return '$val';
  }

  @override
  ASTFunctionDeclaration? getFunction(
      String fName, ASTFunctionSignature parametersSignature, VMContext context,
      {bool caseInsensitive = false}) {
    switch (fName) {
      case 'contains':
        return _functionContains;
      case 'toUpperCase':
        return _functionToUpperCase;
      case 'toLowerCase':
        return _functionToLowerCase;
      case 'valueOf':
        return _functionValueOf;
    }
    throw StateError(
        "Can't find core function: $coreName.$fName( $parametersSignature )");
  }
}

class CoreClassInt extends CoreClassPrimitive<int> {
  static final CoreClassInt instance = CoreClassInt._();

  late final ASTExternalFunction _functionValueOf;

  late final ASTExternalFunction _functionParseInt;

  CoreClassInt._() : super(ASTTypeInt.instance, 'int') {
    _functionParseInt = _externalStaticFunctionArgs1(
      'parseInt',
      ASTTypeInt.instance,
      ASTFunctionParameterDeclaration(ASTTypeString.instance, 's', 0, false),
      (dynamic p1) => parseInt(p1),
    );

    _functionValueOf = _externalStaticFunctionArgs1(
      'valueOf',
      ASTTypeString.instance,
      ASTFunctionParameterDeclaration(ASTTypeDynamic.instance, 'obj', 0, false),
      (dynamic o) => '$o',
    );
  }

  @override
  ASTFunctionDeclaration? getFunction(
      String fName, ASTFunctionSignature parametersSignature, VMContext context,
      {bool caseInsensitive = false}) {
    switch (fName) {
      case 'parseInt':
      case 'parse':
        return _functionParseInt;
      case 'valueOf':
        return _functionValueOf;
    }
    throw StateError(
        "Can't find core function: $coreName.$fName( $parametersSignature )");
  }
}
