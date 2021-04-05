import 'package:apollovm/apollovm.dart';
import 'package:collection/collection.dart' show IterableExtension;
import 'package:swiss_knife/swiss_knife.dart';

import 'apollovm_parser.dart';

abstract class ASTNode {}

class ASTRunStatus {
  static final ASTRunStatus DUMMY = ASTRunStatus();

  bool returned = false;

  ASTValue? returnedValue;

  ASTValueVoid returnVoid() {
    returned = true;
    returnedValue = ASTValueVoid.INSTANCE;
    return ASTValueVoid.INSTANCE;
  }

  ASTValueNull returnNull() {
    returned = true;
    returnedValue = ASTValueNull.INSTANCE;
    return ASTValueNull.INSTANCE;
  }

  ASTValue returnValue(ASTValue value) {
    returned = true;
    returnedValue = value;
    return value;
  }

  bool continued = false;

  bool broke = false;
}

abstract class ASTCodeRunner {
  VMContext defineRunContext(VMContext parentContext) {
    return parentContext;
  }

  ASTValue run(VMContext parentContext, ASTRunStatus runStatus);
}

abstract class ASTStatement implements ASTCodeRunner, ASTNode {
  @override
  VMContext defineRunContext(VMContext parentContext) {
    return parentContext;
  }
}

class ASTCodeBlock extends ASTStatement {
  ASTCodeBlock? parentBlock;

  ASTCodeBlock(this.parentBlock);

  final Map<String, ASTCodeFunctionSet> _functions = {};

  List<ASTCodeFunctionSet> get functions => _functions.values.toList();

  void addFunction(ASTFunctionDeclaration f) {
    var name = f.name;
    f.parentBlock = this;

    var set = _functions[name];
    if (set == null) {
      _functions[name] = ASTCodeFunctionSetSingle(f);
    } else {
      var set2 = set.add(f);
      if (!identical(set, set2)) {
        _functions[name] = set2;
      }
    }
  }

  void addAllFunctions(Iterable<ASTFunctionDeclaration> fs) {
    for (var f in fs) {
      addFunction(f);
    }
  }

  bool containsFunctionWithName(
    String name,
  ) {
    var set = _functions[name];
    return set != null;
  }

  ASTFunctionDeclaration? getFunction(
    String fName,
    ASTFunctionSignature parametersSignature,
    VMContext context,
  ) {
    var set = _functions[fName];
    if (set != null) return set.get(parametersSignature, false);

    var fExternal =
        context.getMappedExternalFunction(fName, parametersSignature);
    return fExternal;
  }

  ASTType<T>? getFunctionReturnType<T>(String name,
          ASTFunctionSignature parametersTypes, VMContext context) =>
      getFunction(name, parametersTypes, context)?.returnType as ASTType<T>?;

  final List<ASTStatement> _statements = [];

  List<ASTStatement> get statements => _statements.toList();

  void set(ASTCodeBlock? other) {
    if (other == null) return;

    _functions.clear();
    addAllFunctions(other._functions.values.expand((e) => e.functions));

    _statements.clear();
    addAllStatements(other._statements);
  }

  void addStatement(ASTStatement statement) {
    _statements.add(statement);
    if (statement is ASTCodeBlock) {
      statement.parentBlock = this;
    }
  }

  void addAllStatements(Iterable<ASTStatement> statements) {
    for (var stm in statements) {
      addStatement(stm);
    }
  }

  ASTValue execute(String entryFunctionName, dynamic? positionalParameters,
      dynamic? namedParameters,
      {ApolloExternalFunctionMapper? externalFunctionMapper}) {
    var rootContext = VMContext(this);
    if (externalFunctionMapper != null) {
      rootContext.externalFunctionMapper = externalFunctionMapper;
    }

    var rootStatus = ASTRunStatus();

    run(rootContext, rootStatus);

    var fSignature =
        ASTFunctionSignature.from(positionalParameters, namedParameters);

    var f = getFunction(entryFunctionName, fSignature, rootContext);
    if (f == null) {
      throw StateError("Can't find entry function: $entryFunctionName");
    }
    return f.call(rootContext,
        positionalParameters: positionalParameters,
        namedParameters: namedParameters);
  }

  @override
  VMContext defineRunContext(VMContext parentContext) {
    return parentContext;
  }

  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    var blockContext = defineRunContext(parentContext);

    ASTValue returnValue = ASTValueVoid.INSTANCE;

    for (var stm in _statements) {
      var ret = stm.run(blockContext, runStatus);

      if (runStatus.returned) {
        return runStatus.returnedValue!;
      }

      returnValue = ret;
    }

    return returnValue;
  }

  ASTClassField? getField(String name) =>
      parentBlock != null ? parentBlock!.getField(name) : null;
}

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
        'Function parameters signature not compatible: $parametersSignature != ${f.parameters}');
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

    for (var f in _functions) {
      return f;
    }

    throw StateError("Can't find function");
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
    return '{positionalParameters: $positionalParameters, optionalParameters: $optionalParameters, namedParameters: $namedParameters}';
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

    initializeVariables(context, positionalParameters, namedParameters);

    var result = super.run(context, ASTRunStatus.DUMMY);
    return resolveReturnValue(context, result);
  }

  ASTValue<T> resolveReturnValue(VMContext context, Object? returnValue) {
    var resolved = returnType.toValue(context, returnValue) ??
        (ASTValueVoid.INSTANCE as ASTValue<T>);
    return resolved;
  }

  void initializeVariables(
      VMContext context, List? positionalParameters, Map? namedParameters) {
    if (positionalParameters != null) {
      for (var i = 0; i < positionalParameters.length; ++i) {
        var paramVal = positionalParameters[i];
        var fParam = getParameterByIndex(i);
        if (fParam == null) {
          throw StateError("Can't find parameter at index: $i");
        }
        var value = fParam.toValue(context, paramVal) ?? ASTValueNull.INSTANCE;
        context.declareVariableWithValue(fParam.type, fParam.name, value);
      }
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
  }
}

typedef ASTPrintFunction = void Function(Object? o);

class ASTObjectValue<T> extends ASTValue<T> {
  final Map<String, ASTValue> _o = {};

  ASTObjectValue(ASTType<T> type) : super(type);

