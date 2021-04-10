import 'dart:async';

import 'package:apollovm/apollovm.dart';
import 'package:collection/collection.dart' show IterableExtension;

import 'apollovm_ast_statement.dart';
import 'apollovm_ast_type.dart';
import 'apollovm_ast_value.dart';
import 'apollovm_ast_variable.dart';

class ASTEntryPointBlock extends ASTBlock {
  ASTEntryPointBlock(ASTBlock? parentBlock) : super(parentBlock);

  FutureOr<ASTValue> execute(String entryFunctionName,
      dynamic? positionalParameters, dynamic? namedParameters,
      {ApolloExternalFunctionMapper? externalFunctionMapper}) async {
    var rootContext = await _initializeEntryPointBlock();

    var prevContext = VMContext.setCurrent(rootContext);
    try {
      if (externalFunctionMapper != null) {
        rootContext.externalFunctionMapper = externalFunctionMapper;
      }

      var fSignature =
          ASTFunctionSignature.from(positionalParameters, namedParameters);

      var f = getFunction(entryFunctionName, fSignature, rootContext);
      if (f == null) {
        throw StateError("Can't find entry function: $entryFunctionName");
      }

      if (!f.modifiers.isStatic) {
        if (this is ASTClass) {
          var obj = (this as ASTClass).createInstance();
          (rootContext as VMClassContext).setObjectInstance(obj);
        }
      }

      return await f.call(rootContext,
          positionalParameters: positionalParameters,
          namedParameters: namedParameters);
    } finally {
      VMContext.setCurrent(prevContext);
      if (identical(
          rootContext.externalFunctionMapper, externalFunctionMapper)) {
        rootContext.externalFunctionMapper = null;
      }
    }
  }

  FutureOr<ASTFunctionDeclaration?> getFunctionWithParameters(
      String entryFunctionName,
      dynamic? positionalParameters,
      dynamic? namedParameters,
      {ApolloExternalFunctionMapper? externalFunctionMapper}) async {
    var rootContext = await _initializeEntryPointBlock();

    var prevContext = VMContext.setCurrent(rootContext);
    try {
      if (externalFunctionMapper != null) {
        rootContext.externalFunctionMapper = externalFunctionMapper;
      }

      var fSignature =
          ASTFunctionSignature.from(positionalParameters, namedParameters);

      try {
        var f = getFunction(entryFunctionName, fSignature, rootContext);
        return f;
      } on Error {
        return null;
      }
    } finally {
      VMContext.setCurrent(prevContext);
      if (identical(
          rootContext.externalFunctionMapper, externalFunctionMapper)) {
        rootContext.externalFunctionMapper = null;
      }
    }
  }

  VMContext? _rootContext;

  Future<VMContext> _initializeEntryPointBlock() async {
    if (_rootContext == null) {
      var rootContext = _createContext();
      var rootStatus = ASTRunStatus();
      _rootContext = rootContext;

      var prevContext = VMContext.setCurrent(rootContext);
      try {
        await run(rootContext, rootStatus);
      } finally {
        VMContext.setCurrent(prevContext);
      }
    }
    return _rootContext!;
  }

  VMContext _createContext() => VMContext(this);
}

class ASTClass extends ASTEntryPointBlock {
  final String name;
  final ASTType<VMObject> type;
  ASTClass(this.name, ASTBlock? parent)
      : type = ASTType<VMObject>(name),
        super(parent);

  @override
  VMContext _createContext() => VMClassContext(this);

  final Map<String, ASTClassField> _fields = <String, ASTClassField>{};

  @override
  ASTClassField? getField(String name) => _fields[name];

  ASTObjectInstance createInstance() {
    var obj = ASTObjectInstance(this);
    return obj;
  }
}

class ASTRoot extends ASTEntryPointBlock {
  ASTRoot() : super(null);

  String namespace = '';

  final Map<String, ASTClass> _classes = <String, ASTClass>{};

  List<ASTClass> get classes => _classes.values.toList();

  List<String> get classesNames => _classes.values.map((e) => e.name).toList();

  void addClass(ASTClass clazz) {
    _classes[clazz.name] = clazz;
  }

  ASTClass? getClass(String className) {
    return _classes[className];
  }

  void addAllClasses(List<ASTClass> classes) {
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

  FutureOr<ASTValue<T>?> toValue(VMContext context, Object? v) =>
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

abstract class ASTFunctionSet implements ASTNode {
  List<ASTFunctionDeclaration> get functions;

  ASTFunctionDeclaration get firstFunction;

  ASTFunctionDeclaration get(
      ASTFunctionSignature parametersSignature, bool exactTypes);

  ASTFunctionSet add(ASTFunctionDeclaration f);
}

class ASTFunctionSetSingle extends ASTFunctionSet {
  final ASTFunctionDeclaration f;

  ASTFunctionSetSingle(this.f);

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
        'Function \'${f.name}\' parameters signature not compatible: sign:$parametersSignature != f:${f.parameters}');
  }

  @override
  ASTFunctionSet add(ASTFunctionDeclaration f) {
    var set = ASTFunctionSetMultiple();
    set.add(this.f);
    set.add(f);
    return set;
  }
}

