// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import '../../apollovm_code_generator.dart';
import '../../apollovm_code_storage.dart';
import '../../ast/apollovm_ast_expression.dart';
import '../../ast/apollovm_ast_statement.dart';
import '../../ast/apollovm_ast_toplevel.dart';
import '../../ast/apollovm_ast_type.dart';
import '../../ast/apollovm_ast_value.dart';
import '../../ast/apollovm_ast_variable.dart';

/// Python 3 implementation of an [ApolloCodeGenerator].
///
/// Emits strict, idiomatic Python: 4-space indentation-based blocks (no braces),
/// PEP-484 type hints when the AST type is statically known (`def f(x: int) ->
/// int:`, `x: str = ...`, `List[T]`/`Dict[K, V]`) with a dynamic/untyped
/// fallback otherwise, `==`/`!=`, `and`/`or`/`not`, `//` integer division,
/// `True`/`False`/`None`, f-strings for interpolation, and `self`-based methods.
class ApolloCodeGeneratorPython extends ApolloCodeGenerator {
  ApolloCodeGeneratorPython(ApolloSourceCodeStorage codeStorage)
    : super('python', codeStorage);

  static const String _tab = '    ';

  /// Python keyword arguments are emitted as `name=value` (no spaces).
  @override
  String get namedArgumentSeparator => '=';

  /// Python parameter defaults are emitted as `name=value` (no spaces).
  @override
  String get parameterDefaultValueSeparator => '=';

  // -----------------------------------------------------------------
  // Types.
  // -----------------------------------------------------------------
  @override
  String normalizeTypeName(String typeName, [String? callingFunction]) {
    switch (typeName) {
      case 'int':
      case 'Integer':
        return 'int';
      case 'double':
      case 'Double':
      case 'num':
        return 'float';
      case 'String':
        return 'str';
      case 'bool':
      case 'Boolean':
        return 'bool';
      case 'void':
      case 'Null':
        return 'None';
      case 'Object':
        return 'object';
      case 'dynamic':
        return 'object';
      case 'List':
        return 'List';
      case 'Map':
        return 'Dict';
      default:
        return typeName;
    }
  }

  @override
  StringBuffer generateASTType(
    ASTType type, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    out.write(normalizeTypeName(type.name));

    var generics = type.generics;
    if (generics != null && generics.isNotEmpty) {
      out.write('[');
      for (var i = 0; i < generics.length; ++i) {
        if (i > 0) out.write(', ');
        generateASTType(generics[i], out: out);
      }
      out.write(']');
    }

    return out;
  }

  @override
  StringBuffer generateASTTypeArray(
    ASTTypeArray type, {
    StringBuffer? out,
    String indent = '',
  }) => generateASTType(type, out: out, indent: indent);

  @override
  StringBuffer generateASTTypeArray2D(
    ASTTypeArray2D type, {
    StringBuffer? out,
    String indent = '',
  }) => generateASTType(type, out: out, indent: indent);

  @override
  StringBuffer generateASTTypeArray3D(
    ASTTypeArray3D type, {
    StringBuffer? out,
    String indent = '',
  }) => generateASTType(type, out: out, indent: indent);

  /// Whether [type] should be emitted as a hint (static resolution). Dynamic /
  /// inferred-unknown types fall back to no annotation.
  bool _isAnnotatable(ASTType? type) {
    if (type == null) return false;
    if (type is ASTTypeDynamic || type is ASTTypeVar || type is ASTTypeNull) {
      return false;
    }
    var n = type.name;
    return n.isNotEmpty && n != 'dynamic' && n != '?' && n != 'var';
  }

  /// Resolves a declaration/parameter type statically (e.g. `var` → its
  /// inferred value type), used to decide whether a hint can be emitted.
  ASTType? _staticType(ASTType type) {
    if (type is ASTTypeVar) {
      var resolved = type.resolveType(null);
      if (resolved is ASTType) return resolved;
      return null;
    }
    return type;
  }

  // -----------------------------------------------------------------
  // Imports.
  // -----------------------------------------------------------------
  @override
  StringBuffer generateASTStatementImport(
    ASTStatementImport import, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();
    out.write('import ');
    out.write(import.path);
    var prefix = import.prefix;
    if (prefix != null) {
      out.write(' as ');
      out.write(prefix);
    }
    out.write('\n');
    return out;
  }