  @override
  T getValue(VMContext context) {
    return _o as T;
  }

  @override
  ASTValue<T> resolve(VMContext context) {
    return this;
  }

  ASTValue? getField(String name) => _o[name];

  ASTValue? setField(String name, ASTValue value) {
    var prev = _o[name];
    _o[name] = value;
    return prev;
  }
}

class ASTObjectInstance extends ASTVariable {
  ASTType type;

  final ASTObjectValue _value;

  ASTObjectInstance(this.type)
      : _value = ASTObjectValue(type),
        super(type.name);

  ASTValue? getField(String name) => _value.getField(name);

  ASTValue? setField(String name, ASTValue value) =>
      _value.setField(name, value);

  @override
  ASTVariable resolveVariable(VMContext context) {
    return this;
  }
}

class ExternalFunctionSet {
  ASTPrintFunction? printFunction;
}

class ASTStatementValue extends ASTStatement {
  ASTValue value;

  ASTStatementValue(ASTCodeBlock block, this.value) : super();

  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    var context = defineRunContext(parentContext);
    return value.getValue(context);
  }
}

abstract class ASTVariable implements ASTNode {
  final String name;

  ASTVariable(this.name);

  ASTVariable resolveVariable(VMContext context);

  ASTValue getValue(VMContext context) {
    var variable = resolveVariable(context);
    return variable.getValue(context);
  }

  void setValue(VMContext context, ASTValue value) {
    var variable = resolveVariable(context);
    variable.setValue(context, value);
  }

  V readIndex<V>(VMContext context, int index) =>
      getValue(context).readIndex(context, index);

  V readKey<V>(VMContext context, Object key) =>
      getValue(context).readKey(context, key);
}

abstract class ASTTypedVariable<T> extends ASTVariable {
  ASTType<T> type;
  final bool finalValue;

  ASTTypedVariable(this.type, String name, this.finalValue) : super(name);
}

class ASTClassField<T> extends ASTTypedVariable<T> {
  ASTClassField(ASTType<T> type, String name, bool finalValue)
      : super(type, name, finalValue);

  @override
  ASTVariable resolveVariable(VMContext context) {
    var variable = context.getField(name);
    if (variable == null) {
      throw StateError("Can't find Class field: $name");
    }
    return variable;
  }
}

class ASTRuntimeVariable<T> extends ASTTypedVariable<T> {
  ASTValue _value;

  ASTRuntimeVariable(ASTType<T> type, String name, [ASTValue? value])
      : _value = value ?? ASTValueNull.INSTANCE,
        super(type, name, false);

  @override
  ASTVariable resolveVariable(VMContext context) {
    return this;
  }

  @override
  ASTValue getValue(VMContext context) {
    return _value;
  }

  @override
  void setValue(VMContext context, ASTValue value) {
    _value = value;
  }
}

class ASTScopeVariable<T> extends ASTVariable {
  ASTScopeVariable(String name) : super(name);

  @override
  ASTVariable resolveVariable(VMContext context) {
    var variable = context.getVariable(name, true);
    if (variable == null) {
      throw StateError("Can't find variable: $name");
    }
    return variable;
  }
}

class ASTThisVariable<T> extends ASTVariable {
  ASTThisVariable() : super('this');

  @override
  ASTVariable resolveVariable(VMContext context) {
    var astObjectInstance = context.getASTObjectInstance();
    if (astObjectInstance == null) {
      throw StateError("Can't determine 'this'! No ASTObjectInstance defined!");
    }
    return astObjectInstance;
  }
}

abstract class ASTValue<T> implements ASTNode {
  factory ASTValue.from(ASTType<T> type, T value) {
    if (type is ASTTypeString) {
      return ASTValueString(value as String) as ASTValue<T>;
    } else if (type is ASTTypeInt) {
      return ASTValueInt(value as int) as ASTValue<T>;
    } else if (type is ASTTypeDouble) {
      return ASTValueDouble(value as double) as ASTValue<T>;
    } else if (type is ASTTypeNull) {
      return ASTValueNull.INSTANCE as ASTValue<T>;
    } else if (type is ASTTypeObject) {
      return ASTValueObject(value!) as ASTValue<T>;
    } else if (type is ASTTypeVoid) {
      return ASTValueVoid.INSTANCE as ASTValue<T>;
    } else if (type is ASTTypeArray3D) {
      return ASTValueArray3D(type, value as dynamic) as ASTValue<T>;
    } else if (type is ASTTypeArray2D) {
      return ASTValueArray2D(type, value as dynamic) as ASTValue<T>;
    } else if (type is ASTTypeArray) {
      return ASTValueArray(type, value as dynamic) as ASTValue<T>;
    } else {
      return ASTValueStatic<T>(type, value);
    }
  }

  static ASTValue fromValue(dynamic o) {
    if (o == null) return ASTValueNull.INSTANCE;

    if (o is String) return ASTValueString(o);
    if (o is int) return ASTValueInt(o);
    if (o is double) return ASTValueDouble(o);

    var t = ASTType.from(o);
    return ASTValueStatic(t, o);
  }

  ASTType<T> type;

  T getValue(VMContext context);

  ASTValue<T> resolve(VMContext context);

  ASTValue(this.type);

  V readIndex<V>(VMContext context, int index) {
    throw UnsupportedError("Can't read index for type: $type");
  }

  V readKey<V>(VMContext context, Object key) {
    throw UnsupportedError("Can't read key for type: $type");
  }

  ASTValue operator +(ASTValue other) =>
      throw UnsupportedValueOperationError('+');

  ASTValue operator -(ASTValue other) =>
      throw UnsupportedValueOperationError('+');

  ASTValue operator /(ASTValue other) =>
      throw UnsupportedValueOperationError('+');

  ASTValue operator *(ASTValue other) =>
      throw UnsupportedValueOperationError('+');

  ASTValue operator ~/(ASTValue other) =>
      throw UnsupportedValueOperationError('+');
}

class ASTValueStatic<T> extends ASTValue<T> {
  T value;

  ASTValueStatic(ASTType<T> type, this.value) : super(type);

  @override
  T getValue(VMContext context) => value;

  @override
  ASTValue<T> resolve(VMContext context) {
    return this;
  }

