// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:collection';
import 'dart:math' as math;

import 'package:async_extension/async_extension.dart';
import 'package:collection/collection.dart'
    show IterableExtension, equalsIgnoreAsciiCase, CombinedListView;

import '../apollovm_base.dart';
import '../apollovm_utils.dart';
import '../core/apollovm_core_base.dart';
import 'apollovm_ast_base.dart';
import 'apollovm_ast_statement.dart';
import 'apollovm_ast_type.dart';
import 'apollovm_ast_value.dart';
import 'apollovm_ast_variable.dart';

/// An [ASTBlock] that can have an entry-point method/function.
class ASTEntryPointBlock extends ASTBlock {
  ASTEntryPointBlock(super.parentBlock);

  FutureOr<ASTValue> execute(
    String entryFunctionName,
    List? positionalParameters,
    Map? namedParameters, {
    ApolloImportManager? importManager,
    ApolloExternalFunctionMapper? externalFunctionMapper,
    VMObject? classInstanceObject,
    Map<String, ASTValue>? classInstanceFields,
    VMTypeResolver? typeResolver,
  }) async {
    var rootContext = await _initializeEntryPointBlock(
      importManager,
      externalFunctionMapper,
      typeResolver,
    );

    ApolloImportManager? prevImportManager;
    if (importManager != null) {
      prevImportManager = rootContext.importManager;
      rootContext.importManager = importManager;
    }

    ApolloExternalFunctionMapper? prevExternalFunctionMapper;
    if (externalFunctionMapper != null) {
      prevExternalFunctionMapper = rootContext.externalFunctionMapper;
      rootContext.externalFunctionMapper = externalFunctionMapper;
    }

    var prevContext = VMContext.setCurrent(rootContext);
    try {
      var fSignature = ASTFunctionSignature.from(
        positionalParameters,
        namedParameters,
      );

      var f = getFunction(
        entryFunctionName,
        fSignature,
        rootContext,
        caseInsensitive: true,
      );
      if (f == null) {
        throw ApolloVMRuntimeError(
          "Can't find entry function: $entryFunctionName",
        );
      }

      var context = rootContext;

      if (!f.modifiers.isStatic) {
        if (this is ASTClass) {
          var clazz = this as ASTClass;
          var classContext = clazz.createContext(typeResolver, rootContext);
          var obj = (await clazz.createInstance(
            classContext,
            ASTRunStatus.dummy,
          ))!;

          if (classInstanceObject != null) {
            await clazz.setInstanceByVMObject(
              classContext,
              ASTRunStatus.dummy,
              obj,
              classInstanceObject,
            );
          }

          if (classInstanceFields != null) {
            await clazz.setInstanceByMap(
              classContext,
              ASTRunStatus.dummy,
              obj,
              classInstanceFields,
            );
          }

          classContext.setClassInstance(obj);
          context = classContext;
        } else {
          throw ApolloVMRuntimeError(
            "Can't call non-static function without a class context: $this",
          );
        }
      }

      return await f.call(
        context,
        positionalParameters: positionalParameters,
        namedParameters: namedParameters,
      );
    } finally {
      VMContext.setCurrent(prevContext);

      if (identical(rootContext.importManager, importManager)) {
        rootContext.importManager = prevImportManager;
      }

      if (identical(
        rootContext.externalFunctionMapper,
        externalFunctionMapper,
      )) {
        rootContext.externalFunctionMapper = prevExternalFunctionMapper;
      }
    }
  }

  FutureOr<ASTInvocableDeclaration?> getFunctionWithParameters(
    String entryFunctionName,
    List? positionalParameters,
    Map? namedParameters, {
    ApolloImportManager? importManager,
    ApolloExternalFunctionMapper? externalFunctionMapper,
    VMTypeResolver? typeResolver,
  }) async {
    var rootContext = await _initializeEntryPointBlock(
      importManager,
      externalFunctionMapper,
      typeResolver,
    );

    ApolloImportManager? prevImportManager;
    if (importManager != null) {
      prevImportManager = rootContext.importManager;
      rootContext.importManager = importManager;
    }

    ApolloExternalFunctionMapper? prevExternalFunctionMapper;
    if (externalFunctionMapper != null) {
      prevExternalFunctionMapper = rootContext.externalFunctionMapper;
      rootContext.externalFunctionMapper = externalFunctionMapper;
    }

    var prevContext = VMContext.setCurrent(rootContext);
    try {
      var fSignature = ASTFunctionSignature.from(
        positionalParameters,
        namedParameters,
      );

      try {
        var f = getFunction(entryFunctionName, fSignature, rootContext);
        return f;
      } on Error {
        return null;
      }
    } finally {
      VMContext.setCurrent(prevContext);

      if (identical(rootContext.importManager, importManager)) {
        rootContext.importManager = prevImportManager;
      }

      if (identical(
        rootContext.externalFunctionMapper,
        externalFunctionMapper,
      )) {
        rootContext.externalFunctionMapper = prevExternalFunctionMapper;
      }
    }
  }

  VMContext? _rootContext;

  Future<VMContext> _initializeEntryPointBlock(
    ApolloImportManager? importManager,
    ApolloExternalFunctionMapper? externalFunctionMapper,
    VMTypeResolver? typeResolver,
  ) async {
    if (_rootContext == null) {
      var rootContext = createContext(typeResolver);
      var rootStatus = ASTRunStatus();
      _rootContext = rootContext;

      ApolloImportManager? prevImportManager;
      if (importManager != null) {
        prevImportManager = rootContext.importManager;
        rootContext.importManager = importManager;
      }

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

        if (identical(rootContext.importManager, importManager)) {
          rootContext.importManager = prevImportManager;
        }

        if (identical(
          rootContext.externalFunctionMapper,
          externalFunctionMapper,
        )) {
          rootContext.externalFunctionMapper = prevExternalFunctionMapper;
        }
      }
    }
    return _rootContext!;
  }

  VMContext createContext(VMTypeResolver? typeResolver) =>
      VMScopeContext(this, typeResolver: typeResolver);
}

/// AST base of a Class.
abstract class ASTClass<T> extends ASTEntryPointBlock {
  final String name;
  final ASTType<T> type;

  late final ASTClassStaticAccessor<ASTClass<T>, T> staticAccessor;

  ASTClass(this.name, this.type, ASTBlock? parentBlock) : super(parentBlock) {
    type.setClass(this);
    staticAccessor = ASTClassStaticAccessor(this);
  }

  @override
  VMClassContext createContext(
    VMTypeResolver? typeResolver, [
    VMContext? parentContext,
  ]) => VMClassContext(this, parent: parentContext, typeResolver: typeResolver);

  List<ASTConstructorSet> get constructors;

  void resolveNodeConstructors(ASTNode? parentNode);

  List<String> get constructorsNames;

  ASTClassConstructorDeclaration? getConstructor(
    String fName,
    ASTFunctionSignature? parametersSignature,
    VMContext context, {
    bool caseInsensitive = false,
  });

  List<ASTClassField> get fields;

  List<String> get fieldsNames;

  /// Returns a [Map<String,Object>] with the fields names and values.
  FutureOr<Map<String, Object>> getFieldsMap({
    VMContext? context,
    Map<String, ASTValue>? fieldOverwrite,
  });

