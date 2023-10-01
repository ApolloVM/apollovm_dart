// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:collection';
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

final _astTypeDouble = ASTTypeDouble.instance;

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

    var sectionType = generateSectionType(root);
    var sectionFunction = generateSectionFunction(root, sectionType.functions);
    var sectionExports = generateSectionExport(root, sectionType.functions);
    var sectionCode = generateSectionCode(root, sectionType.functions);

    out.writeBytes(sectionType.bytes, description: "Section: Type");
    out.writeBytes(sectionFunction, description: "Section: Function");
    out.writeBytes(sectionExports, description: "Section: Export");
    out.writeBytes(sectionCode, description: "Section: Code");

    return out;
  }

  BytesOutput generateSectionExport(
      ASTBlock block, List<ASTFunctionDeclaration> functions,
      {BytesOutput? out}) {
    out ??= newOutput();

    var functionsIndexed =
        functions.mapIndexed((i, f) => MapEntry(f, i)).toList();

    var publicFunctions =
        functionsIndexed.where((e) => !e.key.modifiers.isPrivate).toList();

    var entries = publicFunctions.map((f) {
      var fName = f.key.name;
      var fIndex = f.value;

      return BytesOutput(
        data: [
          BytesOutput(
              data: Wasm.encodeString(fName),
              description: "Function name(`$fName`)"),
          BytesOutput(data: 0x00, description: "Export type(function)"),
          BytesOutput(
              data: Leb128.encodeUnsigned(fIndex),
              description: "Type index($fIndex)"),
        ],
        description: "Export function",
      );
    }).toList();

    entries.insert(
        0,
        BytesOutput(
          data: Leb128.encodeUnsigned(entries.length),
          description: "Exported types count",
        ));

    out.writeByte(0x07, description: "Section Export ID");
    out.writeBytesLeb128Block(entries, description: "Exported types");

    return out;
  }

  ({BytesOutput bytes, List<ASTFunctionDeclaration> functions})
      generateSectionType(ASTBlock block, {BytesOutput? out}) {
    out ??= newOutput();

    var functions = block.functions.expand((fs) => fs.functions).toList();

    var entries = functions.map((f) => f.wasmSignature()).toList();
    entries.insert(
        0,
        BytesOutput(
            data: Leb128.encodeUnsigned(entries.length),
            description: "Types count"));

    out.writeByte(0x01, description: "Section Type ID");
    out.writeBytesLeb128Block(entries, description: "Functions signatures");

    return (bytes: out, functions: functions);
  }

  BytesOutput generateSectionFunction(
      ASTBlock block, List<ASTFunctionDeclaration> functions,
      {BytesOutput? out}) {
    out ??= newOutput();

    var indexes =
        functions.mapIndexed((i, e) => Leb128.encodeUnsigned(i)).toList();

    indexes.insert(0, Leb128.encodeUnsigned(indexes.length));

    out.writeByte(0x03, description: "Section Function ID");
    out.writeLeb128Block(indexes, description: "Functions type indexes");

    return out;
  }

  BytesOutput generateSectionCode(
      ASTBlock block, List<ASTFunctionDeclaration<dynamic>> functions,
      {BytesOutput? out}) {
    out ??= newOutput();

    var entries =
        functions.map((f) => generateASTFunctionDeclaration(f)).toList();

    entries.insert(
        0,
        BytesOutput(
            data: Leb128.encodeUnsigned(entries.length),
            description: "Bodies count"));

    out.writeByte(0x0A, description: "Section Code ID");
    out.writeBytesLeb128Block(entries, description: "Functions bodies");

    return out;
  }

  ({ASTType type, int index}) _getLocalVariable(
      WasmContext? context, String name) {
    return context?.getLocalVariable(name) ??
        (throw StateError("Can't find local variable `$name` in context."));
  }

  @override
  BytesOutput generateASTBlock(ASTBlock block,
      {BytesOutput? out, WasmContext? context}) {
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
      generateASTStatement(stm, out: out);
    }

    return out;
  }

  @override
  BytesOutput generateASTBranchIfBlock(ASTBranchIfBlock branch,
      {BytesOutput? out}) {
    // TODO: implement generateASTBranchIfBlock
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTBranchIfElseBlock(ASTBranchIfElseBlock branch,
      {BytesOutput? out}) {
    // TODO: implement generateASTBranchIfElseBlock
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTBranchIfElseIfsElseBlock(
      ASTBranchIfElseIfsElseBlock branch,
      {BytesOutput? out}) {
    // TODO: implement generateASTBranchIfElseIfsElseBlock
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTClass(ASTClassNormal clazz, {BytesOutput? out}) {
    // TODO: implement generateASTClass
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTClassField(ASTClassField field, {BytesOutput? out}) {
    // TODO: implement generateASTClassField
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTClassFunctionDeclaration(ASTClassFunctionDeclaration f,
      {BytesOutput? out}) {
    // TODO: implement generateASTClassFunctionDeclaration
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTExpressionFunctionInvocation(
      ASTExpressionObjectFunctionInvocation expression,
      {BytesOutput? out}) {
    // TODO: implement generateASTExpressionFunctionInvocation
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTExpressionListLiteral(
      ASTExpressionListLiteral expression,
      {BytesOutput? out}) {
    // TODO: implement generateASTExpressionListLiteral
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTExpressionLiteral(ASTExpressionLiteral expression,
      {BytesOutput? out, WasmContext? context}) {
    out ??= newOutput();
    context ??= WasmContext();

    var value = expression.value;

    var stackLng0 = context.stackLength;

    if (value is ASTValueInt) {
      out.write(Wasm.i32Const(value.value),
          description: "[OP] push constant(i32): ${value.value}");
      context.stackPush(ASTTypeInt.instance, "expression literal value");
    } else if (value is ASTValueDouble) {
      out.write(Wasm.f64Const(value.value),
          description: "[OP] push constant(f64): ${value.value}");
      context.stackPush(_astTypeDouble, "expression literal value");
    } else {
      throw UnsupportedError("Can't handle literal: $value");
    }

    context.assertStackLength(
        stackLng0 + 1, "After expression literal value push");

    return out;
  }

  @override
  BytesOutput generateASTExpressionLocalFunctionInvocation(
      ASTExpressionLocalFunctionInvocation expression,
      {BytesOutput? out}) {
    // TODO: implement generateASTExpressionLocalFunctionInvocation
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTExpressionMapLiteral(
      ASTExpressionMapLiteral expression,
      {BytesOutput? out}) {
    // TODO: implement generateASTExpressionMapLiteral
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTExpressionNegation(ASTExpressionNegation expression,
      {BytesOutput? out}) {
    // TODO: implement generateASTExpressionNegation
    throw UnimplementedError();
  }

  void _fixStackOpsAsFloat64(
      ASTType stackType1,
      ASTType stackType2,
      BytesOutput opsOut1,
      BytesOutput opsOut2,
      BytesOutput out,
      WasmContext context) {
    out.writeBytes(opsOut1);

    if (stackType1 == ASTTypeInt.instance) {
      out.writeByte(Wasm.f64ConvertI32S,
          description: "[OP] convert i32 to f64");

      context.stackReplaceAt(1, _astTypeDouble, "Convert i32 to f64");
    }

    if (stackType2 == ASTTypeInt.instance) {
      out.writeBytes(opsOut2);

      out.writeByte(Wasm.f64ConvertI32S,
          description: "[OP] convert i32 to f64");

      context.stackReplace(_astTypeDouble, "Convert i32 to f64");
    } else {
      out.writeBytes(opsOut2);
    }
  }

  ASTTypeDouble? _getOperationType(ASTExpressionOperation expression) {
    return switch (expression.operator) {
      ASTExpressionOperator.divide ||
      ASTExpressionOperator.divideAsDouble ||
      ASTExpressionOperator.divideAsInt =>
        _astTypeDouble,
      _ => null,
    };
  }

  @override
  BytesOutput generateASTExpressionOperation(ASTExpressionOperation expression,
      {BytesOutput? out, WasmContext? context}) {
    out ??= newOutput();
    context ??= WasmContext();

    final stackLng0 = context.stackLength;

    var exp1Out =
        generateASTExpression(expression.expression1, context: context);

    final stackLng1 = context.assertStackLength(
        stackLng0 + 1, "After operation expression (left)");

    final stack1 = context.stackGet(0)!;

    var exp2Out =
        generateASTExpression(expression.expression2, context: context);

    final stackLng2 = context.assertStackLength(
        stackLng1 + 1, "After operation expression (right)");

    final stack2 = context.stackGet(0)!;

    var stackType1 = stack1.type;
    var stackType2 = stack2.type;

    var operationType = _getOperationType(expression);

    if (operationType == _astTypeDouble ||
        (stackType1 == _astTypeDouble || stackType2 == _astTypeDouble)) {
      _fixStackOpsAsFloat64(
          stackType1, stackType2, exp1Out, exp2Out, out, context);
      stackType1 = stackType2 = _astTypeDouble;

      context.assertStackLength(stackLng2, "After stack fix for Float64");
    } else {
      out.writeBytes(exp1Out);
      out.writeBytes(exp2Out);
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
        String opDesc) {
      if (stackType2 == _astTypeDouble) {
        writeOperation(typeDouble, opDouble, descDouble, opDescDouble);
      } else {
        writeOperation(type, op, desc, opDesc);
      }
    }

    switch (expression.operator) {
      case ASTExpressionOperator.add:
        {
          writeOperationDoubleOr(
              _astTypeDouble,
              Wasm.f64Add,
              "add(f64)",
              "f64.add",
              ASTTypeInt.instance,
              Wasm.i32Add,
              "add(i32)",
              "i32.add");
        }
      case ASTExpressionOperator.subtract:
        {
          writeOperationDoubleOr(
              _astTypeDouble,
              Wasm.f64Sub,
              "sub(f64)",
              "f64.sub",
              ASTTypeInt.instance,
              Wasm.i32Sub,
              "sub(i32)",
              "i32.sub");
        }
      case ASTExpressionOperator.multiply:
        {
          writeOperationDoubleOr(
              _astTypeDouble,
              Wasm.f64Mul,
              "multiply(f64)",
              "f64.multiply",
              ASTTypeInt.instance,
              Wasm.i32Mul,
              "multiply(i32)",
              "i32.multiply");
        }
      case ASTExpressionOperator.divide:
        {
          _checkStackStatusBinaryFloat64(stackType1, stackType2);

          out.writeByte(Wasm.f64Div, description: "[OP] operator: divide(f64)");
          context.stackOperationBinary(_astTypeDouble, "f64.divide");
        }
      case ASTExpressionOperator.divideAsInt:
        {
          _checkStackStatusBinaryFloat64(stackType1, stackType2);

          out.writeByte(Wasm.f64Div, description: "[OP] operator: divide(f64)");
          context.stackOperationBinary(_astTypeDouble, "f64.divide");

          out.writeByte(Wasm.i32TruncF64S,
              description: "[OP] i32.truncate_f64_signed");

          context.stackReplace(ASTTypeInt.instance, "i32.truncate_f64_signed");
        }
      case ASTExpressionOperator.divideAsDouble:
        {
          _checkStackStatusBinaryFloat64(stackType1, stackType2);

          out.writeByte(Wasm.f64Div, description: "[OP] operator: divide(f64)");
          context.stackOperationBinary(_astTypeDouble, "f64.divide");
        }
      case ASTExpressionOperator.equals:
        {
          writeOperationDoubleOr(
              ASTTypeInt.instance,
              Wasm.f64Eq,
              "equals(f64)",
              "f64.equals",
              ASTTypeInt.instance,
              Wasm.i32Eq,
              "equals(i32)",
              "i32.equals");
        }
      case ASTExpressionOperator.notEquals:
        {
          writeOperationDoubleOr(
              ASTTypeInt.instance,
              Wasm.f64Ne,
              "notEquals(f64)",
              "f64.NotEq",
              ASTTypeInt.instance,
              Wasm.i32Ne,
              "notEquals(i32)",
              "i32.NotEq");
        }
      case ASTExpressionOperator.greater:
        {
          writeOperationDoubleOr(
              ASTTypeInt.instance,
              Wasm.f64Gt,
              "greaterThan(f64)",
              "f64.greaterThan",
              ASTTypeInt.instance,
              Wasm.i32GtS,
              "greaterThan(i32)",
              "i32.greaterThanSigned");
        }
      case ASTExpressionOperator.greaterOrEq:
        {
          writeOperationDoubleOr(
              ASTTypeInt.instance,
              Wasm.f64Ge,
              "greaterEquals(f64)",
              "f64.greaterEqualsSigned",
              ASTTypeInt.instance,
              Wasm.i32GeS,
              "greaterEquals(i32)",
              "i32.greaterEqualsSigned");
        }
      case ASTExpressionOperator.lower:
        {
          writeOperationDoubleOr(
              ASTTypeInt.instance,
              Wasm.f64Lt,
              "lowerThan(f64)",
              "f64.lowerThanSigned",
              ASTTypeInt.instance,
              Wasm.i32LtS,
              "lowerThan(i32)",
              "i32.lowerThanSigned");
        }
      case ASTExpressionOperator.lowerOrEq:
        {
          writeOperationDoubleOr(
              ASTTypeInt.instance,
              Wasm.f64Le,
              "lowerEquals(f64)",
              "f64.lowerEqualsSigned",
              ASTTypeInt.instance,
              Wasm.i32LeS,
              "lowerEquals(i32)",
              "i32.lowerEqualsSigned");
        }
    }

    context.assertStackLength(stackLng2 - 1, "After operation result");
    context.assertStackLength(stackLng0 + 1, "After operation result");

    return out;
  }

  void _checkStackStatusBinaryFloat64(ASTType stackType1, ASTType stackType2) {
    if (stackType1 != _astTypeDouble || stackType2 != _astTypeDouble) {
      throw StateError(
          "Stack status error> `f64.divide` needs 2 f64 values in the top of the stack");
    }
  }

  @override
  BytesOutput generateASTExpressionVariableAccess(
      ASTExpressionVariableAccess expression,
      {BytesOutput? out,
      WasmContext? context}) {
    out ??= newOutput();
    context ??= WasmContext();

    var name = expression.variable.name;

    var localVar = _getLocalVariable(context, name);

    final stackLng0 = context.stackLength;

    out.write(Wasm.localGet(localVar.index),
        description: "[OP] local get: ${localVar.index} \$$name");

    context.stackPush(localVar.type, 'Local get: ${localVar.index} \$$name');

    context.assertStackLength(
        stackLng0 + 1, "After variable push: ${localVar.index} \$$name");

    return out;
  }

  @override
  BytesOutput generateASTExpressionVariableAssignment(
      ASTExpressionVariableAssignment expression,
      {BytesOutput? out}) {
    // TODO: implement generateASTExpressionVariableAssignment
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTExpressionVariableEntryAccess(
      ASTExpressionVariableEntryAccess expression,
      {BytesOutput? out}) {
    // TODO: implement generateASTExpressionVariableEntryAccess
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTFunctionDeclaration(ASTFunctionDeclaration f,
      {BytesOutput? out, WasmContext? context}) {
    out ??= newOutput();
    context ??= WasmContext();

    var outBody = newOutput();

    var parametersVariables = f.parameters.declaredVariables();

    for (var v in parametersVariables) {
      context.addLocalVariable(v.key, v.value);
    }

    var localVariables = f.statements.declaredVariables();

    outBody.write(Leb128.encodeUnsigned(localVariables.length),
        description: "Local variables count");

    for (var v in localVariables) {
      var astType = v.value;

      context.addLocalVariable(v.key, astType);

      outBody.write(Leb128.encodeUnsigned(1),
          description: "Declared variable count");
      outBody.writeByte(astType.wasmCode,
          description: "Declared variable type(${astType.wasmType.name})");
    }

    for (var stm in f.statements) {
      generateASTStatement(stm, out: outBody, context: context);
    }

    outBody.writeByte(Wasm.end, description: "Code body end");

    out.writeBytesLeb128Block([outBody], description: "Function body");

    return out;
  }

  @override
  BytesOutput generateASTStatement(ASTStatement statement,
      {BytesOutput? out, WasmContext? context}) {
    if (statement is ASTStatementExpression) {
      return generateASTStatementExpression(statement, out: out);
    } else if (statement is ASTStatementVariableDeclaration) {
      return generateASTStatementVariableDeclaration(statement,
          out: out, context: context);
    } else if (statement is ASTBranch) {
      return generateASTBranch(statement, out: out);
    } else if (statement is ASTStatementForLoop) {
      return generateASTStatementForLoop(statement, out: out);
    } else if (statement is ASTStatementReturnNull) {
      return generateASTStatementReturnNull(statement, out: out);
    } else if (statement is ASTStatementReturnValue) {
      return generateASTStatementReturnValue(statement, out: out);
    } else if (statement is ASTStatementReturnVariable) {
      return generateASTStatementReturnVariable(statement,
          out: out, context: context);
    } else if (statement is ASTStatementReturnWithExpression) {
      return generateASTStatementReturnWithExpression(statement, out: out);
    } else if (statement is ASTStatementReturn) {
      return generateASTStatementReturn(statement, out: out);
    }

    throw UnsupportedError("Can't handle statement: $statement");
  }

  @override
  BytesOutput generateASTFunctionParameterDeclaration(
      ASTFunctionParameterDeclaration parameter,
      {BytesOutput? out}) {
    // TODO: implement generateASTFunctionParameterDeclaration
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTParameterDeclaration(ASTParameterDeclaration parameter,
      {BytesOutput? out}) {
    // TODO: implement generateASTParameterDeclaration
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTParametersDeclaration(
      ASTParametersDeclaration parameters,
      {BytesOutput? out}) {
    // TODO: implement generateASTParametersDeclaration
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTScopeVariable(ASTScopeVariable variable,
      {String? callingFunction, BytesOutput? out}) {
    // TODO: implement generateASTScopeVariable
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTStatementExpression(ASTStatementExpression statement,
      {BytesOutput? out}) {
    // TODO: implement generateASTStatementExpression
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTStatementForLoop(ASTStatementForLoop forLoop,
      {BytesOutput? out}) {
    // TODO: implement generateASTStatementForLoop
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTStatementReturn(ASTStatementReturn statement,
      {BytesOutput? out}) {
    // TODO: implement generateASTStatementReturn
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTStatementReturnNull(ASTStatementReturnNull statement,
      {BytesOutput? out}) {
    // TODO: implement generateASTStatementReturnNull
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTStatementReturnValue(ASTStatementReturnValue statement,
      {BytesOutput? out}) {
    // TODO: implement generateASTStatementReturnValue
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTStatementReturnVariable(
      ASTStatementReturnVariable statement,
      {BytesOutput? out,
      WasmContext? context}) {
    out ??= newOutput();
    context ??= WasmContext();

    var variable = statement.variable;
    var name = variable.name;

    var localVar = _getLocalVariable(context, name);

    out.write(Wasm.localGet(localVar.index),
        description: "[OP] local get: ${localVar.index} \$$name (return)");

    context.stackPush(
        localVar.type, 'Local get: ${localVar.index} \$$name (return)');

    return out;
  }

  @override
  BytesOutput generateASTStatementReturnWithExpression(
      ASTStatementReturnWithExpression statement,
      {BytesOutput? out}) {
    // TODO: implement generateASTStatementReturnWithExpression
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTStatementVariableDeclaration(
      ASTStatementVariableDeclaration statement,
      {BytesOutput? out,
      WasmContext? context}) {
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
        stackLng0 + 1, "After variable declaration expression");

    out.write(Wasm.localSet(localVar.index),
        description: "[OP] local set: ${localVar.index} \$$name");

    context.assertStackLength(
        stackLng1, "After variable set: ${localVar.index} \$$name");
    context.assertStackLength(stackLng0 + 1,
        "After variable declaration:  ${localVar.index} \$$name");

    return out;
  }

  @override
  BytesOutput generateASTExpression(ASTExpression expression,
      {BytesOutput? out, WasmContext? context}) {
    if (expression is ASTExpressionVariableAccess) {
      return generateASTExpressionVariableAccess(expression,
          out: out, context: context);
    } else if (expression is ASTExpressionVariableAssignment) {
      return generateASTExpressionVariableAssignment(expression, out: out);
    } else if (expression is ASTExpressionVariableEntryAccess) {
      return generateASTExpressionVariableEntryAccess(expression, out: out);
    } else if (expression is ASTExpressionLiteral) {
      return generateASTExpressionLiteral(expression,
          out: out, context: context);
    } else if (expression is ASTExpressionListLiteral) {
      return generateASTExpressionListLiteral(expression, out: out);
    } else if (expression is ASTExpressionMapLiteral) {
      return generateASTExpressionMapLiteral(expression, out: out);
    } else if (expression is ASTExpressionNegation) {
      return generateASTExpressionNegation(expression, out: out);
    } else if (expression is ASTExpressionLocalFunctionInvocation) {
      return generateASTExpressionLocalFunctionInvocation(expression, out: out);
    } else if (expression is ASTExpressionObjectFunctionInvocation) {
      return generateASTExpressionFunctionInvocation(expression, out: out);
    } else if (expression is ASTExpressionOperation) {
      return generateASTExpressionOperation(expression,
          out: out, context: context);
    }

    throw UnsupportedError("Can't generate expression: $expression");
  }

  @override
  BytesOutput generateASTTypeArray(ASTTypeArray<ASTType, dynamic> type,
      {BytesOutput? out}) {
    // TODO: implement generateASTTypeArray
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTTypeArray2D(ASTTypeArray2D<ASTType, dynamic> type,
      {BytesOutput? out}) {
    // TODO: implement generateASTTypeArray2D
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTTypeArray3D(ASTTypeArray3D<ASTType, dynamic> type,
      {BytesOutput? out}) {
    // TODO: implement generateASTTypeArray3D
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTTypeDefault(ASTType type, {BytesOutput? out}) {
    // TODO: implement generateASTTypeDefault
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTValueArray(ASTValueArray<ASTType, dynamic> value,
      {BytesOutput? out}) {
    // TODO: implement generateASTValueArray
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTValueArray2D(ASTValueArray2D<ASTType, dynamic> value,
      {BytesOutput? out}) {
    // TODO: implement generateASTValueArray2D
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTValueArray3D(ASTValueArray3D<ASTType, dynamic> value,
      {BytesOutput? out}) {
    // TODO: implement generateASTValueArray3D
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTValueDouble(ASTValueDouble value, {BytesOutput? out}) {
    // TODO: implement generateASTValueDouble
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTValueInt(ASTValueInt value, {BytesOutput? out}) {
    // TODO: implement generateASTValueInt
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTValueNull(ASTValueNull value, {BytesOutput? out}) {
    // TODO: implement generateASTValueNull
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTValueObject(ASTValueObject value, {BytesOutput? out}) {
    // TODO: implement generateASTValueObject
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTValueStatic(ASTValueStatic value, {BytesOutput? out}) {
    // TODO: implement generateASTValueStatic
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTValueString(ASTValueString value, {BytesOutput? out}) {
    // TODO: implement generateASTValueString
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTValueStringConcatenation(
      ASTValueStringConcatenation value,
      {BytesOutput? out}) {
    // TODO: implement generateASTValueStringConcatenation
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTValueStringExpression(ASTValueStringExpression value,
      {BytesOutput? out}) {
    // TODO: implement generateASTValueStringExpression
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTValueStringVariable(ASTValueStringVariable value,
      {BytesOutput? out, bool precededByString = false}) {
    // TODO: implement generateASTValueStringVariable
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTValueVar(ASTValueVar value, {BytesOutput? out}) {
    // TODO: implement generateASTValueVar
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTVariable(ASTVariable variable,
      {String? callingFunction, BytesOutput? out}) {
    // TODO: implement generateASTVariable
    throw UnimplementedError();
  }

  @override
  BytesOutput generateASTVariableGeneric(ASTVariable variable,
      {String? callingFunction, BytesOutput? out}) {
    // TODO: implement generateASTVariableGeneric
    throw UnimplementedError();
  }

  @override
  String resolveASTExpressionOperatorText(ASTExpressionOperator operator,
      ASTNumType aNumType, ASTNumType bNumType) {
    // TODO: implement resolveASTExpressionOperatorText
    throw UnimplementedError();
  }
}

/// The Wasm code context.
class WasmContext {
  final Map<String, ({ASTType type, int index})> _localVariables = {};

  ({ASTType type, int index})? getLocalVariable(String name) {
    return _localVariables[name];
  }

  /// Returns the type of a local variable by [name].
  ASTType? getLocalVariableType(String name) {
    return _localVariables[name]?.type;
  }

  /// Returns the type of a local variable by [index].
  ASTType? getLocalVariableTypeByIndex(int index) {
    return _localVariables.values
        .firstWhereOrNull((e) => e.index == index)
        ?.type;
  }

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
            "Variable `$name` ($type) already defined with a different type: $prevType");
      } else {
        return prev.index;
      }
    }

    var entry = (type: type, index: _localVariables.length);
    _localVariables[name] = entry;
    return entry.index;
  }

  final ListQueue<({ASTType type, String description})> _stack = ListQueue();

  /// The length of the stack.
  int get stackLength => _stack.length;

  /// Asserts the stack length.
  int assertStackLength([int? expectedLength, String? description]) {
    var currentLength = stackLength;

    if (currentLength != expectedLength) {
      throw StateError(
          "Invalid stack length> stackLength: $stackLength != expected: $expectedLength${description != null ? ' ($description)' : ''}");
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
          "Drop from stack error> Empty stack! Expected type: $expectedType");
    }

    var entry = _stack.removeLast();
    if (expectedType != null && entry.type != expectedType) {
      throw StateError(
          "Drop from stack error> Not expected type: stack.drop:${entry.type} != expected:$expectedType");
    }
    return entry;
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
  void stackReplace(ASTType type, String description,
      [ASTType? expectedType1]) {
    stackDrop(expectedType1);
    stackPush(type, description);
  }

  /// Replaces a stack entry at [index].
  void stackReplaceAt(int index, ASTType type, String description,
      [ASTType? expectedType1]) {
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
        "Can't find stack index: $index (stack length: $stackLength");
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
}

extension _ASTTypeExtension on ASTType {
  bool get isVoid => this is ASTTypeVoid || name == 'void';

  WasmType get wasmType {
    if (this is ASTTypeString) {
    } else if (this is ASTTypeInt) {
      return WasmType.i32Type;
    } else if (this is ASTTypeDouble) {
      return WasmType.f32Type;
    } else if (this is ASTTypeVoid) {
      return WasmType.voidType;
    } else if (name == 'void') {
      return WasmType.voidType;
    }

    throw StateError("Can;t handle type: $this");
  }

  int get wasmCode => wasmType.value;
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
      out.write(
          [...Leb128.encodeUnsigned(allParameters.length), ...allParameters],
          description: "Parameters types");
    } else {
      out.writeByte(0, description: "No parameters");
    }

    if (!returnType.isVoid) {
      out.write([...Leb128.encodeUnsigned(1), returnType.wasmCode],
          description: "Return value");
    } else {
      out.writeByte(0, description: "No return value");
    }

    return out;
  }
}

extension _ASTStatementExtension on ASTStatement {
  List<MapEntry<String, ASTType>> declaredVariables() {
    final self = this;
    if (self is ASTStatementVariableDeclaration) {
      return [MapEntry(self.name, self.type)];
    } else if (self is ASTBranchIfBlock) {
      return self.block.declaredVariables();
    } else if (self is ASTBranchIfElseBlock) {
      return [
        ...self.blockIf.declaredVariables(),
        ...self.blockElse.declaredVariables()
      ];
    } else if (self is ASTBranchIfElseIfsElseBlock) {
      return [
        ...self.blockIf.declaredVariables(),
        ...self.blocksElseIf.declaredVariables(),
        ...self.blockElse.declaredVariables()
      ];
    }

    return [];
  }
}

extension _IterableASTStatementExtension on Iterable<ASTStatement> {
  List<MapEntry<String, ASTType>> declaredVariables() =>
      expand((e) => e.declaredVariables()).toList();
}

extension _ASTBlockExtension on ASTBlock {
  List<MapEntry<String, ASTType>> declaredVariables() =>
      statements.expand((e) => e.declaredVariables()).toList();
}

extension _ASTFunctionParameterDeclarationExtension
    on ASTFunctionParameterDeclaration {
  List<MapEntry<String, ASTType>> declaredVariables() =>
      [MapEntry<String, ASTType>(name, type)];
}

extension _IterableASTFunctionParameterDeclarationExtension
    on Iterable<ASTFunctionParameterDeclaration> {
  List<MapEntry<String, ASTType>> declaredVariables() =>
      expand((e) => e.declaredVariables()).toList();
}

extension _ASTParametersDeclarationExtension on ASTParametersDeclaration {
  List<MapEntry<String, ASTType>> declaredVariables() => [
        ...?positionalParameters?.declaredVariables(),
        ...?optionalParameters?.declaredVariables(),
        ...?namedParameters?.declaredVariables(),
      ];
}