  @override
  V readIndex<V>(VMContext context, int index) {
    if (value is List) {
      var list = value as List;
      return list[index] as V;
    } else if (value is Iterable) {
      var it = value as Iterable;

      var idx = 0;
      for (var e in it) {
        if (idx == index) {
          return e;
        }
        idx++;
      }

      throw RangeError.index(index, it);
    }

    throw UnsupportedError("Can't read index for type: $type > $value");
  }

  @override
  V readKey<V>(VMContext context, Object key) {
    if (value is Map) {
      var map = value as Map;
      return map[key];
    }

    throw UnsupportedError("Can't read key for type: $type > $value");
  }
}

abstract class ASTValueNum<T extends num> extends ASTValueStatic<T> {
  ASTValueNum(ASTType<T> type, T value) : super(type, value);

  static ASTValueNum from(dynamic o) {
    if (o is int) return ASTValueInt(o);
    if (o is double) return ASTValueDouble(o);
    if (o is String) return from(parseNum(o.trim()));
    throw StateError("Can't parse number: $o");
  }

  @override
  ASTValue operator +(ASTValue other);

  @override
  ASTValue operator -(ASTValue other);

  @override
  ASTValue operator /(ASTValue other);

  @override
  ASTValue operator *(ASTValue other);
}

class ASTValueInt extends ASTValueNum<int> {
  ASTValueInt(int n) : super(ASTTypeInt.INSTANCE, n);

  @override
  ASTValue operator +(ASTValue other) {
    if (other is ASTValueInt) {
      return ASTValueInt(value + other.value);
    } else if (other is ASTValueDouble) {
      return ASTValueDouble(value + other.value);
    } else if (other is ASTValueString) {
      return ASTValueString('$value' + other.value);
    } else {
      throw UnsupportedValueOperationError(
          "Can't do '+' operation with: $other");
    }
  }

  @override
  ASTValue operator -(ASTValue other) {
    if (other is ASTValueInt) {
      return ASTValueInt(value - other.value);
    } else if (other is ASTValueDouble) {
      return ASTValueDouble(value - other.value);
    } else {
      throw UnsupportedValueOperationError(
          "Can't do '-' operation with: $other");
    }
  }

  @override
  ASTValue operator /(ASTValue other) {
    if (other is ASTValueInt) {
      return ASTValueDouble(value / other.value);
    } else if (other is ASTValueDouble) {
      return ASTValueDouble(value / other.value);
    } else {
      throw UnsupportedValueOperationError(
          "Can't do '/' operation with: $other");
    }
  }

  @override
  ASTValue operator *(ASTValue other) {
    if (other is ASTValueInt) {
      return ASTValueInt(value * other.value);
    } else if (other is ASTValueDouble) {
      return ASTValueDouble(value * other.value);
    } else {
      throw UnsupportedValueOperationError(
          "Can't do '*' operation with: $other");
    }
  }
}

class ASTValueDouble extends ASTValueNum<double> {
  ASTValueDouble(double n) : super(ASTTypeDouble.INSTANCE, n);

  @override
  ASTValue operator +(ASTValue other) {
    if (other is ASTValueInt) {
      return ASTValueDouble(value + other.value);
    } else if (other is ASTValueDouble) {
      return ASTValueDouble(value + other.value);
    } else if (other is ASTValueString) {
      return ASTValueString('$value' + other.value);
    } else {
      throw UnsupportedValueOperationError(
          "Can't do '+' operation with: $other");
    }
  }

  @override
  ASTValueDouble operator -(ASTValue other) {
    if (other is ASTValueInt) {
      return ASTValueDouble(value - other.value);
    } else if (other is ASTValueDouble) {
      return ASTValueDouble(value - other.value);
    } else {
      throw UnsupportedValueOperationError(
          "Can't do '-' operation with: $other");
    }
  }

  @override
  ASTValueDouble operator /(ASTValue other) {
    if (other is ASTValueInt) {
      return ASTValueDouble(value / other.value);
    } else if (other is ASTValueDouble) {
      return ASTValueDouble(value / other.value);
    } else {
      throw UnsupportedValueOperationError(
          "Can't do '/' operation with: $other");
    }
  }

  @override
  ASTValueDouble operator *(ASTValue other) {
    if (other is ASTValueInt) {
      return ASTValueDouble(value * other.value);
    } else if (other is ASTValueDouble) {
      return ASTValueDouble(value * other.value);
    } else {
      throw UnsupportedValueOperationError(
          "Can't do '*' operation with: $other");
    }
  }
}

class ASTValueString extends ASTValueStatic<String> {
  ASTValueString(String s) : super(ASTTypeString.INSTANCE, s);
}

class ASTValueObject extends ASTValueStatic<Object> {
  ASTValueObject(Object o) : super(ASTTypeObject.INSTANCE, o);
}

class ASTValueNull extends ASTValueStatic<Null> {
  ASTValueNull() : super(ASTTypeNull.INSTANCE, null);

  static final ASTValueNull INSTANCE = ASTValueNull();
}

class ASTValueVoid extends ASTValueStatic<void> {
  ASTValueVoid() : super(ASTTypeVoid.INSTANCE, null);

  static final ASTValueVoid INSTANCE = ASTValueVoid();
}

class ASTValueArray<T extends ASTType<V>, V> extends ASTValueStatic<List<V>> {
  ASTValueArray(T type, List<V> value) : super(ASTTypeArray<T, V>(type), value);
}

class ASTValueArray2D<T extends ASTType<V>, V>
    extends ASTValueArray<ASTTypeArray<T, V>, List<V>> {
  ASTValueArray2D(T type, List<List<V>> value)
      : super(ASTTypeArray<T, V>(type), value);
}

class ASTValueArray3D<T extends ASTType<V>, V>
    extends ASTValueArray2D<ASTTypeArray<T, V>, List<V>> {
  ASTValueArray3D(T type, List<List<List<V>>> value)
      : super(ASTTypeArray<T, V>(type), value);
}

class ASTValueVar extends ASTValueStatic<dynamic> {
  ASTValueVar(Object o) : super(ASTTypeVar.INSTANCE, o);
}

