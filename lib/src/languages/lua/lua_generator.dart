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

/// Lua implementation of an [ApolloCodeGenerator].
///
/// Emits idiomatic Lua: keyword-delimited blocks (`function ... end`,
/// `if ... then ... end`), `local` variables, untyped parameters, `..` string
/// concatenation, `and`/`or`/`not`/`~=` operators, table constructors, and a
/// table-based class convention (`Name = {}`, `Name.__index = Name`,
/// `function Name:method(...)`), with `self.`/`self:` prefixing inside methods.
class ApolloCodeGeneratorLua extends ApolloCodeGenerator {
  ApolloCodeGeneratorLua(ApolloSourceCodeStorage codeStorage)
    : super('lua', codeStorage);

  /// Field names of the class currently being generated (for `self.x`).
  Set<String> _currentClassFields = const {};

  /// Method names of the class currently being generated (for `self:m()`).
  Set<String> _currentClassMethods = const {};

  // -----------------------------------------------------------------
  // Imports (Lua uses `require`).
  // -----------------------------------------------------------------
  @override
  StringBuffer generateASTStatementImport(
    ASTStatementImport import, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();
    out.write('require("');
    out.write(import.path);
    out.write('")\n');
    return out;
  }

  // -----------------------------------------------------------------
  // Classes (table-based).
  // -----------------------------------------------------------------
  @override
  StringBuffer generateASTClass(
    ASTClassNormal clazz, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    var name = clazz.name;
    var fields = clazz.fields.toList();

    // Class table with default field values: `Name = { f = v, ... }`.
    out.write(name);
    out.write(' = {');
    for (var i = 0; i < fields.length; ++i) {
      var field = fields[i];
      if (i > 0) out.write(',');
      out.write(' ');
      out.write(field.name);
      out.write(' = ');
      if (field is ASTClassFieldWithInitialValue) {
        generateASTExpression(
          field.initialValue,
          out: out,
          headIndented: false,
        );
      } else {
        out.write('nil');
      }
    }
    if (fields.isNotEmpty) out.write(' ');
    out.write('}\n');

    out.write(name);
    out.write('.__index = ');
    out.write(name);
    out.write('\n\n');

    // Emit methods as `function Name:method(...) ... end`, resolving bare field
    // and sibling-method references to `self.` / `self:`.
    _currentClassFields = fields.map((f) => f.name).toSet();
    _currentClassMethods = {
      for (var set in clazz.functions)
        for (var f in set.functions) f.name,
    };

    for (var set in clazz.functions) {
      for (var f in set.functions) {
        var blockCode = generateASTBlock(
          f,
          indent: indent,
          withBrackets: false,
        );

        out.write(indent);
        out.write('function ');
        out.write(name);
        out.write(':');
        out.write(f.name);
        out.write('(');
        if (f.parametersSize > 0) {
          generateASTParametersDeclaration(f.parameters, out: out);
        }
        out.write(')\n');
        out.write(blockCode);
        out.write(indent);
        out.write('end\n\n');
      }
    }

    _currentClassFields = const {};
    _currentClassMethods = const {};

    return out;
  }

