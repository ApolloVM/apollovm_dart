// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import '../../apollovm_code_generator.dart';
import '../../apollovm_code_storage.dart';
import '../../ast/apollovm_ast_base.dart';
import '../../ast/apollovm_ast_expression.dart';
import '../../ast/apollovm_ast_statement.dart';
import '../../ast/apollovm_ast_toplevel.dart';
import '../../ast/apollovm_ast_type.dart';
import '../../ast/apollovm_ast_value.dart';
import '../../ast/apollovm_ast_variable.dart';

/// Go implementation of an [ApolloCodeGenerator].
///
/// Go has no classes: a class is emitted as a `type Name struct { ... }` plus
/// receiver methods (`func (o *Name) m(...)`) and, when needed, a factory
/// constructor (`func NewName(...) *Name`). Field and sibling-method references
/// inside a method are rewritten to `o.field` / `o.method(...)`.
class ApolloCodeGeneratorGo extends ApolloCodeGenerator {
  ApolloCodeGeneratorGo(ApolloSourceCodeStorage codeStorage)
    : super('go', codeStorage);

  /// The fixed receiver name used for struct methods.
  static const String _receiver = 'o';

  /// Field names of the struct currently being generated (for `o.field`).
  Set<String> _currentClassFields = const {};

  /// Method names of the struct currently being generated (for `o.method()`).
  Set<String> _currentClassMethods = const {};

  /// Name of the struct currently being generated (for the receiver type).
  String? _currentClassName;

  @override
  String normalizeTypeName(String typeName, [String? callingFunction]) {
    switch (typeName) {
      case 'int':
      case 'Int':
      case 'Integer':
        return 'int';
      case 'double':
      case 'Double':
      case 'num':
      case 'Num':
        return 'float64';
      case 'bool':
      case 'Bool':
      case 'Boolean':
        return 'bool';
      case 'String':
      case 'string':
        return 'string';
      case 'void':
      case 'Void':
        return '';
      case 'dynamic':
      case 'Object':
      case 'any':
        return 'any';
      default:
        return typeName;
    }
  }

  // -----------------------------------------------------------------
  // Program structure: `package main` + imports.
  // -----------------------------------------------------------------

  @override
  StringBuffer generateASTRoot(
    ASTRoot root, {
    StringBuffer? out,
    String indent = '',
    bool withBrackets = true,
  }) {
    out ??= newOutput();

    out.write('package main\n\n');

    // `fmt` is imported only when the AST prints (the canonical `print`).
    if (_usesPrint(root) || root.classes.any(_usesPrint)) {
      out.write('import "fmt"\n\n');
    }

    var imports = root.imports;
    if (imports.isNotEmpty) {
      for (var import in imports) {
        generateASTStatementImport(import, out: out);
      }
      out.write('\n');
    }

    generateASTBlock(root, out: out, withBrackets: false);

    for (var clazz in root.classes) {
      generateASTClass(clazz, out: out);
    }

    return out;
  }

  bool _usesPrint(ASTNode node) {
    if (node is ASTExpressionLocalFunctionInvocation && node.name == 'print') {
      return true;
    }
    for (var child in node.children) {
      if (_usesPrint(child)) return true;
    }
    return false;
  }

  @override
  StringBuffer generateASTStatementImport(
    ASTStatementImport import, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();
    out.write('import "');
    out.write(import.path);
    out.write('"\n');
    return out;
  }

  // -----------------------------------------------------------------
  // Structs (classes).
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

    // `type Name struct { field Type ... }`.
    out.write('type ');
    out.write(name);
    out.write(' struct {\n');
    for (var field in fields) {
      out.write('  ');
      out.write(field.name);
      out.write(' ');
      generateASTType(field.type, out: out);
      out.write('\n');
    }
    out.write('}\n\n');

    _currentClassName = name;
    _currentClassFields = fields.map((f) => f.name).toSet();
    _currentClassMethods = {
      for (var set in clazz.functions)
        for (var f in set.functions) f.name,
    };

    // Factory constructor(s) when there are explicit constructors or field
    // initializers (Go structs can't carry inline initializers).
    var fieldInits = fields.whereType<ASTClassFieldWithInitialValue>().toList();
    var constructors = clazz.constructors.toList();

    if (constructors.isNotEmpty) {
      for (var c in constructors) {
        for (var ctor in c.functions) {
          _generateConstructor(ctor, name, fieldInits, out, indent);
        }
      }
    } else if (fieldInits.isNotEmpty) {
      _generateDefaultConstructor(name, fieldInits, out, indent);
    }