class ASTType<V> implements ASTNode {
  static ASTType from(dynamic o) {
    if (o == null) return ASTTypeNull.INSTANCE;

    if (o is ASTType) {
      return o;
    }

    if (o is ASTValue) {
      return o.type;
    }

    if (o is ASTTypedVariable) {
      return o.type;
    }

    if (o is String) return ASTTypeString.INSTANCE;
    if (o is int) return ASTTypeInt.INSTANCE;
    if (o is double) return ASTTypeDouble.INSTANCE;

    if (o is List) {
      if (o is List<String>) return ASTTypeArray(ASTTypeString.INSTANCE);
      if (o is List<int>) return ASTTypeArray(ASTTypeInt.INSTANCE);
      if (o is List<double>) return ASTTypeArray(ASTTypeDouble.INSTANCE);
      if (o is List<Object>) return ASTTypeArray(ASTTypeObject.INSTANCE);
      if (o is List<dynamic>) return ASTTypeArray(ASTTypeDynamic.INSTANCE);

      if (o is List<List<String>>) {
        return ASTTypeArray2D<ASTTypeString, String>.fromElementType(
            ASTTypeString.INSTANCE);
      }
      if (o is List<List<int>>)
        // ignore: curly_braces_in_flow_control_structures
        return ASTTypeArray2D<ASTTypeInt, int>.fromElementType(
            ASTTypeInt.INSTANCE);
      if (o is List<List<double>>)
        // ignore: curly_braces_in_flow_control_structures
        return ASTTypeArray2D<ASTTypeDouble, double>.fromElementType(
            ASTTypeDouble.INSTANCE);
      if (o is List<List<Object>>) {
        return ASTTypeArray2D<ASTTypeObject, Object>.fromElementType(
            ASTTypeObject.INSTANCE);
      }
      if (o is List<List<dynamic>>) {
        return ASTTypeArray2D<ASTTypeDynamic, dynamic>.fromElementType(
            ASTTypeDynamic.INSTANCE);
      }

      if (o is List<List<List<String>>>) {
        return ASTTypeArray3D<ASTTypeString, String>.fromElementType(
            ASTTypeString.INSTANCE);
      }
      if (o is List<List<List<int>>>) {
        return ASTTypeArray3D<ASTTypeInt, int>.fromElementType(
            ASTTypeInt.INSTANCE);
      }
      if (o is List<List<List<double>>>) {
        return ASTTypeArray3D<ASTTypeDouble, double>.fromElementType(
            ASTTypeDouble.INSTANCE);
      }
      if (o is List<List<List<Object>>>) {
        return ASTTypeArray3D<ASTTypeObject, Object>.fromElementType(
            ASTTypeObject.INSTANCE);
      }
      if (o is List<List<List<dynamic>>>) {
        return ASTTypeArray3D<ASTTypeDynamic, dynamic>.fromElementType(
            ASTTypeDynamic.INSTANCE);
      }

      var t = ASTType.from(o.genericType);
      return ASTTypeArray(t);
    }

    if (o.runtimeType == Object) return ASTTypeObject.INSTANCE;

    return ASTTypeDynamic.INSTANCE;
  }

  final String name;

  List<ASTType>? generics;

  ASTType? superType;

  List<ASTAnnotation>? annotations;

  ASTType(this.name, {this.generics, this.superType, this.annotations});

  /// Will return true if [type] can be cast to [this] type.
  /// Note: This is similar to Java `isInstance` and `isAssignableFrom`.
  bool isInstance(ASTType type) {
    if (type == this) return true;

    if (type == ASTTypeGenericWildcard.INSTANCE) return true;

    if (type.name != type.name) {
      var typeSuperType = type.superType;
      if (typeSuperType == null) return false;

      if (!typeSuperType.isInstance(this)) return false;
    }

    var generics = this.generics;
    var typeGenerics = type.generics;

    if (generics == null || generics.isEmpty) {
      return typeGenerics == null || typeGenerics.isEmpty;
    }

    if (typeGenerics == null || typeGenerics.isEmpty) {
      return false;
    }

    if (generics.length != typeGenerics.length) return false;

    var genericsLength = generics.length;

    for (var i = 0; i < genericsLength; ++i) {
      var g = generics[i];
      var tg = typeGenerics[i];

      if (!g.isInstance(tg)) {
        return false;
      }
    }

    return true;
  }

  ASTValue<V>? toValue(VMContext context, Object? v) {
    if (v is ASTValue<V>) return v;

    if (v is ASTValue) {
      v = (v).getValue(context);
    }

    var t = v as V;
    return ASTValue.from(this, t);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ASTType &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          generics == other.generics &&
          superType == other.superType;

  @override
  int get hashCode {
    return name.hashCode ^
        (superType?.hashCode ?? 0) ^
        (generics?.hashCode ?? 0);
  }

  @override
  String toString() {
    return generics == null ? name : '$name<${generics!.join(',')}>';
  }
}

class ASTTypeInterface<V> extends ASTType<V> {
  ASTTypeInterface(String name,
      {List<ASTType>? generics,
      ASTType? superInterface,
      List<ASTAnnotation>? annotations})
      : super(name,
            generics: generics,
            superType: superInterface,
            annotations: annotations);
}

abstract class ASTTypePrimitive<T> extends ASTType<T> {
  ASTTypePrimitive(String name) : super(name);

  @override
  bool isInstance(ASTType type);
}

abstract class ASTTypeNum<T extends num> extends ASTTypePrimitive<T> {
  ASTTypeNum(String name) : super(name);
}

class ASTTypeInt extends ASTTypeNum<int> {
  static final ASTTypeInt INSTANCE = ASTTypeInt();

  ASTTypeInt() : super('int');

  @override
  bool isInstance(ASTType type) {
    if (type == this) return true;
    return false;
  }

  @override
  ASTValueInt? toValue(VMContext context, Object? v) {
    if (v is ASTValueInt) return v;

    if (v is ASTValue) {
      v = (v).getValue(context);
    }

    var n = parseInt(v);
    return n != null ? ASTValueInt(n) : null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other && other is ASTTypeInt && runtimeType == other.runtimeType;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() {
    return 'int';
  }
}

class ASTTypeDouble extends ASTType<double> {
  static final ASTTypeDouble INSTANCE = ASTTypeDouble();

  ASTTypeDouble() : super('double');