  @override
  StringBuffer generateASTClassField(
    ASTClassField field, {
    StringBuffer? out,
    String indent = '',
  }) {
    // Fields are rendered inline in the class table by [generateASTClass]; this
    // is only a fallback.
    out ??= newOutput();
    out.write(indent);
    out.write(field.name);
    out.write(' = ');
    if (field is ASTClassFieldWithInitialValue) {
      generateASTExpression(field.initialValue, out: out, headIndented: false);
    } else {
      out.write('nil');
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
    return out;
  }

  @override
  StringBuffer generateASTClassFunctionDeclaration(
    ASTClassFunctionDeclaration f, {
    StringBuffer? out,
    String indent = '',
  }) {
    return _generateFunction(f, out: out, indent: indent);
  }

  @override
  StringBuffer generateASTFunctionDeclaration(
    ASTFunctionDeclaration f, {
    StringBuffer? out,
    String indent = '',
  }) {
    return _generateFunction(f, out: out, indent: indent);
  }

  StringBuffer _generateFunction(
    ASTFunctionDeclaration f, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    var blockCode = generateASTBlock(f, indent: indent, withBrackets: false);

    out.write(indent);
    out.write('function ');
    out.write(f.name);
    out.write('(');
    if (f.parametersSize > 0) {
      generateASTParametersDeclaration(f.parameters, out: out);
    }
    out.write(')\n');
    out.write(blockCode);
    out.write(indent);
    out.write('end\n\n');

    return out;
  }

  @override
  StringBuffer generateASTParametersDeclaration(
    ASTParametersDeclaration parameters, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    var all = <ASTParameterDeclaration>[
      ...?parameters.positionalParameters,
      ...?parameters.optionalParameters,
      ...?parameters.namedParameters,
    ];

    for (var i = 0; i < all.length; ++i) {
      if (i > 0) out.write(', ');
      generateASTParameterDeclaration(all[i], out: out);
    }

    return out;
  }

  @override
  StringBuffer generateASTParameterDeclaration(
    ASTParameterDeclaration parameter, {
    StringBuffer? out,
    String indent = '',
  }) {
    // Lua parameters are untyped.
    out ??= newOutput();
    out.write(parameter.name);
    return out;
  }

  @override
  StringBuffer generateASTFunctionParameterDeclaration(
    ASTFunctionParameterDeclaration parameter, {
    StringBuffer? out,
    String indent = '',
  }) {
    return generateASTParameterDeclaration(parameter, out: out, indent: indent);
  }

  // -----------------------------------------------------------------
  // Statements.
  // -----------------------------------------------------------------
  @override
  StringBuffer generateASTStatementVariableDeclaration(
    ASTStatementVariableDeclaration statement, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    out.write('local ');
    out.write(statement.name);

    if (statement.value != null) {
      out.write(' = ');
      generateASTExpression(
        statement.value!,
        out: out,
        indent: indent,
        headIndented: false,
      );
    }

    return out;
  }

  @override
  StringBuffer generateASTStatementExpression(
    ASTStatementExpression statement, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    // Lua statements are not terminated by `;`.
    out ??= newOutput();
    if (headIndented) out.write(indent);
    generateASTExpression(statement.expression, out: out);
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
      indent: indent,
      headIndented: false,
    );
    out.write(' do\n');

    var blockCode = generateASTBlock(
      whileLoop.loopBlock,
      indent: indent,
      withBrackets: false,
    );

    out.write(blockCode);
    out.write(indent);
    out.write('end');

    return out;
  }