  /// Builds a [Map<String,Object>] with the fields names and values.
  static FutureOr<Map<String, Object>> buildFieldsMap(
    Map<String, ASTClassField> fields, {
    VMContext? context,
    Map<String, ASTValue>? fieldOverwrite,
  }) async {
    var astRunStatus = ASTRunStatus();

    var fieldsEntriesFuture = fields.values.map((f) async {
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
      context ??= VMScopeContext(ASTBlock(null));
      for (var entry in fieldOverwrite.entries) {
        var value = await entry.value.getValue(context);
        map[entry.key] = value ?? Null;
      }
    }

    return map;
  }

  @override
  ASTClassField? getField(String name, {bool caseInsensitive = false});

  FutureOr<ASTValue<T>?> createInstance(
    VMClassContext context,
    ASTRunStatus runStatus,
  );

  FutureOr<void> initializeInstance(
    VMClassContext context,
    ASTRunStatus runStatus,
    ASTValue<T> instance,
  );

  FutureOr<void> setInstanceByValue(
    VMClassContext context,
    ASTRunStatus runStatus,
    ASTValue<T> instance,
    ASTValue<T> value,
  );

  FutureOr<void> setInstanceByVMObject(
    VMClassContext context,
    ASTRunStatus runStatus,
    ASTValue<T> instance,
    VMObject value,
  );

  FutureOr<void> setInstanceByMap(
    VMClassContext context,
    ASTRunStatus runStatus,
    ASTValue<T> instance,
    Map<String, ASTValue> value, {
    bool caseInsensitive = false,
  });

  FutureOr<ASTValue?> getInstanceFieldValue(
    VMContext context,
    ASTRunStatus runStatus,
    ASTValue<T> instance,
    String fieldName, {
    bool caseInsensitive = false,
  });

  FutureOr<ASTValue?> setInstanceFieldValue(
    VMContext context,
    ASTRunStatus runStatus,
    ASTValue<T> instance,
    String fieldName,
    ASTValue value, {
    bool caseInsensitive = false,
  });

  FutureOr<ASTValue?> removeInstanceFieldValue(
    VMContext context,
    ASTRunStatus runStatus,
    ASTValue<T> instance,
    String fieldName, {
    bool caseInsensitive = false,
  });

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);
    resolveNodeFields(parentNode);
    resolveNodeConstructors(parentNode);
  }

  void resolveNodeFields(ASTNode? parentNode);
}

/// AST of a primitive type VM Class.
class ASTClassPrimitive<T> extends ASTClass<T> {
  ASTClassPrimitive(ASTTypePrimitive<T> type) : super(type.name, type, null);

  @override
  void set(ASTBlock? other) {}

  @override
  List<ASTConstructorSet> get constructors => <ASTConstructorSet>[];

  @override
  List<String> get constructorsNames => <String>[];

  @override
  ASTClassConstructorDeclaration? getConstructor(
    String fName,
    ASTFunctionSignature? parametersSignature,
    VMContext context, {
    bool caseInsensitive = false,
  }) => null;

  @override
  void resolveNodeConstructors(ASTNode? parentNode) {
    for (var c in constructors) {
      c.resolveNode(this);
    }
  }

  @override
  List<ASTClassField> get fields => <ASTClassField>[];

  @override
  void resolveNodeFields(ASTNode? parentNode) {
    for (var f in fields) {
      f.resolveNode(this);
    }
  }

  @override
  ASTNode? getNodeIdentifier(String name, {ASTNode? requester}) {
    var f = fields.where((e) => e.name == name).firstOrNull;
    if (f != null) return f;
    return super.getNodeIdentifier(name, requester: requester);
  }

  @override
  List<String> get fieldsNames => <String>[];

  @override
  FutureOr<Map<String, Object>> getFieldsMap({
    VMContext? context,
    Map<String, ASTValue>? fieldOverwrite,
  }) => <String, Object>{};

  @override
  void addFunction(ASTFunctionDeclaration f) {}

  @override
  ASTClassField? getField(String name, {bool caseInsensitive = false}) {
    return null;
  }

  @override
  FutureOr<ASTValue<T>?> createInstance(
    VMClassContext context,
    ASTRunStatus runStatus,
  ) {
    return type.toDefaultValue(context);
  }

  @override
  FutureOr<void> initializeInstance(
    VMClassContext context,
    ASTRunStatus runStatus,
    ASTValue<T> instance,
  ) {}

  @override
  FutureOr<void> setInstanceByVMObject(
    VMClassContext context,
    ASTRunStatus runStatus,
    ASTValue<T> instance,
    VMObject value,
  ) {}

  @override
  FutureOr<void> setInstanceByValue(
    VMClassContext context,
    ASTRunStatus runStatus,
    ASTValue<T> instance,
    ASTValue<T> value,
  ) {}

  @override
  FutureOr<void> setInstanceByMap(
    VMClassContext context,
    ASTRunStatus runStatus,
    ASTValue<T> instance,
    Map<String, ASTValue> value, {
    bool caseInsensitive = false,
  }) {}

  @override
  FutureOr<ASTValue?> getInstanceFieldValue(
    VMContext context,
    ASTRunStatus runStatus,
    ASTValue<T> instance,
    String fieldName, {
    bool caseInsensitive = false,
  }) => null;

  @override
  FutureOr<ASTValue?> setInstanceFieldValue(
    VMContext context,
    ASTRunStatus runStatus,
    ASTValue<T> instance,
    String fieldName,
    ASTValue value, {
    bool caseInsensitive = false,
  }) => null;

  @override
  FutureOr<ASTValue?> removeInstanceFieldValue(
    VMContext context,
    ASTRunStatus runStatus,
    ASTValue<T> instance,
    String fieldName, {
    bool caseInsensitive = false,
  }) => null;
}

/// AST of a normal VM Class.
class ASTClassNormal extends ASTClass<VMObject> {
  ASTClassNormal(super.name, super.type, super.parentBlock);

  @override
  void set(ASTBlock? other) {
    if (other == null) return;

    if (other is ASTClassNormal) {
      _fields.clear();
      addAllFields(other._fields.values);

      _constructors.clear();
      addAllConstructors(other._constructors.values.expand((e) => e.functions));
    }

    super.set(other);
  }

  final Map<String, ASTConstructorSet> _constructors =
      <String, ASTConstructorSet>{};

  @override
  List<ASTConstructorSet> get constructors => _constructors.values.toList();

  @override
  void resolveNodeConstructors(ASTNode? parentNode) {
    for (var f in _constructors.values) {
      f.resolveNode(this);
    }
  }

  @override
  List<String> get constructorsNames => _constructors.keys.toList();

  ASTConstructorSet? getConstructorWithName(
    String name, {
    bool caseInsensitive = false,
  }) {
    var c = _constructors[name];

    if (c == null && caseInsensitive) {
      for (var entry in _constructors.entries) {
        if (equalsIgnoreAsciiCase(entry.key, name)) {
          c = entry.value;
          break;
        }
      }
    }

    return c;
  }

  bool containsConstructorWithName(
    String name, {
    bool caseInsensitive = false,
  }) {
    var set = getConstructorWithName(name, caseInsensitive: caseInsensitive);
    return set != null;
  }

  @override
  ASTClassConstructorDeclaration? getConstructor(
    String fName,
    ASTFunctionSignature? parametersSignature,
    VMContext context, {
    bool caseInsensitive = false,
  }) {
    var set = getConstructorWithName(fName, caseInsensitive: caseInsensitive);
    if (set == null) return null;

    if (parametersSignature == null) {
      return set.firstFunction;
    } else {
      return set.get(parametersSignature, false);
    }
  }

  void addConstructor(ASTClassConstructorDeclaration constructor) {
    var name = constructor.name;
    constructor.parentBlock = this;

    var set = _constructors[name];
    if (set == null) {
      _constructors[name] = ASTConstructorSetSingle(constructor);
    } else {
      var set2 = set.add(constructor);
      if (!identical(set, set2)) {
        _constructors[name] = set2;
      }
    }
  }

  void addAllConstructors(
    Iterable<ASTClassConstructorDeclaration> constructors,
  ) {
    for (var constructor in constructors) {
      addConstructor(constructor);
    }
  }

  final Map<String, ASTClassField> _fields = <String, ASTClassField>{};

  @override
  List<ASTClassField> get fields => _fields.values.toList();

  @override
  void resolveNodeFields(ASTNode? parentNode) {
    for (var f in _fields.values) {
      f.resolveNode(this);
    }
  }

  @override
  ASTNode? getNodeIdentifier(String name, {ASTNode? requester}) {
    var f = _fields[name];
    if (f != null) return f;
    return super.getNodeIdentifier(name, requester: requester);
  }

