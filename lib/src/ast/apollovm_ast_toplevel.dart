import 'dart:async';

import 'package:apollovm/apollovm.dart';
import 'package:collection/collection.dart'
    show IterableExtension, equalsIgnoreAsciiCase;

import 'apollovm_ast_statement.dart';
import 'apollovm_ast_type.dart';
import 'apollovm_ast_value.dart';
import 'apollovm_ast_variable.dart';

/// An [ASTBlock] that can have an entry-point method/function.
class ASTEntryPointBlock extends ASTBlock {
  ASTEntryPointBlock(ASTBlock? parentBlock) : super(parentBlock);

  FutureOr<ASTValue> execute(
    String entryFunctionName,
    List? positionalParameters,
    Map? namedParameters, {
    ApolloExternalFunctionMapper? externalFunctionMapper,
    VMObject? classInstanceObject,
    Map<String, ASTValue>? classInstanceFields,
  }) async {
    var rootContext = await _initializeEntryPointBlock(externalFunctionMapper);

    ApolloExternalFunctionMapper? prevExternalFunctionMapper;
    if (externalFunctionMapper != null) {
      prevExternalFunctionMapper = rootContext.externalFunctionMapper;
      rootContext.externalFunctionMapper = externalFunctionMapper;
    }

    var prevContext = VMContext.setCurrent(rootContext);
    try {
      var fSignature =
          ASTFunctionSignature.from(positionalParameters, namedParameters);

      var f = getFunction(entryFunctionName, fSignature, rootContext,
          caseInsensitive: true);
      if (f == null) {
        throw StateError("Can't find entry function: $entryFunctionName");
      }

      var context = rootContext;

      if (!f.modifiers.isStatic) {
        if (this is ASTClass) {
          var clazz = this as ASTClass;
          var classContext = clazz._createContext(rootContext);
          var obj =
              await clazz.createInstance(classContext, ASTRunStatus.DUMMY);

          if (classInstanceObject != null) {
            obj.vmObject.setFieldsValues(
                classInstanceObject.getFieldsValues(classContext));
          }

          if (classInstanceFields != null) {
            obj.setFields(classInstanceFields, caseInsensitive: true);
          }

          classContext.setObjectInstance(obj);
          context = classContext;
        } else {
          throw StateError(
              "Can't call non-static function without a class context: $this");
        }
      }

      return await f.call(context,
          positionalParameters: positionalParameters,
          namedParameters: namedParameters);
    } finally {
      VMContext.setCurrent(prevContext);
      if (identical(
          rootContext.externalFunctionMapper, externalFunctionMapper)) {
        rootContext.externalFunctionMapper = prevExternalFunctionMapper;
      }
    }
  }

  FutureOr<ASTFunctionDeclaration?> getFunctionWithParameters(
      String entryFunctionName,
      List? positionalParameters,
      Map? namedParameters,
      {ApolloExternalFunctionMapper? externalFunctionMapper}) async {
    var rootContext = await _initializeEntryPointBlock(externalFunctionMapper);

    ApolloExternalFunctionMapper? prevExternalFunctionMapper;
    if (externalFunctionMapper != null) {
      prevExternalFunctionMapper = rootContext.externalFunctionMapper;
      rootContext.externalFunctionMapper = externalFunctionMapper;
    }

    var prevContext = VMContext.setCurrent(rootContext);
    try {
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
        rootContext.externalFunctionMapper = prevExternalFunctionMapper;
      }
    }
  }

  VMContext? _rootContext;

  Future<VMContext> _initializeEntryPointBlock(
      ApolloExternalFunctionMapper? externalFunctionMapper) async {
    if (_rootContext == null) {
      var rootContext = _createContext();
      var rootStatus = ASTRunStatus();
      _rootContext = rootContext;

      ApolloExternalFunctionMapper? prevExternalFunctionMapper;
      if (externalFunctionMapper != null) {
        prevExternalFunctionMapper = rootContext.externalFunctionMapper;
        rootContext.externalFunctionMapper = externalFunctionMapper;
      }

      var prevContext = VMContext.setCurrent(rootContext);
      try {
        await run(rootContext, rootStatus);
      } finally {
        VMContext.setCurrent(prevContext);

        if (identical(
            rootContext.externalFunctionMapper, externalFunctionMapper)) {
          rootContext.externalFunctionMapper = prevExternalFunctionMapper;
        }
      }
    }
    return _rootContext!;
  }

  VMContext _createContext() => VMContext(this);
}

