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
    out.writeBytes(sectionExports, description: "Section: Export");
    out.writeBytes(sectionCode, description: "Section: Code");
    if (module.hasData) {
      out.writeBytes(generateSectionData(module), description: "Section: Data");
    }

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
    // then the module-defined functions.
    var entries = <BytesOutput>[
      ...module.importedFunctions.map(
        (imp) => _wasmFuncTypeBytes(imp.params, imp.results),
      ),
      ...module.functions.map((f) => f.wasmSignature()),
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

    // Each defined function references its type index, offset past the imports.
    var importCount = module.importCount;
    var indexes = module.functions
        .mapIndexed((i, e) => Leb128.encodeUnsigned(importCount + i))
        .toList();

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
          data: [
            ...Wasm32.i32Const(WasmModuleContext.dataBaseOffset),
            Wasm.end,
          ],
          description:
              "Offset expr (i32.const ${WasmModuleContext.dataBaseOffset})",
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
  }) {
    // TODO: implement generateASTExpressionFunctionInvocation
    throw UnimplementedError('generateASTExpressionFunctionInvocation');
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

  @override
  BytesOutput generateASTExpressionListLiteral(
    ASTExpressionListLiteral expression, {
    BytesOutput? out,
  }) {
    // TODO: implement generateASTExpressionListLiteral
    throw UnimplementedError('generateASTExpressionListLiteral');
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

    var returnType = callee.returnType;
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

  @override
  BytesOutput generateASTExpressionMapLiteral(
    ASTExpressionMapLiteral expression, {
    BytesOutput? out,
  }) {
    // TODO: implement generateASTExpressionMapLiteral
    throw UnimplementedError('generateASTExpressionMapLiteral');
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
  }) {
    // TODO: implement generateASTExpressionVariableEntryAccess
    throw UnimplementedError('generateASTExpressionVariableEntryAccess');
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

    var outBody = newOutput();

    var return0 = context.returnsLength;
    context.returnsPush(
      f.returnType,
      "Function `${f.name}` return: ${f.returnType}",
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

    var returnType = f.returnType;

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
    context.returnsDrop(f.returnType);
    context.assertReturnsLength(return0);

    outBody.writeByte(Wasm.end, description: "Code body end");

    out.writeBytesLeb128Block([outBody], description: "Function body");

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
      return generateASTStatementForEach(statement, out: out);
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
  }) {
    // TODO: implement generateASTStatementForEach
    throw UnimplementedError('generateASTStatementForEach');
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
      return generateASTExpressionVariableEntryAccess(expression, out: out);
    } else if (expression is ASTExpressionLiteral) {
      return generateASTExpressionLiteral(
        expression,
        out: out,
        context: context,
      );
    } else if (expression is ASTExpressionListLiteral) {
      return generateASTExpressionListLiteral(expression, out: out);
    } else if (expression is ASTExpressionMapLiteral) {
      return generateASTExpressionMapLiteral(expression, out: out);
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
    } else if (expression is ASTExpressionLocalFunctionInvocation) {
      return generateASTExpressionLocalFunctionInvocation(
        expression,
        out: out,
        context: context,
      );
    } else if (expression is ASTExpressionObjectFunctionInvocation) {
      return generateASTExpressionFunctionInvocation(expression, out: out);
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
      return generateASTValueStringVariable(value, out: out);
    } else if (value is ASTValueStringConcatenation) {
      return generateASTValueStringConcatenation(value, out: out);
    } else if (value is ASTValueStringExpression) {
      return generateASTValueStringExpression(value, out: out);
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
  }) {
    // TODO: implement generateASTValueStringConcatenation
    throw UnimplementedError('generateASTValueStringConcatenation');
  }

  @override
  BytesOutput generateASTValueStringExpression(
    ASTValueStringExpression value, {
    BytesOutput? out,
  }) {
    // TODO: implement generateASTValueStringExpression
    throw UnimplementedError('generateASTValueStringExpression');
  }

  @override
  BytesOutput generateASTValueStringVariable(
    ASTValueStringVariable value, {
    BytesOutput? out,
    bool precededByString = false,
  }) {
    // TODO: implement generateASTValueStringVariable
    throw UnimplementedError('generateASTValueStringVariable');
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

  // --- Static data region (interned string literals) ---

  /// Base offset of the static data region in linear memory. Offset `0` is
  /// reserved as a null pointer.
  static const int dataBaseOffset = 8;

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

  /// Minimum memory pages (64 KiB each) needed to hold the static data.
  int get memoryMinPages {
    var end = dataBaseOffset + _data.length;
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

extension _ASTFunctionDeclarationExtension on ASTFunctionDeclaration {
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