  // -----------------------------------------------------------------
  // Blocks / suites.
  // -----------------------------------------------------------------
  @override
  StringBuffer generateASTBlock(
    ASTBlock block, {
    StringBuffer? out,
    String indent = '',
    bool withBrackets = true,
    bool withBlankHeadLine = false,
  }) {
    out ??= newOutput();

    for (var set in block.functions) {
      for (var f in set.functions) {
        if (f is ASTClassFunctionDeclaration) {
          generateASTClassFunctionDeclaration(f, out: out, indent: indent);
        } else {
          generateASTFunctionDeclaration(f, out: out, indent: indent);
        }
      }
    }

    for (var stm in block.statements) {
      generateASTStatement(stm, out: out, indent: indent);
    }

    return out;
  }

  /// Emits a suite body at [indent], writing `pass` when the block is empty.
  void _writeSuite(ASTBlock block, StringBuffer out, String indent) {
    var before = out.length;
    generateASTBlock(block, out: out, indent: indent);
    if (out.length == before) {
      out.write(indent);
      out.write('pass\n');
    }
  }

  // -----------------------------------------------------------------
  // Functions / methods.
  // -----------------------------------------------------------------
  @override
  StringBuffer generateASTFunctionDeclaration(
    ASTFunctionDeclaration f, {
    StringBuffer? out,
    String indent = '',
  }) => _generateFunction(f, out: out, indent: indent, isMethod: false);

  @override
  StringBuffer generateASTClassFunctionDeclaration(
    ASTClassFunctionDeclaration f, {
    StringBuffer? out,
    String indent = '',
  }) => _generateFunction(f, out: out, indent: indent, isMethod: true);

  StringBuffer _generateFunction(
    ASTFunctionDeclaration f, {
    StringBuffer? out,
    String indent = '',
    required bool isMethod,
  }) {
    out ??= newOutput();

    out.write(indent);
    if (f.modifiers.isAsync) {
      out.write('async ');
    }
    out.write('def ');
    out.write(f.name);
    out.write('(');

    var wroteParam = false;
    if (isMethod) {
      out.write('self');
      wroteParam = true;
    }
    if (f.parametersSize > 0) {
      if (wroteParam) out.write(', ');
      generateASTParametersDeclaration(f.parameters, out: out);
    }
    out.write(')');

    var returnType = f.returnType;
    if (returnType is! ASTTypeDynamic) {
      out.write(' -> ');
      generateASTType(returnType, out: out);
    }

    out.write(':\n');

    _writeSuite(f, out, '$indent$_tab');
    out.write('\n');

    return out;
  }

  @override
  StringBuffer generateASTParametersDeclaration(
    ASTParametersDeclaration parameters, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    // Python declares all parameters positionally (any can be passed as a
    // keyword argument at the call site), so positional + optional + named are
    // emitted as a single flat, comma-separated list.
    var wrote = 0;
    for (var p in parameters.allParameters) {
      if (wrote > 0) out.write(', ');
      generateASTParameterDeclaration(p, out: out);
      ++wrote;
    }

    return out;
  }

  @override
  StringBuffer generateASTFunctionParameterDeclaration(
    ASTFunctionParameterDeclaration parameter, {
    StringBuffer? out,
    String indent = '',
  }) => generateASTParameterDeclaration(parameter, out: out, indent: indent);

  @override
  StringBuffer generateASTParameterDeclaration(
    ASTParameterDeclaration parameter, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    out.write(parameter.name);

    var type = _staticType(parameter.type);
    if (_isAnnotatable(type)) {
      out.write(': ');
      generateASTType(type!, out: out);
    }

    appendParameterDefaultValue(parameter, out, indent);

    return out;
  }

