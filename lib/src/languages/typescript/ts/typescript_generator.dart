// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import '../../../apollovm_code_generator.dart';
import '../../../apollovm_code_storage.dart';
import '../../../ast/apollovm_ast_expression.dart';
import '../../../ast/apollovm_ast_statement.dart';
import '../../../ast/apollovm_ast_toplevel.dart';
import '../../../ast/apollovm_ast_type.dart';
import '../../../ast/apollovm_ast_value.dart';
import '../../../ast/apollovm_ast_variable.dart';

/// TypeScript implementation of an [ApolloCodeGenerator].
///
/// Emits idiomatic ECMAScript: `let`/`const`, template literals for string
/// interpolation, `for...of` loops, top-level `function` declarations,
/// untyped parameters/fields and `===`/`!==` equality.
class ApolloCodeGeneratorTypeScript extends ApolloCodeGenerator {
  ApolloCodeGeneratorTypeScript(ApolloSourceCodeStorage codeStorage)
    : super('typescript', codeStorage);

  @override
  String normalizeTypeName(String typeName, [String? callingFunction]) {
    // Static-call targets (e.g. `Number.parseInt`) use the JS global object,
    // not the TypeScript primitive type name.
    if (callingFunction != null) {
      switch (typeName) {
        case 'int':
        case 'Integer':
        case 'double':
        case 'Double':
        case 'num':
        case 'number':
          return 'Number';
        default:
          return typeName;
      }
    }

    // Type annotations use TypeScript primitive names.
    switch (typeName) {
      case 'int':
      case 'Integer':
      case 'double':
      case 'Double':
      case 'num':
        return 'number';
      case 'bool':
      case 'Boolean':
        return 'boolean';
      case 'String':
        return 'string';
      case 'void':
        return 'void';
      case 'dynamic':
      case 'Object':
        return 'any';
      default:
        return typeName;
    }
  }

  /// Emits a `: type` annotation when [type] is an explicit type (i.e. not an
  /// inferred `var` and not `dynamic`).
  void _writeTypeAnnotation(ASTType type, StringBuffer out) {
    if (type is ASTTypeVar || type == ASTTypeDynamic.instance) return;
    out.write(': ');
    out.write(generateASTType(type));
  }

  @override
  String normalizeTypeFunction(String typeName, String functionName) {
    switch (typeName) {
      case 'int':
      case 'Integer':
        {
          switch (functionName) {
            case 'parse':
            case 'parseInt':
              return 'parseInt';
            default:
              return functionName;
          }
        }
      case 'double':
      case 'Double':
        {
          switch (functionName) {
            case 'parse':
            case 'parseDouble':
            case 'parseFloat':
              return 'parseFloat';
            default:
              return functionName;
          }
        }
      default:
        return functionName;
    }
  }

  @override
  StringBuffer generateASTStatementImport(
    ASTStatementImport import, {
    StringBuffer? out,
    String indent = '',
  }) {
    final path = import.path;
    final prefix = import.prefix;

    out ??= newOutput();

    if (prefix != null) {
      out.write("import * as $prefix from '$path';\n");
    } else {
      out.write("import '$path';\n");
    }

    return out;
  }

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

    var code = generateASTBlock(
      clazz,
      withBrackets: true,
      withBlankHeadLine: true,
    );

    if (clazz.isAbstract) out.write('abstract ');
    out.write(clazz.isInterface ? 'interface ' : 'class ');
    out.write(clazz.name);

    if (clazz.superClassName != null) {
      out.write(' extends ');
      out.write(clazz.superClassName!);
    }

    var implementsTypes = clazz.implementsTypes;
    if (implementsTypes != null && implementsTypes.isNotEmpty) {
      // An interface `extends` other interfaces; a class `implements` them.
      out.write(clazz.isInterface ? ' extends ' : ' implements ');
      out.write(implementsTypes.join(', '));
    }

    out.write(' ');
    out.write(code);

