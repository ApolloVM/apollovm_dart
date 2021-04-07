import 'package:apollovm/apollovm.dart';
import 'package:collection/collection.dart' show IterableExtension;

import 'apollovm_ast_statement.dart';
import 'apollovm_ast_type.dart';
import 'apollovm_ast_value.dart';
import 'apollovm_ast_variable.dart';

class ASTCodeClass extends ASTCodeBlock {
  final String name;

  ASTCodeClass(this.name, ASTCodeBlock? parent) : super(parent);

  final Map<String, ASTClassField> _fields = <String, ASTClassField>{};

  @override
  ASTClassField? getField(String name) => _fields[name];
}

class ASTCodeRoot extends ASTCodeBlock {
  ASTCodeRoot() : super(null);

  String namespace = '';

  final Map<String, ASTCodeClass> _classes = <String, ASTCodeClass>{};

  List<ASTCodeClass> get classes => _classes.values.toList();

  List<String> get classesNames => _classes.values.map((e) => e.name).toList();

  void addClass(ASTCodeClass clazz) {
    _classes[clazz.name] = clazz;
  }

  ASTCodeClass? getClass(String className) {
    return _classes[className];
  }

  void addAllClasses(List<ASTCodeClass> classes) {
    for (var clazz in classes) {
      addClass(clazz);
    }
  }
}

class ExternalFunctionSet {
  ASTPrintFunction? printFunction;
}

class ASTParameterDeclaration<T> implements ASTNode {
  final ASTType<T> type;

  final String name;

  ASTParameterDeclaration(this.type, this.name);

  ASTValue<T>? toValue(VMContext context, Object? v) =>
      type.toValue(context, v);

  @override
  String toString() {
    return '$type $name';
  }
}

class ASTFunctionParameterDeclaration<T> extends ASTParameterDeclaration<T> {
  final int index;

  final bool optional;

  ASTFunctionParameterDeclaration(
      ASTType<T> type, String name, this.index, this.optional)
      : super(type, name);
}

class ASTFunctionSignature implements ASTNode {
  List<ASTType?>? positionalTypes;

  List<ASTType?>? namedTypes;

  ASTFunctionSignature(this.positionalTypes, this.namedTypes);

  static ASTFunctionSignature from(
      dynamic? positionalParameters, dynamic? namedParameters) {
    if ((positionalParameters == null || positionalParameters.isEmpty) &&
        (namedParameters == null || namedParameters.isEmpty)) {
      return ASTFunctionSignature(null, null);
    }

    var pos = positionalParameters != null
        ? toASTTypeList(positionalParameters)
        : null;
    var named = namedParameters != null ? toASTTypeList(namedParameters) : null;

    return ASTFunctionSignature(pos, named);
  }

  static List<ASTType?> toASTTypeList(dynamic o) {
    if (o == null) return [null];
    if (o is ASTType) return [o];

    if (o is ASTValue) return [o.type];

    if (o is Map) {
      o = o.values.toList();
    }

    if (o is List) {
      var typesList = o.map((e) => ASTType.from(e)).toList();
      return typesList;
    }

    var t = ASTType.from(o);

    return [t];
  }

  int get size {
    var total = 0;

    if (positionalTypes != null) {
      total += positionalTypes!.length;
    }

    if (namedTypes != null) {
      total += namedTypes!.length;
    }

    return total;
  }

  bool get isEmpty {
    if (positionalTypes != null && positionalTypes!.isNotEmpty) return false;
    if (namedTypes != null && namedTypes!.isNotEmpty) return false;
    return true;
  }

  bool get isNotEmpty => !isEmpty;

  @override
  String toString() {
    var s = StringBuffer();

    s.write('{');

    if (positionalTypes != null && positionalTypes!.isNotEmpty) {
      s.write('positionalTypes: ');
      s.write(positionalTypes);
    }

    if (namedTypes != null && namedTypes!.isNotEmpty) {
      if (s.length > 1) s.write(', ');
      s.write('namedTypes: ');
      s.write(namedTypes!.map((e) => e != null ? '$e' : '?').toList());
    }

    s.write('}');

    return s.toString();
  }
}

abstract class ASTCodeFunctionSet implements ASTNode {
  List<ASTFunctionDeclaration> get functions;

  ASTFunctionDeclaration get firstFunction;

  ASTFunctionDeclaration get(
      ASTFunctionSignature parametersSignature, bool exactTypes);

  ASTCodeFunctionSet add(ASTFunctionDeclaration f);
}

class ASTCodeFunctionSetSingle extends ASTCodeFunctionSet {
  final ASTFunctionDeclaration f;

  ASTCodeFunctionSetSingle(this.f);

  @override
  ASTFunctionDeclaration get firstFunction => f;

  @override
  List<ASTFunctionDeclaration> get functions => [f];