  // -----------------------------------------------------------------
  // Classes.
  // -----------------------------------------------------------------
  @override
  StringBuffer generateASTClass(
    ASTClassNormal clazz, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    if (clazz is ASTClassEnum) {
      return generateASTClassEnum(clazz, out: out, indent: indent);
    }

    out.write(indent);
    out.write('class ');
    out.write(clazz.name);

    var superName = clazz.superClassName;
    if (superName != null) {
      out.write('(');
      out.write(superName);
      out.write(')');
    }

    out.write(':\n');

    var bodyIndent = '$indent$_tab';
    var before = out.length;

    for (var field in clazz.fields) {
      generateASTClassField(field, out: out, indent: bodyIndent);
    }
    if (clazz.fields.isNotEmpty) out.write('\n');

    for (var set in clazz.constructors) {
      for (var c in set.functions) {
        generateASTClassConstructorDeclaration(c, out: out, indent: bodyIndent);
      }
    }

    for (var set in clazz.functions) {
      for (var f in set.functions) {
        _generateFunction(f, out: out, indent: bodyIndent, isMethod: true);
      }
    }

    if (out.length == before) {
      out.write(bodyIndent);
      out.write('pass\n');
    }

    out.write('\n');

    return out;
  }

  /// Returns `true` if [clazz] is a rich/enhanced enum (entries with
  /// constructor arguments, or declared fields/constructors/methods). A rich
  /// enum can't map to a `Enum` subclass with plain members, so it's emitted as
  /// a plain class with class-level singleton instances.
  bool _isRichEnum(ASTClassEnum clazz) =>
      clazz.entries.any((e) => e.arguments != null) ||
      clazz.fields.isNotEmpty ||
      clazz.constructors.isNotEmpty ||
      clazz.functions.isNotEmpty;

  /// Generates a Python enum: `class Name(Enum):` with `NAME = value` members.
  /// Members without an explicit value get their ordinal index.
  ///
  /// A rich/enhanced enum is emitted as a plain class with an `__init__` and
  /// class-level singleton instances assigned after the class (see
  /// [_isRichEnum]).
  StringBuffer generateASTClassEnum(
    ASTClassEnum clazz, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    if (_isRichEnum(clazz)) {
      return _generateRichEnumPython(clazz, out, indent);
    }

    out.write(indent);
    out.write('class ');
    out.write(clazz.name);
    out.write('(Enum):\n');

    var bodyIndent = '$indent$_tab';
    var entries = clazz.entries;
    if (entries.isEmpty) {
      out.write(bodyIndent);
      out.write('pass\n');
    }
    for (var i = 0; i < entries.length; ++i) {
      var e = entries[i];
      out.write(bodyIndent);
      out.write(e.name);
      out.write(' = ');
      if (e.value != null) {
        generateASTExpression(e.value!, out: out, headIndented: false);
      } else {
        out.write('$i');
      }
      out.write('\n');
    }
    out.write('\n');

    return out;
  }

  /// Emits a rich/enhanced enum as a plain Python class: an `__init__` that
  /// assigns the declared fields, the methods, and class-level singleton
  /// instances assigned after the class body (so the type already exists),
  /// plus a `values` list.
  StringBuffer _generateRichEnumPython(
    ASTClassEnum clazz,
    StringBuffer out,
    String indent,
  ) {
    var bodyIndent = '$indent$_tab';
    var name = clazz.name;

    out.write(indent);
    out.write('class ');
    out.write(name);
    out.write(':\n');

    var before = out.length;

    // __init__ from the enum constructor (assigns the declared fields).
    var ctor = clazz.constructors.isNotEmpty
        ? clazz.constructors.first.firstFunction
        : null;
    if (ctor != null) {
      var params = ctor.parameters.allParameters;
      out.write(bodyIndent);
      out.write('def __init__(self');
      for (var p in params) {
        out.write(', ');
        out.write(p.name);
      }
      out.write('):\n');
      var assigned = false;
      for (var p in params) {
        if (p.thisParameter) {
          out.write('$bodyIndent${_tab}self.${p.name} = ${p.name}\n');
          assigned = true;
        }
      }
      if (!assigned) {
        out.write('$bodyIndent${_tab}pass\n');
      }
      out.write('\n');
    }

    // Methods.
    for (var set in clazz.functions) {
      for (var f in set.functions) {
        _generateFunction(f, out: out, indent: bodyIndent, isMethod: true);
      }
    }

    if (out.length == before) {
      out.write(bodyIndent);
      out.write('pass\n');
    }

    out.write('\n');

    // Class-level singleton instances, assigned after the class so the type
    // already exists when constructing them.
    for (var e in clazz.entries) {
      out.write(indent);
      out.write('$name.${e.name} = $name(');
      var args = e.arguments;
      if (args != null) {
        for (var i = 0; i < args.length; ++i) {
          if (i > 0) out.write(', ');
          generateASTExpression(args[i], out: out, headIndented: false);
        }
      }
      out.write(')\n');
    }

    // Values list.
    out.write(indent);
    out.write('$name.values = [');
    out.write(clazz.entries.map((e) => '$name.${e.name}').join(', '));
    out.write(']\n');

    out.write('\n');

    return out;
  }