  /// Lua `break` (no statement terminator).
  @override
  StringBuffer generateASTStatementBreak(
    ASTStatementBreak statement, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);
    out.write('break');
    return out;
  }

  /// Lua has no do-while; it is emitted as `repeat <block> until <not cond>`.
  @override
  StringBuffer generateASTStatementDoWhileLoop(
    ASTStatementDoWhileLoop doWhileLoop, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    out.write('repeat\n');

    var blockCode = generateASTBlock(
      doWhileLoop.loopBlock,
      indent: indent,
      withBrackets: false,
    );

    out.write(blockCode);
    out.write(indent);
    out.write('until ');

    // do-while loops while `cond`; Lua's `repeat` loops until its condition is
    // true (i.e. while false), so emit the negation of `cond`. When `cond` is
    // already a negation (the common round-trip case), unwrap it.
    var cond = doWhileLoop.conditionExpression;
    if (cond is ASTExpressionNegation) {
      generateASTExpression(
        cond.expression,
        out: out,
        indent: indent,
        headIndented: false,
      );
    } else {
      out.write('not ');
      generateASTExpression(
        cond,
        out: out,
        indent: indent,
        headIndented: false,
      );
    }

    return out;
  }

  @override
  StringBuffer generateASTStatementForEach(
    ASTStatementForEach forEach, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    out.write('for _, ');
    out.write(forEach.variableName);
    out.write(' in ipairs(');
    generateASTExpression(
      forEach.iterableExpression,
      out: out,
      indent: indent,
      headIndented: false,
    );
    out.write(') do\n');

    var blockCode = generateASTBlock(
      forEach.loopBlock,
      indent: indent,
      withBrackets: false,
    );

    out.write(blockCode);
    out.write(indent);
    out.write('end');

    return out;
  }

  @override
  StringBuffer generateASTStatementForLoop(
    ASTStatementForLoop forLoop, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    // Lua has no C-style `for`; desugar to `init` + `while cond do ... step end`.
    out ??= newOutput();

    if (headIndented) out.write(indent);

    generateASTStatement(
      forLoop.initStatement,
      out: out,
      indent: indent,
      headIndented: false,
    );
    out.write('\n');

    out.write(indent);
    out.write('while ');
    generateASTExpression(
      forLoop.conditionExpression,
      out: out,
      indent: indent,
      headIndented: false,
    );
    out.write(' do\n');

    var blockCode = generateASTBlock(
      forLoop.loopBlock,
      indent: indent,
      withBrackets: false,
    );
    out.write(blockCode);

    out.write('$indent  ');
    generateASTExpression(
      forLoop.continueExpression,
      out: out,
      indent: indent,
      headIndented: false,
    );
    out.write('\n');

    out.write(indent);
    out.write('end');

    return out;
  }

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
    generateASTExpression(
      branch.condition,
      out: out,
      indent: indent,
      headIndented: false,
    );
    out.write(' then\n');

    generateASTBlock(
      branch.block,
      out: out,
      indent: '$indent  ',
      withBrackets: false,
    );

    out.write(indent);
    out.write('end');

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
    generateASTExpression(
      branch.condition,
      out: out,
      indent: indent,
      headIndented: false,
    );
    out.write(' then\n');

    generateASTBlock(
      branch.blockIf,
      out: out,
      indent: '$indent  ',
      withBrackets: false,
    );

    var blockElse = branch.blockElse;
    if (blockElse != null) {
      out.write(indent);
      out.write('else\n');
      generateASTBlock(
        blockElse,
        out: out,
        indent: '$indent  ',
        withBrackets: false,
      );
    }

    out.write(indent);
    out.write('end');

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
    generateASTExpression(
      branch.condition,
      out: out,
      indent: indent,
      headIndented: false,
    );
    out.write(' then\n');

    generateASTBlock(
      branch.blockIf,
      out: out,
      indent: '$indent  ',
      withBrackets: false,
    );

    for (var branchElseIf in branch.blocksElseIf) {
      out.write(indent);
      out.write('elseif ');
      generateASTExpression(
        branchElseIf.condition,
        out: out,
        indent: indent,
        headIndented: false,
      );
      out.write(' then\n');
      generateASTBlock(
        branchElseIf.block,
        out: out,
        indent: '$indent  ',
        withBrackets: false,
      );
    }

    var blockElse = branch.blockElse;
    if (blockElse != null) {
      out.write(indent);
      out.write('else\n');
      generateASTBlock(
        blockElse,
        out: out,
        indent: '$indent  ',
        withBrackets: false,
      );
    }

    out.write(indent);
    out.write('end');

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
    generateASTValue(
      statement.value,
      out: out,
      indent: indent,
      headIndented: false,
    );
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
    generateASTVariable(
      statement.variable,
      out: out,
      indent: indent,
      headIndented: false,
    );
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
    generateASTExpression(
      statement.expression,
      out: out,
      indent: indent,
      headIndented: false,
    );
    return out;
  }

  // -----------------------------------------------------------------
  // Expressions and operators.
  // -----------------------------------------------------------------
  @override
  String resolveASTExpressionOperatorText(
    ASTExpressionOperator operator,
    ASTNumType aNumType,
    ASTNumType bNumType,
  ) {
    switch (operator) {
      case ASTExpressionOperator.equals:
        return '==';
      case ASTExpressionOperator.notEquals:
        return '~=';
      case ASTExpressionOperator.and:
        return 'and';
      case ASTExpressionOperator.or:
        return 'or';
      case ASTExpressionOperator.divideAsInt:
        return '//';
      // Lua 5.3 bitwise operators. NOTE: `bitwiseXor` must be `~` in Lua (the
      // shared default is `^`, which is exponentiation in Lua), so this case is
      // essential, not just cosmetic.
      case ASTExpressionOperator.bitwiseAnd:
        return '&';
      case ASTExpressionOperator.bitwiseOr:
        return '|';
      case ASTExpressionOperator.bitwiseXor:
        return '~';
      case ASTExpressionOperator.shiftLeft:
        return '<<';
      case ASTExpressionOperator.shiftRight:
        return '>>';
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

    // Lua anonymous function: `function(params) ... end`.
    out.write('function');
    generateFunctionParametersNames(f, out: out);

    var single = singleReturnExpression(f);
    if (single != null) {
      out.write(' return ');
      generateASTExpression(single, out: out, headIndented: false);
      out.write(' end');
    } else {
      out.write('\n');
      var blockCode = generateASTBlock(f, indent: indent, withBrackets: false);
      out.write(blockCode);
      out.write(indent);
      out.write('end');
    }

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

    // Lua has no `?:` ternary; the idiomatic form is `cond and a or b`
    // (short-circuit). NOTE: this differs from a true ternary when `valueIfTrue`
    // is `false`/`nil` — a known limitation of the Lua idiom.
    generateASTExpression(expression.condition, out: out, headIndented: false);
    out.write(' and ');
    generateASTExpression(
      expression.valueIfTrue,
      out: out,
      headIndented: false,
    );
    out.write(' or ');
    generateASTExpression(
      expression.valueIfFalse,
      out: out,
      headIndented: false,
    );

    return out;
  }

  @override
  StringBuffer generateASTExpressionOperation(
    ASTExpressionOperation expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    // String concatenation uses `..` in Lua, not `+`.
    if (_looksLikeStringConcatenation(expression)) {
      out ??= newOutput();
      if (headIndented) out.write(indent);
      generateASTExpression(
        expression.expression1,
        out: out,
        indent: '$indent  ',
        headIndented: false,
      );
      out.write(' .. ');
      generateASTExpression(
        expression.expression2,
        out: out,
        indent: '$indent  ',
        headIndented: false,
      );
      return out;
    }

    return super.generateASTExpressionOperation(
      expression,
      out: out,
      indent: indent,
      headIndented: headIndented,
    );
  }

  bool _looksLikeStringConcatenation(ASTExpressionOperation expression) {
    if (expression.operator != ASTExpressionOperator.add) return false;
    var a = expression.expression1;
    var b = expression.expression2;
    if (a.isLiteralString ||
        b.isLiteralString ||
        a.hasDescendantLiteralString ||
        b.hasDescendantLiteralString) {
      return true;
    }
    // A `+` where either operand is statically String-typed (e.g. two `String`
    // variables, `s1 + s2`) is also concatenation and must use `..` in Lua.
    return _isStringTyped(a) || _isStringTyped(b);
  }

  /// Whether [e] resolves synchronously to a `String` type. Falls back to
  /// `false` when the type is unknown or only resolvable asynchronously, so a
  /// numeric `+` is never mistaken for concatenation.
  bool _isStringTyped(ASTExpression e) {
    var t = e.resolveType(null);
    return t is ASTTypeString;
  }

  @override
  StringBuffer generateASTExpressionVariableEntryAccess(
    ASTExpressionVariableEntryAccess expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);

    generateASTVariable(
      expression.variable,
      out: out,
      indent: indent,
      headIndented: headIndented,
    );

    // Lua tables are 1-indexed for their array part, so a list index coming from
    // a 0-based language (`list[0]`) must become `list[1]`. Map/table keys
    // (strings or explicit keys) are left untouched. The Lua grammar does not
    // parse index-access expressions, so every node reaching this generator
    // originates from a 0-based source language — there is no Lua→Lua round-trip
    // that would double-shift.
    var t = expression.variable.resolveType(null);
    ASTType? containerType = t is ASTType ? t : null;

    for (var idx in [expression.expression, ...expression.extraIndices]) {
      out.write('[');
      if (containerType is ASTTypeArray) {
        _writeLuaArrayIndex(idx, out, indent);
      } else {
        generateASTExpression(
          idx,
          out: out,
          indent: indent,
          headIndented: false,
        );
      }
      out.write(']');
      // Descend one container level for the next chained index (`m[0][1]`).
      containerType = containerType is ASTTypeArray
          ? containerType.elementType
          : (containerType is ASTTypeMap ? containerType.valueType : null);
    }
    return out;
  }

  /// Writes a 0-based array index shifted to Lua's 1-based convention. An
  /// integer literal is incremented in place (`list[0]` -> `list[1]`); any other
  /// index expression gets `+ 1` appended (`list[i]` -> `list[(i) + 1]`).
  void _writeLuaArrayIndex(ASTExpression idx, StringBuffer out, String indent) {
    if (idx is ASTExpressionLiteral) {
      var v = idx.value;
      if (v is ASTValueInt) {
        out.write(v.value + 1);
        return;
      }
    }
    out.write('(');
    generateASTExpression(idx, out: out, indent: indent, headIndented: false);
    out.write(') + 1');
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
    var inner = expression.expression;
    var group = inner.isComplex;
    if (group) out.write('(');
    generateASTExpression(inner, out: out, headIndented: false);
    if (group) out.write(')');

    return out;
  }

  @override
  StringBuffer generateASTExpressionLocalFunctionInvocation(
    ASTExpressionLocalFunctionInvocation expression, {
    String indent = '',
    StringBuffer? out,
    bool headIndented = true,
  }) {
    // Sibling-method calls inside a class method become `self:method(...)`.
    if (_currentClassMethods.contains(expression.name)) {
      out ??= newOutput();
      if (headIndented) out.write(indent);
      out.write('self:');
      out.write(expression.name);
      out.write('(');
      var arguments = expression.arguments;
      for (var i = 0; i < arguments.length; ++i) {
        if (i > 0) out.write(', ');
        generateASTExpression(
          arguments[i],
          out: out,
          indent: '$indent  ',
          headIndented: false,
        );
      }
      out.write(')');
      return out;
    }

    return super.generateASTExpressionLocalFunctionInvocation(
      expression,
      indent: indent,
      out: out,
      headIndented: headIndented,
    );
  }

  @override
  StringBuffer generateASTScopeVariable(
    ASTScopeVariable variable, {
    String? callingFunction,
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    // Field reads inside a class method become `self.field`.
    if (!variable.isTypeIdentifier &&
        _currentClassFields.contains(variable.name)) {
      out ??= newOutput();
      if (headIndented) out.write(indent);
      out.write('self.');
      out.write(variable.name);
      return out;
    }

    return super.generateASTScopeVariable(
      variable,
      callingFunction: callingFunction,
      out: out,
      indent: indent,
      headIndented: headIndented,
    );
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

    out.write('{');
    var valuesExpressions = expression.valuesExpressions;
    for (var i = 0; i < valuesExpressions.length; ++i) {
      if (i > 0) out.write(', ');
      generateASTExpression(
        valuesExpressions[i],
        out: out,
        headIndented: false,
      );
    }
    out.write('}');

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
      if (i > 0) out.write(',');
      out.write(' [');
      generateASTExpression(e.key, out: out, headIndented: false);
      out.write('] = ');
      generateASTExpression(e.value, out: out, headIndented: false);
    }
    if (entriesExpressions.isNotEmpty) out.write(' ');
    out.write('}');

    return out;
  }

  // -----------------------------------------------------------------
  // Types (Lua is dynamically typed; only `table` containers are emitted).
  // -----------------------------------------------------------------
  @override
  StringBuffer generateASTTypeArray(
    ASTTypeArray type, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();
    out.write(indent);
    out.write('table');
    return out;
  }

  @override
  StringBuffer generateASTTypeArray2D(
    ASTTypeArray2D type, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();
    out.write(indent);
    out.write('table');
    return out;
  }

  @override
  StringBuffer generateASTTypeArray3D(
    ASTTypeArray3D type, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();
    out.write(indent);
    out.write('table');
    return out;
  }

  // -----------------------------------------------------------------
  // String values.
  //
  // Lua has no string interpolation, so concatenations / templates are emitted
  // as `..`-joined expressions.
  // -----------------------------------------------------------------
  @override
  StringBuffer generateASTValueString(
    ASTValueString value, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);
    out.write('"');
    out.write(_escapeString(value.value));
    out.write('"');
    return out;
  }

  static String _escapeString(String str) {
    return str
        .replaceAll('\\', r'\\')
        .replaceAll('\t', r'\t')
        .replaceAll('\r', r'\r')
        .replaceAll('\n', r'\n')
        .replaceAll('"', r'\"');
  }

  @override
  StringBuffer generateASTValueStringConcatenation(
    ASTValueStringConcatenation value, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    var parts = value.values;
    for (var i = 0; i < parts.length; ++i) {
      if (i > 0) out.write(' .. ');
      out.write(_valuePart(parts[i]));
    }

    return out;
  }

  /// Renders a single string-component value as a Lua expression.
  String _valuePart(ASTValue value) {
    if (value is ASTValueString) {
      return '"${_escapeString(value.value)}"';
    } else if (value is ASTValueStringVariable) {
      return value.variable.name;
    } else if (value is ASTValueStringExpression) {
      var inner = generateASTExpression(value.expression).toString();
      // Lua's `..` binds tighter than comparison/logical operators, so an
      // interpolated subexpression like `${a < b}` or `${a and b}` must be
      // parenthesized or it would mis-associate with the surrounding
      // concatenation (`"x" .. a < b` parses as `("x" .. a) < b`).
      return value.expression.isComplex ? '($inner)' : inner;
    } else if (value is ASTValueStringConcatenation) {
      return value.values.map(_valuePart).join(' .. ');
    } else {
      return generateASTValue(value).toString();
    }
  }

  @override
  StringBuffer generateASTValueStringVariable(
    ASTValueStringVariable value, {
    StringBuffer? out,
    String indent = '',
    bool precededByString = false,
  }) {
    out ??= newOutput();
    out.write(value.variable.name);
    return out;
  }

  @override
  StringBuffer generateASTValueStringExpression(
    ASTValueStringExpression value, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();
    generateASTExpression(value.expression, out: out);
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
}