  @override
  ASTFunctionDeclaration get(
      ASTFunctionSignature parametersSignature, bool exactTypes) {
    if (f.matchesParametersTypes(parametersSignature, exactTypes)) {
      return f;
    }

    throw StateError(
        'Function \'${f.name}\' parameters signature not compatible: $parametersSignature != ${f.parameters}');
  }

  @override
  ASTCodeFunctionSet add(ASTFunctionDeclaration f) {
    var set = ASTCodeFunctionSetMultiple();
    set.add(this.f);
    set.add(f);
    return set;
  }
}

class ASTCodeFunctionSetMultiple extends ASTCodeFunctionSet {
  final List<ASTFunctionDeclaration> _functions = <ASTFunctionDeclaration>[];

  @override
  ASTFunctionDeclaration get firstFunction => _functions.first;

  @override
  List<ASTFunctionDeclaration> get functions => _functions;

  @override
  ASTFunctionDeclaration get(
      ASTFunctionSignature parametersSignature, bool exactTypes) {
    for (var f in _functions) {
      if (f.matchesParametersTypes(parametersSignature, exactTypes)) {
        return f;
      }
    }

    ASTFunctionDeclaration? first;
    for (var f in _functions) {
      first = f;
      break;
    }

    if (!exactTypes && first != null) {
      return first;
    }

    throw StateError(
        "Can't find function \'${first?.name}\' with signature: $parametersSignature");
  }

  @override
  ASTCodeFunctionSet add(ASTFunctionDeclaration f) {
    _functions.add(f);

    _functions.sort((a, b) {
      var pSize1 = a.parametersSize;
      var pSize2 = b.parametersSize;
      return pSize1.compareTo(pSize2);
    });

    return this;
  }
}

class ASTParametersDeclaration {
  List<ASTFunctionParameterDeclaration>? positionalParameters;

  List<ASTFunctionParameterDeclaration>? optionalParameters;

  List<ASTFunctionParameterDeclaration>? namedParameters;

  ASTParametersDeclaration(
      this.positionalParameters, this.optionalParameters, this.namedParameters);

  int get positionalParametersSize => positionalParameters?.length ?? 0;

  int get optionalParametersSize => optionalParameters?.length ?? 0;

  int get namedParametersSize => namedParameters?.length ?? 0;

  int get size =>
      positionalParametersSize + optionalParametersSize + namedParametersSize;

  bool get isEmpty => size == 0;

  bool get isNotEmpty => !isEmpty;

  ASTFunctionParameterDeclaration? getParameterByIndex(int index) {
    var positionalParametersSize = this.positionalParametersSize;

    if (index < positionalParametersSize) {
      return positionalParameters![index];
    }

    var optionalIndex = index - positionalParametersSize;

    if (optionalIndex < optionalParametersSize) {
      return optionalParameters![optionalIndex];
    }

    return null;
  }

  ASTFunctionParameterDeclaration? getParameterByName(String name) {
    if (namedParameters != null) {
      var p = namedParameters!.firstWhereOrNull((p) => p.name == name);
      if (p != null) return p;
    }

    if (positionalParameters != null) {
      var p = positionalParameters!.firstWhereOrNull((p) => p.name == name);
      if (p != null) return p;
    }

    if (optionalParameters != null) {
      var p = optionalParameters!.firstWhereOrNull((p) => p.name == name);
      if (p != null) return p;
    }

    return null;
  }

  bool matchesParametersTypes(
      ASTFunctionSignature parametersSignature, bool exactTypes) {
    var parametersSize = size;
    var paramsSignSize = parametersSignature.size;

    if (paramsSignSize == 0 && parametersSize == 0) return false;
    if (paramsSignSize > parametersSize) return false;

    var paramsSignPositionalTypes = parametersSignature.positionalTypes;

    var i = 0;
    if (paramsSignPositionalTypes != null) {
      var positionalSize = paramsSignPositionalTypes.length;

      for (; i < positionalSize; ++i) {
        var signParamType = paramsSignPositionalTypes[i];
        if (signParamType == null) continue;

        var param = getParameterByIndex(i);

        if (!parameterAcceptsType(param, signParamType, exactTypes)) {
          return false;
        }
      }
    }

    var namedTypes = parametersSignature.namedTypes;
    if (namedTypes != null) {
      for (var signParamType in namedTypes) {
        if (signParamType == null) continue;
        var param = getParameterByName(signParamType.name);

        if (!parameterAcceptsType(param, signParamType, exactTypes)) {
          return false;
        }
      }
    }

    return true;
  }

  static bool parameterAcceptsType(
      ASTFunctionParameterDeclaration? param, ASTType? type, bool exactType) {
    if (param == null || type == null) {
      return false;
    }

    if (exactType) {
      if (param.type != type) return false;
    } else if (!param.type.isInstance(type)) {
      return false;
    }

    return true;
  }