  @override
  StringBuffer generateASTClassField(
    ASTClassField field, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    out.write(indent);
    out.write(field.name);

    var type = _staticType(field.type);
    if (_isAnnotatable(type)) {
      out.write(': ');
      generateASTType(type!, out: out);
    }

    if (field is ASTClassFieldWithInitialValue) {
      out.write(' = ');
      generateASTExpression(field.initialValue, out: out, headIndented: false);
    }

    out.write('\n');
    return out;
  }

  @override
  StringBuffer generateASTClassConstructorDeclaration(
    ASTClassConstructorDeclaration constructor, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    // Python's constructor is the `__init__(self, ...)` method.
    out.write(indent);
    out.write('def __init__(self');
    if (constructor.parametersSize > 0) {
      out.write(', ');
      generateASTParametersDeclaration(constructor.parameters, out: out);
    }
    out.write('):\n');

    _writeSuite(constructor, out, '$indent$_tab');
    out.write('\n');

    return out;
  }

  @override
  StringBuffer generateASTValueArray(
    ASTValueArray value, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    out.write(value.value);
    return out;
  }

  @override
  StringBuffer generateASTValueArray2D(
    ASTValueArray2D value, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    out.write(value.value);
    return out;
  }

  @override
  StringBuffer generateASTValueArray3D(
    ASTValueArray3D value, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    out.write(value.value);
    return out;
  }

