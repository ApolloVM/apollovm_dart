// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import '../../apollovm_code_generator.dart';
import '../../apollovm_code_storage.dart';
import '../../apollovm_parser.dart';
import '../../ast/apollovm_ast_expression.dart';
import '../../ast/apollovm_ast_statement.dart';
import '../../ast/apollovm_ast_toplevel.dart';
import '../../ast/apollovm_ast_type.dart';
import '../../ast/apollovm_ast_value.dart';
import '../../ast/apollovm_ast_variable.dart';

/// C# implementation of an [ApolloCodeGenerator].
class ApolloCodeGeneratorCSharp extends ApolloCodeGenerator {
  ApolloCodeGeneratorCSharp(ApolloSourceCodeStorage codeStorage)
    : super('csharp', codeStorage);

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
    generateFunctionParametersNames(f, out: out);

    // C# lambda: `(params) => expr` or `(params) => { body }`.
    out.write(' => ');
    var single = singleReturnExpression(f);
    if (single != null) {
      generateASTExpression(single, out: out, headIndented: false);
    } else {
      var blockCode = generateASTBlock(f, indent: indent, withBrackets: false);
      out.write('{\n');
      out.write(blockCode);
      out.write(indent);
      out.write('}');
    }

    return out;
  }

  @override
  String normalizeTypeName(String typeName, [String? callingFunction]) {
    switch (typeName) {
      case 'dynamic':
        return 'object';
      default:
        return typeName;
    }
  }

  @override
  String generateASTCatchClauseHeader(ASTCatchClause catchClause) {
    var name = catchClause.variableName ?? 'e';
    var type = catchClause.exceptionType;
    var typeStr = type != null ? '${generateASTType(type)}' : 'Exception';
    return 'catch ($typeStr $name)';
  }

  @override
  String normalizeTypeFunction(String typeName, String functionName) {
    switch (typeName) {
      case 'int':
      case 'Int32':
        {
          switch (functionName) {
            case 'parse':
            case 'parseInt':
              return 'Parse';
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

    out ??= newOutput();

    out.write('using ');
    out.write(path);
    out.write(';\n');

    return out;
  }

  /// The name of the self-parameter of the extension method being generated.
  /// While set, `this` is rendered as that identifier — C# extension methods
  /// receive the instance as a parameter, not as `this`.
  String? _extensionSelfName;

  /// C# has no extension *block*: an extension is a `static class` whose
  /// methods take a `this`-qualified first parameter.
  ///
  /// C# has no extension properties, so an extension declaring getters (from
  /// Dart or Kotlin) cannot be expressed.
  @override
  StringBuffer generateASTExtension(
    ASTExtension extension, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    if (extension.getter.isNotEmpty) {
      throw UnsupportedSyntaxError(
        'C# has no extension property: ${extension.getter.map((g) => g.name).join(', ')}',
      );
    }

    var name = extension.name ?? '${extension.targetType.name}Extension';
    var indent2 = '$indent  ';

    out.write(indent);
    out.write('static class ');
    out.write(name);
    out.write(' {\n\n');

    for (var set in extension.functions) {
      for (var f in set.functions) {
        if (f is ASTClassFunctionDeclaration) {
          _generateExtensionMethod(f, extension.targetType, out, indent2);
        }
      }
    }

    out.write(indent);
    out.write('}\n');

    return out;
  }

  void _generateExtensionMethod(
    ASTClassFunctionDeclaration f,
    ASTType targetType,
    StringBuffer out,
    String indent,
  ) {
    const selfName = 'self';

    _extensionSelfName = selfName;
    StringBuffer blockCode;
    try {
      blockCode = generateASTBlock(f, indent: indent, withBrackets: false);
    } finally {
      _extensionSelfName = null;
    }

    out.write(indent);
    out.write('public static ');
    if (f.modifiers.isAsync) out.write('async ');
    out.write(generateASTType(f.returnType));
    out.write(' ');
    out.write(f.name);

    out.write('(this ');
    out.write(generateASTType(targetType));
    out.write(' $selfName');
    if (f.parametersSize > 0) {
      out.write(', ');
      generateASTParametersDeclaration(f.parameters, out: out);
    }
    out.write(') {\n');
    out.write(blockCode);
    out.write(indent);
    out.write('}\n\n');
  }

  @override
  StringBuffer generateASTVariable(
    ASTVariable variable, {
    String? callingFunction,
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    var selfName = _extensionSelfName;
    if (selfName != null && variable is ASTThisVariable) {
      out ??= newOutput();
      if (headIndented) out.write(indent);
      out.write(selfName);
      return out;
    }

    return super.generateASTVariable(
      variable,
      callingFunction: callingFunction,
      out: out,
      indent: indent,
      headIndented: headIndented,
    );
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

    out.write('class ');
    out.write(clazz.name);
    out.write(' ');
    out.write(code);

    return out;
  }

  /// Returns `true` if [clazz] is a rich/enhanced enum (entries with
  /// constructor arguments, or declared fields/constructors/methods). A rich
  /// enum can't map to a native C# `enum`, so it's emitted as a class with
  /// static-readonly singleton instances.
  bool _isRichEnum(ASTClassEnum clazz) =>
      clazz.entries.any((e) => e.arguments != null) ||
      clazz.fields.isNotEmpty ||
      clazz.constructors.isNotEmpty ||
      clazz.functions.isNotEmpty;

  /// Generates a C# `enum` declaration (with optional `= value` entries).
  ///
  /// A rich/enhanced enum is emitted as a class with a private constructor and
  /// one `static readonly` singleton instance per entry (see [_isRichEnum]).
  StringBuffer generateASTClassEnum(
    ASTClassEnum clazz, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    if (_isRichEnum(clazz)) {
      return _generateRichEnumCSharp(clazz, out, indent);
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

  /// Emits a rich/enhanced enum as a C# class: declared fields, a `private`
  /// constructor, the methods, one `public static readonly` singleton per
  /// entry (constructed with its arguments) and a `Values` array.
  StringBuffer _generateRichEnumCSharp(
    ASTClassEnum clazz,
    StringBuffer out,
    String indent,
  ) {
    var i2 = '$indent  ';
    var name = clazz.name;

    out.write(indent);
    out.write('class ');
    out.write(name);
    out.write(' {\n\n');

    // Declared fields.
    for (var field in clazz.fields) {
      out.write(i2);
      out.write('public ');
      if (field.finalValue) out.write('readonly ');
      out.write(generateASTType(field.type));
      out.write(' ');
      out.write(field.name);
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
    if (clazz.fields.isNotEmpty) out.write('\n');

    // Private constructor.
    var ctor = clazz.constructors.isNotEmpty
        ? clazz.constructors.first.firstFunction
        : null;
    if (ctor != null) {
      var params = ctor.parameters.allParameters;
      out.write(i2);
      out.write('private ');
      out.write(name);
      out.write('(');
      for (var i = 0; i < params.length; ++i) {
        if (i > 0) out.write(', ');
        out.write(generateASTType(params[i].type));
        out.write(' ');
        out.write(params[i].name);
      }
      out.write(') {\n');
      for (var p in params) {
        if (p.thisParameter) {
          out.write('$i2  this.${p.name} = ${p.name};\n');
        }
      }
      out.write(generateASTBlock(ctor, indent: i2, withBrackets: false));
      out.write('$i2}\n\n');
    }

    // Methods.
    for (var set in clazz.functions) {
      for (var f in set.functions) {
        if (f is! ASTClassFunctionDeclaration) continue;
        out.write(i2);
        out.write('public ');
        if (f.modifiers.isStatic) out.write('static ');
        out.write(generateASTType(f.returnType));
        out.write(' ');
        out.write(f.name);
        out.write('(');
        if (f.parametersSize > 0) {
          generateASTParametersDeclaration(f.parameters, out: out);
        }
        out.write(') {\n');
        out.write(generateASTBlock(f, indent: i2, withBrackets: false));
        out.write('$i2}\n\n');
      }
    }

    // Static singleton instances (one per entry).
    for (var e in clazz.entries) {
      out.write(i2);
      out.write('public static readonly $name ${e.name} = new $name(');
      var args = e.arguments;
      if (args != null) {
        for (var i = 0; i < args.length; ++i) {
          if (i > 0) out.write(', ');
          generateASTExpression(args[i], out: out, headIndented: false);
        }
      }
      out.write(');\n');
    }
    if (clazz.entries.isNotEmpty) out.write('\n');

    // Values array.
    out.write(i2);
    out.write('public static readonly $name[] Values = { ');
    out.write(clazz.entries.map((e) => e.name).join(', '));
    out.write(' };\n');

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

    var typeCode = generateASTType(field.type);

    out.write(indent);

    if (field.finalValue) {
      out.write('readonly ');
    }

    out.write(typeCode);
    out.write(' ');
    out.write(field.name);

    if (field is ASTClassFieldWithInitialValue) {
      var initialValueCode = generateASTExpression(
        field.initialValue,
        indent: "$indent  ",
        headIndented: false,
      );
      out.write(' = ');
      out.write(initialValueCode);
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

    out.write(c.classType.name);
    _generateFunctionParamsAndBlock(c, blockCode, out, indent);

    return out;
  }

  @override
  StringBuffer generateASTFunctionDeclaration(
    ASTFunctionDeclaration f, {
    StringBuffer? out,
    String indent = '',
  }) {
    throw UnsupportedSyntaxError('All functions in C# are from a class: $f');
  }

  @override
  StringBuffer generateASTClassFunctionDeclaration(
    ASTClassFunctionDeclaration f, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    var typeCode = generateASTType(f.returnType);

    var blockCode = generateASTBlock(f, indent: indent, withBrackets: false);

    out.write(indent);

    if (f.modifiers.isStatic) {
      out.write('static ');
    }

    if (f.modifiers.isAsync) {
      out.write('async ');
    }

    out.write(typeCode);
    out.write(' ');
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

    // C# declares all parameters positionally (any can be passed by name at the
    // call site), so positional + optional + named are emitted as a single
    // flat, comma-separated list.
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
  }) {
    return generateASTParameterDeclaration(parameter, out: out, indent: indent);
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

    // C# `foreach (var x in coll) { … }`.
    out.write('foreach (var ');
    out.write(forEach.variableName);
    out.write(' in ');

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
    if (operator == ASTExpressionOperator.divideAsInt) {
      return getASTExpressionOperatorText(ASTExpressionOperator.divide);
    }
    return getASTExpressionOperatorText(operator);
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

    final type = expression.type;

    out.write('new List');

    if (type != null) {
      out.write('<');
      generateASTType(type, out: out);
      out.write('>');
    } else {
      out.write('<object>');
    }

    out.write('(){');

    var valuesExpressions = expression.valuesExpressions;
    for (var i = 0; i < valuesExpressions.length; ++i) {
      var e = valuesExpressions[i];
      if (i > 0) out.write(', ');
      generateASTExpression(e, out: out, headIndented: false);
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

    final keyType = expression.keyType;
    final valueType = expression.valueType;

    out.write('new Dictionary');

    if (keyType != null && valueType != null) {
      out.write('<');
      generateASTType(keyType, out: out);
      out.write(', ');
      generateASTType(valueType, out: out);
      out.write('>');
    } else {
      out.write('<object, object>');
    }

    out.write('(){');

    var entriesExpressions = expression.entriesExpressions;
    for (var i = 0; i < entriesExpressions.length; ++i) {
      var e = entriesExpressions[i];
      if (i > 0) out.write(', ');
      out.write('{');
      generateASTExpression(e.key, out: out, headIndented: false);
      out.write(', ');
      generateASTExpression(e.value, out: out, headIndented: false);
      out.write('}');
    }

    out.write('}');

    return out;
  }

  @override
  StringBuffer generateASTTypeArray(
    ASTTypeArray type, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();
    out.write(indent);
    generateASTType(type.elementType, out: out);
    out.write('[]');
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
    generateASTType(type.elementType, out: out);
    out.write('[][]');
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
    generateASTType(type.elementType, out: out);
    out.write('[][][]');
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

    var str = value.value;
    str = _escapeString(str);
    out.write('"$str"');

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
    var list = <dynamic>[];

    var prevIsString = false;
    for (var v in value.values) {
      if (v is ASTValueStringVariable) {
        var s2 = generateASTValueStringVariable(
          v,
          precededByString: prevIsString,
        );
        list.add(s2);
        prevIsString = !prevIsString;
      } else if (v is ASTValueStringExpression) {
        var s2 = generateASTValueStringExpression(v);
        list.add(s2);
        prevIsString = true;
      } else if (v is ASTValueStringConcatenation) {
        var s2 = generateASTValueStringConcatenation(v);
        var string = s2.toString();
        list.add(string);
        prevIsString = string.endsWith('"');
      } else if (v is ASTValueString) {
        var s2 = generateASTValueString(v);
        list.add(s2.toString());
        prevIsString = true;
      }
    }

    out ??= newOutput();

    for (var i = 1; i < list.length;) {
      var prev = list[i - 1];
      var e = list[i];

      if (prev is String && e is String) {
        var merge = prev.substring(0, prev.length - 1) + e.substring(1);
        list[i - 1] = merge;
        list.removeAt(i);
      } else {
        ++i;
      }
    }

    for (var i = 0; i < list.length; ++i) {
      var e = list[i];
      if (i > 0) out.write(' + ');
      out.write(e);
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

    if (precededByString) {
      out.write(value.variable.name);
    } else {
      out.write('Convert.ToString( ${value.variable.name} )');
    }

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
    out.write('Convert.ToString( $exp )');

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
