// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import '../../apollovm_code_generator.dart';
import '../../apollovm_code_storage.dart';
import '../../apollovm_parser.dart';
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

  /// Go's 25 reserved words. None may be used as an identifier, so a name from
  /// the source that collides with one (`map`, `type`, `range`, `func`, …) is
  /// emitted with a trailing `_`.
  static const Set<String> _goKeywords = {
    'break',
    'case',
    'chan',
    'const',
    'continue',
    'default',
    'defer',
    'else',
    'fallthrough',
    'for',
    'func',
    'go',
    'goto',
    'if',
    'import',
    'interface',
    'map',
    'package',
    'range',
    'return',
    'select',
    'struct',
    'switch',
    'type',
    'var',
  };

  /// [name] as a Go identifier: a reserved word gets a trailing `_`.
  ///
  /// Applied at every site that writes a value identifier (variables,
  /// parameters, struct fields, functions and methods), so a declaration and
  /// its uses always agree.
  static String _goIdent(String name) =>
      _goKeywords.contains(name) ? '${name}_' : name;

  /// Member names written after a `.` (`o.type_`, `p.sum()`) are escaped the
  /// same way as the declarations they refer to.
  @override
  String normalizeIdentifier(String name) => _goIdent(name);

  /// Field names of the struct currently being generated (for `o.field`).
  Set<String> _currentClassFields = const {};

  /// Method names of the struct currently being generated (for `o.method()`).
  Set<String> _currentClassMethods = const {};

  /// Names currently in scope whose Go type is a pointer standing in for a
  /// nullable `T?` (see [generateASTType]). A *read* of one of these derefs
  /// (`(*x)`); an assignment target does not, since the pointer itself is what
  /// is being rebound.
  final Map<String, ASTType> _nullablePtrVars = {};

  /// Whether this module needs the `goPtr` helper, which takes the address of
  /// an arbitrary value. Go cannot write `&5`, so a non-null value flowing into
  /// a `*T` slot goes through it.
  bool _needsGoPtrHelper = false;

  /// Registers [name] as a nullable pointer when [type] is one.
  void _trackNullablePtr(String name, ASTType type) {
    if (type.nullable && _goNeedsPointerForNull(type)) {
      _nullablePtrVars[_goIdent(name)] = type.withoutNullability();
    } else {
      _nullablePtrVars.remove(_goIdent(name));
    }
  }

  /// Names of every struct (class) in the program being generated. Go has no
  /// `new`, so instantiating `Point(...)` is emitted as its factory
  /// `NewPoint(...)`.
  Set<String> _programStructNames = const {};

  /// Parameter names of the member currently being generated. A parameter
  /// shadows a same-named field, so `Point(int x) { this.x = x; }` must emit
  /// `o.x = x`, not `o.x = o.x`.
  Set<String> _currentMemberParameters = const {};

  /// Generates [f]'s body with its parameters registered as shadowing names.
  ///
  /// The body is generated *before* the parameter list is written, so a nullable
  /// parameter must be registered here — registering it while writing the
  /// signature would be too late for the body's reads to deref.
  StringBuffer _generateMemberBlock(ASTInvocableDeclaration f, String indent) {
    var previous = _currentMemberParameters;
    var previousPtrs = Map<String, ASTType>.from(_nullablePtrVars);

    _currentMemberParameters = f.parameters.allParameters
        .map((p) => p.name)
        .toSet();
    for (var p in f.parameters.allParameters) {
      _trackNullablePtr(p.name, p.type);
    }

    try {
      return generateASTBlock(f, indent: indent, withBrackets: false);
    } finally {
      _currentMemberParameters = previous;
      _nullablePtrVars
        ..clear()
        ..addAll(previousPtrs);
    }
  }

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

    _programStructNames = root.classes.map((c) => c.name).toSet();
    _nullablePtrVars.clear();
    _needsGoPtrHelper = false;

    // Body-first: the declarations below are what discover whether `goPtr` is
    // needed, so they are generated into a buffer and appended after the
    // header/helper.
    var body = newOutput();

    for (var clazz in root.classes) {
      generateASTClass(clazz, out: body);
    }

    for (var extension in root.extensions) {
      generateASTExtension(extension, out: body);
    }

    generateASTBlock(root, out: body, withBrackets: false);

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

    // `goPtr` takes the address of an arbitrary value, which Go cannot express
    // inline (`&5` is not valid). A nullable `T?` is a `*T`, so assigning a
    // non-null value into one goes through this helper.
    if (_needsGoPtrHelper) {
      out.write('func goPtr[T any](v T) *T { return &v }\n\n');
    }

    // Structs (and their factories) precede the top-level functions that call
    // them. Go itself is order-independent, but ApolloVM's Go parser resolves a
    // `NewPoint(...)` call against the declarations it has seen so far, so a
    // caller emitted first could not resolve the struct.
    out.write(body);

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
      out.write(_goIdent(field.name));
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

    // Every struct gets a factory, so `Point(...)` always has a `NewPoint(...)`
    // to call — see [generateASTExpressionLocalFunctionInvocation].
    if (constructors.isNotEmpty) {
      for (var c in constructors) {
        for (var ctor in c.functions) {
          _generateConstructor(ctor, name, fieldInits, out, indent);
        }
      }
    } else {
      _generateDefaultConstructor(name, fieldInits, out, indent);
    }

    // Methods as `func (o *Name) method(...) ret { ... }`.
    for (var set in clazz.functions) {
      for (var f in set.functions) {
        _generateReceiverMethod(f, name, out, indent);
      }
    }

    // Go has no property accessors. Refuse rather than drop them silently:
    // a dropped accessor leaves the method bodies referencing a property that
    // no longer exists, which compiles as neither Go nor anything else.
    for (var g in clazz.getter) {
      if (g is ASTClassGetterDeclaration) {
        generateASTClassGetterDeclaration(g, out: out, indent: indent);
      }
    }

    for (var s in clazz.setter) {
      if (s is ASTClassSetterDeclaration) {
        generateASTClassSetterDeclaration(s, out: out, indent: indent);
      }
    }

    _currentClassName = null;
    _currentClassFields = const {};
    _currentClassMethods = const {};
    _currentMemberParameters = const {};

    return out;
  }

  void _generateReceiverMethod(
    ASTFunctionDeclaration f,
    String className,
    StringBuffer out,
    String indent,
  ) {
    var blockCode = _generateMemberBlock(f, indent);

    out.write('func (');
    out.write(_receiver);
    out.write(' *');
    out.write(className);
    out.write(') ');
    out.write(_goIdent(f.name));
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
    var blockCode = _generateMemberBlock(ctor, indent);

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
    _writeThisParameterInits(ctor, out, '$indent  ');
    out.write(blockCode);
    out.write('$indent  return $_receiver\n');
    out.write(indent);
    out.write('}\n\n');
  }

  /// Assigns each field-initializing parameter (Dart's `Point(this.x)`) to its
  /// field: `o.x = x`. Go has no such shorthand, and without this the factory
  /// would ignore its arguments and leave the fields zero-valued.
  ///
  /// Written after [_writeFieldInits] so an explicit argument wins over the
  /// field's declared initial value.
  void _writeThisParameterInits(
    ASTClassConstructorDeclaration ctor,
    StringBuffer out,
    String indent,
  ) {
    for (var p in ctor.parameters.allParameters) {
      if (!p.thisParameter) continue;
      var name = _goIdent(p.name);
      out.write('$indent$_receiver.$name = $name\n');
    }
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
      out.write(_goIdent(field.name));
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
    out.write(_goIdent(parameter.name));
    out.write(' ');
    generateASTType(parameter.type, out: out);

    // A `T?` parameter arrives as a `*T`, so reads of it deref.
    _trackNullablePtr(parameter.name, parameter.type);

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

    // A `T?` local is a `*T`; register it before the initializer is generated
    // so a self-reference reads correctly, and so later statements deref it.
    _trackNullablePtr(statement.name, type);
    var isPtr = _nullablePtrVars.containsKey(_goIdent(statement.name));

    // `T? x = <non-null>` needs the address of the value, and Go cannot write
    // `&5`; route it through the `goPtr` helper.
    if (isPtr && value != null && value is! ASTExpressionNullValue) {
      _needsGoPtrHelper = true;
      out.write('var ');
      out.write(_goIdent(statement.name));
      out.write(' ');
      generateASTType(type, out: out);
      out.write(' = goPtr(');
      generateASTExpression(
        value,
        out: out,
        indent: indent,
        headIndented: false,
      );
      out.write(')');
      return out;
    }

    if (value != null && type is ASTTypeVar) {
      // Inferred + value: `x := expr`.
      out.write(_goIdent(statement.name));
      out.write(' := ');
      generateASTExpression(
        value,
        out: out,
        indent: indent,
        headIndented: false,
      );
    } else {
      // `var x Type = expr`, `var x Type`, or `var x = expr`.
      out.write('var ');
      out.write(_goIdent(statement.name));
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

    // A `return x` of a nullable is a *read*, so it derefs — this path writes
    // the variable directly rather than going through
    // `generateASTExpressionVariableAccess`.
    var variable = statement.variable;
    var ptr = variable is ASTScopeVariable
        ? (_nullablePtrVars.containsKey(_goIdent(variable.name))
              ? _goIdent(variable.name)
              : null)
        : null;

    if (ptr != null) {
      out.write('(*$ptr)');
    } else {
      generateASTVariable(
        statement.variable,
        out: out,
        indent: indent,
        headIndented: false,
      );
    }
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
  /// Go has no `assert`; the idiom is an explicit check plus `panic`.
  @override
  StringBuffer generateASTStatementAssert(
    ASTStatementAssert statement, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);

    out.write('if !(');
    generateASTExpression(statement.condition, out: out, headIndented: false);
    out.write(') {\n');
    out.write('$indent  panic(');

    var message = statement.message;
    if (message != null) {
      generateASTExpression(message, out: out, headIndented: false);
    } else {
      out.write('"Assertion failed"');
    }

    out.write(')\n');
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
    generateASTExpression(
      expression.valueIfTrue,
      out: out,
      headIndented: false,
    );
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

    // Instantiating a struct calls its factory: `Point(...)` -> `NewPoint(...)`.
    if (_programStructNames.contains(expression.name)) {
      out ??= newOutput();
      if (headIndented) out.write(indent);
      out.write('New');
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

    // Sibling-method calls inside a struct method become `o.method(...)`.
    if (_currentClassMethods.contains(expression.name)) {
      out ??= newOutput();
      if (headIndented) out.write(indent);
      out.write('$_receiver.');
      out.write(_goIdent(expression.name));
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
    // Field reads inside a struct method become `o.field`, unless a parameter
    // of the same name shadows the field.
    if (!variable.isTypeIdentifier &&
        _currentClassFields.contains(variable.name) &&
        !_currentMemberParameters.contains(variable.name)) {
      out ??= newOutput();
      if (headIndented) out.write(indent);
      out.write('$_receiver.');
      out.write(_goIdent(variable.name));
      return out;
    }

    // A plain variable read: the base writes the raw name, which would not
    // agree with the mangled name its declaration emitted.
    if (!variable.isTypeIdentifier) {
      out ??= newOutput();
      if (headIndented) out.write(indent);
      out.write(_goIdent(variable.name));
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
      out.write(_goIdent(variable.name));
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

  /// Go has neither a null-coalescing operator nor a conditional *expression*,
  /// and this generator maps a nullable `T?` onto a plain Go `T` — which for a
  /// value type (`int`, `string`, …) cannot be compared to `nil` at all. Any
  /// rendering would therefore be code that does not compile, so `??` is
  /// reported as unsupported instead of emitted.
  ///
  /// Supporting it properly means representing `T?` as `*T` throughout the Go
  /// generator (declarations, assignments and dereferences), which is a
  /// separate piece of work.
  @override
  String renderNullCoalesce(String a, String b) {
    // Plain `a ?? b` no longer reaches here — `generateASTExpressionNullCoalesce`
    // lowers it to a nil-checking inline function over the `*T`. This text-level
    // hook is left only for `??=`, whose lowering (`t = t ?? v`) would need the
    // target's element type to write the inline function's return type, which
    // is not available at this point.
    throw UnsupportedSyntaxError(
      'Go has no `??=`, and lowering it to `t = t ?? v` needs the target\'s '
      'element type to build the nil-checking inline function. Use an explicit '
      '`if (t == null) { t = v; }` instead.',
    );
  }

  /// Go has no `??=`; the lowering to `t = t ?? v` still goes through
  /// [renderNullCoalesce], which reports it as unsupported.
  @override
  bool get supportsNullCoalesceAssignment => false;

  /// Go has no null-aware access. Degrading `a?.b` to `a.b` would both skip the
  /// nil check *and* read through a `*T` where the field is expected, so it is
  /// reported rather than mis-emitted.
  @override
  String renderNullAwareGuard(String receiver, String guarded) {
    throw UnsupportedSyntaxError(
      'Go has no null-aware access (`?.` / `?[`), and this generator represents '
      'a nullable `T?` as `*T`, so guarding it needs the receiver\'s pointer '
      'type to both nil-check and dereference. Use an explicit '
      '`if ($receiver != nil) { … }` instead.',
    );
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
    generateASTType(expression.valueType ?? ASTTypeDynamic.instance, out: out);
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
    // A nullable `T?` becomes a Go pointer `*T`, which is the only Go form that
    // can hold `nil` for a value type. Types that are *already* nilable in Go —
    // a slice, a map, an interface — stay as they are.
    if (type.nullable && _goNeedsPointerForNull(type)) {
      out ??= newOutput();
      out.write(indent);
      out.write('*');
      generateASTType(type.withoutNullability(), out: out);
      return out;
    }

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

  /// Null-aware *access* (`a?.x`) has no Go form.
  ///
  /// The shared fallback degrades `?.` to `.`, which was merely lossy while a
  /// nullable was a plain `T`. Now that it is a `*T`, that fallback would emit
  /// a bare `a.x` — no nil check, and a value where a `*T` is expected. Both
  /// are wrong, so it is reported instead.
  ///
  /// Lowering it properly means an inline `func() *T { if a != nil { return
  /// goPtr(a.x) }; return nil }()`, which needs the accessed member's type at
  /// generation time — the generator does not resolve that yet.
  Never _unsupportedNullAware(String form) {
    throw UnsupportedSyntaxError(
      "Go has no null-aware access operator, and this generator now represents "
      "a nullable `T?` as `*T`, so `$form` cannot be degraded to a plain "
      "access: it would skip the nil check and yield the wrong type.",
    );
  }

  @override
  StringBuffer generateASTExpressionObjectGetterAccess(
    ASTExpressionObjectGetterAccess expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    if (expression.isNullAware) _unsupportedNullAware('?.${expression.name}');
    return super.generateASTExpressionObjectGetterAccess(
      expression,
      out: out,
      indent: indent,
      headIndented: headIndented,
    );
  }

  /// The pointer name for a nullable variable read, or `null` when [expression]
  /// is not one. Used where the *pointer* is wanted rather than its value.
  String? _nullablePtrName(ASTExpression expression) {
    if (expression is! ASTExpressionVariableAccess) return null;
    var v = expression.variable;
    if (v is! ASTScopeVariable) return null;
    var name = _goIdent(v.name);
    return _nullablePtrVars.containsKey(name) ? name : null;
  }

  /// `x == null` / `x != null` compare the *pointer*, so they must not deref.
  ///
  /// A non-pointer operand cannot be nil in Go, so it falls through to the
  /// default rendering (which spells the literal `nil` via [nullValueLiteral]).
  @override
  StringBuffer generateASTExpressionNullCheck(
    ASTExpressionNullCheck expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    var ptr = _nullablePtrName(expression.expression);

    if (ptr != null) {
      out ??= newOutput();
      if (headIndented) out.write(indent);
      var op = expression.negated ? '!=' : '==';
      out.write(expression.nullFirst ? 'nil $op $ptr' : '$ptr $op nil');
      return out;
    }

    return super.generateASTExpressionNullCheck(
      expression,
      out: out,
      indent: indent,
      headIndented: headIndented,
    );
  }

  @override
  String get nullValueLiteral => 'nil';

  /// `a ?? b` on a nullable pointer: Go has no conditional *expression*, so this
  /// is an immediately-invoked function that nil-checks the pointer. When the
  /// left side is not a nullable pointer it cannot be nil, so it wins outright.
  @override
  StringBuffer generateASTExpressionNullCoalesce(
    ASTExpressionNullCoalesce expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    var ptr = _nullablePtrName(expression.expression1);
    if (ptr == null) {
      return generateASTExpression(
        expression.expression1,
        out: out,
        indent: indent,
        headIndented: false,
      );
    }

    var fallback = generateASTExpression(
      expression.expression2,
      indent: indent,
      headIndented: false,
    ).toString();

    out.write('func() ');
    generateASTType(_nullablePtrVars[ptr] ?? ASTTypeDynamic.instance, out: out);
    out.write(' { if $ptr != nil { return *$ptr }; return $fallback }()');

    return out;
  }

  /// Reading a `T?` local/parameter derefs its pointer.
  ///
  /// This is the *read* path only — an assignment writes through
  /// `generateASTVariable`, where the pointer itself is the target and must not
  /// be deref'd. A comparison against `null` is handled before this, by
  /// [generateASTExpressionNullCheck], so `x == nil` keeps testing the pointer.
  @override
  StringBuffer generateASTExpressionVariableAccess(
    ASTExpressionVariableAccess expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    var variable = expression.variable;
    if (variable is ASTScopeVariable &&
        _nullablePtrVars.containsKey(_goIdent(variable.name))) {
      out ??= newOutput();
      if (headIndented) out.write(indent);
      out.write('(*');
      out.write(_goIdent(variable.name));
      out.write(')');
      return out;
    }
    return super.generateASTExpressionVariableAccess(
      expression,
      out: out,
      indent: indent,
      headIndented: headIndented,
    );
  }

  /// Whether a nullable [type] needs a Go pointer to represent `nil`.
  ///
  /// Go slices, maps and interfaces are already nilable, so `List<int>?` stays
  /// `[]int`. Value types (`int`, `string`, `bool`, a struct) are not, so they
  /// become `*int`, `*string`, ….
  static bool _goNeedsPointerForNull(ASTType type) =>
      !(type is ASTTypeArray ||
          type is ASTTypeMap ||
          type is ASTTypeDynamic ||
          type is ASTTypeObject);

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
