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

/// JavaScript (modern ES) implementation of an [ApolloCodeGenerator].
///
/// Emits idiomatic ECMAScript: `let`/`const`, template literals for string
/// interpolation, `for...of` loops, top-level `function` declarations,
/// untyped parameters/fields and `===`/`!==` equality.
class ApolloCodeGeneratorJavaScript extends ApolloCodeGenerator {
  ApolloCodeGeneratorJavaScript(ApolloSourceCodeStorage codeStorage)
    : super('javascript', codeStorage);

  /// Optional chaining (`a?.b`, `a?.[i]`) is ES2020.
  @override
  bool get supportsNullAwareOperators => true;

  /// JavaScript has no null-assertion operator: a postfix `!` is logical NOT,
  /// so emitting it would change the meaning rather than drop a check. `x!` is
  /// emitted as plain `x` (the assertion is a no-op at runtime in JS anyway).
  @override
  bool get supportsNullAssertionOperator => false;

  /// JavaScript's null-aware element access is `a?.[i]`, not `a?[i]`.
  @override
  String get nullAwareIndexOpen => '?.[';

  @override
  String normalizeTypeName(String typeName, [String? callingFunction]) {
    switch (typeName) {
      // Static helpers like `int.parse(x)` / `Integer.parseInt(x)` map to the
      // global `Number` object (`Number.parseInt`, `Number.parseFloat`).
      case 'int':
      case 'Integer':
      case 'double':
      case 'Double':
        return 'Number';
      default:
        return typeName;
    }
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

    var code = generateASTBlock(
      clazz,
      withBrackets: true,
      withBlankHeadLine: true,
    );

    out.write('class ');
    out.write(clazz.name);
    out.write(' ');
    out.write(code);

    return out;
  }

  @override
  StringBuffer generateASTClassField(
    ASTClassField field, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    // JavaScript class fields are untyped public fields: `name = value;`.
    out.write(indent);
    out.write(field.name);

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
    // JavaScript allows top-level `function` declarations.
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

    if (f.modifiers.isStatic) {
      out.write('static ');
    }

    if (f.modifiers.isAsync) {
      out.write('async ');
    }

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

    out.write(') {\n');
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
    // JavaScript parameters are untyped (and have no `this.` shorthand).
    out ??= newOutput();
    out.write(parameter.name);
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

    out.write(')');

    if (writeASTLoopBody(forEach.loopBlock, out: out, indent: indent)) {
      out.write('}');
    }

    return out;
  }

  @override
  String resolveASTExpressionOperatorText(
    ASTExpressionOperator operator,
    ASTNumType aNumType,
    ASTNumType bNumType,
  ) {
    switch (operator) {
      // Strict equality in JavaScript.
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
    // JavaScript has no integer-division operator; `a ~/ b` becomes
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

  @override
  StringBuffer generateASTTypeArray(
    ASTTypeArray type, {
    StringBuffer? out,
    String indent = '',
  }) => generateASTTypeDefault(type, out: out, indent: indent);

  @override
  StringBuffer generateASTTypeArray2D(
    ASTTypeArray2D type, {
    StringBuffer? out,
    String indent = '',
  }) => generateASTTypeDefault(type, out: out, indent: indent);

  @override
  StringBuffer generateASTTypeArray3D(
    ASTTypeArray3D type, {
    StringBuffer? out,
    String indent = '',
  }) => generateASTTypeDefault(type, out: out, indent: indent);

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