  @override
  List<String> get fieldsNames => _fields.keys.toList();

  void addField(ASTClassField field) {
    _fields[field.name] = field;
  }

  void addAllFields(Iterable<ASTClassField> fields) {
    for (var field in fields) {
      addField(field);
    }
  }

  @override
  FutureOr<Map<String, Object>> getFieldsMap({
    VMContext? context,
    Map<String, ASTValue>? fieldOverwrite,
  }) => ASTClass.buildFieldsMap(
    _fields,
    context: context,
    fieldOverwrite: fieldOverwrite,
  );

  @override
  void addFunction(ASTFunctionDeclaration f) {
    if (f is ASTClassFunctionDeclaration) {
      f.clazz = this;
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

  @override
  FutureOr<ASTClassInstance<VMObject>?> createInstance(
    VMClassContext context,
    ASTRunStatus runStatus,
  ) {
    var obj = ASTClassInstance<VMObject>(
      this,
      VMObject.createInstance(context, type),
    );
    return initializeInstance(context, runStatus, obj).resolveWithValue(obj);
  }

  @override
  FutureOr<void> initializeInstance(
    VMClassContext context,
    ASTRunStatus runStatus,
    ASTValue<VMObject> instance,
  ) async {
    if (instance is! ASTClassInstance<VMObject>) {
      throw _exceptionNotClassInstance(instance);
    }

    for (var field in _fields.values) {
      if (field is ASTClassFieldWithInitialValue) {
        var value = await field.getInitialValue(context, runStatus);
        instance.vmObject.setFieldValue(field.name, value);
      } else {
        instance.vmObject.setFieldValue(field.name, ASTValueNull.instance);
      }
    }
  }

  @override
  FutureOr<void> setInstanceByVMObject(
    VMClassContext context,
    ASTRunStatus runStatus,
    ASTValue<VMObject> instance,
    VMObject value,
  ) async {
    if (instance is! ASTClassInstance<VMObject>) {
      throw _exceptionNotClassInstance(instance);
    }

    for (var field in _fields.values) {
      var fieldValue = value.getFieldValue(field.name, context);
      if (fieldValue != null) {
        instance.vmObject.setFieldValue(field.name, fieldValue);
      }
    }
  }

  @override
  FutureOr<void> setInstanceByValue(
    VMClassContext context,
    ASTRunStatus runStatus,
    ASTValue<VMObject> instance,
    ASTValue<VMObject> value,
  ) async {
    if (instance is! ASTClassInstance<VMObject>) {
      throw _exceptionNotClassInstance(instance);
    }

    for (var field in _fields.values) {
      var fieldValue = await value.readKey(context, field.name);
      if (fieldValue != null) {
        instance.vmObject.setFieldValue(field.name, fieldValue);
      }
    }
  }

  ApolloVMCastException _exceptionNotClassInstance(
    ASTValue<VMObject> instance,
  ) => ApolloVMCastException(
    "Can't cast $instance to ASTClassInstance<VMObject>",
  );

  @override
  FutureOr<void> setInstanceByMap(
    VMClassContext context,
    ASTRunStatus runStatus,
    ASTValue<VMObject> instance,
    Map<String, ASTValue> value, {
    bool caseInsensitive = false,
  }) async {
    if (instance is! ASTClassInstance<VMObject>) {
      throw _exceptionNotClassInstance(instance);
    }

    var vmObject = instance.vmObject;

    for (var field in _fields.values) {
      var fieldName = field.name;
      var fieldValue = value[fieldName];

      if (fieldValue != null) {
        if (caseInsensitive) {
          fieldName = vmObject.getFieldNameIgnoreCase(fieldName) ?? fieldName;
        }
        vmObject.setFieldValue(fieldName, fieldValue);
      }
    }
  }

  @override
  FutureOr<ASTValue?> getInstanceFieldValue(
    VMContext context,
    ASTRunStatus runStatus,
    ASTValue<VMObject> instance,
    String fieldName, {
    bool caseInsensitive = false,
  }) {
    if (instance is! ASTClassInstance<VMObject>) {
      throw _exceptionNotClassInstance(instance);
    }

    var vmObject = instance.vmObject;

    if (caseInsensitive) {
      fieldName = vmObject.getFieldNameIgnoreCase(fieldName) ?? fieldName;
    }

    var fieldValue = vmObject.getFieldValue(fieldName, context);
    return fieldValue;
  }

  @override
  FutureOr<ASTValue?> setInstanceFieldValue(
    VMContext context,
    ASTRunStatus runStatus,
    ASTValue<VMObject> instance,
    String fieldName,
    ASTValue value, {
    bool caseInsensitive = false,
  }) {
    if (instance is! ASTClassInstance<VMObject>) {
      throw _exceptionNotClassInstance(instance);
    }

    var vmObject = instance.vmObject;

    if (caseInsensitive) {
      fieldName = vmObject.getFieldNameIgnoreCase(fieldName) ?? fieldName;
    }

    var prevValue = vmObject.setFieldValue(fieldName, value, context);
    return prevValue?.getValue(context);
  }

  @override
  FutureOr<ASTValue?> removeInstanceFieldValue(
    VMContext context,
    ASTRunStatus runStatus,
    ASTValue<VMObject> instance,
    String fieldName, {
    bool caseInsensitive = false,
  }) {
    if (instance is! ASTClassInstance<VMObject>) {
      throw _exceptionNotClassInstance(instance);
    }

    var vmObject = instance.vmObject;

    if (caseInsensitive) {
      fieldName = vmObject.getFieldNameIgnoreCase(fieldName) ?? fieldName;
    }

    var fieldValue = vmObject.removeFieldValue(fieldName, context);
    return fieldValue;
  }

  @override
  String toString() {
    return 'class $name';
  }
}

/// An AST Root.
///
/// A parse of a [CodeUnit] generates an [ASTRoot].
class ASTRoot extends ASTEntryPointBlock {
  ASTRoot() : super(null);

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    for (var e in _classes.values) {
      e.resolveNode(this);
    }
  }

  @override
  ASTNode? getNodeIdentifier(String name, {ASTNode? requester}) {
    var identifier = super.getNodeIdentifier(name, requester: requester);
    if (identifier != null) return identifier;

    var clazz = ApolloVMCore.getClass(name);
    if (clazz != null) return clazz;

    return null;
  }

  String namespace = '';

  final Set<ASTStatementImport> _imports = {};

  Set<ASTStatementImport> get imports => UnmodifiableSetView(_imports);

  void addImport(ASTStatementImport import) => _imports.add(import);

  @override
  ASTInvocableDeclaration? getFunction(
    String fName,
    ASTFunctionSignature parametersSignature,
    VMContext context, {
    bool caseInsensitive = false,
  }) {
    var set = getFunctionWithName(fName, caseInsensitive: caseInsensitive);
    if (set != null) return set.get(parametersSignature, false);

    var clazz = getClass(fName);
    if (clazz != null) {
      var constructor = clazz.getConstructor('', null, context);
      if (constructor != null &&
          constructor.matchesParametersTypes(parametersSignature, false)) {
        return constructor;
      }
    }

    var fImported = context.getImportedFunction(fName, parametersSignature);
    if (fImported != null) return fImported;

    var fExternal = context.getMappedExternalFunction(
      fName,
      parametersSignature,
    );

    return fExternal;
  }

  final Map<String, ASTClassNormal> _classes = <String, ASTClassNormal>{};

  List<ASTClassNormal> get classes => _classes.values.toList();

  List<String> get classesNames => _classes.values.map((e) => e.name).toList();

  void addClass(ASTClassNormal clazz) {
    _classes[clazz.name] = clazz;
  }

  ASTClassNormal? getClass(String className, {bool caseInsensitive = false}) {
    var clazz = _classes[className];

    if (clazz != null) {
      return clazz;
    }

    if (caseInsensitive) {
      for (var entry in _classes.entries) {
        if (equalsIgnoreAsciiCase(entry.key, className)) {
          return entry.value;
        }
      }
    }

    return null;
  }

  bool containsClass(String className, {bool caseInsensitive = false}) {
    var clazz = _classes[className];

    if (clazz != null) {
      return true;
    }

    if (caseInsensitive) {
      for (var entry in _classes.entries) {
        if (equalsIgnoreAsciiCase(entry.key, className)) {
          return true;
        }
      }
    }

    return false;
  }

  void addAllClasses(List<ASTClassNormal> classes) {
    for (var clazz in classes) {
      addClass(clazz);
    }
  }

  ASTClassNormal? getClassWithMethod(String methodName) => _classes.values
      .firstWhereOrNull((c) => c.containsFunctionWithName(methodName));

  @override
  FutureOr<ASTValue> run(
    VMContext parentContext,
    ASTRunStatus runStatus,
  ) async {
    var imports = _imports;

    if (imports.isNotEmpty) {
      for (var import in imports) {
        await import.run(parentContext, runStatus);
      }
    }

    return super.run(parentContext, runStatus);
  }
}

/// An AST Parameter declaration.
class ASTParameterDeclaration<T> with ASTNode implements ASTTypedNode {
  ASTType<T> _type;