  @override
  bool isInstance(ASTType type) {
    if (type == this) return true;
    return false;
  }

  @override
  ASTValueDouble? toValue(VMContext context, Object? v) {
    if (v is ASTValueDouble) return v;

    if (v is ASTValue) {
      v = (v).getValue(context);
    }

    var n = parseDouble(v);
    return n != null ? ASTValueDouble(n) : null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other && other is ASTTypeInt && runtimeType == other.runtimeType;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() {
    return 'double';
  }
}

class ASTTypeString extends ASTTypePrimitive<String> {
  static final ASTTypeString INSTANCE = ASTTypeString();

  ASTTypeString() : super('String');

  @override
  bool isInstance(ASTType type) {
    if (type == this) return true;
    return false;
  }

  @override
  ASTValueString? toValue(VMContext context, Object? v) {
    if (v is ASTValueString) return v;

    if (v is ASTValue) {
      v = (v).getValue(context);
    }

    var n = parseString(v);
    return n != null ? ASTValueString(n) : null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other && other is ASTTypeInt && runtimeType == other.runtimeType;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() {
    return 'String';
  }
}

class ASTTypeObject extends ASTType<Object> {
  static final ASTTypeObject INSTANCE = ASTTypeObject();

  ASTTypeObject() : super('Object');

  @override
  bool isInstance(ASTType type) => true;

  @override
  ASTValueObject? toValue(VMContext context, Object? v) {
    if (v is ASTValueObject) return v;

    if (v is ASTValue) {
      v = (v).getValue(context);
    }

    return v != null ? ASTValueObject(v) : null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other && other is ASTTypeInt && runtimeType == other.runtimeType;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() {
    return 'Object';
  }
}

class ASTTypeVar extends ASTType<dynamic> {
  static final ASTTypeVar INSTANCE = ASTTypeVar();

  ASTTypeVar() : super('var');

  @override
  bool isInstance(ASTType type) => true;

  @override
  ASTValue<dynamic> toValue(VMContext context, Object? v) {
    if (v is ASTValue<dynamic> && v.type == this) return v;

    if (v is ASTValue) {
      v = (v).getValue(context);
    }

    return ASTValueStatic<dynamic>(this, v);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other && other is ASTTypeInt && runtimeType == other.runtimeType;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() {
    return 'var';
  }
}

class ASTTypeDynamic extends ASTType<dynamic> {
  static final ASTTypeDynamic INSTANCE = ASTTypeDynamic();

  ASTTypeDynamic() : super('dynamic');

  @override
  bool isInstance(ASTType type) => true;

  @override
  ASTValue<dynamic> toValue(VMContext context, Object? v) {
    if (v is ASTValue<dynamic> && v.type == this) return v;

    if (v is ASTValue) {
      v = (v).getValue(context);
    }

    return ASTValue.from(this, v);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other && other is ASTTypeInt && runtimeType == other.runtimeType;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() {
    return 'dynamic';
  }
}

class ASTTypeNull extends ASTType<Null> {
  static final ASTTypeNull INSTANCE = ASTTypeNull();

  ASTTypeNull() : super('Null');

  @override
  bool isInstance(ASTType type) {
    if (type == this) return true;
    return false;
  }

  @override
  ASTValueNull toValue(VMContext context, Object? v) {
    if (v is ASTValueNull) return v;
    return ASTValueNull.INSTANCE;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other && other is ASTTypeInt && runtimeType == other.runtimeType;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() {
    return 'Null';
  }
}

class ASTTypeVoid extends ASTType<void> {
  static final ASTTypeVoid INSTANCE = ASTTypeVoid();

  ASTTypeVoid() : super('void');

  @override
  bool isInstance(ASTType type) {
    if (type == this) return true;
    return false;
  }

  @override
  ASTValueVoid toValue(VMContext context, Object? v) {
    return ASTValueVoid.INSTANCE;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other && other is ASTTypeInt && runtimeType == other.runtimeType;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() {
    return 'void';
  }
}

class ASTTypeGenericVariable extends ASTType<Object> {
  String variableName;

  ASTType? type;

  ASTTypeGenericVariable(this.variableName, [this.type]) : super(variableName);

  ASTType<Object> get resolveType =>
      (type as ASTType<Object>?) ?? ASTTypeObject.INSTANCE;

  @override
  ASTValue<Object>? toValue(VMContext context, Object? v) {
    return resolveType.toValue(context, v);
  }
}

class ASTTypeGenericWildcard extends ASTTypeGenericVariable {
  static final ASTTypeGenericWildcard INSTANCE = ASTTypeGenericWildcard();

  ASTTypeGenericWildcard() : super('?');
}

class ASTTypeArray<T extends ASTType<V>, V> extends ASTType<List<V>> {
  T componentType;

  ASTType get elementType => componentType;

  ASTTypeArray(this.componentType) : super('List') {
    generics = [componentType];
  }

  @override
  ASTValueArray<T, V>? toValue(VMContext context, Object? v) {
    if (v == null) return null;
    if (v is ASTValueArray) return v as ASTValueArray<T, V>;

    if (v is ASTValue) {
      v = (v).getValue(context);
    }

    List list;
    if (v is List) {
      list = v;
    } else {
      list = [v];
    }

    var list2 = list.whereType<V>().toList();

    var value = ASTValueArray<T, V>(componentType, list2);
    return value;
  }
}

class ASTTypeArray2D<T extends ASTType<V>, V>
    extends ASTTypeArray<ASTTypeArray<T, V>, List<V>> {
  ASTTypeArray2D(ASTTypeArray<T, V> type) : super(type);

  factory ASTTypeArray2D.fromElementType(ASTType<V> elementType) {
    var a1 = ASTTypeArray<T, V>(elementType as T);
    return ASTTypeArray2D<T, V>(a1);
  }

  @override
  ASTType get elementType => componentType.elementType;

  @override
  ASTValueArray2D<T, V>? toValue(VMContext context, Object? v) {
    if (v == null) return null;
    if (v is ASTValueArray2D) return v as ASTValueArray2D<T, V>;

    if (v is ASTValue) {
      v = (v).getValue(context);
    }

    List list;
    if (v is List) {
      list = v;
    } else {
      list = [v];
    }

    var list2 = list.whereType<List<V>>().toList();

    var value = ASTValueArray2D<T, V>(elementType as T, list2);
    return value;
  }
}

class ASTTypeArray3D<T extends ASTType<V>, V>
    extends ASTTypeArray2D<ASTTypeArray<T, V>, List<V>> {
  ASTTypeArray3D(ASTTypeArray2D<T, V> type) : super(type);

  factory ASTTypeArray3D.fromElementType(ASTType<V> elementType) {
    var a1 = ASTTypeArray<T, V>(elementType as T);
    var a2 = ASTTypeArray2D<T, V>(a1);
    return ASTTypeArray3D(a2);
  }

  @override
  ASTType get elementType => componentType.elementType;

  @override
  ASTValueArray3D<T, V>? toValue(VMContext context, Object? v) {
    if (v == null) return null;
    if (v is ASTValueArray2D) return v as ASTValueArray3D<T, V>;

    if (v is ASTValue) {
      v = (v).getValue(context);
    }

    List list;
    if (v is List) {
      list = v;
    } else {
      list = [v];
    }

    var list2 = list.whereType<List<List<V>>>().toList();

    var value = ASTValueArray3D<T, V>(elementType as T, list2);
    return value;
  }
}

class ASTAnnotation implements ASTNode {
  String name;

