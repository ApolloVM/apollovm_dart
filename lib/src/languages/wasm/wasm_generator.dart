// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:data_serializer/data_serializer.dart';

import '../../apollovm_base.dart';
import '../../apollovm_code_storage.dart';
import '../../apollovm_generated_output.dart';
import '../../apollovm_generator.dart';
import '../../apollovm_parser.dart';
import '../../ast/apollovm_ast_base.dart';
import '../../ast/apollovm_ast_expression.dart';
import '../../ast/apollovm_ast_statement.dart';
import '../../ast/apollovm_ast_toplevel.dart';
import '../../ast/apollovm_ast_type.dart';
import '../../ast/apollovm_ast_value.dart';
import '../../ast/apollovm_ast_variable.dart';
import 'wasm.dart';

final _astTypeInt = ASTTypeInt.instance;
final _astTypeInt32 = ASTTypeInt.instance32;
final _astTypeInt64 = ASTTypeInt.instance64;

final _astTypeDouble = ASTTypeDouble.instance;
//final _astTypeDouble32 = ASTTypeDouble.instance32;
final _astTypeDouble64 = ASTTypeDouble.instance64;

final _astTypeString = ASTTypeString.instance;

/// Wasm binary generator.
///
/// - *NOTE: This is in the alpha stage and cannot fully compile the entire AST tree
/// because WebAssembly (Wasm) is a very basic architecture with no support for strings
/// and other high-level abstractions.*
/// - Yes, full support is currently under development.
class ApolloGeneratorWasm<S extends ApolloCodeUnitStorage<D>, D extends Object>
    extends ApolloGenerator<BytesOutput, S, D> {
  ApolloGeneratorWasm(S codeStorage) : super('wasm', codeStorage);

  @override
  D toStorageData(BytesOutput out) {
    if (D == Uint8List) {
      return out.output() as D;
    } else if (D == BytesOutput) {
      return out as D;
    } else if (D == Object) {
      return out as D;
    } else {
      throw StateError("Can't convert to $D");
    }
  }

  @override
  BytesOutput newOutput() => BytesOutput();

  @override
  BytesOutput generateASTRoot(ASTRoot root, {BytesOutput? out}) {
    out ??= newOutput();

    if (root.extensions.isNotEmpty) {
      throw UnsupportedSyntaxError(
        'Wasm compilation of extensions is not implemented: '
        '${root.extensions.join(', ')}',
      );
    }

    out.write(Wasm.magicModuleHeader, description: "Wasm Magic");
    out.write(Wasm.moduleVersion, description: "Version 1");

    var topFunctions = root.functions.expand((fs) => fs.functions).toList();

    // Synthesize the field layouts and the constructor/method functions for
    // each class, appending them to the module function-index space.
    var classLayouts = <String, WasmClassLayout>{};
    var classFunctions = <ASTFunctionDeclaration>[];
    for (var clazz in root.classes) {
      classLayouts[clazz.name] = _buildClassLayout(clazz);
      classFunctions.addAll(_buildClassFunctions(clazz));
    }

    var baseFunctions = [...topFunctions, ...classFunctions];

    // Anonymous functions / closures: each `ASTExpressionLiteralFunction`
    // becomes a module function with a function-table slot (a function value is
    // the i32 index of its slot, dispatched via `call_indirect`). Wasm needs a
    // concrete signature, so rebuild each with the return/parameter types
    // inferred from the function-typed parameter it is passed to.
    var anon = _collectAnonymousClosures(baseFunctions);
    var anonClosures = anon.closures;

    var functions = [...baseFunctions, ...anonClosures.map((c) => c.function)];
    var module = WasmModuleContext(
      functions,
      classLayouts: classLayouts,
      classDeclarations: {for (var c in root.classes) c.name: c},
    );

    // Register a module global for each `static` field, up front (before any
    // enum-entry global) so global indices are stable. Only literal `int`/
    // `double`/`bool` initializers are seeded; others start at 0.
    for (var clazz in root.classes) {
      for (var field in clazz.fields) {
        if (!field.modifiers.isStatic) continue;
        module.registerStaticFieldGlobal(
          '${clazz.name}.${field.name}',
          field.type,
          _staticFieldInitNum(field),
        );
      }
    }

    for (var c in anonClosures) {
      module.registerClosure(c);
    }
    module.boxedVarsByFunction.addAll(anon.boxedVars);
    module.directClosureVarsByFunction.addAll(anon.directClosureVars);

    // A public function with a String or List parameter requires the host to
    // allocate the argument in module memory, so ensure `__alloc` is exported.
    if (_hasMarshalledParam(module)) {
      module.ensureAllocFunction();
    }

    // A `null` literal is a boxed-`Object` pointer, so unifying it with a
    // concrete value (`c ? 1 : null`, `[1, null, 3]`, `a ?? 99`) boxes that
    // value — which allocates. `__alloc` has to exist before the Code section
    // is written, and the boxing is only discovered while writing it, so look
    // ahead for a `null` in any function body.
    if (_hasNullLiteral(module)) {
      module.ensureAllocFunction();
    }

    // Body-first: generate the Code section first so that body codegen can
    // register host imports and string literals on [module]; the Type/Import/
    // Memory/Data sections below then reflect what was discovered.
    var sectionCode = generateSectionCode(module);

    var sectionType = generateSectionType(module);
    var sectionFunction = generateSectionFunction(module);
    var sectionExports = generateSectionExport(module);

    // Sections must be emitted in ascending ID order.
    out.writeBytes(sectionType, description: "Section: Type");
    if (module.importCount > 0) {
      out.writeBytes(
        generateSectionImport(module),
        description: "Section: Import",
      );
    }
    out.writeBytes(sectionFunction, description: "Section: Function");
    if (module.requiresTable) {
      out.writeBytes(
        generateSectionTable(module),
        description: "Section: Table",
      );
    }
    if (module.requiresMemory) {
      out.writeBytes(
        generateSectionMemory(module),
        description: "Section: Memory",
      );
    }
    if (module.requiresHeapGlobal) {
      out.writeBytes(
        generateSectionGlobal(module),
        description: "Section: Global",
      );
    }
    out.writeBytes(sectionExports, description: "Section: Export");
    if (module.requiresTable) {
      out.writeBytes(
        generateSectionElement(module),
        description: "Section: Element",
      );
    }
    out.writeBytes(sectionCode, description: "Section: Code");
    if (module.hasData) {
      out.writeBytes(generateSectionData(module), description: "Section: Data");
    }
    // Self-describing high-level signatures (custom section) so the runner can
    // marshal String/bool returns/params for modules loaded from raw bytes. Only
    // emitted when a public function involves a String or returns a bool,
    // keeping pure-numeric (int/double) modules byte-identical.
    if (_requiresSignatureSection(module)) {
      out.writeBytes(
        generateSectionCustomSignatures(module),
        description: "Section: Custom (apollovm_sig)",
      );
    }

    return out;
  }

  /// Computes the heap layout of a class instance: instance fields in
  /// declaration order, each at a byte offset (int/double 8B, else 4B i32).
  /// Inherited fields come first (superclass-first, see [_allInstanceFields]),
  /// so an inherited field sits at the same offset on a subclass instance as on
  /// the superclass — a superclass method compiled against the superclass layout
  /// reads/writes the correct slot when invoked on a subclass instance.
  WasmClassLayout _buildClassLayout(ASTClassNormal clazz) {
    var offsets = <String, int>{};
    var types = <String, ASTType>{};
    var offset = 0;
    for (var field in _allInstanceFields(clazz)) {
      // On a name collision keep the first (inherited) declaration's offset.
      if (offsets.containsKey(field.name)) continue;
      offsets[field.name] = offset;
      types[field.name] = field.type;
      offset += _elemSize(field.type);
    }
    // An enum entry is a `const` instance carrying two synthetic fields seeded
    // at build time: `index` (the ordinal, an `int` -> i64/8B) and `name` (a
    // `String` -> i32 ptr/4B). Append them after the declared fields so an entry
    // instance has slots for them (loaded through the regular field-load path).
    if (clazz is ASTClassEnum) {
      if (!offsets.containsKey('index')) {
        offsets['index'] = offset;
        types['index'] = _astTypeInt64;
        offset += _elemSize(_astTypeInt64);
      }
      if (!offsets.containsKey('name')) {
        offsets['name'] = offset;
        types['name'] = _astTypeString;
        offset += _elemSize(_astTypeString);
      }
      // An explicit-value enum (C#/TypeScript `Medium = 5`) exposes the declared
      // integer via `.value`; give it an i64 slot seeded at build time.
      if (clazz.entries.any((e) => e.value != null) &&
          !offsets.containsKey('value')) {
        offsets['value'] = offset;
        types['value'] = _astTypeInt64;
        offset += _elemSize(_astTypeInt64);
      }
    }
    return WasmClassLayout(clazz.name, offsets, types, offset);
  }

  /// All non-static instance fields visible on [clazz], **superclass-first**: a
  /// field declared on the top of the `extends` chain appears before a subclass's
  /// own fields. Duplicates (a subclass field named like an inherited one) keep
  /// the superclass declaration's position; the caller de-dupes by name. Enums
  /// have no superclass, so this returns their declared fields unchanged.
  List<ASTClassField> _allInstanceFields(ASTClassNormal clazz) {
    var chain = <ASTClassNormal>[];
    for (ASTClass? c = clazz; c is ASTClassNormal; c = c.superClass) {
      chain.add(c);
    }
    var result = <ASTClassField>[];
    for (var k = chain.length - 1; k >= 0; k--) {
      for (var field in chain[k].fields) {
        // Statics aren't instance fields.
        if (field.modifiers.isStatic) continue;
        result.add(field);
      }
    }
    return result;
  }

  /// The seed value for a `static` field global: the field's literal `int` /
  /// `double` / `bool` initializer (bool as `0`/`1`), or `0` when there is no
  /// initializer or it is not a compile-time literal.
  num _staticFieldInitNum(ASTClassField field) {
    if (field is ASTClassFieldWithInitialValue) {
      try {
        var v = field.getInitialValueNoContext();
        if (v is ASTValue) {
          var raw = v.getValueNoContext();
          if (raw is bool) return raw ? 1 : 0;
          if (raw is num) return raw;
        }
      } catch (_) {
        // Non-literal initializer: leave the global at 0.
      }
    }
    return 0;
  }

  /// The `"Class.field"` key of a bare `static` field [name] of the current
  /// class (via `context.classLayout`), or `null` if it isn't a static field.
  /// Static members are not inherited in Dart, so this does not walk the
  /// `extends` chain (unlike instance-member resolution).
  String? _staticFieldKey(WasmContext context, String name) {
    var module = context.module;
    var className = context.classLayout?.className;
    if (module == null || className == null) return null;
    var key = '$className.$name';
    return module.staticFieldGlobalIndexOf(key) != null ? key : null;
  }

  /// The virtual-stack type used for a value of [type]: a `bool` is an i32,
  /// otherwise the type itself (`int`↔i64 / `double`↔f64, as elsewhere).
  ASTType _wasmStackTypeFor(ASTType type) =>
      type is ASTTypeBool ? _astTypeInt32 : type;

  /// Synthesizes the module functions for a class: one per constructor (Wasm
  /// signature = the constructor's value params, returns an i32 object pointer)
  /// and one per non-static instance method (`this` prepended as param 0).
  List<ASTFunctionDeclaration> _buildClassFunctions(ASTClassNormal clazz) {
    var result = <ASTFunctionDeclaration>[];

    var constructors = clazz.constructors;
    if (constructors.isEmpty) {
      // Implicit default (zero-arg) constructor: allocate + apply field
      // initializers + return `this`.
      var defaultCtor = ASTClassConstructorDeclaration(
        clazz.type,
        '',
        ASTConstructorParametersDeclaration(null, null, null),
      );
      defaultCtor.parentBlock = clazz;
      defaultCtor.resolveNode(clazz);
      result.add(
        _WasmConstructorFunction(
          clazz,
          defaultCtor,
          ASTFunctionParametersDeclaration([]),
        ),
      );
    }

    for (var ctorSet in constructors) {
      for (var ctor in ctorSet.functions) {
        var params = ctor.parameters.allParameters
            .map(
              (p) => ASTFunctionParameterDeclaration(
                p.type,
                p.name,
                p.index,
                p.optional,
              ),
            )
            .toList();
        result.add(
          _WasmConstructorFunction(
            clazz,
            ctor,
            ASTFunctionParametersDeclaration(params),
          ),
        );
      }
    }

    for (var fnSet in clazz.functions) {
      for (var fn in fnSet.functions) {
        if (fn is! ASTClassFunctionDeclaration) continue;

        if (fn.modifiers.isStatic) {
          // Static method: no `this`. Synthesized as an exported module function
          // under the qualified `Class.method` name, generated like a top-level
          // function (see [_WasmStaticMethodFunction]). The declared parameters
          // are reused directly (as the instance-method path does) so their
          // default values are preserved for default-argument resolution.
          var staticParams = fn.parameters.allParameters.toList();
          result.add(
            _WasmStaticMethodFunction(
              clazz,
              fn,
              '${clazz.name}.${fn.name}',
              ASTFunctionParametersDeclaration(staticParams),
              fn.returnType,
              block: fn,
            ),
          );
          continue;
        }

        var params = <ASTFunctionParameterDeclaration>[
          ASTFunctionParameterDeclaration(clazz.type, 'this', 0, false),
          ...fn.parameters.allParameters,
        ];

        result.add(
          _WasmMethodFunction(
            clazz,
            fn,
            '${clazz.name}.${fn.name}',
            ASTFunctionParametersDeclaration(params),
            fn.returnType,
            block: fn,
          ),
        );
      }
    }

    // Setters have no Wasm lowering yet: an assignment to the property would
    // silently write the backing field instead of running the setter body.
    // Refuse rather than mis-compile.
    if (clazz.setter.isNotEmpty) {
      throw UnsupportedSyntaxError(
        'Wasm compilation of setters is not implemented: '
        '${clazz.name}.${clazz.setter.map((s) => s.name).join(', ')}',
      );
    }

    // User-declared getters (`int get x { ... }`) compile to a zero-argument
    // instance method (`this` is param 0). A getter access then lowers to a
    // 0-arg method call, and an inherited getter resolves through the same
    // superclass-chain method lookup as an inherited method.
    for (var getter in clazz.getter) {
      if (getter is! ASTClassGetterDeclaration) continue;
      if (getter.modifiers.isStatic) continue;
      // A fabricated 0-arg method carrying the getter's name/return type: used
      // only for resolution (`.method.name` / `.parameters.size`); the body is
      // the getter block passed as `block:` below.
      var method = ASTClassFunctionDeclaration(
        clazz,
        getter.name,
        ASTFunctionParametersDeclaration(const []),
        getter.returnType,
      );
      method.clazz = clazz;
      result.add(
        _WasmMethodFunction(
          clazz,
          method,
          '${clazz.name}.${getter.name}',
          ASTFunctionParametersDeclaration([
            ASTFunctionParameterDeclaration(clazz.type, 'this', 0, false),
          ]),
          getter.returnType,
          block: getter,
        ),
      );
    }

    return result;
  }

  /// Type tag used by the `apollovm_sig` custom section.
  /// 0=void, 1=int, 2=double, 3=bool, 4=String, 5=other, 6=list, 7=map.
  static int _typeTag(ASTType t) {
    if (t is ASTTypeVoid) return 0;
    if (t is ASTTypeInt) return 1;
    if (t is ASTTypeDouble) return 2;
    if (t is ASTTypeBool) return 3;
    if (t is ASTTypeString) return 4;
    if (t is ASTTypeArray) return 6;
    if (t is ASTTypeMap) return 7;
    // A plain `num` (TS/JS `number`) is represented as i64 (int), so tag it as
    // int — NOT as `Object` (5), so the host passes a raw i64, not a box.
    if (t is ASTTypeNum) return 1;
    // `Object`/`dynamic` (5) is a *boxed* value the runner must decode. Anything
    // else reaching here is a class instance, whose value is a bare pointer —
    // tagged separately (8) so the runner doesn't try to read it as a box.
    if (_isObjectTypeStatic(t) || t is ASTTypeNull) return 5;
    return 8;
  }

  /// Static form of `_isObjectType`, for use from [_typeTag].
  static bool _isObjectTypeStatic(ASTType t) =>
      t is ASTTypeObject || t is ASTTypeDynamic;

  /// Encodes a type as a descriptor for the `apollovm_sig` section. Scalars are
  /// a single tag byte; a list is `[6, <element tag>]` and a map is
  /// `[7, <key tag>, <value tag>]` so the runner can marshal the whole
  /// collection across the host boundary.
  static List<int> _typeDescriptor(ASTType t) {
    if (t is ASTTypeArray) {
      return [6, _typeTag(t.componentType)];
    }
    if (t is ASTTypeMap) {
      return [7, _typeTag(t.keyType), _typeTag(t.valueType)];
    }
    return [_typeTag(t)];
  }

  /// Whether the module needs the `apollovm_sig` custom section: any public
  /// function with a return/param the runner must marshal from/to its raw Wasm
  /// value — a String, a `bool` return, or a list/map (param or return).
  bool _requiresSignatureSection(WasmModuleContext module) {
    // Real-suspension async functions need the section so the runner knows to
    // drive their unwind/rewind loop.
    if (module.asyncifyFunctionNames.isNotEmpty) return true;
    bool needs(ASTType t) =>
        t is ASTTypeString ||
        t is ASTTypeBool ||
        t is ASTTypeArray ||
        t is ASTTypeMap ||
        _isObjectType(t);
    for (var f in module.functions) {
      if (f.modifiers.isPrivate) continue;
      if (needs(f.effectiveReturnType)) return true;
      for (var p in f.parameters.allParameters) {
        // An `Object`/`dynamic` param must be in the section so the runner
        // knows to pass a host-allocated box (not a raw scalar).
        if (needs(p.type)) return true;
      }
    }
    return false;
  }

  /// Whether any function body contains a `null` literal.
  bool _hasNullLiteral(WasmModuleContext module) {
    bool scan(ASTNode node, int depth) {
      if (node is ASTExpressionNullValue) return true;
      if (depth > 64) return false; // depth guard against a cyclic AST
      for (final child in node.children) {
        if (scan(child, depth + 1)) return true;
      }
      return false;
    }

    for (var f in module.functions) {
      if (scan(f, 0)) return true;
    }
    return false;
  }

  /// Whether any public function has a parameter the host must allocate into
  /// module memory (a String, List, or Map), requiring an exported `__alloc`.
  bool _hasMarshalledParam(WasmModuleContext module) {
    for (var f in module.functions) {
      if (f.modifiers.isPrivate) continue;
      for (var p in f.parameters.allParameters) {
        if (p.type is ASTTypeString ||
            p.type is ASTTypeArray ||
            p.type is ASTTypeMap ||
            _isObjectType(p.type)) {
          // A scalar `Object`/`dynamic` param is passed as a host-allocated box.
          return true;
        }
      }
    }
    return false;
  }

  /// Emits a custom section `apollovm_sig` mapping each public function to its
  /// high-level return/parameter type tags (see [_typeTag]).
  BytesOutput generateSectionCustomSignatures(
    WasmModuleContext module, {
    BytesOutput? out,
  }) {
    out ??= newOutput();

    var publics = module.functions
        .where((f) => !f.modifiers.isPrivate)
        .toList();

    var entries = <BytesOutput>[
      BytesOutput(
        data: Wasm.encodeString('apollovm_sig'),
        description: "Custom section name",
      ),
      BytesOutput(
        data: Leb128.encodeUnsigned(publics.length),
        description: "Function count",
      ),
      ...publics.map((f) {
        var paramDescriptors = f.parameters.allParameters
            .map((p) => _typeDescriptor(p.type))
            .toList();
        return BytesOutput(
          data: [
            ...Wasm.encodeString(f.name),
            ..._typeDescriptor(f.effectiveReturnType),
            ...Leb128.encodeUnsigned(paramDescriptors.length),
            ...paramDescriptors.expand((d) => d),
          ],
          description: "Signature `${f.name}`",
        );
      }),
    ];

    // Trailing, backward-compatible block: the names of Asyncify (real-
    // suspension) functions the runner must drive. Only emitted when present,
    // so non-async modules stay byte-identical; older readers stop after the
    // entries above and ignore it.
    var asyncNames = module.asyncifyFunctionNames;
    if (asyncNames.isNotEmpty) {
      entries.add(
        BytesOutput(
          data: [
            ...Leb128.encodeUnsigned(asyncNames.length),
            for (var n in asyncNames) ...Wasm.encodeString(n),
          ],
          description: "Asyncify functions",
        ),
      );
    }

    out.writeByte(0x00, description: "Section Custom ID");
    out.writeBytesLeb128Block(entries, description: "apollovm_sig");

    return out;
  }

  BytesOutput generateSectionExport(
    WasmModuleContext module, {
    BytesOutput? out,
  }) {
    out ??= newOutput();

    var importCount = module.importCount;
    var functionsIndexed = module.functions
        .mapIndexed((i, f) => MapEntry(f, importCount + i))
        .toList();

    // Anonymous functions (closures) are internal — they are invoked via the
    // function table (`call_indirect`), not by name. Exporting them would emit
    // an entry with an empty name, and two closures would collide on the same
    // empty export name (an invalid module). Skip them.
    var publicFunctions = functionsIndexed
        .where((e) => !e.key.modifiers.isPrivate && !module.isClosure(e.key))
        .toList();

    var entries = publicFunctions.map((f) {
      var fName = f.key.name;
      var fIndex = f.value;

      return BytesOutput(
        data: [
          BytesOutput(
            data: Wasm.encodeString(fName),
            description: "Function name(`$fName`)",
          ),
          BytesOutput(data: 0x00, description: "Export type(function)"),
          BytesOutput(
            data: Leb128.encodeUnsigned(fIndex),
            description: "Type index($fIndex)",
          ),
        ],
        description: "Export function",
      );
    }).toList();

    // Export synthesized functions (e.g. `__alloc`) for host use.
    var synthBase = importCount + module.functions.length;
    for (var j = 0; j < module.synthFunctions.length; ++j) {
      var s = module.synthFunctions[j];
      if (!s.exported) continue;
      entries.add(
        BytesOutput(
          data: [
            BytesOutput(
              data: Wasm.encodeString(s.name),
              description: "Function name(`${s.name}`)",
            ),
            BytesOutput(data: 0x00, description: "Export type(function)"),
            BytesOutput(
              data: Leb128.encodeUnsigned(synthBase + j),
              description: "Function index(${synthBase + j})",
            ),
          ],
          description: "Export synth `${s.name}`",
        ),
      );
    }

    // Export the linear memory (as `memory`) so the host can read/write it.
    if (module.requiresMemory) {
      entries.add(
        BytesOutput(
          data: [
            BytesOutput(
              data: Wasm.encodeString('memory'),
              description: "Memory name(`memory`)",
            ),
            BytesOutput(
              data: Wasm.externalKindMemory,
              description: "Export type(memory)",
            ),
            BytesOutput(
              data: Leb128.encodeUnsigned(0),
              description: "Memory index(0)",
            ),
          ],
          description: "Export memory",
        ),
      );
    }

    entries.insert(
      0,
      BytesOutput(
        data: Leb128.encodeUnsigned(entries.length),
        description: "Exported types count",
      ),
    );

    out.writeByte(Wasm.sectionExport, description: "Section Export ID");
    out.writeBytesLeb128Block(entries, description: "Exported types");

    return out;
  }

  BytesOutput generateSectionType(
    WasmModuleContext module, {
    BytesOutput? out,
  }) {
    out ??= newOutput();

    // Imported-function signatures come first (their type indices 0..K-1),
    // then the module-defined functions, then synthesized functions.
    var entries = <BytesOutput>[
      ...module.importedFunctions.map(
        (imp) => _wasmFuncTypeBytes(imp.params, imp.results),
      ),
      ...module.functions.map((f) {
        // A closure takes a hidden env pointer (i32) as its first parameter and
        // uses the concrete return/parameter types inferred at registration
        // (its declared types may be `dynamic`).
        var info = module.closureInfo(f);
        if (info == null) return f.wasmSignature();
        var params = <WasmType>[
          WasmType.i32Type,
          ...info.paramTypes.map((t) => WasmType.fromValue(t.wasmCode)),
        ];
        var results = info.returnType.isVoid
            ? const <WasmType>[]
            : [WasmType.fromValue(info.returnType.wasmCode)];
        return _wasmFuncTypeBytes(params, results);
      }),
      ...module.synthFunctions.map(
        (s) => _wasmFuncTypeBytes(s.params, s.results),
      ),
    ];

    entries.insert(
      0,
      BytesOutput(
        data: Leb128.encodeUnsigned(entries.length),
        description: "Types count",
      ),
    );

    out.writeByte(Wasm.sectionType, description: "Section Type ID");
    out.writeBytesLeb128Block(entries, description: "Functions signatures");

    return out;
  }

  BytesOutput generateSectionImport(
    WasmModuleContext module, {
    BytesOutput? out,
  }) {
    out ??= newOutput();

    var entries = module.importedFunctions.mapIndexed((typeIndex, imp) {
      return BytesOutput(
        data: [
          BytesOutput(
            data: Wasm.encodeString(imp.module),
            description: "Import module(`${imp.module}`)",
          ),
          BytesOutput(
            data: Wasm.encodeString(imp.name),
            description: "Import name(`${imp.name}`)",
          ),
          BytesOutput(
            data: Wasm.externalKindFunction,
            description: "Import kind(function)",
          ),
          BytesOutput(
            data: Leb128.encodeUnsigned(typeIndex),
            description: "Import type index($typeIndex)",
          ),
        ],
        description: "Import `${imp.module}.${imp.name}`",
      );
    }).toList();

    entries.insert(
      0,
      BytesOutput(
        data: Leb128.encodeUnsigned(entries.length),
        description: "Imports count",
      ),
    );

    out.writeByte(Wasm.sectionImport, description: "Section Import ID");
    out.writeBytesLeb128Block(entries, description: "Imports");

    return out;
  }

  BytesOutput generateSectionFunction(
    WasmModuleContext module, {
    BytesOutput? out,
  }) {
    out ??= newOutput();

    // Each defined function references its type index, offset past the imports;
    // synthesized functions follow the user functions.
    var importCount = module.importCount;
    var n = module.functions.length;
    var indexes = <List<int>>[
      ...module.functions.mapIndexed(
        (i, e) => Leb128.encodeUnsigned(importCount + i),
      ),
      ...module.synthFunctions.mapIndexed(
        (j, s) => Leb128.encodeUnsigned(importCount + n + j),
      ),
    ];

    indexes.insert(0, Leb128.encodeUnsigned(indexes.length));

    out.writeByte(Wasm.sectionFunction, description: "Section Function ID");
    out.writeLeb128Block(indexes, description: "Functions type indexes");

    return out;
  }

  /// Table section: a single `funcref` table holding the module's function
  /// values (closures), sized to the number of table functions.
  BytesOutput generateSectionTable(
    WasmModuleContext module, {
    BytesOutput? out,
  }) {
    out ??= newOutput();

    var size = module.tableFunctions.length;
    var entry = BytesOutput(
      data: [
        BytesOutput(data: Wasm.funcRefType, description: "Elem type funcref"),
        BytesOutput(data: 0x00, description: "Limits flags(min only)"),
        BytesOutput(
          data: Leb128.encodeUnsigned(size),
          description: "Min($size)",
        ),
      ],
      description: "Table 0",
    );

    out.writeByte(Wasm.sectionTable, description: "Section Table ID");
    out.writeBytesLeb128Block([
      BytesOutput(data: Leb128.encodeUnsigned(1), description: "Tables count"),
      entry,
    ], description: "Tables");

    return out;
  }

  /// Element section: one active segment initializing table 0 (from offset 0)
  /// with the function indices of each table function, slot-by-slot.
  BytesOutput generateSectionElement(
    WasmModuleContext module, {
    BytesOutput? out,
  }) {
    out ??= newOutput();

    var funcIndices = module.tableFunctions
        .map(
          (f) => BytesOutput(
            data: Leb128.encodeUnsigned(module.functionIndexByDeclaration(f)),
            description: "Func index",
          ),
        )
        .toList();

    var segment = BytesOutput(
      data: [
        BytesOutput(
          data: Leb128.encodeUnsigned(0),
          description: "Segment flags(active, table 0, offset expr)",
        ),
        BytesOutput(
          data: [...Wasm32.i32Const(0), Wasm.end],
          description: "Offset (i32.const 0)",
        ),
        BytesOutput(
          data: Leb128.encodeUnsigned(funcIndices.length),
          description: "Functions count",
        ),
        ...funcIndices,
      ],
      description: "Element segment 0",
    );

    out.writeByte(Wasm.sectionElement, description: "Section Element ID");
    out.writeBytesLeb128Block([
      BytesOutput(
        data: Leb128.encodeUnsigned(1),
        description: "Segments count",
      ),
      segment,
    ], description: "Elements");

    return out;
  }

  /// Collects anonymous functions (closures) and computes their Wasm layout:
  /// concrete return/parameter types (inferred from the function-typed
  /// parameter each is passed to) and the captured-variable environment.
  ({
    List<WasmClosureInfo> closures,
    Map<ASTFunctionDeclaration, Map<String, ASTType>> boxedVars,
    Map<ASTFunctionDeclaration, Map<String, ASTFunctionDeclaration>>
    directClosureVars,
  })
  _collectAnonymousClosures(List<ASTFunctionDeclaration> baseFunctions) {
    var moduleFnNames = baseFunctions.map((f) => f.name).toSet();

    // The closure function carried by a node: an anonymous-function literal
    // (`(n) => …`) or a named nested function declaration (JS/TS parse
    // `let twice = (n) => …` as a named nested function, not a `var`).
    ASTFunctionDeclaration? closureFnOf(ASTNode node) {
      if (node is ASTExpressionLiteralFunction) return node.function;
      if (node is ASTStatementFunctionDeclaration) {
        return node.functionDeclaration;
      }
      return null;
    }

    // Map each closure to the function type it is passed as, and to the
    // function that lexically encloses it (for resolving captured-var types).
    var expected = <ASTFunctionDeclaration, ASTTypeFunction>{};
    var enclosingOf = <ASTFunctionDeclaration, ASTFunctionDeclaration>{};
    for (var encl in baseFunctions) {
      for (var node in encl.descendantChildren) {
        var cfn = closureFnOf(node);
        if (cfn != null) {
          enclosingOf.putIfAbsent(cfn, () => encl);
        }
        if (node is ASTExpressionLocalFunctionInvocation) {
          var callee = _findModuleFunction(
            baseFunctions,
            node.name,
            node.arguments.length,
          );
          if (callee == null) continue;
          var args = node.arguments;
          for (var i = 0; i < args.length; ++i) {
            var arg = args[i];
            if (arg is ASTExpressionLiteralFunction) {
              var pt = _orderedParamType(callee.parameters, i);
              if (pt is ASTTypeFunction) expected[arg.function] = pt;
            }
          }
        }
        // A returned closure takes its signature from the enclosing function's
        // (concrete) function return type, e.g. `int Function(int) make() { ... }`.
        if (node is ASTStatementReturnWithExpression) {
          var ret = node.expression;
          var enclReturn = encl.returnType;
          if (ret is ASTExpressionLiteralFunction &&
              enclReturn is ASTTypeFunction) {
            expected[ret.function] = enclReturn;
          }
        }
      }
    }

    var result = <WasmClosureInfo>[];
    var boxedVars = <ASTFunctionDeclaration, Map<String, ASTType>>{};
    var seen = <ASTFunctionDeclaration>{};
    for (var encl in baseFunctions) {
      for (var node in encl.descendantChildren) {
        var fn = closureFnOf(node);
        if (fn != null) {
          if (!seen.add(fn)) continue;

          var funcType = expected[fn];
          var paramTypes = _closureParamTypes(fn, funcType);
          var returnType = _closureReturnType(fn, funcType, paramTypes);
          var captures = _closureCaptures(fn, enclosingOf[fn], moduleFnNames);

          // Env struct layout: i32 table slot at offset 0, then one i32 box
          // pointer per capture (capture-by-reference: the env holds pointers to
          // shared heap cells, so mutations are visible across the closure and
          // its enclosing scope).
          var offset = 4;
          var layout = <WasmCapture>[];
          for (var c in captures) {
            layout.add((name: c.name, type: c.type, offset: offset));
            offset += 4;
          }

          // Each captured variable is boxed in its enclosing function.
          var encloser = enclosingOf[fn];
          if (encloser != null) {
            var set = boxedVars.putIfAbsent(encloser, () => {});
            for (var c in captures) {
              set[c.name] = c.type;
            }
          }

          result.add(
            WasmClosureInfo(
              fn,
              returnType,
              paramTypes,
              layout,
              offset,
              result.length,
            ),
          );
        }
      }
    }

    // Optimization: a `var` initialized with a capture-free closure literal and
    // only ever *called* (never read as a value, reassigned, or captured) needs
    // no function value at all — no env heap allocation, no table dispatch. Map
    // each such `enclosing function -> {varName -> closure}` so the declaration
    // can be elided and `v(x)` lowered to a direct `call`.
    var directClosureVars =
        <ASTFunctionDeclaration, Map<String, ASTFunctionDeclaration>>{};
    var captureFree = <ASTFunctionDeclaration>{
      for (var c in result)
        if (c.captures.isEmpty) c.function,
    };
    for (var encl in baseFunctions) {
      for (var node in encl.descendantChildren) {
        // `var f = (n) => …`: a closure literal bound to a call-only variable.
        if (node is ASTStatementVariableDeclaration) {
          var init = node.value;
          if (init is! ASTExpressionLiteralFunction) continue;
          if (!captureFree.contains(init.function)) continue;
          if (!_isClosureVarCallOnly(encl, node.name)) continue;
          (directClosureVars[encl] ??= {})[node.name] = init.function;
        } else if (node is ASTStatementFunctionDeclaration) {
          // `let twice = (n) => …` (JS/TS): a named nested function, called by
          // name. Lowered to a direct `call` just like a call-only closure var.
          var fn = node.functionDeclaration;
          if (!captureFree.contains(fn)) continue;
          if (!_isClosureVarCallOnly(encl, fn.name)) continue;
          (directClosureVars[encl] ??= {})[fn.name] = fn;
        }
      }
    }

    return (
      closures: result,
      boxedVars: boxedVars,
      directClosureVars: directClosureVars,
    );
  }

  /// Whether the local [varName] declared in [encl] is *only* used as the
  /// target of a direct call (`varName(...)`) — never read as a first-class
  /// value (`ASTExpressionVariableAccess`) nor reassigned. A call's callee is a
  /// bare name (not a variable node), so those uses don't appear as accesses.
  bool _isClosureVarCallOnly(ASTFunctionDeclaration encl, String varName) {
    for (var node in encl.descendantChildren) {
      if (node is ASTExpressionVariableAccess &&
          node.variable.name == varName) {
        return false;
      }
      if (node is ASTExpressionVariableAssignment &&
          node.variable.name == varName) {
        return false;
      }
    }
    return true;
  }

  ASTFunctionDeclaration? _findModuleFunction(
    List<ASTFunctionDeclaration> functions,
    String name,
    int arity,
  ) {
    for (var f in functions) {
      if (f.name == name && f.parameters.size == arity) return f;
    }
    return null;
  }

  ASTType _closureReturnType(
    ASTFunctionDeclaration fn,
    ASTTypeFunction? funcType,
    List<ASTType> paramTypes,
  ) {
    var declared = fn.returnType;
    if (declared is! ASTTypeDynamic && !declared.isVoid) return declared;

    if (funcType != null) {
      var generics = funcType.generics;
      if (generics != null && generics.isNotEmpty) {
        var rt = generics.first;
        if (rt is! ASTTypeDynamic && !rt.isVoid) return rt;
      }
    }

    // No typed context (e.g. a closure assigned to a `var` and called directly):
    // infer the return type from the body's `return` expression(s), using the
    // (now concrete) parameter types as the scope.
    var inferred = _inferReturnTypeFromBody(fn, paramTypes);
    if (inferred != null) return inferred;

    if (declared.isVoid) return declared;

    throw UnsupportedError(
      "Wasm: can't infer the return type of an anonymous function. Pass it to a "
      "typed function parameter with a concrete return type, e.g. "
      "`int Function(int n)`.",
    );
  }

  /// Best-effort static inference of an anonymous function's return type from
  /// its body, used when no typed context provides it. Scans the function's
  /// own `return` statements (not nested closures) and infers the expression
  /// type from the parameter types in [paramTypes]. Returns `null` when it
  /// can't be determined statically.
  ASTType? _inferReturnTypeFromBody(
    ASTFunctionDeclaration fn,
    List<ASTType> paramTypes,
  ) {
    var params = fn.parameters.allParameters;
    var scope = <String, ASTType>{};
    for (var i = 0; i < params.length && i < paramTypes.length; ++i) {
      scope[params[i].name] = paramTypes[i];
    }
    for (var stm in fn.statements) {
      if (stm is ASTStatementReturnWithExpression) {
        var t = _inferStaticExpressionType(stm.expression, scope);
        if (t != null) return t;
      }
    }
    return null;
  }

  /// Best-effort static inference of an untyped closure parameter [paramName]
  /// from its use in the body: a parameter that participates in a binary
  /// operation is numeric, taking `double` when the other operand is `double`,
  /// else `int`. Returns `null` when it can't be inferred.
  ASTType? _inferParamTypeFromBody(
    ASTFunctionDeclaration fn,
    String paramName,
  ) {
    bool isParam(ASTExpression e) =>
        e is ASTExpressionVariableAccess && e.variable.name == paramName;
    for (var node in fn.descendantChildren) {
      if (node is! ASTExpressionOperation) continue;
      var e1 = node.expression1, e2 = node.expression2;
      if (!isParam(e1) && !isParam(e2)) continue;
      var other = isParam(e1) ? e2 : e1;
      var t = _inferStaticExpressionType(other, const {});
      return t is ASTTypeDouble ? _astTypeDouble : _astTypeInt;
    }
    return null;
  }

  /// Best-effort static type of [expr] given a [scope] of variable-name -> type
  /// (e.g. a closure's parameters). Handles literals, variable reads and binary
  /// operations — enough for simple arrow bodies (`n * 2`, `n + 1`, `n > 0`).
  /// Returns `null` when the type can't be determined without running the code.
  ASTType? _inferStaticExpressionType(
    ASTExpression expr,
    Map<String, ASTType> scope,
  ) {
    if (expr is ASTExpressionLiteral) {
      var t = expr.value.resolveType(null);
      return t is ASTType ? t : null;
    }
    if (expr is ASTExpressionVariableAccess) {
      return scope[expr.variable.name];
    }
    if (expr is ASTExpressionLogical || expr is ASTExpressionNullCheck) {
      return ASTTypeBool.instance;
    }
    if (expr is ASTExpressionNullCoalesce) {
      // `a ?? b` yields whichever operand survives; `b` is the one that always
      // can, so it is the better single guess.
      return _inferStaticExpressionType(expr.expression2, scope);
    }
    if (expr is ASTExpressionOperation) {
      switch (expr.operator) {
        case ASTExpressionOperator.equals:
        case ASTExpressionOperator.notEquals:
        case ASTExpressionOperator.greater:
        case ASTExpressionOperator.greaterOrEq:
        case ASTExpressionOperator.lower:
        case ASTExpressionOperator.lowerOrEq:
        case ASTExpressionOperator.and:
        case ASTExpressionOperator.or:
          return ASTTypeBool.instance;
        case ASTExpressionOperator.divide:
        case ASTExpressionOperator.divideAsDouble:
          return _astTypeDouble;
        case ASTExpressionOperator.divideAsInt:
          return _astTypeInt;
        default:
          // Arithmetic/bitwise: double if any operand is double, else int.
          var t1 = _inferStaticExpressionType(expr.expression1, scope);
          var t2 = _inferStaticExpressionType(expr.expression2, scope);
          if (t1 is ASTTypeDouble || t2 is ASTTypeDouble) return _astTypeDouble;
          if (t1 is ASTTypeInt && t2 is ASTTypeInt) return _astTypeInt;
          if (t1 is ASTTypeNum) return t1;
          if (t2 is ASTTypeNum) return t2;
          return null;
      }
    }
    return null;
  }

  /// Concrete parameter types for closure [fn]: a declared (typed) parameter
  /// keeps its type; an untyped parameter takes the type from the function-typed
  /// parameter [funcType] (`generics[i + 1]`).
  List<ASTType> _closureParamTypes(
    ASTFunctionDeclaration fn,
    ASTTypeFunction? funcType,
  ) {
    var params = fn.parameters.allParameters;
    var fromType = funcType?.generics;
    var result = <ASTType>[];
    for (var i = 0; i < params.length; ++i) {
      var declared = params[i].type;
      if (declared is! ASTTypeDynamic) {
        result.add(declared);
        continue;
      }
      // generics[0] is the return type; parameter i is generics[i + 1].
      if (fromType != null && fromType.length > i + 1) {
        var t = fromType[i + 1];
        if (t is! ASTTypeDynamic) {
          result.add(t);
          continue;
        }
      }
      // No typed context (e.g. `var f = (n) => n * 2` from C#/Lua/Python where
      // the parameter is untyped): infer the parameter type from how it is used
      // in the body.
      var inferred = _inferParamTypeFromBody(fn, params[i].name);
      if (inferred != null) {
        result.add(inferred);
        continue;
      }
      throw UnsupportedError(
        "Wasm: can't infer the type of parameter `${params[i].name}` of an "
        "anonymous function. Pass it to a typed function parameter, e.g. "
        "`int Function(int n)`.",
      );
    }
    return result;
  }

  /// The free variables captured by closure [fn] (referenced in its body but not
  /// declared as its parameters/locals, nor a module function), paired with the
  /// type they have in the [enclosing] function's scope.
  List<({String name, ASTType type})> _closureCaptures(
    ASTFunctionDeclaration fn,
    ASTFunctionDeclaration? enclosing,
    Set<String> moduleFnNames,
  ) {
    var declared = <String>{};
    for (var p in fn.parameters.allParameters) {
      declared.add(p.name);
    }
    for (var v in fn.statements.declaredVariables()) {
      declared.add(v.key);
    }

    var used = <String>[];
    var usedSet = <String>{};
    for (var node in fn.descendantChildren) {
      if (node is ASTScopeVariable) {
        var name = node.name;
        if (name == 'this' ||
            declared.contains(name) ||
            moduleFnNames.contains(name)) {
          continue;
        }
        if (usedSet.add(name)) used.add(name);
      }
    }

    if (used.isEmpty) return const [];

    // Resolve captured-variable types from the enclosing function's scope.
    var scope = <String, ASTType>{};
    if (enclosing != null) {
      for (var p in enclosing.parameters.allParameters) {
        scope[p.name] = p.type;
      }
      for (var v in enclosing.statements.declaredVariables()) {
        scope[v.key] = v.value;
      }
    }

    var result = <({String name, ASTType type})>[];
    for (var name in used) {
      var type = scope[name];
      if (type == null || type is ASTTypeDynamic) {
        throw UnsupportedError(
          "Wasm: can't capture variable `$name` in a closure (its type isn't "
          "statically known).",
        );
      }
      result.add((name: name, type: type));
    }
    return result;
  }

  BytesOutput generateSectionMemory(
    WasmModuleContext module, {
    BytesOutput? out,
  }) {
    out ??= newOutput();

    // One memory, limits = { min: memoryMinPages } (flags 0x00, no max).
    var entry = BytesOutput(
      data: [
        BytesOutput(data: 0x00, description: "Limits flags(min only)"),
        BytesOutput(
          data: Leb128.encodeUnsigned(module.memoryMinPages),
          description: "Min pages(${module.memoryMinPages})",
        ),
      ],
      description: "Memory 0",
    );

    out.writeByte(Wasm.sectionMemory, description: "Section Memory ID");
    out.writeBytesLeb128Block([
      BytesOutput(
        data: Leb128.encodeUnsigned(1),
        description: "Memories count",
      ),
      entry,
    ], description: "Memories");

    return out;
  }

  BytesOutput generateSectionGlobal(
    WasmModuleContext module, {
    BytesOutput? out,
  }) {
    out ??= newOutput();

    // Global 0 (mutable i32): the heap pointer `$hp`, initialized to heapStart.
    var entries = <BytesOutput>[
      BytesOutput(
        data: [
          BytesOutput(
            data: WasmType.i32Type.value,
            description: "Global type(i32)",
          ),
          BytesOutput(data: Wasm.globalMutable, description: "Mutable"),
          BytesOutput(
            data: [...Wasm32.i32Const(module.heapStart), Wasm.end],
            description: "Init (i32.const ${module.heapStart})",
          ),
        ],
        description: "Global \$hp",
      ),
    ];

    // Static-field globals (mutable, typed by the field): one per `static`
    // field, seeded with its literal initializer. Placed right after `$hp`.
    for (var sf in module.staticFieldGlobals) {
      final int typeByte;
      final List<int> initConst;
      if (sf.type is ASTTypeInt) {
        typeByte = WasmType.i64Type.value;
        initConst = Wasm64.i64Const(sf.init.toInt());
      } else if (sf.type is ASTTypeDouble) {
        typeByte = WasmType.f64Type.value;
        initConst = Wasm64.f64Const(sf.init.toDouble());
      } else {
        // `bool` and reference/other types use an i32 global (0 by default).
        typeByte = WasmType.i32Type.value;
        initConst = Wasm32.i32Const(sf.init.toInt());
      }
      entries.add(
        BytesOutput(
          data: [
            BytesOutput(data: typeByte, description: "Global type"),
            BytesOutput(data: Wasm.globalMutable, description: "Mutable"),
            BytesOutput(
              data: [...initConst, Wasm.end],
              description: "Init (${sf.key} = ${sf.init})",
            ),
          ],
          description: "Static field global `${sf.key}`",
        ),
      );
    }

    // Globals 1..N (mutable i32, init 0): one per enum entry, caching its
    // lazily-built `const` instance pointer (0 = not yet built).
    for (var i = 0; i < module.enumEntryGlobalCount; ++i) {
      entries.add(
        BytesOutput(
          data: [
            BytesOutput(
              data: WasmType.i32Type.value,
              description: "Global type(i32)",
            ),
            BytesOutput(data: Wasm.globalMutable, description: "Mutable"),
            BytesOutput(
              data: [...Wasm32.i32Const(0), Wasm.end],
              description: "Init (i32.const 0)",
            ),
          ],
          description: "Enum entry cache global #${i + 1}",
        ),
      );
    }

    out.writeByte(Wasm.sectionGlobal, description: "Section Global ID");
    out.writeBytesLeb128Block([
      BytesOutput(
        data: Leb128.encodeUnsigned(entries.length),
        description: "Globals count",
      ),
      ...entries,
    ], description: "Globals");

    return out;
  }

  BytesOutput generateSectionData(
    WasmModuleContext module, {
    BytesOutput? out,
  }) {
    out ??= newOutput();

    // One active data segment at memory 0, offset = dataBaseOffset.
    var bytes = module.dataBytes;
    var segment = BytesOutput(
      data: [
        BytesOutput(data: 0x00, description: "Data kind(active, mem 0)"),
        BytesOutput(
          data: [...Wasm32.i32Const(module.dataBaseOffset), Wasm.end],
          description: "Offset expr (i32.const ${module.dataBaseOffset})",
        ),
        BytesOutput(
          data: [...Leb128.encodeUnsigned(bytes.length), ...bytes],
          description: "Data bytes(${bytes.length})",
        ),
      ],
      description: "Data segment 0",
    );

    out.writeByte(Wasm.sectionData, description: "Section Data ID");
    out.writeBytesLeb128Block([
      BytesOutput(
        data: Leb128.encodeUnsigned(1),
        description: "Data segments count",
      ),
      segment,
    ], description: "Data segments");

    return out;
  }

  BytesOutput generateSectionCode(
    WasmModuleContext module, {
    BytesOutput? out,
  }) {
    out ??= newOutput();

    // A function's call indices are `importCount + position`, but host imports
    // (`env.print`, `env.int_to_str`, …) are registered lazily as bodies are
    // generated. A function may call another (or itself) and register an import
    // *after* that call is emitted, which would shift `importCount` and corrupt
    // the already-emitted index. So emit a discovery pass first to register all
    // imports — making `importCount` final — before the real pass. The discovery
    // pass only mutates idempotent module state (imports, interned strings,
    // synth functions), so import-free modules stay byte-identical.
    for (var f in module.functions) {
      _generateModuleFunctionBody(f, module);
    }

    var entries = module.functions
        .map((f) => _generateModuleFunctionBody(f, module))
        .toList();

    // Synth functions (e.g. `__alloc`) registered during user-body codegen.
    // Each body is length-prefixed (like user-function bodies). Bodies are
    // materialized here — after the import-discovery pass above has finalized
    // `importCount` — so a deferred body (e.g. an enum-entry init that calls the
    // enum constructor) bakes in correct function-call indices.
    for (var s in module.synthFunctions) {
      var bodyEntry = newOutput();
      bodyEntry.writeBytesLeb128Block([
        s.materializeBody(),
      ], description: "Synth body `${s.name}`");
      entries.add(bodyEntry);
    }

    entries.insert(
      0,
      BytesOutput(
        data: Leb128.encodeUnsigned(entries.length),
        description: "Bodies count",
      ),
    );

    out.writeByte(Wasm.sectionCode, description: "Section Code ID");
    out.writeBytesLeb128Block(entries, description: "Functions bodies");

    return out;
  }

  /// Generates the code-section body of a single module function, dispatching
  /// to the constructor/method generators for synthesized class functions.
  BytesOutput _generateModuleFunctionBody(
    ASTFunctionDeclaration f,
    WasmModuleContext module,
  ) {
    if (f is _WasmConstructorFunction) {
      return _generateClassConstructorFunction(f, module: module);
    } else if (f is _WasmMethodFunction) {
      return _generateClassMethodFunction(f, module: module);
    } else if (f is _WasmStaticMethodFunction) {
      // A static method has no `this` (params remain locals 0..n-1), but it
      // still belongs to a class: set `classLayout` so an unqualified sibling
      // call can resolve against the enclosing class's static methods.
      var context = WasmContext(module: module);
      context.classLayout = module.classLayouts[f.clazz.name];
      return generateASTFunctionDeclaration(
        f,
        context: context,
        module: module,
      );
    }
    return generateASTFunctionDeclaration(f, module: module);
  }

  /// Builds a Wasm function-type entry `0x60 vec(params) vec(results)`.
  BytesOutput _wasmFuncTypeBytes(
    List<WasmType> params,
    List<WasmType> results,
  ) {
    return BytesOutput(
      data: [
        BytesOutput(data: Wasm.functionType, description: "Type: function"),
        BytesOutput(
          data: [
            ...Leb128.encodeUnsigned(params.length),
            ...params.map((t) => t.value),
          ],
          description: "Params",
        ),
        BytesOutput(
          data: [
            ...Leb128.encodeUnsigned(results.length),
            ...results.map((t) => t.value),
          ],
          description: "Results",
        ),
      ],
      description: "Imported function type",
    );
  }

  ({ASTType type, int index}) _getLocalVariable(
    WasmContext? context,
    String name,
  ) {
    return context?.getLocalVariable(name) ??
        (throw StateError("Can't find local variable `$name` in context."));
  }

  @override
  BytesOutput generateASTBlock(
    ASTBlock block, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();

    for (var set in block.functions) {
      for (var f in set.functions) {
        if (f is ASTClassFunctionDeclaration) {
          generateASTClassFunctionDeclaration(f, out: out);
        } else {
          generateASTFunctionDeclaration(f, out: out, context: context);
        }
      }
    }

    for (var stm in block.statements) {
      generateASTStatement(stm, out: out, context: context);
    }

    return out;
  }

  @override
  BytesOutput generateASTSingleLineStatementBlock(
    ASTSingleLineStatementBlock block, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();

    var stm = block.statements.single;

    return generateASTStatement(stm, out: out, context: context);
  }

  @override
  BytesOutput generateASTBranch(
    ASTBranch branch, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    if (branch is ASTBranchIfBlock) {
      return generateASTBranchIfBlock(branch, out: out, context: context);
    } else if (branch is ASTBranchIfElseBlock) {
      return generateASTBranchIfElseBlock(branch, out: out, context: context);
    } else if (branch is ASTBranchIfElseIfsElseBlock) {
      return generateASTBranchIfElseIfsElseBlock(
        branch,
        out: out,
        context: context,
      );
    }

    throw UnsupportedError("Can't handle branch: $branch");
  }

  @override
  BytesOutput generateASTBranchIfBlock(
    ASTBranchIfBlock branch, {
    BytesOutput? out,
    WasmContext? context,
    int ifElseDepth = 0,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    final stackLng0 = context.stackLength;

    var condition = branch.condition;
    generateASTExpression(condition, out: out, context: context);

    context.assertStackLength(stackLng0 + 1, "After if expression");
    var stackType = context.stackGet(0)!.type;
    if (stackType != _astTypeInt32) {
      throw StateError("Stack type error> not a boolean type: $stackType");
    }

    out.write(
      Wasm.ifInstruction(WasmType.voidType),
      description: "[OP] if ( $condition )",
    );
    context.stackDrop(_astTypeInt32);
    context.controlDepth++;

    generateASTBlock(branch.block, out: out, context: context);

    out.writeByte(Wasm.end, description: "[OP] if end");
    context.controlDepth--;

    return out;
  }

  @override
  BytesOutput generateASTBranchIfElseBlock(
    ASTBranchIfElseBlock branch, {
    BytesOutput? out,
    WasmContext? context,
    int ifElseDepth = 0,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    final stackLng0 = context.stackLength;

    var condition = branch.condition;
    generateASTExpression(condition, out: out, context: context);

    context.assertStackLength(stackLng0 + 1, "After if expression");
    var stackType = context.stackGet(0)!.type;
    if (stackType != _astTypeInt32) {
      throw StateError("Stack type error> not a boolean type: $stackType");
    }

    out.write(
      Wasm.ifInstruction(WasmType.voidType),
      description: "[OP] if ( $condition )",
    );
    context.stackDrop(_astTypeInt32);
    context.controlDepth++;

    generateASTBlock(branch.blockIf, out: out, context: context);

    var blockElse = branch.blockElse;
    if (blockElse != null) {
      out.writeByte(Wasm.elseInstruction, description: "[OP] else");
      generateASTBlock(blockElse, out: out, context: context);
    }

    out.writeByte(Wasm.end, description: "[OP] if else end");
    context.controlDepth--;

    return out;
  }

  @override
  BytesOutput generateASTBranchIfElseIfsElseBlock(
    ASTBranchIfElseIfsElseBlock branch, {
    BytesOutput? out,
    WasmContext? context,
    int ifElseDepth = 0,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    final stackLng0 = context.stackLength;

    var condition = branch.condition;
    generateASTExpression(condition, out: out, context: context);

    context.assertStackLength(stackLng0 + 1, "After if expression");
    var stackType = context.stackGet(0)!.type;
    if (stackType != _astTypeInt32) {
      throw StateError("Stack type error> not a boolean type: $stackType");
    }

    out.write(
      Wasm.ifInstruction(WasmType.voidType),
      description: "[OP] if ( $condition )",
    );
    context.stackDrop(_astTypeInt32);
    context.controlDepth++;

    generateASTBlock(branch.blockIf, out: out, context: context);

    {
      final blocksElseIf = branch.blocksElseIf.toList();
      var blockElse = branch.blockElse;

      if (blocksElseIf.isEmpty) {
        if (blockElse != null) {
          out.writeByte(Wasm.elseInstruction, description: "[OP] else");
          generateASTBlock(blockElse, out: out, context: context);
        }
      } else {
        var blocksElseIf0 = blocksElseIf.removeAt(0);

        out.writeByte(Wasm.elseInstruction, description: "[OP] else");

        if (blocksElseIf.isEmpty) {
          generateASTBranchIfElseBlock(
            ASTBranchIfElseBlock(
              blocksElseIf0.condition,
              blocksElseIf0.block,
              blockElse,
            ),
            out: out,
            context: context,
            ifElseDepth: ifElseDepth + 1,
          );
        } else {
          generateASTBranchIfElseIfsElseBlock(
            ASTBranchIfElseIfsElseBlock(
              blocksElseIf0.condition,
              blocksElseIf0.block,
              blocksElseIf,
              blockElse,
            ),
            out: out,
            context: context,
            ifElseDepth: ifElseDepth + 1,
          );
        }
      }
    }

    out.writeByte(Wasm.end, description: "[OP] if else end");
    context.controlDepth--;

    return out;
  }

  @override
  BytesOutput generateASTStatementImport(
    ASTStatementImport import, {
    BytesOutput? out,
  }) {
    // TODO: implement generateASTStatementImport
    throw UnimplementedError("generateASTStatementImport");
  }

  @override
  BytesOutput generateASTClass(ASTClassNormal clazz, {BytesOutput? out}) {
    // TODO: implement generateASTClass
    throw UnimplementedError('generateASTClass');
  }

  @override
  BytesOutput generateASTClassField(ASTClassField field, {BytesOutput? out}) {
    // TODO: implement generateASTClassField
    throw UnimplementedError('generateASTClassField');
  }

  @override
  BytesOutput generateASTClassConstructorDeclaration(
    ASTClassConstructorDeclaration<dynamic> constructor, {
    BytesOutput? out,
  }) {
    // TODO: implement generateASTClassConstructorDeclaration
    throw UnimplementedError("generateASTClassConstructorDeclaration");
  }

  @override
  BytesOutput generateASTClassFunctionDeclaration(
    ASTClassFunctionDeclaration f, {
    BytesOutput? out,
  }) {
    // TODO: implement generateASTClassFunctionDeclaration
    throw UnimplementedError('generateASTClassField');
  }

  @override
  BytesOutput generateASTExpressionFunctionInvocation(
    ASTExpressionObjectFunctionInvocation expression, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    var varName = expression.variable.name;

    // `super.method(args)`: the receiver is the current instance (`this`), but
    // method dispatch starts at the enclosing class's superclass (so an override
    // in the current class is skipped — `super` reaches the inherited one).
    if (varName == 'super') {
      var thisVar = context.getLocalVariable('this');
      var superName = context.module?.superClassNameOf(
        context.classLayout?.className,
      );
      if (thisVar != null && superName != null) {
        return _emitClassMethodCall(
          recv: thisVar,
          receiverDesc: 'super',
          methodName: expression.name,
          arguments: expression.arguments,
          namedArguments: expression.namedArguments,
          resolveClassName: superName,
          out: out,
          context: context,
        );
      }
    }

    var localVar = _getLocalVariable(context, varName);

    // List.add(x)
    if (localVar.type is ASTTypeArray &&
        expression.name == 'add' &&
        expression.arguments.length == 1) {
      return _generateListAdd(
        localVar,
        expression.arguments[0],
        out: out,
        context: context,
      );
    }

    // Map.containsKey(k)
    if (localVar.type is ASTTypeMap &&
        expression.name == 'containsKey' &&
        expression.arguments.length == 1) {
      return _generateMapContainsKey(
        expression,
        localVar,
        out: out,
        context: context,
      );
    }

    // String.toUpperCase() / toLowerCase() (ASCII).
    if (localVar.type is ASTTypeString &&
        expression.arguments.isEmpty &&
        (expression.name == 'toUpperCase' ||
            expression.name == 'toLowerCase')) {
      return _generateStringCaseConvert(
        localVar,
        varName,
        upper: expression.name == 'toUpperCase',
        out: out,
        context: context,
      );
    }

    // Other String methods (ASCII/UTF-8 byte ops over the `[len][utf8]` layout):
    // substring, codeUnitAt, startsWith, endsWith, indexOf, contains.
    if (localVar.type is ASTTypeString) {
      var handled = _tryGenerateStringMethod(
        expression,
        localVar,
        varName,
        out: out,
        context: context,
      );
      if (handled != null) return handled;
    }

    // Instance method call on a class: `recv.method(args)`.
    if (context.module?.layoutForType(localVar.type) != null) {
      return _generateMethodInvocation(
        expression,
        localVar,
        out: out,
        context: context,
      );
    }

    throw UnimplementedError(
      "Wasm method `.${expression.name}` on ${localVar.type} "
      "is not supported yet.",
    );
  }

  /// Lowers `recv.method(args)` to a call of the synthesized method function
  /// (`this` passed as the first argument).
  BytesOutput _generateMethodInvocation(
    ASTExpressionObjectFunctionInvocation expression,
    ({ASTType type, int index}) recvVar, {
    required BytesOutput out,
    required WasmContext context,
  }) {
    return _emitClassMethodCall(
      recv: recvVar,
      receiverDesc: expression.variable.name,
      methodName: expression.name,
      arguments: expression.arguments,
      namedArguments: expression.namedArguments,
      out: out,
      context: context,
    );
  }

  /// Emits a call to class [methodName] on the receiver local [recv] (passed as
  /// the first argument, `this`), used by both `recv.method(args)` and the
  /// implicit-`this` `method(args)` inside another method.
  BytesOutput _emitClassMethodCall({
    required ({ASTType type, int index}) recv,
    required String receiverDesc,
    required String methodName,
    required List<ASTExpression> arguments,
    Map<String, ASTExpression>? namedArguments,
    String? resolveClassName,
    required BytesOutput out,
    required WasmContext context,
  }) {
    var module = context.module!;
    // For `super.m()` the receiver stays the current instance but dispatch
    // starts at the enclosing class's superclass ([resolveClassName]).
    var className = resolveClassName ?? recv.type.name;
    // Supplied arity = positional + named. A call may omit trailing parameters
    // that have default values, so this can be less than the method's declared
    // arity; resolve at the declared arity (Wasm methods are fixed-arity).
    var suppliedCount = arguments.length + (namedArguments?.length ?? 0);

    var calleeIndex = module.methodIndexForCall(
      className,
      methodName,
      suppliedCount,
    );
    if (calleeIndex == null) {
      throw StateError(
        "Can't resolve method `$className.$methodName` with $suppliedCount "
        "argument(s).",
      );
    }
    var callee = module.functionByIndex(calleeIndex) as _WasmMethodFunction;

    // Reorder/merge named arguments into the method's positional order and fill
    // omitted parameters that have defaults (no-op for purely-positional calls
    // that already cover all declared parameters). The resulting list has length
    // equal to the method's DECLARED arity.
    var orderedArgs = _orderInvocationArguments(
      arguments,
      namedArguments,
      callee.method.parameters,
      '$className.$methodName',
    );
    var arity = orderedArgs.length;

    final stackLng0 = context.stackLength;

    // Receiver (`this`) is the first argument.
    _localVariableGet(out, context, recv.index, receiverDesc);
    context.stackPush(recv.type, "receiver `$receiverDesc`");

    for (var i = 0; i < arity; ++i) {
      var stackBefore = context.stackLength;
      generateASTExpression(orderedArgs[i], out: out, context: context);
      context.assertStackLength(stackBefore + 1, "After method arg[$i]");

      var paramType = _orderedParamType(callee.method.parameters, i);
      if (paramType != null) {
        _autoConvertStackTypes(
          context.stackGet(0)!.type,
          paramType,
          out: out,
          context: context,
        );
      }
    }

    out.write(
      Wasm.call(calleeIndex),
      description: "[OP] call `$className.$methodName` (index $calleeIndex)",
    );

    for (var i = 0; i < arity + 1; ++i) {
      context.stackDrop();
    }

    var returnType = callee.method.returnType;
    if (!returnType.isVoid) {
      ASTType resultType;
      if (returnType is ASTTypeInt) {
        resultType = _astTypeInt64;
      } else if (returnType is ASTTypeDouble) {
        resultType = _astTypeDouble64;
      } else {
        resultType = returnType;
      }
      context.stackPush(resultType, "method `$methodName` result");
    }

    context.assertStackLength(
      stackLng0 + (returnType.isVoid ? 0 : 1),
      "After method `$methodName`",
    );
    return out;
  }

  /// `m.containsKey(k)`: linear scan, pushes an i32 bool (1 found / 0 absent).
  BytesOutput _generateMapContainsKey(
    ASTExpressionObjectFunctionInvocation expression,
    ({ASTType type, int index}) mapVar, {
    required BytesOutput out,
    required WasmContext context,
  }) {
    var mapType = _requireMapType(
      mapVar.type,
      expression.variable.name,
      'containsKey',
    );
    var keyType = mapType.keyType;

    var hdr = context.scratchLocal(_astTypeString, 15);
    var keys = context.scratchLocal(_astTypeString, 16);
    var iLoc = context.scratchLocal(_astTypeString, 18);
    var keyLoc = context.scratchLocal(keyType, 19); // i64 (int) or i32 (String)
    var found = context.scratchLocal(_astTypeString, 21);

    final s0 = context.stackLength;

    _localVariableGet(out, context, mapVar.index, expression.variable.name);
    out.write(Wasm.localSet(hdr));
    generateASTExpression(expression.arguments[0], out: out, context: context);
    context.stackDrop();
    out.write(Wasm.localSet(keyLoc));
    out.write(Wasm32.i32Const(0));
    out.write(Wasm.localSet(found));

    _emitMapScan(
      out,
      context,
      keyType: keyType,
      hdrScratch: hdr,
      keysScratch: keys,
      iScratch: iLoc,
      keyScratch: keyLoc,
      onMatch: () {
        out.write(Wasm32.i32Const(1));
        out.write(Wasm.localSet(found));
      },
    );

    out.write(Wasm.localGet(found));
    context.stackPush(_astTypeInt32, "containsKey"); // bool as i32
    context.assertStackLength(s0 + 1, "After containsKey");
    return out;
  }

  /// `list.add(x)`: appends to the growable list, reallocating the data buffer
  /// (and updating the header's capacity/dataPtr in place) when full. Emits no
  /// result (treated as void).
  BytesOutput _generateListAdd(
    ({ASTType type, int index}) listVar,
    ASTExpression argExpr, {
    required BytesOutput out,
    required WasmContext context,
  }) {
    var module = context.module!;
    module.requiresMemory = true;
    module.requiresHeapGlobal = true;

    var elemType = (listVar.type as ASTTypeArray).componentType;
    var size = _elemSize(elemType);

    var hdr = context.scratchLocal(_astTypeString, 11);
    var len = context.scratchLocal(_astTypeString, 12);
    var newCap = context.scratchLocal(_astTypeString, 13);
    var newData = context.scratchLocal(_astTypeString, 14);

    // $hdr = list header pointer
    _localVariableGet(out, context, listVar.index, 'list');
    out.write(Wasm.localSet(hdr));
    // $len = length
    out.write(Wasm.localGet(hdr));
    out.write(Wasm32.i32Load(2, 0));
    out.write(Wasm.localSet(len));

    // if (len == capacity) grow the data buffer
    out.write(Wasm.localGet(len));
    out.write(Wasm.localGet(hdr));
    out.write(Wasm32.i32Load(2, 4)); // capacity
    out.writeByte(Wasm32.i32Equals);
    out.write(Wasm.ifInstruction(WasmType.voidType));
    {
      // newCap = capacity * 2; if 0 -> 4
      out.write(Wasm.localGet(hdr));
      out.write(Wasm32.i32Load(2, 4));
      out.write(Wasm32.i32Const(2));
      out.writeByte(Wasm32.i32Multiply);
      out.write(Wasm.localSet(newCap));
      out.write(Wasm.localGet(newCap));
      out.writeByte(Wasm32.i32EqualsToZero);
      out.write(Wasm.ifInstruction(WasmType.voidType));
      out.write(Wasm32.i32Const(4));
      out.write(Wasm.localSet(newCap));
      out.writeByte(Wasm.end);

      // newData = __alloc(newCap * size)
      out.write(Wasm.localGet(newCap));
      out.write(Wasm32.i32Const(size));
      out.writeByte(Wasm32.i32Multiply);
      _emitInlineAlloc(out, context);
      out.write(Wasm.localSet(newData));

      // memory.copy(newData, oldData, len*size)
      out.write(Wasm.localGet(newData));
      out.write(Wasm.localGet(hdr));
      out.write(Wasm32.i32Load(2, 8)); // old dataPtr
      out.write(Wasm.localGet(len));
      out.write(Wasm32.i32Const(size));
      out.writeByte(Wasm32.i32Multiply);
      out.write(Wasm.memoryCopy);

      // header.capacity = newCap; header.dataPtr = newData
      out.write(Wasm.localGet(hdr));
      out.write(Wasm.localGet(newCap));
      out.write(Wasm32.i32Store(2, 4));
      out.write(Wasm.localGet(hdr));
      out.write(Wasm.localGet(newData));
      out.write(Wasm32.i32Store(2, 8));
    }
    out.writeByte(Wasm.end);

    // store x at dataPtr + len*size
    out.write(Wasm.localGet(hdr));
    out.write(Wasm32.i32Load(2, 8)); // dataPtr
    out.write(Wasm.localGet(len));
    out.write(Wasm32.i32Const(size));
    out.writeByte(Wasm32.i32Multiply);
    out.writeByte(Wasm32.i32Add); // store address
    generateASTExpression(argExpr, out: out, context: context); // value
    context.stackDrop();
    _emitElemStore(out, elemType, 0);

    // header.length = len + 1
    out.write(Wasm.localGet(hdr));
    out.write(Wasm.localGet(len));
    out.write(Wasm32.i32Const(1));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm32.i32Store(2, 0));

    return out;
  }

  @override
  BytesOutput generateASTExpressionObjectEntryFunctionInvocation(
    ASTExpressionObjectEntryFunctionInvocation expression, {
    BytesOutput? out,
  }) {
    // TODO: implement generateASTExpressionObjectEntryFunctionInvocation
    throw UnimplementedError(
      "generateASTExpressionObjectEntryFunctionInvocation",
    );
  }

  // === Lists =========================================================
  //
  // A list value is an i32 pointer to `[length:i32][capacity:i32][elements…]`
  // in linear memory. Element storage: int -> i64 (8B), double -> f64 (8B),
  // String/bool -> i32 (4B). Slice 1 supports int/double element lists.

  /// List header: `[length:i32][capacity:i32][dataPtr:i32]`.
  static const int _listHeaderSize = 12;

  int _elemSize(ASTType elemType) =>
      (elemType is ASTTypeInt || elemType is ASTTypeDouble) ? 8 : 4;

  // Scratch-local slot numbers for a collection literal's header/buffer locals,
  // parameterized by nesting [depth]. Depth 0 keeps the original slots (6/9 for
  // a list; 15/16/17 for a map) so single-level literals stay byte-identical;
  // deeper levels use a disjoint high range (lists and maps in separate bands)
  // so a nested literal never aliases the enclosing one's locals.
  int _listHdrSlot(int depth) => depth == 0 ? 6 : 200 + depth * 2;
  int _listDataSlot(int depth) => depth == 0 ? 9 : 201 + depth * 2;
  int _mapHdrSlot(int depth) => depth == 0 ? 15 : 400 + depth * 3;
  int _mapKeysSlot(int depth) => depth == 0 ? 16 : 401 + depth * 3;
  int _mapValsSlot(int depth) => depth == 0 ? 17 : 402 + depth * 3;

  /// A class-instance reference: an i32 pointer to a heap struct.
  bool _isWasmObjectRef(ASTType t) => t is ASTType<VMObject>;

  /// The static `Object`/`dynamic` type (the root types). Such a value has no
  /// single Wasm representation, so it is *boxed*: an i32 pointer to a 16-byte
  /// heap cell `[tag:i32 @0][typeId:i32 @4][payload:8 @8]` (see [_boxTagInt] ..
  /// [_boxTagInstance]). A concrete class type stays a bare instance pointer.
  bool _isObjectType(ASTType t) => t is ASTTypeObject || t is ASTTypeDynamic;

  /// Whether a slot of type [t] can hold the Wasm `null` (the boxed-`Object`
  /// pointer 0). `var` counts: its type is inferred from the initializer, which
  /// for a `null`-bearing expression resolves to a boxed `Object`.
  bool _acceptsWasmNull(ASTType t) => _isObjectType(t) || t is ASTTypeVar;

  /// Whether a slot of type [t] holds a boxed-`Object` pointer at runtime — the
  /// only representation that can *be* Wasm's `null`.
  ///
  /// `Null` counts: `var x = null` infers the slot as `Null`, and it is stored
  /// as the null box pointer, which is why [_typeTag] already groups it with
  /// `Object`/`dynamic`.
  bool _isBoxedSlot(ASTType t) => _isObjectType(t) || t is ASTTypeNull;

  // Boxed-`Object` tags (must match `wasm_runner.dart`'s `_boxTag*`).
  static const int _boxTagInt = 1;
  static const int _boxTagDouble = 2;
  static const int _boxTagBool = 3;
  static const int _boxTagString = 4;
  static const int _boxTagInstance = 5;

  /// The boxed-`Object` pointer representing `null`.
  ///
  /// The heap never allocates at address 0, so 0 is a free sentinel: `null`
  /// needs no cell, and any real box compares unequal to it. Must match
  /// `wasm_runner.dart`'s `_boxPtrNull`.
  static const int _boxPtrNull = 0;

  // Boxed-`Object` cell layout (16 bytes).
  static const int _boxSize = 16;
  static const int _boxTagOffset = 0;
  static const int _boxTypeIdOffset = 4;
  static const int _boxPayloadOffset = 8;

  void _emitElemStore(BytesOutput out, ASTType elemType, int offset) {
    if (elemType is ASTTypeInt) {
      out.write(Wasm64.i64Store(3, offset));
    } else if (elemType is ASTTypeDouble) {
      out.write(Wasm64.f64Store(FloatAlign.align3, offset));
    } else if (elemType is ASTTypeString ||
        elemType is ASTTypeBool ||
        elemType is ASTTypeArray ||
        elemType is ASTTypeMap ||
        _isObjectType(elemType) ||
        _isWasmObjectRef(elemType)) {
      out.write(Wasm32.i32Store(2, offset));
    } else {
      throw UnimplementedError("Wasm element/field store for $elemType");
    }
  }

  void _emitElemLoad(BytesOutput out, ASTType elemType, int offset) {
    if (elemType is ASTTypeInt) {
      out.write(Wasm64.i64Load(3, offset));
    } else if (elemType is ASTTypeDouble) {
      out.write(Wasm64.f64Load(FloatAlign.align3, offset));
    } else if (elemType is ASTTypeString ||
        elemType is ASTTypeBool ||
        elemType is ASTTypeArray ||
        elemType is ASTTypeMap ||
        _isObjectType(elemType) ||
        _isWasmObjectRef(elemType)) {
      out.write(Wasm32.i32Load(2, offset));
    } else {
      throw UnimplementedError("Wasm element/field load for $elemType");
    }
  }

  ASTType _elemStackType(ASTType elemType) {
    if (elemType is ASTTypeInt) return _astTypeInt64;
    if (elemType is ASTTypeDouble) return _astTypeDouble64;
    if (elemType is ASTTypeString) return _astTypeString;
    if (elemType is ASTTypeBool) return _astTypeInt32; // bool as i32
    return elemType;
  }

  /// Element types that compile to Wasm list storage: `int`/`double` (8B),
  /// `String`/`bool` (4B i32), and a **nested collection** (`List`/`Map`, stored
  /// as a 4B i32 pointer to the inner header). Other element types are
  /// unsupported.
  bool _isSupportedElemType(ASTType t) =>
      t is ASTTypeInt ||
      t is ASTTypeDouble ||
      t is ASTTypeString ||
      t is ASTTypeBool ||
      t is ASTTypeArray ||
      t is ASTTypeMap;

  @override
  BytesOutput generateASTExpressionListLiteral(
    ASTExpressionListLiteral expression, {
    BytesOutput? out,
    WasmContext? context,
    ASTType? elementTypeOverride,
  }) {
    out ??= newOutput();
    context ??= WasmContext();
    var module = context.module;
    if (module == null) {
      throw StateError("Can't build a list without a module.");
    }
    module.requiresMemory = true;
    module.requiresHeapGlobal = true;

    var elemType = expression.type;
    if (elemType == null) {
      var rt = expression.resolveType(null);
      elemType = rt is ASTTypeArray
          ? rt.componentType
          : ASTTypeDynamic.instance;
    }
    // When the literal flows into a `List<Object>`/`List<dynamic>` slot, the
    // consumer reads boxed i32 elements regardless of the literal's own inferred
    // element type. Honor that target so a *homogeneous* literal (e.g. the
    // inferred `List<int>` of `[1, 2, 3]`) boxes its elements instead of storing
    // unboxed 8-byte values the reader would misread (stride/representation
    // mismatch -> garbage or an out-of-bounds trap).
    if (elementTypeOverride != null && _isObjectType(elementTypeOverride)) {
      elemType = elementTypeOverride;
    }
    // `List<Object>`/`List<dynamic>` literals box each element (mixed types);
    // other element types must compile to a direct storage slot.
    var boxElements = _isObjectType(elemType);
    if (!boxElements && !_isSupportedElemType(elemType)) {
      throw UnimplementedError(
        "Wasm list literal of element type $elemType is not supported yet.",
      );
    }

    var size = _elemSize(elemType);
    var values = expression.valuesExpressions;
    var n = values.length;
    // Indirect layout: header [length@0][capacity@4][dataPtr@8]; elements live
    // in a separate buffer so `.add` can realloc without moving the handle.
    // Depth-offset the scratch slots so a nested list literal (an element that is
    // itself a `List`/`Map`) doesn't alias this literal's header/data locals.
    var depth = context.collectionLiteralDepth;
    var hdrLocal = context.scratchLocal(_astTypeString, _listHdrSlot(depth));
    var dataLocal = context.scratchLocal(_astTypeString, _listDataSlot(depth));
    context.collectionLiteralDepth = depth + 1;

    final s0 = context.stackLength;

    // header = alloc(12)
    out.write(Wasm32.i32Const(_listHeaderSize));
    _emitInlineAlloc(out, context);
    out.write(Wasm.localSet(hdrLocal));
    // data = alloc(n*size)
    out.write(Wasm32.i32Const(n * size));
    _emitInlineAlloc(out, context);
    out.write(Wasm.localSet(dataLocal));

    // header fields: length=n, capacity=n, dataPtr=data
    out.write(Wasm.localGet(hdrLocal));
    out.write(Wasm32.i32Const(n));
    out.write(Wasm32.i32Store(2, 0));
    out.write(Wasm.localGet(hdrLocal));
    out.write(Wasm32.i32Const(n));
    out.write(Wasm32.i32Store(2, 4));
    out.write(Wasm.localGet(hdrLocal));
    out.write(Wasm.localGet(dataLocal));
    out.write(Wasm32.i32Store(2, 8));

    // elements at data + i*size
    for (var i = 0; i < n; ++i) {
      out.write(Wasm.localGet(dataLocal)); // store base address
      generateASTExpression(values[i], out: out, context: context);
      if (boxElements) {
        _emitBoxValue(out, context); // concrete value -> Object box ptr
      } else {
        // A boxed `Object` element flowing into a typed numeric list must be
        // unboxed to match the i64/f64 slot.
        _coerceBoxedToNumberSlot(out, context, elemType);
      }
      context.stackDrop(); // value consumed by the store
      _emitElemStore(out, elemType, i * size);
    }

    context.collectionLiteralDepth = depth;

    // list handle (the header pointer)
    out.write(Wasm.localGet(hdrLocal));
    context.stackPush(ASTTypeArray(elemType), "list literal");

    context.assertStackLength(s0 + 1, "After list literal");
    return out;
  }

  @override
  BytesOutput generateASTExpressionLiteral(
    ASTExpressionLiteral expression, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    var value = expression.value;

    var stackLng0 = context.stackLength;

    generateASTValue(value, out: out, context: context);

    context.assertStackLength(
      stackLng0 + 1,
      "After expression literal value push",
    );

    return out;
  }

  /// Merges an invocation's positional and named arguments into the single
  /// positional order expected by the callee (Wasm calls are positional at the
  /// bytecode level).
  ///
  /// When [named] is null/empty AND the [positional] args already cover every
  /// declared parameter, the original [positional] list is returned unchanged,
  /// so the purely-positional path stays byte-for-byte identical.
  ///
  /// Otherwise, walks the callee's declared parameters in order (positional +
  /// optional + named) and, for each parameter index `i`, uses `positional[i]`
  /// when present, else the named argument bound to that parameter's name, else
  /// the parameter's `defaultValue` expression when it has one (Wasm functions
  /// are fixed-arity, so an omitted slot with a default is filled with that
  /// default's expression and emitted by the normal per-argument codegen).
  ///
  /// A parameter that is neither supplied nor defaulted is a genuinely missing
  /// required argument and throws a clear [StateError]. The returned list always
  /// has length equal to the number of declared parameters.
  List<ASTExpression> _orderInvocationArguments(
    List<ASTExpression> positional,
    Map<String, ASTExpression>? named,
    ASTParametersDeclaration parameters,
    String calleeDesc,
  ) {
    var paramDecls = parameters.allParameters;

    // Fast path: purely-positional and already covering all declared
    // parameters (no named args, no omitted/default slots) -> unchanged.
    if ((named == null || named.isEmpty) &&
        positional.length == paramDecls.length) {
      return positional;
    }

    var ordered = <ASTExpression>[];
    for (var i = 0; i < paramDecls.length; ++i) {
      var p = paramDecls[i];

      // Positional argument supplied for this slot.
      if (i < positional.length) {
        ordered.add(positional[i]);
        continue;
      }

      // Named argument bound to this parameter's name.
      var arg = named?[p.name];
      if (arg != null) {
        ordered.add(arg);
        continue;
      }

      // Omitted slot: fill with the parameter's default value expression.
      var defaultValue = p.defaultValue;
      if (defaultValue != null) {
        // The default is emitted by the normal per-argument codegen in the
        // CALLER's WasmContext, which is only correct for constant defaults.
        // A non-constant default (referencing another parameter, `this`, a
        // field or a function call) would resolve against the caller's frame
        // (wrong codegen), diverging from the interpreter which evaluates
        // defaults in the callee scope.
        if (!_isWasmConstDefault(defaultValue)) {
          throw StateError(
            "Wasm: can't bind call to `$calleeDesc`: parameter `${p.name}` has "
            "a non-constant default value (`$defaultValue`). Only constant "
            "defaults (literals and arithmetic over literals) are supported in "
            "Wasm.",
          );
        }
        ordered.add(defaultValue);
        continue;
      }

      throw StateError(
        "Wasm: can't bind call to `$calleeDesc`: parameter `${p.name}` has no "
        "matching positional or named argument and no default value.",
      );
    }

    return ordered;
  }

  /// The declared parameter type for the ordered/pushed argument slot [i].
  ///
  /// Argument lists produced by [_orderInvocationArguments] follow
  /// `parameters.allParameters` (positional + optional + named, in declaration
  /// order). [ASTParametersDeclaration.getParameterByIndex] returns `null` for
  /// named-declared (`{...}`) slots, which would skip type-conversion for those
  /// arguments; indexing [allParameters] keeps the slot/type alignment. For a
  /// positional-only call `allParameters[i]` equals the old
  /// `getParameterByIndex(i)` for `i` in range.
  ASTType? _orderedParamType(ASTParametersDeclaration p, int i) {
    var all = p.allParameters;
    return i < all.length ? all[i].type : null;
  }

  /// Whether [e] is a Wasm-safe CONSTANT default expression: built only from
  /// literals and operations/negations over such literals. Returns `false` if
  /// it references any variable, `this`, field or function call (which the
  /// interpreter would evaluate in the callee scope — see [BUG #3]).
  bool _isWasmConstDefault(ASTExpression e) {
    if (e is ASTExpressionLiteral) return true;
    if (e is ASTExpressionOperation) {
      return _isWasmConstDefault(e.expression1) &&
          _isWasmConstDefault(e.expression2);
    }
    if (e is ASTExpressionNegation) {
      return _isWasmConstDefault(e.expression);
    }
    if (e is ASTExpressionNegative) {
      return _isWasmConstDefault(e.expression);
    }
    if (e is ASTExpressionBitwiseNot) {
      return _isWasmConstDefault(e.expression);
    }
    return false;
  }

  @override
  BytesOutput generateASTExpressionLocalFunctionInvocation(
    ASTExpressionLocalFunctionInvocation expression, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    var name = expression.name;
    var positionalArgs = expression.arguments;
    var namedArgs = expression.namedArguments;
    var arguments = positionalArgs;
    // Total arity = positional + named; used to resolve the callee (Wasm
    // functions are positional/fixed-arity at the bytecode level).
    var argsCount = positionalArgs.length + (namedArgs?.length ?? 0);

    // Built-in external `print(Object)` lowers to a host import call.
    if (name == 'print' && argsCount == 1) {
      return _generatePrintInvocation(expression, out: out, context: context);
    }

    // A capture-free, call-only closure — a `var f = (n) => …` or a named
    // nested function (`let f = (n) => …` parsed as a function declaration) — is
    // lowered directly to a `call` of the closure function (its env parameter is
    // unused, so a null env is passed), skipping the env allocation and
    // `call_indirect`. Checked before the module-function table because a named
    // nested closure is *also* a module function, but its true signature takes
    // the hidden env parameter.
    var directFn = context.directClosureVars[name];
    if (directFn != null) {
      return _emitDirectClosureCall(
        expression,
        directFn,
        out: out,
        context: context,
      );
    }

    // Resolve at the callee's DECLARED arity: a call may omit trailing
    // parameters that have default values, so the supplied [argsCount] can be
    // less than the registered (declared) arity.
    var calleeIndex = context.functionIndexForCall(name, argsCount);
    if (calleeIndex == null) {
      // Inside a method, an unqualified call is an implicit-`this` method call
      // (`foo()` == `this.foo()`).
      var layout = context.classLayout;
      var thisVar = context.getLocalVariable('this');
      if (layout != null &&
          thisVar != null &&
          context.module?.methodIndexForCall(
                layout.className,
                name,
                argsCount,
              ) !=
              null) {
        return _emitClassMethodCall(
          recv: thisVar,
          receiverDesc: 'this',
          methodName: name,
          arguments: positionalArgs,
          namedArguments: namedArgs,
          out: out,
          context: context,
        );
      }

      // A function value held in a local variable (a closure / function-typed
      // parameter): dispatch via `call_indirect`.
      var localFn = context.getLocalVariable(name);
      if (localFn != null && localFn.type is ASTTypeFunction) {
        return _emitIndirectCall(
          expression,
          localFn.type as ASTTypeFunction,
          localFn.index,
          out: out,
          context: context,
        );
      }

      // A bare-name call to a sibling STATIC method of the enclosing class.
      // Static methods are registered under their qualified `Class.method`
      // name, so they miss the top-level bare-name lookup above; resolve them
      // here and fall through to the normal call emission below (no receiver).
      if (layout != null) {
        calleeIndex = context.module?.staticMethodIndexForCall(
          layout.className,
          name,
          argsCount,
        );
      }

      if (calleeIndex == null) {
        // Only static methods are callable without a receiver. A receiver-less
        // call that matches a non-static method (e.g. a `static` method calling
        // an instance sibling, where no `this` is in scope) needs an instance.
        var instanceMethod = context.module?.instanceMethodQualifiedName(
          name,
          argsCount,
        );
        if (instanceMethod != null) {
          throw UnsupportedError(
            "Can't call non-static method '$instanceMethod' without an instance.",
          );
        }

        throw StateError(
          "Can't resolve local function `$name` with $argsCount argument(s) "
          "in the Wasm function index table.",
        );
      }
    }

    var callee = context.functionByIndex(calleeIndex)!;

    // Reorder/merge named arguments into the callee's positional order and fill
    // omitted parameters that have defaults (no-op for purely-positional calls
    // that already cover all declared parameters). The resulting list has length
    // equal to the callee's DECLARED arity (Wasm calls are fixed-arity).
    arguments = _orderInvocationArguments(
      positionalArgs,
      namedArgs,
      callee.parameters,
      name,
    );
    var declaredArity = arguments.length;

    final stackLng0 = context.stackLength;

    // Evaluate each argument (left-to-right), pushing onto the Wasm stack,
    // converting each to the callee's declared parameter type.
    for (var i = 0; i < declaredArity; ++i) {
      var arg = arguments[i];

      var stackLngArg = context.stackLength;
      generateASTExpression(arg, out: out, context: context);
      context.assertStackLength(
        stackLngArg + 1,
        "After argument[$i] push (call `$name`)",
      );

      var stackEntry = context.stackGet(0)!;
      var stackType = stackEntry.type;

      var paramType = _orderedParamType(callee.parameters, i);
      if (paramType != null) {
        _autoConvertStackTypes(
          stackType,
          paramType,
          out: out,
          context: context,
        );
      }
    }

    context.assertStackLength(
      stackLng0 + declaredArity,
      "Before call `$name` (all arguments pushed)",
    );

    out.write(
      Wasm.call(calleeIndex),
      description: "[OP] call `$name` (function index: $calleeIndex)",
    );

    // Update the virtual stack: drop the N arguments and push the return type.
    for (var i = 0; i < declaredArity; ++i) {
      context.stackDrop();
    }

    var returnType = callee.effectiveReturnType;
    if (!returnType.isVoid) {
      ASTType resultType;
      if (returnType is ASTTypeInt) {
        resultType = _astTypeInt64;
      } else if (returnType is ASTTypeDouble) {
        resultType = _astTypeDouble64;
      } else {
        resultType = returnType;
      }
      context.stackPush(resultType, "call `$name` result: $returnType");
    }

    context.assertStackLength(
      stackLng0 + (returnType.isVoid ? 0 : 1),
      "After call `$name` result",
    );

    return out;
  }

  /// Lowers `v(args)` for a direct-closure variable `v` (a capture-free,
  /// call-only closure) to a plain `call` of the closure function [fn]. The
  /// closure's hidden environment parameter is unused (no captures), so a null
  /// env (`i32.const 0`) is passed as argument 0, followed by the real
  /// arguments. No heap allocation and no `call_indirect`.
  BytesOutput _emitDirectClosureCall(
    ASTExpressionLocalFunctionInvocation expression,
    ASTFunctionDeclaration fn, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();
    var module = context.module!;

    var info = module.closureInfo(fn)!;
    var fnIndex = module.functionIndexByDeclaration(fn);
    var arguments = expression.arguments;

    final stackLng0 = context.stackLength;

    // Argument 0: the (unused) environment pointer — null.
    out.write(
      Wasm32.i32Const(0),
      description: "[OP] direct closure call: null env",
    );
    context.stackPush(_astTypeInt32, "direct closure null env");

    // Real arguments, converted to the closure's parameter types.
    for (var i = 0; i < arguments.length; ++i) {
      generateASTExpression(arguments[i], out: out, context: context);
      if (i < info.paramTypes.length) {
        _autoConvertStackTypes(
          context.stackGet(0)!.type,
          info.paramTypes[i],
          out: out,
          context: context,
        );
      }
    }

    out.write(
      Wasm.call(fnIndex),
      description:
          "[OP] direct call closure `${expression.name}` (index $fnIndex)",
    );

    // Drop env + arguments; push the return value.
    for (var i = 0; i < arguments.length; ++i) {
      context.stackDrop();
    }
    context.stackDrop(); // env
    var returnType = info.returnType;
    if (!returnType.isVoid) {
      ASTType resultType;
      if (returnType is ASTTypeInt) {
        resultType = _astTypeInt64;
      } else if (returnType is ASTTypeDouble) {
        resultType = _astTypeDouble64;
      } else {
        resultType = returnType;
      }
      context.stackPush(resultType, "direct closure call result");
    }

    context.assertStackLength(
      stackLng0 + (returnType.isVoid ? 0 : 1),
      "After direct closure call `${expression.name}`",
    );

    return out;
  }

  /// Calls a function value held in a local (a closure / function-typed
  /// parameter) via `call_indirect`. The value is the i32 table index; the
  /// signature comes from the variable's [funcType] (`generics[0]` = return
  /// type, the rest = parameter types).
  BytesOutput _emitIndirectCall(
    ASTExpressionLocalFunctionInvocation expression,
    ASTTypeFunction funcType,
    int localIndex, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();
    context.module?.tableUsed = true; // an indirect call dispatches via table

    var namedArgs = expression.namedArguments;
    if (namedArgs != null && namedArgs.isNotEmpty) {
      throw StateError(
        "Wasm: named arguments are not supported for closure / indirect calls "
        "(`${expression.name}`): a function-typed value carries no parameter "
        "names to bind by.",
      );
    }

    var arguments = expression.arguments;
    var generics = funcType.generics ?? const <ASTType>[];
    var returnType = generics.isNotEmpty
        ? generics.first
        : ASTTypeDynamic.instance;
    var paramTypes = generics.length > 1
        ? generics.sublist(1)
        : const <ASTType>[];

    final stackLng0 = context.stackLength;

    // The function value is a pointer to the closure struct; it is also passed
    // as the hidden first argument (the environment).
    out.write(
      Wasm.localGet(localIndex),
      description: "[OP] closure env ptr `${expression.name}`",
    );
    context.stackPush(_astTypeInt32, "closure env `${expression.name}`");

    // Push arguments (converting to the declared parameter types).
    for (var i = 0; i < arguments.length; ++i) {
      generateASTExpression(arguments[i], out: out, context: context);
      var stackType = context.stackGet(0)!.type;
      if (i < paramTypes.length) {
        _autoConvertStackTypes(
          stackType,
          paramTypes[i],
          out: out,
          context: context,
        );
      }
    }

    // Push the table slot loaded from the closure struct (`env[0]`).
    out.write(
      Wasm.localGet(localIndex),
      description: "[OP] closure ptr `${expression.name}` (slot load)",
    );
    out.write(Wasm32.i32Load(2, 0));
    context.stackPush(_astTypeInt32, "closure table slot `${expression.name}`");

    // Resolve the type index matching the call signature (env i32 + params).
    var paramCodes = [
      WasmType.i32Type.value,
      ...paramTypes.map((t) => t.wasmCode),
    ];
    var resultCode = returnType.isVoid ? null : returnType.wasmCode;
    var typeIndex = context.module!.typeIndexForSignature(
      paramCodes,
      resultCode,
    );
    if (typeIndex < 0) {
      throw StateError(
        "Wasm: no function type matches the indirect-call signature of "
        "`${expression.name}` ($funcType).",
      );
    }

    out.write(
      Wasm.callIndirect(typeIndex),
      description: "[OP] call_indirect `${expression.name}` (type $typeIndex)",
    );

    // Drop the env, the arguments and the table slot; push the return value.
    context.stackDrop(); // table slot
    for (var i = 0; i < arguments.length; ++i) {
      context.stackDrop();
    }
    context.stackDrop(); // env pointer
    if (!returnType.isVoid) {
      ASTType resultType;
      if (returnType is ASTTypeInt) {
        resultType = _astTypeInt64;
      } else if (returnType is ASTTypeDouble) {
        resultType = _astTypeDouble64;
      } else {
        resultType = returnType;
      }
      context.stackPush(
        resultType,
        "call_indirect `${expression.name}` result",
      );
    }

    context.assertStackLength(
      stackLng0 + (returnType.isVoid ? 0 : 1),
      "After call_indirect `${expression.name}`",
    );

    return out;
  }

  /// Lowers `print(arg)` to a host import call `env.print(i32 ptr)`. The
  /// argument is lowered to a string handle (i32 pointer to `[len][utf8]`).
  BytesOutput _generatePrintInvocation(
    ASTExpressionLocalFunctionInvocation expression, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    var module = context.module;
    if (module == null) {
      throw StateError("Can't lower `print` without a module.");
    }

    final stackLng0 = context.stackLength;

    var arg = expression.arguments[0];

    // `print(null)` prints the literal `null`. The generic null-value path can't
    // be lowered (Wasm has no null), so intern the text directly.
    if (arg is ASTExpressionNullValue) {
      var ptr = module.internStringLiteral('null');
      out.write(
        Wasm32.i32Const(ptr),
        description: "[OP] push 'null' literal ptr($ptr)",
      );
      context.stackPush(_astTypeString, "print null literal");
    } else {
      // Evaluate the argument, then coerce whatever it is (int/double/bool/
      // String) to an i32 string handle for `env.print`.
      generateASTExpression(arg, out: out, context: context);
      context.assertStackLength(stackLng0 + 1, "After print argument");
      _emitToStringHandle(out, context, context.stackGet(0)!.type);
    }

    var importIndex = module.registerImportedFunction('env', 'print', [
      WasmType.i32Type,
    ], const []);

    if (context.exceptionMode && module.requiresException) {
      // If an exception was raised while building the argument (e.g. an integer
      // division by zero inside the interpolation), skip the print: the value is
      // invalid and the exception is about to unwind. This matches the
      // interpreter, which never reaches the print. (The handle is stashed in a
      // local so the `if` branches don't reach below their block frame.)
      var argLocal = context.scratchLocal(_astTypeString, 57); // i32 handle
      out.write(Wasm.localSet(argLocal), description: "[OP] stash print arg");
      out.write(Wasm32.i32Const(0));
      out.write(
        Wasm32.i32Load(2, module.excPendingOffset),
        description: "[OP] load EXC_PENDING (guard print)",
      );
      out.write(Wasm.ifInstruction(WasmType.voidType));
      // pending: skip the print (argument discarded).
      out.writeByte(Wasm.elseInstruction);
      out.write(Wasm.localGet(argLocal));
      out.write(
        Wasm.call(importIndex),
        description: "[OP] call host import `env.print` (index $importIndex)",
      );
      out.writeByte(Wasm.end);
    } else {
      out.write(
        Wasm.call(importIndex),
        description: "[OP] call host import `env.print` (index $importIndex)",
      );
    }
    context.stackDrop();

    context.assertStackLength(stackLng0, "After print (void)");

    return out;
  }

  @override
  BytesOutput generateASTExpressionGroupFunctionInvocation(
    ASTExpressionGroupFunctionInvocation expression, {
    BytesOutput? out,
  }) {
    // TODO: implement generateASTExpressionGroupFunctionInvocation
    throw UnimplementedError("generateASTExpressionGroupFunctionInvocation");
  }

  // === Maps ==========================================================
  //
  // A map value is an i32 pointer to a 16-byte header
  // `[length:i32][capacity:i32][keysPtr:i32][valuesPtr:i32]`. Keys and values
  // each live in their own parallel buffer (element encodings as for lists:
  // int->i64, double->f64, String/bool->i32). Lookup/set is a linear scan with
  // key equality. Slice 1 supports `int` keys.
  static const int _mapHeaderSize = 16;

  /// Resolves a local variable's `ASTTypeMap`, or throws if not a supported map.
  /// Supported keys: `int` (i64) and `String` (i32 pointer, compared by bytes).
  ASTTypeMap _requireMapType(ASTType t, String name, String op) {
    if (t is! ASTTypeMap) {
      throw UnimplementedError(
        "Wasm $op on `$name` ($t) is not supported yet.",
      );
    }
    if (t.keyType is! ASTTypeInt && t.keyType is! ASTTypeString) {
      throw UnimplementedError(
        "Wasm maps with key type ${t.keyType} are not supported yet "
        "(only `int` and `String` keys).",
      );
    }
    if (!_isSupportedElemType(t.valueType)) {
      throw UnimplementedError(
        "Wasm maps with value type ${t.valueType} are not supported yet.",
      );
    }
    return t;
  }

  /// Storage size of a map key: `int` -> 8 (i64), `String` -> 4 (i32 pointer).
  int _mapKeySize(ASTType keyType) => keyType is ASTTypeInt ? 8 : 4;

  /// Emits the key-comparison loop for `m[k]`. On entry the key is evaluated
  /// into [keyScratch]; emits a `block { loop { … } }` that, for each entry,
  /// runs [onMatch] (with the matching index `i` in [iScratch] and the key
  /// buffer base in [keysScratch]) and breaks. Falls through (no match) past the
  /// block. Used by get/set/containsKey.
  void _emitMapScan(
    BytesOutput out,
    WasmContext context, {
    required ASTType keyType,
    required int hdrScratch,
    required int keysScratch,
    required int iScratch,
    required int keyScratch,
    required void Function() onMatch,
  }) {
    var keySize = _mapKeySize(keyType);
    int? strEqIndex;
    if (keyType is ASTTypeString) {
      var module = context.module!;
      module.ensureStrEqFunction();
      strEqIndex = module.synthFunctionIndex('__streq')!;
    }

    // keysPtr = load(hdr, 8) ; i = 0
    out.write(Wasm.localGet(hdrScratch));
    out.write(Wasm32.i32Load(2, 8));
    out.write(Wasm.localSet(keysScratch));
    out.write(Wasm32.i32Const(0));
    out.write(Wasm.localSet(iScratch));

    out.write(Wasm.block(WasmType.voidType));
    out.write(Wasm.loop(WasmType.voidType));

    // if (i >= length) break the block (no match)
    out.write(Wasm.localGet(iScratch));
    out.write(Wasm.localGet(hdrScratch));
    out.write(Wasm32.i32Load(2, 0)); // length
    out.writeByte(Wasm32.i32GreaterThanOrEqualsUnsigned);
    out.write(Wasm.brIf(1));

    // if (keys[i] == key) { onMatch(); break }
    out.write(Wasm.localGet(keysScratch));
    out.write(Wasm.localGet(iScratch));
    out.write(Wasm32.i32Const(keySize));
    out.writeByte(Wasm32.i32Multiply);
    out.writeByte(Wasm32.i32Add);
    if (keyType is ASTTypeString) {
      out.write(Wasm32.i32Load(2, 0)); // keys[i] (string pointer)
      out.write(Wasm.localGet(keyScratch)); // query key pointer
      out.write(Wasm.call(strEqIndex!)); // __streq(keys[i], key) -> i32 0/1
    } else {
      out.write(Wasm64.i64Load(3, 0)); // keys[i] (i64)
      out.write(Wasm.localGet(keyScratch)); // query key
      out.writeByte(Wasm64.i64Equals);
    }
    out.write(Wasm.ifInstruction(WasmType.voidType));
    onMatch();
    out.write(Wasm.br(2)); // break out of the scan block (if -> loop -> block)
    out.writeByte(Wasm.end); // end if

    // i++ ; continue
    out.write(Wasm.localGet(iScratch));
    out.write(Wasm32.i32Const(1));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localSet(iScratch));
    out.write(Wasm.br(0));

    out.writeByte(Wasm.end); // end loop
    out.writeByte(Wasm.end); // end block
  }

  @override
  BytesOutput generateASTExpressionMapLiteral(
    ASTExpressionMapLiteral expression, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();
    var module = context.module;
    if (module == null) {
      throw StateError("Can't build a map without a module.");
    }
    module.requiresMemory = true;
    module.requiresHeapGlobal = true;

    var entries = expression.entriesExpressions;
    var n = entries.length;

    // Element sizes only matter when there are entries to store. An empty `{}`
    // (typed `Map<dynamic,dynamic>`) allocates zero-size buffers; its element
    // types are taken later from the variable's declared type (on `m[k] = v`).
    ASTType keyType = ASTTypeInt.instance;
    ASTType valueType = ASTTypeInt.instance;
    ASTTypeMap mapType = ASTTypeMap(keyType, valueType);
    if (n > 0) {
      var rt = expression.resolveType(null);
      var resolvedKey =
          expression.keyType ?? (rt is ASTTypeMap ? rt.keyType : null);
      var resolvedVal =
          expression.valueType ?? (rt is ASTTypeMap ? rt.valueType : null);
      mapType = _requireMapType(
        ASTTypeMap(
          resolvedKey ?? ASTTypeDynamic.instance,
          resolvedVal ?? ASTTypeDynamic.instance,
        ),
        'map literal',
        'map literal',
      );
      keyType = mapType.keyType;
      valueType = mapType.valueType;
    }
    var keySize = _mapKeySize(keyType);
    var valSize = _elemSize(valueType);

    // Depth-offset the scratch slots so a nested collection value (a `Map`/`List`
    // value) doesn't alias this literal's header/keys/values locals.
    var depth = context.collectionLiteralDepth;
    var hdrLocal = context.scratchLocal(_astTypeString, _mapHdrSlot(depth));
    var keysLocal = context.scratchLocal(_astTypeString, _mapKeysSlot(depth));
    var valsLocal = context.scratchLocal(_astTypeString, _mapValsSlot(depth));
    context.collectionLiteralDepth = depth + 1;

    final s0 = context.stackLength;

    // header = alloc(16); keys = alloc(n*keySize); vals = alloc(n*valSize)
    out.write(Wasm32.i32Const(_mapHeaderSize));
    _emitInlineAlloc(out, context);
    out.write(Wasm.localSet(hdrLocal));
    out.write(Wasm32.i32Const(n * keySize));
    _emitInlineAlloc(out, context);
    out.write(Wasm.localSet(keysLocal));
    out.write(Wasm32.i32Const(n * valSize));
    _emitInlineAlloc(out, context);
    out.write(Wasm.localSet(valsLocal));

    // header: length=n@0, capacity=n@4, keysPtr@8, valuesPtr@12
    out.write(Wasm.localGet(hdrLocal));
    out.write(Wasm32.i32Const(n));
    out.write(Wasm32.i32Store(2, 0));
    out.write(Wasm.localGet(hdrLocal));
    out.write(Wasm32.i32Const(n));
    out.write(Wasm32.i32Store(2, 4));
    out.write(Wasm.localGet(hdrLocal));
    out.write(Wasm.localGet(keysLocal));
    out.write(Wasm32.i32Store(2, 8));
    out.write(Wasm.localGet(hdrLocal));
    out.write(Wasm.localGet(valsLocal));
    out.write(Wasm32.i32Store(2, 12));

    // entries
    for (var i = 0; i < n; ++i) {
      // keys[i] = key
      out.write(Wasm.localGet(keysLocal));
      generateASTExpression(entries[i].key, out: out, context: context);
      _coerceBoxedToNumberSlot(out, context, keyType);
      context.stackDrop();
      _emitElemStore(out, keyType, i * keySize);
      // vals[i] = value
      out.write(Wasm.localGet(valsLocal));
      generateASTExpression(entries[i].value, out: out, context: context);
      _coerceBoxedToNumberSlot(out, context, valueType);
      context.stackDrop();
      _emitElemStore(out, valueType, i * valSize);
    }

    context.collectionLiteralDepth = depth;

    out.write(Wasm.localGet(hdrLocal));
    context.stackPush(mapType, "map literal");
    context.assertStackLength(s0 + 1, "After map literal");
    return out;
  }

  @override
  BytesOutput generateASTExpressionNegation(
    ASTExpressionNegation expression, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    final stackLng0 = context.stackLength;

    generateASTExpression(expression.expression, out: out, context: context);

    context.assertStackLength(stackLng0 + 1, "After negation operand");

    var stackType = context.stackGet(0)!.type;
    if (stackType != _astTypeInt32) {
      throw StateError(
        "Logical negation `!` needs a boolean (i32) value: $stackType",
      );
    }

    out.writeByte(
      Wasm32.i32EqualsToZero,
      description: "[OP] operator: not (i32.eqz)",
    );
    context.stackOperationUnary(_astTypeInt32, "i32.eqz (not)");

    context.assertStackLength(stackLng0 + 1, "After negation result");

    return out;
  }

  @override
  BytesOutput generateASTExpressionNegative(
    ASTExpressionNegative expression, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    final stackLng0 = context.stackLength;

    generateASTExpression(expression.expression, out: out, context: context);

    context.assertStackLength(stackLng0 + 1, "After negative operand");

    var stackType = context.stackGet(0)!.type;

    if (stackType == _astTypeDouble64 || stackType == _astTypeDouble) {
      out.writeByte(
        Wasm64.f64Negation,
        description: "[OP] operator: negative (f64.neg)",
      );
      // Unary: top stays f64 (stack length unchanged).
    } else {
      // No `i64.neg` opcode: negate via `x * -1`.
      out.write(
        Wasm64.i64Const(-1),
        description: "[OP] push constant(i64): -1 (negate)",
      );
      context.stackPush(_astTypeInt64, "negate -1");
      out.writeByte(
        Wasm64.i64Multiply,
        description: "[OP] operator: negative (i64.mul -1)",
      );
      context.stackOperationBinary(_astTypeInt64, "i64.mul (negate)");
    }

    context.assertStackLength(stackLng0 + 1, "After negative result");

    return out;
  }

  BytesOutput generateASTExpressionBitwiseNot(
    ASTExpressionBitwiseNot expression, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    final stackLng0 = context.stackLength;

    generateASTExpression(expression.expression, out: out, context: context);

    context.assertStackLength(stackLng0 + 1, "After bitwise-not operand");

    // No `i64.not` opcode: `~x == x ^ -1`.
    out.write(
      Wasm64.i64Const(-1),
      description: "[OP] push constant(i64): -1 (bitwise-not)",
    );
    context.stackPush(_astTypeInt64, "bitwise-not -1");
    out.writeByte(
      Wasm64.i64BitwiseXor,
      description: "[OP] operator: bitwise-not (i64.xor -1)",
    );
    context.stackOperationBinary(_astTypeInt64, "i64.xor (bitwise-not)");

    context.assertStackLength(stackLng0 + 1, "After bitwise-not result");

    return out;
  }

  // The Wasm backend executes synchronously, so a `Future<T>` value is always
  // already available: `await expr` compiles to just `expr` (a value
  // pass-through), and an `async` function is compiled as a normal function
  // returning the unwrapped `T` (see `effectiveReturnType`). This yields
  // correct results for compute-style async code.
  //
  // TODO(async): real suspension — lower `await`/`async` to a resumable
  // continuation (state machine) that yields to the host event loop
  // (e.g. Asyncify or JSPI). That requires runtime support the synchronous
  // `WasmRuntime` does not yet have.
  @override
  BytesOutput generateASTExpressionAwait(
    ASTExpressionAwait expression, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    return generateASTExpression(
      expression.expression,
      out: out,
      context: context,
    );
  }

  ASTTypeDouble _fixStackOpsAsFloat64(
    ASTType stackType1,
    ASTType stackType2,
    BytesOutput opsOut1,
    BytesOutput opsOut2,
    BytesOutput out,
    WasmContext context,
  ) {
    out.writeBytes(opsOut1);

    if (stackType1.equalsStrict(_astTypeInt64) ||
        stackType1.equalsStrict(_astTypeInt)) {
      out.writeByte(
        Wasm64.i64ConvertToF64Signed,
        description: "[OP] convert i64 to f64 signed",
      );

      context.stackReplaceAt(1, _astTypeDouble64, "Convert i64 to f64 signed");
    } else if (stackType1.equalsStrict(_astTypeInt32)) {
      out.writeByte(
        Wasm32.i32ConvertToF64Signed,
        description: "[OP] convert i32 to f64 signed",
      );

      context.stackReplaceAt(1, _astTypeDouble64, "Convert i32 to f64 signed");
    }

    out.writeBytes(opsOut2);

    if (stackType2.equalsStrict(_astTypeInt64) ||
        stackType2.equalsStrict(_astTypeInt)) {
      out.writeByte(
        Wasm64.i64ConvertToF64Signed,
        description: "[OP] convert i64 to f64 signed",
      );

      context.stackReplace(_astTypeDouble64, "Convert i64 to f64 signed");
    } else if (stackType2.equalsStrict(_astTypeInt32)) {
      out.writeByte(
        Wasm32.i32ConvertToF64Signed,
        description: "[OP] convert i32 to f64 signed",
      );

      context.stackReplace(_astTypeDouble64, "Convert i32 to f64 signed");
    }

    return _astTypeDouble64;
  }

  ASTType _fixStackOpsAsInt(
    ASTType stackType1,
    ASTType stackType2,
    BytesOutput opsOut1,
    BytesOutput opsOut2,
    BytesOutput out,
    WasmContext context,
  ) {
    // `int` operands, or a plain `num` (TS/JS `number`) which is represented as
    // i64 like `int`.
    assert(stackType1 is ASTTypeNum, stackType1);
    assert(stackType2 is ASTTypeNum, stackType2);

    if (stackType1.equalsStrict(stackType2)) {
      out.writeBytes(opsOut1);
      out.writeBytes(opsOut2);
      return stackType1;
    }

    out.writeBytes(opsOut1);

    if (stackType1.equalsStrict(_astTypeInt32)) {
      out.writeByte(
        Wasm32.i32ExtendToI64Signed,
        description: "[OP] convert i32 to i64 signed",
      );

      context.stackReplaceAt(1, _astTypeInt64, "Convert i32 to i64 signed");
    }

    out.writeBytes(opsOut2);

    if (stackType2.equalsStrict(_astTypeInt32)) {
      out.writeByte(
        Wasm32.i32ExtendToI64Signed,
        description: "[OP] convert i32 to i64 signed",
      );

      context.stackReplace(_astTypeInt64, "Convert i32 to i64 signed");
    }

    return _astTypeInt64;
  }

  ASTType? _getOperationType(
    ASTExpressionOperation expression,
    ASTType<dynamic> stackType1,
    ASTType<dynamic> stackType2,
  ) {
    return switch (expression.operator) {
      ASTExpressionOperator.divide ||
      ASTExpressionOperator.divideAsDouble ||
      ASTExpressionOperator.divideAsInt => _astTypeDouble64 as ASTType,
      ASTExpressionOperator.greater ||
      ASTExpressionOperator.greaterOrEq ||
      ASTExpressionOperator.lower ||
      ASTExpressionOperator.lowerOrEq =>
        ((stackType1 == _astTypeDouble || stackType2 == _astTypeDouble)
                ? _astTypeDouble64
                : _astTypeInt64)
            as ASTType,
      _ => null,
    };
  }

  BytesOutput generateASTExpressionOperationEqualsToZero(
    ASTExpression expression, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    final stackLng0 = context.stackLength;

    generateASTExpression(expression, out: out, context: context);

    final stackLng1 = context.assertStackLength(
      stackLng0 + 1,
      "After operation expression (left)",
    );

    // A boxed `Object`/`dynamic` operand (e.g. a dynamic `b` in `b == 0`) is
    // unboxed to i64 before the `i64.eqz`.
    if (_isObjectType(context.stackGet(0)!.type)) {
      _emitUnboxNumberInto(out, context, _astTypeInt64);
    }

    out.writeByte(
      Wasm64.i64EqualsToZero,
      description: "[OP] operator: equals to zero",
    );
    context.stackOperationUnary(_astTypeInt32, 'f64.eqToZero');

    context.assertStackLength(stackLng1, "After operation result (eqZero)");

    return out;
  }

  /// Generates a short-circuiting logical `&&` / `||` as an `if/else` that
  /// yields an i32 boolean, so the right operand is only evaluated when needed:
  /// - `a && b`  ->  `a ? b : false`
  /// - `a || b`  ->  `a ? true : b`
  @override
  BytesOutput generateASTExpressionLogical(
    ASTExpressionLogical expression, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    final isAnd = expression is ASTExpressionLogicalAnd;
    final stackLng0 = context.stackLength;

    // Left operand (i32 boolean).
    generateASTExpression(expression.expression1, out: out, context: context);
    context.assertStackLength(stackLng0 + 1, "After logical left operand");

    var leftType = context.stackGet(0)!.type;
    if (leftType != _astTypeInt32) {
      throw StateError("Logical operand is not a boolean (i32): $leftType");
    }

    // `if` consumes the left boolean and yields an i32 result.
    out.write(
      Wasm.ifInstruction(WasmType.i32Type),
      description: "[OP] logical ${isAnd ? '&&' : '||'} (short-circuit)",
    );
    context.stackDrop(_astTypeInt32);

    // `then` branch value.
    if (isAnd) {
      generateASTExpression(expression.expression2, out: out, context: context);
    } else {
      out.write(Wasm32.i32Const(1), description: "[OP] push true");
      context.stackPush(_astTypeInt32, "logical true");
    }
    // The two branches are mutually exclusive: drop the `then` result from the
    // virtual stack before generating the `else` branch.
    context.stackDrop();

    out.writeByte(Wasm.elseInstruction, description: "[OP] logical else");

    // `else` branch value.
    if (isAnd) {
      out.write(Wasm32.i32Const(0), description: "[OP] push false");
      context.stackPush(_astTypeInt32, "logical false");
    } else {
      generateASTExpression(expression.expression2, out: out, context: context);
    }

    out.writeByte(Wasm.end, description: "[OP] logical end");

    context.assertStackLength(stackLng0 + 1, "After logical short-circuit");

    return out;
  }

  @override
  BytesOutput generateASTExpressionLiteralFunction(
    ASTExpressionLiteralFunction expression, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    var module = context.module;
    var info = module?.closureInfo(expression.function);
    if (module == null || info == null) {
      throw UnsupportedError(
        "Wasm: this anonymous function wasn't registered as a function value: "
        "$expression",
      );
    }

    module.requiresMemory = true;
    module.requiresHeapGlobal = true;
    module.tableUsed = true; // a real function value needs the table slot

    final s0 = context.stackLength;

    // A function value is an i32 pointer to a heap struct
    // `[tableSlot@0, capture0, capture1, ...]`.
    out.write(
      Wasm32.i32Const(info.envSize),
      description: "[OP] closure env size (${info.envSize})",
    );
    _emitInlineAlloc(out, context); // size -> ptr

    var ptrLocal = context.scratchLocal(_astTypeString, 12);
    out.write(Wasm.localSet(ptrLocal), description: "[OP] save closure ptr");

    // Store the table slot at offset 0.
    out.write(Wasm.localGet(ptrLocal));
    out.write(Wasm32.i32Const(info.slot));
    out.write(
      Wasm32.i32Store(2, 0),
      description: "[OP] closure[0] = table slot ${info.slot}",
    );

    // Store each capture's box pointer (the shared heap cell) into the
    // environment, so the closure reads/writes the variable by reference.
    for (var c in info.captures) {
      out.write(Wasm.localGet(ptrLocal));
      _emitBoxPointer(out, context, c.name);
      out.write(
        Wasm32.i32Store(2, c.offset),
        description: "[OP] closure env[${c.offset}] = box of `${c.name}`",
      );
    }

    // Leave the closure pointer on the stack as the result. The value carries
    // the closure's concrete signature (`generics = [returnType, ...params]`)
    // so a `var` it is assigned to can be called via `call_indirect` with the
    // right type.
    out.write(Wasm.localGet(ptrLocal), description: "[OP] closure ptr (value)");
    context.stackPush(
      ASTTypeFunction(info.returnType, info.paramTypes),
      "closure value (slot ${info.slot}, env ${info.envSize}B)",
    );
    context.assertStackLength(s0 + 1, "After closure value");

    return out;
  }

  @override
  BytesOutput generateASTExpressionConditional(
    ASTExpressionConditional expression, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    final stackLng0 = context.stackLength;

    // Condition (i32 boolean).
    generateASTExpression(expression.condition, out: out, context: context);
    context.assertStackLength(stackLng0 + 1, "After conditional condition");

    var condType = context.stackGet(0)!.type;
    if (condType != _astTypeInt32) {
      throw StateError(
        "Conditional (ternary) condition is not a boolean (i32): $condType",
      );
    }

    // The `if` block yields the value of the selected branch, so it needs the
    // result type up-front. Both branches must agree on this type.
    var resultType = expression.resolveType(null);
    if (resultType is Future) {
      throw UnsupportedError(
        "Conditional (ternary) with async type resolution not supported in Wasm",
      );
    }

    // A `null` arm is the boxed-Object pointer 0, so the whole conditional has
    // to yield a boxed `Object` — otherwise the other arm's concrete value
    // (an i64 `int`, say) would disagree with the block's result type and
    // produce a module that fails to validate.
    if (expression.valueIfTrue is ASTExpressionNullValue ||
        expression.valueIfFalse is ASTExpressionNullValue) {
      resultType = ASTTypeObject.instance;
    }

    out.write(
      Wasm.ifInstruction(resultType.wasmType),
      description: "[OP] conditional (ternary): $expression",
    );
    context.stackDrop(_astTypeInt32);

    // `then` branch value, coerced to the block's result type (the two arms can
    // differ — e.g. `c ? 1 : null` mixes an `int` with a boxed `null`).
    generateASTExpression(expression.valueIfTrue, out: out, context: context);
    _autoConvertStackTypes(
      context.stackGet(0)!.type,
      resultType,
      out: out,
      context: context,
    );
    // The two branches are mutually exclusive: drop the `then` result from the
    // virtual stack before generating the `else` branch.
    context.stackDrop();

    out.writeByte(Wasm.elseInstruction, description: "[OP] conditional else");

    // `else` branch value, coerced the same way.
    generateASTExpression(expression.valueIfFalse, out: out, context: context);
    _autoConvertStackTypes(
      context.stackGet(0)!.type,
      resultType,
      out: out,
      context: context,
    );

    out.writeByte(Wasm.end, description: "[OP] conditional end");

    context.assertStackLength(stackLng0 + 1, "After conditional (ternary)");

    return out;
  }

  /// Appends, to [buf], bytes that unbox the boxed `Object` pointer currently
  /// on top of the stack into a concrete number of type [target] (`int`→i64 or
  /// `double`→f64), dispatching on the runtime box tag
  /// (`[tag@0][typeId@4][payload@8]`). A box whose tag disagrees with [target]
  /// is converted (`i64.trunc_f64_s` / `f64.convert_i64_s`) so the result type
  /// is always [target]. Used when a dynamic value (e.g. a `List<Object>`
  /// element) flows into arithmetic. Net stack effect: replaces the i32 box
  /// pointer with one [target] value.
  void _emitUnboxNumberInto(
    BytesOutput buf,
    WasmContext context,
    ASTType target,
  ) {
    var module = context.module;
    if (module == null) {
      throw StateError("Can't unbox an Object without a module.");
    }
    module.requiresMemory = true;

    var wantDouble = target == _astTypeDouble64 || target == _astTypeDouble;
    var resultType = wantDouble ? WasmType.f64Type : WasmType.i64Type;
    var boxTmp = context.scratchLocal(_astTypeString, 56); // i32

    buf.write(
      Wasm.localSet(boxTmp),
      description: "[OP] unbox Object: stash box ptr",
    );
    buf.write(Wasm.localGet(boxTmp));
    buf.write(Wasm32.i32Load(2, _boxTagOffset));
    buf.write(Wasm32.i32Const(_boxTagInt));
    buf.writeByte(Wasm32.i32Equals);
    buf.write(Wasm.ifInstruction(resultType));
    // tag == int: payload is i64.
    buf.write(Wasm.localGet(boxTmp));
    buf.write(Wasm64.i64Load(3, _boxPayloadOffset));
    if (wantDouble) {
      buf.writeByte(
        Wasm64.i64ConvertToF64Signed,
        description: "[OP] unbox int -> f64",
      );
    }
    buf.writeByte(Wasm.elseInstruction);
    // else: payload is f64 (double box).
    buf.write(Wasm.localGet(boxTmp));
    buf.write(Wasm64.f64Load(FloatAlign.align3, _boxPayloadOffset));
    if (!wantDouble) {
      buf.writeByte(
        Wasm64.f64TruncateToI64Signed,
        description: "[OP] unbox double -> i64",
      );
    }
    buf.writeByte(Wasm.end);
  }

  /// If the value on top of the stack is a boxed `Object` but [slotType] is a
  /// concrete number (`int`/`double`), unboxes it (via [_emitUnboxNumberInto])
  /// so it can be stored into a typed numeric element/field slot. No-op
  /// otherwise. Does not touch the virtual stack (the caller drops the value).
  void _coerceBoxedToNumberSlot(
    BytesOutput out,
    WasmContext context,
    ASTType slotType,
  ) {
    var vt = context.stackGet(0)?.type;
    if (vt != null &&
        _isObjectType(vt) &&
        (slotType is ASTTypeInt || slotType is ASTTypeDouble)) {
      _emitUnboxNumberInto(
        out,
        context,
        slotType is ASTTypeDouble ? _astTypeDouble64 : _astTypeInt64,
      );
    }
  }

  @override
  BytesOutput generateASTExpressionNullCoalesce(
    ASTExpressionNullCoalesce expression, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    generateASTExpression(expression.expression1, out: out, context: context);
    var leftType = context.stackGet(0)!.type;

    // In the numeric domain a value can never be null, so the left operand
    // always determines the result and the right one is dropped.
    if (!_isObjectType(leftType)) return out;

    // A boxed value *can* be the null pointer, so test it and fall back to
    // the right operand. The result is boxed either way.
    var leftTmp = context.scratchLocal(_astTypeString, 78); // i32 box ptr
    out.write(
      Wasm.localSet(leftTmp),
      description: "[OP] `??`: stash left operand",
    );
    context.stackDrop();

    out.write(Wasm.localGet(leftTmp));
    out.write(Wasm32.i32Const(_boxPtrNull));
    out.writeByte(Wasm32.i32Equals, description: "[OP] `??`: left is null?");
    out.write(Wasm.ifInstruction(WasmType.i32Type));

    // then: the left operand is null — evaluate the right one, boxed.
    generateASTExpression(expression.expression2, out: out, context: context);
    _autoConvertStackTypes(
      context.stackGet(0)!.type,
      ASTTypeObject.instance,
      out: out,
      context: context,
    );
    context.stackDrop();

    out.writeByte(Wasm.elseInstruction);
    out.write(
      Wasm.localGet(leftTmp),
      description: "[OP] `??`: left operand (non-null)",
    );
    out.writeByte(Wasm.end);

    context.stackPush(ASTTypeObject.instance, "`??` result");
    return out;
  }

  /// `x == null` / `x != null`.
  ///
  /// Wasm has no null of its own: `null` is the boxed-`Object` pointer
  /// [_boxPtrNull], so this is an `i32` comparison against that pointer. It must
  /// not go through the String or numeric equality paths — `__streq` would
  /// compare *contents* against address 0, and the numeric path would push two
  /// i32 handles into an `i64.eq` (an invalid module).
  ///
  /// The result is tracked on the virtual stack as an i32, which is how every
  /// other comparison reports a boolean here.
  @override
  BytesOutput generateASTExpressionNullCheck(
    ASTExpressionNullCheck expression, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    final stackLng0 = context.stackLength;

    generateASTExpression(expression.expression, out: out, context: context);
    var type = context.stackGet(0)!.type;
    context.stackDrop();

    var wantEquals = !expression.negated;

    if (_isObjectType(type)) {
      // A boxed value: compare the pointer against the null box.
      out.write(Wasm32.i32Const(_boxPtrNull));
      out.writeByte(
        wantEquals ? Wasm32.i32Equals : Wasm32.i32NotEquals,
        description: "[OP] boxed `${wantEquals ? '==' : '!='} null`",
      );
    } else {
      // A concrete slot (`int`, `double`, `String`, an instance) has no null
      // representation in Wasm, so the answer is constant. The operand is
      // still emitted and dropped, to keep its side effects.
      out.writeByte(
        Wasm.drop,
        description: "[OP] drop non-null operand of `== null`",
      );
      out.write(
        Wasm32.i32Const(wantEquals ? 0 : 1),
        description:
            "[OP] `${wantEquals ? '==' : '!='} null` on a non-nullable "
            "$type is constant",
      );
    }

    context.stackPush(_astTypeInt32, "`== null` result");
    context.assertStackLength(stackLng0 + 1, "After `== null`");

    return out;
  }

  @override
  BytesOutput generateASTExpressionOperation(
    ASTExpressionOperation expression, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    final expression1 = expression.expression1;
    final expression2 = expression.expression2;

    // `x == 0` fast-path (`i64.eqz`). Only valid for the `equals` operator:
    // applying it to `>`, `<`, `!=`, etc. with a literal `0` would silently
    // compute an equals-to-zero instead of the requested comparison.
    if (expression.operator == ASTExpressionOperator.equals &&
        expression2 is ASTExpressionLiteral) {
      var expression2Value = expression2.value;
      if (expression2Value is ASTValueInt && expression2Value.isZero) {
        return generateASTExpressionOperationEqualsToZero(
          expression1,
          out: out,
          context: context,
        );
      }
    }

    final stackLng0 = context.stackLength;

    var exp1Out = generateASTExpression(expression1, context: context);

    final stackLng1 = context.assertStackLength(
      stackLng0 + 1,
      "After operation expression (left)",
    );

    final stack1 = context.stackGet(0)!;

    var exp2Out = generateASTExpression(expression2, context: context);

    final stackLng2 = context.assertStackLength(
      stackLng1 + 1,
      "After operation expression (right)",
    );

    final stack2 = context.stackGet(0)!;

    var stackType1 = stack1.type;
    var stackType2 = stack2.type;

    // String `+` -> concatenation. Each operand is coerced to a String handle
    // (a String is already a handle; int/double/bool route through the same
    // host converters used by string interpolation), so `String + number`
    // (from Java/Kotlin/C#/JS/TS, e.g. `"n=" + n`) works.
    if (expression.operator == ASTExpressionOperator.add &&
        (stackType1 is ASTTypeString || stackType2 is ASTTypeString)) {
      // The operands were tracked on the virtual stack during generation above;
      // drop them and re-track as each is emitted then coerced, so the coercion
      // helpers see the correct top-of-stack value (the conversion bytes must be
      // interleaved between the two operand buffers).
      context.stackDrop(); // operand 2 (stack2)
      context.stackDrop(); // operand 1 (stack1)

      out.writeBytes(exp1Out);
      context.stackPush(stackType1, "string `+` operand 1");
      _emitToStringHandle(out, context, stackType1);

      out.writeBytes(exp2Out);
      context.stackPush(stackType2, "string `+` operand 2");
      _emitToStringHandle(out, context, stackType2);

      context.assertStackLength(stackLng2, "After push string operands");
      _emitStringConcat2(out, context);
      context.assertStackLength(stackLng0 + 1, "After string concat");
      return out;
    }

    // String `==` / `!=` -> content equality via the `__streq` helper. Both
    // operands are String handles (i32 pointers); a numeric comparison would
    // test pointer identity (and emit invalid Wasm when the pointers reach an
    // `i64.eq`), not content. `__streq(a, b)` returns an i32 bool (1 if the
    // bytes are equal); `!=` inverts it with `i32.eqz`. The result is an i32
    // bool, matching the numeric `==`/`!=` comparison result type below.
    if ((expression.operator == ASTExpressionOperator.equals ||
            expression.operator == ASTExpressionOperator.notEquals) &&
        stackType1 is ASTTypeString &&
        stackType2 is ASTTypeString) {
      var module = context.module!;
      module.ensureStrEqFunction();
      var strEqIndex = module.synthFunctionIndex('__streq')!;

      // Operands were tracked on the virtual stack during generation above;
      // drop them and re-emit the buffers so the two String handles sit on the
      // real stack as `__streq`'s two i32 arguments.
      context.stackDrop(); // operand 2 (stack2)
      context.stackDrop(); // operand 1 (stack1)

      out.writeBytes(exp1Out);
      out.writeBytes(exp2Out);
      out.write(Wasm.call(strEqIndex)); // __streq(a, b) -> i32 0/1
      if (expression.operator == ASTExpressionOperator.notEquals) {
        out.writeByte(
          Wasm32.i32EqualsToZero,
          description: "[OP] invert __streq for String `!=`",
        );
      }
      context.stackPush(_astTypeInt32, "String ==/!= result (i32 bool)");
      context.assertStackLength(stackLng0 + 1, "After String equality");
      return out;
    }

    // A boxed `Object`/`dynamic` operand (e.g. an element read from a
    // `List<Object>`, which the interpreter treats dynamically) carries an i32
    // box pointer, not a number. Unbox it to a concrete numeric value before
    // arithmetic/comparison; otherwise the box pointer would flow straight into
    // `i64.add`/`f64.div` and produce invalid Wasm. Division always computes in
    // f64; otherwise the target follows the other (numeric) operand, defaulting
    // to int. (String operands are handled by the concatenation branch above.)
    if (_isObjectType(stackType1) || _isObjectType(stackType2)) {
      var op = expression.operator;
      var isDivide =
          op == ASTExpressionOperator.divide ||
          op == ASTExpressionOperator.divideAsInt ||
          op == ASTExpressionOperator.divideAsDouble;
      bool isDouble(ASTType t) => t == _astTypeDouble || t == _astTypeDouble64;
      ASTType target =
          (isDivide || isDouble(stackType1) || isDouble(stackType2))
          ? _astTypeDouble64
          : _astTypeInt64;
      if (_isObjectType(stackType1)) {
        _emitUnboxNumberInto(exp1Out, context, target);
        stackType1 = target;
        context.stackReplaceAt(1, target, "unbox Object operand 1 -> $target");
      }
      if (_isObjectType(stackType2)) {
        _emitUnboxNumberInto(exp2Out, context, target);
        stackType2 = target;
        context.stackReplace(target, "unbox Object operand 2 -> $target");
      }
    }

    var operationType = _getOperationType(expression, stackType1, stackType2);

    if (operationType == _astTypeDouble ||
        (stackType1 == _astTypeDouble || stackType2 == _astTypeDouble)) {
      operationType = _fixStackOpsAsFloat64(
        stackType1,
        stackType2,
        exp1Out,
        exp2Out,
        out,
        context,
      );

      stackType1 = stackType2 = operationType;

      context.assertStackLength(
        stackLng2,
        "After stack fix for Float64 operation.",
      );
    } else if (operationType == _astTypeInt ||
        (stackType1 == _astTypeInt || stackType2 == _astTypeInt)) {
      operationType = _fixStackOpsAsInt(
        stackType1,
        stackType2,
        exp1Out,
        exp2Out,
        out,
        context,
      );

      stackType1 = stackType2 = operationType;

      context.assertStackLength(
        stackLng2,
        "After stack fix for int operation.",
      );
    } else {
      out.writeBytes(exp1Out);
      out.writeBytes(exp2Out);

      context.assertStackLength(
        stackLng2,
        "After push stack values for operation.",
      );
    }

    void writeOperation(ASTType type, int op, String desc, String opDesc) {
      out!.writeByte(op, description: "[OP] operator: $desc");
      context!.stackOperationBinary(type, opDesc);
    }

    void writeOperationDoubleOr(
      ASTType typeDouble,
      int opDouble,
      String descDouble,
      String opDescDouble,
      ASTType type,
      int op,
      String desc,
      String opDesc,
    ) {
      if (stackType2 == _astTypeDouble) {
        writeOperation(typeDouble, opDouble, descDouble, opDescDouble);
      } else {
        writeOperation(type, op, desc, opDesc);
      }
    }

    final opInt32 = operationType?.equalsStrict(_astTypeInt32) ?? false;

    switch (expression.operator) {
      case ASTExpressionOperator.add:
        {
          writeOperationDoubleOr(
            _astTypeDouble64,
            Wasm64.f64Add,
            "add(f64)",
            "f64.add",
            _astTypeInt64,
            opInt32 ? Wasm32.i32Add : Wasm64.i64Add,
            opInt32 ? "add(i32)" : "add(i64)",
            opInt32 ? "i32.add" : "i64.add",
          );
        }
      case ASTExpressionOperator.subtract:
        {
          writeOperationDoubleOr(
            _astTypeDouble64,
            Wasm64.f64Subtract,
            "sub(f64)",
            "f64.sub",
            _astTypeInt64,
            opInt32 ? Wasm32.i32Subtract : Wasm64.i64Subtract,
            opInt32 ? "sub(i32)" : "sub(i64)",
            opInt32 ? "i32.sub" : "i64.sub",
          );
        }
      case ASTExpressionOperator.multiply:
        {
          writeOperationDoubleOr(
            _astTypeDouble64,
            Wasm64.f64Multiply,
            "multiply(f64)",
            "f64.multiply",
            _astTypeInt64,
            opInt32 ? Wasm32.i32Multiply : Wasm64.i64Multiply,
            opInt32 ? "multiply(i32)" : "multiply(i64)",
            opInt32 ? "i32.multiply" : "i64.multiply",
          );
        }
      case ASTExpressionOperator.divide:
        {
          _checkStackStatusF64(stackType1, stackType2);

          out.writeByte(
            Wasm64.f64Divide,
            description: "[OP] operator: divide(f64)",
          );
          context.stackOperationBinary(_astTypeDouble64, "Wasm64.f64Divide");

          // `/` on integer operands is *integer* division in Java/Kotlin/C#
          // (the AST resolves the expression to `int`): truncate to i64, and on
          // divide-by-zero raise the matching catchable exception. Dart's `/`
          // resolves to `double` and stays an f64 quotient.
          var resolved = expression.resolveType(null);
          if (resolved is ASTTypeInt) {
            if (context.exceptionMode) {
              _emitGuardedF64ToI64(
                out,
                context,
                msg: 'IntegerDivisionByZeroException',
              );
            } else {
              out.writeByte(
                Wasm64.f64TruncateToI64Signed,
                description: "[OP] integer divide -> i64",
              );
            }
            context.stackReplace(_astTypeInt64, "integer divide -> i64");
          }
        }
      case ASTExpressionOperator.divideAsInt:
        {
          _checkStackStatusF64(stackType1, stackType2);

          out.writeByte(
            Wasm64.f64Divide,
            description: "[OP] operator: divide(f64)",
          );
          context.stackOperationBinary(_astTypeDouble64, "Wasm64.f64Divide");

          if (context.exceptionMode) {
            // Guard the truncation: `i64.trunc_f64_s` traps on Infinity/NaN
            // (e.g. `1 ~/ 0`). Instead raise a catchable exception (matching the
            // AST interpreter's message) and yield 0.
            _emitGuardedF64ToI64(out, context);
          } else {
            out.writeByte(
              Wasm64.f64TruncateToI64Signed,
              description: "[OP] Wasm64.f64TruncateToi64Signed",
            );
          }

          context.stackReplace(_astTypeInt64, "i64.truncate_f64_signed");
        }
      case ASTExpressionOperator.divideAsDouble:
        {
          _checkStackStatusF64(stackType1, stackType2);

          out.writeByte(
            Wasm64.f64Divide,
            description: "[OP] operator: divide(f64)",
          );
          context.stackOperationBinary(_astTypeDouble64, "Wasm64.f64Divide");
        }
      case ASTExpressionOperator.equals:
        {
          writeOperationDoubleOr(
            _astTypeInt32,
            Wasm64.f64Equals,
            "equals(f64)",
            "f64.equals",
            _astTypeInt32,
            opInt32 ? Wasm32.i32Equals : Wasm64.i64Equals,
            "equals(i64)",
            opInt32 ? "i32.equals" : "i64.equals",
          );
        }
      case ASTExpressionOperator.notEquals:
        {
          writeOperationDoubleOr(
            _astTypeInt32,
            Wasm64.f64NotEquals,
            "notEquals(f64)",
            "f64.NotEq",
            _astTypeInt32,
            opInt32 ? Wasm32.i32NotEquals : Wasm64.i64NotEquals,
            "notEquals(i64)",
            opInt32 ? "i32NotEqual" : "i64NotEqual",
          );
        }
      case ASTExpressionOperator.greater:
        {
          writeOperationDoubleOr(
            _astTypeInt32,
            Wasm64.f64GreaterThan,
            "greaterThan(f64)",
            "f64.greaterThan",
            _astTypeInt32,
            Wasm64.i64GreaterThanSigned,
            "greaterThan(i64)",
            "i64.greaterThanSigned",
          );
        }
      case ASTExpressionOperator.greaterOrEq:
        {
          writeOperationDoubleOr(
            _astTypeInt32,
            Wasm64.f64GreaterThanOrEquals,
            "greaterEquals(f64)",
            "f64.greaterOrEqualsSigned",
            _astTypeInt32,
            Wasm64.i64GreaterThanOrEqualsSigned,
            "greaterEquals(i64)",
            "i64.greaterOrEqualsSigned",
          );
        }
      case ASTExpressionOperator.lower:
        {
          writeOperationDoubleOr(
            _astTypeInt32,
            Wasm64.f64LessThan,
            "lowerThan(f64)",
            "f64.lowerThanSigned",
            _astTypeInt32,
            Wasm64.i64LessThanSigned,
            "lowerThan(i64)",
            "i64.lowerThanSigned",
          );
        }
      case ASTExpressionOperator.lowerOrEq:
        {
          writeOperationDoubleOr(
            _astTypeInt32,
            Wasm64.f64LessThanOrEquals,
            "lowerEquals(f64)",
            "f64.lowerOrEqualsSigned",
            _astTypeInt32,
            Wasm64.i64LessThanOrEqualsSigned,
            "lowerEquals(i64)",
            "i64.lowerOrEqualsSigned",
          );
        }
      case ASTExpressionOperator.remainder:
        {
          // Dart `%` always yields a non-negative result in `[0, |b|)`, which
          // differs from Wasm's truncated `i64.rem_s` / the f64 formula for
          // negative operands; the helpers apply the sign correction.
          if (stackType2 == _astTypeDouble) {
            _writeDoubleModulo(out, context);
          } else {
            _writeIntModulo(out, context);
          }
        }
      case ASTExpressionOperator.bitwiseAnd:
        {
          writeOperation(
            opInt32 ? _astTypeInt32 : _astTypeInt64,
            opInt32 ? Wasm32.i32BitwiseAnd : Wasm64.i64BitwiseAnd,
            opInt32 ? "and(i32)" : "and(i64)",
            opInt32 ? "i32.and" : "i64.and",
          );
        }
      case ASTExpressionOperator.bitwiseOr:
        {
          writeOperation(
            opInt32 ? _astTypeInt32 : _astTypeInt64,
            opInt32 ? Wasm32.i32BitwiseOr : Wasm64.i64BitwiseOr,
            opInt32 ? "or(i32)" : "or(i64)",
            opInt32 ? "i32.or" : "i64.or",
          );
        }
      case ASTExpressionOperator.bitwiseXor:
        {
          writeOperation(
            opInt32 ? _astTypeInt32 : _astTypeInt64,
            opInt32 ? Wasm32.i32BitwiseXor : Wasm64.i64BitwiseXor,
            opInt32 ? "xor(i32)" : "xor(i64)",
            opInt32 ? "i32.xor" : "i64.xor",
          );
        }
      case ASTExpressionOperator.shiftLeft:
        {
          writeOperation(
            opInt32 ? _astTypeInt32 : _astTypeInt64,
            opInt32 ? Wasm32.i32ShiftLeft : Wasm64.i64ShiftLeft,
            opInt32 ? "shl(i32)" : "shl(i64)",
            opInt32 ? "i32.shl" : "i64.shl",
          );
        }
      case ASTExpressionOperator.shiftRight:
        {
          writeOperation(
            opInt32 ? _astTypeInt32 : _astTypeInt64,
            opInt32 ? Wasm32.i32ShiftRightSigned : Wasm64.i64ShiftRightSigned,
            opInt32 ? "shr_s(i32)" : "shr_s(i64)",
            opInt32 ? "i32.shr_s" : "i64.shr_s",
          );
        }
      default:
        // `and`/`or` are handled before operand evaluation (short-circuit).
        throw UnsupportedError(
          "Wasm Operator not supported: ${expression.operator.name}",
        );
    }

    context.assertStackLength(stackLng2 - 1, "After operation result");
    context.assertStackLength(stackLng0 + 1, "After operation result");

    return out;
  }

  void _checkStackStatusF64(ASTType stackType1, ASTType stackType2) {
    if (stackType1 != _astTypeDouble || stackType2 != _astTypeDouble) {
      throw StateError(
        "Stack status error> `f64.divide` needs 2 f64 values in the top of the stack",
      );
    }
  }

  /// Emits Dart integer `%` for `[a, b]` on the stack (both i64).
  ///
  /// `i64.rem_s` yields a truncated remainder (sign of the dividend), but Dart
  /// `%` is always in `[0, |b|)`. So: `r = a rem b; if (r < 0) r += |b|`,
  /// computed branchlessly with `select` and two scratch locals.
  void _writeIntModulo(BytesOutput out, WasmContext context) {
    var bs = context.scratchLocal(_astTypeInt64, 0);
    var rs = context.scratchLocal(_astTypeInt64, 1);

    out.write(Wasm.localTee(bs), description: "[OP] % keep b");
    out.writeByte(Wasm64.i64RemainderSigned, description: "[OP] i64.rem_s");
    out.write(Wasm.localTee(rs), description: "[OP] % keep r");

    // |b| = (b < 0) ? -b : b
    out.write(Wasm64.i64Const(0));
    out.write(Wasm.localGet(bs));
    out.writeByte(Wasm64.i64Subtract, description: "[OP] -b");
    out.write(Wasm.localGet(bs));
    out.write(Wasm.localGet(bs));
    out.write(Wasm64.i64Const(0));
    out.writeByte(Wasm64.i64LessThanSigned, description: "[OP] b < 0");
    out.writeByte(Wasm.select, description: "[OP] |b|");

    // addend = (r < 0) ? |b| : 0
    out.write(Wasm64.i64Const(0));
    out.write(Wasm.localGet(rs));
    out.write(Wasm64.i64Const(0));
    out.writeByte(Wasm64.i64LessThanSigned, description: "[OP] r < 0");
    out.writeByte(Wasm.select, description: "[OP] addend");

    out.writeByte(Wasm64.i64Add, description: "[OP] r + addend (Dart %)");

    context.stackOperationBinary(_astTypeInt64, "i64 Dart modulo");
  }

  /// Emits Dart double `%` for `[a, b]` on the stack (both f64).
  ///
  /// f64 has no remainder opcode: `r = a - trunc(a / b) * b`, then the same
  /// non-negative correction `if (r < 0) r += |b|`. Uses three scratch locals.
  void _writeDoubleModulo(BytesOutput out, WasmContext context) {
    var af = context.scratchLocal(_astTypeDouble64, 0);
    var bf = context.scratchLocal(_astTypeDouble64, 1);
    var rf = context.scratchLocal(_astTypeDouble64, 2);

    out.write(Wasm.localSet(bf), description: "[OP] % save b");
    out.write(Wasm.localSet(af), description: "[OP] % save a");

    // r = a - trunc(a / b) * b
    out.write(Wasm.localGet(af));
    out.write(Wasm.localGet(af));
    out.write(Wasm.localGet(bf));
    out.writeByte(Wasm64.f64Divide, description: "[OP] a / b");
    out.writeByte(
      Wasm64.f64TruncateToF64Signed,
      description: "[OP] trunc(a / b)",
    );
    out.write(Wasm.localGet(bf));
    out.writeByte(Wasm64.f64Multiply, description: "[OP] trunc(a / b) * b");
    out.writeByte(Wasm64.f64Subtract, description: "[OP] a - ...");
    out.write(Wasm.localTee(rf), description: "[OP] % keep r");

    // addend = (r < 0) ? |b| : 0
    out.write(Wasm.localGet(bf));
    out.writeByte(Wasm64.f64Absolute, description: "[OP] |b|");
    out.write(Wasm64.f64Const(0.0));
    out.write(Wasm.localGet(rf));
    out.write(Wasm64.f64Const(0.0));
    out.writeByte(Wasm64.f64LessThan, description: "[OP] r < 0");
    out.writeByte(Wasm.select, description: "[OP] addend");

    out.writeByte(Wasm64.f64Add, description: "[OP] r + addend (Dart %)");

    context.stackOperationBinary(_astTypeDouble64, "f64 Dart modulo");
  }

  @override
  BytesOutput generateASTExpressionNullValue(
    ASTExpressionNullValue expression, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    // `null` is the boxed-`Object` pointer 0 (see [_boxPtrNull]): the heap never
    // hands out address 0, so it is distinguishable from every real box, and it
    // needs no allocation. It types as `Object`, so it unifies with any other
    // boxed value — e.g. the two arms of `c ? args[0] : null`.
    //
    // Wasm has no null in its *numeric* domain, so this only works where the
    // value stays boxed; a `null` flowing into an `int`/`double` slot still
    // fails, at the point of that conversion.
    out.write(
      Wasm32.i32Const(_boxPtrNull),
      description: "[OP] null (boxed Object pointer 0)",
    );
    context.stackPush(ASTTypeObject.instance, "null");

    return out;
  }

  @override
  BytesOutput generateASTExpressionVariableAccess(
    ASTExpressionVariableAccess expression, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    var name = expression.variable.name;

    // A captured variable (closure body) or a boxed variable (enclosing scope)
    // lives in a shared heap cell — read it by dereferencing the box pointer.
    if (context.isCapturedVariable(name) || context.isBoxedVariable(name)) {
      final s0 = context.stackLength;
      var type = _emitBoxPointer(out, context, name);
      _emitElemLoad(out, type, 0);
      context.stackPush(_elemStackType(type), "boxed `$name` (deref)");
      context.assertStackLength(s0 + 1, "After boxed read `$name`");
      return out;
    }

    // A bare name that is a class field (and not a local) reads `this + offset`.
    if (context.isFieldAccess(name)) {
      return _generateFieldGet(out, context, name);
    }

    // A bare `static` field of the current class reads its module global.
    var staticKey = _staticFieldKey(context, name);
    if (staticKey != null) {
      final s0 = context.stackLength;
      var type = context.module!.staticFieldTypeOf(staticKey)!;
      out.write(
        Wasm.globalGet(context.module!.staticFieldGlobalIndexOf(staticKey)!),
        description: "[OP] static field get `$staticKey`",
      );
      context.stackPush(_wasmStackTypeFor(type), "static field `$name`");
      context.assertStackLength(s0 + 1, "After static field get `$name`");
      return out;
    }

    var localVar = _getLocalVariable(context, name);

    final stackLng0 = context.stackLength;

    _localVariableGet(out, context, localVar.index, name);

    // Booleans are represented as i32 on the Wasm stack, so a `bool` local is
    // pushed with the i32 type to stay consistent with comparisons/logic.
    var pushType = localVar.type is ASTTypeBool ? _astTypeInt32 : localVar.type;
    context.stackPush(pushType, 'Local get: ${localVar.index} \$$name');

    context.assertStackLength(
      stackLng0 + 1,
      "After variable push: ${localVar.index} \$$name",
    );

    return out;
  }

  @override
  BytesOutput generateASTExpressionVariableAssignment(
    ASTExpressionVariableAssignment expression, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    var op = expression.operator;

    var variable = expression.variable;
    var name = variable.name;

    // A captured/boxed variable stores into its shared heap cell.
    if (context.isCapturedVariable(name) || context.isBoxedVariable(name)) {
      return _emitBoxedStore(expression, out, context);
    }

    // A bare name that is a class field (and not a local) stores to
    // `this + offset`.
    if (context.isFieldAccess(name)) {
      return _generateFieldSet(expression, out: out, context: context);
    }

    // A bare `static` field of the current class stores to its module global.
    var staticKey = _staticFieldKey(context, name);
    if (staticKey != null) {
      final s0 = context.stackLength;
      if (op == ASTAssignmentOperator.set) {
        generateASTExpression(
          expression.expression,
          out: out,
          context: context,
        );
      } else {
        // Compound op: read the current value (`ASTExpressionVariableAccess`
        // resolves to the static global), apply the operator with the RHS.
        generateASTExpressionOperation(
          ASTExpressionOperation(
            ASTExpressionVariableAccess(variable),
            op.asASTExpressionOperator!,
            expression.expression,
          ),
          out: out,
          context: context,
        );
      }
      context.assertStackLength(s0 + 1, "After static assign value `$name`");
      out.write(
        Wasm.globalSet(context.module!.staticFieldGlobalIndexOf(staticKey)!),
        description: "[OP] static field set `$staticKey`",
      );
      // Keep the phantom virtual entry (the real stack is balanced by
      // `global.set`), matching the local-assignment contract.
      return out;
    }

    var localVar = _getLocalVariable(context, name);

    final stackLng0 = context.stackLength;

    switch (op) {
      case ASTAssignmentOperator.set:
        {
          generateASTExpression(
            expression.expression,
            out: out,
            context: context,
          );
        }
      default:
        {
          var expOp = op.asASTExpressionOperator!;

          generateASTExpressionOperation(
            ASTExpressionOperation(
              ASTExpressionVariableAccess(variable),
              expOp,
              expression.expression,
            ),
            out: out,
            context: context,
          );
        }
    }

    final stackLng1 = context.assertStackLength(
      stackLng0 + 1,
      "After variable assigment expression",
    );

    _localVariableSet(out, context, localVar.index, name);

    context.assertStackLength(
      stackLng1,
      "After variable set: ${localVar.index} \$$name",
    );
    context.assertStackLength(
      stackLng0 + 1,
      "After variable declaration:  ${localVar.index} \$$name",
    );

    return out;
  }

  /// The scratch-local type matching a value of [t] on the Wasm stack:
  /// i64 for `int`, f64 for `double`, otherwise i32 (`_astTypeString`).
  ASTType _wasmLocalType(ASTType t) => t is ASTTypeInt
      ? _astTypeInt64
      : (t is ASTTypeDouble ? _astTypeDouble64 : _astTypeString);

  /// Pushes (untracked) the i32 box pointer for a captured/boxed variable
  /// [name], returning its value type. For a captured variable it is loaded
  /// from the closure environment (`env[offset]`); for a boxed variable it is
  /// the function's box local.
  ASTType _emitBoxPointer(BytesOutput out, WasmContext context, String name) {
    if (context.isCapturedVariable(name)) {
      var cap = context.capturedVariables[name]!;
      out.write(
        Wasm.localGet(context.closureEnvLocalIndex),
        description: "[OP] closure env ptr (box of `$name`)",
      );
      out.write(Wasm32.i32Load(2, cap.offset));
      return cap.type;
    }
    var b = context.boxedVariables[name]!;
    out.write(
      Wasm.localGet(b.boxLocal),
      description: "[OP] box ptr of `$name`",
    );
    return b.type;
  }

  /// Stores the assigned value into a captured/boxed variable's heap cell, then
  /// leaves the value on the stack (assignment is an expression).
  BytesOutput _emitBoxedStore(
    ASTExpressionVariableAssignment expression,
    BytesOutput out,
    WasmContext context,
  ) {
    var name = expression.variable.name;
    final s0 = context.stackLength;

    // Box pointer (untracked) first — it must sit below the value for the store.
    var type = _emitBoxPointer(out, context, name);

    // Compute the value (plain assignment) or the compound-op result.
    if (expression.operator == ASTAssignmentOperator.set) {
      generateASTExpression(expression.expression, out: out, context: context);
    } else {
      generateASTExpressionOperation(
        ASTExpressionOperation(
          ASTExpressionVariableAccess(expression.variable),
          expression.operator.asASTExpressionOperator!,
          expression.expression,
        ),
        out: out,
        context: context,
      );
    }
    context.assertStackLength(s0 + 1, "After boxed store value `$name`");

    // Keep the value (assignment result) while storing it into the cell.
    var valLocal = context.scratchLocal(_wasmLocalType(type), 46);
    out.write(Wasm.localTee(valLocal));
    _emitElemStore(out, type, 0);
    out.write(Wasm.localGet(valLocal));

    context.assertStackLength(s0 + 1, "After boxed store `$name`");
    return out;
  }

  /// Loads a class field of the current method's `this`: `this + offset`.
  BytesOutput _generateFieldGet(
    BytesOutput out,
    WasmContext context,
    String name,
  ) {
    final s0 = context.stackLength;
    var layout = context.classLayout!;
    var offset = layout.offsets[name]!;
    var fieldType = layout.types[name]!;

    out.write(
      Wasm.localGet(context.thisLocalIndex),
      description: "[OP] this (read field `$name`)",
    );
    _emitElemLoad(out, fieldType, offset);
    context.stackPush(_elemStackType(fieldType), "field `$name`");

    context.assertStackLength(s0 + 1, "After field get `$name`");
    return out;
  }

  /// Stores to a class field of the current method's `this`. Mirrors the local
  /// assignment-expression contract: the address is pushed to the real stack
  /// only and the value's virtual entry is left on the stack.
  BytesOutput _generateFieldSet(
    ASTExpressionVariableAssignment expression, {
    required BytesOutput out,
    required WasmContext context,
  }) {
    var name = expression.variable.name;
    var layout = context.classLayout!;
    var offset = layout.offsets[name]!;
    var fieldType = layout.types[name]!;

    final s0 = context.stackLength;
    var op = expression.operator;

    // Address (`this`) on the real stack; not tracked on the virtual stack so
    // the value sub-expression's relative assertions hold.
    out.write(
      Wasm.localGet(context.thisLocalIndex),
      description: "[OP] this (store field `$name`)",
    );

    if (op == ASTAssignmentOperator.set) {
      generateASTExpression(expression.expression, out: out, context: context);
    } else {
      var expOp = op.asASTExpressionOperator!;
      generateASTExpressionOperation(
        ASTExpressionOperation(
          ASTExpressionVariableAccess(expression.variable),
          expOp,
          expression.expression,
        ),
        out: out,
        context: context,
      );
    }

    // `store` consumes the address and value from the real stack; the value's
    // virtual entry stays (matching local assignment).
    _emitElemStore(out, fieldType, offset);
    context.assertStackLength(s0 + 1, "After field set `$name`");
    return out;
  }

  @override
  BytesOutput generateASTExpressionVariableDirectOperation(
    ASTExpressionVariableDirectOperation expression, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    var op = expression.operator;

    var variable = expression.variable;
    var name = variable.name;

    var localVar = _getLocalVariable(context, name);

    final stackLng0 = context.stackLength;

    var expOp = op.asASTExpressionOperator!;

    if (!expression.preOperation) {
      //throw UnsupportedError("Not supported: $name++ or $name--");
      _localVariableGet(out, context, localVar.index, name);
    }

    generateASTExpressionOperation(
      ASTExpressionOperation(
        ASTExpressionVariableAccess(variable),
        expOp,
        ASTExpressionLiteral(ASTValueInt(1)),
      ),
      out: out,
      context: context,
    );

    final stackLng1 = context.assertStackLength(
      stackLng0 + 1,
      "After variable assigment expression",
    );

    _localVariableSet(out, context, localVar.index, name);

    context.assertStackLength(
      stackLng1,
      "After variable set: ${localVar.index} \$$name",
    );
    context.assertStackLength(
      stackLng0 + 1,
      "After variable declaration:  ${localVar.index} \$$name",
    );

    if (expression.preOperation) {
      _localVariableGet(out, context, localVar.index, name);
    }

    return out;
  }

  void _localVariableGet(
    BytesOutput out,
    WasmContext? context,
    int localVarIndex,
    String name, [
    String? desc,
  ]) {
    out.write(
      Wasm.localGet(localVarIndex),
      description:
          "[OP] local get: #$localVarIndex \$$name"
          "${desc != null ? ' $desc' : ''}",
    );
  }

  void _localVariableSet(
    BytesOutput out,
    WasmContext? context,
    int localVarIndex,
    String localVarName,
  ) {
    if (context != null) {
      var localVar = context.getLocalVariableByIndex(localVarIndex);
      var stackValue = context.stackGet(localVarIndex);

      if (localVar != null && stackValue != null) {
        var localVarType = stackValue.type;
        var stackValueType = stackValue.type;

        if (!localVarType.equalsStrict(stackValueType)) {
          throw StateError(
            "Setting local variable#$localVarIndex `$localVarName` with wrong type> localVar:$localVarType != stackValue:$stackValueType",
          );
        }
      }
    }

    out.write(
      Wasm.localSet(localVarIndex),
      description: "[OP] local set: #$localVarIndex \$$localVarName",
    );
  }

  @override
  BytesOutput generateASTExpressionVariableEntryAccess(
    ASTExpressionVariableEntryAccess expression, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    var name = expression.variable.name;
    var localVar = _getLocalVariable(context, name);
    var containerType = localVar.type;

    // Nested/chained access (`m[0][1]` / `m['a']['b']`): push the base container,
    // then apply each index to the value produced by the previous level (an inner
    // `List`/`Map` pointer). Each intermediate value stays on the stack.
    if (expression.extraIndices.isNotEmpty) {
      final s0 = context.stackLength;
      _localVariableGet(out, context, localVar.index, name);
      context.stackPush(containerType, "chain base `$name`");
      var curType = containerType;
      for (var indexExpr in [
        expression.expression,
        ...expression.extraIndices,
      ]) {
        curType = _emitApplyIndexOnStack(out, context, curType, indexExpr);
      }
      context.assertStackLength(s0 + 1, "After chained index `$name`");
      return out;
    }

    if (containerType is ASTTypeMap) {
      return _generateMapGet(expression, localVar, out: out, context: context);
    }

    // `s[i]` on a String: a fresh length-1 String holding the byte at `s + 4 + i`
    // (Dart's `String[]` returns a length-1 String).
    if (containerType is ASTTypeString) {
      return _generateStringIndexAccess(
        localVar,
        name,
        expression.expression,
        out: out,
        context: context,
      );
    }

    if (containerType is! ASTTypeArray) {
      throw UnimplementedError(
        "Wasm index access on `$name` ($containerType) is not supported yet.",
      );
    }
    var elemType = containerType.componentType;
    var size = _elemSize(elemType);

    final s0 = context.stackLength;

    // addr = dataPtr + index*size; then load the element.
    _localVariableGet(out, context, localVar.index, name); // header ptr (raw)
    out.write(Wasm32.i32Load(2, 8)); // dataPtr = load(header, 8)
    generateASTExpression(
      expression.expression,
      out: out,
      context: context,
    ); // index (i64, tracked)
    out.writeByte(Wasm64.i64WrapToi32); // index -> i32
    out.write(Wasm32.i32Const(size));
    out.writeByte(Wasm32.i32Multiply);
    out.writeByte(Wasm32.i32Add); // dataPtr + index*size
    _emitElemLoad(out, elemType, 0);

    context.stackDrop(); // the index
    context.stackPush(_elemStackType(elemType), "list[index]");
    context.assertStackLength(s0 + 1, "After list index");
    return out;
  }

  /// Applies one subscript to the container whose header pointer is on top of the
  /// (real and virtual) Wasm stack, typed [containerType]. Reads the element at
  /// [indexExpr], replacing the container on the stack with the element value.
  /// Returns the element/value type (used to drive the next chained level).
  ASTType _emitApplyIndexOnStack(
    BytesOutput out,
    WasmContext context,
    ASTType containerType,
    ASTExpression indexExpr,
  ) {
    if (containerType is ASTTypeArray) {
      var elemType = containerType.componentType;
      var size = _elemSize(elemType);
      // stack: [header] -> [dataPtr]
      out.write(Wasm32.i32Load(2, 8)); // dataPtr = load(header, 8)
      generateASTExpression(
        indexExpr,
        out: out,
        context: context,
      ); // index (i64)
      out.writeByte(Wasm64.i64WrapToi32);
      out.write(Wasm32.i32Const(size));
      out.writeByte(Wasm32.i32Multiply);
      out.writeByte(Wasm32.i32Add); // dataPtr + index*size
      _emitElemLoad(out, elemType, 0);
      context.stackDrop(); // the index
      context.stackDrop(); // the container
      context.stackPush(_elemStackType(elemType), "list[index] (chain)");
      return elemType;
    }

    if (containerType is ASTTypeMap) {
      var mapType = _requireMapType(containerType, 'chain', 'm[k]');
      var keyType = mapType.keyType;
      var valueType = mapType.valueType;
      var valSize = _elemSize(valueType);

      var hdr = context.scratchLocal(_astTypeString, 15);
      var keys = context.scratchLocal(_astTypeString, 16);
      var iLoc = context.scratchLocal(_astTypeString, 18);
      var keyLoc = context.scratchLocal(keyType, 19);
      var result = context.scratchLocal(valueType, 25);

      // header is on the stack: pop it into a local for the scan.
      out.write(Wasm.localSet(hdr));
      context.stackDrop(); // the container
      generateASTExpression(indexExpr, out: out, context: context); // key
      context.stackDrop();
      out.write(Wasm.localSet(keyLoc));
      _emitZeroDefault(out, valueType);
      out.write(Wasm.localSet(result));

      _emitMapScan(
        out,
        context,
        keyType: keyType,
        hdrScratch: hdr,
        keysScratch: keys,
        iScratch: iLoc,
        keyScratch: keyLoc,
        onMatch: () {
          out.write(Wasm.localGet(hdr));
          out.write(Wasm32.i32Load(2, 12)); // valuesPtr
          out.write(Wasm.localGet(iLoc));
          out.write(Wasm32.i32Const(valSize));
          out.writeByte(Wasm32.i32Multiply);
          out.writeByte(Wasm32.i32Add);
          _emitElemLoad(out, valueType, 0);
          out.write(Wasm.localSet(result));
        },
      );

      out.write(Wasm.localGet(result));
      context.stackPush(_elemStackType(valueType), "map[key] (chain)");
      return valueType;
    }

    throw UnimplementedError(
      "Wasm chained index access on $containerType is not supported yet.",
    );
  }

  /// `m[k]` map lookup: linear scan by key; pushes the matching value, or a
  /// zero/null default when the key is absent (Dart returns `null`; tests use
  /// present keys).
  BytesOutput _generateMapGet(
    ASTExpressionVariableEntryAccess expression,
    ({ASTType type, int index}) mapVar, {
    required BytesOutput out,
    required WasmContext context,
  }) {
    var mapType = _requireMapType(
      mapVar.type,
      expression.variable.name,
      'm[k]',
    );
    var keyType = mapType.keyType;
    var valueType = mapType.valueType;
    var valSize = _elemSize(valueType);

    var hdr = context.scratchLocal(_astTypeString, 15);
    var keys = context.scratchLocal(_astTypeString, 16);
    var iLoc = context.scratchLocal(_astTypeString, 18);
    var keyLoc = context.scratchLocal(keyType, 19); // i64 (int) or i32 (String)
    var result = context.scratchLocal(valueType, 25);

    final s0 = context.stackLength;

    // hdr = map header
    _localVariableGet(out, context, mapVar.index, expression.variable.name);
    out.write(Wasm.localSet(hdr));
    // key = eval(k)
    generateASTExpression(expression.expression, out: out, context: context);
    context.stackDrop();
    out.write(Wasm.localSet(keyLoc));
    // result = 0 (default)
    _emitZeroDefault(out, valueType);
    out.write(Wasm.localSet(result));

    _emitMapScan(
      out,
      context,
      keyType: keyType,
      hdrScratch: hdr,
      keysScratch: keys,
      iScratch: iLoc,
      keyScratch: keyLoc,
      onMatch: () {
        // result = values[i]
        out.write(Wasm.localGet(hdr));
        out.write(Wasm32.i32Load(2, 12)); // valuesPtr
        out.write(Wasm.localGet(iLoc));
        out.write(Wasm32.i32Const(valSize));
        out.writeByte(Wasm32.i32Multiply);
        out.writeByte(Wasm32.i32Add);
        _emitElemLoad(out, valueType, 0);
        out.write(Wasm.localSet(result));
      },
    );

    out.write(Wasm.localGet(result));
    context.stackPush(_elemStackType(valueType), "map[key]");
    context.assertStackLength(s0 + 1, "After map[key]");
    return out;
  }

  /// Pushes a zero/null default value of [type] (i64 0 / f64 0 / i32 0).
  void _emitZeroDefault(BytesOutput out, ASTType type) {
    if (type is ASTTypeInt) {
      out.write(Wasm64.i64Const(0));
    } else if (type is ASTTypeDouble) {
      out.write(Wasm64.f64Const(0));
    } else {
      out.write(Wasm32.i32Const(0)); // String/bool -> null ptr / false
    }
  }

  /// Subscript assignment `m[k] = v` (map) or `a[i] = v` (list). Emitted as a
  /// void statement (nothing left on the stack).
  BytesOutput _generateWasmEntryAssignment(
    ASTExpressionVariableEntryAssignment expression, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    // Desugar a compound assignment `c[k] OP= v` into `c[k] = (c[k] OP v)`
    // (carrying any chained indices so `m[0][1] += v` desugars correctly).
    if (expression.operator != ASTAssignmentOperator.set) {
      var binOp = _compoundToOperator(expression.operator);
      var access = ASTExpressionVariableEntryAccess(
        expression.variable,
        expression.keyExpression,
        expression.extraKeys,
      );
      var operation = ASTExpressionOperation(
        access,
        binOp,
        expression.expression,
      );
      var desugared = ASTExpressionVariableEntryAssignment(
        expression.variable,
        expression.keyExpression,
        ASTAssignmentOperator.set,
        operation,
        expression.extraKeys,
      );
      desugared.resolveNode(expression.parentNode);
      return _generateWasmEntryAssignment(
        desugared,
        out: out,
        context: context,
      );
    }

    var name = expression.variable.name;
    var localVar = _getLocalVariable(context, name);
    var containerType = localVar.type;

    // Chained write (`m[0][1] = v`): navigate through all but the last index to
    // the innermost container, then store at the last index.
    if (expression.extraKeys.isNotEmpty) {
      return _generateChainedEntryAssignment(
        expression,
        localVar,
        out: out,
        context: context,
      );
    }

    if (containerType is ASTTypeMap) {
      return _generateMapSet(expression, localVar, out: out, context: context);
    }
    if (containerType is ASTTypeArray) {
      return _generateListIndexSet(
        expression,
        localVar,
        out: out,
        context: context,
      );
    }

    throw UnimplementedError(
      "Wasm entry assignment on `$name` ($containerType) is not supported yet.",
    );
  }

  /// Maps a compound-assignment operator (`+=`, …) to its binary operator.
  ///
  /// The mapping lives on the enum, so `%=` and the bitwise/shift forms come
  /// for free — `ASTExpressionOperation` already compiles all of them.
  ASTExpressionOperator _compoundToOperator(ASTAssignmentOperator op) {
    switch (op) {
      case ASTAssignmentOperator.set:
        throw ArgumentError("`set` is not a compound operator");
      case ASTAssignmentOperator.nullCoalesce:
        throw UnimplementedError(
          "Wasm `??=` (null-coalescing assignment) is not supported yet.",
        );
      default:
        return op.asASTExpressionOperator!;
    }
  }

  /// `a[i] = v`: store `v` at `dataPtr + i*size`.
  BytesOutput _generateListIndexSet(
    ASTExpressionVariableEntryAssignment expression,
    ({ASTType type, int index}) listVar, {
    required BytesOutput out,
    required WasmContext context,
  }) {
    var elemType = (listVar.type as ASTTypeArray).componentType;
    var size = _elemSize(elemType);

    final s0 = context.stackLength;

    // addr = dataPtr + index*size
    _localVariableGet(out, context, listVar.index, expression.variable.name);
    out.write(Wasm32.i32Load(2, 8)); // dataPtr
    generateASTExpression(
      expression.keyExpression,
      out: out,
      context: context,
    ); // index (i64)
    context.stackDrop();
    out.writeByte(Wasm64.i64WrapToi32);
    out.write(Wasm32.i32Const(size));
    out.writeByte(Wasm32.i32Multiply);
    out.writeByte(Wasm32.i32Add); // addr
    generateASTExpression(expression.expression, out: out, context: context);
    context.stackDrop();
    _emitElemStore(out, elemType, 0);

    context.assertStackLength(s0, "After list[i] = v");
    return out;
  }

  /// Chained subscript assignment `m[0][1] = v`: navigate through all but the
  /// last index (reading each level's inner `List`/`Map` pointer onto the stack)
  /// then store `v` at the last index of the innermost container. The innermost
  /// container must be a `List`; navigation levels may be `List` or `Map`.
  BytesOutput _generateChainedEntryAssignment(
    ASTExpressionVariableEntryAssignment expression,
    ({ASTType type, int index}) localVar, {
    required BytesOutput out,
    required WasmContext context,
  }) {
    var name = expression.variable.name;
    final s0 = context.stackLength;

    // Push the base container, then navigate all-but-last index.
    _localVariableGet(out, context, localVar.index, name);
    context.stackPush(localVar.type, "chain base `$name`");
    var curType = localVar.type;
    var indices = [expression.keyExpression, ...expression.extraKeys];
    for (var i = 0; i < indices.length - 1; ++i) {
      curType = _emitApplyIndexOnStack(out, context, curType, indices[i]);
    }

    if (curType is! ASTTypeArray) {
      // Writing into an innermost `Map` (`list[0]['k'] = v`) needs the full
      // scan/append path against a stack container — left as a follow-up.
      throw UnimplementedError(
        "Wasm chained assignment into $curType is not supported yet.",
      );
    }

    var elemType = curType.componentType;
    var size = _elemSize(elemType);

    // Innermost list header is on the stack: addr = dataPtr + lastIndex*size.
    out.write(Wasm32.i32Load(2, 8)); // dataPtr
    generateASTExpression(
      indices.last,
      out: out,
      context: context,
    ); // index i64
    out.writeByte(Wasm64.i64WrapToi32);
    out.write(Wasm32.i32Const(size));
    out.writeByte(Wasm32.i32Multiply);
    out.writeByte(Wasm32.i32Add); // addr
    generateASTExpression(expression.expression, out: out, context: context);
    _emitElemStore(out, elemType, 0);

    context.stackDrop(); // RHS value
    context.stackDrop(); // last index
    context.stackDrop(); // innermost container
    context.assertStackLength(s0, "After chained assignment `$name`");
    return out;
  }

  /// `m[k] = v`: scan for the key; update in place if present, else append
  /// (growing the parallel key/value buffers when full).
  BytesOutput _generateMapSet(
    ASTExpressionVariableEntryAssignment expression,
    ({ASTType type, int index}) mapVar, {
    required BytesOutput out,
    required WasmContext context,
  }) {
    var module = context.module!;
    module.requiresMemory = true;
    module.requiresHeapGlobal = true;

    var mapType = _requireMapType(
      mapVar.type,
      expression.variable.name,
      'm[k] = v',
    );
    var keyType = mapType.keyType;
    var valueType = mapType.valueType;
    var keySize = _mapKeySize(keyType);
    var valSize = _elemSize(valueType);

    var hdr = context.scratchLocal(_astTypeString, 15);
    var keys = context.scratchLocal(_astTypeString, 16);
    var iLoc = context.scratchLocal(_astTypeString, 18);
    var keyLoc = context.scratchLocal(keyType, 19); // i64 (int) or i32 (String)
    var valLoc = context.scratchLocal(valueType, 20);
    var found = context.scratchLocal(_astTypeString, 21);
    var newCap = context.scratchLocal(_astTypeString, 22);
    var newBuf = context.scratchLocal(_astTypeString, 23);

    final s0 = context.stackLength;

    // hdr = map header
    _localVariableGet(out, context, mapVar.index, expression.variable.name);
    out.write(Wasm.localSet(hdr));
    // key = eval(k) ; val = eval(v)
    generateASTExpression(expression.keyExpression, out: out, context: context);
    context.stackDrop();
    out.write(Wasm.localSet(keyLoc));
    generateASTExpression(expression.expression, out: out, context: context);
    context.stackDrop();
    out.write(Wasm.localSet(valLoc));
    // found = 0
    out.write(Wasm32.i32Const(0));
    out.write(Wasm.localSet(found));

    _emitMapScan(
      out,
      context,
      keyType: keyType,
      hdrScratch: hdr,
      keysScratch: keys,
      iScratch: iLoc,
      keyScratch: keyLoc,
      onMatch: () {
        // values[i] = val ; found = 1
        out.write(Wasm.localGet(hdr));
        out.write(Wasm32.i32Load(2, 12)); // valuesPtr
        out.write(Wasm.localGet(iLoc));
        out.write(Wasm32.i32Const(valSize));
        out.writeByte(Wasm32.i32Multiply);
        out.writeByte(Wasm32.i32Add);
        out.write(Wasm.localGet(valLoc));
        _emitElemStore(out, valueType, 0);
        out.write(Wasm32.i32Const(1));
        out.write(Wasm.localSet(found));
      },
    );

    // if (!found) append the new entry
    out.write(Wasm.localGet(found));
    out.writeByte(Wasm32.i32EqualsToZero);
    out.write(Wasm.ifInstruction(WasmType.voidType));
    {
      // grow parallel buffers if length == capacity
      out.write(Wasm.localGet(hdr));
      out.write(Wasm32.i32Load(2, 0)); // length
      out.write(Wasm.localGet(hdr));
      out.write(Wasm32.i32Load(2, 4)); // capacity
      out.writeByte(Wasm32.i32Equals);
      out.write(Wasm.ifInstruction(WasmType.voidType));
      {
        // newCap = capacity*2; if 0 -> 4
        out.write(Wasm.localGet(hdr));
        out.write(Wasm32.i32Load(2, 4));
        out.write(Wasm32.i32Const(2));
        out.writeByte(Wasm32.i32Multiply);
        out.write(Wasm.localSet(newCap));
        out.write(Wasm.localGet(newCap));
        out.writeByte(Wasm32.i32EqualsToZero);
        out.write(Wasm.ifInstruction(WasmType.voidType));
        out.write(Wasm32.i32Const(4));
        out.write(Wasm.localSet(newCap));
        out.writeByte(Wasm.end);

        // keys: newBuf = alloc(newCap*keySize); copy; hdr.keysPtr = newBuf
        _emitReallocBuffer(out, context, hdr, 8, keySize, newCap, newBuf);
        // values: newBuf = alloc(newCap*valSize); copy; hdr.valuesPtr = newBuf
        _emitReallocBuffer(out, context, hdr, 12, valSize, newCap, newBuf);

        // hdr.capacity = newCap
        out.write(Wasm.localGet(hdr));
        out.write(Wasm.localGet(newCap));
        out.write(Wasm32.i32Store(2, 4));
      }
      out.writeByte(Wasm.end);

      // keys[length] = key
      out.write(Wasm.localGet(hdr));
      out.write(Wasm32.i32Load(2, 8)); // keysPtr
      out.write(Wasm.localGet(hdr));
      out.write(Wasm32.i32Load(2, 0)); // length
      out.write(Wasm32.i32Const(keySize));
      out.writeByte(Wasm32.i32Multiply);
      out.writeByte(Wasm32.i32Add);
      out.write(Wasm.localGet(keyLoc));
      _emitElemStore(out, keyType, 0);
      // values[length] = val
      out.write(Wasm.localGet(hdr));
      out.write(Wasm32.i32Load(2, 12)); // valuesPtr
      out.write(Wasm.localGet(hdr));
      out.write(Wasm32.i32Load(2, 0)); // length
      out.write(Wasm32.i32Const(valSize));
      out.writeByte(Wasm32.i32Multiply);
      out.writeByte(Wasm32.i32Add);
      out.write(Wasm.localGet(valLoc));
      _emitElemStore(out, valueType, 0);
      // length++
      out.write(Wasm.localGet(hdr));
      out.write(Wasm.localGet(hdr));
      out.write(Wasm32.i32Load(2, 0));
      out.write(Wasm32.i32Const(1));
      out.writeByte(Wasm32.i32Add);
      out.write(Wasm32.i32Store(2, 0));
    }
    out.writeByte(Wasm.end);

    context.assertStackLength(s0, "After map[k] = v");
    return out;
  }

  /// Reallocates a header buffer field (`keysPtr`@[ptrOffset] or `valuesPtr`):
  /// `newBuf = __alloc(newCap*elemSize)`, copy `length*elemSize` old bytes, then
  /// `hdr[ptrOffset] = newBuf`.
  void _emitReallocBuffer(
    BytesOutput out,
    WasmContext context,
    int hdr,
    int ptrOffset,
    int elemSize,
    int newCap,
    int newBuf,
  ) {
    // newBuf = __alloc(newCap * elemSize)
    out.write(Wasm.localGet(newCap));
    out.write(Wasm32.i32Const(elemSize));
    out.writeByte(Wasm32.i32Multiply);
    _emitInlineAlloc(out, context);
    out.write(Wasm.localSet(newBuf));
    // memory.copy(newBuf, oldPtr, length*elemSize)
    out.write(Wasm.localGet(newBuf));
    out.write(Wasm.localGet(hdr));
    out.write(Wasm32.i32Load(2, ptrOffset)); // old buffer
    out.write(Wasm.localGet(hdr));
    out.write(Wasm32.i32Load(2, 0)); // length
    out.write(Wasm32.i32Const(elemSize));
    out.writeByte(Wasm32.i32Multiply);
    out.write(Wasm.memoryCopy);
    // hdr[ptrOffset] = newBuf
    out.write(Wasm.localGet(hdr));
    out.write(Wasm.localGet(newBuf));
    out.write(Wasm32.i32Store(2, ptrOffset));
  }

  /// `m.keys` / `m.values`: builds a fresh list (`[length][capacity][dataPtr]`)
  /// by copying the map's key (or value) buffer, and pushes its handle typed as
  /// `List<keyType>` / `List<valueType>`.
  BytesOutput _generateMapKeysOrValues(
    ASTExpressionObjectGetterAccess expression,
    ({ASTType type, int index}) mapVar, {
    required bool keys,
    required BytesOutput out,
    required WasmContext context,
  }) {
    var module = context.module!;
    module.requiresMemory = true;
    module.requiresHeapGlobal = true;

    var mapType = _requireMapType(
      mapVar.type,
      expression.variable.name,
      keys ? 'keys' : 'values',
    );
    var elemType = keys ? mapType.keyType : mapType.valueType;
    var elemSize = _elemSize(elemType);
    var srcOffset = keys ? 8 : 12; // keysPtr / valuesPtr in the map header

    var mapHdr = context.scratchLocal(_astTypeString, 15);
    var listHdr = context.scratchLocal(_astTypeString, 26);
    var listData = context.scratchLocal(_astTypeString, 27);

    final s0 = context.stackLength;

    // mapHdr = map header
    _localVariableGet(out, context, mapVar.index, expression.variable.name);
    out.write(Wasm.localSet(mapHdr));

    // listHdr = alloc(12) ; listData = alloc(length*elemSize)
    out.write(Wasm32.i32Const(_listHeaderSize));
    _emitInlineAlloc(out, context);
    out.write(Wasm.localSet(listHdr));
    out.write(Wasm.localGet(mapHdr));
    out.write(Wasm32.i32Load(2, 0)); // length
    out.write(Wasm32.i32Const(elemSize));
    out.writeByte(Wasm32.i32Multiply);
    _emitInlineAlloc(out, context);
    out.write(Wasm.localSet(listData));

    // memory.copy(listData, map[srcOffset], length*elemSize)
    out.write(Wasm.localGet(listData));
    out.write(Wasm.localGet(mapHdr));
    out.write(Wasm32.i32Load(2, srcOffset));
    out.write(Wasm.localGet(mapHdr));
    out.write(Wasm32.i32Load(2, 0)); // length
    out.write(Wasm32.i32Const(elemSize));
    out.writeByte(Wasm32.i32Multiply);
    out.write(Wasm.memoryCopy);

    // listHdr: length=len@0, capacity=len@4, dataPtr=listData@8
    out.write(Wasm.localGet(listHdr));
    out.write(Wasm.localGet(mapHdr));
    out.write(Wasm32.i32Load(2, 0));
    out.write(Wasm32.i32Store(2, 0));
    out.write(Wasm.localGet(listHdr));
    out.write(Wasm.localGet(mapHdr));
    out.write(Wasm32.i32Load(2, 0));
    out.write(Wasm32.i32Store(2, 4));
    out.write(Wasm.localGet(listHdr));
    out.write(Wasm.localGet(listData));
    out.write(Wasm32.i32Store(2, 8));

    out.write(Wasm.localGet(listHdr));
    context.stackPush(
      ASTTypeArray(elemType),
      "${expression.variable.name}.${keys ? 'keys' : 'values'}",
    );
    context.assertStackLength(s0 + 1, "After .${keys ? 'keys' : 'values'}");
    return out;
  }

  /// `.length` / `.isEmpty` / `.isNotEmpty` on a boxed-`Object` receiver
  /// (`var` / `Object?` / `dynamic`), dispatching on the box tag at runtime.
  ///
  /// Only a boxed **String** carries these members: `List`/`Map` have no boxed
  /// form at all ([_emitBoxValue] rejects them), and the int/double/bool/
  /// instance tags have no length. Any other tag traps rather than reading a
  /// length word out of a payload that isn't a string pointer.
  ///
  /// The null handling is the reason this exists. A boxed slot is the only one
  /// that can hold Wasm's `null` ([_boxPtrNull]), so:
  ///
  /// - `a?.length` yields `null` when `a` is null, which means the result is
  ///   nullable and therefore itself boxed;
  /// - `a.length` on a null box traps, matching the interpreter's
  ///   `ApolloVMNullPointerException`.
  ///
  /// That asymmetry is why the null-aware form pushes an `Object` and the plain
  /// form pushes an `int`/`bool` — a nullable result has no unboxed encoding.
  BytesOutput _generateBoxedGetterAccess(
    ASTExpressionObjectGetterAccess expression,
    int localIndex,
    String varName,
    String name, {
    required BytesOutput out,
    required WasmContext context,
  }) {
    final module = context.module;
    if (module == null) {
      throw StateError("Can't lower a boxed getter without a module.");
    }
    module.requiresMemory = true;

    final s0 = context.stackLength;
    final nullAware = expression.isNullAware;
    final isLength = name == 'length';

    // The box pointer, and the length read out of it, both need to outlive the
    // branches below.
    final boxLocal = context.scratchLocal(_astTypeString, 44); // i32 box ptr
    final tagLocal = context.scratchLocal(_astTypeString, 45); // i32 tag

    _localVariableGet(out, context, localIndex, varName);
    out.write(
      Wasm.localSet(boxLocal),
      description: "[OP] `$varName.$name`: stash box ptr",
    );

    // The result type: a null-aware access can produce `null`, so it stays
    // boxed; otherwise it is the concrete i64 length / i32 bool.
    final resultWasmType = nullAware
        ? WasmType
              .i32Type // box ptr
        : (isLength ? WasmType.i64Type : WasmType.i32Type);

    // if (box == null)
    out.write(Wasm.localGet(boxLocal));
    out.write(Wasm32.i32Const(_boxPtrNull));
    out.writeByte(Wasm32.i32Equals, description: "[OP] `$varName` is null?");
    out.write(Wasm.ifInstruction(resultWasmType));

    if (nullAware) {
      // `a?.length` on null short-circuits to null — the whole point of `?.`.
      out.write(
        Wasm32.i32Const(_boxPtrNull),
        description: "[OP] `$varName?.$name`: null receiver -> null",
      );
    } else {
      // `a.length` on null is a null dereference.
      out.writeByte(
        Wasm.unreachable,
        description: "[OP] `$varName.$name`: null dereference",
      );
    }

    out.writeByte(Wasm.elseInstruction);

    // else: read the tag and require a String box.
    out.write(Wasm.localGet(boxLocal));
    out.write(Wasm32.i32Load(2, _boxTagOffset));
    out.write(Wasm.localSet(tagLocal), description: "[OP] load box tag");

    out.write(Wasm.localGet(tagLocal));
    out.write(Wasm32.i32Const(_boxTagString));
    out.writeByte(Wasm32.i32Equals, description: "[OP] box is a String?");
    out.write(Wasm.ifInstruction(resultWasmType));

    // The payload is the string pointer; its header[0] is the UTF-8 length,
    // the same word a bare String slot reads.
    out.write(Wasm.localGet(boxLocal));
    out.write(Wasm32.i32Load(2, _boxPayloadOffset));
    out.write(Wasm32.i32Load(2, 0), description: "[OP] boxed String length");

    if (isLength) {
      out.writeByte(Wasm32.i32ExtendToI64Signed); // -> i64 (int)
      if (nullAware) {
        // Re-box: the result is `int?`, which has no unboxed encoding.
        context.stackPush(_astTypeInt64, "boxed `.length`");
        _emitBoxValue(out, context);
        context.stackDrop();
      }
    } else {
      if (name == 'isEmpty') {
        out.writeByte(Wasm32.i32EqualsToZero); // length == 0
      } else {
        out.write(Wasm32.i32Const(0));
        out.writeByte(Wasm32.i32NotEquals); // length != 0 (normalized 0/1)
      }
      if (nullAware) {
        // Box as a *bool*, not as the i32 it is represented by: `_emitBoxValue`
        // picks its scratch local from the declared type, and an int-looking
        // type would reserve an i64 one and then store this i32 into it.
        context.stackPush(ASTTypeBool.instance, "boxed `.$name`");
        _emitBoxValue(out, context);
        context.stackDrop();
      }
    }

    out.writeByte(Wasm.elseInstruction);
    // A non-String box has no `.$name`.
    out.writeByte(
      Wasm.unreachable,
      description: "[OP] `.$name` on a non-String box",
    );
    out.writeByte(Wasm.end);

    out.writeByte(Wasm.end);

    context.stackPush(
      nullAware
          ? ASTTypeObject.instance
          : (isLength ? _astTypeInt64 : _astTypeInt32),
      "$varName${nullAware ? '?' : ''}.$name",
    );
    context.assertStackLength(s0 + 1, "After boxed getter .$name");

    return out;
  }

  /// Lowers a getter access (`a.length`). Slice 1 supports `List.length`.
  BytesOutput _generateWasmGetterAccess(
    ASTExpressionObjectGetterAccess expression, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    var name = expression.name;
    var varName = expression.variable.name;

    // `EnumName.entry`: the receiver names an enum class (not a local variable),
    // so resolve it to the entry's cached `const` instance pointer (built and
    // cached lazily on first access). The subsequent `.index`/`.name`/declared
    // field load and method dispatch then flow through the normal instance
    // machinery, since the result has the enum's class layout.
    var enumPtr = _tryGenerateEnumEntryAccess(
      expression,
      varName,
      name,
      out: out,
      context: context,
    );
    if (enumPtr != null) return enumPtr;

    var localVar = _getLocalVariable(context, varName);

    var listType = localVar.type;

    // `obj.field` on a class instance: load `recv + offset`.
    var classLayout = context.module?.layoutForType(listType);
    if (classLayout != null && classLayout.offsets.containsKey(name)) {
      final s0 = context.stackLength;
      var offset = classLayout.offsets[name]!;
      var fieldType = classLayout.types[name]!;
      _localVariableGet(out, context, localVar.index, varName);
      _emitElemLoad(out, fieldType, offset);
      context.stackPush(_elemStackType(fieldType), "$varName.$name");
      context.assertStackLength(s0 + 1, "After getter $varName.$name");
      return out;
    }

    // `obj.x` where `x` is a user-declared getter: it compiled to a zero-arg
    // method (see `_buildClassFunctions`), so lower the access to a method call.
    // `hasGetter`/`methodIndex` walk the `extends` chain, so an inherited getter
    // resolves too.
    if (classLayout != null &&
        (context.module?.hasGetter(listType.name, name) ?? false)) {
      return _emitClassMethodCall(
        recv: localVar,
        receiverDesc: varName,
        methodName: name,
        arguments: const [],
        out: out,
        context: context,
      );
    }

    // A boxed-`Object` receiver (`var` / `Object?` / `dynamic`). This is the
    // only slot that can hold `null`, so it is also the only place `?.` has to
    // do anything — on a concrete slot the receiver cannot be null and the
    // null-awareness is vacuous.
    if (_isBoxedSlot(listType) &&
        const {'length', 'isEmpty', 'isNotEmpty'}.contains(name)) {
      return _generateBoxedGetterAccess(
        expression,
        localVar.index,
        varName,
        name,
        out: out,
        context: context,
      );
    }

    // `.length`/`.isEmpty`/`.isNotEmpty` read header[0] (length), which is the
    // same offset for both the list and map layouts.
    if (listType is ASTTypeArray || listType is ASTTypeMap) {
      final s0 = context.stackLength;

      if (name == 'length') {
        _localVariableGet(out, context, localVar.index, varName);
        out.write(Wasm32.i32Load(2, 0)); // length (i32)
        out.writeByte(Wasm32.i32ExtendToI64Signed); // -> i64 (int)
        context.stackPush(_astTypeInt64, "$varName.length");
        context.assertStackLength(s0 + 1, "After .length");
        return out;
      }

      if (name == 'isEmpty' || name == 'isNotEmpty') {
        _localVariableGet(out, context, localVar.index, varName);
        out.write(Wasm32.i32Load(2, 0)); // length (i32)
        if (name == 'isEmpty') {
          out.writeByte(Wasm32.i32EqualsToZero); // length == 0
        } else {
          out.write(Wasm32.i32Const(0));
          out.writeByte(Wasm32.i32NotEquals); // length != 0 (normalized 0/1)
        }
        context.stackPush(_astTypeInt32, "$varName.$name"); // bool as i32
        context.assertStackLength(s0 + 1, "After .$name");
        return out;
      }
    }

    // A String is stored as `[len:i32][utf8]`, so `.length`/`.isEmpty`/
    // `.isNotEmpty` read the same header[0] length word as a list/map. The
    // stored length is the UTF-8 byte count, which equals the Dart code-unit
    // count for ASCII text.
    if (listType is ASTTypeString) {
      final s0 = context.stackLength;

      if (name == 'length') {
        _localVariableGet(out, context, localVar.index, varName);
        out.write(Wasm32.i32Load(2, 0)); // length (i32)
        out.writeByte(Wasm32.i32ExtendToI64Signed); // -> i64 (int)
        context.stackPush(_astTypeInt64, "$varName.length");
        context.assertStackLength(s0 + 1, "After String .length");
        return out;
      }

      if (name == 'isEmpty' || name == 'isNotEmpty') {
        _localVariableGet(out, context, localVar.index, varName);
        out.write(Wasm32.i32Load(2, 0)); // length (i32)
        if (name == 'isEmpty') {
          out.writeByte(Wasm32.i32EqualsToZero); // length == 0
        } else {
          out.write(Wasm32.i32Const(0));
          out.writeByte(Wasm32.i32NotEquals); // length != 0 (normalized 0/1)
        }
        context.stackPush(_astTypeInt32, "$varName.$name"); // bool as i32
        context.assertStackLength(s0 + 1, "After String .$name");
        return out;
      }
    }

    // `m.keys` / `m.values`: materialize a fresh list (the map's key/value
    // buffer already has the list element layout), enabling `for (var k in
    // m.keys)` via the regular list for-each.
    if (listType is ASTTypeMap && (name == 'keys' || name == 'values')) {
      return _generateMapKeysOrValues(
        expression,
        localVar,
        keys: name == 'keys',
        out: out,
        context: context,
      );
    }

    if (listType is ASTTypeArray) {
      final s0 = context.stackLength;

      if (name == 'first' || name == 'last') {
        var elemType = listType.componentType;
        var size = _elemSize(elemType);
        // addr = dataPtr + index*size ; first -> index 0 ; last -> length-1.
        _localVariableGet(out, context, localVar.index, varName);
        out.write(Wasm32.i32Load(2, 8)); // dataPtr
        if (name == 'last') {
          _localVariableGet(out, context, localVar.index, varName);
          out.write(Wasm32.i32Load(2, 0)); // length
          out.write(Wasm32.i32Const(1));
          out.writeByte(Wasm32.i32Subtract); // length - 1
          out.write(Wasm32.i32Const(size));
          out.writeByte(Wasm32.i32Multiply);
          out.writeByte(Wasm32.i32Add); // dataPtr + (length-1)*size
        }
        _emitElemLoad(out, elemType, 0);
        context.stackPush(_elemStackType(elemType), "$varName.$name");
        context.assertStackLength(s0 + 1, "After .$name");
        return out;
      }
    }

    throw UnimplementedError(
      "Wasm getter `.$name` on ${localVar.type} is not supported yet.",
    );
  }

  /// If the receiver [varName] of `EnumName.member` names an `ASTClassEnum`,
  /// emits the value of that static access and returns [out]; otherwise returns
  /// `null` (the caller falls back to the local-variable getter path).
  ///
  /// - `EnumName.entry` -> the entry's cached `const` instance pointer (i32),
  ///   built lazily by a synthesized per-entry init function.
  /// - `EnumName.values` -> a freshly materialized list of all entry pointers.
  BytesOutput? _tryGenerateEnumEntryAccess(
    ASTExpressionObjectGetterAccess expression,
    String varName,
    String name, {
    required BytesOutput out,
    required WasmContext context,
  }) {
    var node = expression.getNodeIdentifier(varName);
    if (node is! ASTClassEnum) return null;
    var enumClass = node;
    var module = context.module;
    if (module == null) return null;

    if (name == 'values') {
      return _generateEnumValues(enumClass, out: out, context: context);
    }

    var entryIndex = enumClass.entries.indexWhere((e) => e.name == name);
    if (entryIndex < 0) return null; // a static member, not an enum entry

    var initIndex = _ensureEnumEntryInitFunction(enumClass, entryIndex, module);
    out.write(
      Wasm.call(initIndex),
      description: "[OP] enum `${enumClass.name}.$name` instance",
    );
    context.stackPush(enumClass.type, "enum `${enumClass.name}.$name`");
    return out;
  }

  /// Emits `EnumName.values`: a fresh list (the regular list layout
  /// `[len][cap][dataPtr]`) of the i32 entry-instance pointers, so
  /// `for (var e in EnumName.values)` works through the normal list for-each.
  BytesOutput _generateEnumValues(
    ASTClassEnum enumClass, {
    required BytesOutput out,
    required WasmContext context,
  }) {
    var module = context.module!;
    module.requiresMemory = true;
    module.requiresHeapGlobal = true;
    module.ensureAllocFunction();

    var n = enumClass.entries.length;
    const elemSize = 4; // each element is an i32 instance pointer

    var hdrLocal = context.scratchLocal(_astTypeString, 30);
    var dataLocal = context.scratchLocal(_astTypeString, 31);

    // header = alloc(12) ; data = alloc(n*4)
    out.write(Wasm32.i32Const(12));
    _emitInlineAlloc(out, context);
    out.write(Wasm.localSet(hdrLocal));
    out.write(Wasm32.i32Const(n * elemSize));
    _emitInlineAlloc(out, context);
    out.write(Wasm.localSet(dataLocal));

    // header[0]=length ; header[4]=capacity ; header[8]=dataPtr
    out.write(Wasm.localGet(hdrLocal));
    out.write(Wasm32.i32Const(n));
    out.write(Wasm32.i32Store(2, 0));
    out.write(Wasm.localGet(hdrLocal));
    out.write(Wasm32.i32Const(n));
    out.write(Wasm32.i32Store(2, 4));
    out.write(Wasm.localGet(hdrLocal));
    out.write(Wasm.localGet(dataLocal));
    out.write(Wasm32.i32Store(2, 8));

    // data[i] = <entry i instance pointer>
    for (var i = 0; i < n; ++i) {
      var initIndex = _ensureEnumEntryInitFunction(enumClass, i, module);
      out.write(Wasm.localGet(dataLocal));
      out.write(Wasm.call(initIndex));
      out.write(Wasm32.i32Store(2, i * elemSize));
    }

    out.write(Wasm.localGet(hdrLocal));
    context.stackPush(
      ASTTypeArray(enumClass.type),
      "enum `${enumClass.name}.values`",
    );
    return out;
  }

  /// Registers (once) a synthesized `() -> i32` function that lazily builds and
  /// caches the `const` instance for enum [enumClass]'s entry at [entryIndex],
  /// returning the Wasm function index to `call`.
  ///
  /// The instance is built by invoking the enum's constructor (the rich entry's
  /// arguments, or the implicit zero-arg constructor for a simple entry), then
  /// seeding the synthetic `index` (ordinal i64) and `name` (interned String
  /// ptr) slots, and caching the pointer in a per-entry i32 global so repeated
  /// access (and `==` identity) sees the one singleton.
  int _ensureEnumEntryInitFunction(
    ASTClassEnum enumClass,
    int entryIndex,
    WasmModuleContext module,
  ) {
    var entry = enumClass.entries[entryIndex];
    var synthName = '__enum_${enumClass.name}_${entry.name}';
    var existing = module.synthFunctionIndex(synthName);
    if (existing != null) return existing;

    module.requiresMemory = true;
    module.requiresHeapGlobal = true;
    module.ensureAllocFunction();

    var layout = module.classLayouts[enumClass.name]!;
    var globalIndex = module.enumEntryGlobalIndex(synthName);
    var namePtr = module.internStringLiteral(entry.name);

    // The body calls the enum's constructor, whose call index is
    // `importCount + position`. Host imports are registered lazily as bodies are
    // generated, so the body must be materialized only AFTER the import-
    // discovery pass has finalized `importCount` — otherwise a `print`/string
    // coercion elsewhere could register imports later and shift the baked call
    // index onto a host import. Defer body generation via `bodyBuilder`; only
    // the synth function's *index* is reserved eagerly here.
    BytesOutput buildBody() {
      // Build the body with a fresh context so the constructor invocation reuses
      // the full argument-evaluation / type-conversion machinery.
      var context = WasmContext(module: module);
      var instLocal = context.scratchLocal(_astTypeString, 0); // i32 ptr

      var body = newOutput();

      // if (global == 0) { build + cache }
      body.write(Wasm.globalGet(globalIndex));
      body.writeByte(Wasm32.i32EqualsToZero);
      body.write(Wasm.ifInstruction(WasmType.voidType));

      // instance = EnumName(<entry args>)  (the constructor allocates + inits).
      var args = entry.arguments ?? const <ASTExpression>[];
      var invocation = ASTExpressionLocalFunctionInvocation(
        enumClass.name,
        args.toList(),
      );
      generateASTExpressionLocalFunctionInvocation(
        invocation,
        out: body,
        context: context,
      );
      context.stackDrop(); // consumed by the local.set below
      body.write(Wasm.localSet(instLocal));

      // instance.index = ordinal (i64)
      body.write(Wasm.localGet(instLocal));
      body.write(Wasm64.i64Const(entryIndex));
      _emitElemStore(body, _astTypeInt64, layout.offsets['index']!);

      // instance.name = interned String ptr (i32)
      body.write(Wasm.localGet(instLocal));
      body.write(Wasm32.i32Const(namePtr));
      _emitElemStore(body, _astTypeString, layout.offsets['name']!);

      // instance.value = explicit declared value (i64), for explicit-value enums.
      var valueOffset = layout.offsets['value'];
      if (valueOffset != null) {
        body.write(Wasm.localGet(instLocal));
        var entryValue = entry.value;
        if (entryValue != null) {
          generateASTExpression(entryValue, out: body, context: context);
          _autoConvertStackTypes(
            context.stackGet(0)!.type,
            _astTypeInt64,
            out: body,
            context: context,
          );
          context.stackDrop(); // consumed by the store below
        } else {
          body.write(Wasm64.i64Const(0));
        }
        _emitElemStore(body, _astTypeInt64, valueOffset);
      }

      // global = instance
      body.write(Wasm.localGet(instLocal));
      body.write(Wasm.globalSet(globalIndex));
      body.writeByte(Wasm.end); // if

      // return global
      body.write(Wasm.globalGet(globalIndex));

      // Function body: local declarations (scratch locals) + ops + end.
      var outBody = newOutput();
      var scratchTypes = context.scratchLocalTypes;
      outBody.write(
        Leb128.encodeUnsigned(scratchTypes.length),
        description: "Local groups (enum init `$synthName`)",
      );
      for (var astType in scratchTypes) {
        outBody.write(
          Leb128.encodeUnsigned(1),
          description: "Scratch var count",
        );
        outBody.writeByte(
          astType.wasmCode,
          description: "Scratch (${astType.wasmType.name})",
        );
      }
      outBody.writeBytes(body);
      outBody.writeByte(Wasm.end, description: "Enum init body end");
      return outBody;
    }

    module.addSynthFunction(
      WasmSynthFunction(
        synthName,
        const [],
        const [WasmType.i32Type],
        null,
        bodyBuilder: buildBody,
      ),
    );

    return module.synthFunctionIndex(synthName)!;
  }

  /// Allocates a heap cell ("box") for each captured variable of [f] so it can
  /// be shared by reference between the function and the closures that capture
  /// it. Registers each in `context.boxedVariables`; for boxed *parameters*,
  /// emits the entry code that copies the incoming value into the cell (boxed
  /// *locals* are boxed at their declaration).
  void _setupBoxedVariables(
    ASTFunctionDeclaration f, {
    required WasmContext context,
    required BytesOutput entry,
  }) {
    var module = context.module;
    var boxed = module?.boxedVarsByFunction[f];
    if (module == null || boxed == null || boxed.isEmpty) return;

    module.requiresMemory = true;
    module.requiresHeapGlobal = true;

    var paramNames = f.parameters.allParameters.map((p) => p.name).toSet();

    var slot = 40;
    for (var entryVar in boxed.entries) {
      var name = entryVar.key;
      var type = entryVar.value;
      // The box local holds an i32 cell pointer (`_astTypeString` is the i32
      // scratch type — `_astTypeInt32` lowers to i64).
      var boxLocal = context.scratchLocal(_astTypeString, slot++);
      context.boxedVariables[name] = (type: type, boxLocal: boxLocal);

      if (paramNames.contains(name)) {
        var paramLocal = context.getLocalVariable(name);
        if (paramLocal == null) continue;
        // box = alloc(size); *box = param value
        entry.write(Wasm32.i32Const(_elemSize(type)));
        _emitInlineAlloc(entry, context);
        entry.write(Wasm.localSet(boxLocal));
        entry.write(Wasm.localGet(boxLocal));
        entry.write(Wasm.localGet(paramLocal.index));
        _emitElemStore(entry, type, 0);
      }
    }
  }

  @override
  BytesOutput generateASTFunctionDeclaration(
    ASTFunctionDeclaration f, {
    BytesOutput? out,
    WasmContext? context,
    WasmModuleContext? module,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    if (module != null) {
      context.module = module;
    }

    // Exception handling (`throw` / `try` / `catch`): lower to a `$pc`-dispatched
    // CFG so unwinding uses absolute jumps. Takes precedence over the synchronous
    // path; the async+exceptions combination is deferred (builder returns null).
    if (module != null && _exceptionEligible(module).contains(f.name)) {
      final cfg = _buildExceptionCfg(f, module, _exceptionEligible(module));
      if (cfg != null) {
        return _generateExceptionCfgFunction(
          f,
          cfg,
          out: out,
          context: context,
          module: module,
        );
      }
    }

    // Real `async`/`await` suspension (Asyncify): emit the unwind/rewind state
    // machine so an async function can really suspend. The linear path handles
    // top-level statement awaits; the CFG path handles awaits inside control
    // flow (`while`). Anything else falls back to synchronous-collapse below.
    if (f.modifiers.isAsync && module != null) {
      final eligible = _asyncifyEligible(module);
      if (eligible.contains(f.name)) {
        final points = _asyncifyAwaitPoints(f, module, eligible);
        if (points != null) {
          return _generateAsyncifyFunction(
            f,
            _AsyncifyMatch(points),
            out: out,
            context: context,
            module: module,
          );
        }
        final cfg = _buildAsyncifyCfg(f, module, eligible);
        if (cfg != null) {
          return _generateAsyncifyCfgFunction(
            f,
            cfg,
            out: out,
            context: context,
            module: module,
          );
        }
      }
    }

    var outBody = newOutput();

    // For an `async` function the declared `Future<T>` collapses to `T` (Wasm
    // executes synchronously); compile it as a normal function returning `T`.
    // Anonymous functions use the concrete return type inferred at registration.
    var effectiveReturnType =
        context.module?.returnTypeOverride(f) ?? f.effectiveReturnType;

    var return0 = context.returnsLength;
    context.returnsPush(
      effectiveReturnType,
      "Function `${f.name}` return: $effectiveReturnType",
    );
    context.assertReturnsLength(return0 + 1);

    // Direct-closure vars of this function (capture-free, call-only closures
    // assigned to a `var`): their declarations are elided and calls go direct.
    var mod = context.module;
    if (mod != null) {
      context.directClosureVars = mod.directClosureVars(f);
    }

    var closureInfo = context.module?.closureInfo(f);
    if (closureInfo != null) {
      // Hidden environment pointer as parameter 0.
      context.closureEnvLocalIndex = context.addLocalVariable(
        '__env',
        _astTypeInt32,
      );
      // Real parameters with their inferred (concrete) types.
      var params = f.parameters.allParameters;
      for (var i = 0; i < params.length; ++i) {
        var t = i < closureInfo.paramTypes.length
            ? closureInfo.paramTypes[i]
            : params[i].type;
        context.addLocalVariable(params[i].name, t);
      }
      // Captured variables are read from the environment struct.
      for (var c in closureInfo.captures) {
        context.capturedVariables[c.name] = (type: c.type, offset: c.offset);
      }
    } else {
      var parametersVariables = f.parameters.declaredVariables();
      for (var v in parametersVariables) {
        context.addLocalVariable(v.key, v.value);
      }
    }

    var localVariables = f.statements.declaredVariables();

    // Register declared locals before generating the body (which references
    // them, and may also allocate scratch locals).
    for (var v in localVariables) {
      context.addLocalVariable(v.key, v.value);
    }

    // Generate the body first, into its own buffer: body generation may
    // allocate scratch locals (e.g. for `%`), which must be declared in the
    // preamble below.
    var bodyCode = newOutput();

    // Box captured variables (capture-by-reference): boxed parameters are moved
    // into a heap cell at entry; boxed locals are boxed at their declaration.
    _setupBoxedVariables(f, context: context, entry: bodyCode);

    for (var stm in f.statements) {
      generateASTStatement(stm, out: bodyCode, context: context);
    }

    var returnType = effectiveReturnType;

    // A non-void function needs a trailing `unreachable` + default unless its
    // body already ends with an explicit `return` instruction. When the last
    // top-level statement is NOT a `return` (e.g. a `switch`/`if`/`while` that
    // returns on all paths), the body ends with a `block`'s `end`, which the
    // validator treats as reachable — so the terminator is required even when a
    // residual virtual-stack entry (e.g. from a preceding `var` declaration)
    // makes `context.stackLength != 0`. The `stackLength == 0` case keeps the
    // (redundant but pre-existing) terminator for plain `return`-ended bodies.
    var lastStatement = f.statements.isEmpty ? null : f.statements.last;

    if (!returnType.isVoid &&
        (context.stackLength == 0 || lastStatement is! ASTStatementReturn)) {
      // Notify that the function can't reach the end.
      bodyCode.writeByte(
        Wasm.unreachable,
        description: "[OP] Unreachable function end",
      );

      if (returnType is ASTTypeInt) {
        bodyCode.write(
          Wasm64.i64Const(0),
          description: "Unreachable default return",
        );
      } else if (returnType is ASTTypeDouble) {
        bodyCode.write(
          Wasm64.f64Const(0),
          description: "Unreachable default return",
        );
      }
    }

    // Preamble: declared locals followed by any scratch locals (in index
    // order), then the generated body.
    var scratchTypes = context.scratchLocalTypes;

    outBody.write(
      Leb128.encodeUnsigned(localVariables.length + scratchTypes.length),
      description: "Local variables count",
    );

    for (var v in localVariables) {
      // Use the context's (possibly refined) type — a `var` initialized from a
      // constructor is re-typed from `dynamic` to the class type during body gen.
      var astType = context.getLocalVariable(v.key)?.type ?? v.value;
      outBody.write(
        Leb128.encodeUnsigned(1),
        description: "Declared variable count",
      );
      outBody.writeByte(
        astType.wasmCode,
        description:
            "Declared variable `${v.key}` type(${astType.wasmType.name})",
      );
    }

    for (var astType in scratchTypes) {
      outBody.write(
        Leb128.encodeUnsigned(1),
        description: "Scratch variable count",
      );
      outBody.writeByte(
        astType.wasmCode,
        description: "Scratch variable type(${astType.wasmType.name})",
      );
    }

    outBody.writeBytes(bodyCode);

    context.assertReturnsLength(return0 + 1);
    context.returnsDrop(effectiveReturnType);
    context.assertReturnsLength(return0);

    outBody.writeByte(Wasm.end, description: "Code body end");

    out.writeBytesLeb128Block([outBody], description: "Function body");

    return out;
  }

  /// Generates a class instance method. Reuses [generateASTFunctionDeclaration]
  /// with a context that knows the class field layout and that `this` is the
  /// first parameter (local 0), so bare field accesses in the body lower to
  /// loads/stores against `this`.
  BytesOutput _generateClassMethodFunction(
    _WasmMethodFunction f, {
    required WasmModuleContext module,
  }) {
    var context = WasmContext(module: module);
    context.classLayout = module.classLayouts[f.clazz.name];
    context.thisLocalIndex = 0; // `this` is parameter 0.
    return generateASTFunctionDeclaration(f, context: context, module: module);
  }

  /// Generates a class constructor as a function returning an i32 object
  /// pointer: allocates the instance struct, applies field initializers and
  /// `this.field` parameter stores, runs the constructor body, and returns
  /// `this`.
  BytesOutput _generateClassConstructorFunction(
    _WasmConstructorFunction f, {
    required WasmModuleContext module,
  }) {
    var out = newOutput();
    var context = WasmContext(module: module);

    var clazz = f.clazz;
    var layout = module.classLayouts[clazz.name]!;
    context.classLayout = layout;

    module.requiresMemory = true;
    module.requiresHeapGlobal = true;
    module.ensureAllocFunction();

    var classType = clazz.type;
    var return0 = context.returnsLength;
    context.returnsPush(classType, "Constructor `${clazz.name}` return");

    // Value parameters become locals 0..n-1.
    var paramVars = f.parameters.declaredVariables();
    for (var v in paramVars) {
      context.addLocalVariable(v.key, v.value);
    }

    // The `this` pointer is a local just past the parameters.
    var thisIndex = context.addLocalVariable('this', classType);
    context.thisLocalIndex = thisIndex;

    // Locals declared in the constructor body.
    var bodyLocals = f.ctor.statements.declaredVariables();
    for (var v in bodyLocals) {
      context.addLocalVariable(v.key, v.value);
    }

    var bodyCode = newOutput();

    // this = __alloc(sizeof(class))
    bodyCode.write(
      Wasm32.i32Const(layout.size),
      description: "[OP] sizeof ${clazz.name} = ${layout.size}",
    );
    _emitInlineAlloc(bodyCode, context);
    bodyCode.write(
      Wasm.localSet(thisIndex),
      description: "[OP] this = alloc(${clazz.name})",
    );

    var thisParamNames = f.ctor.parameters.allParameters
        .where((p) => p.thisParameter)
        .map((p) => p.name)
        .toSet();

    // Field initializers (e.g. `int y = 5`) for fields not set by a `this.`
    // parameter — including inherited fields (superclass-first, so a superclass
    // initializer runs before the subclass's own; the seen-set keeps the first).
    var initializedFields = <String>{};
    for (var field in _allInstanceFields(clazz)) {
      if (field.modifiers.isStatic) continue;
      if (!initializedFields.add(field.name)) continue;
      if (thisParamNames.contains(field.name)) continue;
      if (field is! ASTClassFieldWithInitialValue) continue;

      var offset = layout.offsets[field.name]!;
      var fieldType = layout.types[field.name]!;
      bodyCode.write(
        Wasm.localGet(thisIndex),
        description: "[OP] this (init field `${field.name}`)",
      );
      generateASTExpression(
        field.initialValue,
        out: bodyCode,
        context: context,
      );
      context.stackDrop(); // value consumed by the field store
      _emitElemStore(bodyCode, fieldType, offset);
    }

    // `this.field` parameter stores.
    for (var p in f.ctor.parameters.allParameters) {
      if (!p.thisParameter) continue;
      var offset = layout.offsets[p.name];
      if (offset == null) continue;
      var fieldType = layout.types[p.name]!;
      var paramLocal = context.getLocalVariable(p.name)!;
      bodyCode.write(
        Wasm.localGet(thisIndex),
        description: "[OP] this (store param `${p.name}`)",
      );
      bodyCode.write(
        Wasm.localGet(paramLocal.index),
        description: "[OP] param `${p.name}`",
      );
      _emitElemStore(bodyCode, fieldType, offset);
    }

    // Explicit constructor body statements.
    for (var stm in f.ctor.statements) {
      generateASTStatement(stm, out: bodyCode, context: context);
    }

    // return this
    bodyCode.write(
      Wasm.localGet(thisIndex),
      description: "[OP] return this (${clazz.name})",
    );

    // Preamble: the `this` local, then body locals, then scratch locals.
    var outBody = newOutput();
    var scratchTypes = context.scratchLocalTypes;

    outBody.write(
      Leb128.encodeUnsigned(1 + bodyLocals.length + scratchTypes.length),
      description: "Local variables count",
    );
    outBody.write(Leb128.encodeUnsigned(1), description: "this local count");
    outBody.writeByte(classType.wasmCode, description: "this local (i32)");
    for (var v in bodyLocals) {
      var astType = context.getLocalVariable(v.key)?.type ?? v.value;
      outBody.write(
        Leb128.encodeUnsigned(1),
        description: "Declared var count",
      );
      outBody.writeByte(
        astType.wasmCode,
        description: "Local `${v.key}` (${astType.wasmType.name})",
      );
    }
    for (var astType in scratchTypes) {
      outBody.write(Leb128.encodeUnsigned(1), description: "Scratch var count");
      outBody.writeByte(
        astType.wasmCode,
        description: "Scratch (${astType.wasmType.name})",
      );
    }

    outBody.writeBytes(bodyCode);
    outBody.writeByte(Wasm.end, description: "Code body end");

    context.returnsDrop(classType);
    context.assertReturnsLength(return0);

    out.writeBytesLeb128Block([outBody], description: "Constructor body");
    return out;
  }

  /// The await points of [f] if its shape is Asyncify-able, assuming the module
  /// functions in [eligible] are themselves transformed. Each await must be a
  /// top-level statement (`T v = await call(...)` or `await call(...)`) of an
  /// external (host) call (a *leaf* suspension) or a call to a function in
  /// [eligible] (an *internal* frame). Returns `null` for anything more complex
  /// (an await nested in control flow or another expression, multiple awaits in
  /// one statement, awaiting a not-yet-eligible module function, or a `var`-
  /// typed result the Wasm backend can't infer).
  /// If [s] is a statement-level await (`T v = await call(...)` or
  /// `await call(...)`) of a supported callee, returns its await point (with
  /// `stmtIndex` unset = -1); otherwise `null`.
  /// Classifies a directly-awaited call: `await name(args)` where `name` is a
  /// host import (leaf) or an eligible module function (internal). `null` if the
  /// awaited expression isn't a supported call.
  ({String name, List<ASTExpression> args, bool isInternal})?
  _classifyAwaitCall(
    ASTExpressionAwait aw,
    WasmModuleContext module,
    Set<String> eligible,
  ) {
    final inner = aw.expression;
    if (inner is! ASTExpressionLocalFunctionInvocation) return null;
    final name = inner.name;
    final args = inner.arguments;
    if (name == 'print') return null;
    final isInternal = module.functionIndex(name, args.length) != null;
    if (isInternal && !eligible.contains(name)) return null;
    return (name: name, args: args, isInternal: isInternal);
  }

  _AwaitPoint? _statementAwaitPoint(
    ASTStatement s,
    WasmModuleContext module,
    Set<String> eligible,
  ) {
    final awaitsInS = s.descendantChildren
        .whereType<ASTExpressionAwait>()
        .toList();
    if (awaitsInS.length != 1) return null;

    final aw = awaitsInS.first;
    final call = _classifyAwaitCall(aw, module, eligible);
    if (call == null) return null;
    final name = call.name;
    final args = call.args;
    final isInternal = call.isInternal;

    if (s is ASTStatementVariableDeclaration && identical(s.value, aw)) {
      if (s.type is ASTTypeVar) return null; // explicit type required
      return _AwaitPoint(-1, name, args, s.name, s.type, isInternal);
    } else if (s is ASTStatementExpression) {
      final e = s.expression;
      if (identical(e, aw)) {
        return _AwaitPoint(-1, name, args, null, null, isInternal); // discarded
      }
      // `x = await f(...)`: assign the awaited value into an existing local.
      if (e is ASTExpressionVariableAssignment &&
          e.operator == ASTAssignmentOperator.set &&
          identical(e.expression, aw)) {
        return _AwaitPoint(-1, name, args, e.variable.name, null, isInternal);
      }
    }
    return null;
  }

  bool _hasAwait(ASTExpression n) =>
      n.descendantChildren.whereType<ASTExpressionAwait>().isNotEmpty;

  /// Functionally rewrites [e], lifting each nested `await call(...)` into a
  /// fresh temp (appended to [temps] + [hoisted] as a leaf/internal await) and
  /// replacing it with a reference to that temp. Subtrees without awaits are
  /// reused unchanged (no AST mutation). Returns `null` for an unsupported
  /// expression shape containing an await.
  ASTExpression? _hoistExpr(
    ASTExpression e,
    WasmModuleContext module,
    Set<String> eligible,
    List<_AwaitPoint> hoisted,
    List<({String name, ASTType type})> temps,
  ) {
    if (e is! ASTExpressionAwait && !_hasAwait(e)) return e; // reuse as-is

    if (e is ASTExpressionAwait) {
      final call = _classifyAwaitCall(e, module, eligible);
      if (call == null) return null;
      final type = call.isInternal
          ? module
                .functionByIndex(
                  module.functionIndex(call.name, call.args.length)!,
                )!
                .effectiveReturnType
          : _astTypeInt; // host result: assume int (i64) for now
      final tmp = '\$async_h_${temps.length}';
      temps.add((name: tmp, type: type));
      hoisted.add(
        _AwaitPoint(-1, call.name, call.args, tmp, type, call.isInternal),
      );
      return ASTExpressionVariableAccess(ASTScopeVariable(tmp));
    }
    if (e is ASTExpressionOperation) {
      final a = _hoistExpr(e.expression1, module, eligible, hoisted, temps);
      final b = _hoistExpr(e.expression2, module, eligible, hoisted, temps);
      if (a == null || b == null) return null;
      return ASTExpressionOperation(a, e.operator, b);
    }
    if (e is ASTExpressionVariableAssignment) {
      final v = _hoistExpr(e.expression, module, eligible, hoisted, temps);
      if (v == null) return null;
      return ASTExpressionVariableAssignment(e.variable, e.operator, v);
    }
    if (e is ASTExpressionLocalFunctionInvocation) {
      if (e.hasChainFunctionInvocation) return null;
      final newArgs = <ASTExpression>[];
      for (final a in e.arguments) {
        final h = _hoistExpr(a, module, eligible, hoisted, temps);
        if (h == null) return null;
        newArgs.add(h);
      }
      final rebuilt = ASTExpressionLocalFunctionInvocation(e.name, newArgs);
      // Preserve named arguments (hoisting each value the same way as the
      // positional args); dropping them would silently lose a named call's
      // bindings inside an `async` function.
      final named = e.namedArguments;
      if (named != null && named.isNotEmpty) {
        final hoistedNamed = <String, ASTExpression>{};
        for (final entry in named.entries) {
          final h = _hoistExpr(entry.value, module, eligible, hoisted, temps);
          if (h == null) return null;
          hoistedNamed[entry.key] = h;
        }
        rebuilt.namedArguments = hoistedNamed;
      }
      return rebuilt;
    }
    if (e is ASTExpressionNegation) {
      final x = _hoistExpr(e.expression, module, eligible, hoisted, temps);
      return x == null ? null : ASTExpressionNegation(x);
    }
    if (e is ASTExpressionNegative) {
      final x = _hoistExpr(e.expression, module, eligible, hoisted, temps);
      return x == null ? null : ASTExpressionNegative(x);
    }
    return null; // unsupported expression type containing an await
  }

  /// Rewrites a statement so its awaits are lifted to statement level (see
  /// [_hoistExpr]). Returns the rewritten statement or `null` if unsupported.
  ASTStatement? _hoistStatement(
    ASTStatement s,
    WasmModuleContext module,
    Set<String> eligible,
    List<_AwaitPoint> hoisted,
    List<({String name, ASTType type})> temps,
  ) {
    if (s is ASTStatementVariableDeclaration && s.value != null) {
      if (s.type is ASTTypeVar) return null;
      final v = _hoistExpr(s.value!, module, eligible, hoisted, temps);
      if (v == null) return null;
      return ASTStatementVariableDeclaration(s.type, s.name, v);
    }
    if (s is ASTStatementReturnWithExpression) {
      final v = _hoistExpr(s.expression, module, eligible, hoisted, temps);
      if (v == null) return null;
      return ASTStatementReturnWithExpression(v);
    }
    if (s is ASTStatementExpression) {
      final v = _hoistExpr(s.expression, module, eligible, hoisted, temps);
      if (v == null) return null;
      return ASTStatementExpression(v);
    }
    return null;
  }

  /// The await points of [f] if *all* its awaits are top-level statement awaits
  /// (the linear Asyncify shape); `null` otherwise (=> CFG path or collapse).
  List<_AwaitPoint>? _asyncifyAwaitPoints(
    ASTFunctionDeclaration f,
    WasmModuleContext module,
    Set<String> eligible,
  ) {
    if (!f.modifiers.isAsync) return null;
    final stmts = f.statements;
    final points = <_AwaitPoint>[];

    for (var i = 0; i < stmts.length; i++) {
      final s = stmts[i];
      if (s.descendantChildren.whereType<ASTExpressionAwait>().isEmpty) {
        continue;
      }
      final ap = _statementAwaitPoint(s, module, eligible);
      if (ap == null) return null; // await not a clean top-level statement
      points.add(
        _AwaitPoint(
          i,
          ap.calleeName,
          ap.args,
          ap.resultVarName,
          ap.resultType,
          ap.isInternal,
        ),
      );
    }

    if (points.isEmpty) return null;
    return points;
  }

  /// Lowers [f] into a CFG of basic blocks for the Asyncify PC state machine,
  /// covering awaits inside control flow (`if`/`if-else`/`else if`, `while`,
  /// `for`) and `return await ...`. Returns `null` for shapes that don't
  /// require the CFG (no awaits) or that it doesn't support (`for-each`,
  /// `break`/`continue`, awaits nested deeper in expressions).
  _Cfg? _buildAsyncifyCfg(
    ASTFunctionDeclaration f,
    WasmModuleContext module,
    Set<String> eligible,
  ) {
    if (!f.modifiers.isAsync) return null;

    final blocks = <_Bb>[];
    final temps = <({String name, ASTType type})>[];
    int newBb() {
      final b = _Bb(blocks.length);
      blocks.add(b);
      return b.pc;
    }

    var ok = true;
    var sawAwait = false;

    // Lowers [stmts] starting at block [cur]; returns the block where control
    // continues, or -1 if it returned (no fall-through).
    int lower(List<ASTStatement> stmts, int cur, bool inControl) {
      for (final s in stmts) {
        if (!ok) return cur;

        final hasAwait = s.descendantChildren
            .whereType<ASTExpressionAwait>()
            .isNotEmpty;

        if (hasAwait) {
          final ap = _statementAwaitPoint(s, module, eligible);
          if (ap != null) {
            sawAwait = true;
            if (ap.isInternal) {
              final cont = newBb();
              blocks[cur].term = _TInternal(ap, cont);
              cur = cont;
            } else {
              final resume = newBb();
              blocks[cur].term = _TLeaf(ap, resume);
              blocks[resume].leafResume = ap;
              cur = resume;
            }
            continue;
          }
          // `return await f(...)`: await into a synthetic temp, then return it.
          if (s is ASTStatementReturnWithExpression &&
              s.expression is ASTExpressionAwait) {
            final call = _classifyAwaitCall(
              s.expression as ASTExpressionAwait,
              module,
              eligible,
            );
            if (call == null) {
              ok = false;
              return cur;
            }
            sawAwait = true;
            final tmp = '\$async_ret_${temps.length}';
            temps.add((name: tmp, type: f.effectiveReturnType));
            final rap = _AwaitPoint(
              -1,
              call.name,
              call.args,
              tmp,
              f.effectiveReturnType,
              call.isInternal,
            );
            if (rap.isInternal) {
              final ret = newBb();
              blocks[cur].term = _TInternal(rap, ret);
              blocks[ret].term = _TReturnLocal(tmp);
            } else {
              final resume = newBb();
              blocks[cur].term = _TLeaf(rap, resume);
              blocks[resume].leafResume = rap;
              blocks[resume].term = _TReturnLocal(tmp);
            }
            return -1;
          }
          // Control flow whose *condition* awaits is not supported (only the
          // body may contain awaits).
          if ((s is ASTStatementWhileLoop &&
                  _hasAwait(s.conditionExpression)) ||
              (s is ASTStatementForLoop && _hasAwait(s.conditionExpression)) ||
              (s is ASTBranchIfBlock && _hasAwait(s.condition)) ||
              (s is ASTBranchIfElseBlock && _hasAwait(s.condition)) ||
              (s is ASTBranchIfElseIfsElseBlock && _hasAwait(s.condition))) {
            ok = false;
            return cur;
          }
          // Control flow containing awaits.
          if (s is ASTStatementWhileLoop) {
            final condPc = newBb();
            blocks[cur].term = _TGoto(condPc);
            final bodyPc = newBb();
            final exitPc = newBb();
            blocks[condPc].term = _TBranch(
              s.conditionExpression,
              bodyPc,
              exitPc,
            );
            final bodyExit = lower(s.loopBlock.statements, bodyPc, true);
            if (bodyExit >= 0) blocks[bodyExit].term = _TGoto(condPc);
            cur = exitPc;
            continue;
          }
          if (s is ASTStatementForLoop) {
            blocks[cur].stmts.add(s.initStatement);
            final condPc = newBb();
            blocks[cur].term = _TGoto(condPc);
            final bodyPc = newBb();
            final exitPc = newBb();
            blocks[condPc].term = _TBranch(
              s.conditionExpression,
              bodyPc,
              exitPc,
            );
            final bodyExit = lower(s.loopBlock.statements, bodyPc, true);
            if (bodyExit >= 0) {
              blocks[bodyExit].stmts.add(
                ASTStatementExpression(s.continueExpression),
              );
              blocks[bodyExit].term = _TGoto(condPc);
            }
            cur = exitPc;
            continue;
          }
          // `for (T e in it)` over a list variable, desugared to an index loop:
          //   __i = 0; while (__i < it.length) { T e = it[__i]; body; __i++ }
          // Only `it.length` is raw (no AST getter); the rest is synthetic AST.
          if (s is ASTStatementForEach) {
            final iter = s.iterableExpression;
            if (iter is! ASTExpressionVariableAccess) {
              ok = false;
              return cur;
            }
            final itVar = iter.variable;
            final iName = '\$async_fe_i${temps.length}';
            final lenName = '\$async_fe_n${temps.length}';
            temps.add((name: iName, type: _astTypeInt));
            temps.add((name: lenName, type: _astTypeInt));

            ASTExpression iAccess() =>
                ASTExpressionVariableAccess(ASTScopeVariable(iName));

            final condPc = newBb();
            blocks[cur].rawInit = (body, ctx) {
              final i = ctx.getLocalVariable(iName)!;
              final n = ctx.getLocalVariable(lenName)!;
              final it = ctx.getLocalVariable(itVar.name)!;
              body.write([
                ...Wasm64.i64Const(0),
                ...Wasm.localSet(i.index), // __i = 0
                ...Wasm.localGet(it.index), // list header ptr
                ...Wasm32.i32Load(2, 0), // length (i32)
                Wasm32.i32ExtendToI64Unsigned,
                ...Wasm.localSet(n.index), // __len
              ]);
            };
            blocks[cur].term = _TGoto(condPc);

            final bodyPc = newBb();
            final exitPc = newBb();
            blocks[condPc].term = _TBranch(
              ASTExpressionOperation(
                iAccess(),
                ASTExpressionOperator.lower,
                ASTExpressionVariableAccess(ASTScopeVariable(lenName)),
              ),
              bodyPc,
              exitPc,
            );

            // Body entry: bind `T e = it[__i]`, then the original body.
            blocks[bodyPc].stmts.add(
              ASTStatementVariableDeclaration(
                s.variableType,
                s.variableName,
                ASTExpressionVariableEntryAccess(itVar, iAccess()),
              ),
            );
            final bodyExit = lower(s.loopBlock.statements, bodyPc, true);
            if (bodyExit >= 0) {
              // __i = __i + 1
              blocks[bodyExit].stmts.add(
                ASTStatementExpression(
                  ASTExpressionVariableAssignment(
                    ASTScopeVariable(iName),
                    ASTAssignmentOperator.set,
                    ASTExpressionOperation(
                      iAccess(),
                      ASTExpressionOperator.add,
                      ASTExpressionLiteral(ASTValueInt(1)),
                    ),
                  ),
                ),
              );
              blocks[bodyExit].term = _TGoto(condPc);
            }
            cur = exitPc;
            continue;
          }
          if (s is ASTBranchIfBlock) {
            final thenPc = newBb();
            final joinPc = newBb();
            blocks[cur].term = _TBranch(s.condition, thenPc, joinPc);
            final thenExit = lower(s.block.statements, thenPc, true);
            if (thenExit >= 0) blocks[thenExit].term = _TGoto(joinPc);
            cur = joinPc;
            continue;
          }
          if (s is ASTBranchIfElseBlock) {
            final thenPc = newBb();
            final elsePc = s.blockElse != null ? newBb() : -1;
            final joinPc = newBb();
            blocks[cur].term = _TBranch(
              s.condition,
              thenPc,
              elsePc >= 0 ? elsePc : joinPc,
            );
            final thenExit = lower(s.blockIf.statements, thenPc, true);
            if (thenExit >= 0) blocks[thenExit].term = _TGoto(joinPc);
            if (elsePc >= 0) {
              final elseExit = lower(s.blockElse!.statements, elsePc, true);
              if (elseExit >= 0) blocks[elseExit].term = _TGoto(joinPc);
            }
            cur = joinPc;
            continue;
          }
          if (s is ASTBranchIfElseIfsElseBlock) {
            final joinPc = newBb();
            final arms = <({ASTExpression cond, ASTBlock block})>[
              (cond: s.condition, block: s.blockIf),
              for (final e in s.blocksElseIf)
                (cond: e.condition, block: e.block),
            ];
            var condCur = cur;
            for (var ai = 0; ai < arms.length; ai++) {
              final isLast = ai == arms.length - 1;
              final thenPc = newBb();
              final elsePc = isLast
                  ? (s.blockElse != null ? newBb() : joinPc)
                  : newBb();
              blocks[condCur].term = _TBranch(arms[ai].cond, thenPc, elsePc);
              final thenExit = lower(arms[ai].block.statements, thenPc, true);
              if (thenExit >= 0) blocks[thenExit].term = _TGoto(joinPc);
              if (isLast && s.blockElse != null) {
                final elseExit = lower(s.blockElse!.statements, elsePc, true);
                if (elseExit >= 0) blocks[elseExit].term = _TGoto(joinPc);
              } else if (!isLast) {
                condCur = elsePc; // next arm's condition evaluates here
              }
            }
            cur = joinPc;
            continue;
          }
          // Hoist awaits nested in an expression, e.g. `t = t + await f()` or
          // `return await f() + 1`: lift each into a temp await, then emit the
          // rewritten statement.
          final hoisted = <_AwaitPoint>[];
          final rewritten = _hoistStatement(
            s,
            module,
            eligible,
            hoisted,
            temps,
          );
          if (rewritten != null) {
            sawAwait = true;
            for (final ap in hoisted) {
              if (ap.isInternal) {
                final cont = newBb();
                blocks[cur].term = _TInternal(ap, cont);
                cur = cont;
              } else {
                final resume = newBb();
                blocks[cur].term = _TLeaf(ap, resume);
                blocks[resume].leafResume = ap;
                cur = resume;
              }
            }
            if (rewritten is ASTStatementReturn) {
              blocks[cur].term = _TReturn(rewritten);
              return -1;
            }
            blocks[cur].stmts.add(rewritten);
            continue;
          }
          // for-each, awaits in conditions, etc.: unsupported.
          ok = false;
          return cur;
        }

        // Straight-line (incl. await-free control flow); a `return` ends control.
        if (s is ASTStatementReturn) {
          blocks[cur].term = _TReturn(s);
          return -1;
        }
        blocks[cur].stmts.add(s);
      }
      return cur;
    }

    final exit = lower(f.statements, newBb(), false);
    if (!ok || !sawAwait) return null;

    if (exit >= 0 && blocks[exit].term == null) {
      blocks[exit].term = _TReturnEnd();
    }
    for (final b in blocks) {
      b.term ??= _TReturnEnd();
    }
    return _Cfg(blocks, temps);
  }

  /// Runtime type tag stored in `EXC_TAG` for a thrown value of [type]. Used by
  /// catch dispatch to match typed clauses (and to choose the load width when
  /// binding the catch variable).
  static int _excTypeTag(ASTType type) {
    if (type is ASTTypeInt) return 1;
    if (type is ASTTypeDouble) return 2;
    if (type is ASTTypeBool) return 3;
    if (type is ASTTypeString) return 4;
    return 5; // list / map / object / other (i32 pointer)
  }

  /// The universal catch-all supertypes (mirrors the AST interpreter): a clause
  /// typed with one of these — or untyped — matches any thrown value.
  static const _excCatchAllTypeNames = {
    'Object',
    'dynamic',
    'Exception',
    'Throwable',
    'Error',
  };

  /// Representative AST types for each primitive tag, used to compute which tags
  /// a typed catch clause accepts (via [ASTType.acceptsType]).
  static final Map<int, ASTType> _tagRepresentativeTypes = {
    1: ASTTypeInt.instance,
    2: ASTTypeDouble.instance,
    3: ASTTypeBool.instance,
    4: ASTTypeString.instance,
  };

  /// The set of `EXC_TAG` values a catch clause accepts, or `null` if it is a
  /// catch-all. Mirrors the AST interpreter: a clause matches a thrown value
  /// whose type the clause type `acceptsType` (so `on double` also accepts an
  /// `int`).
  static Set<int>? _catchClauseAcceptedTags(ASTCatchClause c) {
    final t = c.exceptionType;
    if (t == null || _excCatchAllTypeNames.contains(t.name)) return null;
    final tags = <int>{};
    _tagRepresentativeTypes.forEach((tag, repr) {
      if (t.acceptsType(repr)) tags.add(tag);
    });
    // A non-primitive (object/list/map) clause matches the pointer tag.
    if (_excTypeTag(t) == 5) tags.add(5);
    return tags;
  }

  /// Emits a non-trapping `f64 -> i64` truncation: if the f64 on the stack is
  /// finite, truncate; otherwise raise a catchable exception (a `String` whose
  /// message matches the AST interpreter) and yield `0`. Net stack effect:
  /// pops one `f64`, pushes one `i64`.
  void _emitGuardedF64ToI64(
    BytesOutput out,
    WasmContext context, {
    String msg = 'Unsupported operation: Infinity or NaN toInt',
  }) {
    final module = context.module!;
    module.requiresException = true;
    final fdiv = context.scratchLocal(_astTypeDouble64, 950);
    final msgPtr = module.internStringLiteral(msg);

    out.write(Wasm.localSet(fdiv)); // $fdiv = result
    // finite? (result - result == 0; Infinity/NaN make the difference NaN != 0)
    out.write(Wasm.localGet(fdiv));
    out.write(Wasm.localGet(fdiv));
    out.writeByte(Wasm64.f64Subtract);
    out.write(Wasm64.f64Const(0));
    out.writeByte(Wasm64.f64Equals);
    out.write(Wasm.ifInstruction(WasmType.i64Type));
    // finite: truncate normally.
    out.write(Wasm.localGet(fdiv));
    out.writeByte(Wasm64.f64TruncateToI64Signed);
    out.writeByte(Wasm.elseInstruction);
    // non-finite: raise a catchable String exception, yield 0.
    out.write([
      ...Wasm32.i32Const(0),
      ...Wasm32.i32Const(4), // EXC_TAG = String
      ...Wasm32.i32Store(2, module.excTagOffset),
    ]);
    out.write([
      ...Wasm32.i32Const(0),
      ...Wasm32.i32Const(msgPtr), // EXC_VALUE = interned message pointer
      ...Wasm32.i32Store(2, module.excValueOffset),
    ]);
    out.write([
      ...Wasm32.i32Const(0),
      ...Wasm32.i32Const(1), // EXC_PENDING = 1
      ...Wasm32.i32Store(2, module.excPendingOffset),
    ]);
    out.write(Wasm64.i64Const(0));
    out.writeByte(Wasm.end);
  }

  /// The returned expression of a `return` statement (for capturing the value
  /// before a `finally` runs), or `null` for a bare/`null` return.
  ASTExpression? _returnExpression(ASTStatementReturn s) {
    if (s is ASTStatementReturnWithExpression) return s.expression;
    if (s is ASTStatementReturnValue) return ASTExpressionLiteral(s.value);
    if (s is ASTStatementReturnVariable) {
      return ASTExpressionVariableAccess(s.variable);
    }
    return null;
  }

  /// Whether [o] is an integer division that can raise a catchable "division by
  /// zero" exception: Dart's `~/` (`divideAsInt`), or `/` whose operands are
  /// integers so the expression resolves to `int` (Java/Kotlin/C# `/`).
  bool _isIntegerDivision(ASTExpressionOperation o) =>
      o.operator == ASTExpressionOperator.divideAsInt ||
      (o.operator == ASTExpressionOperator.divide &&
          o.resolveType(null) is ASTTypeInt);

  /// Whether [tryBlock] can raise (a `throw` statement or an integer division).
  bool _tryHasThrow(ASTBlock tryBlock) =>
      tryBlock.statements.any((s) => s is ASTStatementThrow) ||
      tryBlock.descendantChildren.any(
        (n) =>
            n is ASTStatementThrow ||
            (n is ASTExpressionOperation && _isIntegerDivision(n)),
      );

  /// The common static type of the values thrown directly within [tryBlock]
  /// (used to type an untyped catch variable). Returns `null` if no `throw` is
  /// found or the thrown types differ.
  ASTType? _inferTryThrownType(ASTBlock tryBlock) {
    ASTType? result;
    void consider(ASTType? rt) {
      if (rt == null) return;
      result ??= rt;
    }

    final throws = <ASTStatementThrow>[
      ...tryBlock.statements.whereType<ASTStatementThrow>(),
      ...tryBlock.descendantChildren.whereType<ASTStatementThrow>(),
    ];
    final types = <String, ASTType>{};
    for (final t in throws) {
      final rt = t.expression.resolveType(null);
      if (rt is! ASTType) return null;
      types[rt.name] = rt;
    }
    // An integer division can raise a `String` (the division-by-zero message).
    if (tryBlock.descendantChildren.whereType<ASTExpressionOperation>().any(
      _isIntegerDivision,
    )) {
      types['String'] = ASTTypeString.instance;
    }
    if (types.length > 1) return null; // mixed thrown types
    for (final t in types.values) {
      consider(t);
    }
    return result;
  }

  /// Whether [f] contains a `throw` or `try` and so must be compiled through the
  /// exception CFG (rather than the straight-line path).
  bool _functionUsesExceptions(ASTFunctionDeclaration f) {
    for (var s in f.statements) {
      if (s is ASTStatementThrow || s is ASTStatementTryCatch) return true;
      if (s.descendantChildren.any(
        (n) => n is ASTStatementThrow || n is ASTStatementTryCatch,
      )) {
        return true;
      }
    }
    return false;
  }

  /// All local-function invocations within [f].
  Iterable<ASTExpressionLocalFunctionInvocation> _functionCalls(
    ASTFunctionDeclaration f,
  ) => f.statements
      .expand((s) => [s, ...s.descendantChildren])
      .whereType<ASTExpressionLocalFunctionInvocation>();

  /// Fixed-point set of exception-eligible function names: functions that use
  /// `throw`/`try` directly, plus any function that (transitively) calls one —
  /// callers need post-call checks so a thrown exception propagates out. Cached
  /// per module.
  Set<String> _exceptionEligible(WasmModuleContext module) {
    final cached = module.exceptionEligible;
    if (cached != null) return cached;

    final eligible = <String>{};
    for (final f in module.functions) {
      if (_functionUsesExceptions(f)) eligible.add(f.name);
    }
    var changed = true;
    while (changed) {
      changed = false;
      for (final f in module.functions) {
        if (eligible.contains(f.name)) continue;
        if (_functionCalls(f).any((c) => eligible.contains(c.name))) {
          eligible.add(f.name);
          changed = true;
        }
      }
    }
    return module.exceptionEligible = eligible;
  }

  /// Number of calls within [s] (including nested) to a function in [eligible].
  int _countEligibleCalls(ASTStatement s, Set<String> eligible) =>
      [s, ...s.descendantChildren]
          .whereType<ASTExpressionLocalFunctionInvocation>()
          .where((c) => eligible.contains(c.name))
          .length;

  /// Number of integer divisions (`~/`) within [s] — each can raise a catchable
  /// "Infinity or NaN" exception under the exception CFG, so the enclosing
  /// statement needs a post-evaluation pending check.
  int _countIntDivisions(ASTStatement s) => [
    s,
    ...s.descendantChildren,
  ].whereType<ASTExpressionOperation>().where(_isIntegerDivision).length;

  /// Builds the exception-handling CFG for [f]: lowers `throw` / `try` / `catch`
  /// (and the statements around them) into `$pc`-dispatched basic blocks with
  /// exception terminators. Returns `null` (caller falls back / fails loudly)
  /// for shapes not yet supported by this slice.
  _Cfg? _buildExceptionCfg(
    ASTFunctionDeclaration f,
    WasmModuleContext module,
    Set<String> excEligible,
  ) {
    // The combination of real `await` suspension and exceptions in the same
    // function is a separate, advanced axis — defer it (handled elsewhere).
    if (f.statements.any(
      (s) => s.descendantChildren.whereType<ASTExpressionAwait>().isNotEmpty,
    )) {
      return null;
    }

    final blocks = <_Bb>[];
    final temps = <({String name, ASTType type})>[];
    int newBb() {
      final b = _Bb(blocks.length);
      blocks.add(b);
      return b.pc;
    }

    var ok = true;

    // Entry is pc 0; the function-level propagate block re-raises out of `f`.
    final entryPc = newBb();
    final propagatePc = newBb();
    blocks[propagatePc].term = _TPropagate();

    // Where a `return` inside the current `try`/`catch` region must jump after
    // capturing its value into `$exc_ret`, so any enclosing `finally` runs first.
    // -1 = no enclosing finally (emit a direct `return`). Saved/restored around
    // each `try`-with-`finally`.
    var returnTargetPc = -1;

    // The synthetic local holding a return value while enclosing `finally`s run.
    String? excRetName;
    String ensureExcRet() {
      var name = excRetName;
      if (name == null) {
        name = '\$exc_ret';
        excRetName = name;
        temps.add((name: name, type: f.effectiveReturnType));
      }
      return name;
    }

    // Statements that stash a `return`'s value into `$exc_ret` (empty for void /
    // bare return).
    List<ASTStatement> captureReturn(ASTStatementReturn s) {
      final expr = _returnExpression(s);
      if (expr == null || f.effectiveReturnType.isVoid) return const [];
      final name = ensureExcRet();
      return [
        ASTStatementExpression(
          ASTExpressionVariableAssignment(
            ASTScopeVariable(name),
            ASTAssignmentOperator.set,
            expr,
          ),
        ),
      ];
    }

    // Mutually-recursive lowering helpers (declared `late` so each can call the
    // other).
    late final int Function(List<ASTStatement>, int, int) lower;

    // Lowers a `try`/`catch`/`finally` region; returns the join pc (where
    // control continues), or -1 if every path left (returned/threw).
    int lowerTry(ASTStatementTryCatch s, int cur, int handlerPc) {
      final finallyBlock = s.finallyBlock;
      final joinPc = newBb();

      // Resolve each catch clause's bound-variable type (typed clause type, or
      // inferred from the thrown values for an untyped `catch (e)`).
      final clauseVarTypes = <ASTType?>[];
      for (final c in s.catches) {
        // A bound stack-trace variable (`catch (e, s)`) has no Wasm
        // representation: refuse rather than silently dropping the binding and
        // leaving the body referencing an undeclared name.
        if (c.stackTraceName != null) {
          ok = false;
          return cur;
        }

        var varType = c.exceptionType;
        // A declared catch-all type (`Exception`/`Throwable`/`Error`/`Object`/
        // `dynamic`, from Java/Kotlin/C# `catch (Exception e)` or Dart
        // `on Exception catch (e)`) is not a representable Wasm value type and
        // binds whatever was thrown. Resolve its bound variable like an untyped
        // `catch (e)` (infer from the thrown value); the clause still matches
        // every tag via [_catchClauseAcceptedTags].
        if (varType != null && _excCatchAllTypeNames.contains(varType.name)) {
          varType = null;
        }
        if (varType == null && c.variableName != null) {
          final inferred = _inferTryThrownType(s.tryBlock);
          if (inferred != null) {
            varType = inferred;
          } else if (_tryHasThrow(s.tryBlock)) {
            ok = false;
            return cur;
          } else {
            varType = _astTypeInt;
          }
        }
        clauseVarTypes.add(varType);
      }

      final savedReturnTarget = returnTargetPc;

      // --- No `finally`: throws/returns route straight to the enclosing region.
      if (finallyBlock == null) {
        final catchPc = newBb();
        final tryEntry = newBb();
        blocks[cur].term = _TGoto(tryEntry);
        final tryExit = lower(s.tryBlock.statements, tryEntry, catchPc);
        if (tryExit >= 0) blocks[tryExit].term = _TGoto(joinPc);

        final clauses = <_CatchInfo>[];
        for (var ci = 0; ci < s.catches.length; ci++) {
          final c = s.catches[ci];
          final bodyPc = newBb();
          clauses.add(
            _CatchInfo(
              _catchClauseAcceptedTags(c),
              c.variableName,
              clauseVarTypes[ci],
              bodyPc,
            ),
          );
          final clauseExit = lower(c.block.statements, bodyPc, handlerPc);
          if (clauseExit >= 0) blocks[clauseExit].term = _TGoto(joinPc);
        }
        blocks[catchPc].term = _TCatchDispatch(clauses, handlerPc);
        return joinPc;
      }

      // --- With `finally`: lower a fresh copy of the finally block for each exit
      // path (normal completion, caught completion, propagation, and `return`).
      // The final return continuation runs any *enclosing* finally first.
      final returnEndPc = newBb();
      blocks[returnEndPc].term = f.effectiveReturnType.isVoid
          ? _TReturnEnd()
          : _TReturnLocal(ensureExcRet());
      final returnCont = savedReturnTarget >= 0
          ? savedReturnTarget
          : returnEndPc;

      // Lowers `finally` into a fresh block chain that continues at [contPc].
      // A throw or return inside the finally itself re-raises / returns through
      // the *enclosing* region.
      int finallyInstance(int contPc) {
        final fEntry = newBb();
        returnTargetPc = returnCont;
        final fExit = lower(finallyBlock.statements, fEntry, handlerPc);
        if (fExit >= 0) blocks[fExit].term = _TGoto(contPc);
        return fEntry;
      }

      final finallyJoin = finallyInstance(joinPc);
      final finallyPropagate = finallyInstance(handlerPc);
      final finallyReturn = finallyInstance(returnCont);

      final catchPc = newBb();
      final tryEntry = newBb();
      blocks[cur].term = _TGoto(tryEntry);

      // Inside the try/catch bodies, returns route through this try's finally.
      returnTargetPc = finallyReturn;
      final tryExit = lower(s.tryBlock.statements, tryEntry, catchPc);
      if (tryExit >= 0) blocks[tryExit].term = _TGoto(finallyJoin);

      final clauses = <_CatchInfo>[];
      for (var ci = 0; ci < s.catches.length; ci++) {
        final c = s.catches[ci];
        final bodyPc = newBb();
        clauses.add(
          _CatchInfo(
            _catchClauseAcceptedTags(c),
            c.variableName,
            clauseVarTypes[ci],
            bodyPc,
          ),
        );
        // A throw inside a catch body runs `finally`, then propagates.
        final clauseExit = lower(c.block.statements, bodyPc, finallyPropagate);
        if (clauseExit >= 0) blocks[clauseExit].term = _TGoto(finallyJoin);
      }
      returnTargetPc = savedReturnTarget;

      // No clause matched: run `finally`, then re-raise to the enclosing handler.
      blocks[catchPc].term = _TCatchDispatch(clauses, finallyPropagate);
      return joinPc;
    }

    // Lowers [stmts] from block [cur]; throws/pending jump to [handlerPc].
    // Returns the continue pc or -1 if control left.
    lower = (List<ASTStatement> stmts, int cur, int handlerPc) {
      for (final s in stmts) {
        if (!ok) return cur;

        if (s is ASTStatementThrow) {
          blocks[cur].term = _TThrow(s.expression, handlerPc);
          return -1;
        }

        if (s is ASTStatementTryCatch) {
          cur = lowerTry(s, cur, handlerPc);
          if (cur < 0) return -1;
          continue;
        }

        if (s is ASTStatementReturn) {
          // `return <throwing call>` inside a `try` would exit before this
          // function's own handler runs — defer rather than miscompile. (Outside
          // a try it is fine: the callee's pending flag propagates to our caller.)
          if (_countEligibleCalls(s, excEligible) + _countIntDivisions(s) > 0 &&
              (handlerPc != propagatePc || returnTargetPc >= 0)) {
            ok = false;
            return cur;
          }
          // With an enclosing finally, capture the value and route through it;
          // otherwise return directly.
          if (returnTargetPc >= 0) {
            blocks[cur].stmts.addAll(captureReturn(s));
            blocks[cur].term = _TGoto(returnTargetPc);
          } else {
            blocks[cur].term = _TReturn(s);
          }
          return -1;
        }

        // A statement stays straight-line unless it contains a `throw`/`try`
        // (which must reach [handlerPc]), a call to a function that may throw
        // (which needs a post-call check to propagate), or — inside a `finally`
        // region — a `return` (which must route through the enclosing finally).
        final hasExc = s.descendantChildren.any(
          (n) => n is ASTStatementThrow || n is ASTStatementTryCatch,
        );
        // Operations that can raise: a call to a throwing function, or an
        // integer division (which may raise "Infinity or NaN").
        final throwingOps =
            _countEligibleCalls(s, excEligible) + _countIntDivisions(s);
        final hasRoutedReturn =
            returnTargetPc >= 0 &&
            s.descendantChildren.any((n) => n is ASTStatementReturn);
        if (!hasExc && !hasRoutedReturn && throwingOps == 0) {
          blocks[cur].stmts.add(s);
          continue;
        }

        // A simple (non-control-flow) statement with a single raising operation:
        // run it, then check the pending flag and jump to the handler if it
        // raised.
        if (throwingOps >= 1 &&
            s is! ASTStatementTryCatch &&
            s is! ASTBranch &&
            s is! ASTStatementWhileLoop &&
            s is! ASTStatementForLoop &&
            s is! ASTStatementForEach) {
          if (throwingOps > 1) {
            // Multiple raising operations in one statement would need per-op
            // hoisting — defer rather than miscompile.
            ok = false;
            return cur;
          }
          final cont = newBb();
          blocks[cur].term = _TCallCheck(s, cont, handlerPc);
          cur = cont;
          continue;
        }

        // Control flow that *contains* a `throw`/`try`: lower into the CFG so
        // exceptions raised inside the branch/loop reach [handlerPc]. The
        // condition itself is assumed exception-free.
        if (s is ASTBranchIfBlock) {
          final thenPc = newBb();
          final joinPc = newBb();
          blocks[cur].term = _TBranch(s.condition, thenPc, joinPc);
          final thenExit = lower(s.block.statements, thenPc, handlerPc);
          if (thenExit >= 0) blocks[thenExit].term = _TGoto(joinPc);
          cur = joinPc;
          continue;
        }
        if (s is ASTBranchIfElseBlock) {
          final thenPc = newBb();
          final joinPc = newBb();
          final elseBlock = s.blockElse;
          final elsePc = elseBlock != null ? newBb() : joinPc;
          blocks[cur].term = _TBranch(s.condition, thenPc, elsePc);
          final thenExit = lower(s.blockIf.statements, thenPc, handlerPc);
          if (thenExit >= 0) blocks[thenExit].term = _TGoto(joinPc);
          if (elseBlock != null) {
            final elseExit = lower(elseBlock.statements, elsePc, handlerPc);
            if (elseExit >= 0) blocks[elseExit].term = _TGoto(joinPc);
          }
          cur = joinPc;
          continue;
        }
        if (s is ASTBranchIfElseIfsElseBlock) {
          final joinPc = newBb();
          final arms = <({ASTExpression cond, ASTBlock block})>[
            (cond: s.condition, block: s.blockIf),
            for (final e in s.blocksElseIf) (cond: e.condition, block: e.block),
          ];
          var condCur = cur;
          for (var ai = 0; ai < arms.length; ai++) {
            final isLast = ai == arms.length - 1;
            final thenPc = newBb();
            final elsePc = isLast
                ? (s.blockElse != null ? newBb() : joinPc)
                : newBb();
            blocks[condCur].term = _TBranch(arms[ai].cond, thenPc, elsePc);
            final thenExit = lower(
              arms[ai].block.statements,
              thenPc,
              handlerPc,
            );
            if (thenExit >= 0) blocks[thenExit].term = _TGoto(joinPc);
            if (isLast && s.blockElse != null) {
              final elseExit = lower(
                s.blockElse!.statements,
                elsePc,
                handlerPc,
              );
              if (elseExit >= 0) blocks[elseExit].term = _TGoto(joinPc);
            } else if (!isLast) {
              condCur = elsePc;
            }
          }
          cur = joinPc;
          continue;
        }
        if (s is ASTStatementWhileLoop) {
          final condPc = newBb();
          blocks[cur].term = _TGoto(condPc);
          final bodyPc = newBb();
          final exitPc = newBb();
          blocks[condPc].term = _TBranch(s.conditionExpression, bodyPc, exitPc);
          final bodyExit = lower(s.loopBlock.statements, bodyPc, handlerPc);
          if (bodyExit >= 0) blocks[bodyExit].term = _TGoto(condPc);
          cur = exitPc;
          continue;
        }
        if (s is ASTStatementForLoop) {
          blocks[cur].stmts.add(s.initStatement);
          final condPc = newBb();
          blocks[cur].term = _TGoto(condPc);
          final bodyPc = newBb();
          final exitPc = newBb();
          blocks[condPc].term = _TBranch(s.conditionExpression, bodyPc, exitPc);
          final bodyExit = lower(s.loopBlock.statements, bodyPc, handlerPc);
          if (bodyExit >= 0) {
            blocks[bodyExit].stmts.add(
              ASTStatementExpression(s.continueExpression),
            );
            blocks[bodyExit].term = _TGoto(condPc);
          }
          cur = exitPc;
          continue;
        }

        // Other shapes containing exceptions (e.g. `for-each`, or a throw nested
        // deep inside an expression) are deferred — fail loudly, don't
        // miscompile.
        ok = false;
        return cur;
      }
      return cur;
    };

    final exit = lower(f.statements, entryPc, propagatePc);
    if (!ok) return null;

    if (exit >= 0 && blocks[exit].term == null) {
      blocks[exit].term = _TReturnEnd();
    }
    for (final b in blocks) {
      b.term ??= _TReturnEnd();
    }
    return _Cfg(blocks, temps);
  }

  /// Emits [f] as a `$pc`-dispatched CFG that implements `throw` / `try` /
  /// `catch`. Unlike the Asyncify CFG there is no suspend/rewind: control simply
  /// loops over basic blocks, and exception terminators marshal the thrown value
  /// through the fixed exception slots in linear memory.
  BytesOutput _generateExceptionCfgFunction(
    ASTFunctionDeclaration f,
    _Cfg cfg, {
    required BytesOutput out,
    required WasmContext context,
    required WasmModuleContext module,
  }) {
    module.requiresException = true;
    module.requiresMemory = true;
    context.exceptionMode = true;

    final pendOff = module.excPendingOffset;
    final tagOff = module.excTagOffset;
    final valOff = module.excValueOffset;

    final returnType = f.effectiveReturnType;
    final return0 = context.returnsLength;
    context.returnsPush(returnType, "exc-cfg `${f.name}` -> $returnType");

    for (var v in f.parameters.declaredVariables()) {
      context.addLocalVariable(v.key, v.value);
    }

    // Collect locals from the *flattened* CFG: variables declared inside `try`/
    // `catch` bodies (and any other lowered blocks) plus the catch-clause
    // variables — `f.statements.declaredVariables()` does not see into these.
    final declaredLocals = <({String name, ASTType type})>[];
    final seenLocal = <String>{};
    void addDeclaredLocal(String name, ASTType type) {
      if (seenLocal.add(name)) {
        declaredLocals.add((name: name, type: type));
        context.addLocalVariable(name, type);
      }
    }

    for (final b in cfg.blocks) {
      for (var v in b.stmts.declaredVariables()) {
        addDeclaredLocal(v.key, v.value);
      }
      final t = b.term;
      if (t is _TCatchDispatch) {
        for (final c in t.clauses) {
          if (c.varName != null) {
            addDeclaredLocal(c.varName!, c.varType ?? _astTypeInt);
          }
        }
      } else if (t is _TReturn) {
        for (var v in [t.stmt].declaredVariables()) {
          addDeclaredLocal(v.key, v.value);
        }
      } else if (t is _TCallCheck) {
        for (var v in [t.stmt].declaredVariables()) {
          addDeclaredLocal(v.key, v.value);
        }
      }
    }

    for (var t in cfg.temps) {
      context.addLocalVariable(t.name, t.type);
    }
    final pcIdx = context.addLocalVariable('\$exc_pc', _astTypeInt32);

    List<int> defaultConst(ASTType t) {
      final kind = t.wasmType;
      if (kind == WasmType.voidType) return const [];
      if (kind == WasmType.f64Type) return Wasm64.f64Const(0);
      if (kind == WasmType.i32Type) return Wasm32.i32Const(0);
      return Wasm64.i64Const(0);
    }

    // Stores the value currently in [valueLocal] (of wasm-kind [kind]) into the
    // EXC_VALUE slot.
    List<int> storeThrownValue(int valueLocal, WasmType kind) => [
      ...Wasm32.i32Const(0),
      ...Wasm.localGet(valueLocal),
      if (kind == WasmType.f64Type)
        ...Wasm64.f64Store(FloatAlign.align3, valOff)
      else if (kind == WasmType.i32Type)
        ...Wasm32.i32Store(2, valOff)
      else
        ...Wasm64.i64Store(3, valOff),
    ];

    // Loads EXC_VALUE (with width chosen by the catch variable's wasm-kind) into
    // the catch variable local.
    List<int> bindCatchVar(_CatchInfo c) {
      if (c.varName == null) return const [];
      final v = context.getLocalVariable(c.varName!)!;
      final kind = v.type.wasmType;
      return [
        ...Wasm32.i32Const(0),
        if (kind == WasmType.f64Type)
          ...Wasm64.f64Load(FloatAlign.align3, valOff)
        else if (kind == WasmType.i32Type)
          ...Wasm32.i32Load(2, valOff)
        else
          ...Wasm64.i64Load(3, valOff),
        ...Wasm.localSet(v.index),
      ];
    }

    List<int> setPending(int value) => [
      ...Wasm32.i32Const(0),
      ...Wasm32.i32Const(value),
      ...Wasm32.i32Store(2, pendOff),
    ];

    final body = newOutput();
    final blocks = cfg.blocks;
    final n = blocks.length - 1;

    body.write(Wasm.loop(WasmType.voidType));
    for (var i = 0; i <= n; i++) {
      body.write(Wasm.block(WasmType.voidType));
    }
    body.write([
      ...Wasm.localGet(pcIdx),
      ...Wasm.brTable([for (var j = 0; j <= n; j++) j], 0),
    ]);

    // Emits `(EXC_TAG == t0) || (EXC_TAG == t1) || ...` leaving an i32 bool on
    // the stack.
    void emitTagTest(Set<int> tags) {
      final list = tags.toList();
      for (var k = 0; k < list.length; k++) {
        body.write([
          ...Wasm32.i32Const(0),
          ...Wasm32.i32Load(2, tagOff),
          ...Wasm32.i32Const(list[k]),
          Wasm32.i32Equals,
        ]);
        if (k > 0) body.writeByte(Wasm32.i32BitwiseOr);
      }
    }

    // Emits the catch-clause match chain for a dispatch terminator.
    void emitCatchChain(List<_CatchInfo> clauses, int noMatchPc, int idx) {
      if (idx >= clauses.length) {
        body.write([...Wasm32.i32Const(noMatchPc), ...Wasm.localSet(pcIdx)]);
        return;
      }
      final c = clauses[idx];
      if (c.tags == null || c.tags!.isEmpty) {
        // Catch-all: clear pending, bind, jump to body.
        body.write(setPending(0));
        body.write(bindCatchVar(c));
        body.write([...Wasm32.i32Const(c.bodyPc), ...Wasm.localSet(pcIdx)]);
        return;
      }
      emitTagTest(c.tags!);
      body.write([...Wasm.ifInstruction(WasmType.voidType)]);
      body.write(setPending(0));
      body.write(bindCatchVar(c));
      body.write([...Wasm32.i32Const(c.bodyPc), ...Wasm.localSet(pcIdx)]);
      body.write([Wasm.elseInstruction]);
      emitCatchChain(clauses, noMatchPc, idx + 1);
      body.write([Wasm.end]);
    }

    for (var i = 0; i <= n; i++) {
      body.writeByte(Wasm.end); // end $b_i => bb_i follows
      final bb = blocks[i];
      final loopDepth = n - i;

      bb.rawInit?.call(body, context);

      for (final s in bb.stmts) {
        generateASTStatement(s, out: body, context: context);
      }

      final term = bb.term!;
      switch (term) {
        case _TGoto():
          body.write([
            ...Wasm32.i32Const(term.pc),
            ...Wasm.localSet(pcIdx),
            ...Wasm.br(loopDepth),
          ]);
        case _TBranch():
          generateASTExpression(term.cond, out: body, context: context);
          context.stackDrop();
          body.write([
            ...Wasm.ifInstruction(WasmType.voidType),
            ...Wasm32.i32Const(term.thenPc),
            ...Wasm.localSet(pcIdx),
            Wasm.elseInstruction,
            ...Wasm32.i32Const(term.elsePc),
            ...Wasm.localSet(pcIdx),
            Wasm.end,
            ...Wasm.br(loopDepth),
          ]);
        case _TThrow():
          generateASTExpression(term.value, out: body, context: context);
          final vtype = context.stackGet(0)!.type;
          final kind = vtype.wasmType;
          final tag = _excTypeTag(vtype);
          final scratch = context.scratchLocal(vtype, 900 + kind.value);
          body.write(Wasm.localSet(scratch));
          context.stackDrop();
          body.write([
            ...Wasm32.i32Const(0),
            ...Wasm32.i32Const(tag),
            ...Wasm32.i32Store(2, tagOff),
          ]);
          body.write(storeThrownValue(scratch, kind));
          body.write(setPending(1));
          body.write([
            ...Wasm32.i32Const(term.handlerPc),
            ...Wasm.localSet(pcIdx),
            ...Wasm.br(loopDepth),
          ]);
        case _TCatchDispatch():
          emitCatchChain(term.clauses, term.noMatchPc, 0);
          body.write(Wasm.br(loopDepth));
        case _TPropagate():
          body.write(setPending(1));
          if (!returnType.isVoid) body.write(defaultConst(returnType));
          body.writeByte(Wasm.functionReturn);
        case _TCallCheck():
          generateASTStatement(term.stmt, out: body, context: context);
          body.write([
            ...Wasm32.i32Const(0),
            ...Wasm32.i32Load(2, pendOff),
            ...Wasm.ifInstruction(WasmType.voidType),
            ...Wasm32.i32Const(term.handlerPc),
            ...Wasm.localSet(pcIdx),
            Wasm.elseInstruction,
            ...Wasm32.i32Const(term.contPc),
            ...Wasm.localSet(pcIdx),
            Wasm.end,
            ...Wasm.br(loopDepth),
          ]);
        case _TReturn():
          generateASTStatement(term.stmt, out: body, context: context);
        case _TReturnLocal():
          final rv = context.getLocalVariable(term.name)!;
          body.write(Wasm.localGet(rv.index));
          body.writeByte(Wasm.functionReturn);
        case _TReturnEnd():
          if (!returnType.isVoid) body.write(defaultConst(returnType));
          body.writeByte(Wasm.functionReturn);
        case _TLeaf():
        case _TInternal():
          throw StateError("Async terminator in exception CFG: $term");
      }
    }

    body.writeByte(Wasm.end); // end loop

    if (!returnType.isVoid) {
      body.writeByte(Wasm.unreachable);
      body.write(defaultConst(returnType));
    }

    final outBody = newOutput();
    final scratchTypes = context.scratchLocalTypes;
    outBody.write(
      Leb128.encodeUnsigned(
        declaredLocals.length + cfg.temps.length + 1 + scratchTypes.length,
      ),
      description: "Local variables count",
    );
    for (var v in declaredLocals) {
      outBody.write(Leb128.encodeUnsigned(1));
      outBody.writeByte(v.type.wasmCode);
    }
    for (var t in cfg.temps) {
      outBody.write(Leb128.encodeUnsigned(1));
      outBody.writeByte(t.type.wasmCode);
    }
    outBody.write(Leb128.encodeUnsigned(1), description: "\$exc_pc");
    outBody.writeByte(WasmType.i32Type.value);
    for (var t in scratchTypes) {
      outBody.write(Leb128.encodeUnsigned(1));
      outBody.writeByte(t.wasmCode);
    }
    outBody.writeBytes(body);
    outBody.writeByte(Wasm.end, description: "Code body end");

    context.returnsDrop(returnType);
    context.assertReturnsLength(return0);

    out.writeBytesLeb128Block([
      outBody,
    ], description: "Exception function (CFG)");
    return out;
  }

  /// Fixed-point set of Asyncify-eligible function names: async functions
  /// transformable by the linear or CFG path whose awaited module functions are
  /// themselves eligible. Computed once per module.
  Set<String> _asyncifyEligible(WasmModuleContext module) {
    var cached = module.asyncifyEligible;
    if (cached != null) return cached;

    final eligible = <String>{};
    var changed = true;
    while (changed) {
      changed = false;
      for (var f in module.functions) {
        if (eligible.contains(f.name)) continue;
        if (_asyncifyAwaitPoints(f, module, eligible) != null ||
            _buildAsyncifyCfg(f, module, eligible) != null) {
          eligible.add(f.name);
          changed = true;
        }
      }
    }

    return module.asyncifyEligible = eligible;
  }

  /// Emits the Asyncify state machine for a [match]ed async function: a rewind
  /// dispatch prologue, the pre-await segment + suspend (spill live locals,
  /// set state, return), and the post-await resume segment. The host driver
  /// re-invokes the export to rewind. See
  /// `test/apollovm_wasm_asyncify_*` and `WasmModuleContext` for the layout.
  BytesOutput _generateAsyncifyFunction(
    ASTFunctionDeclaration f,
    _AsyncifyMatch match, {
    required BytesOutput out,
    required WasmContext context,
    required WasmModuleContext module,
  }) {
    module.requiresAsyncify = true;
    module.requiresMemory = true;
    module.asyncifyFunctionNames.add(f.name);

    const stateOff = WasmModuleContext.asyncifyStateOffset;
    const resultOff = WasmModuleContext.asyncifyResultOffset;

    final returnType = f.effectiveReturnType;
    final return0 = context.returnsLength;
    context.returnsPush(returnType, "async `${f.name}` -> $returnType");

    // Register params, then declared locals (preamble/index order), then the
    // `$resume` control local. Collect every user local for spill/restore.
    final userLocals = <({int index, ASTType type})>[];
    for (var v in f.parameters.declaredVariables()) {
      userLocals.add((
        index: context.addLocalVariable(v.key, v.value),
        type: v.value,
      ));
    }
    final declaredLocals = f.statements.declaredVariables();
    for (var v in declaredLocals) {
      userLocals.add((
        index: context.addLocalVariable(v.key, v.value),
        type: v.value,
      ));
    }
    final resumeIdx = context.addLocalVariable(
      '\$asyncify_resume',
      _astTypeInt32,
    );

    const spOff = WasmModuleContext.asyncifyStackPointerOffset;
    final frameSize = 8 + userLocals.length * 8; // resume(8) + N i64 slots

    List<int> defaultConst(ASTType t) {
      final k = t.wasmType;
      if (k == WasmType.voidType) return const [];
      if (k == WasmType.f64Type) return Wasm64.f64Const(0);
      if (k == WasmType.i32Type) return Wasm32.i32Const(0);
      return Wasm64.i64Const(0);
    }

    // The frame-stack pointer (SP) value on the stack.
    List<int> loadSP() => [...Wasm32.i32Const(0), ...Wasm32.i32Load(2, spOff)];

    // SP += frameSize (or -= when [sub]).
    List<int> moveSP({required bool sub}) => [
      ...Wasm32.i32Const(0),
      ...loadSP(),
      ...Wasm32.i32Const(frameSize),
      if (sub) Wasm32.i32Subtract else Wasm32.i32Add,
      ...Wasm32.i32Store(2, spOff),
    ];

    // Spill / restore local [idx] at byte [frameOff] within the current frame
    // (base = SP).
    List<int> spillFrame(int idx, ASTType t, int frameOff) {
      final k = t.wasmType;
      return [
        ...loadSP(),
        ...Wasm32.i32Const(frameOff),
        Wasm32.i32Add,
        ...Wasm.localGet(idx),
        if (k == WasmType.f64Type)
          ...Wasm64.f64Store(FloatAlign.align3, 0)
        else if (k == WasmType.i32Type)
          ...Wasm32.i32Store(2, 0)
        else
          ...Wasm64.i64Store(3, 0),
      ];
    }

    List<int> restoreFrame(int idx, ASTType t, int frameOff) {
      final k = t.wasmType;
      return [
        ...loadSP(),
        ...Wasm32.i32Const(frameOff),
        Wasm32.i32Add,
        if (k == WasmType.f64Type)
          ...Wasm64.f64Load(FloatAlign.align3, 0)
        else if (k == WasmType.i32Type)
          ...Wasm32.i32Load(2, 0)
        else
          ...Wasm64.i64Load(3, 0),
        ...Wasm.localSet(idx),
      ];
    }

    final points = match.awaits;
    final k = points.length;
    final stmts = f.statements;

    // Loads the host-provided leaf result into a resume's result variable.
    List<int> loadResultInto(_AwaitPoint p) {
      if (p.resultVarName == null) return const [];
      final rv = context.getLocalVariable(p.resultVarName!)!;
      final rk = (p.resultType ?? rv.type).wasmType;
      return [
        ...Wasm32.i32Const(0),
        if (rk == WasmType.f64Type)
          ...Wasm64.f64Load(FloatAlign.align3, resultOff)
        else if (rk == WasmType.i32Type)
          ...Wasm32.i32Load(2, resultOff)
        else
          ...Wasm64.i64Load(3, resultOff),
        ...Wasm.localSet(rv.index),
      ];
    }

    final body = newOutput();

    // Suspend: push this frame (resume index + spilled locals), advance SP,
    // flag unwound, and return a default value.
    void emitSuspend(int resumeValue) {
      body.write([
        ...loadSP(),
        ...Wasm32.i32Const(resumeValue),
        ...Wasm32.i32Store(2, 0), // frame[0] = resume
      ]);
      for (var i = 0; i < userLocals.length; i++) {
        body.write(
          spillFrame(userLocals[i].index, userLocals[i].type, 8 + i * 8),
        );
      }
      body.write([
        ...moveSP(sub: false),
        ...Wasm32.i32Const(0),
        ...Wasm32.i32Const(1),
        ...Wasm32.i32Store(2, stateOff), // STATE = unwinding
        ...defaultConst(returnType),
      ]);
      body.writeByte(Wasm.functionReturn);
    }

    // Leaf await (host import): evaluate args, call the suspending import, and
    // unconditionally suspend.
    void emitLeafSuspend(_AwaitPoint p, int resumeValue) {
      final argTypes = <WasmType>[];
      for (var arg in p.args) {
        generateASTExpression(arg, out: body, context: context);
        argTypes.add(context.stackGet(0)!.type.wasmType);
      }
      final importIndex = module.registerImportedFunction(
        'env',
        p.calleeName,
        argTypes,
        const [],
      );
      body.write(Wasm.call(importIndex));
      for (var _ in p.args) {
        context.stackDrop();
      }
      emitSuspend(resumeValue);
    }

    // Leaf resume: deliver the host result and complete the rewind.
    void emitLeafResume(_AwaitPoint p) {
      body.write(loadResultInto(p));
      body.write([
        ...Wasm32.i32Const(0),
        ...Wasm32.i32Const(0),
        ...Wasm32.i32Store(2, stateOff), // STATE = normal (rewind done)
      ]);
    }

    // Internal await (module async fn): call it and propagate any unwind. On a
    // fresh pass the callee may suspend (=> we propagate); on rewind the call is
    // re-executed (the callee rewinds and returns its real value).
    void emitInternalAwait(_AwaitPoint p, int resumeValue) {
      final calleeIndex = module.functionIndex(p.calleeName, p.args.length)!;
      final callee = module.functionByIndex(calleeIndex)!;
      for (var i = 0; i < p.args.length; i++) {
        generateASTExpression(p.args[i], out: body, context: context);
        final paramType = _orderedParamType(callee.parameters, i);
        if (paramType != null) {
          _autoConvertStackTypes(
            context.stackGet(0)!.type,
            paramType,
            out: body,
            context: context,
          );
        }
      }
      body.write(Wasm.call(calleeIndex));
      for (var _ in p.args) {
        context.stackDrop();
      }
      if (p.resultVarName != null) {
        final rv = context.getLocalVariable(p.resultVarName!)!;
        body.write(Wasm.localSet(rv.index));
      } else if (!callee.effectiveReturnType.isVoid) {
        body.writeByte(Wasm.drop);
      }
      // Unwind propagation: if the callee suspended, suspend this frame too.
      body.write([
        ...Wasm32.i32Const(0),
        ...Wasm32.i32Load(2, stateOff),
        ...Wasm32.i32Const(1),
        Wasm32.i32Equals,
        ...Wasm.ifInstruction(WasmType.voidType),
      ]);
      emitSuspend(resumeValue);
      body.writeByte(Wasm.end);
    }

    // --- prologue: on rewind, pop this frame (restore the resume index and
    // locals) WITHOUT clearing the global state — the state stays "rewinding"
    // until the leaf that suspended completes. On a fresh call resume = 0. ---
    body.write([
      ...Wasm32.i32Const(0),
      ...Wasm32.i32Load(2, stateOff),
      ...Wasm32.i32Const(2),
      Wasm32.i32Equals,
      ...Wasm.ifInstruction(WasmType.voidType),
      ...moveSP(sub: true),
      ...loadSP(),
      ...Wasm32.i32Load(2, 0),
      ...Wasm.localSet(resumeIdx), // resume = frame[0]
    ]);
    for (var i = 0; i < userLocals.length; i++) {
      body.write(
        restoreFrame(userLocals[i].index, userLocals[i].type, 8 + i * 8),
      );
    }
    body.write([
      Wasm.elseInstruction,
      ...Wasm32.i32Const(0),
      ...Wasm.localSet(resumeIdx),
      Wasm.end,
    ]);

    // --- resume dispatch: nested blocks ($exit, $L_k .. $L_0) with a
    // `br_table` over the resume index. Index 0 => segment 0 (fresh); index
    // i => resume just after await i-1. ---
    for (var i = 0; i < k + 2; i++) {
      body.write(Wasm.block(WasmType.voidType));
    }
    body.write([
      ...Wasm.localGet(resumeIdx),
      ...Wasm.brTable([for (var j = 0; j <= k; j++) j], k + 1),
    ]);
    body.writeByte(Wasm.end); // end $L_0 => segment 0 follows

    // Segment 0 (before the first await).
    for (var i = 0; i < points[0].stmtIndex; i++) {
      generateASTStatement(stmts[i], out: body, context: context);
    }
    // A leaf await suspends here (before its block boundary); an internal await
    // emits all its code after the boundary (so it re-executes on rewind).
    if (!points[0].isInternal) emitLeafSuspend(points[0], 1);
    body.writeByte(Wasm.end); // end $L_1

    for (var j = 1; j <= k; j++) {
      final prev = points[j - 1];
      if (prev.isInternal) {
        emitInternalAwait(prev, j);
      } else {
        emitLeafResume(prev);
      }

      final startIdx = prev.stmtIndex + 1;
      final endIdx = (j < k) ? points[j].stmtIndex : stmts.length;
      for (var i = startIdx; i < endIdx; i++) {
        generateASTStatement(stmts[i], out: body, context: context);
      }

      if (j < k && !points[j].isInternal) emitLeafSuspend(points[j], j + 1);
      body.writeByte(Wasm.end); // end $L_{j+1} (=> $exit when j == k)
    }

    // The `br_table` default lands here (past `end $exit`) with an empty stack,
    // so a non-void function needs an unreachable default to type-check — the
    // real resume paths always `return` before reaching it.
    if (!returnType.isVoid) {
      body.writeByte(Wasm.unreachable);
      body.write(defaultConst(returnType));
    }

    // --- assemble: locals preamble + body + end ---
    final outBody = newOutput();
    final scratchTypes = context.scratchLocalTypes;
    outBody.write(
      Leb128.encodeUnsigned(declaredLocals.length + 1 + scratchTypes.length),
      description: "Local variables count",
    );
    for (var v in declaredLocals) {
      outBody.write(Leb128.encodeUnsigned(1));
      outBody.writeByte(v.value.wasmCode);
    }
    outBody.write(Leb128.encodeUnsigned(1), description: "\$asyncify_resume");
    outBody.writeByte(WasmType.i32Type.value);
    for (var t in scratchTypes) {
      outBody.write(Leb128.encodeUnsigned(1));
      outBody.writeByte(t.wasmCode);
    }
    outBody.writeBytes(body);
    outBody.writeByte(Wasm.end, description: "Code body end");

    context.returnsDrop(returnType);
    context.assertReturnsLength(return0);

    out.writeBytesLeb128Block([
      outBody,
    ], description: "Async function (asyncify)");
    return out;
  }

  /// Emits the control-flow-aware Asyncify state machine for [cfg]: a `loop` +
  /// `br_table` dispatch over a `$pc` local, with `$pc` and locals spilled to
  /// the Asyncify frame stack at each suspension (see `_buildAsyncifyCfg`).
  BytesOutput _generateAsyncifyCfgFunction(
    ASTFunctionDeclaration f,
    _Cfg cfg, {
    required BytesOutput out,
    required WasmContext context,
    required WasmModuleContext module,
  }) {
    module.requiresAsyncify = true;
    module.requiresMemory = true;
    module.asyncifyFunctionNames.add(f.name);

    const stateOff = WasmModuleContext.asyncifyStateOffset;
    const spOff = WasmModuleContext.asyncifyStackPointerOffset;
    const resultOff = WasmModuleContext.asyncifyResultOffset;

    final returnType = f.effectiveReturnType;
    final return0 = context.returnsLength;
    context.returnsPush(returnType, "async-cfg `${f.name}` -> $returnType");

    final userLocals = <({int index, ASTType type})>[];
    for (var v in f.parameters.declaredVariables()) {
      userLocals.add((
        index: context.addLocalVariable(v.key, v.value),
        type: v.value,
      ));
    }
    final declaredLocals = f.statements.declaredVariables();
    for (var v in declaredLocals) {
      userLocals.add((
        index: context.addLocalVariable(v.key, v.value),
        type: v.value,
      ));
    }
    // Synthetic temps (e.g. for `return await ...`) are spilled like locals.
    for (var t in cfg.temps) {
      userLocals.add((
        index: context.addLocalVariable(t.name, t.type),
        type: t.type,
      ));
    }
    final pcIdx = context.addLocalVariable('\$asyncify_pc', _astTypeInt32);
    final frameSize = 8 + userLocals.length * 8;

    List<int> defaultConst(ASTType t) {
      final kind = t.wasmType;
      if (kind == WasmType.voidType) return const [];
      if (kind == WasmType.f64Type) return Wasm64.f64Const(0);
      if (kind == WasmType.i32Type) return Wasm32.i32Const(0);
      return Wasm64.i64Const(0);
    }

    List<int> loadSP() => [...Wasm32.i32Const(0), ...Wasm32.i32Load(2, spOff)];

    List<int> moveSP({required bool sub}) => [
      ...Wasm32.i32Const(0),
      ...loadSP(),
      ...Wasm32.i32Const(frameSize),
      if (sub) Wasm32.i32Subtract else Wasm32.i32Add,
      ...Wasm32.i32Store(2, spOff),
    ];

    List<int> spillFrame(int idx, ASTType t, int frameOff) {
      final kind = t.wasmType;
      return [
        ...loadSP(),
        ...Wasm32.i32Const(frameOff),
        Wasm32.i32Add,
        ...Wasm.localGet(idx),
        if (kind == WasmType.f64Type)
          ...Wasm64.f64Store(FloatAlign.align3, 0)
        else if (kind == WasmType.i32Type)
          ...Wasm32.i32Store(2, 0)
        else
          ...Wasm64.i64Store(3, 0),
      ];
    }

    List<int> restoreFrame(int idx, ASTType t, int frameOff) {
      final kind = t.wasmType;
      return [
        ...loadSP(),
        ...Wasm32.i32Const(frameOff),
        Wasm32.i32Add,
        if (kind == WasmType.f64Type)
          ...Wasm64.f64Load(FloatAlign.align3, 0)
        else if (kind == WasmType.i32Type)
          ...Wasm32.i32Load(2, 0)
        else
          ...Wasm64.i64Load(3, 0),
        ...Wasm.localSet(idx),
      ];
    }

    List<int> loadResultInto(_AwaitPoint p) {
      if (p.resultVarName == null) return const [];
      final rv = context.getLocalVariable(p.resultVarName!)!;
      final rk = (p.resultType ?? rv.type).wasmType;
      return [
        ...Wasm32.i32Const(0),
        if (rk == WasmType.f64Type)
          ...Wasm64.f64Load(FloatAlign.align3, resultOff)
        else if (rk == WasmType.i32Type)
          ...Wasm32.i32Load(2, resultOff)
        else
          ...Wasm64.i64Load(3, resultOff),
        ...Wasm.localSet(rv.index),
      ];
    }

    final body = newOutput();

    // Suspend: push the frame (resume `$pc` + locals), advance SP, flag
    // unwound, and return a default value.
    void emitSuspend(int resumePc) {
      body.write([
        ...loadSP(),
        ...Wasm32.i32Const(resumePc),
        ...Wasm32.i32Store(2, 0), // frame[0] = resume pc
      ]);
      for (var i = 0; i < userLocals.length; i++) {
        body.write(
          spillFrame(userLocals[i].index, userLocals[i].type, 8 + i * 8),
        );
      }
      body.write([
        ...moveSP(sub: false),
        ...Wasm32.i32Const(0),
        ...Wasm32.i32Const(1),
        ...Wasm32.i32Store(2, stateOff),
        ...defaultConst(returnType),
      ]);
      body.writeByte(Wasm.functionReturn);
    }

    // --- prologue: on rewind pop this frame (restore `$pc` + locals) without
    // clearing the state; on a fresh call `$pc` = 0. ---
    body.write([
      ...Wasm32.i32Const(0),
      ...Wasm32.i32Load(2, stateOff),
      ...Wasm32.i32Const(2),
      Wasm32.i32Equals,
      ...Wasm.ifInstruction(WasmType.voidType),
      ...moveSP(sub: true),
      ...loadSP(),
      ...Wasm32.i32Load(2, 0),
      ...Wasm.localSet(pcIdx),
    ]);
    for (var i = 0; i < userLocals.length; i++) {
      body.write(
        restoreFrame(userLocals[i].index, userLocals[i].type, 8 + i * 8),
      );
    }
    body.write([
      Wasm.elseInstruction,
      ...Wasm32.i32Const(0),
      ...Wasm.localSet(pcIdx),
      Wasm.end,
    ]);

    final blocks = cfg.blocks;
    final n = blocks.length - 1; // max pc

    // --- dispatch: loop { block*(n+1) br_table($pc) ; bb0 ; bb1 ; ... } ---
    body.write(Wasm.loop(WasmType.voidType));
    for (var i = 0; i <= n; i++) {
      body.write(Wasm.block(WasmType.voidType));
    }
    body.write([
      ...Wasm.localGet(pcIdx),
      ...Wasm.brTable([for (var j = 0; j <= n; j++) j], 0),
    ]);

    for (var i = 0; i <= n; i++) {
      body.writeByte(Wasm.end); // end $b_i => bb_i follows
      final bb = blocks[i];
      final loopDepth = n - i; // relative depth of `loop` from this bb

      if (bb.leafResume != null) {
        body.write(loadResultInto(bb.leafResume!));
        body.write([
          ...Wasm32.i32Const(0),
          ...Wasm32.i32Const(0),
          ...Wasm32.i32Store(2, stateOff), // STATE = normal (rewind done)
        ]);
      }

      bb.rawInit?.call(body, context);

      for (final s in bb.stmts) {
        generateASTStatement(s, out: body, context: context);
      }

      final term = bb.term!;
      switch (term) {
        case _TGoto():
          body.write([
            ...Wasm32.i32Const(term.pc),
            ...Wasm.localSet(pcIdx),
            ...Wasm.br(loopDepth),
          ]);
        case _TBranch():
          generateASTExpression(term.cond, out: body, context: context);
          context.stackDrop();
          body.write([
            ...Wasm.ifInstruction(WasmType.voidType),
            ...Wasm32.i32Const(term.thenPc),
            ...Wasm.localSet(pcIdx),
            Wasm.elseInstruction,
            ...Wasm32.i32Const(term.elsePc),
            ...Wasm.localSet(pcIdx),
            Wasm.end,
            ...Wasm.br(loopDepth),
          ]);
        case _TLeaf():
          final argTypes = <WasmType>[];
          for (var arg in term.await.args) {
            generateASTExpression(arg, out: body, context: context);
            argTypes.add(context.stackGet(0)!.type.wasmType);
          }
          final importIndex = module.registerImportedFunction(
            'env',
            term.await.calleeName,
            argTypes,
            const [],
          );
          body.write(Wasm.call(importIndex));
          for (var _ in term.await.args) {
            context.stackDrop();
          }
          emitSuspend(term.resumePc);
        case _TInternal():
          final calleeIndex = module.functionIndex(
            term.await.calleeName,
            term.await.args.length,
          )!;
          final callee = module.functionByIndex(calleeIndex)!;
          for (var ai = 0; ai < term.await.args.length; ai++) {
            generateASTExpression(
              term.await.args[ai],
              out: body,
              context: context,
            );
            final paramType = _orderedParamType(callee.parameters, ai);
            if (paramType != null) {
              _autoConvertStackTypes(
                context.stackGet(0)!.type,
                paramType,
                out: body,
                context: context,
              );
            }
          }
          body.write(Wasm.call(calleeIndex));
          for (var _ in term.await.args) {
            context.stackDrop();
          }
          if (term.await.resultVarName != null) {
            final rv = context.getLocalVariable(term.await.resultVarName!)!;
            body.write(Wasm.localSet(rv.index));
          } else if (!callee.effectiveReturnType.isVoid) {
            body.writeByte(Wasm.drop);
          }
          body.write([
            ...Wasm32.i32Const(0),
            ...Wasm32.i32Load(2, stateOff),
            ...Wasm32.i32Const(1),
            Wasm32.i32Equals,
            ...Wasm.ifInstruction(WasmType.voidType),
          ]);
          emitSuspend(i); // resume this same block (re-call the callee)
          body.write([
            Wasm.end,
            ...Wasm32.i32Const(term.contPc),
            ...Wasm.localSet(pcIdx),
            ...Wasm.br(loopDepth),
          ]);
        case _TReturn():
          generateASTStatement(term.stmt, out: body, context: context);
        case _TReturnLocal():
          final rv = context.getLocalVariable(term.name)!;
          body.write(Wasm.localGet(rv.index));
          body.writeByte(Wasm.functionReturn);
        case _TReturnEnd():
          if (!returnType.isVoid) body.write(defaultConst(returnType));
          body.writeByte(Wasm.functionReturn);
        case _TThrow():
        case _TCatchDispatch():
        case _TPropagate():
        case _TCallCheck():
          throw StateError("Exception terminator in async CFG: $term");
      }
    }

    body.writeByte(Wasm.end); // end loop

    // The loop never falls through (every block branches / returns / suspends),
    // but a non-void function still needs an unreachable default to type-check.
    if (!returnType.isVoid) {
      body.writeByte(Wasm.unreachable);
      body.write(defaultConst(returnType));
    }

    // --- assemble: locals preamble + body + end ---
    final outBody = newOutput();
    final scratchTypes = context.scratchLocalTypes;
    outBody.write(
      Leb128.encodeUnsigned(
        declaredLocals.length + cfg.temps.length + 1 + scratchTypes.length,
      ),
      description: "Local variables count",
    );
    for (var v in declaredLocals) {
      outBody.write(Leb128.encodeUnsigned(1));
      outBody.writeByte(v.value.wasmCode);
    }
    for (var t in cfg.temps) {
      outBody.write(Leb128.encodeUnsigned(1));
      outBody.writeByte(t.type.wasmCode);
    }
    outBody.write(Leb128.encodeUnsigned(1), description: "\$asyncify_pc");
    outBody.writeByte(WasmType.i32Type.value);
    for (var t in scratchTypes) {
      outBody.write(Leb128.encodeUnsigned(1));
      outBody.writeByte(t.wasmCode);
    }
    outBody.writeBytes(body);
    outBody.writeByte(Wasm.end, description: "Code body end");

    context.returnsDrop(returnType);
    context.assertReturnsLength(return0);

    out.writeBytesLeb128Block([
      outBody,
    ], description: "Async function (asyncify CFG)");
    return out;
  }

  @override
  BytesOutput generateASTStatement(
    ASTStatement statement, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    if (statement is ASTStatementExpression) {
      return generateASTStatementExpression(
        statement,
        out: out,
        context: context,
      );
    } else if (statement is ASTStatementVariableDeclaration) {
      return generateASTStatementVariableDeclaration(
        statement,
        out: out,
        context: context,
      );
    } else if (statement is ASTBranch) {
      return generateASTBranch(statement, out: out, context: context);
    } else if (statement is ASTStatementForLoop) {
      return generateASTStatementForLoop(statement, out: out, context: context);
    } else if (statement is ASTStatementForEach) {
      return generateASTStatementForEach(statement, out: out, context: context);
    } else if (statement is ASTStatementDoWhileLoop) {
      return generateASTStatementDoWhileLoop(
        statement,
        out: out,
        context: context,
      );
    } else if (statement is ASTStatementWhileLoop) {
      return generateASTStatementWhileLoop(
        statement,
        out: out,
        context: context,
      );
    } else if (statement is ASTStatementSwitch) {
      return generateASTStatementSwitch(statement, out: out, context: context);
    } else if (statement is ASTStatementBreak) {
      return generateASTStatementBreak(statement, out: out, context: context);
    } else if (statement is ASTStatementContinue) {
      return generateASTStatementContinue(
        statement,
        out: out,
        context: context,
      );
    } else if (statement is ASTStatementBlock) {
      return generateASTStatementBlock(statement, out: out);
    } else if (statement is ASTStatementFunctionDeclaration) {
      return generateASTStatementFunctionDeclaration(statement, out: out);
    } else if (statement is ASTStatementReturnNull) {
      return generateASTStatementReturnNull(statement, out: out);
    } else if (statement is ASTStatementReturnValue) {
      return generateASTStatementReturnValue(
        statement,
        out: out,
        context: context,
      );
    } else if (statement is ASTStatementReturnVariable) {
      return generateASTStatementReturnVariable(
        statement,
        out: out,
        context: context,
      );
    } else if (statement is ASTStatementReturnWithExpression) {
      return generateASTStatementReturnWithExpression(
        statement,
        out: out,
        context: context,
      );
    } else if (statement is ASTStatementReturn) {
      return generateASTStatementReturn(statement, out: out, context: context);
    } else if (statement is ASTStatementAssert) {
      // Refuse rather than mis-compile: `assert` throws on failure, and the
      // Wasm backend has no exception lowering for a bare throw.
      throw UnsupportedSyntaxError(
        'Wasm compilation of `assert` is not implemented: $statement',
      );
    }

    throw UnsupportedError("Can't handle statement: $statement");
  }

  @override
  BytesOutput generateASTFunctionParameterDeclaration(
    ASTFunctionParameterDeclaration parameter, {
    BytesOutput? out,
  }) {
    // TODO: implement generateASTFunctionParameterDeclaration
    throw UnimplementedError('generateASTFunctionParameterDeclaration');
  }

  @override
  BytesOutput generateASTParameterDeclaration(
    ASTParameterDeclaration parameter, {
    BytesOutput? out,
  }) {
    // TODO: implement generateASTParameterDeclaration
    throw UnimplementedError('generateASTParameterDeclaration');
  }

  @override
  BytesOutput generateASTParametersDeclaration(
    ASTParametersDeclaration parameters, {
    BytesOutput? out,
  }) {
    // TODO: implement generateASTParametersDeclaration
    throw UnimplementedError('generateASTParametersDeclaration');
  }

  @override
  BytesOutput generateASTScopeVariable(
    ASTScopeVariable variable, {
    String? callingFunction,
    BytesOutput? out,
  }) {
    // TODO: implement generateASTScopeVariable
    throw UnimplementedError('generateASTScopeVariable');
  }

  @override
  BytesOutput generateASTStatementExpression(
    ASTStatementExpression statement, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    final expression = statement.expression;
    generateASTExpression(expression, out: out, context: context);

    // A pre/post increment or decrement (`i++`, `++i`, `i--`, `--i`) is an
    // *expression*: its codegen leaves the operation's value on the real Wasm
    // stack (unlike a plain assignment, which leaves only a phantom
    // virtual-stack entry with the real stack balanced). In statement position
    // that value is discarded, so it must be dropped — otherwise it lingers to
    // the end of the enclosing (void) block and fails Wasm validation with
    // "values remaining on stack at end of block", e.g. `i++;` in a `while`
    // body. In a `for` header the update expression is instead unwound by the
    // loop's back-edge branch, so this only matters for statement position.
    if (expression is ASTExpressionVariableDirectOperation) {
      out.writeByte(
        Wasm.drop,
        description: "[OP] drop unused ${expression.operator} result",
      );
      context.stackDrop();
    }

    return out;
  }

  @override
  BytesOutput generateASTStatementForLoop(
    ASTStatementForLoop forLoop, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    // Emit the init statement BEFORE the loop block:
    generateASTStatement(forLoop.initStatement, out: out, context: context);

    _generateLoop(
      out: out,
      context: context,
      conditionExpression: forLoop.conditionExpression,
      loopBlock: forLoop.loopBlock,
      continueExpression: forLoop.continueExpression,
      description: "for",
    );

    return out;
  }

  @override
  BytesOutput generateASTStatementForEach(
    ASTStatementForEach forEach, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    // Evaluate the iterable (a list pointer) into a scratch local.
    generateASTExpression(
      forEach.iterableExpression,
      out: out,
      context: context,
    );
    var iterType = context.stackGet(0)!.type;
    if (iterType is! ASTTypeArray) {
      throw UnimplementedError(
        "Wasm for-each over $iterType is not supported yet.",
      );
    }
    var elemType = iterType.componentType;
    var size = _elemSize(elemType);

    var listScratch = context.scratchLocal(_astTypeString, 7);
    var iScratch = context.scratchLocal(_astTypeString, 8);
    var dataScratch = context.scratchLocal(_astTypeString, 10);
    out.write(Wasm.localSet(listScratch));
    context.stackDrop(); // iterable consumed

    // dataPtr = load(header, 8) — cached once (length is read each iteration so
    // the loop reflects a `return`-truncated view, like the interpreter).
    out.write(Wasm.localGet(listScratch));
    out.write(Wasm32.i32Load(2, 8));
    out.write(Wasm.localSet(dataScratch));

    var eLocal = _getLocalVariable(context, forEach.variableName);

    // i = 0
    out.write(Wasm32.i32Const(0));
    out.write(Wasm.localSet(iScratch));

    // block(break) { loop(repeat) { if (i >= len) break; e = data[i];
    //   block(continue) { <body> }; i++; continue } }
    out.write(Wasm.block(WasmType.voidType));
    context.controlDepth++;
    final breakLevel = context.controlDepth;
    out.write(Wasm.loop(WasmType.voidType));
    context.controlDepth++;
    final repeatLevel = context.controlDepth;

    // if (i >= len) br break
    out.write(Wasm.localGet(iScratch));
    out.write(Wasm.localGet(listScratch));
    out.write(Wasm32.i32Load(2, 0)); // length
    out.writeByte(Wasm32.i32GreaterThanOrEqualsUnsigned);
    out.write(Wasm.brIf(context.controlDepth - breakLevel));

    // e = data[i*size]
    out.write(Wasm.localGet(dataScratch));
    out.write(Wasm.localGet(iScratch));
    out.write(Wasm32.i32Const(size));
    out.writeByte(Wasm32.i32Multiply);
    out.writeByte(Wasm32.i32Add);
    _emitElemLoad(out, elemType, 0);
    out.write(Wasm.localSet(eLocal.index));

    // continue target wrapping the body.
    out.write(Wasm.block(WasmType.voidType));
    context.controlDepth++;
    final continueLevel = context.controlDepth;

    // body (a `return` inside emits `return` directly; no extra check needed)
    context.pushLoopFrame(breakLevel: breakLevel, continueLevel: continueLevel);
    generateASTBlock(forEach.loopBlock, out: out, context: context);
    context.popLoopFrame();

    out.writeByte(Wasm.end); // continue block
    context.controlDepth--;

    // i++
    out.write(Wasm.localGet(iScratch));
    out.write(Wasm32.i32Const(1));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localSet(iScratch));

    out.write(Wasm.br(context.controlDepth - repeatLevel)); // continue/repeat
    out.writeByte(Wasm.end); // loop
    context.controlDepth--;
    out.writeByte(Wasm.end); // block
    context.controlDepth--;

    // The body may leave phantom virtual-stack entries (assignments use
    // `local.set` without a matching virtual drop), like the for/while loops;
    // the real Wasm stack stays balanced, so no post-body assertion here.
    return out;
  }

  BytesOutput generateASTStatementDoWhileLoop(
    ASTStatementDoWhileLoop doWhileLoop, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    _generateLoop(
      out: out,
      context: context,
      conditionExpression: doWhileLoop.conditionExpression,
      loopBlock: doWhileLoop.loopBlock,
      continueExpression: null,
      description: "do-while",
      conditionAfterBody: true,
    );

    return out;
  }

  BytesOutput generateASTStatementBreak(
    ASTStatementBreak statement, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();
    out.write(Wasm.br(context.breakBranchLabel), description: "[OP] break");
    return out;
  }

  BytesOutput generateASTStatementContinue(
    ASTStatementContinue statement, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();
    out.write(
      Wasm.br(context.continueBranchLabel),
      description: "[OP] continue",
    );
    return out;
  }

  /// Integer `switch` (C-style fall-through). Encoded as nested blocks with an
  /// inner dispatch that compares the value to each `case` and branches to the
  /// matching case block; cases fall through to the next unless they `break`.
  BytesOutput generateASTStatementSwitch(
    ASTStatementSwitch statement, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    // Evaluate the switch value once into a scratch local. Supported scrutinee
    // kinds:
    //  - `int`    : i64 equality (branch table).
    //  - `String` : content equality via the `__streq` host/synth helper.
    //  - a reference instance (e.g. an `enum` entry): i32 pointer identity —
    //    enum entries are cached `const` singletons, so `==` is identity.
    // A boxed `dynamic`/`Object` scrutinee is not supported (see GAP 5).
    generateASTExpression(statement.expression, out: out, context: context);
    var valueType = context.stackGet(0)!.type;

    // A boxed `dynamic`/`Object` scrutinee (e.g. a JavaScript/Python untyped
    // parameter) is unboxed to a concrete i64 so it can drive the int branch
    // table (case labels are integer literals).
    if (_isObjectType(valueType)) {
      _emitUnboxNumberInto(out, context, _astTypeInt64);
      context.stackReplace(_astTypeInt64, "unboxed dynamic switch scrutinee");
      valueType = _astTypeInt64;
    }

    // A plain `num` (TS/JS `number`) is represented as i64; switch on it as int.
    final switchOnInt =
        valueType == _astTypeInt64 ||
        valueType == _astTypeInt ||
        (valueType is ASTTypeNum && valueType is! ASTTypeDouble);
    final switchOnString = valueType is ASTTypeString;

    // An `enum` scrutinee is compared by ordinal: reduce both the scrutinee and
    // each case entry to their `.index` (i64).
    final enumLayout =
        (!switchOnInt && !switchOnString && valueType.name.isNotEmpty)
        ? context.module?.classLayouts[valueType.name]
        : null;
    final switchOnEnum =
        enumLayout != null && enumLayout.offsets.containsKey('index');
    final enumIndexOffset = switchOnEnum ? enumLayout.offsets['index']! : 0;

    if (!switchOnInt && !switchOnString && !switchOnEnum) {
      throw UnimplementedError(
        "Wasm switch on $valueType is not supported "
        "(int, String or enum only).",
      );
    }

    int? strEqIndex;
    if (switchOnString) {
      var module = context.module!;
      module.requiresMemory = true;
      module.ensureStrEqFunction();
      strEqIndex = module.synthFunctionIndex('__streq')!;
    }

    if (switchOnEnum) {
      context.module?.requiresMemory = true;
      out.write(
        Wasm64.i64Load(3, enumIndexOffset),
        description: "[OP] switch enum scrutinee .index",
      );
      context.stackReplace(_astTypeInt64, "enum scrutinee .index");
    }

    // The scrutinee is held as i64 (int / enum ordinal) or i32 (String handle).
    final ASTType scrutineeLocalType = (switchOnInt || switchOnEnum)
        ? _astTypeInt64
        : _astTypeString;
    var valueLocal = context.scratchLocal(scrutineeLocalType, 17);
    out.write(Wasm.localSet(valueLocal));
    context.stackDrop();

    final cases = statement.cases;
    final n = cases.length;

    // Outer `block` is the break/exit target.
    out.write(
      Wasm.block(WasmType.voidType),
      description: "[OP] block (switch)",
    );
    context.controlDepth++;
    final exitLevel = context.controlDepth;

    // One `block` per case, in reverse source order, so falling out of case i's
    // block lands in case i+1's code (fall-through).
    final caseLevel = List<int>.filled(n, 0);
    for (var i = n - 1; i >= 0; --i) {
      out.write(
        Wasm.block(WasmType.voidType),
        description: "[OP] block (switch case $i)",
      );
      context.controlDepth++;
      caseLevel[i] = context.controlDepth;
    }

    // Dispatch block: compare and branch to the matching case.
    out.write(
      Wasm.block(WasmType.voidType),
      description: "[OP] block (switch dispatch)",
    );
    context.controlDepth++;
    final dispatchLevel = context.controlDepth;

    // Branching to a `block` lands *after* its `end`. Case i's code starts right
    // after the `end` of the previous block, so the entry target for case i is
    // the dispatch block (i == 0) or the previous case's block (i > 0).
    int entryLevel(int i) => i == 0 ? dispatchLevel : caseLevel[i - 1];

    int? defaultIndex;
    for (var i = 0; i < n; ++i) {
      var c = cases[i];
      if (c.isDefault) {
        defaultIndex = i;
        continue;
      }
      out.write(Wasm.localGet(valueLocal));
      context.stackPush(scrutineeLocalType, "switch value");
      generateASTExpression(c.value!, out: out, context: context);
      if (switchOnEnum) {
        // Reduce the case enum entry to its `.index` (i64), then compare ints.
        context.module?.requiresMemory = true;
        out.write(
          Wasm64.i64Load(3, enumIndexOffset),
          description: "[OP] switch enum case .index",
        );
        context.stackReplace(_astTypeInt64, "enum case .index");
      }
      if (switchOnString) {
        // __streq(scrutinee, caseValue) -> i32 (0/1) content equality.
        out.write(
          Wasm.call(strEqIndex!),
          description: "[OP] switch case __streq",
        );
      } else {
        out.writeByte(
          Wasm64.i64Equals,
          description: "[OP] switch case == (i64)",
        );
      }
      context.stackOperationBinary(_astTypeInt32, "switch case ==");
      out.write(
        Wasm.brIf(context.controlDepth - entryLevel(i)),
        description: "[OP] switch br_if case $i",
      );
      context.stackDrop(_astTypeInt32);
    }
    // No case matched: go to `default` (if any), else exit the switch.
    var fallbackLevel = defaultIndex != null
        ? entryLevel(defaultIndex)
        : exitLevel;
    out.write(
      Wasm.br(context.controlDepth - fallbackLevel),
      description: "[OP] switch dispatch fallback",
    );

    out.writeByte(Wasm.end, description: "[OP] block end (switch dispatch)");
    context.controlDepth--;

    // Case bodies, emitted as the case blocks close (so they fall through).
    context.pushSwitchFrame(breakLevel: exitLevel);
    for (var i = 0; i < n; ++i) {
      generateASTBlock(cases[i].block, out: out, context: context);
      if (!statement.fallThrough) {
        // Non-fall-through (`when`/`match`): jump to exit after the matched case.
        out.write(
          Wasm.br(context.controlDepth - exitLevel),
          description: "[OP] switch case $i exit (no fall-through)",
        );
      }
      out.writeByte(Wasm.end, description: "[OP] block end (switch case $i)");
      context.controlDepth--;
    }
    context.popLoopFrame();

    out.writeByte(Wasm.end, description: "[OP] block end (switch)");
    context.controlDepth--;

    return out;
  }

  @override
  BytesOutput generateASTStatementWhileLoop(
    ASTStatementWhileLoop whileLoop, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    _generateLoop(
      out: out,
      context: context,
      conditionExpression: whileLoop.conditionExpression,
      loopBlock: whileLoop.loopBlock,
      continueExpression: null,
      description: "while",
    );

    return out;
  }

  /// Generates the `block`/`loop` structure shared by `while` and `for` loops.
  ///
  /// Structure emitted (void block types):
  /// ```
  /// block (void)
  ///   loop (void)
  ///     <cond>       ; pushes i32
  ///     i32.eqz      ; !cond
  ///     br_if 1      ; break out to block
  ///     <body>
  ///     <continue>   ; (for-loops only)
  ///     br 0         ; jump back to loop
  ///   end
  /// end
  /// ```
  void _generateLoop({
    required BytesOutput out,
    required WasmContext context,
    required ASTExpression conditionExpression,
    required ASTBlock loopBlock,
    required ASTExpression? continueExpression,
    required String description,
    bool conditionAfterBody = false,
  }) {
    // Structure (void blocks); the inner `block` is the `continue` target so
    // `continue` still runs the post-step (increment / do-while condition):
    //   block (break)
    //     loop (repeat)
    //       [pre-cond: eqz; br_if break]        ; while / for
    //       block (continue) <body> end
    //       [continueExpression]                ; for
    //       [post-cond: br_if repeat] | br repeat
    //     end
    //   end
    out.write(
      Wasm.block(WasmType.voidType),
      description: "[OP] block ($description break)",
    );
    context.controlDepth++;
    final breakLevel = context.controlDepth;

    out.write(
      Wasm.loop(WasmType.voidType),
      description: "[OP] loop ($description repeat)",
    );
    context.controlDepth++;
    final repeatLevel = context.controlDepth;

    void writeCondition() {
      final stackLng0 = context.stackLength;
      generateASTExpression(conditionExpression, out: out, context: context);
      context.assertStackLength(
        stackLng0 + 1,
        "After $description loop condition",
      );
      var stackType = context.stackGet(0)!.type;
      if (stackType != _astTypeInt32) {
        throw StateError("Stack type error> not a boolean type: $stackType");
      }
    }

    // Pre-condition (while / for): break out of the loop when false.
    if (!conditionAfterBody) {
      writeCondition();
      out.writeByte(
        Wasm32.i32EqualsToZero,
        description: "[OP] i32.eqz ( !($conditionExpression) )",
      );
      out.write(
        Wasm.brIf(context.controlDepth - breakLevel),
        description: "[OP] br_if ($description break)",
      );
      context.stackDrop(_astTypeInt32);
    }

    // `continue` target wrapping the body.
    out.write(
      Wasm.block(WasmType.voidType),
      description: "[OP] block ($description continue)",
    );
    context.controlDepth++;
    final continueLevel = context.controlDepth;

    context.pushLoopFrame(breakLevel: breakLevel, continueLevel: continueLevel);
    generateASTBlock(loopBlock, out: out, context: context);
    context.popLoopFrame();

    out.writeByte(
      Wasm.end,
      description: "[OP] block end ($description continue)",
    );
    context.controlDepth--;

    // Continue expression (for-loops only), e.g. `i++`:
    if (continueExpression != null) {
      generateASTExpression(continueExpression, out: out, context: context);
    }

    if (conditionAfterBody) {
      // do-while: repeat while the condition is true.
      writeCondition();
      out.write(
        Wasm.brIf(context.controlDepth - repeatLevel),
        description: "[OP] br_if ($description repeat)",
      );
      context.stackDrop(_astTypeInt32);
    } else {
      // Jump back to the top of the `loop`. Any leaked operand-stack values are
      // unwound by this branch (loop is void).
      out.write(
        Wasm.br(context.controlDepth - repeatLevel),
        description: "[OP] br ($description repeat)",
      );
    }

    out.writeByte(Wasm.end, description: "[OP] loop end ($description)");
    context.controlDepth--;
    out.writeByte(Wasm.end, description: "[OP] block end ($description)");
    context.controlDepth--;
  }

  @override
  BytesOutput generateASTStatementBlock(
    ASTStatementBlock statement, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    return generateASTBlock(statement.block, out: out, context: context);
  }

  @override
  BytesOutput generateASTStatementReturn(
    ASTStatementReturn statement, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    var stack0 = context.stackGet(0);

    if (stack0 != null && stack0.type is! ASTTypeVoid) {
      throw StateError("Returning with pushed element in stack: $stack0");
    }

    out.writeByte(Wasm.functionReturn, description: "[OP] return");

    return out;
  }

  @override
  BytesOutput generateASTStatementReturnNull(
    ASTStatementReturnNull statement, {
    BytesOutput? out,
  }) {
    // TODO: implement generateASTStatementReturnNull
    throw UnimplementedError('generateASTStatementReturnNull');
  }

  @override
  BytesOutput generateASTStatementReturnValue(
    ASTStatementReturnValue statement, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    var value = statement.value;

    var stackLength0 = context.stackLength;

    generateASTValue(value, out: out, context: context);

    context.assertStackLength(stackLength0 + 1, "Return value: $value");

    var stack0Type = context.stackGet(0)!.type;
    var returnType = context.returnsGet(0)!.type;

    _autoConvertStackTypes(stack0Type, returnType, out: out, context: context);

    out.writeByte(
      Wasm.functionReturn,
      description: "[OP] return value: $value",
    );
    context.stackDrop();

    return out;
  }

  @override
  BytesOutput generateASTStatementReturnVariable(
    ASTStatementReturnVariable statement, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    var variable = statement.variable;
    var name = variable.name;

    var stackLength0 = context.stackLength;

    if (context.isCapturedVariable(name) || context.isBoxedVariable(name)) {
      // Captured/boxed variable: dereference the shared heap cell.
      var type = _emitBoxPointer(out, context, name);
      _emitElemLoad(out, type, 0);
      context.stackPush(_elemStackType(type), 'boxed `$name` (return)');
    } else if (context.isFieldAccess(name)) {
      _generateFieldGet(out, context, name);
    } else if (_staticFieldKey(context, name) != null) {
      var key = _staticFieldKey(context, name)!;
      var type = context.module!.staticFieldTypeOf(key)!;
      out.write(
        Wasm.globalGet(context.module!.staticFieldGlobalIndexOf(key)!),
        description: "[OP] static field get `$key` (return)",
      );
      context.stackPush(
        _wasmStackTypeFor(type),
        'static field `$name` (return)',
      );
    } else {
      var localVar = _getLocalVariable(context, name);
      _localVariableGet(out, context, localVar.index, name, '(return)');
      var pushType = localVar.type is ASTTypeBool
          ? _astTypeInt32
          : localVar.type;
      context.stackPush(
        pushType,
        'Local get: ${localVar.index} \$$name (return)',
      );
    }

    context.assertStackLength(stackLength0 + 1, "Return variable: $name");

    var stack0Type = context.stackGet(0)!.type;
    var returnType = context.returnsGet(0)!.type;

    _autoConvertStackTypes(stack0Type, returnType, out: out, context: context);

    out.writeByte(
      Wasm.functionReturn,
      description: "[OP] return variable: \$$name",
    );
    context.stackDrop();

    return out;
  }

  @override
  BytesOutput generateASTStatementReturnWithExpression(
    ASTStatementReturnWithExpression statement, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    final stackLng0 = context.stackLength;

    var expression = statement.expression;

    generateASTExpression(expression, out: out, context: context);

    context.assertStackLength(stackLng0 + 1, "After expression (return)");

    var stack0Type = context.stackGet(0)!.type;
    var returnType = context.returnsGet(0)!.type;

    _autoConvertStackTypes(stack0Type, returnType, out: out, context: context);

    out.writeByte(
      Wasm.functionReturn,
      description: "[OP] return expression: $expression",
    );
    context.stackDrop();

    return out;
  }

  BytesOutput _autoConvertStackTypes(
    ASTType stackType,
    ASTType targetType, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    if (stackType == targetType) return out;

    // A boxed `Object`/`dynamic` value flowing into a concrete numeric target
    // (e.g. a dynamic argument passed to a typed `int` closure/function
    // parameter) is unboxed via the runtime box tag.
    if (_isObjectType(stackType) && targetType is ASTTypeNum) {
      _emitUnboxNumberInto(
        out,
        context,
        targetType is ASTTypeDouble ? _astTypeDouble64 : _astTypeInt64,
      );
      return out;
    }

    // A boxed `Object` flowing into a concrete non-numeric i32 target — a generic
    // `T` field (`Box<String>`, `Box<bool>`) read back at its instantiation type.
    // The box payload holds the i32 value (String pointer, or a bool 0/1), so
    // extract it. (A generic instance field — `Box<SomeClass>` — is a follow-up:
    // the read result types as `dynamic`, so further member access isn't wired.)
    if (_isObjectType(stackType) &&
        (targetType is ASTTypeString || targetType is ASTTypeBool)) {
      out.write(
        Wasm32.i32Load(2, _boxPayloadOffset),
        description: "[OP] unbox Object payload (i32)",
      );
      return out;
    }

    // A concrete value flowing into an `Object`/`dynamic` target (e.g. an `int`
    // argument passed to a generic `T` field/parameter, which is represented as
    // a boxed `Object`) is boxed.
    if (_isObjectType(targetType) && !_isObjectType(stackType)) {
      _emitBoxValue(out, context);
      return out;
    }

    if (stackType is ASTTypeNum) {
      final stackType32 = stackType.isBits32;
      final stackType64 = stackType.isBits64;

      if (targetType is ASTTypeNum) {
        final targetType32 = targetType.isBits32;
        final targetType64 = targetType.isBits64;

        if (stackType is ASTTypeInt) {
          if (targetType is ASTTypeInt) {
            if (stackType32 && targetType64) {
              out.writeByte(
                Wasm32.i32ExtendToI64Signed,
                description: "i32ExtendToI64Signed",
              );
            } else if (stackType64 && targetType32) {
              out.writeByte(Wasm64.i64WrapToi32, description: "i64WrapToi32");
            }
          } else if (targetType is ASTTypeDouble) {
            if (stackType32 && targetType32) {
              out.writeByte(
                Wasm32.i32ConvertToF32Signed,
                description: "i32ConvertToF32Signed",
              );
            } else if (stackType32 && targetType64) {
              out.writeByte(
                Wasm32.i32ConvertToF64Signed,
                description: "i32ConvertToF64Signed",
              );
            } else if (stackType64 && targetType32) {
              out.writeByte(
                Wasm64.i64ConvertToF32Signed,
                description: "i64ConvertToF32Signed",
              );
            } else if (stackType64 && targetType64) {
              out.writeByte(
                Wasm64.i64ConvertToF64Signed,
                description: "i64ConvertToF64Signed",
              );
            }
          }
        } else if (stackType is ASTTypeDouble) {
          if (targetType is ASTTypeInt) {
            if (stackType32 && targetType32) {
              out.writeByte(
                Wasm32.f32TruncateToI32Signed,
                description: "f32TruncateToI32Signed",
              );
            } else if (stackType32 && targetType64) {
              out.writeByte(
                Wasm32.f32TruncateToI64Signed,
                description: "f32TruncateToI64Signed",
              );
            } else if (stackType64 && targetType32) {
              out.writeByte(
                Wasm64.f64TruncateToI32Signed,
                description: "f64TruncateToI32Signed",
              );
            } else if (stackType64 && targetType64) {
              out.writeByte(
                Wasm64.f64TruncateToI64Signed,
                description: "f64TruncateToI64Signed",
              );
            }
          }
        }
      }
    }

    return out;
  }

  @override
  BytesOutput generateASTStatementVariableDeclaration(
    ASTStatementVariableDeclaration statement, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    var value = statement.value;
    if (value == null) {
      return out;
    }

    // `null` exists only in the boxed-`Object` domain (see
    // [generateASTExpressionNullValue]). A slot with a concrete Wasm
    // representation — `int` as i64, `double` as f64, `String` as a string
    // pointer — has no encoding for it, so refuse the declaration explicitly
    // rather than emit a module that fails to validate.
    if (value is ASTExpressionNullValue && !_acceptsWasmNull(statement.type)) {
      throw UnsupportedSyntaxError(
        "Wasm has no null value for `${statement.type}`: can't compile "
        "`${statement.type} ${statement.name} = null`. Wasm represents `null` "
        "only in the boxed-`Object` domain, so declare the variable as `var` / "
        "`Object?` / `dynamic`, or give it a non-null initial value.",
      );
    }

    var name = statement.name;

    // A capture-free closure assigned to a call-only `var` carries no function
    // value: elide the declaration entirely (no env allocation, no store). The
    // matching `name(x)` calls are lowered to a direct `call`.
    if (context.directClosureVars.containsKey(name) &&
        value is ASTExpressionLiteralFunction) {
      return out;
    }

    final ASTExpression initValue = value;
    final BytesOutput initOut = out;
    final WasmContext initContext = context;
    // Emits the initializer, boxing a homogeneous list literal when it is
    // declared as a `List<Object>`/`List<dynamic>` (the declared type is read
    // back as boxed i32 elements, so the literal must store boxes too).
    void emitInitializer() {
      var declType = statement.type;
      if (initValue is ASTExpressionListLiteral &&
          declType is ASTTypeArray &&
          _isObjectType(declType.componentType)) {
        generateASTExpressionListLiteral(
          initValue,
          out: initOut,
          context: initContext,
          elementTypeOverride: ASTTypeObject.instance,
        );
      } else {
        generateASTExpression(initValue, out: initOut, context: initContext);
      }
    }

    // A boxed (captured-by-reference) local: allocate its heap cell, then store
    // the initializer into it (leaving the value on the stack as the result).
    if (context.isBoxedVariable(name)) {
      final s0 = context.stackLength;
      var b = context.boxedVariables[name]!;
      out.write(Wasm32.i32Const(_elemSize(b.type)));
      _emitInlineAlloc(out, context);
      out.write(Wasm.localSet(b.boxLocal));

      out.write(Wasm.localGet(b.boxLocal));
      emitInitializer();
      var valLocal = context.scratchLocal(_wasmLocalType(b.type), 47);
      out.write(Wasm.localTee(valLocal));
      _emitElemStore(out, b.type, 0);
      out.write(Wasm.localGet(valLocal));

      context.assertStackLength(s0 + 1, "After boxed var decl `$name`");
      return out;
    }

    var localVar = _getLocalVariable(context, name);

    final stackLng0 = context.stackLength;

    emitInitializer();

    final stackLng1 = context.assertStackLength(
      stackLng0 + 1,
      "After variable declaration expression",
    );

    // A `var` that the AST couldn't statically resolve (e.g. `var p = Point()`)
    // is registered as `dynamic`; refine it to the initializer's real type so
    // method/field access and the local's Wasm type are correct.
    //
    // A closure assigned to a `var` (`var twice = (int n) => n * 2`) is declared
    // `var`/`dynamic` with an untyped `Function` literal; adopt the closure's
    // concrete function type (signature generics) so a later `twice(x)` call
    // dispatches via `call_indirect` with the matching type.
    var initType = context.stackGet(0)!.type;
    if (_isObjectType(localVar.type) && !_isObjectType(initType)) {
      // A `var`/`Object`/`dynamic` local whose initializer has a concrete type:
      // refine to it so method/field access and the local's Wasm width are
      // correct — `var p = Point()` (i32 instance) or `var s = a + b` where
      // `a`/`b` are boxed `Object`s and the sum is an i64. A genuinely boxed
      // initializer (e.g. `var a = args[0]`) stays `Object`.
      context.updateLocalVariableType(name, initType);
    } else if (initType is ASTTypeFunction &&
        (initType.generics?.isNotEmpty ?? false)) {
      // The initializer is a closure with a concrete signature; adopt it even
      // if the local was registered as a bare `Function` (the parser resolves a
      // `var f = (…) => …` to untyped `Function`), so `f(x)` dispatches via
      // `call_indirect` with the matching type.
      context.updateLocalVariableType(name, initType);
    }

    _localVariableSet(out, context, localVar.index, name);

    context.assertStackLength(
      stackLng1,
      "After variable set: ${localVar.index} \$$name",
    );
    context.assertStackLength(
      stackLng0 + 1,
      "After variable declaration:  ${localVar.index} \$$name",
    );

    return out;
  }

  @override
  BytesOutput generateASTStatementFunctionDeclaration(
    ASTStatementFunctionDeclaration statement, {
    BytesOutput? out,
  }) {
    // A named nested function (e.g. JS/TS `let twice = (n) => …`) is collected
    // and generated as a module function by [_collectAnonymousClosures]; the
    // declaration statement itself emits nothing. A call `twice(x)` resolves to
    // a direct `call` (capture-free, call-only) or fails to resolve at the call
    // site if it is used in an unsupported way (captured/escaping).
    return out ?? newOutput();
  }

  @override
  BytesOutput generateASTExpression(
    ASTExpression expression, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    if (expression is ASTExpressionNullValue) {
      return generateASTExpressionNullValue(
        expression,
        out: out,
        context: context,
      );
    }
    if (expression is ASTExpressionNullCoalesce) {
      return generateASTExpressionNullCoalesce(
        expression,
        out: out,
        context: context,
      );
    }
    if (expression is ASTExpressionNullCheck) {
      return generateASTExpressionNullCheck(
        expression,
        out: out,
        context: context,
      );
    }
    if (expression is ASTExpressionLogical) {
      return generateASTExpressionLogical(
        expression,
        out: out,
        context: context,
      );
    }
    if (expression is ASTExpressionVariableAccess) {
      return generateASTExpressionVariableAccess(
        expression,
        out: out,
        context: context,
      );
    } else if (expression is ASTExpressionVariableAssignment) {
      return generateASTExpressionVariableAssignment(
        expression,
        out: out,
        context: context,
      );
    } else if (expression is ASTExpressionVariableDirectOperation) {
      return generateASTExpressionVariableDirectOperation(
        expression,
        out: out,
        context: context,
      );
    } else if (expression is ASTExpressionVariableEntryAccess) {
      return generateASTExpressionVariableEntryAccess(
        expression,
        out: out,
        context: context,
      );
    } else if (expression is ASTExpressionObjectGetterAccess) {
      return _generateWasmGetterAccess(expression, out: out, context: context);
    } else if (expression is ASTExpressionLiteral) {
      return generateASTExpressionLiteral(
        expression,
        out: out,
        context: context,
      );
    } else if (expression is ASTExpressionListLiteral) {
      return generateASTExpressionListLiteral(
        expression,
        out: out,
        context: context,
      );
    } else if (expression is ASTExpressionMapLiteral) {
      return generateASTExpressionMapLiteral(
        expression,
        out: out,
        context: context,
      );
    } else if (expression is ASTExpressionVariableEntryAssignment) {
      return _generateWasmEntryAssignment(
        expression,
        out: out,
        context: context,
      );
    } else if (expression is ASTExpressionNegation) {
      return generateASTExpressionNegation(
        expression,
        out: out,
        context: context,
      );
    } else if (expression is ASTExpressionNegative) {
      return generateASTExpressionNegative(
        expression,
        out: out,
        context: context,
      );
    } else if (expression is ASTExpressionBitwiseNot) {
      return generateASTExpressionBitwiseNot(
        expression,
        out: out,
        context: context,
      );
    } else if (expression is ASTExpressionAwait) {
      return generateASTExpressionAwait(expression, out: out, context: context);
    } else if (expression is ASTExpressionLocalFunctionInvocation) {
      return generateASTExpressionLocalFunctionInvocation(
        expression,
        out: out,
        context: context,
      );
    } else if (expression is ASTExpressionObjectFunctionInvocation) {
      return generateASTExpressionFunctionInvocation(
        expression,
        out: out,
        context: context,
      );
    } else if (expression is ASTExpressionGroupFunctionInvocation) {
      return generateASTExpressionGroupFunctionInvocation(expression, out: out);
    } else if (expression is ASTExpressionObjectSetterAssignment) {
      return _generateObjectSetterAssignment(
        expression,
        out: out,
        context: context,
      );
    } else if (expression is ASTExpressionOperation) {
      return generateASTExpressionOperation(
        expression,
        out: out,
        context: context,
      );
    } else if (expression is ASTExpressionConditional) {
      return generateASTExpressionConditional(
        expression,
        out: out,
        context: context,
      );
    } else if (expression is ASTExpressionLiteralFunction) {
      return generateASTExpressionLiteralFunction(
        expression,
        out: out,
        context: context,
      );
    } else if (expression is ASTExpressionNullAssertion) {
      // Wasm's numeric domain has no `null`, so a null-assertion (`x!`) can
      // never fail here — compile it as the inner expression.
      return generateASTExpression(
        expression.expression,
        out: out,
        context: context,
      );
    }

    throw UnsupportedError("Can't generate expression: $expression");
  }

  /// Lowers `obj.field = value` (and `this.field = value`), including compound
  /// operators, to a store at `recv + offset`.
  BytesOutput _generateObjectSetterAssignment(
    ASTExpressionObjectSetterAssignment expression, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    var recvName = expression.variable.name;
    var recvVar = _getLocalVariable(context, recvName);
    var layout = context.module?.layoutForType(recvVar.type);
    if (layout == null || !layout.offsets.containsKey(expression.name)) {
      throw UnimplementedError(
        "Wasm field assignment `${recvVar.type}.${expression.name}` "
        "is not supported.",
      );
    }
    var offset = layout.offsets[expression.name]!;
    var fieldType = layout.types[expression.name]!;

    final s0 = context.stackLength;

    // Receiver pointer (the store address) on the real stack only — the value
    // sub-expression's relative assertions hold, and the value's virtual entry
    // remains (matching the local assignment-expression contract).
    _localVariableGet(out, context, recvVar.index, recvName);

    if (expression.operator == ASTAssignmentOperator.set) {
      generateASTExpression(expression.expression, out: out, context: context);
    } else {
      var expOp = expression.operator.asASTExpressionOperator!;
      generateASTExpressionOperation(
        ASTExpressionOperation(
          ASTExpressionObjectGetterAccess(expression.variable, expression.name),
          expOp,
          expression.expression,
        ),
        out: out,
        context: context,
      );
    }

    _autoConvertStackTypes(
      context.stackGet(0)!.type,
      fieldType,
      out: out,
      context: context,
    );
    _emitElemStore(out, fieldType, offset);
    context.assertStackLength(s0 + 1, "After object field set");
    return out;
  }

  @override
  BytesOutput generateASTTypeArray(
    ASTTypeArray<ASTType, dynamic> type, {
    BytesOutput? out,
  }) {
    // TODO: implement generateASTTypeArray
    throw UnimplementedError('generateASTTypeArray');
  }

  @override
  BytesOutput generateASTTypeArray2D(
    ASTTypeArray2D<ASTType, dynamic> type, {
    BytesOutput? out,
  }) {
    // TODO: implement generateASTTypeArray2D
    throw UnimplementedError('generateASTTypeArray2D');
  }

  @override
  BytesOutput generateASTTypeArray3D(
    ASTTypeArray3D<ASTType, dynamic> type, {
    BytesOutput? out,
  }) {
    // TODO: implement generateASTTypeArray3D
    throw UnimplementedError('generateASTTypeArray3D');
  }

  @override
  BytesOutput generateASTTypeDefault(ASTType type, {BytesOutput? out}) {
    // TODO: implement generateASTTypeDefault
    throw UnimplementedError('generateASTTypeDefault');
  }

  @override
  BytesOutput generateASTValue(
    ASTValue value, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    if (value is ASTValueString) {
      return generateASTValueString(value, out: out, context: context);
    } else if (value is ASTValueInt) {
      return generateASTValueInt(value, out: out, context: context);
    } else if (value is ASTValueDouble) {
      return generateASTValueDouble(value, out: out, context: context);
    } else if (value is ASTValueBool) {
      return generateASTValueBool(value, out: out, context: context);
    } else if (value is ASTValueNull) {
      return generateASTValueNull(value, out: out);
    } else if (value is ASTValueVar) {
      return generateASTValueVar(value, out: out);
    } else if (value is ASTValueObject) {
      return generateASTValueObject(value, out: out);
    } else if (value is ASTValueStatic) {
      return generateASTValueStatic(value, out: out);
    } else if (value is ASTValueStringVariable) {
      return generateASTValueStringVariable(value, out: out, context: context);
    } else if (value is ASTValueStringConcatenation) {
      return generateASTValueStringConcatenation(
        value,
        out: out,
        context: context,
      );
    } else if (value is ASTValueStringExpression) {
      return generateASTValueStringExpression(
        value,
        out: out,
        context: context,
      );
    } else if (value is ASTValueArray) {
      return generateASTValueArray(value, out: out);
    } else if (value is ASTValueArray2D) {
      return generateASTValueArray2D(value, out: out);
    } else if (value is ASTValueArray3D) {
      return generateASTValueArray3D(value, out: out);
    }

    throw UnsupportedError("Can't generate value: $value");
  }

  @override
  BytesOutput generateASTValueArray(
    ASTValueArray<ASTType, dynamic> value, {
    BytesOutput? out,
  }) {
    // TODO: implement generateASTValueArray
    throw UnimplementedError('generateASTValueArray');
  }

  @override
  BytesOutput generateASTValueArray2D(
    ASTValueArray2D<ASTType, dynamic> value, {
    BytesOutput? out,
  }) {
    // TODO: implement generateASTValueArray2D
    throw UnimplementedError('generateASTValueArray2D');
  }

  @override
  BytesOutput generateASTValueArray3D(
    ASTValueArray3D<ASTType, dynamic> value, {
    BytesOutput? out,
  }) {
    // TODO: implement generateASTValueArray3D
    throw UnimplementedError('generateASTValueArray3D');
  }

  @override
  BytesOutput generateASTValueDouble(
    ASTValueDouble value, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    var v = value.value;

    out.write(Wasm64.f64Const(v), description: "[OP] push constant(f64): $v");
    context.stackPush(_astTypeDouble64, "double literal: $v");

    return out;
  }

  @override
  BytesOutput generateASTValueInt(
    ASTValueInt value, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    var v = value.value;

    out.write(Wasm64.i64Const(v), description: "[OP] push constant(i64): $v");
    context.stackPush(_astTypeInt64, "int literal: $v");

    return out;
  }

  BytesOutput generateASTValueBool(
    ASTValueBool value, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    var v = value.value;

    out.write(
      Wasm32.i32Const(v ? 1 : 0),
      description: "[OP] push constant(bool/i32): $v",
    );
    context.stackPush(_astTypeInt32, "bool literal: $v");

    return out;
  }

  @override
  BytesOutput generateASTValueNull(ASTValueNull value, {BytesOutput? out}) {
    // TODO: implement generateASTValueNull
    throw UnimplementedError('generateASTValueNull');
  }

  @override
  BytesOutput generateASTValueObject(ASTValueObject value, {BytesOutput? out}) {
    // TODO: implement generateASTValueObject
    throw UnimplementedError('generateASTValueObject');
  }

  @override
  BytesOutput generateASTValueStatic(ASTValueStatic value, {BytesOutput? out}) {
    // TODO: implement generateASTValueStatic
    throw UnimplementedError('generateASTValueStatic');
  }

  @override
  BytesOutput generateASTValueString(
    ASTValueString value, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    var module = context.module;
    if (module == null) {
      throw StateError("Can't generate a string literal without a module.");
    }

    // Intern the literal into the static data region; its value is the i32
    // pointer to `[len:i32][utf8]`.
    var ptr = module.internStringLiteral(value.value);

    out.write(
      Wasm32.i32Const(ptr),
      description: "[OP] push string literal ptr($ptr): ${value.value}",
    );
    context.stackPush(_astTypeString, "string literal: ${value.value}");

    return out;
  }

  @override
  BytesOutput generateASTValueStringConcatenation(
    ASTValueStringConcatenation value, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    var values = value.values;
    if (values.isEmpty) {
      return generateASTValueString(
        ASTValueString(''),
        out: out,
        context: context,
      );
    }

    // Fold left: concat(concat(e0, e1), e2)...
    generateASTValue(values.first, out: out, context: context);
    for (var i = 1; i < values.length; ++i) {
      generateASTValue(values[i], out: out, context: context);
      _emitStringConcat2(out, context);
    }

    return out;
  }

  @override
  BytesOutput generateASTValueStringExpression(
    ASTValueStringExpression value, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    generateASTExpression(value.expression, out: out, context: context);

    _emitToStringHandle(out, context, context.stackGet(0)!.type);

    return out;
  }

  @override
  BytesOutput generateASTValueStringVariable(
    ASTValueStringVariable value, {
    BytesOutput? out,
    bool precededByString = false,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    var name = value.variable.name;

    // A field interpolated inside a method (`'$x'`) loads `this + offset`.
    if (context.isFieldAccess(name)) {
      _generateFieldGet(out, context, name);
      _emitToStringHandle(out, context, context.stackGet(0)!.type);
      return out;
    }

    var localVar = _getLocalVariable(context, name);
    var t = localVar.type;

    _localVariableGet(out, context, localVar.index, name);

    // Booleans live as i32 on the stack; push the storage type, then coerce.
    var pushType = t is ASTTypeBool ? _astTypeInt32 : t;
    context.stackPush(pushType, "interp var: \$$name");
    _emitToStringHandle(out, context, pushType);

    return out;
  }

  /// Converts the number on the top of the stack (i64 for int, f64 for double)
  /// to a string handle via a host import (`env.int_to_str` / `double_to_str`).
  void _emitNumberToString(
    BytesOutput out,
    WasmContext context,
    ASTType numType,
  ) {
    var module = context.module;
    if (module == null) {
      throw StateError("Can't convert a number to String without a module.");
    }
    module.requiresMemory = true;
    module.ensureAllocFunction();

    int importIndex;
    if (numType is ASTTypeInt) {
      importIndex = module.registerImportedFunction(
        'env',
        'int_to_str',
        const [WasmType.i64Type],
        const [WasmType.i32Type],
      );
    } else if (numType is ASTTypeDouble) {
      importIndex = module.registerImportedFunction(
        'env',
        'double_to_str',
        const [WasmType.f64Type],
        const [WasmType.i32Type],
      );
    } else {
      throw UnimplementedError(
        "Wasm number-to-string for $numType is not supported yet.",
      );
    }

    out.write(
      Wasm.call(importIndex),
      description: "[OP] call host number-to-string (index $importIndex)",
    );
    context.stackDrop();
    context.stackPush(_astTypeString, "number to string");
  }

  /// Coerces the value currently on top of the stack to an i32 string handle,
  /// ready for `env.print` or string concatenation. Strings already are handles;
  /// `int`/`double` route through [_emitNumberToString] and `bool` through
  /// [_emitBoolToString]. A bare i32 stack value is a `bool` (booleans, logic and
  /// comparison results are all represented as i32 in this generator).
  void _emitToStringHandle(BytesOutput out, WasmContext context, ASTType type) {
    if (type is ASTTypeString) {
      // Already a string handle.
    } else if (type is ASTTypeBool || identical(type, _astTypeInt32)) {
      // Booleans (and comparison/logic results) are the only values pushed as
      // the i32 singleton; checked before `ASTTypeInt` since `instance32` *is*
      // an `ASTTypeInt`. Real `int`s are pushed as i64 (`instance64`).
      _emitBoolToString(out, context);
    } else if (type is ASTTypeInt || type is ASTTypeDouble) {
      _emitNumberToString(out, context, type);
    } else if (type is ASTTypeNum) {
      // A plain `num` (TS/JS `number`) is represented as i64 (int) in Wasm.
      _emitNumberToString(out, context, _astTypeInt);
    } else if (_isObjectType(type)) {
      _emitBoxToString(out, context);
    } else if (type is ASTTypeMap) {
      _emitMapToString(out, context, type);
    } else if (type is ASTTypeArray) {
      _emitListToString(out, context, type);
    } else if (_isWasmObjectRef(type)) {
      _emitInstanceToString(out, context, type);
    } else {
      throw UnimplementedError(
        "Wasm string coercion of type $type is not supported yet.",
      );
    }
  }

  /// Converts the class instance pointer on top of the stack to an i32 string
  /// handle by calling its `toString()` method (which returns a string handle).
  void _emitInstanceToString(
    BytesOutput out,
    WasmContext context,
    ASTType type,
  ) {
    var module = context.module;
    var className = type.name;
    var calleeIndex = module?.methodIndex(className, 'toString', 0);
    if (calleeIndex == null) {
      throw UnimplementedError(
        "Wasm `print`/interpolation of a `$className` needs a `toString()` "
        "method.",
      );
    }
    // The receiver is already on the stack; `toString()` consumes it and
    // returns the string handle.
    out.write(
      Wasm.call(calleeIndex),
      description: "[OP] call `$className.toString` (index $calleeIndex)",
    );
    context.stackDrop();
    context.stackPush(_astTypeString, "$className.toString() result");
  }

  /// Appends, at runtime, the string handle produced by [emitPiece] onto the
  /// accumulator string in local [accLocal]: `acc = concat(acc, piece)`.
  /// [emitPiece] must leave exactly one i32 string handle on the stack (and
  /// push it on the virtual stack), e.g. an interned literal or an element
  /// coerced via [_emitToStringHandle]. Net virtual-stack effect: zero.
  void _emitConcatInto(
    BytesOutput out,
    WasmContext context,
    int accLocal,
    void Function() emitPiece,
  ) {
    out.write(Wasm.localGet(accLocal));
    context.stackPush(_astTypeString, "collection toString acc");
    emitPiece();
    _emitStringConcat2(out, context);
    out.write(Wasm.localSet(accLocal));
    context.stackDrop();
  }

  /// Loads element `i` (counter in [iLocal]) from the buffer based at
  /// [basePtrLocal] with stride [size] and coerces it to a string handle.
  /// Nested collections are rejected: they would re-enter [_emitMapToString]/
  /// [_emitListToString] and clobber the shared scratch locals.
  void _emitCollectionElement(
    BytesOutput out,
    WasmContext context,
    ASTType elemType,
    int basePtrLocal,
    int iLocal,
    int size,
  ) {
    if (elemType is ASTTypeMap || elemType is ASTTypeArray) {
      throw UnimplementedError(
        "Wasm string coercion of a nested collection ($elemType) inside a "
        "Map/List is not supported yet.",
      );
    }
    // addr = base + i*size
    out.write(Wasm.localGet(basePtrLocal));
    out.write(Wasm.localGet(iLocal));
    out.write(Wasm32.i32Const(size));
    out.writeByte(Wasm32.i32Multiply);
    out.writeByte(Wasm32.i32Add);
    _emitElemLoad(out, elemType, 0);
    context.stackPush(_elemStackType(elemType), "collection element");
    _emitToStringHandle(out, context, elemType);
  }

  /// Pushes an interned string literal as an i32 handle (and tracks it on the
  /// virtual stack).
  void _emitStringLiteralHandle(
    BytesOutput out,
    WasmContext context,
    String s,
  ) {
    out.write(Wasm32.i32Const(context.module!.internStringLiteral(s)));
    context.stackPush(_astTypeString, "collection toString literal '$s'");
  }

  /// Converts the `Map` header pointer on top of the stack to an i32 string
  /// handle in Dart's `{k0: v0, k1: v1}` form. Scans the parallel key/value
  /// buffers (`[len@0][cap@4][keysPtr@8][valuesPtr@12]`) at runtime, coercing
  /// each key and value through [_emitToStringHandle] and joining with `, `.
  void _emitMapToString(BytesOutput out, WasmContext context, ASTTypeMap type) {
    var module = context.module;
    if (module == null) {
      throw StateError("Can't convert a Map to String without a module.");
    }
    module.requiresMemory = true;
    module.requiresHeapGlobal = true;

    var keyType = type.keyType;
    var valueType = type.valueType;
    var keySize = _mapKeySize(keyType);
    var valSize = _elemSize(valueType);

    // i32 scratch locals (slots 50+ avoid the string-concat slots 0..2 reused
    // by `_emitStringConcat2` on every entry).
    var hdr = context.scratchLocal(_astTypeString, 50);
    var keysPtr = context.scratchLocal(_astTypeString, 51);
    var valsPtr = context.scratchLocal(_astTypeString, 52);
    var iLoc = context.scratchLocal(_astTypeString, 53);
    var lenLoc = context.scratchLocal(_astTypeString, 54);
    var acc = context.scratchLocal(_astTypeString, 55);

    // Consume the Map header pointer (top of stack) into `hdr`.
    out.write(
      Wasm.localSet(hdr),
      description: "[OP] Map -> String: stash header",
    );
    context.stackDrop();

    // acc = "{"
    _emitStringLiteralHandle(out, context, '{');
    out.write(Wasm.localSet(acc));
    context.stackDrop();

    // len = hdr[0] ; keysPtr = hdr[8] ; valsPtr = hdr[12] ; i = 0
    out.write(Wasm.localGet(hdr));
    out.write(Wasm32.i32Load(2, 0));
    out.write(Wasm.localSet(lenLoc));
    out.write(Wasm.localGet(hdr));
    out.write(Wasm32.i32Load(2, 8));
    out.write(Wasm.localSet(keysPtr));
    out.write(Wasm.localGet(hdr));
    out.write(Wasm32.i32Load(2, 12));
    out.write(Wasm.localSet(valsPtr));
    out.write(Wasm32.i32Const(0));
    out.write(Wasm.localSet(iLoc));

    out.write(Wasm.block(WasmType.voidType));
    out.write(Wasm.loop(WasmType.voidType));

    // if (i >= len) break the block
    out.write(Wasm.localGet(iLoc));
    out.write(Wasm.localGet(lenLoc));
    out.writeByte(Wasm32.i32GreaterThanOrEqualsUnsigned);
    out.write(Wasm.brIf(1));

    // if (i > 0) acc += ", "  (i is non-negative, so `i` itself is the test)
    out.write(Wasm.localGet(iLoc));
    out.write(Wasm.ifInstruction(WasmType.voidType));
    _emitConcatInto(
      out,
      context,
      acc,
      () => _emitStringLiteralHandle(out, context, ', '),
    );
    out.writeByte(Wasm.end);

    // acc += key ; acc += ": " ; acc += value
    _emitConcatInto(
      out,
      context,
      acc,
      () =>
          _emitCollectionElement(out, context, keyType, keysPtr, iLoc, keySize),
    );
    _emitConcatInto(
      out,
      context,
      acc,
      () => _emitStringLiteralHandle(out, context, ': '),
    );
    _emitConcatInto(
      out,
      context,
      acc,
      () => _emitCollectionElement(
        out,
        context,
        valueType,
        valsPtr,
        iLoc,
        valSize,
      ),
    );

    // i++ ; continue
    out.write(Wasm.localGet(iLoc));
    out.write(Wasm32.i32Const(1));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localSet(iLoc));
    out.write(Wasm.br(0));

    out.writeByte(Wasm.end); // loop
    out.writeByte(Wasm.end); // block

    // acc += "}"
    _emitConcatInto(
      out,
      context,
      acc,
      () => _emitStringLiteralHandle(out, context, '}'),
    );

    out.write(Wasm.localGet(acc));
    context.stackPush(_astTypeString, "Map to string");
  }

  /// Converts the `List` header pointer on top of the stack to an i32 string
  /// handle in Dart's `[e0, e1]` form. Scans the element buffer
  /// (`[len@0][cap@4][dataPtr@8]`) at runtime, coercing each element through
  /// [_emitToStringHandle] and joining with `, `.
  void _emitListToString(
    BytesOutput out,
    WasmContext context,
    ASTTypeArray type,
  ) {
    var module = context.module;
    if (module == null) {
      throw StateError("Can't convert a List to String without a module.");
    }
    module.requiresMemory = true;
    module.requiresHeapGlobal = true;

    var elemType = type.componentType;
    var size = _elemSize(elemType);

    var hdr = context.scratchLocal(_astTypeString, 50);
    var dataPtr = context.scratchLocal(_astTypeString, 51);
    var iLoc = context.scratchLocal(_astTypeString, 53);
    var lenLoc = context.scratchLocal(_astTypeString, 54);
    var acc = context.scratchLocal(_astTypeString, 55);

    out.write(
      Wasm.localSet(hdr),
      description: "[OP] List -> String: stash header",
    );
    context.stackDrop();

    // acc = "["
    _emitStringLiteralHandle(out, context, '[');
    out.write(Wasm.localSet(acc));
    context.stackDrop();

    // len = hdr[0] ; dataPtr = hdr[8] ; i = 0
    out.write(Wasm.localGet(hdr));
    out.write(Wasm32.i32Load(2, 0));
    out.write(Wasm.localSet(lenLoc));
    out.write(Wasm.localGet(hdr));
    out.write(Wasm32.i32Load(2, 8));
    out.write(Wasm.localSet(dataPtr));
    out.write(Wasm32.i32Const(0));
    out.write(Wasm.localSet(iLoc));

    out.write(Wasm.block(WasmType.voidType));
    out.write(Wasm.loop(WasmType.voidType));

    out.write(Wasm.localGet(iLoc));
    out.write(Wasm.localGet(lenLoc));
    out.writeByte(Wasm32.i32GreaterThanOrEqualsUnsigned);
    out.write(Wasm.brIf(1));

    out.write(Wasm.localGet(iLoc));
    out.write(Wasm.ifInstruction(WasmType.voidType));
    _emitConcatInto(
      out,
      context,
      acc,
      () => _emitStringLiteralHandle(out, context, ', '),
    );
    out.writeByte(Wasm.end);

    _emitConcatInto(
      out,
      context,
      acc,
      () => _emitCollectionElement(out, context, elemType, dataPtr, iLoc, size),
    );

    out.write(Wasm.localGet(iLoc));
    out.write(Wasm32.i32Const(1));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localSet(iLoc));
    out.write(Wasm.br(0));

    out.writeByte(Wasm.end); // loop
    out.writeByte(Wasm.end); // block

    _emitConcatInto(
      out,
      context,
      acc,
      () => _emitStringLiteralHandle(out, context, ']'),
    );

    out.write(Wasm.localGet(acc));
    context.stackPush(_astTypeString, "List to string");
  }

  /// Converts the boxed `Object` pointer on top of the stack to an i32 string
  /// handle by branching on the box `tag` (`[tag@0][typeId@4][payload@8]`):
  /// int/double via the host `int_to_str`/`double_to_str` imports, bool by
  /// `select`ing the interned `"true"`/`"false"` literals, a boxed instance by
  /// dispatching on its `typeId` to the matching `Class.toString`, and a boxed
  /// String by returning its payload pointer directly.
  void _emitBoxToString(BytesOutput out, WasmContext context) {
    var module = context.module;
    if (module == null) {
      throw StateError(
        "Can't convert a boxed Object to String without a "
        "module.",
      );
    }
    module.requiresMemory = true;

    var boxLocal = context.scratchLocal(_astTypeString, 40); // i32
    var tagLocal = context.scratchLocal(_astTypeString, 41); // i32

    out.write(
      Wasm.localSet(boxLocal),
      description: "[OP] stash Object box ptr",
    );
    out.write(Wasm.localGet(boxLocal));
    out.write(
      Wasm32.i32Load(2, _boxTagOffset),
      description: "[OP] load Object box tag",
    );
    out.write(Wasm.localSet(tagLocal));

    var intToStr = module.registerImportedFunction(
      'env',
      'int_to_str',
      const [WasmType.i64Type],
      const [WasmType.i32Type],
    );
    var doubleToStr = module.registerImportedFunction(
      'env',
      'double_to_str',
      const [WasmType.f64Type],
      const [WasmType.i32Type],
    );
    var truePtr = module.internStringLiteral('true');
    var falsePtr = module.internStringLiteral('false');
    var nullPtr = module.internStringLiteral('null');

    // if (box == null) -> "null". Checked first: a null box has no cell, so its
    // tag must not be dereferenced.
    out.write(Wasm.localGet(boxLocal));
    out.write(Wasm32.i32Const(_boxPtrNull));
    out.writeByte(Wasm32.i32Equals);
    out.write(Wasm.ifInstruction(WasmType.i32Type));
    out.write(
      Wasm32.i32Const(nullPtr),
      description: "[OP] box null -> \"null\"",
    );
    out.writeByte(Wasm.elseInstruction);

    // if (tag == int)
    out.write(Wasm.localGet(tagLocal));
    out.write(Wasm32.i32Const(_boxTagInt));
    out.writeByte(Wasm32.i32Equals);
    out.write(Wasm.ifInstruction(WasmType.i32Type));
    out.write(Wasm.localGet(boxLocal));
    out.write(Wasm64.i64Load(3, _boxPayloadOffset));
    out.write(Wasm.call(intToStr), description: "[OP] box int -> string");
    out.writeByte(Wasm.elseInstruction);

    // else if (tag == double)
    out.write(Wasm.localGet(tagLocal));
    out.write(Wasm32.i32Const(_boxTagDouble));
    out.writeByte(Wasm32.i32Equals);
    out.write(Wasm.ifInstruction(WasmType.i32Type));
    out.write(Wasm.localGet(boxLocal));
    out.write(Wasm64.f64Load(FloatAlign.align3, _boxPayloadOffset));
    out.write(Wasm.call(doubleToStr), description: "[OP] box double -> string");
    out.writeByte(Wasm.elseInstruction);

    // else if (tag == bool): select between interned "true"/"false".
    out.write(Wasm.localGet(tagLocal));
    out.write(Wasm32.i32Const(_boxTagBool));
    out.writeByte(Wasm32.i32Equals);
    out.write(Wasm.ifInstruction(WasmType.i32Type));
    out.write(Wasm32.i32Const(truePtr));
    out.write(Wasm32.i32Const(falsePtr));
    out.write(Wasm.localGet(boxLocal));
    out.write(Wasm32.i32Load(2, _boxPayloadOffset));
    out.writeByte(Wasm.select, description: "[OP] box bool -> string");
    out.writeByte(Wasm.elseInstruction);

    // else: tag is String (payload is the string ptr) or instance (dispatch on
    // typeId to the matching `Class.toString`). Boxed instances carry a 1-based
    // typeId; String boxes carry typeId 0 and fall through to the payload ptr.
    var toStringClasses = <({int typeId, int methodIdx})>[];
    var typeId = 0;
    for (var className in module.classLayouts.keys) {
      typeId++;
      var mi = module.methodIndex(className, 'toString', 0);
      if (mi != null) toStringClasses.add((typeId: typeId, methodIdx: mi));
    }
    for (var cls in toStringClasses) {
      out.write(Wasm.localGet(boxLocal));
      out.write(Wasm32.i32Load(2, _boxTypeIdOffset));
      out.write(Wasm32.i32Const(cls.typeId));
      out.writeByte(Wasm32.i32Equals);
      out.write(Wasm.ifInstruction(WasmType.i32Type));
      out.write(Wasm.localGet(boxLocal));
      out.write(Wasm32.i32Load(2, _boxPayloadOffset));
      out.write(
        Wasm.call(cls.methodIdx),
        description: "[OP] box instance(typeId ${cls.typeId}) -> toString",
      );
      out.writeByte(Wasm.elseInstruction);
    }
    // Innermost else / String fallback: the payload is already a string handle.
    out.write(Wasm.localGet(boxLocal));
    out.write(
      Wasm32.i32Load(2, _boxPayloadOffset),
      description: "[OP] box String -> payload ptr",
    );
    for (var _ in toStringClasses) {
      out.writeByte(Wasm.end);
    }

    out.writeByte(Wasm.end); // bool
    out.writeByte(Wasm.end); // double
    out.writeByte(Wasm.end); // int
    out.writeByte(Wasm.end); // null

    context.stackDrop(); // box ptr consumed
    context.stackPush(_astTypeString, "Object box to string");
  }

  /// Boxes the concrete value on top of the stack into a 16-byte `Object` cell
  /// (`[tag@0][typeId@4][payload@8]`), leaving the box pointer on the stack
  /// (stack type `Object`). The reverse of [_emitBoxToString]; used when a
  /// concrete value flows into an `Object` slot (e.g. a `List<Object>` literal).
  /// A value already typed `Object` is left unchanged.
  void _emitBoxValue(BytesOutput out, WasmContext context) {
    var module = context.module;
    if (module == null) {
      throw StateError("Can't box a value without a module.");
    }
    var type = context.stackGet(0)!.type;
    if (_isObjectType(type)) return; // already a box

    module.requiresMemory = true;
    module.requiresHeapGlobal = true;

    int tag;
    var typeId = 0;
    ASTType valLocalType;
    if (type is ASTTypeBool || identical(type, _astTypeInt32)) {
      // bool (and the i32 singleton) — checked before `ASTTypeInt`.
      tag = _boxTagBool;
      valLocalType = _astTypeString; // i32
    } else if (type is ASTTypeInt) {
      tag = _boxTagInt;
      valLocalType = _astTypeInt64; // i64
    } else if (type is ASTTypeDouble) {
      tag = _boxTagDouble;
      valLocalType = _astTypeDouble64; // f64
    } else if (type is ASTTypeNum) {
      // A plain `num` (TS/JS `number`) is represented as i64 (int).
      tag = _boxTagInt;
      valLocalType = _astTypeInt64;
    } else if (type is ASTTypeString) {
      tag = _boxTagString;
      valLocalType = _astTypeString; // i32 string ptr
    } else if (_isWasmObjectRef(type)) {
      tag = _boxTagInstance;
      typeId = module.typeIdOf(type.name);
      valLocalType = _astTypeString; // i32 instance ptr
    } else {
      throw UnimplementedError("Wasm boxing of type $type is not supported.");
    }

    var valLocal = context.scratchLocal(valLocalType, 42);
    var boxLocal = context.scratchLocal(_astTypeString, 43);

    out.write(Wasm.localSet(valLocal), description: "[OP] stash value to box");
    out.write(Wasm32.i32Const(_boxSize));
    _emitInlineAlloc(out, context);
    out.write(Wasm.localSet(boxLocal));

    out.write(Wasm.localGet(boxLocal));
    out.write(Wasm32.i32Const(tag));
    out.write(Wasm32.i32Store(2, _boxTagOffset), description: "[OP] box tag");
    out.write(Wasm.localGet(boxLocal));
    out.write(Wasm32.i32Const(typeId));
    out.write(
      Wasm32.i32Store(2, _boxTypeIdOffset),
      description: "[OP] box typeId",
    );
    out.write(Wasm.localGet(boxLocal));
    out.write(Wasm.localGet(valLocal));
    if (tag == _boxTagInt) {
      out.write(Wasm64.i64Store(3, _boxPayloadOffset));
    } else if (tag == _boxTagDouble) {
      out.write(Wasm64.f64Store(FloatAlign.align3, _boxPayloadOffset));
    } else {
      out.write(Wasm32.i32Store(2, _boxPayloadOffset));
    }

    out.write(Wasm.localGet(boxLocal), description: "[OP] boxed Object ptr");

    context.stackDrop();
    context.stackPush(ASTTypeObject.instance, "boxed Object");
  }

  /// Converts the i32 boolean on top of the stack to an i32 string handle:
  /// `select`s between the interned `"true"` / `"false"` literals. `select`
  /// pops `[a, b, cond]` and keeps `a` when `cond != 0`, so the condition is
  /// stashed in a scratch local and re-pushed above the two pointers.
  void _emitBoolToString(BytesOutput out, WasmContext context) {
    var module = context.module;
    if (module == null) {
      throw StateError("Can't convert a bool to String without a module.");
    }
    var truePtr = module.internStringLiteral('true');
    var falsePtr = module.internStringLiteral('false');

    // i32 scratch local (an `ASTTypeInt` would map to i64; `_astTypeString` is
    // the i32-typed slot used throughout this generator).
    var condLocal = context.scratchLocal(_astTypeString, 30);

    // cond := top ; [truePtr, falsePtr, cond] ; select -> chosen pointer.
    out.write(Wasm.localSet(condLocal), description: "[OP] stash bool cond");
    out.write(
      Wasm32.i32Const(truePtr),
      description: "[OP] push 'true' literal ptr($truePtr)",
    );
    out.write(
      Wasm32.i32Const(falsePtr),
      description: "[OP] push 'false' literal ptr($falsePtr)",
    );
    out.write(Wasm.localGet(condLocal), description: "[OP] reload bool cond");
    out.writeByte(Wasm.select, description: "[OP] select true/false string");

    context.stackDrop(); // bool consumed
    context.stackPush(_astTypeString, "bool to string");
  }

  /// Concatenates the top two string handles on the stack (`[a, b]`) into a
  /// freshly allocated `[len:i32][utf8]` string, leaving its pointer on the
  /// stack. Uses the bump allocator (`$hp`) + `memory.copy`.
  void _emitStringConcat2(BytesOutput out, WasmContext context) {
    var module = context.module;
    if (module == null) {
      throw StateError("Can't concatenate strings without a module.");
    }
    module.requiresMemory = true;
    module.requiresHeapGlobal = true;

    // i32 scratch locals (ASTTypeString maps to i32).
    var a = context.scratchLocal(_astTypeString, 0);
    var b = context.scratchLocal(_astTypeString, 1);
    var dest = context.scratchLocal(_astTypeString, 2);

    void getLen(int strLocal) {
      out.write(Wasm.localGet(strLocal));
      out.write(Wasm32.i32Load());
    }

    void dataPtr(int strLocal) {
      out.write(Wasm.localGet(strLocal));
      out.write(Wasm32.i32Const(4));
      out.writeByte(Wasm32.i32Add);
    }

    // Consume operands [a, b].
    out.write(Wasm.localSet(b));
    out.write(Wasm.localSet(a));

    // size = len(a) + len(b) + 4
    getLen(a);
    getLen(b);
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm32.i32Const(4));
    out.writeByte(Wasm32.i32Add);

    // Allocate (grow-aware): [size] -> [ptr], then dest = ptr.
    _emitInlineAlloc(out, context);
    out.write(Wasm.localSet(dest));

    // Store total length at dest.
    out.write(Wasm.localGet(dest));
    getLen(a);
    getLen(b);
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm32.i32Store());

    // memory.copy(dest+4, a+4, len(a))
    out.write(Wasm.localGet(dest));
    out.write(Wasm32.i32Const(4));
    out.writeByte(Wasm32.i32Add);
    dataPtr(a);
    getLen(a);
    out.write(Wasm.memoryCopy);

    // memory.copy(dest+4+len(a), b+4, len(b))
    out.write(Wasm.localGet(dest));
    out.write(Wasm32.i32Const(4));
    out.writeByte(Wasm32.i32Add);
    getLen(a);
    out.writeByte(Wasm32.i32Add);
    dataPtr(b);
    getLen(b);
    out.write(Wasm.memoryCopy);

    // Result pointer.
    out.write(Wasm.localGet(dest));

    context.stackDrop();
    context.stackDrop();
    context.stackPush(_astTypeString, "string concat");
  }

  /// Lowers `s.toUpperCase()` / `s.toLowerCase()` for ASCII text. Allocates a
  /// fresh `[len:i32][utf8]` buffer the same size as the receiver, then copies
  /// each byte shifting ASCII letters by `0x20` (case bit). Non-letter bytes and
  /// non-ASCII bytes are copied unchanged, so this matches Dart semantics for
  /// ASCII input (the same restriction as the byte-length `.length`).
  /// Dispatches a supported String method (over the `[len:i32][utf8]` layout) to
  /// its byte-level codegen, or returns `null` if [expression.name] isn't one of
  /// them (the caller then errors). Byte-indexed, so exact for ASCII text (a
  /// multi-byte UTF-8 code point counts as its byte length).
  BytesOutput? _tryGenerateStringMethod(
    ASTExpressionObjectFunctionInvocation expression,
    ({ASTType type, int index}) recv,
    String varName, {
    required BytesOutput out,
    required WasmContext context,
  }) {
    var name = expression.name;
    var args = expression.arguments;
    if (name == 'codeUnitAt' && args.length == 1) {
      return _generateStringCodeUnitAt(
        recv,
        varName,
        args[0],
        out: out,
        context: context,
      );
    }
    if (name == 'substring' && (args.length == 1 || args.length == 2)) {
      return _generateStringSubstring(
        recv,
        varName,
        args,
        out: out,
        context: context,
      );
    }
    if (name == 'startsWith' && args.length == 1) {
      return _generateStringStartsEndsWith(
        recv,
        varName,
        args[0],
        ends: false,
        out: out,
        context: context,
      );
    }
    if (name == 'endsWith' && args.length == 1) {
      return _generateStringStartsEndsWith(
        recv,
        varName,
        args[0],
        ends: true,
        out: out,
        context: context,
      );
    }
    if (name == 'indexOf' && args.length == 1) {
      return _generateStringIndexOf(
        recv,
        varName,
        args[0],
        asContains: false,
        out: out,
        context: context,
      );
    }
    if (name == 'contains' && args.length == 1) {
      return _generateStringIndexOf(
        recv,
        varName,
        args[0],
        asContains: true,
        out: out,
        context: context,
      );
    }
    if ((name == 'trim' || name == 'trimLeft' || name == 'trimRight') &&
        args.isEmpty) {
      return _generateStringTrim(
        recv,
        varName,
        left: name != 'trimRight',
        right: name != 'trimLeft',
        out: out,
        context: context,
      );
    }
    if ((name == 'padLeft' || name == 'padRight') &&
        (args.length == 1 || args.length == 2)) {
      return _generateStringPad(
        recv,
        varName,
        args,
        left: name == 'padLeft',
        out: out,
        context: context,
      );
    }
    if ((name == 'replaceAll' || name == 'replaceFirst') && args.length == 2) {
      return _generateStringReplace(
        recv,
        varName,
        args,
        all: name == 'replaceAll',
        out: out,
        context: context,
      );
    }
    if (name == 'compareTo' && args.length == 1) {
      return _generateStringCompareTo(
        recv,
        varName,
        args[0],
        out: out,
        context: context,
      );
    }
    if (name == 'split' && args.length == 1) {
      return _generateStringSplit(
        recv,
        varName,
        args[0],
        out: out,
        context: context,
      );
    }
    return null;
  }

  /// `s.split(sep)` -> a `List<String>` of the pieces between (non-overlapping)
  /// occurrences of `sep`. Two passes over the byte layout: pass 1 counts the
  /// separators to size the list (`pieces = count + 1`), pass 2 allocates each
  /// piece as a fresh String and stores its pointer in the list buffer. An empty
  /// `sep` yields a single piece (the whole string) — Dart's char-split for `''`
  /// is a follow-up.
  BytesOutput _generateStringSplit(
    ({ASTType type, int index}) recv,
    String varName,
    ASTExpression sepExpr, {
    required BytesOutput out,
    required WasmContext context,
  }) {
    var module = context.module!;
    module.requiresMemory = true;
    module.requiresHeapGlobal = true;
    final s0 = context.stackLength;

    var src = context.scratchLocal(_astTypeString, 60);
    var srcLen = context.scratchLocal(_astTypeString, 61);
    var sep = context.scratchLocal(_astTypeString, 62);
    var sepLen = context.scratchLocal(_astTypeString, 63);
    var sepData = context.scratchLocal(_astTypeString, 64);
    var count = context.scratchLocal(_astTypeString, 65);
    var i = context.scratchLocal(_astTypeString, 66);
    var listHdr = context.scratchLocal(_astTypeString, 67);
    var dataBuf = context.scratchLocal(_astTypeString, 68);
    var pieceIdx = context.scratchLocal(_astTypeString, 69);
    var ps = context.scratchLocal(_astTypeString, 70);
    var isMatch = context.scratchLocal(_astTypeString, 71);
    var j = context.scratchLocal(_astTypeString, 72);
    var aAddr = context.scratchLocal(_astTypeString, 73);
    var pieceLen = context.scratchLocal(_astTypeString, 74);
    var strPtr = context.scratchLocal(_astTypeString, 75);
    var isEnd = context.scratchLocal(_astTypeString, 76);
    var doEmit = context.scratchLocal(_astTypeString, 77);

    // sep = eval(arg) ; src = recv ; lengths ; sepData = sep + 4
    generateASTExpression(sepExpr, out: out, context: context);
    context.stackDrop();
    out.write(Wasm.localSet(sep));
    _localVariableGet(out, context, recv.index, varName);
    out.write(Wasm.localSet(src));
    out.write(Wasm.localGet(src));
    out.write(Wasm32.i32Load());
    out.write(Wasm.localSet(srcLen));
    out.write(Wasm.localGet(sep));
    out.write(Wasm32.i32Load());
    out.write(Wasm.localSet(sepLen));
    out.write(Wasm.localGet(sep));
    out.write(Wasm32.i32Const(4));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localSet(sepData));

    // --- Pass 1: count non-overlapping separators ---
    out.write(Wasm32.i32Const(0));
    out.write(Wasm.localSet(count));
    out.write(Wasm32.i32Const(0));
    out.write(Wasm.localSet(i));
    out.write(Wasm.block(WasmType.voidType));
    context.controlDepth++;
    var brk1 = context.controlDepth;
    out.write(Wasm.loop(WasmType.voidType));
    context.controlDepth++;
    var rpt1 = context.controlDepth;
    // if (i + sepLen > srcLen) break
    out.write(Wasm.localGet(i));
    out.write(Wasm.localGet(sepLen));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localGet(srcLen));
    out.writeByte(Wasm32.i32GreaterThanUnsigned);
    out.write(Wasm.brIf(context.controlDepth - brk1));
    // aAddr = src + 4 + i ; isMatch = bytesEqual(aAddr, sepData, sepLen) & sepLen!=0
    out.write(Wasm.localGet(src));
    out.write(Wasm32.i32Const(4));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localGet(i));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localSet(aAddr));
    _emitBytesEqualNoBreak(
      out,
      context,
      aLoc: aAddr,
      bLoc: sepData,
      lenLoc: sepLen,
      jLoc: j,
      outLoc: isMatch,
    );
    out.write(Wasm.localGet(isMatch));
    out.write(Wasm.localGet(sepLen));
    out.write(Wasm32.i32Const(0));
    out.writeByte(Wasm32.i32NotEquals);
    out.writeByte(Wasm32.i32BitwiseAnd);
    out.write(Wasm.localSet(isMatch));
    // count += isMatch ; i += isMatch ? sepLen : 1
    out.write(Wasm.localGet(count));
    out.write(Wasm.localGet(isMatch));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localSet(count));
    out.write(Wasm.localGet(i));
    out.write(Wasm.localGet(sepLen));
    out.write(Wasm32.i32Const(1));
    out.write(Wasm.localGet(isMatch));
    out.writeByte(Wasm.select);
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localSet(i));
    out.write(Wasm.br(context.controlDepth - rpt1));
    out.writeByte(Wasm.end); // loop
    context.controlDepth--;
    out.writeByte(Wasm.end); // block
    context.controlDepth--;

    // list header (12) + data buffer ((count + 1) * 4)
    out.write(Wasm32.i32Const(_listHeaderSize));
    _emitInlineAlloc(out, context);
    out.write(Wasm.localSet(listHdr));
    out.write(Wasm.localGet(count));
    out.write(Wasm32.i32Const(1));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm32.i32Const(4));
    out.writeByte(Wasm32.i32Multiply);
    _emitInlineAlloc(out, context);
    out.write(Wasm.localSet(dataBuf));
    // header: length = count+1, capacity = count+1, dataPtr = dataBuf
    out.write(Wasm.localGet(listHdr));
    out.write(Wasm.localGet(count));
    out.write(Wasm32.i32Const(1));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm32.i32Store(2, 0));
    out.write(Wasm.localGet(listHdr));
    out.write(Wasm.localGet(count));
    out.write(Wasm32.i32Const(1));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm32.i32Store(2, 4));
    out.write(Wasm.localGet(listHdr));
    out.write(Wasm.localGet(dataBuf));
    out.write(Wasm32.i32Store(2, 8));

    // --- Pass 2: emit each piece [ps, i) as a fresh String ---
    out.write(Wasm32.i32Const(0));
    out.write(Wasm.localSet(pieceIdx));
    out.write(Wasm32.i32Const(0));
    out.write(Wasm.localSet(ps));
    out.write(Wasm32.i32Const(0));
    out.write(Wasm.localSet(i));
    out.write(Wasm.block(WasmType.voidType));
    context.controlDepth++;
    var brk2 = context.controlDepth;
    out.write(Wasm.loop(WasmType.voidType));
    context.controlDepth++;
    var rpt2 = context.controlDepth;

    // isEnd = i >= srcLen
    out.write(Wasm.localGet(i));
    out.write(Wasm.localGet(srcLen));
    out.writeByte(Wasm32.i32GreaterThanOrEqualsUnsigned);
    out.write(Wasm.localSet(isEnd));
    // isMatch = (i + sepLen <= srcLen) & bytesEqual(src+4+i, sepData, sepLen) & sepLen!=0
    out.write(Wasm.localGet(src));
    out.write(Wasm32.i32Const(4));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localGet(i));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localSet(aAddr));
    _emitBytesEqualNoBreak(
      out,
      context,
      aLoc: aAddr,
      bLoc: sepData,
      lenLoc: sepLen,
      jLoc: j,
      outLoc: isMatch,
    );
    out.write(Wasm.localGet(isMatch));
    out.write(Wasm.localGet(sepLen));
    out.write(Wasm32.i32Const(0));
    out.writeByte(Wasm32.i32NotEquals);
    out.writeByte(Wasm32.i32BitwiseAnd);
    out.write(Wasm.localGet(i));
    out.write(Wasm.localGet(sepLen));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localGet(srcLen));
    out.writeByte(Wasm32.i32LessThanOrEqualsUnsigned);
    out.writeByte(Wasm32.i32BitwiseAnd);
    out.write(Wasm.localSet(isMatch));
    // doEmit = isEnd | isMatch
    out.write(Wasm.localGet(isEnd));
    out.write(Wasm.localGet(isMatch));
    out.writeByte(Wasm32.i32BitwiseOr);
    out.write(Wasm.localSet(doEmit));

    // if (doEmit) { emit piece [ps, i) ; dataBuf[pieceIdx++] = strPtr }
    out.write(Wasm.localGet(doEmit));
    out.write(Wasm.ifInstruction(WasmType.voidType));
    // pieceLen = i - ps
    out.write(Wasm.localGet(i));
    out.write(Wasm.localGet(ps));
    out.writeByte(Wasm32.i32Subtract);
    out.write(Wasm.localSet(pieceLen));
    // strPtr = alloc(pieceLen + 4) ; store pieceLen ; memcpy(strPtr+4, src+4+ps, pieceLen)
    out.write(Wasm.localGet(pieceLen));
    out.write(Wasm32.i32Const(4));
    out.writeByte(Wasm32.i32Add);
    _emitInlineAlloc(out, context);
    out.write(Wasm.localSet(strPtr));
    out.write(Wasm.localGet(strPtr));
    out.write(Wasm.localGet(pieceLen));
    out.write(Wasm32.i32Store());
    out.write(Wasm.localGet(strPtr));
    out.write(Wasm32.i32Const(4));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localGet(src));
    out.write(Wasm32.i32Const(4));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localGet(ps));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localGet(pieceLen));
    out.write(Wasm.memoryCopy);
    // dataBuf[pieceIdx * 4] = strPtr
    out.write(Wasm.localGet(dataBuf));
    out.write(Wasm.localGet(pieceIdx));
    out.write(Wasm32.i32Const(4));
    out.writeByte(Wasm32.i32Multiply);
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localGet(strPtr));
    out.write(Wasm32.i32Store());
    // pieceIdx++
    out.write(Wasm.localGet(pieceIdx));
    out.write(Wasm32.i32Const(1));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localSet(pieceIdx));
    out.writeByte(Wasm.end); // if

    // if (isEnd) break
    out.write(Wasm.localGet(isEnd));
    out.write(Wasm.brIf(context.controlDepth - brk2));

    // ps = isMatch ? i + sepLen : ps ; i += isMatch ? sepLen : 1
    out.write(Wasm.localGet(i));
    out.write(Wasm.localGet(sepLen));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localGet(ps));
    out.write(Wasm.localGet(isMatch));
    out.writeByte(Wasm.select);
    out.write(Wasm.localSet(ps));
    out.write(Wasm.localGet(i));
    out.write(Wasm.localGet(sepLen));
    out.write(Wasm32.i32Const(1));
    out.write(Wasm.localGet(isMatch));
    out.writeByte(Wasm.select);
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localSet(i));
    out.write(Wasm.br(context.controlDepth - rpt2));

    out.writeByte(Wasm.end); // loop
    context.controlDepth--;
    out.writeByte(Wasm.end); // block
    context.controlDepth--;

    out.write(Wasm.localGet(listHdr));
    context.stackPush(ASTTypeArray(_astTypeString), "$varName.split");
    context.assertStackLength(s0 + 1, "After String.split");
    return out;
  }

  /// `s.compareTo(other)` -> `-1`/`0`/`1` (lexicographic byte comparison), as an
  /// `int` (i64). Matches `String.compareTo`, which returns exactly `-1`/`0`/`1`.
  BytesOutput _generateStringCompareTo(
    ({ASTType type, int index}) recv,
    String varName,
    ASTExpression argExpr, {
    required BytesOutput out,
    required WasmContext context,
  }) {
    context.module!.requiresMemory = true;
    final s0 = context.stackLength;

    var src = context.scratchLocal(_astTypeString, 60);
    var srcLen = context.scratchLocal(_astTypeString, 61);
    var sub = context.scratchLocal(_astTypeString, 62);
    var subLen = context.scratchLocal(_astTypeString, 63);
    var minLen = context.scratchLocal(_astTypeString, 64);
    var i = context.scratchLocal(_astTypeString, 65);
    var ca = context.scratchLocal(_astTypeString, 66);
    var cb = context.scratchLocal(_astTypeString, 67);
    var result = context.scratchLocal(_astTypeString, 68);

    generateASTExpression(argExpr, out: out, context: context);
    context.stackDrop();
    out.write(Wasm.localSet(sub));
    _localVariableGet(out, context, recv.index, varName);
    out.write(Wasm.localSet(src));
    out.write(Wasm.localGet(src));
    out.write(Wasm32.i32Load());
    out.write(Wasm.localSet(srcLen));
    out.write(Wasm.localGet(sub));
    out.write(Wasm32.i32Load());
    out.write(Wasm.localSet(subLen));

    // minLen = (srcLen < subLen) ? srcLen : subLen
    out.write(Wasm.localGet(srcLen));
    out.write(Wasm.localGet(subLen));
    out.write(Wasm.localGet(srcLen));
    out.write(Wasm.localGet(subLen));
    out.writeByte(Wasm32.i32LessThanUnsigned);
    out.writeByte(Wasm.select);
    out.write(Wasm.localSet(minLen));

    // result = 0 ; i = 0
    out.write(Wasm32.i32Const(0));
    out.write(Wasm.localSet(result));
    out.write(Wasm32.i32Const(0));
    out.write(Wasm.localSet(i));

    out.write(Wasm.block(WasmType.voidType));
    context.controlDepth++;
    final brk = context.controlDepth;
    out.write(Wasm.loop(WasmType.voidType));
    context.controlDepth++;
    final rpt = context.controlDepth;
    // if (i >= minLen) break
    out.write(Wasm.localGet(i));
    out.write(Wasm.localGet(minLen));
    out.writeByte(Wasm32.i32GreaterThanOrEqualsUnsigned);
    out.write(Wasm.brIf(context.controlDepth - brk));
    // ca = src[i] ; cb = sub[i]
    out.write(Wasm.localGet(src));
    out.write(Wasm32.i32Const(4));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localGet(i));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm32.i32Load8U());
    out.write(Wasm.localSet(ca));
    out.write(Wasm.localGet(sub));
    out.write(Wasm32.i32Const(4));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localGet(i));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm32.i32Load8U());
    out.write(Wasm.localSet(cb));
    // sign = (ca < cb) ? -1 : 1 ; result = (ca != cb) ? sign : result
    out.write(Wasm32.i32Const(-1));
    out.write(Wasm32.i32Const(1));
    out.write(Wasm.localGet(ca));
    out.write(Wasm.localGet(cb));
    out.writeByte(Wasm32.i32LessThanUnsigned);
    out.writeByte(Wasm.select);
    out.write(Wasm.localGet(result));
    out.write(Wasm.localGet(ca));
    out.write(Wasm.localGet(cb));
    out.writeByte(Wasm32.i32NotEquals);
    out.writeByte(Wasm.select);
    out.write(Wasm.localSet(result));
    // break when ca != cb
    out.write(Wasm.localGet(ca));
    out.write(Wasm.localGet(cb));
    out.writeByte(Wasm32.i32NotEquals);
    out.write(Wasm.brIf(context.controlDepth - brk));
    // i++
    out.write(Wasm.localGet(i));
    out.write(Wasm32.i32Const(1));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localSet(i));
    out.write(Wasm.br(context.controlDepth - rpt));
    out.writeByte(Wasm.end); // loop
    context.controlDepth--;
    out.writeByte(Wasm.end); // block
    context.controlDepth--;

    // Tie-break on length when the common prefix is equal (result still 0):
    // result = (result == 0) ? ((srcLen>subLen) - (srcLen<subLen)) : result
    out.write(Wasm.localGet(srcLen));
    out.write(Wasm.localGet(subLen));
    out.writeByte(Wasm32.i32GreaterThanUnsigned);
    out.write(Wasm.localGet(srcLen));
    out.write(Wasm.localGet(subLen));
    out.writeByte(Wasm32.i32LessThanUnsigned);
    out.writeByte(Wasm32.i32Subtract); // gt - lt in {-1, 0, 1}
    out.write(Wasm.localGet(result));
    out.write(Wasm.localGet(result));
    out.writeByte(Wasm32.i32EqualsToZero);
    out.writeByte(Wasm.select); // (result == 0) ? lengthCmp : result
    out.write(Wasm.localSet(result));

    out.write(Wasm.localGet(result));
    out.writeByte(Wasm32.i32ExtendToI64Signed);
    context.stackPush(_astTypeInt64, "$varName.compareTo");
    context.assertStackLength(s0 + 1, "After String.compareTo");
    return out;
  }

  /// `s.replaceAll(from, to)` / `s.replaceFirst(from, to)`: returns a fresh
  /// String with (all / the first) non-overlapping occurrence(s) of `from`
  /// replaced by `to`. Two passes over the byte layout — pass 1 counts matches
  /// to size the output buffer, pass 2 builds it. An empty `from` is treated as
  /// no match (returns a copy) to avoid a non-terminating scan.
  BytesOutput _generateStringReplace(
    ({ASTType type, int index}) recv,
    String varName,
    List<ASTExpression> args, {
    required bool all,
    required BytesOutput out,
    required WasmContext context,
  }) {
    var module = context.module!;
    module.requiresMemory = true;
    module.requiresHeapGlobal = true;
    final s0 = context.stackLength;

    var src = context.scratchLocal(_astTypeString, 60);
    var srcLen = context.scratchLocal(_astTypeString, 61);
    var from = context.scratchLocal(_astTypeString, 62);
    var fromLen = context.scratchLocal(_astTypeString, 63);
    var to = context.scratchLocal(_astTypeString, 64);
    var toLen = context.scratchLocal(_astTypeString, 65);
    var count = context.scratchLocal(_astTypeString, 66);
    var i = context.scratchLocal(_astTypeString, 67);
    var dest = context.scratchLocal(_astTypeString, 68);
    var outLen = context.scratchLocal(_astTypeString, 69);
    var w = context.scratchLocal(_astTypeString, 70);
    var match = context.scratchLocal(_astTypeString, 71);
    var j = context.scratchLocal(_astTypeString, 72);
    var aAddr = context.scratchLocal(_astTypeString, 73);
    var fromData = context.scratchLocal(_astTypeString, 74);

    // from = arg0 ; to = arg1 ; src = recv
    generateASTExpression(args[0], out: out, context: context);
    context.stackDrop();
    out.write(Wasm.localSet(from));
    generateASTExpression(args[1], out: out, context: context);
    context.stackDrop();
    out.write(Wasm.localSet(to));
    _localVariableGet(out, context, recv.index, varName);
    out.write(Wasm.localSet(src));
    out.write(Wasm.localGet(src));
    out.write(Wasm32.i32Load());
    out.write(Wasm.localSet(srcLen));
    out.write(Wasm.localGet(from));
    out.write(Wasm32.i32Load());
    out.write(Wasm.localSet(fromLen));
    out.write(Wasm.localGet(to));
    out.write(Wasm32.i32Load());
    out.write(Wasm.localSet(toLen));
    // fromData = from + 4 (the pattern's byte start, reused by both passes)
    out.write(Wasm.localGet(from));
    out.write(Wasm32.i32Const(4));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localSet(fromData));

    // Pass 1: count non-overlapping matches into `count`.
    _emitReplaceScan(
      out,
      context,
      src: src,
      srcLen: srcLen,
      fromData: fromData,
      fromLen: fromLen,
      iLoc: i,
      matchLoc: match,
      jLoc: j,
      aAddr: aAddr,
      counterLoc: count,
      all: all,
      dest: null,
      w: w,
      to: to,
      toLen: toLen,
    );

    // outLen = srcLen + count * (toLen - fromLen)
    out.write(Wasm.localGet(srcLen));
    out.write(Wasm.localGet(count));
    out.write(Wasm.localGet(toLen));
    out.write(Wasm.localGet(fromLen));
    out.writeByte(Wasm32.i32Subtract);
    out.writeByte(Wasm32.i32Multiply);
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localSet(outLen));

    // dest = alloc(outLen + 4) ; store outLen
    out.write(Wasm.localGet(outLen));
    out.write(Wasm32.i32Const(4));
    out.writeByte(Wasm32.i32Add);
    _emitInlineAlloc(out, context);
    out.write(Wasm.localSet(dest));
    out.write(Wasm.localGet(dest));
    out.write(Wasm.localGet(outLen));
    out.write(Wasm32.i32Store());

    // Pass 2: build the output at `dest`.
    _emitReplaceScan(
      out,
      context,
      src: src,
      srcLen: srcLen,
      fromData: fromData,
      fromLen: fromLen,
      iLoc: i,
      matchLoc: match,
      jLoc: j,
      aAddr: aAddr,
      counterLoc: count,
      all: all,
      dest: dest,
      w: w,
      to: to,
      toLen: toLen,
    );

    out.write(Wasm.localGet(dest));
    context.stackPush(_astTypeString, "$varName.replace");
    context.assertStackLength(s0 + 1, "After String.replace");
    return out;
  }

  /// One scan pass for [_generateStringReplace]. With [dest] null it counts
  /// matches into [counterLoc]; otherwise it builds the output at [dest] (copying
  /// `to` for a match, else one byte), reusing [counterLoc] to gate replaceFirst.
  void _emitReplaceScan(
    BytesOutput out,
    WasmContext context, {
    required int src,
    required int srcLen,
    required int fromData,
    required int fromLen,
    required int iLoc,
    required int matchLoc,
    required int jLoc,
    required int aAddr,
    required int counterLoc,
    required bool all,
    required int? dest,
    required int w,
    required int to,
    required int toLen,
  }) {
    final building = dest != null;
    out.write(Wasm32.i32Const(0));
    out.write(Wasm.localSet(counterLoc));
    out.write(Wasm32.i32Const(0));
    out.write(Wasm.localSet(iLoc));
    if (building) {
      out.write(Wasm32.i32Const(0));
      out.write(Wasm.localSet(w));
    }

    out.write(Wasm.block(WasmType.voidType));
    context.controlDepth++;
    final brk = context.controlDepth;
    out.write(Wasm.loop(WasmType.voidType));
    context.controlDepth++;
    final rpt = context.controlDepth;

    // if (i >= srcLen) break
    out.write(Wasm.localGet(iLoc));
    out.write(Wasm.localGet(srcLen));
    out.writeByte(Wasm32.i32GreaterThanOrEqualsUnsigned);
    out.write(Wasm.brIf(context.controlDepth - brk));

    // aAddr = src + 4 + i ; match = (fromLen bytes at aAddr == from)
    out.write(Wasm.localGet(src));
    out.write(Wasm32.i32Const(4));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localGet(iLoc));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localSet(aAddr));
    _emitBytesEqualNoBreak(
      out,
      context,
      aLoc: aAddr,
      bLoc: fromData,
      lenLoc: fromLen,
      jLoc: jLoc,
      outLoc: matchLoc,
    );
    // match &= (fromLen != 0) & (i + fromLen <= srcLen)
    out.write(Wasm.localGet(matchLoc));
    out.write(Wasm.localGet(fromLen));
    out.write(Wasm32.i32Const(0));
    out.writeByte(Wasm32.i32NotEquals);
    out.writeByte(Wasm32.i32BitwiseAnd);
    out.write(Wasm.localGet(iLoc));
    out.write(Wasm.localGet(fromLen));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localGet(srcLen));
    out.writeByte(Wasm32.i32LessThanOrEqualsUnsigned);
    out.writeByte(Wasm32.i32BitwiseAnd);
    out.write(Wasm.localSet(matchLoc));
    // replaceFirst: only the first match counts (gate on counter == 0)
    if (!all) {
      out.write(Wasm.localGet(matchLoc));
      out.write(Wasm.localGet(counterLoc));
      out.writeByte(Wasm32.i32EqualsToZero);
      out.writeByte(Wasm32.i32BitwiseAnd);
      out.write(Wasm.localSet(matchLoc));
    }

    if (!building) {
      // count += match ; i += match ? fromLen : 1
      out.write(Wasm.localGet(counterLoc));
      out.write(Wasm.localGet(matchLoc));
      out.writeByte(Wasm32.i32Add);
      out.write(Wasm.localSet(counterLoc));
      out.write(Wasm.localGet(iLoc));
      out.write(Wasm.localGet(fromLen));
      out.write(Wasm32.i32Const(1));
      out.write(Wasm.localGet(matchLoc));
      out.writeByte(Wasm.select);
      out.writeByte(Wasm32.i32Add);
      out.write(Wasm.localSet(iLoc));
    } else {
      out.write(Wasm.localGet(matchLoc));
      out.write(Wasm.ifInstruction(WasmType.voidType));
      // match: memory.copy(dest + 4 + w, to + 4, toLen)
      out.write(Wasm.localGet(dest));
      out.write(Wasm32.i32Const(4));
      out.writeByte(Wasm32.i32Add);
      out.write(Wasm.localGet(w));
      out.writeByte(Wasm32.i32Add);
      out.write(Wasm.localGet(to));
      out.write(Wasm32.i32Const(4));
      out.writeByte(Wasm32.i32Add);
      out.write(Wasm.localGet(toLen));
      out.write(Wasm.memoryCopy);
      // w += toLen ; i += fromLen ; count++
      out.write(Wasm.localGet(w));
      out.write(Wasm.localGet(toLen));
      out.writeByte(Wasm32.i32Add);
      out.write(Wasm.localSet(w));
      out.write(Wasm.localGet(iLoc));
      out.write(Wasm.localGet(fromLen));
      out.writeByte(Wasm32.i32Add);
      out.write(Wasm.localSet(iLoc));
      out.write(Wasm.localGet(counterLoc));
      out.write(Wasm32.i32Const(1));
      out.writeByte(Wasm32.i32Add);
      out.write(Wasm.localSet(counterLoc));
      out.writeByte(Wasm.elseInstruction);
      // no match: dest[4 + w] = src[4 + i] ; w++ ; i++
      out.write(Wasm.localGet(dest));
      out.write(Wasm32.i32Const(4));
      out.writeByte(Wasm32.i32Add);
      out.write(Wasm.localGet(w));
      out.writeByte(Wasm32.i32Add);
      out.write(Wasm.localGet(src));
      out.write(Wasm32.i32Const(4));
      out.writeByte(Wasm32.i32Add);
      out.write(Wasm.localGet(iLoc));
      out.writeByte(Wasm32.i32Add);
      out.write(Wasm32.i32Load8U());
      out.write(Wasm32.i32Store8());
      out.write(Wasm.localGet(w));
      out.write(Wasm32.i32Const(1));
      out.writeByte(Wasm32.i32Add);
      out.write(Wasm.localSet(w));
      out.write(Wasm.localGet(iLoc));
      out.write(Wasm32.i32Const(1));
      out.writeByte(Wasm32.i32Add);
      out.write(Wasm.localSet(iLoc));
      out.writeByte(Wasm.end); // if
    }

    out.write(Wasm.br(context.controlDepth - rpt));
    out.writeByte(Wasm.end); // loop
    context.controlDepth--;
    out.writeByte(Wasm.end); // block
    context.controlDepth--;
  }

  /// `s[i]` -> a fresh length-1 String holding the byte at `s + 4 + i`.
  BytesOutput _generateStringIndexAccess(
    ({ASTType type, int index}) recv,
    String varName,
    ASTExpression indexExpr, {
    required BytesOutput out,
    required WasmContext context,
  }) {
    var module = context.module!;
    module.requiresMemory = true;
    module.requiresHeapGlobal = true;
    final s0 = context.stackLength;

    var src = context.scratchLocal(_astTypeString, 60);
    var dest = context.scratchLocal(_astTypeString, 61);
    var ch = context.scratchLocal(_astTypeString, 62);

    // ch = load8(src + 4 + i)
    _localVariableGet(out, context, recv.index, varName);
    out.write(Wasm.localSet(src));
    out.write(Wasm.localGet(src));
    out.write(Wasm32.i32Const(4));
    out.writeByte(Wasm32.i32Add);
    generateASTExpression(indexExpr, out: out, context: context); // index (i64)
    context.stackDrop();
    out.writeByte(Wasm64.i64WrapToi32);
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm32.i32Load8U());
    out.write(Wasm.localSet(ch));

    // dest = alloc(1 + 4) ; store len=1 ; store8(dest + 4, ch)
    out.write(Wasm32.i32Const(5));
    _emitInlineAlloc(out, context);
    out.write(Wasm.localSet(dest));
    out.write(Wasm.localGet(dest));
    out.write(Wasm32.i32Const(1));
    out.write(Wasm32.i32Store());
    out.write(Wasm.localGet(dest));
    out.write(Wasm32.i32Const(4));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localGet(ch));
    out.write(Wasm32.i32Store8());

    out.write(Wasm.localGet(dest));
    context.stackPush(_astTypeString, "$varName[index]");
    context.assertStackLength(s0 + 1, "After String index");
    return out;
  }

  /// Pushes `1` if the char in [chLoc] is ASCII whitespace (space, or `\t`..`\r`,
  /// i.e. `0x09..0x0D`), else `0`.
  void _emitCharIsWhitespace(BytesOutput out, int chLoc) {
    out.write(Wasm.localGet(chLoc));
    out.write(Wasm32.i32Const(0x20));
    out.writeByte(Wasm32.i32Equals); // ch == ' '
    out.write(Wasm.localGet(chLoc));
    out.write(Wasm32.i32Const(0x09));
    out.writeByte(Wasm32.i32GreaterThanOrEqualsUnsigned);
    out.write(Wasm.localGet(chLoc));
    out.write(Wasm32.i32Const(0x0D));
    out.writeByte(Wasm32.i32LessThanOrEqualsUnsigned);
    out.writeByte(Wasm32.i32BitwiseAnd); // 0x09 <= ch <= 0x0D
    out.writeByte(Wasm32.i32BitwiseOr);
  }

  /// `s.trim()` / `s.trimLeft()` / `s.trimRight()`: returns a fresh String with
  /// ASCII whitespace stripped from the requested side(s).
  BytesOutput _generateStringTrim(
    ({ASTType type, int index}) recv,
    String varName, {
    required bool left,
    required bool right,
    required BytesOutput out,
    required WasmContext context,
  }) {
    var module = context.module!;
    module.requiresMemory = true;
    module.requiresHeapGlobal = true;
    final s0 = context.stackLength;

    var src = context.scratchLocal(_astTypeString, 60);
    var srcLen = context.scratchLocal(_astTypeString, 61);
    var a = context.scratchLocal(_astTypeString, 62);
    var b = context.scratchLocal(_astTypeString, 63);
    var ch = context.scratchLocal(_astTypeString, 64);
    var dest = context.scratchLocal(_astTypeString, 65);
    var newLen = context.scratchLocal(_astTypeString, 66);

    _localVariableGet(out, context, recv.index, varName);
    out.write(Wasm.localSet(src));
    out.write(Wasm.localGet(src));
    out.write(Wasm32.i32Load());
    out.write(Wasm.localSet(srcLen));

    // a = 0 ; b = srcLen
    out.write(Wasm32.i32Const(0));
    out.write(Wasm.localSet(a));
    out.write(Wasm.localGet(srcLen));
    out.write(Wasm.localSet(b));

    if (left) {
      // while (a < b && isWs(src[a])) a++
      out.write(Wasm.block(WasmType.voidType));
      context.controlDepth++;
      final brk = context.controlDepth;
      out.write(Wasm.loop(WasmType.voidType));
      context.controlDepth++;
      final rpt = context.controlDepth;
      // if (a >= b) break
      out.write(Wasm.localGet(a));
      out.write(Wasm.localGet(b));
      out.writeByte(Wasm32.i32GreaterThanOrEqualsUnsigned);
      out.write(Wasm.brIf(context.controlDepth - brk));
      // ch = src[a] ; if (!isWs(ch)) break
      out.write(Wasm.localGet(src));
      out.write(Wasm32.i32Const(4));
      out.writeByte(Wasm32.i32Add);
      out.write(Wasm.localGet(a));
      out.writeByte(Wasm32.i32Add);
      out.write(Wasm32.i32Load8U());
      out.write(Wasm.localSet(ch));
      _emitCharIsWhitespace(out, ch);
      out.writeByte(Wasm32.i32EqualsToZero); // !isWs
      out.write(Wasm.brIf(context.controlDepth - brk));
      // a++
      out.write(Wasm.localGet(a));
      out.write(Wasm32.i32Const(1));
      out.writeByte(Wasm32.i32Add);
      out.write(Wasm.localSet(a));
      out.write(Wasm.br(context.controlDepth - rpt));
      out.writeByte(Wasm.end);
      context.controlDepth--;
      out.writeByte(Wasm.end);
      context.controlDepth--;
    }

    if (right) {
      // while (b > a && isWs(src[b-1])) b--
      out.write(Wasm.block(WasmType.voidType));
      context.controlDepth++;
      final brk = context.controlDepth;
      out.write(Wasm.loop(WasmType.voidType));
      context.controlDepth++;
      final rpt = context.controlDepth;
      // if (b <= a) break
      out.write(Wasm.localGet(b));
      out.write(Wasm.localGet(a));
      out.writeByte(Wasm32.i32LessThanOrEqualsUnsigned);
      out.write(Wasm.brIf(context.controlDepth - brk));
      // ch = src[b-1] ; if (!isWs(ch)) break
      out.write(Wasm.localGet(src));
      out.write(Wasm32.i32Const(4));
      out.writeByte(Wasm32.i32Add);
      out.write(Wasm.localGet(b));
      out.write(Wasm32.i32Const(1));
      out.writeByte(Wasm32.i32Subtract);
      out.writeByte(Wasm32.i32Add);
      out.write(Wasm32.i32Load8U());
      out.write(Wasm.localSet(ch));
      _emitCharIsWhitespace(out, ch);
      out.writeByte(Wasm32.i32EqualsToZero);
      out.write(Wasm.brIf(context.controlDepth - brk));
      // b--
      out.write(Wasm.localGet(b));
      out.write(Wasm32.i32Const(1));
      out.writeByte(Wasm32.i32Subtract);
      out.write(Wasm.localSet(b));
      out.write(Wasm.br(context.controlDepth - rpt));
      out.writeByte(Wasm.end);
      context.controlDepth--;
      out.writeByte(Wasm.end);
      context.controlDepth--;
    }

    // newLen = b - a ; dest = alloc(newLen+4) ; copy [a, b)
    out.write(Wasm.localGet(b));
    out.write(Wasm.localGet(a));
    out.writeByte(Wasm32.i32Subtract);
    out.write(Wasm.localSet(newLen));
    out.write(Wasm.localGet(newLen));
    out.write(Wasm32.i32Const(4));
    out.writeByte(Wasm32.i32Add);
    _emitInlineAlloc(out, context);
    out.write(Wasm.localSet(dest));
    out.write(Wasm.localGet(dest));
    out.write(Wasm.localGet(newLen));
    out.write(Wasm32.i32Store());
    // memory.copy(dest+4, src+4+a, newLen)
    out.write(Wasm.localGet(dest));
    out.write(Wasm32.i32Const(4));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localGet(src));
    out.write(Wasm32.i32Const(4));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localGet(a));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localGet(newLen));
    out.write(Wasm.memoryCopy);

    out.write(Wasm.localGet(dest));
    context.stackPush(_astTypeString, "$varName.trim");
    context.assertStackLength(s0 + 1, "After String.trim");
    return out;
  }

  /// `s.padLeft(width, [pad])` / `s.padRight(width, [pad])`: returns a fresh
  /// String padded to at least [width] bytes with the first byte of `pad`
  /// (default space). A single-byte pad is assumed (the common case).
  BytesOutput _generateStringPad(
    ({ASTType type, int index}) recv,
    String varName,
    List<ASTExpression> args, {
    required bool left,
    required BytesOutput out,
    required WasmContext context,
  }) {
    var module = context.module!;
    module.requiresMemory = true;
    module.requiresHeapGlobal = true;
    final s0 = context.stackLength;

    var src = context.scratchLocal(_astTypeString, 60);
    var srcLen = context.scratchLocal(_astTypeString, 61);
    var width = context.scratchLocal(_astTypeString, 62);
    var padCh = context.scratchLocal(_astTypeString, 63);
    var padCount = context.scratchLocal(_astTypeString, 64);
    var dest = context.scratchLocal(_astTypeString, 65);
    var newLen = context.scratchLocal(_astTypeString, 66);
    var k = context.scratchLocal(_astTypeString, 67);

    // width = arg0 ; padCh = arg1[0] or ' '
    generateASTExpression(args[0], out: out, context: context);
    context.stackDrop();
    out.writeByte(Wasm64.i64WrapToi32);
    out.write(Wasm.localSet(width));
    if (args.length >= 2) {
      generateASTExpression(args[1], out: out, context: context);
      context.stackDrop();
      out.write(Wasm32.i32Const(4));
      out.writeByte(Wasm32.i32Add);
      out.write(Wasm32.i32Load8U()); // pad[0]
      out.write(Wasm.localSet(padCh));
    } else {
      out.write(Wasm32.i32Const(0x20));
      out.write(Wasm.localSet(padCh));
    }

    _localVariableGet(out, context, recv.index, varName);
    out.write(Wasm.localSet(src));
    out.write(Wasm.localGet(src));
    out.write(Wasm32.i32Load());
    out.write(Wasm.localSet(srcLen));

    // padCount = (width > srcLen) ? width - srcLen : 0
    out.write(Wasm.localGet(width));
    out.write(Wasm.localGet(srcLen));
    out.writeByte(Wasm32.i32Subtract);
    out.write(Wasm32.i32Const(0));
    out.write(Wasm.localGet(width));
    out.write(Wasm.localGet(srcLen));
    out.writeByte(Wasm32.i32GreaterThanUnsigned);
    out.writeByte(Wasm.select); // (width>srcLen) ? (width-srcLen) : 0
    out.write(Wasm.localSet(padCount));

    // newLen = srcLen + padCount ; dest = alloc(newLen+4)
    out.write(Wasm.localGet(srcLen));
    out.write(Wasm.localGet(padCount));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localSet(newLen));
    out.write(Wasm.localGet(newLen));
    out.write(Wasm32.i32Const(4));
    out.writeByte(Wasm32.i32Add);
    _emitInlineAlloc(out, context);
    out.write(Wasm.localSet(dest));
    out.write(Wasm.localGet(dest));
    out.write(Wasm.localGet(newLen));
    out.write(Wasm32.i32Store());

    // Copy the source bytes to their position (offset padCount for padLeft).
    out.write(Wasm.localGet(dest));
    out.write(Wasm32.i32Const(4));
    out.writeByte(Wasm32.i32Add);
    if (left) {
      out.write(Wasm.localGet(padCount));
      out.writeByte(Wasm32.i32Add);
    }
    out.write(Wasm.localGet(src));
    out.write(Wasm32.i32Const(4));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localGet(srcLen));
    out.write(Wasm.memoryCopy);

    // Fill the pad bytes: k = 0 ; while (k < padCount) dest[base+k] = padCh.
    // base = padLeft ? dest+4 : dest+4+srcLen.
    out.write(Wasm32.i32Const(0));
    out.write(Wasm.localSet(k));
    out.write(Wasm.block(WasmType.voidType));
    context.controlDepth++;
    final brk = context.controlDepth;
    out.write(Wasm.loop(WasmType.voidType));
    context.controlDepth++;
    final rpt = context.controlDepth;
    out.write(Wasm.localGet(k));
    out.write(Wasm.localGet(padCount));
    out.writeByte(Wasm32.i32GreaterThanOrEqualsUnsigned);
    out.write(Wasm.brIf(context.controlDepth - brk));
    // addr = dest + 4 + (left ? 0 : srcLen) + k
    out.write(Wasm.localGet(dest));
    out.write(Wasm32.i32Const(4));
    out.writeByte(Wasm32.i32Add);
    if (!left) {
      out.write(Wasm.localGet(srcLen));
      out.writeByte(Wasm32.i32Add);
    }
    out.write(Wasm.localGet(k));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localGet(padCh));
    out.write(Wasm32.i32Store8());
    out.write(Wasm.localGet(k));
    out.write(Wasm32.i32Const(1));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localSet(k));
    out.write(Wasm.br(context.controlDepth - rpt));
    out.writeByte(Wasm.end);
    context.controlDepth--;
    out.writeByte(Wasm.end);
    context.controlDepth--;

    out.write(Wasm.localGet(dest));
    context.stackPush(_astTypeString, "$varName.pad");
    context.assertStackLength(s0 + 1, "After String.pad");
    return out;
  }

  /// `s.codeUnitAt(i)` -> the (unsigned) byte at `s + 4 + i` as an `int` (i64).
  BytesOutput _generateStringCodeUnitAt(
    ({ASTType type, int index}) recv,
    String varName,
    ASTExpression indexExpr, {
    required BytesOutput out,
    required WasmContext context,
  }) {
    context.module!.requiresMemory = true;
    final s0 = context.stackLength;
    _localVariableGet(out, context, recv.index, varName); // src ptr
    out.write(Wasm32.i32Const(4));
    out.writeByte(Wasm32.i32Add);
    generateASTExpression(indexExpr, out: out, context: context); // index (i64)
    context.stackDrop();
    out.writeByte(Wasm64.i64WrapToi32);
    out.writeByte(Wasm32.i32Add); // src + 4 + index
    out.write(Wasm32.i32Load8U());
    out.writeByte(Wasm32.i32ExtendToI64Unsigned);
    context.stackPush(_astTypeInt64, "$varName.codeUnitAt");
    context.assertStackLength(s0 + 1, "After String.codeUnitAt");
    return out;
  }

  /// `s.substring(start, [end])` -> a fresh String holding the byte slice
  /// `[start, end)` (end defaults to the length).
  BytesOutput _generateStringSubstring(
    ({ASTType type, int index}) recv,
    String varName,
    List<ASTExpression> args, {
    required BytesOutput out,
    required WasmContext context,
  }) {
    var module = context.module!;
    module.requiresMemory = true;
    module.requiresHeapGlobal = true;
    final s0 = context.stackLength;

    var src = context.scratchLocal(_astTypeString, 30);
    var srcLen = context.scratchLocal(_astTypeString, 31);
    var startL = context.scratchLocal(_astTypeString, 32);
    var endL = context.scratchLocal(_astTypeString, 33);
    var dest = context.scratchLocal(_astTypeString, 34);
    var newLen = context.scratchLocal(_astTypeString, 35);

    // src = recv ; srcLen = load(src, 0)
    _localVariableGet(out, context, recv.index, varName);
    out.write(Wasm.localSet(src));
    out.write(Wasm.localGet(src));
    out.write(Wasm32.i32Load());
    out.write(Wasm.localSet(srcLen));

    // start = arg0 (i64 -> i32)
    generateASTExpression(args[0], out: out, context: context);
    context.stackDrop();
    out.writeByte(Wasm64.i64WrapToi32);
    out.write(Wasm.localSet(startL));

    // end = arg1 if present, else srcLen
    if (args.length >= 2) {
      generateASTExpression(args[1], out: out, context: context);
      context.stackDrop();
      out.writeByte(Wasm64.i64WrapToi32);
      out.write(Wasm.localSet(endL));
    } else {
      out.write(Wasm.localGet(srcLen));
      out.write(Wasm.localSet(endL));
    }

    // newLen = end - start
    out.write(Wasm.localGet(endL));
    out.write(Wasm.localGet(startL));
    out.writeByte(Wasm32.i32Subtract);
    out.write(Wasm.localSet(newLen));

    // dest = alloc(newLen + 4) ; store newLen at dest[0]
    out.write(Wasm.localGet(newLen));
    out.write(Wasm32.i32Const(4));
    out.writeByte(Wasm32.i32Add);
    _emitInlineAlloc(out, context);
    out.write(Wasm.localSet(dest));
    out.write(Wasm.localGet(dest));
    out.write(Wasm.localGet(newLen));
    out.write(Wasm32.i32Store());

    // memory.copy(dest + 4, src + 4 + start, newLen)
    out.write(Wasm.localGet(dest));
    out.write(Wasm32.i32Const(4));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localGet(src));
    out.write(Wasm32.i32Const(4));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localGet(startL));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localGet(newLen));
    out.write(Wasm.memoryCopy);

    out.write(Wasm.localGet(dest));
    context.stackPush(_astTypeString, "$varName.substring");
    context.assertStackLength(s0 + 1, "After String.substring");
    return out;
  }

  /// `s.startsWith(p)` / `s.endsWith(p)` -> a `bool` (i32): whether the pattern's
  /// bytes match at the start (or end) of the receiver.
  BytesOutput _generateStringStartsEndsWith(
    ({ASTType type, int index}) recv,
    String varName,
    ASTExpression argExpr, {
    required bool ends,
    required BytesOutput out,
    required WasmContext context,
  }) {
    context.module!.requiresMemory = true;
    final s0 = context.stackLength;

    var src = context.scratchLocal(_astTypeString, 36);
    var srcLen = context.scratchLocal(_astTypeString, 37);
    var sub = context.scratchLocal(_astTypeString, 38);
    var subLen = context.scratchLocal(_astTypeString, 39);
    var aAddr = context.scratchLocal(_astTypeString, 40);
    var bAddr = context.scratchLocal(_astTypeString, 41);
    var res = context.scratchLocal(_astTypeString, 42);
    var j = context.scratchLocal(_astTypeString, 43);

    // sub = eval(arg) ; src = recv
    generateASTExpression(argExpr, out: out, context: context);
    context.stackDrop();
    out.write(Wasm.localSet(sub));
    _localVariableGet(out, context, recv.index, varName);
    out.write(Wasm.localSet(src));
    out.write(Wasm.localGet(src));
    out.write(Wasm32.i32Load());
    out.write(Wasm.localSet(srcLen));
    out.write(Wasm.localGet(sub));
    out.write(Wasm32.i32Load());
    out.write(Wasm.localSet(subLen));

    // bAddr = sub + 4
    out.write(Wasm.localGet(sub));
    out.write(Wasm32.i32Const(4));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localSet(bAddr));
    // aAddr = src + 4 (+ srcLen - subLen for endsWith)
    out.write(Wasm.localGet(src));
    out.write(Wasm32.i32Const(4));
    out.writeByte(Wasm32.i32Add);
    if (ends) {
      out.write(Wasm.localGet(srcLen));
      out.write(Wasm.localGet(subLen));
      out.writeByte(Wasm32.i32Subtract);
      out.writeByte(Wasm32.i32Add);
    }
    out.write(Wasm.localSet(aAddr));

    // res = 0 ; only compare when the pattern fits (guards an OOB read).
    out.write(Wasm32.i32Const(0));
    out.write(Wasm.localSet(res));
    out.write(Wasm.localGet(subLen));
    out.write(Wasm.localGet(srcLen));
    out.writeByte(Wasm32.i32LessThanOrEqualsUnsigned);
    out.write(Wasm.ifInstruction(WasmType.voidType));
    _emitBytesEqualNoBreak(
      out,
      context,
      aLoc: aAddr,
      bLoc: bAddr,
      lenLoc: subLen,
      jLoc: j,
      outLoc: res,
    );
    out.writeByte(Wasm.end); // if

    out.write(Wasm.localGet(res));
    context.stackPush(
      _astTypeInt32,
      "$varName.${ends ? 'endsWith' : 'startsWith'}",
    );
    context.assertStackLength(s0 + 1, "After String.startsWith/endsWith");
    return out;
  }

  /// `s.indexOf(p)` -> the first byte offset where `p` occurs (or `-1`), as an
  /// `int` (i64); or, when [asContains], `s.contains(p)` as a `bool` (i32).
  BytesOutput _generateStringIndexOf(
    ({ASTType type, int index}) recv,
    String varName,
    ASTExpression argExpr, {
    required bool asContains,
    required BytesOutput out,
    required WasmContext context,
  }) {
    context.module!.requiresMemory = true;
    final s0 = context.stackLength;

    var src = context.scratchLocal(_astTypeString, 44);
    var srcLen = context.scratchLocal(_astTypeString, 45);
    var sub = context.scratchLocal(_astTypeString, 46);
    var subLen = context.scratchLocal(_astTypeString, 47);
    var iL = context.scratchLocal(_astTypeString, 48);
    var match = context.scratchLocal(_astTypeString, 49);
    var j = context.scratchLocal(_astTypeString, 50);
    var result = context.scratchLocal(_astTypeString, 51);
    var aAddr = context.scratchLocal(_astTypeString, 52);
    var bAddr = context.scratchLocal(_astTypeString, 53);

    // sub = eval(arg) ; src = recv
    generateASTExpression(argExpr, out: out, context: context);
    context.stackDrop();
    out.write(Wasm.localSet(sub));
    _localVariableGet(out, context, recv.index, varName);
    out.write(Wasm.localSet(src));
    out.write(Wasm.localGet(src));
    out.write(Wasm32.i32Load());
    out.write(Wasm.localSet(srcLen));
    out.write(Wasm.localGet(sub));
    out.write(Wasm32.i32Load());
    out.write(Wasm.localSet(subLen));

    // bAddr = sub + 4 ; result = -1 ; i = 0
    out.write(Wasm.localGet(sub));
    out.write(Wasm32.i32Const(4));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localSet(bAddr));
    out.write(Wasm32.i32Const(-1));
    out.write(Wasm.localSet(result));
    out.write(Wasm32.i32Const(0));
    out.write(Wasm.localSet(iL));

    // block { loop { ... } } scanning positions i = 0..srcLen-subLen.
    out.write(Wasm.block(WasmType.voidType));
    context.controlDepth++;
    final breakLevel = context.controlDepth;
    out.write(Wasm.loop(WasmType.voidType));
    context.controlDepth++;
    final repeatLevel = context.controlDepth;

    // if (i + subLen > srcLen) break — no room for a match.
    out.write(Wasm.localGet(iL));
    out.write(Wasm.localGet(subLen));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localGet(srcLen));
    out.writeByte(Wasm32.i32GreaterThanUnsigned);
    out.write(Wasm.brIf(context.controlDepth - breakLevel));

    // aAddr = src + 4 + i ; match = (subLen bytes at aAddr == bAddr)
    out.write(Wasm.localGet(src));
    out.write(Wasm32.i32Const(4));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localGet(iL));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localSet(aAddr));
    _emitBytesEqualNoBreak(
      out,
      context,
      aLoc: aAddr,
      bLoc: bAddr,
      lenLoc: subLen,
      jLoc: j,
      outLoc: match,
    );

    // result = match ? i : result ; break when matched.
    out.write(Wasm.localGet(iL));
    out.write(Wasm.localGet(result));
    out.write(Wasm.localGet(match));
    out.writeByte(Wasm.select);
    out.write(Wasm.localSet(result));
    out.write(Wasm.localGet(match));
    out.write(Wasm.brIf(context.controlDepth - breakLevel));

    // i++ ; repeat
    out.write(Wasm.localGet(iL));
    out.write(Wasm32.i32Const(1));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localSet(iL));
    out.write(Wasm.br(context.controlDepth - repeatLevel));

    out.writeByte(Wasm.end); // loop
    context.controlDepth--;
    out.writeByte(Wasm.end); // block
    context.controlDepth--;

    if (asContains) {
      out.write(Wasm.localGet(result));
      out.write(Wasm32.i32Const(-1));
      out.writeByte(Wasm32.i32NotEquals);
      context.stackPush(_astTypeInt32, "$varName.contains");
    } else {
      out.write(Wasm.localGet(result));
      out.writeByte(Wasm32.i32ExtendToI64Signed); // -1 stays -1
      context.stackPush(_astTypeInt64, "$varName.indexOf");
    }
    context.assertStackLength(s0 + 1, "After String.indexOf/contains");
    return out;
  }

  /// Emits a byte-compare loop: sets [outLoc] to 1 if the [lenLoc] bytes at
  /// address [aLoc] equal those at [bLoc], else 0 (AND-accumulated, no early
  /// exit, so it never branches out of an enclosing `if`). [jLoc] is a scratch
  /// counter. The caller must guarantee both ranges are in-bounds.
  void _emitBytesEqualNoBreak(
    BytesOutput out,
    WasmContext context, {
    required int aLoc,
    required int bLoc,
    required int lenLoc,
    required int jLoc,
    required int outLoc,
  }) {
    out.write(Wasm32.i32Const(1));
    out.write(Wasm.localSet(outLoc));
    out.write(Wasm32.i32Const(0));
    out.write(Wasm.localSet(jLoc));

    out.write(Wasm.block(WasmType.voidType));
    context.controlDepth++;
    final breakLevel = context.controlDepth;
    out.write(Wasm.loop(WasmType.voidType));
    context.controlDepth++;
    final repeatLevel = context.controlDepth;

    // if (j >= len) break
    out.write(Wasm.localGet(jLoc));
    out.write(Wasm.localGet(lenLoc));
    out.writeByte(Wasm32.i32GreaterThanOrEqualsUnsigned);
    out.write(Wasm.brIf(context.controlDepth - breakLevel));

    // out = out & (load8(a + j) == load8(b + j))
    out.write(Wasm.localGet(outLoc));
    out.write(Wasm.localGet(aLoc));
    out.write(Wasm.localGet(jLoc));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm32.i32Load8U());
    out.write(Wasm.localGet(bLoc));
    out.write(Wasm.localGet(jLoc));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm32.i32Load8U());
    out.writeByte(Wasm32.i32Equals);
    out.writeByte(Wasm32.i32BitwiseAnd);
    out.write(Wasm.localSet(outLoc));

    // j++ ; repeat
    out.write(Wasm.localGet(jLoc));
    out.write(Wasm32.i32Const(1));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localSet(jLoc));
    out.write(Wasm.br(context.controlDepth - repeatLevel));

    out.writeByte(Wasm.end); // loop
    context.controlDepth--;
    out.writeByte(Wasm.end); // block
    context.controlDepth--;
  }

  BytesOutput _generateStringCaseConvert(
    ({ASTType type, int index}) localVar,
    String varName, {
    required bool upper,
    required BytesOutput out,
    required WasmContext context,
  }) {
    var module = context.module;
    if (module == null) {
      throw StateError("Can't transform a String without a module.");
    }
    module.requiresMemory = true;
    module.requiresHeapGlobal = true;

    final s0 = context.stackLength;

    // i32 scratch locals (distinct slots from concat/for-each to avoid clashes).
    var src = context.scratchLocal(_astTypeString, 20);
    var dest = context.scratchLocal(_astTypeString, 21);
    var len = context.scratchLocal(_astTypeString, 22);
    var i = context.scratchLocal(_astTypeString, 23);
    var ch = context.scratchLocal(_astTypeString, 24);

    // src = receiver ; len = load(src, 0)
    _localVariableGet(out, context, localVar.index, varName);
    out.write(Wasm.localSet(src));
    out.write(Wasm.localGet(src));
    out.write(Wasm32.i32Load());
    out.write(Wasm.localSet(len));

    // dest = alloc(len + 4) ; store len at dest[0]
    out.write(Wasm.localGet(len));
    out.write(Wasm32.i32Const(4));
    out.writeByte(Wasm32.i32Add);
    _emitInlineAlloc(out, context);
    out.write(Wasm.localSet(dest));
    out.write(Wasm.localGet(dest));
    out.write(Wasm.localGet(len));
    out.write(Wasm32.i32Store());

    // i = 0
    out.write(Wasm32.i32Const(0));
    out.write(Wasm.localSet(i));

    // block(break) { loop(repeat) { if (i>=len) break; <copy+shift>; i++; repeat } }
    out.write(Wasm.block(WasmType.voidType), description: "[OP] block (case)");
    context.controlDepth++;
    final breakLevel = context.controlDepth;
    out.write(Wasm.loop(WasmType.voidType), description: "[OP] loop (case)");
    context.controlDepth++;
    final repeatLevel = context.controlDepth;

    out.write(Wasm.localGet(i));
    out.write(Wasm.localGet(len));
    out.writeByte(Wasm32.i32GreaterThanOrEqualsUnsigned);
    out.write(Wasm.brIf(context.controlDepth - breakLevel));

    // ch = load8_u(src + 4 + i)
    out.write(Wasm.localGet(src));
    out.write(Wasm32.i32Const(4));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localGet(i));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm32.i32Load8U());
    out.write(Wasm.localSet(ch));

    // if (ch in [lo..hi]) ch += /-= 0x20
    final lo = upper ? 0x61 : 0x41; // 'a' / 'A'
    final hi = upper ? 0x7A : 0x5A; // 'z' / 'Z'
    out.write(Wasm.localGet(ch));
    out.write(Wasm32.i32Const(lo));
    out.writeByte(Wasm32.i32GreaterThanOrEqualsUnsigned);
    out.write(Wasm.localGet(ch));
    out.write(Wasm32.i32Const(hi));
    out.writeByte(Wasm32.i32LessThanOrEqualsUnsigned);
    out.writeByte(Wasm32.i32BitwiseAnd);
    out.write(Wasm.ifInstruction(WasmType.voidType));
    out.write(Wasm.localGet(ch));
    out.write(Wasm32.i32Const(0x20));
    out.writeByte(upper ? Wasm32.i32Subtract : Wasm32.i32Add);
    out.write(Wasm.localSet(ch));
    out.writeByte(Wasm.end);

    // store8(dest + 4 + i, ch)
    out.write(Wasm.localGet(dest));
    out.write(Wasm32.i32Const(4));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localGet(i));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localGet(ch));
    out.write(Wasm32.i32Store8());

    // i++ ; repeat
    out.write(Wasm.localGet(i));
    out.write(Wasm32.i32Const(1));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localSet(i));
    out.write(Wasm.br(context.controlDepth - repeatLevel));

    out.writeByte(Wasm.end); // loop
    context.controlDepth--;
    out.writeByte(Wasm.end); // block
    context.controlDepth--;

    // Result pointer.
    out.write(Wasm.localGet(dest));
    context.stackPush(
      _astTypeString,
      "$varName.${upper ? 'toUpperCase' : 'toLowerCase'}",
    );
    context.assertStackLength(s0 + 1, "After String case convert");
    return out;
  }

  /// Grow-aware bump allocation, emitted inline: consumes `[size]` on the stack
  /// and leaves `[ptr]`, growing the memory if `$hp + size` would overflow.
  /// (Mirrors the exported `__alloc`; used by string concatenation.)
  void _emitInlineAlloc(BytesOutput out, WasmContext context) {
    const hp = WasmModuleContext.heapGlobalIndex;
    var sz = context.scratchLocal(_astTypeString, 3);
    var newHp = context.scratchLocal(_astTypeString, 4);
    var delta = context.scratchLocal(_astTypeString, 5);

    out.write(Wasm.localSet(sz));

    // newHp = $hp + size
    out.write(Wasm.globalGet(hp));
    out.write(Wasm.localGet(sz));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localSet(newHp));

    // delta = ceil(newHp / 64KiB) - memory.size
    out.write(Wasm.localGet(newHp));
    out.write(Wasm32.i32Const(65535));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm32.i32Const(16));
    out.writeByte(Wasm32.i32ShiftRightUnsigned);
    out.write(Wasm.memorySize);
    out.writeByte(Wasm32.i32Subtract);
    out.write(Wasm.localSet(delta));

    // if (delta > 0) memory.grow(delta)
    out.write(Wasm.localGet(delta));
    out.write(Wasm32.i32Const(0));
    out.writeByte(Wasm32.i32GreaterThanSigned);
    out.write(Wasm.ifInstruction(WasmType.voidType));
    out.write(Wasm.localGet(delta));
    out.write(Wasm.memoryGrow);
    out.writeByte(Wasm.drop);
    out.writeByte(Wasm.end);

    // result = $hp; $hp = newHp  (leaves [ptr])
    out.write(Wasm.globalGet(hp));
    out.write(Wasm.localGet(newHp));
    out.write(Wasm.globalSet(hp));
  }

  @override
  BytesOutput generateASTValueVar(ASTValueVar value, {BytesOutput? out}) {
    // TODO: implement generateASTValueVar
    throw UnimplementedError('generateASTValueVar');
  }

  @override
  BytesOutput generateASTVariable(
    ASTVariable variable, {
    String? callingFunction,
    BytesOutput? out,
  }) {
    // TODO: implement generateASTVariable
    throw UnimplementedError('generateASTVariable');
  }

  @override
  BytesOutput generateASTVariableGeneric(
    ASTVariable variable, {
    String? callingFunction,
    BytesOutput? out,
  }) {
    // TODO: implement generateASTVariableGeneric
    throw UnimplementedError('generateASTVariableGeneric');
  }

  @override
  String resolveASTExpressionOperatorText(
    ASTExpressionOperator operator,
    ASTNumType aNumType,
    ASTNumType bNumType,
  ) {
    // TODO: implement resolveASTExpressionOperatorText
    throw UnimplementedError('resolveASTExpressionOperatorText');
  }

  @override
  StringBuffer generateASTExpressionLocalGetterAccess(
    ASTExpressionLocalGetterAccess expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    // TODO: implement generateASTExpressionLocalGetterAccess
    throw UnimplementedError();
  }

  @override
  StringBuffer generateASTExpressionObjectGetterAccess(
    ASTExpressionObjectGetterAccess expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    // TODO: implement generateASTExpressionObjectGetterAccess
    throw UnimplementedError();
  }
}

/// An imported (host-provided) Wasm function. Occupies a function index in
/// `0..importCount-1`, before any module-defined function.
class WasmImportedFunction {
  final String module;
  final String name;
  final List<WasmType> params;
  final List<WasmType> results;

  WasmImportedFunction(this.module, this.name, this.params, this.results);
}

/// A generator-synthesized module function (e.g. the `__alloc` bump allocator),
/// placed in the function index space after the user-defined functions.
class WasmSynthFunction {
  final String name;
  final List<WasmType> params;
  final List<WasmType> results;

  /// The complete code body (locals vector + instructions + `end`), or null
  /// when [bodyBuilder] defers body generation.
  final BytesOutput? body;

  /// Deferred body generator. Used when the body bakes in function-call indices
  /// that depend on the final `importCount` (e.g. an enum-entry init that calls
  /// the enum constructor): the synth function's *index* is registered eagerly
  /// (during the import-discovery pass), but its *body* is materialized only
  /// once all host imports have been registered, so call indices are correct.
  final BytesOutput Function()? bodyBuilder;

  final bool exported;

  WasmSynthFunction(
    this.name,
    this.params,
    this.results,
    this.body, {
    this.bodyBuilder,
    this.exported = false,
  });

  /// The body bytes, generating them on demand via [bodyBuilder] if deferred.
  BytesOutput materializeBody() => body ?? bodyBuilder!();
}

/// Memory layout of a class instance: field byte [offsets] (declaration order),
/// field [types], and total [size]. An instance is an i32 pointer to a heap
/// struct holding the fields at these offsets (int/double -> 8B, everything
/// else -> 4B i32).
class WasmClassLayout {
  final String className;
  final Map<String, int> offsets;
  final Map<String, ASTType> types;
  final int size;

  WasmClassLayout(this.className, this.offsets, this.types, this.size);
}

/// A captured variable of a closure: its [name], [type] and byte [offset]
/// within the closure's heap environment struct.
typedef WasmCapture = ({String name, ASTType type, int offset});

/// Compile-time info for an anonymous function (closure). A closure value is an
/// i32 pointer to a heap struct laid out as `[tableSlot@0, capture0, ...]`; the
/// closure function takes that pointer as a hidden first parameter (`env`) and
/// reads its captured variables from it.
class WasmClosureInfo {
  final ASTFunctionDeclaration function;

  /// Concrete return type (the declared one may be `dynamic`).
  final ASTType returnType;

  /// Concrete parameter types (the declared ones may be `dynamic` / untyped),
  /// in declaration order, inferred from the function-typed parameter the
  /// closure is passed to.
  final List<ASTType> paramTypes;

  /// Captured (free) variables, with their env-struct offsets.
  final List<WasmCapture> captures;

  /// Total size of the environment struct in bytes (`4` for the table slot plus
  /// each capture's size).
  final int envSize;

  /// The function-table slot (the closure's dispatch index).
  final int slot;

  WasmClosureInfo(
    this.function,
    this.returnType,
    this.paramTypes,
    this.captures,
    this.envSize,
    this.slot,
  );
}

/// A synthesized module function wrapping a class constructor. Its Wasm
/// signature takes the constructor's value parameters and returns an i32 object
/// pointer; codegen allocates the struct, stores fields, runs the body and
/// returns `this` (see `generateClassConstructorFunction`).
class _WasmConstructorFunction extends ASTFunctionDeclaration {
  final ASTClassNormal clazz;
  final ASTClassConstructorDeclaration ctor;

  _WasmConstructorFunction(
    this.clazz,
    this.ctor,
    ASTFunctionParametersDeclaration parameters,
  ) : super(
        clazz.name,
        parameters,
        clazz.type,
        modifiers: ASTModifiers(isPrivate: true),
      );
}

/// A synthesized module function wrapping a class instance method. Its Wasm
/// signature takes `this` (i32) as the first parameter followed by the method's
/// declared parameters (see `generateClassMethodFunction`).
class _WasmMethodFunction extends ASTFunctionDeclaration {
  final ASTClassNormal clazz;
  final ASTClassFunctionDeclaration method;

  _WasmMethodFunction(
    this.clazz,
    this.method,
    String name,
    ASTFunctionParametersDeclaration parameters,
    ASTType returnType, {
    super.block,
  }) : super(
         name,
         parameters,
         returnType,
         modifiers: ASTModifiers(isPrivate: true),
       );
}

/// A synthesized module function wrapping a `static` class method. Unlike
/// [_WasmMethodFunction] it does NOT take a `this` parameter and is left
/// non-private, so it is exported (under the qualified `Class.method` name) and
/// callable directly by the host. Its body is generated by the generic
/// [WasmGenerator.generateASTFunctionDeclaration] path (no `this`/`classLayout`
/// in scope).
class _WasmStaticMethodFunction extends ASTFunctionDeclaration {
  final ASTClassNormal clazz;
  final ASTClassFunctionDeclaration method;

  _WasmStaticMethodFunction(
    this.clazz,
    this.method,
    String name,
    ASTFunctionParametersDeclaration parameters,
    ASTType returnType, {
    super.block,
  }) : super(name, parameters, returnType);
}

/// Module-level Wasm codegen state shared across all functions: the function
/// index space (imports + defined functions) and the static data region
/// (interned string literals).
class WasmModuleContext {
  /// Module-defined functions, in index order (placed after any imports).
  /// Includes top-level functions plus synthesized class constructors
  /// ([_WasmConstructorFunction]) and methods ([_WasmMethodFunction]).
  final List<ASTFunctionDeclaration> functions;

  /// Field memory layout for each class, keyed by class name.
  final Map<String, WasmClassLayout> classLayouts;

  /// The class declarations, keyed by name — used to walk the `extends` chain
  /// when resolving inherited members and `super` dispatch.
  final Map<String, ASTClassNormal> classDeclarations;

  WasmModuleContext(
    this.functions, {
    this.classLayouts = const {},
    this.classDeclarations = const {},
  });

  /// The field layout of the class whose instances have type [t], or `null`.
  WasmClassLayout? layoutForType(ASTType t) => classLayouts[t.name];

  /// The name of the direct superclass of [className] (its `extends` target),
  /// or `null` if the class is unknown or has no superclass.
  String? superClassNameOf(String? className) {
    if (className == null) return null;
    return classDeclarations[className]?.superClass?.name;
  }

  /// Whether [className] (or a superclass) declares a user getter named [name].
  /// Distinguishes a getter access from a same-named 0-arg method (a getter is
  /// compiled as a zero-arg method, so `methodIndex` alone can't tell them
  /// apart).
  bool hasGetter(String? className, String name) {
    for (var cn = className; cn != null; cn = superClassNameOf(cn)) {
      if (classDeclarations[cn]?.getGetterWithName(name) != null) return true;
    }
    return false;
  }

  // --- Function table (for closures / function values via `call_indirect`) ---

  /// Functions placed in the module's function table, in table-slot order. A
  /// function value is an i32 pointer to a heap closure struct
  /// `[tableSlot@0, captured0, captured1, ...]`.
  final List<ASTFunctionDeclaration> tableFunctions = [];

  /// Closure info per anonymous-function declaration.
  final Map<ASTFunctionDeclaration, WasmClosureInfo> closures = {};

  /// Per enclosing function, the local/parameter variables captured by a
  /// closure (so they must be "boxed" into a shared heap cell for
  /// capture-by-reference), mapped to their type.
  final Map<ASTFunctionDeclaration, Map<String, ASTType>> boxedVarsByFunction =
      {};

  /// Per enclosing function, the local variables that hold a capture-free
  /// closure called directly only (`var f = (…) => …; f(x)`), mapped to the
  /// closure declaration. Such a variable carries no function value: its
  /// declaration is elided and the call is a direct `call` (no env alloc / no
  /// `call_indirect`).
  final Map<ASTFunctionDeclaration, Map<String, ASTFunctionDeclaration>>
  directClosureVarsByFunction = {};

  /// The direct-closure variables of [f] (see [directClosureVarsByFunction]).
  Map<String, ASTFunctionDeclaration> directClosureVars(
    ASTFunctionDeclaration f,
  ) => directClosureVarsByFunction[f] ?? const {};

  /// Set when a closure value is actually materialized or invoked via
  /// `call_indirect`. A closure that is only ever called directly (see
  /// [directClosureVarsByFunction]) never touches the table, so it stays
  /// `false` and the table / element sections are omitted entirely.
  bool tableUsed = false;

  bool get requiresTable => tableUsed && tableFunctions.isNotEmpty;

  /// Registers an anonymous function (closure), returning its table slot.
  int registerClosure(WasmClosureInfo info) {
    var existing = closures[info.function];
    if (existing != null) return existing.slot;
    tableFunctions.add(info.function);
    closures[info.function] = info;
    return info.slot;
  }

  /// The table slot of the anonymous function [f], or -1.
  int closureSlot(ASTFunctionDeclaration f) => closures[f]?.slot ?? -1;

  /// The closure info for [f], or `null` if [f] is not a closure.
  WasmClosureInfo? closureInfo(ASTFunctionDeclaration f) => closures[f];

  bool isClosure(ASTFunctionDeclaration f) => closures.containsKey(f);

  /// The concrete return type to use for closure [f] (its declared return type
  /// may be `dynamic`), or `null` if [f] is not a closure.
  ASTType? returnTypeOverride(ASTFunctionDeclaration f) =>
      closures[f]?.returnType;

  /// The Wasm function index of a module-defined function [f] (by identity).
  int functionIndexByDeclaration(ASTFunctionDeclaration f) {
    for (var i = 0; i < functions.length; ++i) {
      if (identical(functions[i], f)) return importCount + i;
    }
    return -1;
  }

  /// Finds the type index whose signature matches [paramCodes] → [resultCode]
  /// (a Wasm value-type byte, or `null` for void). Used by `call_indirect`,
  /// which must reference a type index. Reuses an existing function's type
  /// (every callable-by-value function is a module function, so a match
  /// exists). Returns -1 if none matches.
  int typeIndexForSignature(List<int> paramCodes, int? resultCode) {
    var want = _sigKey(paramCodes, resultCode);

    var index = 0;
    for (var imp in importedFunctions) {
      var key = _sigKey(
        imp.params.map((p) => p.value).toList(),
        imp.results.isEmpty ? null : imp.results.first.value,
      );
      if (key == want) return index;
      index++;
    }
    for (var f in functions) {
      var info = closures[f];
      var rt = info?.returnType ?? f.effectiveReturnType;
      // Closures take a hidden env pointer (i32) as their first parameter and
      // use their inferred (concrete) parameter types.
      var params = info != null
          ? [WasmType.i32Type.value, ...info.paramTypes.map((t) => t.wasmCode)]
          : f.parametersTypesWasmCode;
      var key = _sigKey(params, rt.isVoid ? null : rt.wasmCode);
      if (key == want) return index;
      index++;
    }
    for (var s in synthFunctions) {
      var key = _sigKey(
        s.params.map((p) => p.value).toList(),
        s.results.isEmpty ? null : s.results.first.value,
      );
      if (key == want) return index;
      index++;
    }
    return -1;
  }

  static String _sigKey(List<int> paramCodes, int? resultCode) =>
      '${paramCodes.join(',')}>${resultCode ?? ''}';

  /// Stable 1-based id for a class, by class-layout insertion order (0 = not a
  /// known class). Stamped into a boxed `Object` cell (`typeId@4`) when an
  /// instance is boxed, so its `toString()` can be dispatched at runtime.
  int typeIdOf(String className) {
    var id = 0;
    for (var name in classLayouts.keys) {
      id++;
      if (name == className) return id;
    }
    return 0;
  }

  /// Resolves the Wasm function index of class [className]'s method
  /// [methodName] taking [arity] declared arguments (excluding `this`). Walks the
  /// `extends` chain, so an inherited (non-overridden) method resolves to the
  /// superclass function that defines it.
  int? methodIndex(String className, String methodName, int arity) {
    for (String? cn = className; cn != null; cn = superClassNameOf(cn)) {
      for (var i = 0; i < functions.length; ++i) {
        var f = functions[i];
        if (f is _WasmMethodFunction &&
            f.clazz.name == cn &&
            f.method.name == methodName &&
            f.method.parameters.size == arity) {
          return importCount + i;
        }
      }
    }
    return null;
  }

  /// Resolves a class method for a call supplying [suppliedCount] arguments
  /// (excluding `this`), allowing omitted trailing parameters that have default
  /// values: picks the method named [methodName] on [className] with the
  /// smallest declared parameter count that is `>= suppliedCount` (an exact
  /// arity match wins). Returns its Wasm function index, or `null` if none.
  int? methodIndexForCall(
    String className,
    String methodName,
    int suppliedCount,
  ) {
    // Walk the `extends` chain: the most-derived class that declares the method
    // wins (an override), falling back to an inherited superclass method.
    for (String? cn = className; cn != null; cn = superClassNameOf(cn)) {
      int? bestIndex;
      int? bestSize;
      for (var i = 0; i < functions.length; ++i) {
        var f = functions[i];
        if (f is! _WasmMethodFunction ||
            f.clazz.name != cn ||
            f.method.name != methodName) {
          continue;
        }
        var size = f.method.parameters.size;
        if (size < suppliedCount) continue;
        if (bestSize == null || size < bestSize) {
          bestSize = size;
          bestIndex = importCount + i;
        }
      }
      if (bestIndex != null) return bestIndex;
    }
    return null;
  }

  /// Like [methodIndexForCall] but for **static** methods (no receiver):
  /// resolves a bare-name call to a sibling `static` method of [className].
  /// Returns the smallest declared arity `>= suppliedCount` (so omitted
  /// default-valued trailing parameters still resolve).
  int? staticMethodIndexForCall(
    String className,
    String methodName,
    int suppliedCount,
  ) {
    int? bestIndex;
    int? bestSize;
    for (var i = 0; i < functions.length; ++i) {
      var f = functions[i];
      if (f is! _WasmStaticMethodFunction ||
          f.clazz.name != className ||
          f.method.name != methodName) {
        continue;
      }
      var size = f.method.parameters.size;
      if (size < suppliedCount) continue;
      if (bestSize == null || size < bestSize) {
        bestSize = size;
        bestIndex = importCount + i;
      }
    }
    return bestIndex;
  }

  /// The qualified `Class.method` name of a compiled **non-static** (instance)
  /// method whose declared name is [methodName] and arity is [arity], or null if
  /// none. Used to reject a receiver-less call to a non-static method (e.g. a
  /// `static` method calling an instance sibling) with a clear error.
  String? instanceMethodQualifiedName(String methodName, int arity) {
    for (var f in functions) {
      if (f is _WasmMethodFunction &&
          f.method.name == methodName &&
          f.method.parameters.size == arity) {
        return '${f.clazz.name}.${f.method.name}';
      }
    }
    return null;
  }

  // --- Imported functions (function indices 0..importCount-1) ---

  final List<WasmImportedFunction> importedFunctions = [];
  final Map<String, int> _importIndexByKey = {};

  int get importCount => importedFunctions.length;

  /// Registers (or reuses) an imported host function, returning its function
  /// index.
  int registerImportedFunction(
    String module,
    String name,
    List<WasmType> params,
    List<WasmType> results,
  ) {
    var key = '$module $name ${params.length}';
    var existing = _importIndexByKey[key];
    if (existing != null) return existing;

    var index = importedFunctions.length;
    importedFunctions.add(WasmImportedFunction(module, name, params, results));
    _importIndexByKey[key] = index;
    requiresMemory = true;
    return index;
  }

  // --- Synthesized functions (indices importCount + functions.length + j) ---

  final List<WasmSynthFunction> synthFunctions = [];
  final Set<String> _synthNames = {};

  /// Registers a pre-built synthesized function (e.g. an enum entry initializer).
  void addSynthFunction(WasmSynthFunction f) {
    if (_synthNames.contains(f.name)) return;
    synthFunctions.add(f);
    _synthNames.add(f.name);
  }

  // --- Enum entry caches (one mutable i32 global per enum entry) ---

  /// Per-entry global keys (in registration order). Each holds the i32 pointer
  /// of a cached enum entry `const` instance (0 = not yet built). Placed after
  /// the heap-pointer global `$hp` (index 0), so a key's global index is
  /// `1 + its position` here.
  final List<String> _enumEntryGlobals = [];

  /// Number of enum-entry cache globals (emitted after `$hp`).
  int get enumEntryGlobalCount => _enumEntryGlobals.length;

  /// Registers (or reuses) the cache global for enum-entry [key], returning its
  /// Wasm global index. Enum globals follow the heap pointer (index 0) and the
  /// static-field globals (see [registerStaticFieldGlobal]).
  int enumEntryGlobalIndex(String key) {
    var base = 1 + staticFieldGlobalCount;
    var i = _enumEntryGlobals.indexOf(key);
    if (i >= 0) return base + i;
    _enumEntryGlobals.add(key);
    requiresMemory = true;
    requiresHeapGlobal = true; // ensures the Global section is emitted
    return base + (_enumEntryGlobals.length - 1);
  }

  // --- Static field globals (one typed mutable global per `static` field) ---

  /// Static-field globals in index order: each holds the field's value. Placed
  /// right after the heap-pointer global `$hp` (index 0), so a field's global
  /// index is `1 + its position` here. Registered up front at module build
  /// (before any enum globals), so indices are stable.
  final List<({String key, ASTType type, num init})> _staticFieldGlobals = [];
  final Map<String, int> _staticFieldGlobalIndex = {};

  /// Number of static-field globals (emitted after `$hp`, before enum globals).
  int get staticFieldGlobalCount => _staticFieldGlobals.length;

  /// The registered static-field globals, in index order.
  List<({String key, ASTType type, num init})> get staticFieldGlobals =>
      List.unmodifiable(_staticFieldGlobals);

  /// Registers a `static` field global for [key] (`"Class.field"`), returning
  /// its Wasm global index. Idempotent per key.
  int registerStaticFieldGlobal(String key, ASTType type, num init) {
    var existing = _staticFieldGlobalIndex[key];
    if (existing != null) return existing;
    var index = 1 + _staticFieldGlobals.length; // after `$hp` (index 0)
    _staticFieldGlobals.add((key: key, type: type, init: init));
    _staticFieldGlobalIndex[key] = index;
    requiresHeapGlobal = true; // ensures the Global section is emitted
    return index;
  }

  /// The global index of static field [key] (`"Class.field"`), or `null`.
  int? staticFieldGlobalIndexOf(String key) => _staticFieldGlobalIndex[key];

  /// The declared type of static field [key] (`"Class.field"`), or `null`.
  ASTType? staticFieldTypeOf(String key) {
    var idx = _staticFieldGlobalIndex[key];
    return idx == null ? null : _staticFieldGlobals[idx - 1].type;
  }

  /// Ensures the exported `__alloc(i32 size) -> i32 ptr` bump-allocator function
  /// exists. Exported so the host can allocate strings in module memory.
  void ensureAllocFunction() {
    if (_synthNames.contains('__alloc')) return;
    requiresMemory = true;
    requiresHeapGlobal = true;

    // i32 __alloc(i32 size):
    //   newHp = $hp + size
    //   delta = ceil(newHp / 64KiB) - memory.size; if delta > 0: memory.grow
    //   result = $hp; $hp = newHp; return result
    // Locals: 0=size(param), 1=newHp, 2=delta.
    var body = BytesOutput();
    // 1 local group of 2 i32 locals.
    body.write(Leb128.encodeUnsigned(1), description: "Local groups");
    body.write(Leb128.encodeUnsigned(2), description: "i32 locals");
    body.writeByte(WasmType.i32Type.value, description: "i32");

    // newHp = $hp + size
    body.write(Wasm.globalGet(heapGlobalIndex));
    body.write(Wasm.localGet(0));
    body.writeByte(Wasm32.i32Add);
    body.write(Wasm.localSet(1));

    // delta = ((newHp + 65535) >>> 16) - memory.size
    body.write(Wasm.localGet(1));
    body.write(Wasm32.i32Const(65535));
    body.writeByte(Wasm32.i32Add);
    body.write(Wasm32.i32Const(16));
    body.writeByte(Wasm32.i32ShiftRightUnsigned);
    body.write(Wasm.memorySize);
    body.writeByte(Wasm32.i32Subtract);
    body.write(Wasm.localSet(2));

    // if (delta > 0) memory.grow(delta) (dropping the previous-size result)
    body.write(Wasm.localGet(2));
    body.write(Wasm32.i32Const(0));
    body.writeByte(Wasm32.i32GreaterThanSigned);
    body.write(Wasm.ifInstruction(WasmType.voidType));
    body.write(Wasm.localGet(2));
    body.write(Wasm.memoryGrow);
    body.writeByte(Wasm.drop);
    body.writeByte(Wasm.end);

    // result = $hp; $hp = newHp
    body.write(Wasm.globalGet(heapGlobalIndex));
    body.write(Wasm.localGet(1));
    body.write(Wasm.globalSet(heapGlobalIndex));
    body.writeByte(Wasm.end);

    synthFunctions.add(
      WasmSynthFunction(
        '__alloc',
        const [WasmType.i32Type],
        const [WasmType.i32Type],
        body,
        exported: true,
      ),
    );
    _synthNames.add('__alloc');
  }

  /// Ensures the `__streq(i32 a, i32 b) -> i32` helper exists: returns `1` if
  /// the two `[len:i32][utf8]` strings at pointers `a`/`b` are byte-equal, else
  /// `0`. Used for `String`-keyed map lookups. Not exported.
  void ensureStrEqFunction() {
    if (_synthNames.contains('__streq')) return;
    requiresMemory = true;

    // Locals beyond the 2 params: 2=lenA, 3=i.
    var body = BytesOutput();
    body.write(Leb128.encodeUnsigned(1), description: "Local groups");
    body.write(Leb128.encodeUnsigned(2), description: "i32 locals");
    body.writeByte(WasmType.i32Type.value, description: "i32");

    // if (a == b) return 1  (same pointer / interned literal)
    body.write(Wasm.localGet(0));
    body.write(Wasm.localGet(1));
    body.writeByte(Wasm32.i32Equals);
    body.write(Wasm.ifInstruction(WasmType.voidType));
    body.write(Wasm32.i32Const(1));
    body.writeByte(Wasm.functionReturn);
    body.writeByte(Wasm.end);

    // lenA = load(a, 0) ; if (lenA != load(b, 0)) return 0
    body.write(Wasm.localGet(0));
    body.write(Wasm32.i32Load(2, 0));
    body.write(Wasm.localSet(2));
    body.write(Wasm.localGet(2));
    body.write(Wasm.localGet(1));
    body.write(Wasm32.i32Load(2, 0));
    body.writeByte(Wasm32.i32NotEquals);
    body.write(Wasm.ifInstruction(WasmType.voidType));
    body.write(Wasm32.i32Const(0));
    body.writeByte(Wasm.functionReturn);
    body.writeByte(Wasm.end);

    // for (i = 0; i < lenA; i++) if (a[4+i] != b[4+i]) return 0
    body.write(Wasm32.i32Const(0));
    body.write(Wasm.localSet(3));
    body.write(Wasm.block(WasmType.voidType));
    body.write(Wasm.loop(WasmType.voidType));
    body.write(Wasm.localGet(3));
    body.write(Wasm.localGet(2));
    body.writeByte(Wasm32.i32GreaterThanOrEqualsUnsigned);
    body.write(Wasm.brIf(1));
    body.write(Wasm.localGet(0));
    body.write(Wasm.localGet(3));
    body.writeByte(Wasm32.i32Add);
    body.write(Wasm32.i32Load8U(0, 4));
    body.write(Wasm.localGet(1));
    body.write(Wasm.localGet(3));
    body.writeByte(Wasm32.i32Add);
    body.write(Wasm32.i32Load8U(0, 4));
    body.writeByte(Wasm32.i32NotEquals);
    body.write(Wasm.ifInstruction(WasmType.voidType));
    body.write(Wasm32.i32Const(0));
    body.writeByte(Wasm.functionReturn);
    body.writeByte(Wasm.end);
    body.write(Wasm.localGet(3));
    body.write(Wasm32.i32Const(1));
    body.writeByte(Wasm32.i32Add);
    body.write(Wasm.localSet(3));
    body.write(Wasm.br(0));
    body.writeByte(Wasm.end); // loop
    body.writeByte(Wasm.end); // block

    body.write(Wasm32.i32Const(1)); // all bytes matched
    body.writeByte(Wasm.end); // function end

    synthFunctions.add(
      WasmSynthFunction(
        '__streq',
        const [WasmType.i32Type, WasmType.i32Type],
        const [WasmType.i32Type],
        body,
      ),
    );
    _synthNames.add('__streq');
  }

  /// Resolves the Wasm function index of a synthesized function by [name]
  /// (placed after imports and module functions). Returns `null` if absent.
  int? synthFunctionIndex(String name) {
    for (var j = 0; j < synthFunctions.length; ++j) {
      if (synthFunctions[j].name == name) {
        return importCount + functions.length + j;
      }
    }
    return null;
  }

  /// Resolves the Wasm function index for a module-defined function with [name]
  /// and [arity], offset by [importCount]. Returns `null` if not found.
  int? functionIndex(String name, int arity) {
    for (var i = 0; i < functions.length; ++i) {
      var f = functions[i];
      if (f.name == name && f.parameters.size == arity) {
        return importCount + i;
      }
    }
    return null;
  }

  /// Resolves a module function for a call by [name] supplying [suppliedCount]
  /// arguments, allowing omitted trailing parameters that have default values:
  /// picks the function named [name] with the smallest declared parameter count
  /// that is `>= suppliedCount` (an exact arity match wins). Returns its Wasm
  /// function index, or `null` if none. The actual default-filling/validation
  /// happens in `_orderInvocationArguments`.
  int? functionIndexForCall(String name, int suppliedCount) {
    int? bestIndex;
    int? bestSize;
    for (var i = 0; i < functions.length; ++i) {
      var f = functions[i];
      if (f.name != name) continue;
      var size = f.parameters.size;
      if (size < suppliedCount) continue;
      if (bestSize == null || size < bestSize) {
        bestSize = size;
        bestIndex = importCount + i;
      }
    }
    return bestIndex;
  }

  /// Returns the module-defined function at function [index] (accounting for
  /// the imported-function offset); `null` for imported indices.
  ASTFunctionDeclaration? functionByIndex(int index) {
    var i = index - importCount;
    if (i < 0 || i >= functions.length) return null;
    return functions[i];
  }

  // --- Asyncify control region (real `async`/`await` suspension) ---
  //
  // When an `async` function is compiled with real suspension (Asyncify), a
  // small fixed region of low linear memory holds the suspension state. The
  // host driver and the generated code agree on these absolute offsets. Offset
  // `0` stays reserved as the null pointer.
  //
  //   ASY_STATE  (i32 @ 8):  0=normal, 1=unwound(suspended), 2=rewinding
  //   ASY_SP     (i32 @12):  Asyncify frame-stack pointer (byte offset of the
  //                          next free slot); the host driver initializes it to
  //                          [asyncifyStackBase] before the first call.
  //   ASY_RESULT (i64 @16):  the leaf await value, written back by the host
  //   stack      (@24..):    a LIFO of frames; each suspendable function pushes
  //                          `[resume:i32 @+0 (8B)] [local0:i64 @+8] ...` on
  //                          unwind and pops it on rewind. Frames let nested
  //                          async calls (multi-frame) suspend and resume.

  static const int asyncifyBase = 8;
  static const int asyncifyStateOffset = 8;
  static const int asyncifyStackPointerOffset = 12;
  static const int asyncifyResultOffset = 16;
  static const int asyncifyStackBase = 24;

  /// Bytes reserved for the Asyncify control region (state, SP, result, and the
  /// frame stack). 4 KiB allows a deep enough chain of suspended frames.
  static const int asyncifyRegionSize = 4096;

  // --- Exception control region (try/catch/throw) ---
  //
  // `throw` / `try` / `catch` / `finally` lower to a `$pc`-dispatched CFG (like
  // Asyncify), but a thrown value must also unwind *across* function calls: a
  // callee that throws sets EXC_PENDING and returns a default value, and each
  // call site re-checks EXC_PENDING and jumps to its nearest handler (or
  // re-propagates). The thrown value + an in-flight flag live at fixed linear
  // memory offsets, placed just past the Asyncify region (when present) so the
  // absolute offsets never collide.
  //
  //   EXC_PENDING (i32): 1 while an exception is unwinding, else 0
  //   EXC_TAG     (i32): runtime type tag of the thrown value (see `_excTypeTag`)
  //   EXC_VALUE   (i64): marshalled payload (i64 int / f64 bits / i32 pointer)

  /// Whether the module compiled at least one `throw` / `try` / `catch`, and so
  /// reserves the exception control region (and a linear memory).
  bool requiresException = false;

  /// Cached fixed-point set of exception-eligible function names (functions that
  /// use `throw`/`try` or transitively call one); `null` until first computed.
  Set<String>? exceptionEligible;

  /// Bytes reserved for the exception control region (pending flag, type tag,
  /// thrown value).
  static const int exceptionRegionSize = 16;

  /// Base offset of the exception control region: just past the Asyncify region
  /// when that is present, otherwise at the start of low memory.
  int get exceptionBase =>
      asyncifyBase + (requiresAsyncify ? asyncifyRegionSize : 0);

  int get excPendingOffset => exceptionBase + 0;
  int get excTagOffset => exceptionBase + 4;
  int get excValueOffset => exceptionBase + 8;

  /// Whether the module compiled at least one real-suspension `async` function
  /// and therefore reserves the Asyncify control region.
  bool requiresAsyncify = false;

  /// Names of functions compiled with the Asyncify transform (real suspension).
  /// Surfaced in the `apollovm_sig` section so the runner drives them.
  final Set<String> asyncifyFunctionNames = {};

  /// Cached fixed-point set of Asyncify-eligible function names (see
  /// `_asyncifyEligible`); `null` until first computed.
  Set<String>? asyncifyEligible;

  // --- Static data region (interned string literals) ---

  /// Base offset of the static data region in linear memory. Offset `0` is
  /// reserved as a null pointer; when Asyncify is used the static data is
  /// shifted up past the control region so its fixed offsets never collide.
  int get dataBaseOffset {
    var base = 8;
    if (requiresAsyncify) base += asyncifyRegionSize;
    if (requiresException) base += exceptionRegionSize;
    return base;
  }

  final BytesBuilder _data = BytesBuilder();
  final Map<String, int> _literalPointers = {};

  /// Whether the module must declare (and export) a linear memory.
  bool requiresMemory = false;

  /// Interns a string literal as `[len:i32 little-endian][utf8 bytes]` in the
  /// static data region and returns its memory pointer.
  int internStringLiteral(String s) {
    var existing = _literalPointers[s];
    if (existing != null) return existing;

    var ptr = dataBaseOffset + _data.length;
    var bytes = utf8.encode(s);
    _data.add([
      bytes.length & 0xff,
      (bytes.length >> 8) & 0xff,
      (bytes.length >> 16) & 0xff,
      (bytes.length >> 24) & 0xff,
    ]);
    _data.add(bytes);
    _literalPointers[s] = ptr;
    requiresMemory = true;
    return ptr;
  }

  bool get hasData => _data.isNotEmpty;

  /// The static data bytes (placed at [dataBaseOffset]).
  Uint8List get dataBytes => _data.toBytes();

  // --- Heap (bump allocator) ---

  /// Whether the module needs a mutable heap-pointer global (runtime
  /// allocations, e.g. string concatenation).
  bool requiresHeapGlobal = false;

  /// Wasm global index of the heap pointer (`$hp`).
  static const int heapGlobalIndex = 0;

  /// Reserved heap headroom (bytes) for runtime allocations, in addition to the
  /// static data. (Fixed for now; `memory.grow` lands in a later slice.)
  static const int heapReserveBytes = 1 << 16; // 64 KiB

  /// Initial value of `$hp`: just past the static data, 4-byte aligned.
  int get heapStart {
    var end = dataBaseOffset + _data.length;
    return (end + 3) & ~3;
  }

  /// Minimum memory pages (64 KiB each): enough for the static data plus the
  /// heap reserve when a heap is used.
  int get memoryMinPages {
    var end = dataBaseOffset + _data.length;
    if (requiresHeapGlobal) end = heapStart + heapReserveBytes;
    var pages = (end + 65535) ~/ 65536;
    return pages < 1 ? 1 : pages;
  }
}

/// The Wasm code context (per function body).
class WasmContext {
  /// Module-level state (function index space, imports, data). May be null for
  /// throwaway sub-generation contexts that never resolve calls.
  WasmModuleContext? module;

  WasmContext({this.module});

  /// Whether the current function is compiled through the exception CFG. When
  /// set, integer division emits a non-trapping guard that raises a catchable
  /// exception on a zero/overflowing divisor instead of trapping the module.
  bool exceptionMode = false;

  /// Nesting depth of the collection literal (`List`/`Map`) currently being
  /// generated: 0 for a top-level literal, +1 for each literal nested as an
  /// element/value. Used to offset the header/buffer scratch-local slots so a
  /// nested literal never aliases the enclosing literal's locals (which the
  /// global scratch cache would otherwise share). Depth 0 keeps the original
  /// slot numbers, so single-level collections stay byte-identical.
  int collectionLiteralDepth = 0;

  /// Number of currently-open structured control instructions (`block`/`loop`/
  /// `if`). A Wasm `br L` targets the structure `L` levels up from the innermost,
  /// so the relative label for a target opened at depth `K` is `controlDepth - K`.
  /// Maintained by the loop and `if`-branch generators so `break`/`continue` can
  /// compute correct relative branch labels regardless of nesting.
  int controlDepth = 0;

  /// Stack of enclosing loops, innermost last. Each frame records the
  /// [controlDepth] of the loop's break target (the outer `block`) and of its
  /// continue target (the inner `block` wrapping the body).
  final List<({int breakLevel, int continueLevel})> _loopFrames = [];

  void pushLoopFrame({required int breakLevel, required int continueLevel}) {
    _loopFrames.add((breakLevel: breakLevel, continueLevel: continueLevel));
  }

  /// Pushes a `switch` frame: `break` targets the switch exit ([breakLevel]),
  /// but `continue` keeps targeting the enclosing loop (inherited from the
  /// current innermost frame, if any).
  void pushSwitchFrame({required int breakLevel}) {
    var continueLevel = _loopFrames.isNotEmpty
        ? _loopFrames.last.continueLevel
        : -1;
    _loopFrames.add((breakLevel: breakLevel, continueLevel: continueLevel));
  }

  void popLoopFrame() => _loopFrames.removeLast();

  /// Relative branch label from the current [controlDepth] to the innermost
  /// loop's break target, for a `break` statement.
  int get breakBranchLabel {
    if (_loopFrames.isEmpty) {
      throw StateError("`break` outside of a loop/switch");
    }
    return controlDepth - _loopFrames.last.breakLevel;
  }

  /// Relative branch label to the innermost loop's continue target, for a
  /// `continue` statement.
  int get continueBranchLabel {
    if (_loopFrames.isEmpty) {
      throw StateError("`continue` outside of a loop");
    }
    return controlDepth - _loopFrames.last.continueLevel;
  }

  /// Resolves the Wasm function index for a function with [name] and [arity].
  int? functionIndex(String name, int arity) =>
      module?.functionIndex(name, arity);

  /// Resolves the Wasm function index for a call by [name] supplying
  /// [suppliedCount] arguments, allowing omitted trailing parameters that have
  /// default values (see [WasmModuleContext.functionIndexForCall]).
  int? functionIndexForCall(String name, int suppliedCount) =>
      module?.functionIndexForCall(name, suppliedCount);

  /// Returns the function at the module's function index [index].
  ASTFunctionDeclaration? functionByIndex(int index) =>
      module?.functionByIndex(index);

  /// When generating a class constructor/method body, the field layout of the
  /// owning class and the local index holding the `this` pointer. A bare name
  /// that isn't a local but is a field resolves to a load/store at
  /// `this + offset`.
  WasmClassLayout? classLayout;
  int thisLocalIndex = -1;

  /// When generating a closure body, the local index of the hidden environment
  /// pointer (parameter 0), and the captured variables stored in that
  /// environment (read as `env + offset`). `-1` / empty when not a closure.
  int closureEnvLocalIndex = -1;
  final Map<String, ({ASTType type, int offset})> capturedVariables = {};

  /// Local variables of the function currently being generated that hold a
  /// capture-free, call-only closure: their declaration is elided and `v(x)`
  /// lowers to a direct `call` of the mapped closure (no env / no
  /// `call_indirect`). Empty when there are none.
  Map<String, ASTFunctionDeclaration> directClosureVars = const {};

  /// Whether [name] is a captured variable read from the closure environment.
  bool isCapturedVariable(String name) =>
      closureEnvLocalIndex >= 0 && capturedVariables.containsKey(name);

  /// Variables captured by a closure of the *current* function, "boxed" into a
  /// shared heap cell for capture-by-reference. Maps the variable name to its
  /// value [type] and the i32 local holding the box (cell) pointer.
  final Map<String, ({ASTType type, int boxLocal})> boxedVariables = {};

  /// Whether [name] is a boxed (captured-by-reference) variable of the current
  /// function (its local holds a pointer to a heap cell).
  bool isBoxedVariable(String name) => boxedVariables.containsKey(name);

  /// Whether [name] resolves to a field of the current method's class (and is
  /// not shadowed by a local variable).
  bool isFieldAccess(String name) =>
      classLayout != null &&
      !_localVariables.containsKey(name) &&
      classLayout!.offsets.containsKey(name);

  final Map<String, ({ASTType type, int index})> _localVariables = {};

  ({ASTType type, int index})? getLocalVariable(String name) {
    return _localVariables[name];
  }

  /// Returns the type of a local variable by [name].
  ASTType? getLocalVariableType(String name) {
    return _localVariables[name]?.type;
  }

  /// Returns the local variable by [index].
  ({int index, ASTType type})? getLocalVariableByIndex(int index) {
    return _localVariables.values.firstWhereOrNull((e) => e.index == index);
  }

  /// Returns the type of a local variable by [index].
  /// See [getLocalVariableByIndex].
  ASTType? getLocalVariableTypeByIndex(int index) =>
      getLocalVariableByIndex(index)?.type;

  /// Returns the index of a local variable with [name].
  int getLocalVariableIndex(String name) {
    var prev = _localVariables[name];
    return prev?.index ?? (throw StateError("Variable `$name` not defined!"));
  }

  /// Adds a local variable and returns its index.
  int addLocalVariable(String name, ASTType type) {
    var prev = _localVariables[name];
    if (prev != null) {
      var prevType = prev.type;

      if (prevType != type) {
        throw StateError(
          "Variable `$name` ($type) already defined with a different type: $prevType",
        );
      } else {
        return prev.index;
      }
    }

    var entry = (type: type, index: _localVariables.length);
    _localVariables[name] = entry;
    return entry.index;
  }

  /// Re-types an existing local (keeping its index). Used to refine a `var`
  /// declared as `dynamic` once its initializer's real type is known.
  void updateLocalVariableType(String name, ASTType type) {
    var prev = _localVariables[name];
    if (prev == null) {
      throw StateError("Variable `$name` not defined!");
    }
    _localVariables[name] = (type: type, index: prev.index);
  }

  /// Scratch (temporary) local types, in the order they were allocated. These
  /// are declared in the function preamble after the regular locals.
  final List<ASTType> scratchLocalTypes = [];

  final Map<String, int> _scratchCache = {};

  /// Allocates (or reuses) a scratch local of [type] identified by [slot].
  /// Reused across the function so repeated operations don't keep allocating.
  /// Must be called while generating the function body (before the preamble is
  /// emitted), so [generateASTFunctionDeclaration] can declare them.
  int scratchLocal(ASTType type, int slot) {
    var key = '${type.wasmType.value}#$slot';
    var cached = _scratchCache[key];
    if (cached != null) return cached;

    var index = addLocalVariable('\$scratch_$key', type);
    scratchLocalTypes.add(type);
    _scratchCache[key] = index;
    return index;
  }

  final ListQueue<({ASTType type, String description})> _stack = ListQueue();

  /// The length of the stack.
  int get stackLength => _stack.length;

  /// Asserts the stack length.
  int assertStackLength([int? expectedLength, String? description]) {
    var currentLength = stackLength;

    if (currentLength != expectedLength) {
      throw StateError(
        "Invalid stack length> stackLength: $stackLength != expected: $expectedLength${description != null ? ' ($description)' : ''}",
      );
    }

    return currentLength;
  }

  /// Notify a stack push.
  void stackPush(ASTType type, String description) {
    _stack.add((type: type, description: description));
  }

  /// Notify a stack drop.
  ({ASTType type, String description}) stackDrop([ASTType? expectedType]) {
    if (_stack.isEmpty) {
      throw StateError(
        "Drop from stack error> Empty stack! Expected type: $expectedType",
      );
    }

    var entry = _stack.removeLast();
    if (expectedType != null && entry.type != expectedType) {
      throw StateError(
        "Drop from stack error> Not expected type: stack.drop:${entry.type} != expected:$expectedType",
      );
    }
    return entry;
  }

  /// Notify an unary stack operation.
  void stackOperationUnary(
    ASTType type,
    String description, [
    ASTType? expectedType1,
    ASTType? expectedType2,
  ]) {
    stackDrop(expectedType1);
    stackPush(type, description);
  }

  /// Notify a binary stack operation.
  void stackOperationBinary(
    ASTType type,
    String description, [
    ASTType? expectedType1,
    ASTType? expectedType2,
  ]) {
    stackDrop(expectedType1);
    stackDrop(expectedType2);
    stackPush(type, description);
  }

  /// Replaces the top stack entry.
  void stackReplace(
    ASTType type,
    String description, [
    ASTType? expectedType1,
  ]) {
    stackDrop(expectedType1);
    stackPush(type, description);
  }

  /// Replaces a stack entry at [index].
  void stackReplaceAt(
    int index,
    ASTType type,
    String description, [
    ASTType? expectedType1,
  ]) {
    var prev = ListQueue<({ASTType type, String description})>();

    for (var i = 0; i <= index; ++i) {
      var s = stackDrop();

      if (i == index) {
        stackPush(type, description);
        _stack.addAll(prev);
        return;
      } else {
        prev.addFirst(s);
      }
    }

    throw StateError(
      "Can't find stack index: $index (stack length: $stackLength",
    );
  }

  /// Gets the stack entry.
  /// - [index] is in reverse order, from last added to first added (`0` is the top of the stack).
  ({ASTType type, String description})? stackGet(int index) {
    if (_stack.isEmpty) return null;

    if (index == 0) {
      return _stack.last;
    }

    var i = _stack.length - 1;
    for (var s in _stack) {
      if (i == index) {
        return s;
      }
      --i;
    }

    return null;
  }

  final ListQueue<({ASTType type, String description})> _returns = ListQueue();

  /// The length of expected returns.
  int get returnsLength => _returns.length;

  /// Asserts the stack length.
  int assertReturnsLength([int? expectedLength, String? description]) {
    var currentLength = returnsLength;

    if (currentLength != expectedLength) {
      throw StateError(
        "Invalid returns length> returnsLength: $returnsLength != expected: $expectedLength${description != null ? ' ($description)' : ''}",
      );
    }

    return currentLength;
  }

  /// Notify a returns push.
  void returnsPush(ASTType type, String description) {
    _returns.add((type: type, description: description));
  }

  /// Notify a returns drop.
  ({ASTType type, String description}) returnsDrop([ASTType? expectedType]) {
    if (_returns.isEmpty) {
      throw StateError(
        "Drop from returns error> Empty returns! Expected type: $expectedType",
      );
    }

    var entry = _returns.removeLast();
    if (expectedType != null && entry.type != expectedType) {
      throw StateError(
        "Drop from returns error> Not expected type: returns.drop:${entry.type} != expected:$expectedType",
      );
    }
    return entry;
  }

  /// Gets the returns entry.
  /// - [index] is in reverse order, from last added to first added (`0` is the top of the returns stack).
  ({ASTType type, String description})? returnsGet(int index) {
    if (_returns.isEmpty) return null;

    if (index == 0) {
      return _returns.last;
    }

    var i = _returns.length - 1;
    for (var s in _returns) {
      if (i == index) {
        return s;
      }
      --i;
    }

    return null;
  }

  @override
  String toString() {
    return 'WasmContext{'
        'localVariables: ${_localVariables.length}${_localVariables.entries.map((e) => '${e.value.index}:${e.value.type} ${e.key}').toList()}, '
        'stack: ${_stack.length}'
        '}';
  }
}

extension _ASTTypeExtension on ASTType {
  bool get isVoid => this is ASTTypeVoid || name == 'void';

  WasmType get wasmType {
    if (this is ASTTypeInt) {
      return WasmType.i64Type;
    } else if (this is ASTTypeDouble) {
      return WasmType.f64Type;
    } else if (this is ASTTypeNum) {
      // A plain `num` (e.g. TypeScript/JS `number`) has no fixed width; ApolloVM
      // treats integer-valued numbers as `int`, so represent it as i64.
      return WasmType.i64Type;
    } else if (this is ASTTypeBool) {
      return WasmType.i32Type;
    } else if (this is ASTTypeString) {
      // A string is an i32 pointer into linear memory.
      return WasmType.i32Type;
    } else if (this is ASTTypeArray) {
      // A list is an i32 pointer into linear memory.
      return WasmType.i32Type;
    } else if (this is ASTTypeMap) {
      // A map is an i32 pointer into linear memory.
      return WasmType.i32Type;
    } else if (this is ASTTypeFunction) {
      // A function value is an i32 index into the module's function table.
      return WasmType.i32Type;
    } else if (this is ASTTypeObject || this is ASTTypeDynamic) {
      // A boxed `Object`/`dynamic` is an i32 pointer to its 16-byte box cell.
      return WasmType.i32Type;
    } else if (this is ASTTypeVoid) {
      return WasmType.voidType;
    } else if (name == 'void') {
      return WasmType.voidType;
    } else if (this is ASTType<VMObject>) {
      // A class instance is an i32 pointer into linear memory.
      return WasmType.i32Type;
    } else if (name.isNotEmpty) {
      // Any other named reference type — a user class or an enum used by name
      // (e.g. an enum-typed parameter `Planet p`) — is a heap instance,
      // represented as an i32 pointer like other object instances.
      return WasmType.i32Type;
    }

    throw StateError("Can't handle type: $this");
  }

  int get wasmCode => wasmType.value;
}

extension _ASTTypeNumExtension on ASTTypeNum {
  bool get isBits32 => bits == 32;

  bool get isBits64 => bits == null || bits == 64;
}

extension on Iterable<ASTFunctionParameterDeclaration> {
  Iterable<int> toWasmCodes() => map((p) => p.type.wasmCode);
}

/// A single statement-level `await` of an external call (see `_matchAsyncify`).
class _AwaitPoint {
  /// Index of the await statement within the function's statements.
  final int stmtIndex;

  /// Name of the awaited external (host) function.
  final String calleeName;

  /// Argument expressions passed to the awaited call.
  final List<ASTExpression> args;

  /// Local that receives the awaited result on resume (`null` if discarded).
  final String? resultVarName;

  /// Declared type of [resultVarName] (`null` when there is no result var).
  final ASTType? resultType;

  /// `true` when [calleeName] is another module (async) function — an *internal*
  /// frame whose suspension must be propagated; `false` for a host import leaf.
  final bool isInternal;

  _AwaitPoint(
    this.stmtIndex,
    this.calleeName,
    this.args,
    this.resultVarName,
    this.resultType,
    this.isInternal,
  );
}

/// A matched Asyncify shape: the ordered list of statement-level [awaits] that
/// drive the unwind/rewind state machine.
class _AsyncifyMatch {
  final List<_AwaitPoint> awaits;

  _AsyncifyMatch(this.awaits);
}

// --- Control-flow-aware Asyncify (PC state machine) ---
//
// When awaits appear inside `if`/`while`/`for`, the function body is lowered
// into a CFG of basic blocks dispatched by a program counter (`$pc`) via a
// `loop` + `br_table`. Awaits become block boundaries; `$pc` is spilled and
// restored on the Asyncify frame stack like any other local.

/// A basic block: straight-line [stmts] (no control flow / await) followed by a
/// single [term]inator.
class _Bb {
  final int pc;
  final List<ASTStatement> stmts = [];

  /// When set, on entering this block the leaf await's host result is loaded
  /// into its variable (the block is a leaf-await resume target).
  _AwaitPoint? leafResume;

  /// Raw Wasm emitted at block entry (before [stmts]); used for `for-each` loop
  /// setup that has no AST form (reading the list length, resetting the index).
  void Function(BytesOutput body, WasmContext ctx)? rawInit;

  _Term? term;

  _Bb(this.pc);
}

/// A basic-block terminator.
sealed class _Term {}

/// Unconditional jump: set `$pc = [pc]` and re-dispatch.
class _TGoto extends _Term {
  final int pc;
  _TGoto(this.pc);
}

/// Conditional: evaluate [cond] and jump to [thenPc] or [elsePc].
class _TBranch extends _Term {
  final ASTExpression cond;
  final int thenPc;
  final int elsePc;
  _TBranch(this.cond, this.thenPc, this.elsePc);
}

/// Leaf await (host import): suspend; on rewind resume at [resumePc].
class _TLeaf extends _Term {
  final _AwaitPoint await;
  final int resumePc;
  _TLeaf(this.await, this.resumePc);
}

/// Internal await (module async fn): call it, propagate any unwind, then
/// continue at [contPc]; re-executes its own block on rewind.
class _TInternal extends _Term {
  final _AwaitPoint await;
  final int contPc;
  _TInternal(this.await, this.contPc);
}

/// Emits a `return` statement (block end of control).
class _TReturn extends _Term {
  final ASTStatement stmt;
  _TReturn(this.stmt);
}

/// Returns the value of a local (used for `return await ...` via a temp).
class _TReturnLocal extends _Term {
  final String name;
  _TReturnLocal(this.name);
}

/// Implicit function end (fell off the body): return the default / unreachable.
class _TReturnEnd extends _Term {}

// --- Exception terminators (try/catch/finally/throw) ---

/// `throw [value]`: marshal the value into the exception slots, flag pending,
/// and jump to [handlerPc] (a catch-dispatch block, or the function's propagate
/// block when there is no enclosing `try`).
class _TThrow extends _Term {
  final ASTExpression value;
  final int handlerPc;
  _TThrow(this.value, this.handlerPc);
}

/// One `catch` clause within a [_TCatchDispatch].
class _CatchInfo {
  /// `null` = catch-all (untyped or a universal supertype); otherwise the set of
  /// `EXC_TAG` values this clause accepts (mirrors `ASTType.acceptsType`, e.g. an
  /// `on double` clause also accepts an `int` value).
  final Set<int>? tags;
  final String? varName;
  final ASTType? varType;
  final int bodyPc;
  _CatchInfo(this.tags, this.varName, this.varType, this.bodyPc);
}

/// Catch dispatch: an exception is pending; test [clauses] in order against
/// `EXC_TAG`. On the first match, clear the pending flag, bind the clause
/// variable from `EXC_VALUE`, and jump to its body; if none match, jump to
/// [noMatchPc] (a `finally` runner or the propagate block).
class _TCatchDispatch extends _Term {
  final List<_CatchInfo> clauses;
  final int noMatchPc;
  _TCatchDispatch(this.clauses, this.noMatchPc);
}

/// Re-raise / propagate the pending exception out of this function: ensure the
/// pending flag is set and return the default value (the caller re-checks it).
class _TPropagate extends _Term {}

/// Emits [stmt] (which contains a call that may throw), then checks the pending
/// flag: if set, jump to [handlerPc]; otherwise continue at [contPc].
class _TCallCheck extends _Term {
  final ASTStatement stmt;
  final int contPc;
  final int handlerPc;
  _TCallCheck(this.stmt, this.contPc, this.handlerPc);
}

/// A built CFG: its [blocks] plus any synthetic temp locals (e.g. for
/// `return await ...`) that the emitter must declare.
class _Cfg {
  final List<_Bb> blocks;
  final List<({String name, ASTType type})> temps;
  _Cfg(this.blocks, this.temps);
}

extension _ASTFunctionDeclarationExtension on ASTFunctionDeclaration {
  /// The effective Wasm return type. For an `async` function the declared
  /// `Future<T>` collapses to `T`, because the Wasm backend executes
  /// synchronously — a future's value is always already available, so
  /// `await` is a value pass-through and an `async` function is compiled as a
  /// normal function returning `T`. (Real suspension would require Asyncify or
  /// JSPI; see the `TODO(async)` on `generateASTExpressionAwait`.)
  ASTType get effectiveReturnType {
    var rt = returnType;
    if (modifiers.isAsync && rt is ASTTypeFuture) {
      return rt.futureValueType;
    }
    // A function typed `dynamic` (e.g. an untyped Lua/Python function) whose own
    // body never directly returns a value — its only `return <expr>` lives in a
    // nested closure, which some parsers wrongly attribute to the parent — is
    // effectively `void`. Treating it as non-void would emit a trailing
    // terminator that traps when the function falls off its end.
    if (rt is ASTTypeDynamic && !_bodyHasDirectValueReturn) {
      return ASTTypeVoid.instance;
    }
    return rt;
  }

  /// Whether this function's own body contains a `return <expression>` that is
  /// not inside a nested anonymous function (closures are skipped).
  bool get _bodyHasDirectValueReturn {
    bool scan(ASTNode node) {
      if (node is ASTExpressionLiteralFunction) return false;
      if (node is ASTStatementReturnWithExpression) return true;
      for (var c in node.children) {
        if (scan(c)) return true;
      }
      return false;
    }

    for (var stm in statements) {
      if (scan(stm)) return true;
    }
    return false;
  }

  List<int> get parametersTypesWasmCode {
    final parameters = this.parameters;

    var positionalParameters = parameters.positionalParameters?.toWasmCodes();
    var optionalParameters = parameters.optionalParameters?.toWasmCodes();
    var namedParameters = parameters.namedParameters?.toWasmCodes();

    var allParameters = [
      ...?positionalParameters,
      ...?optionalParameters,
      ...?namedParameters,
    ];

    return allParameters;
  }

  BytesOutput wasmSignature({BytesOutput? out}) {
    out ??= BytesOutput();

    out.writeByte(Wasm.functionType, description: "Type: function");

    var allParameters = parametersTypesWasmCode;

    if (allParameters.isNotEmpty) {
      out.write([
        ...Leb128.encodeUnsigned(allParameters.length),
        ...allParameters,
      ], description: "Parameters: $parameters");
    } else {
      out.writeByte(0, description: "No parameters");
    }

    var returnType = effectiveReturnType;

    if (!returnType.isVoid) {
      out.write([
        ...Leb128.encodeUnsigned(1),
        returnType.wasmCode,
      ], description: "Return value");
    } else {
      out.writeByte(0, description: "No return value");
    }

    return out;
  }
}

extension _ASTStatementExtension on ASTStatement {
  List<MapEntry<String, ASTType>> declaredVariablesTypes() {
    final self = this;
    if (self is ASTStatementVariableDeclaration) {
      var resolvedType = self.resolveType(null);
      var type = resolvedType is ASTType ? resolvedType : self.type;
      return [MapEntry(self.name, type)];
    } else if (self is ASTBranchIfBlock) {
      return self.block.declaredVariables();
    } else if (self is ASTBranchIfElseBlock) {
      return [
        ...self.blockIf.declaredVariables(),
        ...?self.blockElse?.declaredVariables(),
      ];
    } else if (self is ASTBranchIfElseIfsElseBlock) {
      return [
        ...self.blockIf.declaredVariables(),
        ...self.blocksElseIf.declaredVariables(),
        ...?self.blockElse?.declaredVariables(),
      ];
    } else if (self is ASTStatementForLoop) {
      return [
        ...self.initStatement.declaredVariablesTypes(),
        ...self.loopBlock.declaredVariables(),
      ];
    } else if (self is ASTStatementWhileLoop) {
      return self.loopBlock.declaredVariables();
    } else if (self is ASTStatementForEach) {
      // The loop variable's type is the iterable's element type (the declared
      // type is usually `var`).
      var iterExpr = self.iterableExpression;
      var iterType = iterExpr.resolveType(null);
      ASTType elemType;
      if (iterType is ASTTypeArray) {
        elemType = iterType.componentType;
      } else if (iterExpr is ASTExpressionObjectGetterAccess &&
          (iterExpr.name == 'keys' || iterExpr.name == 'values')) {
        // `for (var k in m.keys)` / `m.values`: element type from the map.
        var mapType = iterExpr.variable.resolveType(null);
        elemType = mapType is ASTTypeMap
            ? (iterExpr.name == 'keys' ? mapType.keyType : mapType.valueType)
            : self.variableType;
      } else {
        elemType = self.variableType;
      }
      return [
        MapEntry(self.variableName, elemType),
        ...self.loopBlock.declaredVariables(),
      ];
    }

    return [];
  }
}

extension _IterableASTStatementExtension on Iterable<ASTStatement> {
  List<MapEntry<String, ASTType>> declaredVariables() =>
      expand((e) => e.declaredVariablesTypes()).toList();
}

extension _ASTBlockExtension on ASTBlock {
  List<MapEntry<String, ASTType>> declaredVariables() =>
      statements.expand((e) => e.declaredVariablesTypes()).toList();
}

extension _ASTFunctionParameterDeclarationExtension
    on ASTFunctionParameterDeclaration {
  List<MapEntry<String, ASTType>> declaredVariables() => [
    MapEntry<String, ASTType>(name, type),
  ];
}

extension _IterableASTFunctionParameterDeclarationExtension
    on Iterable<ASTFunctionParameterDeclaration> {
  List<MapEntry<String, ASTType>> declaredVariables() =>
      expand((e) => e.declaredVariables()).toList();
}

extension _ASTParametersDeclarationExtension
    on ASTFunctionParametersDeclaration {
  List<MapEntry<String, ASTType>> declaredVariables() => [
    ...?positionalParameters?.declaredVariables(),
    ...?optionalParameters?.declaredVariables(),
    ...?namedParameters?.declaredVariables(),
  ];
}