  ASTType<T> get type => _type;

  final String name;

  ASTParameterDeclaration(ASTType<T> type, this.name) : _type = type;

  @override
  Iterable<ASTNode> get children => [type];

  @override
  void associateToType(ASTTypedNode node) {}

  @override
  FutureOr<ASTType> resolveType(VMContext? context) => type;

  @override
  FutureOr<ASTType> resolveRuntimeType(VMContext context, ASTNode? node) =>
      resolveType(context);

  FutureOr<ASTValue<T>?> toValue(VMContext context, Object? v) =>
      type.toValue(context, v);

  ASTNode? _parentNode;

  @override
  ASTNode? get parentNode => _parentNode;

  @override
  void resolveNode(ASTNode? parentNode) {
    _parentNode = parentNode;

    cacheDescendantChildren();
  }

  @override
  ASTNode? getNodeIdentifier(String name, {ASTNode? requester}) =>
      parentNode?.getNodeIdentifier(name, requester: requester);

  @override
  String toString() {
    return '$type $name';
  }
}

extension IterableASTParameterDeclarationExtension<
  P extends ASTParameterDeclaration
>
    on Iterable<P> {
  Iterable<P> withThisParameter() => where(
    (p) =>
        p.type is ASTTypeConstructorThis ||
        (p is ASTConstructorParameterDeclaration && p.thisParameter),
  );
}

class ASTConstructorParameterDeclaration<T> extends ASTParameterDeclaration {
  final int index;

  final bool optional;

  final bool thisParameter;

  ASTConstructorParameterDeclaration(
    super.type,
    super.name,
    this.index,
    this.optional, {
    this.thisParameter = false,
  });

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    if (identical(type, ASTTypeConstructorThis.instance) &&
        parentNode is ASTClassConstructorDeclaration) {
      var parentClass = parentNode.parentClass;
      var field = parentClass?.getField(name);
      if (field != null) {
        _type = field.type;
      }
    }
  }

  ASTFunctionParameterDeclaration toASTFunctionParameterDeclaration() =>
      ASTFunctionParameterDeclaration(type, name, index, optional);
}

extension IterableASTConstructorParameterDeclarationExtension
    on Iterable<ASTConstructorParameterDeclaration> {
  List<ASTFunctionParameterDeclaration> toASTFunctionParameterDeclaration() =>
      map((e) => e.toASTFunctionParameterDeclaration()).toList();
}

/// An AST Function Parameter declaration.
class ASTFunctionParameterDeclaration<T> extends ASTParameterDeclaration<T> {
  final int index;

  final bool optional;

  final bool unmodifiable;

  ASTFunctionParameterDeclaration(
    super.type,
    super.name,
    this.index,
    this.optional, {
    this.unmodifiable = false,
  });
}

/// An AST Function Signature.
class ASTFunctionSignature with ASTNode {
  List<ASTType?>? positionalTypes;

  Map<String, ASTType?>? namedTypes;

  ASTFunctionSignature(this.positionalTypes, this.namedTypes);

  @override
  Iterable<ASTNode> get children => [...?positionalTypes?.nonNulls];

  static ASTFunctionSignature from(
    List? positionalParameters,
    Map? namedParameters,
  ) {
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

  static Map<String, ASTType?>? toASTTypeMap(
    Map? params, [
    VMContext? context,
  ]) {
    if (params == null || params.isEmpty) return null;
    return params.map((k, v) => MapEntry('$k', toASTType(v, context)));
  }

  static ASTType? toASTType(dynamic o, [VMContext? context]) {
    if (o == null) return null;
    if (o is ASTType) {
      var t = o.resolveType(context);
      return t is ASTType ? t : o;
    }

    if (o is ASTValue) {
      if (context != null) {
        var resolved = o.resolve(context);
        if (resolved is ASTValue) {
          return toASTType(resolved.type, context);
        }
      }
      return o.type;
    }

    var t = ASTType.from(o, context);

    var t2 = t.resolveType(context);
    return t2 is ASTType ? t2 : t;
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

  ASTNode? _parentNode;

  @override
  ASTNode? get parentNode => _parentNode;

  @override
  void resolveNode(ASTNode? parentNode) {
    _parentNode = parentNode;

    cacheDescendantChildren();
  }

  @override
  ASTNode? getNodeIdentifier(String name, {ASTNode? requester}) =>
      parentNode?.getNodeIdentifier(name, requester: requester);

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
      s.write(
        namedTypes!.entries.map((e) {
          var k = e.key;
          var v = e.value;
          return v != null ? '$k: $v' : '$k: ?';
        }).toList(),
      );
    }

    s.write('}');

    return s.toString();
  }
}

/// Base AST Invokable Set.
abstract class ASTInvokableSet<
  P extends ASTParameterDeclaration,
  PS extends ASTParametersDeclaration<P>,
  F extends ASTInvocableDeclaration<dynamic, P, PS>
>
    with ASTNode {
  String get invokableTypeName;

  String get name => firstFunction.name;

  List<F> get functions;

  F get firstFunction;

  F get(ASTFunctionSignature parametersSignature, bool exactTypes);

  ASTInvokableSet<P, PS, F> add(F f);

  ASTNode? _parentNode;

  @override
  ASTNode? get parentNode => _parentNode;

  @override
  void resolveNode(ASTNode? parentNode) {
    _parentNode = parentNode;

    resolveFunctionsNodes(parentNode);

    cacheDescendantChildren();
  }

  void resolveFunctionsNodes(ASTNode? parentNode);

  @override
  ASTNode? getNodeIdentifier(String name, {ASTNode? requester}) =>
      parentNode?.getNodeIdentifier(name, requester: requester);
}

/// Base [ASTInvokableSet] implementation, with 1 entry.
abstract class ASTInvokableSetSingle<
  P extends ASTParameterDeclaration,
  PS extends ASTParametersDeclaration<P>,
  F extends ASTInvocableDeclaration<dynamic, P, PS>
>
    extends ASTInvokableSet<P, PS, F> {
  final F f;

  ASTInvokableSetSingle(this.f);

  @override
  Iterable<ASTNode> get children => [f];

  @override
  F get firstFunction => f;

  @override
  List<F> get functions => [f];

  @override
  F get(ASTFunctionSignature parametersSignature, bool exactTypes) {
    if (f.matchesParametersTypes(parametersSignature, exactTypes)) {
      return f;
    }

    throw StateError(
      '$invokableTypeName \'${f.name}\' parameters signature not compatible: sign:$parametersSignature != f:${f.parameters}',
    );
  }

  @override
  void resolveFunctionsNodes(ASTNode? parentNode) {
    f.resolveNode(parentNode);
  }
}