  Map<String, ASTAnnotationParameter>? parameters;

  ASTAnnotation(this.name, [this.parameters]);
}

class ASTAnnotationParameter implements ASTNode {
  String name;

  String value;

  bool defaultParameter;

  ASTAnnotationParameter(this.name, this.value,
      [this.defaultParameter = false]);
}

class ASTValueAsString<T> extends ASTValue<String> {
  ASTValue<T> value;

  ASTValueAsString(this.value) : super(ASTTypeString.INSTANCE);

  @override
  String getValue(VMContext context) {
    var v = value.getValue(context);
    return '$v';
  }

  @override
  ASTValue<String> resolve(VMContext context) {
    return ASTValueString(getValue(context));
  }
}

class ASTValuesListAsString extends ASTValue<String> {
  List<ASTValue> values;

  ASTValuesListAsString(this.values) : super(ASTTypeString.INSTANCE);

  @override
  String getValue(VMContext context) {
    return values.map((e) {
      var v = e.resolve(context).getValue(context);
      return '$v';
    }).join();
  }

  @override
  ASTValue<String> resolve(VMContext context) {
    return ASTValueString(getValue(context));
  }
}

class ASTValueStringExpresion<T> extends ASTValue<String> {
  final ASTExpression expression;

  ASTValueStringExpresion(this.expression) : super(ASTTypeString.INSTANCE);

  @override
  String getValue(VMContext context) {
    var res = expression.run(context, ASTRunStatus()).getValue(context);
    return '$res';
  }

  @override
  ASTValue<String> resolve(VMContext context) {
    var s = getValue(context);
    return ASTValueString(s);
  }
}

class ASTValueStringVariable<T> extends ASTValue<String> {
  final ASTVariable variable;

  ASTValueStringVariable(this.variable) : super(ASTTypeString.INSTANCE);

  @override
  String getValue(VMContext context) {
    var v = variable.getValue(context).getValue(context);
    return '$v';
  }

  @override
  ASTValue<String> resolve(VMContext context) {
    var value = variable.getValue(context);
    return value is ASTValue<String> ? value : ASTValueAsString(value);
  }
}

class ASTValueStringConcatenation extends ASTValue<String> {
  final List<ASTValue<String>> values;

  ASTValueStringConcatenation(this.values) : super(ASTTypeString.INSTANCE);

  @override
  String getValue(VMContext context) {
    var vs = values.map((e) => e.getValue(context)).toList();
    return vs.join();
  }

  @override
  ASTValue<String> resolve(VMContext context) {
    var vs = values.map((e) => e.resolve(context)).toList();
    return ASTValuesListAsString(vs);
  }
}

class ASTValueReadIndex<T> extends ASTValue<T> {
  final ASTVariable variable;
  final Object _index;

  ASTValueReadIndex(ASTType<T> type, this.variable, this._index) : super(type);

  int getIndex(VMContext context) {
    if (_index is int) {
      return _index as int;
    } else if (_index is ASTValue) {
      var idx = (_index as ASTValue).getValue(context);
      return parseInt(idx)!;
    } else {
      return parseInt(_index)!;
    }
  }

  @override
  T getValue(VMContext context) =>
      variable.readIndex(context, getIndex(context));

  @override
  ASTValue<T> resolve(VMContext context) {
    var v = getValue(context);
    return ASTValue.from(type, v);
  }
}

class ASTValueReadKey<T> extends ASTValue<T> {
  final ASTVariable variable;
  final Object _key;

  ASTValueReadKey(ASTType<T> type, this.variable, this._key) : super(type);

  Object getKey(VMContext context) {
    if (_key is ASTValue) {
      return (_key as ASTValue).getValue(context);
    } else {
      return _key;
    }
  }

  @override
  T getValue(VMContext context) => variable.readKey(context, getKey(context));

  @override
  ASTValue<T> resolve(VMContext context) {
    var v = getValue(context);
    return ASTValue.from(type, v);
  }
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

enum ASTAssignmentOperator { set, multiply, divide, sum, subtract }

ASTAssignmentOperator getASTAssignmentOperator(String op) {
  op = op.trim();

  switch (op) {
    case '=':
      return ASTAssignmentOperator.set;
    case '*=':
      return ASTAssignmentOperator.multiply;
    case '/=':
      return ASTAssignmentOperator.divide;
    case '+=':
      return ASTAssignmentOperator.sum;
    case '-=':
      return ASTAssignmentOperator.subtract;
    default:
      throw UnsupportedError('$op');
  }
}

String getASTAssignmentOperatorText(ASTAssignmentOperator op) {
  switch (op) {
    case ASTAssignmentOperator.set:
      return '=';
    case ASTAssignmentOperator.multiply:
      return '*=';
    case ASTAssignmentOperator.divide:
      return '/=';
    case ASTAssignmentOperator.sum:
      return '+=';
    case ASTAssignmentOperator.subtract:
      return '-=';
    default:
      throw UnsupportedError('$op');
  }
}

class ASTStatementExpression extends ASTStatement {
  ASTExpression expression;