class ASTFunctionSetMultiple extends ASTFunctionSet {
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
  ASTFunctionSet add(ASTFunctionDeclaration f) {
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

    if (paramsSignSize == 0 && parametersSize == 0) return true;
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

class ASTFunctionDeclaration<T> extends ASTBlock {
  final String name;

  final ASTParametersDeclaration _parameters;

  final ASTType<T> returnType;

  final ASTModifiers modifiers;

  ASTFunctionDeclaration(this.name, this._parameters, this.returnType,
      {ASTBlock? block, ASTModifiers? modifiers})
      : modifiers = modifiers ?? ASTModifiers.modifiersNone,
        super(null) {
    set(block);
  }

  ASTParametersDeclaration get parameters => _parameters;

  int get parametersSize => _parameters.size;

  ASTFunctionParameterDeclaration? getParameterByIndex(int index) =>
      _parameters.getParameterByIndex(index);

  ASTFunctionParameterDeclaration? getParameterByName(String name) =>
      _parameters.getParameterByName(name);

  FutureOr<ASTValue?> getParameterValueByIndex(VMContext context, int index) {
    var p = getParameterByIndex(index);
    if (p == null) return null;
    var variable = context.getVariable(p.name, false);
    return variable?.getValue(context);
  }

  FutureOr<ASTValue?> getParameterValueByName(VMContext context, String name) {
    var p = getParameterByName(name);
    if (p == null) return null;
    var variable = context.getVariable(p.name, false);
    return variable?.getValue(context);
  }

  bool matchesParametersTypes(
          ASTFunctionSignature signature, bool exactTypes) =>
      _parameters.matchesParametersTypes(signature, exactTypes);

  FutureOr<ASTValue<T>> call(VMContext parent,
      {List? positionalParameters, Map? namedParameters}) async {
    var context = VMContext(this, parent: parent);

    var prevContext = VMContext.setCurrent(context);
    try {
      await initializeVariables(context, positionalParameters, namedParameters);

      var result = await super.run(context, ASTRunStatus.DUMMY);
      return await resolveReturnValue(context, result);
    } finally {
      VMContext.setCurrent(prevContext);
    }
  }

  FutureOr<ASTValue<T>> resolveReturnValue(
      VMContext context, Object? returnValue) async {
    var resolved = await returnType.toValue(context, returnValue);
    resolved ??= ASTValueVoid.INSTANCE as ASTValue<T>;
    return resolved;
  }

  Future<void> initializeVariables(VMContext context,
      List? positionalParameters, Map? namedParameters) async {
    var i = 0;

    if (positionalParameters != null) {
      for (; i < positionalParameters.length; ++i) {
        var paramVal = positionalParameters[i];
        var fParam = getParameterByIndex(i);
        if (fParam == null) {
          throw StateError("Can't find parameter at index: $i");
        }
        var value =
            await fParam.toValue(context, paramVal) ?? ASTValueNull.INSTANCE;
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
  FutureOr<ASTValue<T>> call(VMContext parent,
      {List? positionalParameters, Map? namedParameters}) async {
    var context = VMContext(this, parent: parent);

    var prevContext = VMContext.setCurrent(context);
    try {
      await initializeVariables(context, positionalParameters, namedParameters);

      var parametersSize = this.parametersSize;

      var result;
      if (externalFunction.isParametersSize0 || parametersSize == 0) {
        result = externalFunction();
      } else if (externalFunction.isParametersSize1 || parametersSize == 1) {
        var paramVal = await getParameterValueByIndex(context, 0);
        var a0 = paramVal?.getValue(context);
        result = externalFunction(a0);
      } else if (this.parametersSize == 2) {
        var paramVal0 = await getParameterValueByIndex(context, 0);
        var paramVal1 = await getParameterValueByIndex(context, 1);
        var a0 = paramVal0?.getValue(context);
        var a1 = paramVal1?.getValue(context);
        result = externalFunction(a0, a1);
      } else if (this.parametersSize == 3) {
        var paramVal0 = await getParameterValueByIndex(context, 0);
        var paramVal1 = await getParameterValueByIndex(context, 1);
        var paramVal2 = await getParameterValueByIndex(context, 2);
        var a0 = paramVal0?.getValue(context);
        var a1 = paramVal1?.getValue(context);
        var a2 = paramVal2?.getValue(context);
        result = externalFunction(a0, a1, a2);
      } else {
        result = externalFunction.call();
      }

      if (result is Future) {
        var r = await result;
        return await resolveReturnValue(context, r);
      } else {
        return await resolveReturnValue(context, result);
      }
    } finally {
      VMContext.setCurrent(prevContext);
    }
  }
}

extension _FExtension on Function {
  bool get isParametersSize0 {
    return this is Function();
  }

  bool get isParametersSize1 {
    return this is Function(dynamic a) ||
        this is Function(Object a) ||
        this is Function(String a) ||
        this is Function(int a) ||
        this is Function(double a) ||
        this is Function(List a) ||
        this is Function(Map a);
  }
}

typedef ASTPrintFunction = void Function(Object? o);