/// Base [ASTInvokableSet] implementation, with multiple entries.
abstract class ASTInvokableSetMultiple<
  P extends ASTParameterDeclaration,
  PS extends ASTParametersDeclaration<P>,
  F extends ASTInvocableDeclaration<dynamic, P, PS>
>
    extends ASTInvokableSet<P, PS, F> {
  final List<F> _functions = <F>[];

  @override
  Iterable<ASTNode> get children => [..._functions];

  @override
  F get firstFunction => _functions.first;

  @override
  List<F> get functions => _functions;

  @override
  F get(ASTFunctionSignature parametersSignature, bool exactTypes) {
    for (var f in _functions) {
      if (f.matchesParametersTypes(parametersSignature, exactTypes)) {
        return f;
      }
    }

    F? first;
    for (var f in _functions) {
      first = f;
      break;
    }

    if (!exactTypes && first != null) {
      return first;
    }

    throw ApolloVMRuntimeError(
      "Can't find ${invokableTypeName.toLowerCase()} '${first?.name}' with signature: $parametersSignature",
    );
  }

  @override
  ASTInvokableSet<P, PS, F> add(F f) {
    _functions.add(f);

    _functions.sort((a, b) {
      var pSize1 = a.parametersSize;
      var pSize2 = b.parametersSize;
      return pSize1.compareTo(pSize2);
    });

    return this;
  }

  @override
  void resolveFunctionsNodes(ASTNode? parentNode) {
    for (var f in _functions) {
      f.resolveNode(parentNode);
    }
  }
}

/// Base AST Function Set.
abstract class ASTFunctionSet
    extends
        ASTInvokableSet<
          ASTFunctionParameterDeclaration,
          ASTFunctionParametersDeclaration,
          ASTFunctionDeclaration
        > {
  @override
  String get invokableTypeName => 'Function';

  @override
  ASTFunctionSet add(ASTFunctionDeclaration f);
}

/// [ASTFunctionSet] implementation, with 1 entry.
class ASTFunctionSetSingle
    extends
        ASTInvokableSetSingle<
          ASTFunctionParameterDeclaration,
          ASTFunctionParametersDeclaration,
          ASTFunctionDeclaration
        >
    implements ASTFunctionSet {
  ASTFunctionSetSingle(super.f);

  @override
  String get invokableTypeName => 'Function';

  @override
  ASTFunctionSet add(ASTFunctionDeclaration f) {
    var set = ASTFunctionSetMultiple();
    set.add(this.f);
    set.add(f);
    return set;
  }
}

/// [ASTFunctionSet] implementation, with multiple entries.
class ASTFunctionSetMultiple
    extends
        ASTInvokableSetMultiple<
          ASTFunctionParameterDeclaration,
          ASTFunctionParametersDeclaration,
          ASTFunctionDeclaration
        >
    implements ASTFunctionSet {
  @override
  String get invokableTypeName => 'Function';

  @override
  ASTFunctionSet add(ASTFunctionDeclaration f) {
    super.add(f);
    return this;
  }
}

/// Base AST Constructor Set.
abstract class ASTConstructorSet
    extends
        ASTInvokableSet<
          ASTConstructorParameterDeclaration,
          ASTConstructorParametersDeclaration,
          ASTClassConstructorDeclaration
        > {
  @override
  String get invokableTypeName => 'Constructor';

  @override
  ASTConstructorSet add(ASTClassConstructorDeclaration c);
}

/// [ASTConstructorSet] implementation, with 1 entry.
class ASTConstructorSetSingle
    extends
        ASTInvokableSetSingle<
          ASTConstructorParameterDeclaration,
          ASTConstructorParametersDeclaration,
          ASTClassConstructorDeclaration
        >
    implements ASTConstructorSet {
  ASTConstructorSetSingle(super.c);

  @override
  String get invokableTypeName => 'Constructor';

  @override
  ASTConstructorSet add(ASTClassConstructorDeclaration c) {
    var set = ASTConstructorSetMultiple();
    set.add(f);
    set.add(c);
    return set;
  }
}

/// [ASTConstructorSet] implementation, with multiple entries.
class ASTConstructorSetMultiple
    extends
        ASTInvokableSetMultiple<
          ASTConstructorParameterDeclaration,
          ASTConstructorParametersDeclaration,
          ASTClassConstructorDeclaration
        >
    implements ASTConstructorSet {
  @override
  String get invokableTypeName => 'Constructor';

  @override
  // ignore: avoid_renaming_method_parameters
  ASTConstructorSet add(ASTClassConstructorDeclaration c) {
    super.add(c);
    return this;
  }
}

/// An AST Constructor Parameters Declaration
class ASTConstructorParametersDeclaration
    extends ASTParametersDeclaration<ASTConstructorParameterDeclaration> {
  ASTConstructorParametersDeclaration(
    super.positionalParameters, [
    super.optionalParameters,
    super.namedParameters,
  ]);
}

/// An AST Function Parameters Declaration
class ASTFunctionParametersDeclaration
    extends ASTParametersDeclaration<ASTFunctionParameterDeclaration> {
  ASTFunctionParametersDeclaration(
    super.positionalParameters, [
    super.optionalParameters,
    super.namedParameters,
  ]);
}

/// An AST Parameters Declaration
abstract class ASTParametersDeclaration<P extends ASTParameterDeclaration> {
  List<P>? positionalParameters;

  List<P>? optionalParameters;

  List<P>? namedParameters;

  ASTParametersDeclaration(
    this.positionalParameters, [
    this.optionalParameters,
    this.namedParameters,
  ]);

  void resolveNode(ASTNode? parentNode) {
    if (positionalParameters != null) {
      for (var e in positionalParameters!) {
        e.resolveNode(parentNode);
      }
    }

    if (optionalParameters != null) {
      for (var e in optionalParameters!) {
        e.resolveNode(parentNode);
      }
    }

    if (namedParameters != null) {
      for (var e in namedParameters!) {
        e.resolveNode(parentNode);
      }
    }
  }

  /// Returns a list with all the [positionalParameters], [optionalParameters] and [namedParameters].
  List<P> get allParameters => [
    ...?positionalParameters,
    ...?optionalParameters,
    ...?namedParameters,
  ];

  int get positionalParametersSize => positionalParameters?.length ?? 0;

  int get optionalParametersSize => optionalParameters?.length ?? 0;

  int get namedParametersSize => namedParameters?.length ?? 0;

  int get size =>
      positionalParametersSize + optionalParametersSize + namedParametersSize;

  bool get isEmpty => size == 0;

  bool get isNotEmpty => !isEmpty;