/// AST of a Class.
class ASTClass extends ASTEntryPointBlock {
  final String name;
  final ASTType<VMObject> type;

  ASTClass(this.name, ASTBlock? parent)
      : type = ASTType<VMObject>(name),
        super(parent);

  @override
  void set(ASTBlock? other) {
    if (other == null) return;

    if (other is ASTClass) {
      _fields.clear();
      addAllFields(other._fields.values);
    }

    super.set(other);
  }

  @override
  VMClassContext _createContext([VMContext? parentContext]) =>
      VMClassContext(this, parent: parentContext);

  final Map<String, ASTClassField> _fields = <String, ASTClassField>{};

  List<ASTClassField> get fields => _fields.values.toList();

  List<String> get fieldsNames => _fields.keys.toList();

  void addField(ASTClassField field) {
    _fields[field.name] = field;
  }

  void addAllFields(Iterable<ASTClassField> fields) {
    for (var field in fields) {
      addField(field);
    }
  }

  /// Returns a [Map<String,Object>] with the fields names and values.
  Future<Map<String, Object>> getFieldsMap(
      {VMContext? context, Map<String, ASTValue>? fieldOverwrite}) async {
    var astRunStatus = ASTRunStatus();

    var fieldsEntriesFuture = _fields.values.map((f) async {
      if (f is ASTClassFieldWithInitialValue) {
        var initialValueFuture = context != null
            ? f.getInitialValue(context, astRunStatus)
            : f.getInitialValueNoContext();

        var initialValue = await initialValueFuture;

        var value = (await initialValue.getValueNoContext()) as Object?;
        return MapEntry(f.name, value ?? Null);
      } else {
        return MapEntry(f.name, f.type);
      }
    }).toList();

    var fieldsEntries = await Future.wait(fieldsEntriesFuture);

    var map = Map<String, Object>.fromEntries(fieldsEntries);

    if (fieldOverwrite != null && fieldOverwrite.isNotEmpty) {
      context ??= VMContext(ASTBlock(null));
      for (var entry in fieldOverwrite.entries) {
        var value = await entry.value.getValue(context);
        map[entry.key] = value ?? Null;
      }
    }

    return map;
  }

  @override
  void addFunction(ASTFunctionDeclaration f) {
    if (f is ASTClassFunctionDeclaration) {
      f.classType = type;
      super.addFunction(f);
    } else {
      throw StateError('Only accepting class functions: $f');
    }
  }

  @override
  ASTClassField? getField(String name, {bool caseInsensitive = false}) {
    var field = _fields[name];

    if (field == null && caseInsensitive) {
      for (var entry in _fields.entries) {
        if (equalsIgnoreAsciiCase(entry.key, name)) {
          field = entry.value;
          break;
        }
      }
    }

    return field;
  }

  Future<ASTObjectInstance> createInstance(
      VMClassContext context, ASTRunStatus runStatus) async {
    var obj = ASTObjectInstance(this);
    await initializeInstance(context, runStatus, obj);
    return obj;
  }

  Future<void> initializeInstance(VMClassContext context,
      ASTRunStatus runStatus, ASTObjectInstance instance) async {
    for (var field in _fields.values) {
      if (field is ASTClassFieldWithInitialValue) {
        var value = await field.getInitialValue(context, runStatus);
        instance.setField(field.name, value);
      } else {
        instance.setField(field.name, ASTValueNull.INSTANCE);
      }
    }
  }
}

/// An AST Root.
///
/// A parse of a [CodeUnit] generates an [ASTRoot].
class ASTRoot extends ASTEntryPointBlock {
  ASTRoot() : super(null);

  String namespace = '';

  final Map<String, ASTClass> _classes = <String, ASTClass>{};

  List<ASTClass> get classes => _classes.values.toList();

  List<String> get classesNames => _classes.values.map((e) => e.name).toList();

  void addClass(ASTClass clazz) {
    _classes[clazz.name] = clazz;
  }

  ASTClass? getClass(String className, {bool caseInsensitive = false}) {
    var clazz = _classes[className];

    if (clazz == null && caseInsensitive) {
      for (var entry in _classes.entries) {
        if (equalsIgnoreAsciiCase(entry.key, className)) {
          clazz = entry.value;
          break;
        }
      }
    }

    return clazz;
  }

  void addAllClasses(List<ASTClass> classes) {
    for (var clazz in classes) {
      addClass(clazz);
    }
  }
}

/// An AST Parameter declaration.
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

/// An AST Function Parameter declaration.
class ASTFunctionParameterDeclaration<T> extends ASTParameterDeclaration<T> {
  final int index;

