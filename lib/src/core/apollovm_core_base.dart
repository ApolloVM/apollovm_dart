import 'package:apollovm/apollovm.dart';

class ApolloVMCore {
  static ASTClass<V>? getClass<V>(String className) {
    switch (className) {
      case 'String':
        return CoreClassString.INSTANCE as ASTClass<V>;
      default:
        return null;
    }
  }
}

abstract class CoreClassPrimitive<T> extends ASTClassPrimitive<T> {
  CoreClassPrimitive(ASTTypePrimitive<T> type) : super(type) {
    type.setClass(this);
  }

  ASTExternalClassFunction<R> _externalClassFunctionArgs0<R>(
      String name, ASTType<R> returnType, Function externalFunction) {
    return ASTExternalClassFunction<R>(
        this,
        name,
        ASTParametersDeclaration(null, null, null),
        returnType,
        externalFunction);
  }

  ASTExternalClassFunction<R> _externalClassFunctionArgs1<R>(
      String name,
      ASTType<R> returnType,
      ASTFunctionParameterDeclaration param1,
      Function externalFunction) {
    return ASTExternalClassFunction<R>(
        this,
        name,
        ASTParametersDeclaration([param1], null, null),
        returnType,
        externalFunction);
  }

  // ignore: unused_element
  ASTExternalFunction<R> _externalStaticFunctionArgs0<R>(
      String name, ASTType<R> returnType, Function externalFunction) {
    return ASTExternalFunction<R>(
        name,
        ASTParametersDeclaration(null, null, null),
        returnType,
        externalFunction);
  }

  ASTExternalFunction<R> _externalStaticFunctionArgs1<R>(
      String name,
      ASTType<R> returnType,
      ASTFunctionParameterDeclaration param1,
      Function externalFunction) {
    return ASTExternalFunction<R>(
        name,
        ASTParametersDeclaration([param1], null, null),
        returnType,
        externalFunction);
  }
}

class CoreClassString extends CoreClassPrimitive<String> {
  static final CoreClassString INSTANCE = CoreClassString._();

  late final ASTExternalClassFunction _function_contains;

  late final ASTExternalClassFunction _function_toUpperCase;

  late final ASTExternalClassFunction _function_toLowerCase;

  late final ASTExternalFunction _function_valueOf;

  CoreClassString._() : super(ASTTypeString.INSTANCE) {
    _function_contains = _externalClassFunctionArgs1(
      'contains',
      ASTTypeBool.INSTANCE,
      ASTFunctionParameterDeclaration(ASTTypeString.INSTANCE, 's', 0, false),
      (String o, String p1) => o.contains(p1),
    );

    _function_toUpperCase = _externalClassFunctionArgs0(
      'toUpperCase',
      ASTTypeString.INSTANCE,
      (String o) => o.toUpperCase(),
    );

    _function_toLowerCase = _externalClassFunctionArgs0(
      'toLowerCase',
      ASTTypeString.INSTANCE,
      (String o) => o.toLowerCase(),
    );

    _function_valueOf = _externalStaticFunctionArgs1(
      'valueOf',
      ASTTypeString.INSTANCE,
      ASTFunctionParameterDeclaration(ASTTypeDynamic.INSTANCE, 'obj', 0, false),
      (dynamic o) => '$o',
    );
  }

  @override
  ASTFunctionDeclaration? getFunction(
      String fName, ASTFunctionSignature parametersSignature, VMContext context,
      {bool caseInsensitive = false}) {
    switch (fName) {
      case 'contains':
        return _function_contains;
      case 'toUpperCase':
        return _function_toUpperCase;
      case 'toLowerCase':
        return _function_toLowerCase;
      case 'valueOf':
        return _function_valueOf;
    }
    throw StateError(
        "Can't find core function: $fName( $parametersSignature )");
  }
}