  P? getParameterByIndex(int index) {
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

  P? getParameterByName(String name) {
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
    ASTFunctionSignature parametersSignature,
    bool exactTypes,
  ) {
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
  /// - [exactType]: if true the [param] should be exact to [type].
  static bool parameterAcceptsType(
    ASTParameterDeclaration? param,
    ASTType? type,
    bool exactType,
  ) {
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
  ASTClass? clazz;

  ASTType? get classType => clazz?.type;

  ASTClassFunctionDeclaration(
    this.clazz,
    String name,
    ASTFunctionParametersDeclaration parameters,
    ASTType<T> returnType, {
    ASTBlock? block,
    ASTModifiers? modifiers,
  }) : super(name, parameters, returnType, block: block, modifiers: modifiers);

  FutureOr<ASTValue<T>> objectCall(
    VMContext parent,
    ASTValue classInstance, {
    List? positionalParameters,
    Map? namedParameters,
  }) {
    var objContext = VMClassContext(clazz!, parent: parent);
    objContext.setClassInstance(classInstance);
    return call(
      objContext,
      positionalParameters: positionalParameters,
      namedParameters: namedParameters,
    );
  }
}

/// An AST of an invocable block declaration.
/// See [ASTClassConstructorDeclaration] and [ASTFunctionDeclaration].
abstract class ASTInvocableDeclaration<
  T,
  P extends ASTParameterDeclaration,
  PS extends ASTParametersDeclaration<P>
>
    extends ASTBlock {
  /// Name of this function/constructor.
  final String name;

  /// Parameters.
  final PS _parameters;

  /// The return type of this function.
  final ASTType<T> returnType;

  /// Modifiers of this function.
  final ASTModifiers modifiers;

  ASTInvocableDeclaration(
    this.name,
    this._parameters,
    this.returnType, {
    ASTBlock? block,
    ASTModifiers? modifiers,
  }) : modifiers = modifiers ?? ASTModifiers.modifiersNone,
       super(null) {
    set(block);
  }

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    _parameters.resolveNode(this);
  }

  @override
  ASTNode? getNodeIdentifier(String name, {ASTNode? requester}) {
    var allChildren = descendantChildren;

    var limit = allChildren.length;

    if (requester != null) {
      var idx = allChildren.indexWhere((e) => identical(e, requester));

      if (idx >= 0) {
        limit = idx + 1;
      }
    }

    for (var i = limit - 1; i >= 0; --i) {
      var child = allChildren[i];

      if (child is ASTStatementVariableDeclaration && child.name == name) {
        return child;
      } else if (child is ASTFunctionDeclaration && child.name == name) {
        return child;
      }
    }

    var p = _parameters.getParameterByName(name);
    if (p != null) return p;

    return super.getNodeIdentifier(name, requester: requester);
  }

  PS get parameters => _parameters;

  int get parametersSize => _parameters.size;

  P? getParameterByIndex(int index) => _parameters.getParameterByIndex(index);

  P? getParameterByName(String name) => _parameters.getParameterByName(name);

  FutureOr<ASTValue?> getParameterValueByIndex(VMContext context, int index) {
    var p = getParameterByIndex(index);
    if (p == null) return null;
    var variable = context.getVariable(p.name, false);
    if (variable == null) return null;

    return variable.resolveMapped((v) => v?.getValue(context));
  }

  FutureOr<ASTValue?> getParameterValueByName(VMContext context, String name) {
    var p = getParameterByName(name);
    if (p == null) return null;
    return context.getVariable(p.name, false).resolveMapped((variable) {
      return variable?.getValue(context);
    });
  }

  bool matchesParametersTypes(
    ASTFunctionSignature signature,
    bool exactTypes,
  ) => _parameters.matchesParametersTypes(signature, exactTypes);

  FutureOr<ASTValue<T>> call(
    VMContext parent, {
    List? positionalParameters,
    Map? namedParameters,
  }) async {
    var context = VMScopeContext(this, parent: parent);

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
    VMContext context,
    Object? returnValue,
  ) {
    var ret = returnType.toValue(context, returnValue);
    return ret.resolveMapped((resolved) {
      resolved ??= ASTValueVoid.instance as ASTValue<T>;
      return resolved;
    });
  }

  FutureOr<void> initializeVariables(
    VMContext context,
    List? positionalParameters,
    Map? namedParameters,
  ) {
    if (positionalParameters != null) {
      var ret = _initializePositionalParameters(
        positionalParameters,
        0,
        context,
      );
      return ret.onResolve((i) {
        _initializeOptionalParameters(i, context);
      });
    } else {
      _initializeOptionalParameters(0, context);
    }
  }

  FutureOr<int> _initializePositionalParameters(
    List<dynamic> positionalParameters,
    int i,
    VMContext context,
  ) {
    FutureOr<void> prevFuture;

    for (; i < positionalParameters.length; ++i) {
      var paramVal = positionalParameters[i];
      var fParam = getParameterByIndex(i);
      if (fParam == null) {
        throw StateError("Can't find parameter at index: $i");
      }

      var value = fParam.toValue(context, paramVal) ?? ASTValueNull.instance;

      var future = value.onResolve((v) {
        context.declareVariableWithValue(fParam.type, fParam.name, v);
      });

      if (prevFuture == null) {
        prevFuture = future;
      } else {
        prevFuture = prevFuture.resolveWith(() => future);
      }
    }

    return prevFuture.resolveWith(() => i);
  }

  (List?, Map?) normalizeParameters({
    List? positionalParameters,
    Map? namedParameters,
  }) {
    positionalParameters = normalizePositionalParameters(positionalParameters);
    namedParameters = normalizeNamedParameters(namedParameters);

    return (positionalParameters, namedParameters);
  }

  List? normalizePositionalParameters(List? positionalParameters) {
    if (positionalParameters == null) return null;

    final positionalParametersDeclaration = parameters.positionalParameters;

    final optionalParametersDeclaration = parameters.optionalParameters;

    final positionalParametersLength =
        positionalParametersDeclaration?.length ?? 0;
    final optionalParametersLength = optionalParametersDeclaration?.length ?? 0;

    if (positionalParametersLength == 0 && optionalParametersLength == 0) {
      return null;
    }

    var lng = math.min(
      positionalParametersLength + optionalParametersLength,
      positionalParameters.length,
    );

    if (lng == 0) return null;

    final allParametersDeclaration = positionalParametersDeclaration == null
        // Only optional parameters exist (guaranteed non-null here)
        ? optionalParametersDeclaration!
        : optionalParametersDeclaration == null
        // Only positional parameters exist
        ? positionalParametersDeclaration
        // Both exist: combine lazily without allocating a merged list
        : CombinedListView([
            positionalParametersDeclaration,
            optionalParametersDeclaration,
          ]);

    var positionalParameters2 = List.generate(lng, (i) {
      var p = allParametersDeclaration[i];
      var v = positionalParameters[i];
      var astType = p.type;

      var astValue = astType.toASTValue(v);
      var v2 = astValue?.getValueNoContext();
      return v2;
    });

    return positionalParameters2;
  }

  Map? normalizeNamedParameters(
    Map? namedParameters, {
    bool ignoreCase = true,
  }) {
    if (namedParameters == null) return null;

    final namedParametersDeclaration = parameters.namedParameters;
    if (namedParametersDeclaration == null ||
        namedParametersDeclaration.isEmpty) {
      return null;
    }

    var lng = math.min(
      namedParametersDeclaration.length,
      namedParameters.length,
    );

    if (lng == 0) return null;

    var namedParameters2 = Map.fromEntries(
      List.generate(lng, (i) {
        var p = namedParametersDeclaration[i];
        var pName = p.name;
        var v = namedParameters.lookupValue(pName, ignoreCase: true);
        var astType = p.type;
        var astValue = astType.toASTValue(v);
        var v2 = astValue?.getValueNoContext();
        return MapEntry(pName, v2);
      }),
    );

    return namedParameters2;
  }

  void _initializeOptionalParameters(int i, VMContext context) {
    var parametersSize = this.parametersSize;

    for (; i < parametersSize; ++i) {
      var fParam = getParameterByIndex(i)!;
      context.declareVariableWithValue(
        fParam.type,
        fParam.name,
        ASTValueNull.instance,
      );
    }
  }

  @override
  VMContext defineRunContext(VMContext parentContext) {
    // Ensure the the passed parentContext will be used by the block,
    // since is already instantiated by call(...).
    return parentContext;
  }

  @override
  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus) {
    throw UnsupportedError(
      "Can't run this block directly! Should use call(...), since this block needs parameters initialization!",
    );
  }

  @override
  ASTType resolveType(VMContext? context) => returnType;

  @override
  String toString() {
    var block = super.toString();
    return '$modifiers $returnType $name($_parameters) $block';
  }
}

extension IterableASTFunctionDeclarationExtension<
  P extends ASTParameterDeclaration,
  PS extends ASTParametersDeclaration<P>,
  F extends ASTInvocableDeclaration<dynamic, P, PS>
>
    on Iterable<F> {
  F? resolveBestMatchBySignature({
    List? positionalParameters,
    Map? namedParameters,
  }) {
    final length = this.length;

    if (length == 0) return null;

    if (length == 1) {
      return first;
    } else {
      var fSignature = ASTFunctionSignature.from(
        positionalParameters,
        namedParameters,
      );

      return
      // Try strict match first (exact parameter type compatibility)
      firstWhereOrNull((f) => f.matchesParametersTypes(fSignature, true)) ??
          // Fallback to relaxed match (allowing looser type compatibility)
          firstWhereOrNull((f) => f.matchesParametersTypes(fSignature, false));
    }
  }
}

/// An AST Function Declaration.
class ASTFunctionDeclaration<T>
    extends
        ASTInvocableDeclaration<
          T,
          ASTFunctionParameterDeclaration,
          ASTFunctionParametersDeclaration
        > {
  ASTFunctionDeclaration(
    super.name,
    super._parameters,
    super.returnType, {
    super.block,
    super.modifiers,
  });
}

/// An AST Function Declaration.
class ASTClassConstructorDeclaration<T>
    extends
        ASTInvocableDeclaration<
          T,
          ASTConstructorParameterDeclaration,
          ASTConstructorParametersDeclaration
        > {
  /// The return type of this function.
  final ASTType<T> classType;

  ASTClassConstructorDeclaration(
    this.classType,
    String name,
    ASTConstructorParametersDeclaration parameters, {
    super.block,
    super.modifiers,
  }) : super(name, parameters, classType);

  ASTClass? _parentClass;

  ASTClass? get parentClass => _parentClass;

  @override
  void resolveNode(ASTNode? parentNode) {
    if (parentNode is ASTClass) {
      _parentClass = parentNode;
    }

    super.resolveNode(parentNode);
  }

  @override
  ASTType resolveType(VMContext? context) => classType;

  @override
  FutureOr<ASTClassInstance<ASTValue<T>>> initializeVariables(
    VMContext context,
    List? positionalParameters,
    Map? namedParameters,
  ) {
    final parentClass =
        this.parentClass ??
        (throw ApolloVMRuntimeError("`parentClass` not defined!"));

    var classContext = parentClass.createContext(context.typeResolver, context);

    return parentClass
        .createInstance(classContext, ASTRunStatus.dummy)
        .resolveMapped((obj) {
          if (obj == null) {
            throw ApolloVMRuntimeError(
              "Can't instantiate class `$classType` instance!",
            );
          }

          context.declareVariableWithValue(parentClass.type, 'this', obj);

          return super
              .initializeVariables(
                context,
                positionalParameters,
                namedParameters,
              )
              .resolveMapped((_) {
                return obj as ASTClassInstance<ASTValue<T>>;
              });
        });
  }

  @override
  FutureOr<ASTValue<T>> call(
    VMContext parent, {
    List? positionalParameters,
    Map? namedParameters,
  }) async {
    var context = VMScopeContext(this, parent: parent);

    var prevContext = VMContext.setCurrent(context);
    try {
      var obj = await initializeVariables(
        context,
        positionalParameters,
        namedParameters,
      );

      final parameters = _parameters;

      var constructorParameters = [
        ...?parameters.positionalParameters?.withThisParameter(),
        ...?parameters.optionalParameters?.withThisParameter(),
        ...?parameters.namedParameters?.withThisParameter(),
      ];

      if (constructorParameters.isNotEmpty) {
        var classContext = obj.createContext(context);
        for (var p in constructorParameters.withThisParameter()) {
          var variable = await context.getVariable(p.name, false);
          if (variable != null) {
            var v = await variable.getValue(context);
            await obj.setField(classContext, p.name, v);
          } else if (!p.optional) {
            throw ApolloVMNullPointerException(
              "Missing required constructor parameter: $p\n"
              "Constructor: $this",
            );
          }
        }
      }

      await run(context, ASTRunStatus());

      return obj as ASTValue<T>;
    } finally {
      VMContext.setCurrent(prevContext);
    }
  }

  @override
  FutureOr<ASTValue> run(
    VMContext parentContext,
    ASTRunStatus runStatus,
  ) async {
    var blockContext = defineRunContext(parentContext);

    FutureOr<ASTValue> returnValue = ASTValueVoid.instance;

    for (var stm in statements) {
      var ret = await stm.run(blockContext, runStatus);

      if (runStatus.returned) {
        return (runStatus.returnedFutureValue ?? runStatus.returnedValue)!;
      }

      returnValue = ret;
    }

    return returnValue;
  }

  @override
  String toString() {
    var block = super.toString();
    return '$modifiers $classType.$name($_parameters) $block';
  }
}

/// An AST Class Getter Declaration.
class ASTClassGetterDeclaration<T> extends ASTGetterDeclaration<T> {
  /// The class type of this getter.
  ASTClass? clazz;