  final bool optional;

  ASTFunctionParameterDeclaration(
      ASTType<T> type, String name, this.index, this.optional)
      : super(type, name);
}

/// An AST Function Signature.
class ASTFunctionSignature implements ASTNode {
  List<ASTType?>? positionalTypes;

  Map<String, ASTType?>? namedTypes;

  ASTFunctionSignature(this.positionalTypes, this.namedTypes);

  static ASTFunctionSignature from(
      List? positionalParameters, Map? namedParameters) {
    if ((positionalParameters == null || positionalParameters.isEmpty) &&
        (namedParameters == null || namedParameters.isEmpty)) {
      return ASTFunctionSignature(null, null);
    }

    var pos = positionalParameters != null
        ? toASTTypeList(positionalParameters)
        : null;

    var named = namedParameters != null ? toASTTypeMap(namedParameters) : null;

    if (pos != null && pos.isEmpty) pos = null;
    if (named != null && named.isEmpty) named = null;

    return ASTFunctionSignature(pos, named);
  }

  static List<ASTType?>? toASTTypeList(List? params, [VMContext? context]) {
    if (params == null || params.isEmpty) return null;
    return params.map((e) => toASTType(e, context)).toList();
  }

  static Map<String, ASTType?>? toASTTypeMap(Map? params,
      [VMContext? context]) {
    if (params == null || params.isEmpty) return null;
    return params.map((k, v) => MapEntry('$k', toASTType(v, context)));
  }

  static ASTType? toASTType(dynamic o, [VMContext? context]) {
    if (o == null) return null;
    if (o is ASTType) return o;

    if (o is ASTValue) {
      if (context != null) {
        var resolved = o.resolve(context);
        if (resolved is ASTValue) {
          return resolved.type;
        }
      }
      return o.type;
    }

    var t = ASTType.from(o);
    return t;
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
      s.write(namedTypes!.entries.map((e) {
        var k = e.key;
        var v = e.value;
        return v != null ? '$k: $v' : '$k: ?';
      }).toList());
    }

    s.write('}');

    return s.toString();
  }
}

/// An AST Function Set.
abstract class ASTFunctionSet implements ASTNode {
  String get name => firstFunction.name;

  List<ASTFunctionDeclaration> get functions;

  ASTFunctionDeclaration get firstFunction;

  ASTFunctionDeclaration get(
      ASTFunctionSignature parametersSignature, bool exactTypes);

  ASTFunctionSet add(ASTFunctionDeclaration f);
}

/// [ASTFunctionSet] implementation, with 1 entry.
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

/// [ASTFunctionSet] implementation, with multiple entries.
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

/// An AST Parameters Declaration
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

  /// Returns true if [parametersSignature] matches this parameters declaration.
  ///
  /// - [exactTypes] if true the types should be exact, and not only acceptable.
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
      for (var entry in namedTypes.entries) {
        var singParamName = entry.key;
        var signParamType = entry.value;
        if (signParamType == null) continue;

        var param = getParameterByName(singParamName);

        if (!parameterAcceptsType(param, signParamType, exactTypes)) {
          return false;
        }
      }
    }

    return true;
  }

  /// Returns true if [param] accepts [type].
  ///
  /// - [exactType] if true the [param.type] should be exact to [type].
  static bool parameterAcceptsType(
      ASTFunctionParameterDeclaration? param, ASTType? type, bool exactType) {
    if (param == null || type == null) {
      return false;
    }

    if (exactType) {
      if (param.type != type) return false;
    } else if (type is! ASTTypeDynamic && !param.type.acceptsType(type)) {
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

/// An AST Class Function Declaration.
class ASTClassFunctionDeclaration<T> extends ASTFunctionDeclaration<T> {
  /// The class type of this function.
  ASTType? classType;

  ASTClassFunctionDeclaration(this.classType, String name,
      ASTParametersDeclaration parameters, ASTType<T> returnType,
      {ASTBlock? block, ASTModifiers? modifiers})
      : super(name, parameters, returnType, block: block, modifiers: modifiers);
}

/// An AST Function Declaration.
class ASTFunctionDeclaration<T> extends ASTBlock {
  /// Name of this function.
  final String name;

  /// Parameters of this function.
  final ASTParametersDeclaration _parameters;

  /// The return type of this function.
  final ASTType<T> returnType;

  /// Modifiers of this function.
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

      var result = await super.run(context, ASTRunStatus());
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

  @override
  ASTType resolveType(VMContext? context) => returnType;
}

/// An AST External Function.
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
