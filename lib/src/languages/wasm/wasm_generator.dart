// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:data_serializer/data_serializer.dart';

import '../../apollovm_code_storage.dart';
import '../../apollovm_generated_output.dart';
import '../../apollovm_generator.dart';
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

    out.write(Wasm.magicModuleHeader, description: "Wasm Magic");
    out.write(Wasm.moduleVersion, description: "Version 1");

    var functions = root.functions.expand((fs) => fs.functions).toList();
    var module = WasmModuleContext(functions);

    // A public function with a String or List parameter requires the host to
    // allocate the argument in module memory, so ensure `__alloc` is exported.
    if (_hasMarshalledParam(module)) {
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
    return 5;
  }

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
        t is ASTTypeMap;
    for (var f in module.functions) {
      if (f.modifiers.isPrivate) continue;
      if (needs(f.effectiveReturnType)) return true;
      for (var p in f.parameters.allParameters) {
        if (p.type is ASTTypeString ||
            p.type is ASTTypeArray ||
            p.type is ASTTypeMap) {
          return true;
        }
      }
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
            p.type is ASTTypeMap) {
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

    var publicFunctions = functionsIndexed
        .where((e) => !e.key.modifiers.isPrivate)
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
      ...module.functions.map((f) => f.wasmSignature()),
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

    // One mutable i32 global: the heap pointer `$hp`, initialized to heapStart.
    var entry = BytesOutput(
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
    );

    out.writeByte(Wasm.sectionGlobal, description: "Section Global ID");
    out.writeBytesLeb128Block([
      BytesOutput(data: Leb128.encodeUnsigned(1), description: "Globals count"),
      entry,
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

    var entries = module.functions
        .map((f) => generateASTFunctionDeclaration(f, module: module))
        .toList();

    // Synth functions (e.g. `__alloc`) registered during user-body codegen.
    // Each body is length-prefixed (like user-function bodies).
    for (var s in module.synthFunctions) {
      var bodyEntry = newOutput();
      bodyEntry.writeBytesLeb128Block([
        s.body,
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

    generateASTBlock(branch.block, out: out, context: context);

    out.writeByte(Wasm.end, description: "[OP] if end");

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

    generateASTBlock(branch.blockIf, out: out, context: context);

    var blockElse = branch.blockElse;
    if (blockElse != null) {
      out.writeByte(Wasm.elseInstruction, description: "[OP] else");
      generateASTBlock(blockElse, out: out, context: context);
    }

    out.writeByte(Wasm.end, description: "[OP] if else end");

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

    throw UnimplementedError(
      "Wasm method `.${expression.name}` on ${localVar.type} "
      "is not supported yet.",
    );
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

  void _emitElemStore(BytesOutput out, ASTType elemType, int offset) {
    if (elemType is ASTTypeInt) {
      out.write(Wasm64.i64Store(3, offset));
    } else if (elemType is ASTTypeDouble) {
      out.write(Wasm64.f64Store(FloatAlign.align3, offset));
    } else if (elemType is ASTTypeString || elemType is ASTTypeBool) {
      out.write(Wasm32.i32Store(2, offset));
    } else {
      throw UnimplementedError("Wasm list element store for $elemType");
    }
  }

  void _emitElemLoad(BytesOutput out, ASTType elemType, int offset) {
    if (elemType is ASTTypeInt) {
      out.write(Wasm64.i64Load(3, offset));
    } else if (elemType is ASTTypeDouble) {
      out.write(Wasm64.f64Load(FloatAlign.align3, offset));
    } else if (elemType is ASTTypeString || elemType is ASTTypeBool) {
      out.write(Wasm32.i32Load(2, offset));
    } else {
      throw UnimplementedError("Wasm list element load for $elemType");
    }
  }

  ASTType _elemStackType(ASTType elemType) {
    if (elemType is ASTTypeInt) return _astTypeInt64;
    if (elemType is ASTTypeDouble) return _astTypeDouble64;
    if (elemType is ASTTypeString) return _astTypeString;
    if (elemType is ASTTypeBool) return _astTypeInt32; // bool as i32
    return elemType;
  }

  /// Element types that compile to Wasm list storage: `int`/`double` (8B) and
  /// `String`/`bool` (4B i32). Other element types are unsupported.
  bool _isSupportedElemType(ASTType t) =>
      t is ASTTypeInt ||
      t is ASTTypeDouble ||
      t is ASTTypeString ||
      t is ASTTypeBool;

  @override
  BytesOutput generateASTExpressionListLiteral(
    ASTExpressionListLiteral expression, {
    BytesOutput? out,
    WasmContext? context,
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
    if (!_isSupportedElemType(elemType)) {
      throw UnimplementedError(
        "Wasm list literal of element type $elemType is not supported yet.",
      );
    }

    var size = _elemSize(elemType);
    var values = expression.valuesExpressions;
    var n = values.length;
    // Indirect layout: header [length@0][capacity@4][dataPtr@8]; elements live
    // in a separate buffer so `.add` can realloc without moving the handle.
    var hdrLocal = context.scratchLocal(_astTypeString, 6);
    var dataLocal = context.scratchLocal(_astTypeString, 9);

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
      context.stackDrop(); // value consumed by the store
      _emitElemStore(out, elemType, i * size);
    }

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

  @override
  BytesOutput generateASTExpressionLocalFunctionInvocation(
    ASTExpressionLocalFunctionInvocation expression, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    var name = expression.name;
    var arguments = expression.arguments;
    var argsCount = arguments.length;

    // Built-in external `print(Object)` lowers to a host import call.
    if (name == 'print' && argsCount == 1) {
      return _generatePrintInvocation(expression, out: out, context: context);
    }

    var calleeIndex = context.functionIndex(name, argsCount);
    if (calleeIndex == null) {
      throw StateError(
        "Can't resolve local function `$name` with $argsCount argument(s) "
        "in the Wasm function index table.",
      );
    }

    var callee = context.functionByIndex(calleeIndex)!;

    final stackLng0 = context.stackLength;

    // Evaluate each argument (left-to-right), pushing onto the Wasm stack,
    // converting each to the callee's declared parameter type.
    for (var i = 0; i < argsCount; ++i) {
      var arg = arguments[i];

      var stackLngArg = context.stackLength;
      generateASTExpression(arg, out: out, context: context);
      context.assertStackLength(
        stackLngArg + 1,
        "After argument[$i] push (call `$name`)",
      );

      var stackEntry = context.stackGet(0)!;
      var stackType = stackEntry.type;

      var paramType = callee.parameters.getParameterByIndex(i)?.type;
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
      stackLng0 + argsCount,
      "Before call `$name` (all arguments pushed)",
    );

    out.write(
      Wasm.call(calleeIndex),
      description: "[OP] call `$name` (function index: $calleeIndex)",
    );

    // Update the virtual stack: drop the N arguments and push the return type.
    for (var i = 0; i < argsCount; ++i) {
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

    // Evaluate the argument; it must resolve to a string handle (i32).
    generateASTExpression(expression.arguments[0], out: out, context: context);
    context.assertStackLength(stackLng0 + 1, "After print argument");

    var argType = context.stackGet(0)!.type;
    if (argType != _astTypeInt32 && argType is! ASTTypeString) {
      throw UnimplementedError(
        "Wasm `print` currently supports String arguments only "
        "(got $argType); number/other interpolation lands in a later slice.",
      );
    }

    var importIndex = module.registerImportedFunction('env', 'print', [
      WasmType.i32Type,
    ], const []);

    out.write(
      Wasm.call(importIndex),
      description: "[OP] call host import `env.print` (index $importIndex)",
    );
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

    var hdrLocal = context.scratchLocal(_astTypeString, 15);
    var keysLocal = context.scratchLocal(_astTypeString, 16);
    var valsLocal = context.scratchLocal(_astTypeString, 17);

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
      context.stackDrop();
      _emitElemStore(out, keyType, i * keySize);
      // vals[i] = value
      out.write(Wasm.localGet(valsLocal));
      generateASTExpression(entries[i].value, out: out, context: context);
      context.stackDrop();
      _emitElemStore(out, valueType, i * valSize);
    }

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
    assert(stackType1 == _astTypeInt, stackType1);
    assert(stackType2 == _astTypeInt, stackType2);

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
  BytesOutput generateASTExpressionLogicalShortCircuit(
    ASTExpressionOperation expression, {
    BytesOutput? out,
    WasmContext? context,
  }) {
    out ??= newOutput();
    context ??= WasmContext();

    final isAnd = expression.operator == ASTExpressionOperator.and;
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

    // Short-circuit logical operators must NOT eagerly evaluate the right
    // operand, so they are handled before the generic operand evaluation below.
    if (expression.operator == ASTExpressionOperator.and ||
        expression.operator == ASTExpressionOperator.or) {
      return generateASTExpressionLogicalShortCircuit(
        expression,
        out: out,
        context: context,
      );
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

    // String `+` -> concatenation (both operands must already be String).
    if (expression.operator == ASTExpressionOperator.add &&
        (stackType1 is ASTTypeString || stackType2 is ASTTypeString)) {
      if (stackType1 is! ASTTypeString || stackType2 is! ASTTypeString) {
        throw UnimplementedError(
          "Wasm string `+` with a non-String operand (number-to-string) is "
          "not supported yet ($stackType1 + $stackType2).",
        );
      }
      out.writeBytes(exp1Out);
      out.writeBytes(exp2Out);
      context.assertStackLength(stackLng2, "After push string operands");
      _emitStringConcat2(out, context);
      context.assertStackLength(stackLng0 + 1, "After string concat");
      return out;
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
        }
      case ASTExpressionOperator.divideAsInt:
        {
          _checkStackStatusF64(stackType1, stackType2);

          out.writeByte(
            Wasm64.f64Divide,
            description: "[OP] operator: divide(f64)",
          );
          context.stackOperationBinary(_astTypeDouble64, "Wasm64.f64Divide");

          out.writeByte(
            Wasm64.f64TruncateToI64Signed,
            description: "[OP] Wasm64.f64TruncateToi64Signed",
          );

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
    // TODO: implement generateASTExpressionNullValue
    throw UnimplementedError("generateASTExpressionNullValue");
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

    if (containerType is ASTTypeMap) {
      return _generateMapGet(expression, localVar, out: out, context: context);
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

    // Desugar a compound assignment `c[k] OP= v` into `c[k] = (c[k] OP v)`.
    if (expression.operator != ASTAssignmentOperator.set) {
      var binOp = _compoundToOperator(expression.operator);
      var access = ASTExpressionVariableEntryAccess(
        expression.variable,
        expression.keyExpression,
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
  ASTExpressionOperator _compoundToOperator(ASTAssignmentOperator op) {
    switch (op) {
      case ASTAssignmentOperator.sum:
        return ASTExpressionOperator.add;
      case ASTAssignmentOperator.subtract:
        return ASTExpressionOperator.subtract;
      case ASTAssignmentOperator.multiply:
        return ASTExpressionOperator.multiply;
      case ASTAssignmentOperator.divide:
        return ASTExpressionOperator.divide;
      case ASTAssignmentOperator.divideAsInt:
        return ASTExpressionOperator.divideAsInt;
      case ASTAssignmentOperator.set:
        throw ArgumentError("`set` is not a compound operator");
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
    var localVar = _getLocalVariable(context, varName);

    var listType = localVar.type;

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

    // Real `async`/`await` suspension (Asyncify): if this async function has a
    // single statement-level `await` of an external (host) call, emit the
    // unwind/rewind state machine so it can really suspend. Anything more
    // complex falls back to the synchronous-collapse path below.
    if (f.modifiers.isAsync && module != null) {
      var match = _matchAsyncify(f, module);
      if (match != null) {
        return _generateAsyncifyFunction(
          f,
          match,
          out: out,
          context: context,
          module: module,
        );
      }
    }

    var outBody = newOutput();

    // For an `async` function the declared `Future<T>` collapses to `T` (Wasm
    // executes synchronously); compile it as a normal function returning `T`.
    var effectiveReturnType = f.effectiveReturnType;

    var return0 = context.returnsLength;
    context.returnsPush(
      effectiveReturnType,
      "Function `${f.name}` return: $effectiveReturnType",
    );
    context.assertReturnsLength(return0 + 1);

    var parametersVariables = f.parameters.declaredVariables();

    for (var v in parametersVariables) {
      context.addLocalVariable(v.key, v.value);
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

    for (var stm in f.statements) {
      generateASTStatement(stm, out: bodyCode, context: context);
    }

    var returnType = effectiveReturnType;

    if (!returnType.isVoid && context.stackLength == 0) {
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
      var astType = v.value;
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

  /// The await points of [f] if its shape is Asyncify-able, assuming the module
  /// functions in [eligible] are themselves transformed. Each await must be a
  /// top-level statement (`T v = await call(...)` or `await call(...)`) of an
  /// external (host) call (a *leaf* suspension) or a call to a function in
  /// [eligible] (an *internal* frame). Returns `null` for anything more complex
  /// (an await nested in control flow or another expression, multiple awaits in
  /// one statement, awaiting a not-yet-eligible module function, or a `var`-
  /// typed result the Wasm backend can't infer).
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
      final awaitsInS = s.descendantChildren
          .whereType<ASTExpressionAwait>()
          .toList();
      if (awaitsInS.isEmpty) continue;
      if (awaitsInS.length != 1) return null; // >1 await in one statement

      final aw = awaitsInS.first;
      final inner = aw.expression;
      if (inner is! ASTExpressionLocalFunctionInvocation) return null;

      final name = inner.name;
      final args = inner.arguments;
      if (name == 'print') return null;

      // Internal frame (awaiting a module function) vs leaf (host import).
      final isInternal = module.functionIndex(name, args.length) != null;
      if (isInternal && !eligible.contains(name)) return null;

      String? resultVar;
      ASTType? resultType;
      if (s is ASTStatementVariableDeclaration && identical(s.value, aw)) {
        if (s.type is ASTTypeVar) return null; // explicit type required
        resultVar = s.name;
        resultType = s.type;
      } else if (s is ASTStatementExpression && identical(s.expression, aw)) {
        // discarded result
      } else {
        return null; // await not a clean top-level statement
      }

      points.add(_AwaitPoint(i, name, args, resultVar, resultType, isInternal));
    }

    if (points.isEmpty) return null;
    return points;
  }

  /// Fixed-point set of Asyncify-eligible function names: async functions whose
  /// awaits all conform and whose awaited module functions are themselves
  /// eligible. Computed once per module.
  Set<String> _asyncifyEligible(WasmModuleContext module) {
    var cached = module.asyncifyEligible;
    if (cached != null) return cached;

    final eligible = <String>{};
    var changed = true;
    while (changed) {
      changed = false;
      for (var f in module.functions) {
        if (eligible.contains(f.name)) continue;
        if (_asyncifyAwaitPoints(f, module, eligible) != null) {
          eligible.add(f.name);
          changed = true;
        }
      }
    }

    return module.asyncifyEligible = eligible;
  }

  _AsyncifyMatch? _matchAsyncify(
    ASTFunctionDeclaration f,
    WasmModuleContext module,
  ) {
    final eligible = _asyncifyEligible(module);
    if (!eligible.contains(f.name)) return null;
    final points = _asyncifyAwaitPoints(f, module, eligible);
    if (points == null) return null;
    return _AsyncifyMatch(points);
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
      final rk = p.resultType!.wasmType;
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
        final paramType = callee.parameters.getParameterByIndex(i)?.type;
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
    } else if (statement is ASTStatementWhileLoop) {
      return generateASTStatementWhileLoop(
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

    generateASTExpression(statement.expression, out: out, context: context);

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

    // block { loop { if (i >= len) break; e = data[i]; <body>; i++; continue } }
    out.write(Wasm.block(WasmType.voidType));
    out.write(Wasm.loop(WasmType.voidType));

    // if (i >= len) br 1
    out.write(Wasm.localGet(iScratch));
    out.write(Wasm.localGet(listScratch));
    out.write(Wasm32.i32Load(2, 0)); // length
    out.writeByte(Wasm32.i32GreaterThanOrEqualsUnsigned);
    out.write(Wasm.brIf(1));

    // e = data[i*size]
    out.write(Wasm.localGet(dataScratch));
    out.write(Wasm.localGet(iScratch));
    out.write(Wasm32.i32Const(size));
    out.writeByte(Wasm32.i32Multiply);
    out.writeByte(Wasm32.i32Add);
    _emitElemLoad(out, elemType, 0);
    out.write(Wasm.localSet(eLocal.index));

    // body (a `return` inside emits `return` directly; no extra check needed)
    generateASTBlock(forEach.loopBlock, out: out, context: context);

    // i++
    out.write(Wasm.localGet(iScratch));
    out.write(Wasm32.i32Const(1));
    out.writeByte(Wasm32.i32Add);
    out.write(Wasm.localSet(iScratch));

    out.write(Wasm.br(0)); // continue
    out.writeByte(Wasm.end); // loop
    out.writeByte(Wasm.end); // block

    // The body may leave phantom virtual-stack entries (assignments use
    // `local.set` without a matching virtual drop), like the for/while loops;
    // the real Wasm stack stays balanced, so no post-body assertion here.
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
  }) {
    out.write(
      Wasm.block(WasmType.voidType),
      description: "[OP] block ($description loop)",
    );
    out.write(
      Wasm.loop(WasmType.voidType),
      description: "[OP] loop ($description loop)",
    );

    final stackLng0 = context.stackLength;

    // Condition: pushes an i32 (boolean).
    generateASTExpression(conditionExpression, out: out, context: context);

    context.assertStackLength(
      stackLng0 + 1,
      "After $description loop condition",
    );
    var stackType = context.stackGet(0)!.type;
    if (stackType != _astTypeInt32) {
      throw StateError("Stack type error> not a boolean type: $stackType");
    }

    // Negate the condition: `i32.eqz` consumes 1 i32 and pushes 1 i32
    // (net zero on the virtual stack).
    out.writeByte(
      Wasm32.i32EqualsToZero,
      description: "[OP] i32.eqz ( !($conditionExpression) )",
    );

    // Break out of the `block` (label 1) when the condition is false:
    out.write(Wasm.brIf(1), description: "[OP] br_if 1 ($description break)");
    context.stackDrop(_astTypeInt32);

    context.assertStackLength(
      stackLng0,
      "After $description loop condition br",
    );

    // Loop body:
    generateASTBlock(loopBlock, out: out, context: context);

    // Continue expression (for-loops only), e.g. `i++`:
    if (continueExpression != null) {
      generateASTExpression(continueExpression, out: out, context: context);
    }

    // Jump back to the top of the `loop` (label 0). Any leaked operand-stack
    // values are unwound by this branch (loop is void).
    out.write(Wasm.br(0), description: "[OP] br 0 ($description continue)");

    out.writeByte(Wasm.end, description: "[OP] loop end ($description)");
    out.writeByte(Wasm.end, description: "[OP] block end ($description)");
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

    var localVar = _getLocalVariable(context, name);

    var stackLength0 = context.stackLength;

    _localVariableGet(out, context, localVar.index, name, '(return)');

    context.stackPush(
      localVar.type,
      'Local get: ${localVar.index} \$$name (return)',
    );

    context.assertStackLength(stackLength0 + 1, "Return variable: $name");

    var stack0Type = context.stackGet(0)!.type;
    var returnType = context.returnsGet(0)!.type;

    _autoConvertStackTypes(stack0Type, returnType, out: out, context: context);

    out.writeByte(
      Wasm.functionReturn,
      description: "[OP] return variable: ${localVar.index} \$$name",
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

    _autoConvertStackTypes(stack0Type, returnType, out: out);

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

    var name = statement.name;

    var localVar = _getLocalVariable(context, name);

    final stackLng0 = context.stackLength;

    generateASTExpression(value, out: out, context: context);

    final stackLng1 = context.assertStackLength(
      stackLng0 + 1,
      "After variable declaration expression",
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

  @override
  BytesOutput generateASTStatementFunctionDeclaration(
    ASTStatementFunctionDeclaration statement, {
    BytesOutput? out,
  }) {
    throw UnimplementedError("generateASTStatementFunctionDeclaration");
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
    } else if (expression is ASTExpressionOperation) {
      return generateASTExpressionOperation(
        expression,
        out: out,
        context: context,
      );
    }

    throw UnsupportedError("Can't generate expression: $expression");
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

    var t = context.stackGet(0)!.type;
    if (t is ASTTypeString) {
      // Already a string handle.
    } else if (t is ASTTypeInt || t is ASTTypeDouble) {
      _emitNumberToString(out, context, t);
    } else {
      throw UnimplementedError(
        "Wasm string interpolation of expression type $t is not supported yet.",
      );
    }

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
    var localVar = _getLocalVariable(context, name);
    var t = localVar.type;

    _localVariableGet(out, context, localVar.index, name);

    if (t is ASTTypeString) {
      context.stackPush(_astTypeString, "string var: \$$name");
    } else if (t is ASTTypeInt || t is ASTTypeDouble) {
      context.stackPush(t, "number var: \$$name");
      _emitNumberToString(out, context, t);
    } else {
      throw UnimplementedError(
        "Wasm interpolation of variable `$name` ($t) is not supported yet.",
      );
    }

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

  /// The complete code body: locals vector + instructions + `end`.
  final BytesOutput body;
  final bool exported;

  WasmSynthFunction(
    this.name,
    this.params,
    this.results,
    this.body, {
    this.exported = false,
  });
}

/// Module-level Wasm codegen state shared across all functions: the function
/// index space (imports + defined functions) and the static data region
/// (interned string literals).
class WasmModuleContext {
  /// Module-defined functions, in index order (placed after any imports).
  final List<ASTFunctionDeclaration> functions;

  WasmModuleContext(this.functions);

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
  int get dataBaseOffset =>
      requiresAsyncify ? (asyncifyBase + asyncifyRegionSize) : 8;

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

  /// Resolves the Wasm function index for a function with [name] and [arity].
  int? functionIndex(String name, int arity) =>
      module?.functionIndex(name, arity);

  /// Returns the function at the module's function index [index].
  ASTFunctionDeclaration? functionByIndex(int index) =>
      module?.functionByIndex(index);

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
    } else if (this is ASTTypeVoid) {
      return WasmType.voidType;
    } else if (name == 'void') {
      return WasmType.voidType;
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
    return rt;
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