  // -----------------------------------------------------------------
  // Statements.
  // -----------------------------------------------------------------
  @override
  StringBuffer generateASTStatementExpression(
    ASTStatementExpression statement, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);
    generateASTExpression(statement.expression, out: out, headIndented: false);
    out.write('\n');
    return out;
  }

  @override
  StringBuffer generateASTStatementVariableDeclaration(
    ASTStatementVariableDeclaration statement, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);

    out.write(statement.name);

    var type = _staticType(statement.type);
    if (_isAnnotatable(type)) {
      out.write(': ');
      generateASTType(type!, out: out);
    }

    if (statement.value != null) {
      out.write(' = ');
      generateASTExpression(statement.value!, out: out, headIndented: false);
    }

    out.write('\n');
    return out;
  }

  @override
  StringBuffer generateASTStatementReturn(
    ASTStatementReturn statement, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);
    out.write('return\n');
    return out;
  }

  @override
  StringBuffer generateASTStatementBreak(
    ASTStatementBreak statement, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);
    out.write('break\n');
    return out;
  }

  @override
  StringBuffer generateASTStatementContinue(
    ASTStatementContinue statement, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);
    out.write('continue\n');
    return out;
  }

  /// Python uses `match`/`case` (no fall-through); `case _:` is the default.
  @override
  StringBuffer generateASTStatementSwitch(
    ASTStatementSwitch statement, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);

    out.write('match ');
    generateASTExpression(statement.expression, out: out, headIndented: false);
    out.write(':\n');

    var caseIndent = '$indent$_tab';
    var bodyIndent = '$caseIndent$_tab';
    for (var c in statement.cases) {
      out.write(caseIndent);
      if (c.isDefault) {
        out.write('case _:\n');
      } else {
        out.write('case ');
        generateASTExpression(c.value!, out: out, headIndented: false);
        out.write(':\n');
      }
      _writeSuite(c.block, out, bodyIndent);
    }

    return out;
  }

  @override
  StringBuffer generateASTStatementReturnNull(
    ASTStatementReturnNull statement, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);
    out.write('return None\n');
    return out;
  }

  @override
  StringBuffer generateASTStatementReturnValue(
    ASTStatementReturnValue statement, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);
    out.write('return ');
    generateASTValue(statement.value, out: out, headIndented: false);
    out.write('\n');
    return out;
  }

  @override
  StringBuffer generateASTStatementReturnVariable(
    ASTStatementReturnVariable statement, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);
    out.write('return ');
    generateASTVariable(statement.variable, out: out, headIndented: false);
    out.write('\n');
    return out;
  }

  @override
  StringBuffer generateASTStatementReturnWithExpression(
    ASTStatementReturnWithExpression statement, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);
    out.write('return ');
    generateASTExpression(statement.expression, out: out, headIndented: false);
    out.write('\n');
    return out;
  }

  @override
  StringBuffer generateASTStatementThrow(
    ASTStatementThrow statement, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);
    out.write('raise ');
    generateASTExpression(statement.expression, out: out, headIndented: false);
    out.write('\n');
    return out;
  }

  @override
  StringBuffer generateASTStatementTryCatch(
    ASTStatementTryCatch tryCatch, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);

    out.write('try:\n');
    _writeSuite(tryCatch.tryBlock, out, '$indent$_tab');

    for (var catchClause in tryCatch.catches) {
      out.write(indent);
      out.write('except');
      var type = catchClause.exceptionType;
      if (type != null) {
        out.write(' ');
        generateASTType(type, out: out);
        var name = catchClause.variableName;
        if (name != null) {
          out.write(' as ');
          out.write(name);
        }
      }
      out.write(':\n');
      _writeSuite(catchClause.block, out, '$indent$_tab');
    }

    var finallyBlock = tryCatch.finallyBlock;
    if (finallyBlock != null) {
      out.write(indent);
      out.write('finally:\n');
      _writeSuite(finallyBlock, out, '$indent$_tab');
    }

    return out;
  }

  // -----------------------------------------------------------------
  // Branches.
  // -----------------------------------------------------------------
  @override
  StringBuffer generateASTBranchIfBlock(
    ASTBranchIfBlock branch, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);

    out.write('if ');
    generateASTExpression(branch.condition, out: out, headIndented: false);
    out.write(':\n');
    _writeSuite(branch.block, out, '$indent$_tab');

    return out;
  }

  @override
  StringBuffer generateASTBranchIfElseBlock(
    ASTBranchIfElseBlock branch, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);

    out.write('if ');
    generateASTExpression(branch.condition, out: out, headIndented: false);
    out.write(':\n');
    _writeSuite(branch.blockIf, out, '$indent$_tab');

    var blockElse = branch.blockElse;
    out.write(indent);
    out.write('else:\n');
    if (blockElse != null) {
      _writeSuite(blockElse, out, '$indent$_tab');
    } else {
      out.write('$indent$_tab');
      out.write('pass\n');
    }

    return out;
  }

  @override
  StringBuffer generateASTBranchIfElseIfsElseBlock(
    ASTBranchIfElseIfsElseBlock branch, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);

    out.write('if ');
    generateASTExpression(branch.condition, out: out, headIndented: false);
    out.write(':\n');
    _writeSuite(branch.blockIf, out, '$indent$_tab');

    for (var elseIf in branch.blocksElseIf) {
      out.write(indent);
      out.write('elif ');
      generateASTExpression(elseIf.condition, out: out, headIndented: false);
      out.write(':\n');
      _writeSuite(elseIf.block, out, '$indent$_tab');
    }

    var blockElse = branch.blockElse;
    if (blockElse != null) {
      out.write(indent);
      out.write('else:\n');
      _writeSuite(blockElse, out, '$indent$_tab');
    }

    return out;
  }

  // -----------------------------------------------------------------
  // Loops.
  // -----------------------------------------------------------------
  @override
  StringBuffer generateASTStatementForEach(
    ASTStatementForEach forEach, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);

    out.write('for ');
    out.write(forEach.variableName);
    out.write(' in ');
    generateASTExpression(
      forEach.iterableExpression,
      out: out,
      headIndented: false,
    );
    out.write(':\n');
    _writeSuite(forEach.loopBlock, out, '$indent$_tab');

    return out;
  }

  @override
  StringBuffer generateASTStatementWhileLoop(
    ASTStatementWhileLoop whileLoop, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);

    out.write('while ');
    generateASTExpression(
      whileLoop.conditionExpression,
      out: out,
      headIndented: false,
    );
    out.write(':\n');
    _writeSuite(whileLoop.loopBlock, out, '$indent$_tab');

    return out;
  }

  /// A C-style `for (init; cond; cont)` (e.g. from another language) becomes a
  /// `while` loop, the faithful Python translation.
  @override
  StringBuffer generateASTStatementForLoop(
    ASTStatementForLoop forLoop, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    generateASTStatement(forLoop.initStatement, out: out, indent: indent);

    out.write(indent);
    out.write('while ');
    generateASTExpression(
      forLoop.conditionExpression,
      out: out,
      headIndented: false,
    );
    out.write(':\n');

    var bodyIndent = '$indent$_tab';
    _writeSuite(forLoop.loopBlock, out, bodyIndent);
    generateASTExpression(
      forLoop.continueExpression,
      out: out,
      indent: bodyIndent,
      headIndented: true,
    );
    out.write('\n');

    return out;
  }

  // -----------------------------------------------------------------
  // Expressions / operators.
  // -----------------------------------------------------------------
  @override
  String resolveASTExpressionOperatorText(
    ASTExpressionOperator operator,
    ASTNumType aNumType,
    ASTNumType bNumType,
  ) {
    switch (operator) {
      case ASTExpressionOperator.and:
        return 'and';
      case ASTExpressionOperator.or:
        return 'or';
      case ASTExpressionOperator.divideAsInt:
        return '//';
      case ASTExpressionOperator.divide:
      case ASTExpressionOperator.divideAsDouble:
        return '/';
      default:
        return getASTExpressionOperatorText(operator);
    }
  }

  @override
  StringBuffer generateASTExpressionLiteralFunction(
    ASTExpressionLiteralFunction expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);

    var f = expression.function;

    // Python anonymous functions are `lambda params: expr` and can only hold a
    // single expression.
    var single = singleReturnExpression(f);
    if (single == null) {
      throw UnsupportedError(
        "Python `lambda` only supports a single-expression body: $f",
      );
    }

    out.write('lambda');
    if (f.parametersSize > 0) {
      out.write(' ');
      generateASTParametersDeclaration(f.parameters, out: out);
    }
    out.write(': ');
    generateASTExpression(single, out: out, headIndented: false);

    return out;
  }

  @override
  StringBuffer generateASTExpressionConditional(
    ASTExpressionConditional expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);

    // Python's conditional expression: `valueIfTrue if condition else
    // valueIfFalse`.
    generateASTExpression(
      expression.valueIfTrue,
      out: out,
      headIndented: false,
    );
    out.write(' if ');
    generateASTExpression(expression.condition, out: out, headIndented: false);
    out.write(' else ');
    generateASTExpression(
      expression.valueIfFalse,
      out: out,
      headIndented: false,
    );

    return out;
  }

  @override
  StringBuffer generateASTExpressionNegation(
    ASTExpressionNegation expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);

    out.write('not ');

    final inner = expression.expression;
    final group = inner.isComplex;

    if (group) out.write('(');
    generateASTExpression(inner, out: out, headIndented: false);
    if (group) out.write(')');

    return out;
  }

  @override
  StringBuffer generateASTExpressionVariableAssignment(
    ASTExpressionVariableAssignment expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);

    generateASTVariable(expression.variable, out: out, headIndented: false);

    out.write(' ');
    out.write(_assignmentOperatorText(expression.operator));
    out.write(' ');
    generateASTExpression(expression.expression, out: out, headIndented: false);

    return out;
  }

  String _assignmentOperatorText(ASTAssignmentOperator operator) {
    var text = getASTAssignmentOperatorText(operator);
    return text == '~/=' ? '//=' : text;
  }

  @override
  StringBuffer generateASTExpressionVariableDirectOperation(
    ASTExpressionVariableDirectOperation expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);

    // Python has no `++`/`--`; emit the equivalent augmented assignment.
    generateASTVariable(expression.variable, out: out, headIndented: false);
    var op = getASTAssignmentDirectOperatorText(expression.operator);
    out.write(op == '++' ? ' += 1' : ' -= 1');

    return out;
  }

  @override
  StringBuffer generateASTExpressionListLiteral(
    ASTExpressionListLiteral expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);

    out.write('[');
    var valuesExpressions = expression.valuesExpressions;
    for (var i = 0; i < valuesExpressions.length; ++i) {
      if (i > 0) out.write(', ');
      generateASTExpression(
        valuesExpressions[i],
        out: out,
        headIndented: false,
      );
    }
    out.write(']');

    return out;
  }

  @override
  StringBuffer generateASTExpressionMapLiteral(
    ASTExpressionMapLiteral expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);

    out.write('{');
    var entriesExpressions = expression.entriesExpressions;
    for (var i = 0; i < entriesExpressions.length; ++i) {
      var e = entriesExpressions[i];
      if (i > 0) out.write(', ');
      generateASTExpression(e.key, out: out, headIndented: false);
      out.write(': ');
      generateASTExpression(e.value, out: out, headIndented: false);
    }
    out.write('}');

    return out;
  }

  @override
  StringBuffer generateASTExpressionNullValue(
    ASTExpressionNullValue expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);
    out.write('None');
    return out;
  }

  // -----------------------------------------------------------------
  // Variables.
  // -----------------------------------------------------------------
  @override
  StringBuffer generateASTVariableGeneric(
    ASTVariable variable, {
    String? callingFunction,
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);
    out.write(variable is ASTThisVariable ? 'self' : variable.name);
    return out;
  }

  // -----------------------------------------------------------------
  // Values.
  // -----------------------------------------------------------------
  @override
  StringBuffer generateASTValueStatic(
    ASTValueStatic value, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    if (value is ASTValueBool) {
      out ??= newOutput();
      if (headIndented) out.write(indent);
      out.write(value.value ? 'True' : 'False');
      return out;
    }
    return super.generateASTValueStatic(
      value,
      out: out,
      indent: indent,
      headIndented: headIndented,
    );
  }

  @override
  StringBuffer generateASTValueNull(
    ASTValueNull value, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);
    out.write('None');
    return out;
  }

  @override
  StringBuffer generateASTValueString(
    ASTValueString value, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);
    out.write(_quote(value.value));
    return out;
  }

  @override
  StringBuffer generateASTValueStringConcatenation(
    ASTValueStringConcatenation value, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();
    out.write("f'");
    _writeFStringParts(value.values, out);
    out.write("'");
    return out;
  }

  @override
  StringBuffer generateASTValueStringExpression(
    ASTValueStringExpression value, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();
    out.write("f'{");
    generateASTExpression(value.expression, out: out, headIndented: false);
    out.write("}'");
    return out;
  }

  @override
  StringBuffer generateASTValueStringVariable(
    ASTValueStringVariable value, {
    StringBuffer? out,
    String indent = '',
    bool precededByString = false,
  }) {
    out ??= newOutput();
    out.write("f'{");
    out.write(value.variable.name);
    out.write("}'");
    return out;
  }

  void _writeFStringParts(List<ASTValue> parts, StringBuffer out) {
    for (var p in parts) {
      if (p is ASTValueStringExpression) {
        out.write('{');
        generateASTExpression(p.expression, out: out, headIndented: false);
        out.write('}');
      } else if (p is ASTValueStringVariable) {
        out.write('{');
        out.write(p.variable.name);
        out.write('}');
      } else if (p is ASTValueStringConcatenation) {
        _writeFStringParts(p.values, out);
      } else if (p is ASTValueString) {
        out.write(_escapeFStringSingle(p.value));
      }
    }
  }

  /// Renders a Python string literal, preferring single quotes.
  static String _quote(String s) {
    var escaped = s
        .replaceAll('\\', r'\\')
        .replaceAll('\t', r'\t')
        .replaceAll('\r', r'\r')
        .replaceAll('\n', r'\n');

    if (!escaped.contains("'")) {
      return "'$escaped'";
    } else if (!escaped.contains('"')) {
      return '"$escaped"';
    } else {
      return "'${escaped.replaceAll("'", r"\'")}'";
    }
  }

  /// Escapes a literal chunk for inclusion in a single-quoted f-string.
  static String _escapeFStringSingle(String s) => s
      .replaceAll('\\', r'\\')
      .replaceAll('\t', r'\t')
      .replaceAll('\r', r'\r')
      .replaceAll('\n', r'\n')
      .replaceAll('{', '{{')
      .replaceAll('}', '}}')
      .replaceAll("'", r"\'");
}