  @override
  String toString() {
    var s = StringBuffer();
    s.write('{');

    if (positionalParameters != null) {
      s.write('positionalParameters: ');
      s.write(positionalParameters);
    }

    if (optionalParameters != null) {
      if (s.length > 1) s.write(', ');
      s.write('optionalParameters: ');
      s.write(optionalParameters);
    }

    if (namedParameters != null) {
      if (s.length > 1) s.write(', ');
      s.write('namedParameters: ');
      s.write(namedParameters);
    }

    s.write('}');

    return s.toString();
  }
}

class ASTFunctionDeclaration<T> extends ASTCodeBlock {
  final String name;

  final ASTParametersDeclaration _parameters;

  final ASTType<T> returnType;

  ASTFunctionDeclaration(this.name, this._parameters, this.returnType,
      [ASTCodeBlock? block])
      : super(null) {
    set(block);
  }

  ASTParametersDeclaration get parameters => _parameters;

  int get parametersSize => _parameters.size;

  ASTFunctionParameterDeclaration? getParameterByIndex(int index) =>
      _parameters.getParameterByIndex(index);

  ASTFunctionParameterDeclaration? getParameterByName(String name) =>
      _parameters.getParameterByName(name);

  ASTValue? getParameterValueByIndex(VMContext context, int index) {
    var p = getParameterByIndex(index);
    if (p == null) return null;
    var variable = context.getVariable(p.name, false);
    return variable!.getValue(context);
  }

  ASTValue? getParameterValueByName(VMContext context, String name) {
    var p = getParameterByName(name);
    if (p == null) return null;
    return context.getVariable(p.name, false)?.getValue(context);
  }

  bool matchesParametersTypes(
          ASTFunctionSignature signature, bool exactTypes) =>
      _parameters.matchesParametersTypes(signature, exactTypes);

  ASTValue<T> call(VMContext parent,
      {List? positionalParameters, Map? namedParameters}) {
    var context = VMContext(this, parent: parent);

    var prevContext = VMContext.setCurrent(context);
    try {
      initializeVariables(context, positionalParameters, namedParameters);

      var result = super.run(context, ASTRunStatus.DUMMY);
      return resolveReturnValue(context, result);
    } finally {
      VMContext.setCurrent(prevContext);
    }
  }

  ASTValue<T> resolveReturnValue(VMContext context, Object? returnValue) {
    var resolved = returnType.toValue(context, returnValue) ??
        (ASTValueVoid.INSTANCE as ASTValue<T>);
    return resolved;
  }

  void initializeVariables(
      VMContext context, List? positionalParameters, Map? namedParameters) {
    var i = 0;

    if (positionalParameters != null) {
      for (; i < positionalParameters.length; ++i) {
        var paramVal = positionalParameters[i];
        var fParam = getParameterByIndex(i);
        if (fParam == null) {
          throw StateError("Can't find parameter at index: $i");
        }
        var value = fParam.toValue(context, paramVal) ?? ASTValueNull.INSTANCE;
        context.declareVariableWithValue(fParam.type, fParam.name, value);
      }
    }

    var parametersSize = this.parametersSize;

    for (; i < parametersSize; ++i) {
      var fParam = getParameterByIndex(i)!;
      context.declareVariableWithValue(
          fParam.type, fParam.name, ASTValueNull.INSTANCE);
    }
  }

  @override
  VMContext defineRunContext(VMContext parentContext) {
    // Ensure the the passed parentContext will be used by the block,
    // since is already instantiated by call(...).
    return parentContext;
  }

  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    throw UnsupportedError(
        "Can't run this block directly! Should use call(...), since this block needs parameters initialization!");
  }
}

class ASTExternalFunction<T> extends ASTFunctionDeclaration<T> {
  final Function externalFunction;

  ASTExternalFunction(String name, ASTParametersDeclaration parameters,
      ASTType<T> returnType, this.externalFunction)
      : super(name, parameters, returnType);

  @override
  ASTValue<T> call(VMContext parent,
      {List? positionalParameters, Map? namedParameters}) {
    var context = VMContext(this, parent: parent);

    var prevContext = VMContext.setCurrent(context);
    try {
      initializeVariables(context, positionalParameters, namedParameters);

      var result;
      if (externalFunction is Function(dynamic a)) {
        var a0 = getParameterValueByIndex(context, 0)?.getValue(context);
        result = externalFunction(a0);
      } else if (externalFunction is Function(dynamic a0, dynamic a1)) {
        var a0 = getParameterValueByIndex(context, 0)?.getValue(context);
        var a1 = getParameterValueByIndex(context, 1)?.getValue(context);
        result = externalFunction(a0, a1);
      } else {
        result = externalFunction();
      }

      return resolveReturnValue(context, result);
    } finally {
      VMContext.setCurrent(prevContext);
    }
  }
}

typedef ASTPrintFunction = void Function(Object? o);