    return out;
  }

  /// Returns `true` if [clazz] is a rich/enhanced enum (entries with
  /// constructor arguments, or declared fields/constructors/methods). A rich
  /// enum can't map to a native TypeScript `enum`, so it's emitted as a class
  /// with static-readonly singleton instances.
  bool _isRichEnum(ASTClassEnum clazz) =>
      clazz.entries.any((e) => e.arguments != null) ||
      clazz.fields.isNotEmpty ||
      clazz.constructors.isNotEmpty ||
      clazz.functions.isNotEmpty;

  /// Generates a TypeScript `enum` declaration.
  ///
  /// A rich/enhanced enum is emitted as a class with a constructor and one
  /// `static readonly` singleton instance per entry (see [_isRichEnum]).
  StringBuffer generateASTClassEnum(
    ASTClassEnum clazz, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    if (_isRichEnum(clazz)) {
      return _generateRichEnumTypeScript(clazz, out, indent);
    }

    out.write(indent);
    out.write('enum ');
    out.write(clazz.name);
    out.write(' {\n');

    var entries = clazz.entries;
    for (var i = 0; i < entries.length; ++i) {
      var e = entries[i];
      out.write('$indent  ');
      out.write(e.name);
      if (e.value != null) {
        out.write(' = ');
        generateASTExpression(e.value!, out: out, headIndented: false);
      }
      if (i < entries.length - 1) out.write(',');
      out.write('\n');
    }

    out.write('$indent}\n');

    return out;
  }

  /// Emits a rich/enhanced enum as a TypeScript class: a constructor using
  /// parameter properties for the declared fields, the methods, one
  /// `static readonly` singleton per entry (constructed with its arguments)
  /// and a `values` array.
  StringBuffer _generateRichEnumTypeScript(
    ASTClassEnum clazz,
    StringBuffer out,
    String indent,
  ) {
    var i2 = '$indent  ';
    var name = clazz.name;

    out.write(indent);
    out.write('class ');
    out.write(name);
    out.write(' {\n');

    // Constructor — parameter properties declare and assign the fields.
    var ctor = clazz.constructors.isNotEmpty
        ? clazz.constructors.first.firstFunction
        : null;

    // Names of the fields covered by the constructor's `this.` parameters.
    var ctorFieldNames = <String>{};

    if (ctor != null) {
      var params = ctor.parameters.allParameters;
      out.write(i2);
      out.write('constructor(');
      for (var i = 0; i < params.length; ++i) {
        var p = params[i];
        if (i > 0) out.write(', ');
        if (p.thisParameter) {
          ctorFieldNames.add(p.name);
          var field = clazz.getField(p.name);
          out.write(
            (field != null && field.finalValue)
                ? 'public readonly '
                : 'public ',
          );
        }
        out.write(p.name);
        _writeTypeAnnotation(p.type, out);
      }
      out.write(') {}\n\n');
    }

    // Fields not declared via constructor parameter properties.
    for (var field in clazz.fields) {
      if (ctorFieldNames.contains(field.name)) continue;
      out.write(i2);
      if (field.modifiers.isStatic) out.write('static ');
      if (field.finalValue) out.write('readonly ');
      out.write(field.name);
      _writeTypeAnnotation(field.type, out);
      if (field is ASTClassFieldWithInitialValue) {
        out.write(' = ');
        generateASTExpression(
          field.initialValue,
          out: out,
          headIndented: false,
        );
      }
      out.write(';\n');
    }

    // Methods.
    for (var set in clazz.functions) {
      for (var f in set.functions) {
        if (f is! ASTClassFunctionDeclaration) continue;
        generateASTClassFunctionDeclaration(f, out: out, indent: i2);
      }
    }

    // Static singleton instances (one per entry).
    for (var e in clazz.entries) {
      out.write(i2);
      out.write('static readonly ${e.name} = new $name(');
      var args = e.arguments;
      if (args != null) {
        for (var i = 0; i < args.length; ++i) {
          if (i > 0) out.write(', ');
          generateASTExpression(args[i], out: out, headIndented: false);
        }
      }
      out.write(');\n');
    }

    // Values array.
    out.write(i2);
    out.write('static readonly values = [');
    out.write(clazz.entries.map((e) => '$name.${e.name}').join(', '));
    out.write('];\n');

    out.write('$indent}\n');

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

    var m = field.modifiers;
    if (m.isPrivate) {
      out.write('private ');
    } else if (m.isProtected) {
      out.write('protected ');
    }
    if (m.isStatic) out.write('static ');
    if (m.isFinal) out.write('readonly ');

    out.write(field.name);
    _writeTypeAnnotation(field.type, out);

    if (field is ASTClassFieldWithInitialValue) {
      out.write(' = ');
      generateASTExpression(field.initialValue, out: out, headIndented: false);
    }

    out.write(';\n');

    return out;
  }

  @override
  StringBuffer generateASTClassConstructorDeclaration(
    ASTClassConstructorDeclaration c, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    var blockCode = generateASTBlock(c, indent: indent, withBrackets: false);

    out.write(indent);
    out.write('constructor');
    _generateFunctionParamsAndBlock(c, blockCode, out, indent);

    return out;
  }

  @override
  StringBuffer generateASTFunctionDeclaration(
    ASTFunctionDeclaration f, {
    StringBuffer? out,
    String indent = '',
  }) {
    // TypeScript allows top-level `function` declarations.
    out ??= newOutput();

    var blockCode = generateASTBlock(f, indent: indent, withBrackets: false);

    out.write(indent);
    if (f.modifiers.isAsync) {
      out.write('async ');
    }
    out.write('function ');
    out.write(f.name);
    _generateFunctionParamsAndBlock(f, blockCode, out, indent);

    return out;
  }

  @override
  StringBuffer generateASTClassFunctionDeclaration(
    ASTClassFunctionDeclaration f, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    var blockCode = generateASTBlock(f, indent: indent, withBrackets: false);

    out.write(indent);

    var m = f.modifiers;
    if (m.isPrivate) {
      out.write('private ');
    } else if (m.isProtected) {
      out.write('protected ');
    }

    // Interface members are implicitly abstract; don't emit the keyword there.
    var clazz = f.clazz;
    var inInterface = clazz is ASTClassNormal && clazz.isInterface;
    if (m.isAbstract && !inInterface) out.write('abstract ');
    if (m.isStatic) out.write('static ');
    if (m.isAsync) out.write('async ');

    out.write(f.name);
    _generateFunctionParamsAndBlock(f, blockCode, out, indent);

    return out;
  }

  void _generateFunctionParamsAndBlock(
    ASTInvocableDeclaration f,
    StringBuffer blockCode,
    StringBuffer out,
    String indent,
  ) {
    out.write('(');

    if (f.parametersSize > 0) {
      generateASTParametersDeclaration(f.parameters, out: out);
    }

    out.write(')');

    // Return type annotation (functions/methods only, not constructors).
    if (f is ASTFunctionDeclaration) {
      _writeTypeAnnotation(f.returnType, out);
    }

    // Abstract/interface methods have no body.
    if (f is ASTFunctionDeclaration && f.modifiers.isAbstract) {
      out.write(';\n\n');
      return;
    }

    out.write(' {\n');
    out.write(blockCode);
    out.write(indent);
    out.write('}\n\n');
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
    // TypeScript parameters carry an optional `: type` annotation.
    out ??= newOutput();
    out.write(parameter.name);
    _writeTypeAnnotation(parameter.type, out);
    appendParameterDefaultValue(parameter, out, indent);
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

  @override
  StringBuffer generateASTStatementVariableDeclaration(
    ASTStatementVariableDeclaration statement, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    // `const` only when unmodifiable AND initialized (JS forbids uninitialized
    // `const`); otherwise `let`.
    var keyword = (statement.unmodifiable && statement.value != null)
        ? 'const'
        : 'let';

    out.write(keyword);
    out.write(' ');
    out.write(statement.name);
    _writeTypeAnnotation(statement.type, out);

    if (statement.value != null) {
      out.write(' = ');
      generateASTExpression(
        statement.value!,
        out: out,
        indent: indent,
        headIndented: false,
      );
    }

    out.write(';');

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

    out.write('for (const ');
    out.write(forEach.variableName);
    out.write(' of ');

    generateASTExpression(
      forEach.iterableExpression,
      out: out,
      indent: indent,
      headIndented: false,
    );

    out.write(') {\n');

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
  String resolveASTExpressionOperatorText(
    ASTExpressionOperator operator,
    ASTNumType aNumType,
    ASTNumType bNumType,
  ) {
    switch (operator) {
      // Strict equality in TypeScript.
      case ASTExpressionOperator.equals:
        return '===';
      case ASTExpressionOperator.notEquals:
        return '!==';
      default:
        return getASTExpressionOperatorText(operator);
    }
  }

  @override
  StringBuffer generateASTExpressionOperation(
    ASTExpressionOperation expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    // TypeScript has no integer-division operator; `a ~/ b` becomes
    // `Math.trunc(a / b)`.
    if (expression.operator == ASTExpressionOperator.divideAsInt) {
      out ??= newOutput();
      if (headIndented) out.write(indent);

      out.write('Math.trunc(');
      generateASTExpression(
        expression.expression1,
        out: out,
        indent: indent,
        headIndented: false,
      );
      out.write(' / ');
      generateASTExpression(
        expression.expression2,
        out: out,
        indent: indent,
        headIndented: false,
      );
      out.write(')');

      return out;
    }

    return super.generateASTExpressionOperation(
      expression,
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

  /// TypeScript arrays are rendered as `T[]` (1D), `T[][]` (2D), `T[][][]` (3D).
  StringBuffer _writeArrayType(
    ASTType elementType,
    int dims,
    StringBuffer out,
  ) {
    out.write(generateASTType(elementType));
    out.write('[]' * dims);
    return out;
  }

  @override
  StringBuffer generateASTTypeArray(
    ASTTypeArray type, {
    StringBuffer? out,
    String indent = '',
  }) => _writeArrayType(type.elementType, 1, out ??= newOutput());

  @override
  StringBuffer generateASTTypeArray2D(
    ASTTypeArray2D type, {
    StringBuffer? out,
    String indent = '',
  }) => _writeArrayType(type.elementType, 2, out ??= newOutput());

  @override
  StringBuffer generateASTTypeArray3D(
    ASTTypeArray3D type, {
    StringBuffer? out,
    String indent = '',
  }) => _writeArrayType(type.elementType, 3, out ??= newOutput());

  @override
  StringBuffer generateASTValueString(
    ASTValueString value, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    out.write("'");
    out.write(_escapeSingleQuoted(value.value));
    out.write("'");

    return out;
  }

  static String _escapeSingleQuoted(String str) {
    return str
        .replaceAll('\\', r'\\')
        .replaceAll('\t', r'\t')
        .replaceAll('\r', r'\r')
        .replaceAll('\n', r'\n')
        .replaceAll('\b', r'\b')
        .replaceAll("'", r"\'");
  }

  static String _escapeTemplateLiteral(String str) {
    return str
        .replaceAll('\\', r'\\')
        .replaceAll('`', r'\`')
        .replaceAll(r'$', r'\$')
        .replaceAll('\t', r'\t')
        .replaceAll('\r', r'\r')
        .replaceAll('\n', r'\n')
        .replaceAll('\b', r'\b');
  }

  /// Renders a string-component value as the inner content of a template
  /// literal (without the surrounding back-ticks).
  String _templateInner(ASTValue value) {
    if (value is ASTValueString) {
      return _escapeTemplateLiteral(value.value);
    } else if (value is ASTValueStringVariable) {
      return '\${${value.variable.name}}';
    } else if (value is ASTValueStringExpression) {
      var exp = generateASTExpression(value.expression).toString();
      return '\${$exp}';
    } else if (value is ASTValueStringConcatenation) {
      return value.values.map(_templateInner).join();
    } else {
      return generateASTValue(value).toString();
    }
  }

  @override
  StringBuffer generateASTValueStringConcatenation(
    ASTValueStringConcatenation value, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    out.write('`');
    out.write(value.values.map(_templateInner).join());
    out.write('`');

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

    out.write('`\${');
    out.write(value.variable.name);
    out.write('}`');

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
    out.write('`\${');
    out.write(exp);
    out.write('}`');

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