  ASTStatementExpression(this.expression);

  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    var context = defineRunContext(parentContext);
    return expression.run(context, runStatus);
  }
}

class ASTStatementReturn extends ASTStatement {
  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    return runStatus.returnVoid();
  }
}

class ASTStatementReturnNull extends ASTStatementReturn {
  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    return runStatus.returnNull();
  }
}

class ASTStatementReturnValue extends ASTStatementReturn {
  ASTValue value;

  ASTStatementReturnValue(this.value);

  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    return runStatus.returnValue(value);
  }
}

class ASTStatementReturnVariable extends ASTStatementReturn {
  ASTVariable variable;

  ASTStatementReturnVariable(this.variable);

  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    var value = variable.getValue(parentContext);
    return runStatus.returnValue(value);
  }
}

class ASTStatementReturnWithExpression extends ASTStatementReturn {
  ASTExpression expression;

  ASTStatementReturnWithExpression(this.expression);

  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    var value = expression.run(parentContext, runStatus);
    return runStatus.returnValue(value);
  }
}

abstract class ASTExpression implements ASTCodeRunner, ASTNode {
  @override
  VMContext defineRunContext(VMContext parentContext) {
    return parentContext;
  }
}

class ASTExpressionVariableAccess extends ASTExpression {
  ASTVariable variable;

  ASTExpressionVariableAccess(this.variable);

  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    var context = defineRunContext(parentContext);
    return variable.getValue(context);
  }
}

class ASTExpressionLiteral extends ASTExpression {
  ASTValue value;

  ASTExpressionLiteral(this.value);

  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    return value.resolve(parentContext);
  }
}

class ASTExpressionVariableEntryAccess extends ASTExpression {
  ASTVariable variable;
  ASTExpression expression;

  ASTExpressionVariableEntryAccess(this.variable, this.expression);

  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    var context = defineRunContext(parentContext);

    var key = expression.run(context, runStatus);
    var value = variable.getValue(context);

    var readValue;
    if (key is ASTValueNum) {
      var idx = key.getValue(context).toInt();
      readValue = value.readIndex(context, idx);
    } else {
      var k = key.getValue(context);
      readValue = value.readKey(context, k);
    }

    var readType = ASTType.from(readValue);
    return ASTValue.from(readType, readValue);
  }
}

enum ASTExpressionOperator {
  add,
  subtract,
  multiply,
  divide,
  divideAsInt,
  divideAsDouble
}

ASTExpressionOperator getASTExpressionOperator(String op) {
  op = op.trim();
  switch (op) {
    case '+':
      return ASTExpressionOperator.add;
    case '-':
      return ASTExpressionOperator.subtract;
    case '*':
      return ASTExpressionOperator.multiply;
    case '/':
      return ASTExpressionOperator.divide;
    case '~/':
      return ASTExpressionOperator.divideAsInt;
    default:
      throw UnsupportedError('$op');
  }
}

String getASTExpressionOperatorText(ASTExpressionOperator op) {
  switch (op) {
    case ASTExpressionOperator.add:
      return '+';
    case ASTExpressionOperator.subtract:
      return '-';
    case ASTExpressionOperator.multiply:
      return '*';
    case ASTExpressionOperator.divide:
    case ASTExpressionOperator.divideAsDouble:
      return '/';
    case ASTExpressionOperator.divideAsInt:
      return '~/';
    default:
      throw UnsupportedError('$op');
  }
}

class ASTExpressionOperation extends ASTExpression {
  ASTExpression expression1;
  ASTExpressionOperator operator;
  ASTExpression expression2;

  ASTExpressionOperation(this.expression1, this.operator, this.expression2);

  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    var context = defineRunContext(parentContext);

    var val2 = expression2.run(context, runStatus);
    var val1 = expression1.run(context, runStatus);

    switch (operator) {
      case ASTExpressionOperator.add:
        return operatorAdd(parentContext, val1, val2);
      case ASTExpressionOperator.subtract:
        return operatorSubtract(parentContext, val1, val2);
      case ASTExpressionOperator.multiply:
        return operatorMultiply(parentContext, val1, val2);
      case ASTExpressionOperator.divide:
        return operatorDivide(parentContext, val1, val2);
      case ASTExpressionOperator.divideAsInt:
        return operatorDivideAsInt(parentContext, val1, val2);
      case ASTExpressionOperator.divideAsDouble:
        return operatorDivideAsDouble(parentContext, val1, val2);
    }
  }

  ASTValue operatorAdd(VMContext context, ASTValue val1, ASTValue val2) {
    var t1 = val1.type;
    var t2 = val2.type;

    if (t1 is ASTTypeString || t2 is ASTTypeString) {
      var v1 = val1.getValue(context);
      var v2 = val2.getValue(context);
      var r = '$v1$v2';
      return ASTValueString(r);
    }

    if (t1 is ASTTypeInt) {
      if (t2 is ASTTypeInt) {
        var v1 = val1.getValue(context) as int;
        var v2 = val2.getValue(context) as int;
        var r = v1 + v2;
        return ASTValueInt(r);
      } else if (t2 is ASTTypeDouble) {
        var v1 = val1.getValue(context) as int;
        var v2 = val2.getValue(context) as double;
        var r = v1 + v2;
        return ASTValueDouble(r);
      }
    }

    if (t1 is ASTTypeDouble) {
      if (t2 is ASTTypeInt || t2 is ASTTypeDouble) {
        var v1 = val1.getValue(context) as double;
        var v2 = val2.getValue(context) as num;
        var r = v1 + v2;
        return ASTValueDouble(r);
      }
    }

    throw UnsupportedError("Can't perform '+' operation in types: $t1 + $t2");
  }

  ASTValue operatorSubtract(VMContext context, ASTValue val1, ASTValue val2) {
    var t1 = val1.type;
    var t2 = val2.type;

    if (t1 is ASTTypeInt) {
      if (t2 is ASTTypeInt) {
        var v1 = val1.getValue(context) as int;
        var v2 = val2.getValue(context) as int;
        var r = v1 - v2;
        return ASTValueInt(r);
      } else if (t2 is ASTTypeDouble) {
        var v1 = val1.getValue(context) as int;
        var v2 = val2.getValue(context) as double;
        var r = v1 - v2;
        return ASTValueDouble(r);
      }
    }

    if (t1 is ASTTypeDouble) {
      if (t2 is ASTTypeInt || t2 is ASTTypeDouble) {
        var v1 = val1.getValue(context) as double;
        var v2 = val2.getValue(context) as num;
        var r = v1 - v2;
        return ASTValueDouble(r);
      }
    }

    throw UnsupportedError("Can't perform '-' operation in types: $t1 - $t2");
  }