  ASTType? get classType => clazz?.type;

  ASTClassGetterDeclaration(
    this.clazz,
    String name,

    ASTType<T> returnType, {
    ASTBlock? block,
    ASTModifiers? modifiers,
  }) : super(name, returnType, block: block, modifiers: modifiers);

  FutureOr<ASTValue<T>> objectCall(
    VMContext parent,
    ASTValue classInstance, {
    List? positionalParameters,
    Map? namedParameters,
  }) {
    var objContext = VMClassContext(clazz!, parent: parent);
    objContext.setClassInstance(classInstance);
    return call(objContext);
  }
}

/// An AST getter Declaration.
class ASTGetterDeclaration<T> extends ASTBlock {
  /// Name of this function.
  final String name;

  /// The return type of this function.
  final ASTType<T> returnType;

  /// Modifiers of this function.
  final ASTModifiers modifiers;

  ASTGetterDeclaration(
    this.name,
    this.returnType, {
    ASTBlock? block,
    ASTModifiers? modifiers,
  }) : modifiers = modifiers ?? ASTModifiers.modifiersNone,
       super(null) {
    set(block);
  }

  @override
  ASTNode? getNodeIdentifier(String name, {ASTNode? requester}) {
    var allChildren = descendantChildren;

    var limit = allChildren.length;

    if (requester != null) {
      var idx = allChildren.indexWhere((e) => identical(e, requester));

      if (idx >= 0) {
        limit = idx + 1;
      }
    }

    for (var i = limit - 1; i >= 0; --i) {
      var child = allChildren[i];

      if (child is ASTStatementVariableDeclaration && child.name == name) {
        return child;
      } else if (child is ASTFunctionDeclaration && child.name == name) {
        return child;
      }
    }

    return super.getNodeIdentifier(name, requester: requester);
  }

  FutureOr<ASTValue<T>> call(VMContext parent) async {
    var context = VMScopeContext(this, parent: parent);

    var prevContext = VMContext.setCurrent(context);
    try {
      var result = await super.run(context, ASTRunStatus());
      return await resolveReturnValue(context, result, result);
    } finally {
      VMContext.setCurrent(prevContext);
    }
  }

  FutureOr<ASTValue<T>> resolveReturnValue(
    VMContext context,
    ASTNode? node,
    Object? returnValue,
  ) {
    return resolveRuntimeType(
      context,
      returnValue is ASTNode ? returnValue : node,
    ).resolveMapped((runtimeReturnType) {
      var ret = runtimeReturnType is ASTType<T>
          ? runtimeReturnType.toValue(context, returnValue)
          : returnType.toValue(context, returnValue);
      return ret.resolveMapped((resolved) {
        resolved ??= ASTValueVoid.instance as ASTValue<T>;
        return resolved;
      });
    });
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
      "Can't run this block directly! Should use call(...), since this block needs parameters initialization!",
    );
  }

  @override
  ASTType resolveType(VMContext? context) => returnType;

  @override
  String toString() {
    var block = super.toString();
    return '$modifiers $returnType get $name $block';
  }
}

typedef ParameterValueResolver =
    FutureOr<dynamic> Function(ASTValue? paramVal, VMContext context);

/// An AST External Getter.
class ASTExternalGetter<T> extends ASTGetterDeclaration<T> {
  final Function() externalFunction;

  ASTExternalGetter(super.name, super.returnType, this.externalFunction);