    // Methods as `func (o *Name) method(...) ret { ... }`.
    for (var set in clazz.functions) {
      for (var f in set.functions) {
        _generateReceiverMethod(f, name, out, indent);
      }
    }

    _currentClassName = null;
    _currentClassFields = const {};
    _currentClassMethods = const {};

    return out;
  }

  void _generateReceiverMethod(
    ASTFunctionDeclaration f,
    String className,
    StringBuffer out,
    String indent,
  ) {
    var blockCode = generateASTBlock(f, indent: indent, withBrackets: false);

    out.write('func (');
    out.write(_receiver);
    out.write(' *');
    out.write(className);
    out.write(') ');
    out.write(f.name);
    out.write('(');
    if (f.parametersSize > 0) {
      generateASTParametersDeclaration(f.parameters, out: out);
    }
    out.write(')');
    _writeReturnType(f.returnType, out);
    out.write(' {\n');
    out.write(blockCode);
    out.write(indent);
    out.write('}\n\n');
  }

  void _generateConstructor(
    ASTClassConstructorDeclaration ctor,
    String className,
    List<ASTClassFieldWithInitialValue> fieldInits,
    StringBuffer out,
    String indent,
  ) {
    var blockCode = generateASTBlock(ctor, indent: indent, withBrackets: false);

    out.write('func New');
    out.write(className);
    out.write('(');
    if (ctor.parametersSize > 0) {
      generateASTParametersDeclaration(ctor.parameters, out: out);
    }
    out.write(') *');
    out.write(className);
    out.write(' {\n');
    out.write('$indent  ');
    out.write('$_receiver := &$className{}\n');
    _writeFieldInits(fieldInits, out, '$indent  ');
    out.write(blockCode);
    out.write('$indent  return $_receiver\n');
    out.write(indent);
    out.write('}\n\n');
  }

  void _generateDefaultConstructor(
    String className,
    List<ASTClassFieldWithInitialValue> fieldInits,
    StringBuffer out,
    String indent,
  ) {
    out.write('func New');
    out.write(className);
    out.write('() *');
    out.write(className);
    out.write(' {\n');
    out.write('$indent  ');
    out.write('$_receiver := &$className{}\n');
    _writeFieldInits(fieldInits, out, '$indent  ');
    out.write('$indent  return $_receiver\n');
    out.write(indent);
    out.write('}\n\n');
  }

  void _writeFieldInits(
    List<ASTClassFieldWithInitialValue> fieldInits,
    StringBuffer out,
    String indent,
  ) {
    for (var field in fieldInits) {
      out.write(indent);
      out.write('$_receiver.');
      out.write(field.name);
      out.write(' = ');
      generateASTExpression(field.initialValue, out: out, headIndented: false);
      out.write('\n');
    }
  }

  void _writeReturnType(ASTType returnType, StringBuffer out) {
    if (returnType is ASTTypeVoid) return;
    var name = normalizeTypeName(returnType.name);
    if (name.isEmpty) return;
    out.write(' ');
    generateASTType(returnType, out: out);
  }

  /// Struct methods are emitted directly by [generateASTClass]; this is only a
  /// fallback for a class function reached outside that path.
  @override
  StringBuffer generateASTClassFunctionDeclaration(
    ASTClassFunctionDeclaration f, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();
    _generateReceiverMethod(f, _currentClassName ?? 'Object', out, indent);
    return out;
  }

  @override
  StringBuffer generateASTClassField(
    ASTClassField field, {
    StringBuffer? out,
    String indent = '',
  }) {
    // Fields are rendered inline in the struct by [generateASTClass]; nothing
    // to emit here.
    out ??= newOutput();
    return out;
  }

  @override
  StringBuffer generateASTClassConstructorDeclaration(
    ASTClassConstructorDeclaration c, {
    StringBuffer? out,
    String indent = '',
  }) {
    // Constructors are rendered as factories by [generateASTClass].
    out ??= newOutput();
    return out;
  }

  // -----------------------------------------------------------------
  // Functions.
  // -----------------------------------------------------------------

  @override
  StringBuffer generateASTFunctionDeclaration(
    ASTFunctionDeclaration f, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    var blockCode = generateASTBlock(f, indent: indent, withBrackets: false);

    out.write(indent);
    out.write('func ');
    out.write(f.name);
    out.write('(');
    if (f.parametersSize > 0) {
      generateASTParametersDeclaration(f.parameters, out: out);
    }
    out.write(')');
    _writeReturnType(f.returnType, out);
    out.write(' {\n');
    out.write(blockCode);
    out.write(indent);
    out.write('}\n\n');

    return out;
  }

  @override
  StringBuffer generateASTParametersDeclaration(
    ASTParametersDeclaration parameters, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    var wrote = 0;
    for (var p in parameters.allParameters) {
      if (wrote > 0) out.write(', ');
      generateASTParameterDeclaration(p, out: out);
      ++wrote;
    }

    return out;
  }

  @override
  StringBuffer generateASTParameterDeclaration(
    ASTParameterDeclaration parameter, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    // Go declares the type *after* the name: `a int`.
    out.write(parameter.name);
    out.write(' ');
    generateASTType(parameter.type, out: out);

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

    final type = statement.type;
    final value = statement.value;

    if (value != null && type is ASTTypeVar) {
      // Inferred + value: `x := expr`.
      out.write(statement.name);
      out.write(' := ');
      generateASTExpression(value, out: out, indent: indent, headIndented: false);
    } else {
      // `var x Type = expr`, `var x Type`, or `var x = expr`.
      out.write('var ');
      out.write(statement.name);
      if (type is! ASTTypeVar) {
        out.write(' ');
        generateASTType(type, out: out);
      }
      if (value != null) {
        out.write(' = ');
        generateASTExpression(
          value,
          out: out,
          indent: indent,
          headIndented: false,
        );
      }
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
    out ??= newOutput();
    if (headIndented) out.write(indent);
    generateASTExpression(statement.expression, out: out);
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
    out.write('break');
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
    out.write('continue');
    return out;
  }

  // Go statements use no trailing `;`.

  @override
  StringBuffer generateASTStatementReturn(
    ASTStatementReturn statement, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);
    out.write('return');
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
    out.write('return nil');
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
    generateASTValue(statement.value, out: out, indent: indent, headIndented: false);
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

  // Go `if`/`else if`/`else` use no parentheses around the condition.

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
    out.write(' {\n');
    generateASTBlock(
      branch.block,
      out: out,
      indent: '$indent  ',
      withBrackets: false,
    );
    out.write(indent);
    out.write('}\n');
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
    out.write(' {\n');
    generateASTBlock(
      branch.blockIf,
      out: out,
      indent: '$indent  ',
      withBrackets: false,
    );
    out.write(indent);

    var blockElse = branch.blockElse;
    if (blockElse != null) {
      out.write('} else {\n');
      generateASTBlock(
        blockElse,
        out: out,
        indent: '$indent  ',
        withBrackets: false,
      );
      out.write(indent);
      out.write('}\n');
    } else {
      out.write('}\n');
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
    generateASTExpression(
      branch.condition,
      out: out,
      indent: indent,
      headIndented: false,
    );
    out.write(' {\n');
    generateASTBlock(
      branch.blockIf,
      out: out,
      indent: '$indent  ',
      withBrackets: false,
    );

    for (var branchElseIf in branch.blocksElseIf) {
      out.write(indent);
      out.write('} else if ');
      generateASTExpression(
        branchElseIf.condition,
        out: out,
        indent: indent,
        headIndented: false,
      );
      out.write(' {\n');
      generateASTBlock(
        branchElseIf.block,
        out: out,
        indent: '$indent  ',
        withBrackets: false,
      );
    }

    out.write(indent);

    var blockElse = branch.blockElse;
    if (blockElse != null) {
      out.write('} else {\n');
      generateASTBlock(
        blockElse,
        out: out,
        indent: '$indent  ',
        withBrackets: false,
      );
      out.write(indent);
      out.write('}\n');
    } else {
      out.write('}\n');
    }
    return out;
  }

  @override
  StringBuffer generateASTStatementForLoop(
    ASTStatementForLoop forLoop, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    out.write('for ');
    generateASTStatement(
      forLoop.initStatement,
      out: out,
      indent: indent,
      headIndented: false,
    );
    out.write('; ');
    generateASTExpression(
      forLoop.conditionExpression,
      out: out,
      indent: indent,
      headIndented: false,
    );
    out.write('; ');
    generateASTExpression(
      forLoop.continueExpression,
      out: out,
      indent: indent,
      headIndented: false,
    );
    out.write(' {\n');

    var blockCode = generateASTBlock(
      forLoop.loopBlock,
      indent: indent,
      withBrackets: false,
    );

    out.write(blockCode);
    out.write(indent);
    out.write('}');

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
    out.write(' := range ');
    generateASTExpression(
      forEach.iterableExpression,
      out: out,
      indent: indent,
      headIndented: false,
    );
    out.write(' {\n');

    var blockCode = generateASTBlock(
      forEach.loopBlock,
      indent: indent,
      withBrackets: false,
    );

    out.write(blockCode);
    out.write(indent);
    out.write('}');

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

    out.write('for ');
    generateASTExpression(
      whileLoop.conditionExpression,
      out: out,
      indent: indent,
      headIndented: false,
    );
    out.write(' {\n');

    var blockCode = generateASTBlock(
      whileLoop.loopBlock,
      indent: indent,
      withBrackets: false,
    );

    out.write(blockCode);
    out.write(indent);
    out.write('}');

    return out;
  }

  /// Go has no `do`/`while`; emitted as `for { <body> if !cond { break } }`.
  @override
  StringBuffer generateASTStatementDoWhileLoop(
    ASTStatementDoWhileLoop doWhileLoop, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    var indent2 = '$indent  ';

    out.write('for {\n');

    var blockCode = generateASTBlock(
      doWhileLoop.loopBlock,
      indent: indent,
      withBrackets: false,
    );
    out.write(blockCode);

    out.write(indent2);
    out.write('if ');
    // Negate the loop condition (a round-trippable, stable form via the base
    // negation generator's parenthesization).
    generateASTExpression(
      ASTExpressionNegation(doWhileLoop.conditionExpression),
      out: out,
      indent: indent2,
      headIndented: false,
    );
    out.write(' {\n');
    out.write('$indent2  break\n');
    out.write(indent2);
    out.write('}\n');

    out.write(indent);
    out.write('}');

    return out;
  }

  @override
  StringBuffer generateASTStatementSwitch(
    ASTStatementSwitch statement, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    var indent2 = '$indent  ';

    out.write('switch ');
    generateASTExpression(
      statement.expression,
      out: out,
      indent: indent,
      headIndented: false,
    );
    out.write(' {\n');

    for (var c in statement.cases) {
      out.write(indent2);
      if (c.isDefault) {
        out.write('default:\n');
      } else {
        out.write('case ');
        generateASTExpression(c.value!, out: out, headIndented: false);
        out.write(':\n');
      }
      out.write(
        generateASTBlock(c.block, indent: indent2, withBrackets: false),
      );
    }

    out.write(indent);
    out.write('}');

    return out;
  }

  // -----------------------------------------------------------------
  // Expressions.
  // -----------------------------------------------------------------

  /// Go has no ternary/if-expression; emit an IIFE:
  /// `func() any { if cond { return a } else { return b } }()`.
  @override
  StringBuffer generateASTExpressionConditional(
    ASTExpressionConditional expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);

    out.write('func() any { if ');
    generateASTExpression(expression.condition, out: out, headIndented: false);
    out.write(' { return ');
    generateASTExpression(expression.valueIfTrue, out: out, headIndented: false);
    out.write(' } else { return ');
    generateASTExpression(
      expression.valueIfFalse,
      out: out,
      headIndented: false,
    );
    out.write(' } }()');

    return out;
  }

  /// Go closure: `func(params) ret { body }`.
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

    out.write('func(');
    if (f.parametersSize > 0) {
      generateASTParametersDeclaration(f.parameters, out: out);
    }
    out.write(')');
    _writeReturnType(f.returnType, out);
    out.write(' {\n');
    var blockCode = generateASTBlock(f, indent: indent, withBrackets: false);
    out.write(blockCode);
    out.write(indent);
    out.write('}');

    return out;
  }

  @override
  StringBuffer generateASTExpressionLocalFunctionInvocation(
    ASTExpressionLocalFunctionInvocation expression, {
    String indent = '',
    StringBuffer? out,
    bool headIndented = true,
  }) {
    // The canonical `print` becomes Go's `fmt.Println`.
    if (expression.name == 'print') {
      out ??= newOutput();
      if (headIndented) out.write(indent);
      out.write('fmt.Println(');
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

    // Sibling-method calls inside a struct method become `o.method(...)`.
    if (_currentClassMethods.contains(expression.name)) {
      out ??= newOutput();
      if (headIndented) out.write(indent);
      out.write('$_receiver.');
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
    // Field reads inside a struct method become `o.field`.
    if (!variable.isTypeIdentifier &&
        _currentClassFields.contains(variable.name)) {
      out ??= newOutput();
      if (headIndented) out.write(indent);
      out.write('$_receiver.');
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
  StringBuffer generateASTVariableGeneric(
    ASTVariable variable, {
    String? callingFunction,
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);
    // `this` is the Go receiver `o`.
    if (variable is ASTThisVariable) {
      out.write(_receiver);
    } else {
      out.write(variable.name);
    }
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
    out.write('nil');
    return out;
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
    out.write('nil');
    return out;
  }

  @override
  String resolveASTExpressionOperatorText(
    ASTExpressionOperator operator,
    ASTNumType aNumType,
    ASTNumType bNumType,
  ) {
    // Go int `/` already truncates, matching integer division.
    if (operator == ASTExpressionOperator.divideAsInt) {
      return getASTExpressionOperatorText(ASTExpressionOperator.divide);
    }
    return getASTExpressionOperatorText(operator);
  }

  /// Go writes bitwise NOT as a prefix `^`.
  @override
  StringBuffer generateASTExpressionBitwiseNot(
    ASTExpressionBitwiseNot expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    out.write('^');
    final inner = expression.expression;
    final group = inner.isComplex;
    if (group) out.write('(');
    generateASTExpression(inner, out: out, indent: indent, headIndented: false);
    if (group) out.write(')');

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

    out.write('[]');
    generateASTType(expression.type ?? ASTTypeDynamic.instance, out: out);
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
    String indent = '',
    StringBuffer? out,
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    out.write('map[');
    generateASTType(expression.keyType ?? ASTTypeDynamic.instance, out: out);
    out.write(']');
    generateASTType(
      expression.valueType ?? ASTTypeDynamic.instance,
      out: out,
    );
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

  // -----------------------------------------------------------------
  // Types.
  // -----------------------------------------------------------------

  @override
  StringBuffer generateASTType(
    ASTType type, {
    StringBuffer? out,
    String indent = '',
  }) {
    if (type is ASTTypeMap) {
      out ??= newOutput();
      out.write(indent);
      out.write('map[');
      generateASTType(type.keyType, out: out);
      out.write(']');
      generateASTType(type.valueType, out: out);
      return out;
    }
    return super.generateASTType(type, out: out, indent: indent);
  }

  @override
  StringBuffer generateASTTypeArray(
    ASTTypeArray type, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();
    out.write(indent);
    out.write('[]');
    generateASTType(type.elementType, out: out);
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
    out.write('[][]');
    generateASTType(type.elementType, out: out);
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
    out.write('[][][]');
    generateASTType(type.elementType, out: out);
    return out;
  }

  // -----------------------------------------------------------------
  // String values (Go has no interpolation; use `+` concatenation).
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

  String _escapeString(String str) {
    return str
        .replaceAll('\\', r'\\')
        .replaceAll('\t', r'\t')
        .replaceAll('"', r'\"')
        .replaceAll('\r', r'\r')
        .replaceAll('\n', r'\n')
        .replaceAll('\b', r'\b');
  }

  @override
  StringBuffer generateASTValueStringConcatenation(
    ASTValueStringConcatenation value, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    var parts = <({String code, bool isString})>[];

    for (var v in value.values) {
      if (v is ASTValueStringVariable) {
        parts.add((code: v.variable.name, isString: false));
      } else if (v is ASTValueStringExpression) {
        var exp = generateASTExpression(v.expression).toString();
        parts.add((code: '($exp)', isString: false));
      } else if (v is ASTValueStringConcatenation) {
        var nested = generateASTValueStringConcatenation(v).toString();
        parts.add((code: nested, isString: false));
      } else if (v is ASTValueString) {
        parts.add((code: '"${_escapeString(v.value)}"', isString: true));
      }
    }

    if (parts.isEmpty) {
      out.write('""');
      return out;
    }

    // Force string context when the first operand is not a string literal, so
    // `a + b` cannot become a numeric add (mirrors Java's `String.valueOf`).
    if (!parts.first.isString) {
      out.write('"" + ');
    }

    for (var i = 0; i < parts.length; ++i) {
      if (i > 0) out.write(' + ');
      out.write(parts[i].code);
    }

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
    out.write('"" + ');
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
    var exp = generateASTExpression(value.expression).toString();
    out.write('"" + (');
    out.write(exp);
    out.write(')');
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