  ASTValue operatorMultiply(VMContext context, ASTValue val1, ASTValue val2) {
    var t1 = val1.type;
    var t2 = val2.type;

    if (t1 is ASTTypeInt) {
      if (t2 is ASTTypeInt) {
        var v1 = val1.getValue(context) as int;
        var v2 = val2.getValue(context) as int;
        var r = v1 * v2;
        return ASTValueInt(r);
      } else if (t2 is ASTTypeDouble) {
        var v1 = val1.getValue(context) as int;
        var v2 = val2.getValue(context) as double;
        var r = v1 * v2;
        return ASTValueDouble(r);
      }
    }

    if (t1 is ASTTypeDouble) {
      if (t2 is ASTTypeInt || t2 is ASTTypeDouble) {
        var v1 = val1.getValue(context) as double;
        var v2 = val2.getValue(context) as num;
        var r = v1 * v2;
        return ASTValueDouble(r);
      }
    }

    throw UnsupportedError("Can't perform '*' operation in types: $t1 * $t2");
  }

  ASTValue operatorDivide(VMContext context, ASTValue val1, ASTValue val2) {
    var t1 = val1.type;
    var t2 = val2.type;

    if (t1 is ASTTypeInt) {
      if (t2 is ASTTypeInt) {
        var v1 = val1.getValue(context) as int;
        var v2 = val2.getValue(context) as int;
        var r = v1 ~/ v2;
        return ASTValueInt(r);
      } else if (t2 is ASTTypeDouble) {
        var v1 = val1.getValue(context) as int;
        var v2 = val2.getValue(context) as double;
        var r = v1 / v2;
        return ASTValueDouble(r);
      }
    }

    if (t1 is ASTTypeDouble) {
      if (t2 is ASTTypeInt || t2 is ASTTypeDouble) {
        var v1 = val1.getValue(context) as double;
        var v2 = val2.getValue(context) as num;
        var r = v1 / v2;
        return ASTValueDouble(r);
      }
    }

    throw UnsupportedError("Can't perform '/' operation in types: $t1 / $t2");
  }

  ASTValue operatorDivideAsInt(
      VMContext context, ASTValue val1, ASTValue val2) {
    var t1 = val1.type;
    var t2 = val2.type;

    if (t1 is ASTTypeInt || t1 is ASTTypeDouble) {
      if (t2 is ASTTypeInt || t2 is ASTTypeDouble) {
        var v1 = val1.getValue(context) as double;
        var v2 = val2.getValue(context) as num;
        var r = v1 / v2;
        return ASTValueInt(r.toInt());
      }
    }

    throw UnsupportedError("Can't perform '/' operation in types: $t1 / $t2");
  }

  ASTValue operatorDivideAsDouble(
      VMContext context, ASTValue val1, ASTValue val2) {
    var t1 = val1.type;
    var t2 = val2.type;

    if (t1 is ASTTypeInt || t1 is ASTTypeDouble) {
      if (t2 is ASTTypeInt || t2 is ASTTypeDouble) {
        var v1 = val1.getValue(context) as double;
        var v2 = val2.getValue(context) as num;
        var r = v1 / v2;
        return ASTValueDouble(r);
      }
    }

    throw UnsupportedError("Can't perform '/' operation in types: $t1 / $t2");
  }
}

class ASTExpressionVariableAssignment extends ASTExpression {
  ASTVariable variable;

  ASTAssignmentOperator operator;

  ASTExpression expression;

  ASTExpressionVariableAssignment(
      this.variable, this.operator, this.expression);

  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    var context = defineRunContext(parentContext);

    var value = expression.run(context, runStatus);
    var variableValue = variable.getValue(context);

    switch (operator) {
      case ASTAssignmentOperator.set:
        {
          variable.setValue(context, value);
          return value;
        }
      case ASTAssignmentOperator.sum:
        {
          var res = variableValue + value;
          variable.setValue(context, res);
          return value;
        }
      case ASTAssignmentOperator.subtract:
        {
          var res = variableValue - value;
          variable.setValue(context, res);
          return value;
        }
      case ASTAssignmentOperator.divide:
        {
          var res = variableValue / value;
          variable.setValue(context, res);
          return value;
        }
      case ASTAssignmentOperator.multiply:
        {
          var res = variableValue * value;
          variable.setValue(context, res);
          return value;
        }
      default:
        throw UnsupportedError('operator: $operator');
    }
  }
}

class ASTExpressionLocalFunctionInvocation extends ASTExpression {
  String name;
  List<ASTExpression> arguments;

  ASTExpressionLocalFunctionInvocation(this.name, this.arguments);

  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    var fSignature = ASTFunctionSignature.from(arguments, null);
    var f = parentContext.block.getFunction(name, fSignature, parentContext);
    if (f == null) {
      throw StateError(
          'Can\'t find function "$name" with parameters signature: $fSignature');
    }

    var argumentsValues = arguments.map((e) {
      return e.run(parentContext, runStatus);
    }).toList();

    return f.call(parentContext, positionalParameters: argumentsValues);
  }
}

class ASTExpressionObjectFunctionInvocation extends ASTExpression {
  ASTVariable variable;
  String name;
  List arguments;

  ASTExpressionObjectFunctionInvocation(
      this.variable, this.name, this.arguments);

  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    // TODO: implement run
    throw UnimplementedError();
  }
}

class ASTStatementVariableDeclaration<V> extends ASTStatement {
  ASTType<V> type;

  String name;

  ASTExpression? value;

  ASTStatementVariableDeclaration(this.type, this.name, this.value);

  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    var result = value?.run(parentContext, runStatus) ?? ASTValueNull.INSTANCE;
    parentContext.declareVariableWithValue(type, name, result);
    return ASTValueVoid.INSTANCE;
  }
}