  @override
  FutureOr<ASTValue<T>> call(VMContext parent) async {
    var context = VMScopeContext(this, parent: parent);

    var prevContext = VMContext.setCurrent(context);
    try {
      dynamic result = externalFunction();

      if (result is Future) {
        var r = await result;
        return await resolveReturnValue(context, null, r);
      } else {
        return await resolveReturnValue(context, null, result);
      }
    } finally {
      VMContext.setCurrent(prevContext);
    }
  }
}

/// An AST External Class Getter.
class ASTExternalClassGetter<T> extends ASTClassGetterDeclaration<T> {
  final Function(Object? o) externalFunction;

  final FutureOr<ASTType> Function(VMContext? context, ASTNode? o)?
  returnTypeResolver;

  ASTExternalClassGetter(
    ASTClass super.clazz,
    super.name,
    super.returnType,
    this.externalFunction, [
    this.returnTypeResolver,
  ]);

  @override
  FutureOr<ASTType<dynamic>> resolveRuntimeType(
    VMContext context,
    ASTNode? node,
  ) {
    final returnTypeResolver = this.returnTypeResolver;
    if (returnTypeResolver != null) {
      return returnTypeResolver(context, node);
    }

    return super.resolveRuntimeType(context, node);
  }

  @override
  FutureOr<ASTValue<T>> call(
    VMContext parent, {
    List? positionalParameters,
    Map? namedParameters,
  }) {
    var classInstance = parent.getClassInstance();
    return classInstance!.getValue(parent).resolveMapped((obj) {
      var context = VMScopeContext(this, parent: parent);

      var prevContext = VMContext.setCurrent(context);
      try {
        dynamic result = externalFunction(obj);
        if (result is Future) {
          return result
              .then((r) => resolveReturnValue(context, classInstance, r))
              .whenComplete(() => VMContext.setCurrent(prevContext));
        } else {
          try {
            return resolveReturnValue(context, classInstance, result);
          } finally {
            VMContext.setCurrent(prevContext);
          }
        }
      } catch (_) {
        if (identical(VMContext.getCurrent(), context)) {
          VMContext.setCurrent(prevContext);
        }
        rethrow;
      }
    });
  }
}

/// An AST External Function.
class ASTExternalFunction<T> extends ASTFunctionDeclaration<T> {
  final Function externalFunction;

  final ParameterValueResolver? parameterResolver;

  ASTExternalFunction(
    super.name,
    super.parameters,
    super.returnType,
    this.externalFunction, [
    this.parameterResolver,
  ]);

  FutureOr<dynamic> resolveParameterValue<V>(
    ASTValue<V>? paramVal,
    VMContext context,
  ) {
    var parameterResolver = this.parameterResolver;

    if (parameterResolver != null) {
      return parameterResolver(paramVal, context);
    } else {
      return paramVal?.getValue(context);
    }
  }

  @override
  FutureOr<ASTValue<T>> call(
    VMContext parent, {
    List? positionalParameters,
    Map? namedParameters,
  }) async {
    var context = VMScopeContext(this, parent: parent);

    var prevContext = VMContext.setCurrent(context);
    try {
      await initializeVariables(context, positionalParameters, namedParameters);

      var parametersSize = this.parametersSize;

      dynamic result;
      if (externalFunction.isParametersSize0 || parametersSize == 0) {
        result = externalFunction();
      } else if (externalFunction.isParametersSize1 || parametersSize == 1) {
        var paramVal = await getParameterValueByIndex(context, 0);
        var a0 = resolveParameterValue(paramVal, context);
        result = externalFunction(a0);
      } else if (this.parametersSize == 2) {
        var paramVal0 = await getParameterValueByIndex(context, 0);
        var paramVal1 = await getParameterValueByIndex(context, 1);
        var a0 = resolveParameterValue(paramVal0, context);
        var a1 = resolveParameterValue(paramVal1, context);
        result = externalFunction(a0, a1);
      } else if (this.parametersSize == 3) {
        var paramVal0 = await getParameterValueByIndex(context, 0);
        var paramVal1 = await getParameterValueByIndex(context, 1);
        var paramVal2 = await getParameterValueByIndex(context, 2);
        var a0 = resolveParameterValue(paramVal0, context);
        var a1 = resolveParameterValue(paramVal1, context);
        var a2 = resolveParameterValue(paramVal2, context);
        result = externalFunction(a0, a1, a2);
      } else if (this.parametersSize == 4) {
        var paramVal0 = await getParameterValueByIndex(context, 0);
        var paramVal1 = await getParameterValueByIndex(context, 1);
        var paramVal2 = await getParameterValueByIndex(context, 2);
        var paramVal3 = await getParameterValueByIndex(context, 4);
        var a0 = resolveParameterValue(paramVal0, context);
        var a1 = resolveParameterValue(paramVal1, context);
        var a2 = resolveParameterValue(paramVal2, context);
        var a3 = resolveParameterValue(paramVal3, context);
        result = externalFunction(a0, a1, a2, a3);
      } else if (this.parametersSize == 5) {
        var paramVal0 = await getParameterValueByIndex(context, 0);
        var paramVal1 = await getParameterValueByIndex(context, 1);
        var paramVal2 = await getParameterValueByIndex(context, 2);
        var paramVal3 = await getParameterValueByIndex(context, 4);
        var paramVal4 = await getParameterValueByIndex(context, 5);
        var a0 = resolveParameterValue(paramVal0, context);
        var a1 = resolveParameterValue(paramVal1, context);
        var a2 = resolveParameterValue(paramVal2, context);
        var a3 = resolveParameterValue(paramVal3, context);
        var a4 = resolveParameterValue(paramVal4, context);
        result = externalFunction(a0, a1, a2, a3, a4);
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

/// An AST External Class Function.
class ASTExternalClassFunction<T> extends ASTClassFunctionDeclaration<T> {
  final Function externalFunction;

  final ParameterValueResolver? parameterResolver;

  ASTExternalClassFunction(
    ASTClass super.clazz,
    super.name,
    super.parameters,
    super.returnType,
    this.externalFunction, [
    this.parameterResolver,
  ]);

  FutureOr<dynamic> resolveParameterValue<V>(
    ASTValue<V>? paramVal,
    VMContext context,
  ) {
    var parameterResolver = this.parameterResolver;

    if (parameterResolver != null) {
      return parameterResolver(paramVal, context);
    } else {
      return paramVal?.getValue(context);
    }
  }

  @override
  FutureOr<ASTValue<T>> call(
    VMContext parent, {
    List? positionalParameters,
    Map? namedParameters,
  }) async {
    var classInstance = parent.getClassInstance();
    var obj = await classInstance!.getValue(parent);

    var context = VMScopeContext(this, parent: parent);

    var prevContext = VMContext.setCurrent(context);
    try {
      await initializeVariables(context, positionalParameters, namedParameters);

      var parametersSize = this.parametersSize;

      dynamic result;
      if (externalFunction.isParametersSize0 || parametersSize == 0) {
        result = externalFunction(obj);
      } else if (externalFunction.isParametersSize1 || parametersSize == 1) {
        var paramVal = await getParameterValueByIndex(context, 0);
        var a0 = resolveParameterValue(paramVal, context);
        result = externalFunction(obj, a0);
      } else if (this.parametersSize == 2) {
        var paramVal0 = await getParameterValueByIndex(context, 0);
        var paramVal1 = await getParameterValueByIndex(context, 1);
        var a0 = resolveParameterValue(paramVal0, context);
        var a1 = resolveParameterValue(paramVal1, context);
        result = externalFunction(obj, a0, a1);
      } else if (this.parametersSize == 3) {
        var paramVal0 = await getParameterValueByIndex(context, 0);
        var paramVal1 = await getParameterValueByIndex(context, 1);
        var paramVal2 = await getParameterValueByIndex(context, 2);
        var a0 = resolveParameterValue(paramVal0, context);
        var a1 = resolveParameterValue(paramVal1, context);
        var a2 = resolveParameterValue(paramVal2, context);
        result = externalFunction(a0, a1, a2);
      } else {
        result = externalFunction.call(obj);
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
