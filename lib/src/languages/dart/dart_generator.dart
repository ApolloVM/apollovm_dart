// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:collection/collection.dart';

import '../../apollovm_code_generator.dart';
import '../../apollovm_code_storage.dart';
import '../../ast/apollovm_ast_expression.dart';
import '../../ast/apollovm_ast_statement.dart';
import '../../ast/apollovm_ast_toplevel.dart';
import '../../ast/apollovm_ast_type.dart';
import '../../ast/apollovm_ast_value.dart';
import '../../ast/apollovm_ast_variable.dart';

/// Dart implementation of an [ApolloCodeGenerator].
class ApolloCodeGeneratorDart extends ApolloCodeGenerator {
  ApolloCodeGeneratorDart(ApolloSourceCodeStorage codeStorage)
    : super('dart', codeStorage);

  @override
  bool get supportsNullableTypeSuffix => true;

  @override
  bool get supportsNullAwareOperators => true;

  @override
  String normalizeTypeName(String typeName, [String? callingFunction]) {
    switch (typeName) {
      case 'Integer':
        return 'int';
      default:
        return typeName;
    }
  }

  @override
  String generateASTCatchClauseHeader(ASTCatchClause catchClause) {
    var name = catchClause.variableName ?? 'e';
    var type = catchClause.exceptionType;
    if (type != null) {
      return 'on ${generateASTType(type)} catch ($name)';
    }
    return 'catch ($name)';
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
              return 'parse';
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

    out.write('import ');
    out.write("'$path'");
    if (prefix != null) {
      out.write(' as ');
      out.write(prefix);
    }
    for (var c in import.combinators) {
      out.write(c.isShow ? ' show ' : ' hide ');
      out.write(c.names.join(', '));
    }
    out.write(';\n');

    return out;
  }

  @override
  StringBuffer generateASTStatementExport(
    ASTStatementExport export, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    out.write('export');
    final path = export.path;
    if (path != null) {
      out.write(" '$path'");
    }
    for (var c in export.combinators) {
      out.write(c.isShow ? ' show ' : ' hide ');
      out.write(c.names.join(', '));
    }
    out.write(';\n');

    return out;
  }

  @override
  StringBuffer generateASTTypeAlias(
    ASTTypeAlias typeAlias, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    out.write('typedef ');
    out.write(typeAlias.name);
    out.write(' = ');
    out.write(generateASTType(typeAlias.targetType));
    out.write(';\n');

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

    // Dart has no `interface` keyword; an interface is an `abstract class`.
    if (clazz.isAbstract || clazz.isInterface) {
      out.write('abstract ');
    }

    out.write('class ');
    out.write(clazz.name);

    if (clazz.superClassName != null) {
      out.write(' extends ');
      out.write(clazz.superClassName!);
    }

    var implementsTypes = clazz.implementsTypes;
    if (implementsTypes != null && implementsTypes.isNotEmpty) {
      out.write(' implements ');
      out.write(implementsTypes.join(', '));
    }

    out.write(' ');
    out.write(code);

    return out;
  }

  @override
  StringBuffer generateASTExtension(
    ASTExtension extension, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    var code = generateASTBlock(
      extension,
      withBrackets: true,
      withBlankHeadLine: true,
    );

    out.write(indent);
    out.write('extension ');

    var name = extension.name;
    if (name != null) {
      out.write(name);
      out.write(' ');
    }

    out.write('on ');
    out.write(generateASTType(extension.targetType));
    out.write(' ');
    out.write(code);

    return out;
  }

  @override
  StringBuffer generateASTClassGetterDeclaration(
    ASTClassGetterDeclaration getter, {
    StringBuffer? out,
    String indent = '',
    String? receiver,
  }) {
    out ??= newOutput();

    var blockCode = generateASTBlock(
      getter,
      indent: indent,
      withBrackets: false,
    );

    out.write(indent);
    out.write(generateASTType(getter.returnType));
    out.write(' get ');
    out.write(getter.name);
    out.write(' {\n');
    out.write(blockCode);
    out.write(indent);
    out.write('}\n\n');

    return out;
  }

  /// Generates a Dart `enum` declaration (simple or enhanced/rich).
  StringBuffer generateASTClassEnum(
    ASTClassEnum clazz, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    var hasMembers =
        clazz.fields.isNotEmpty ||
        clazz.constructors.isNotEmpty ||
        clazz.functions.isNotEmpty;

    out.write(indent);
    out.write('enum ');
    out.write(clazz.name);
    out.write(' {\n');

    var entries = clazz.entries;
    for (var i = 0; i < entries.length; ++i) {
      out.write('$indent  ');
      _generateEnumEntry(entries[i], out);
      if (i < entries.length - 1) out.write(',');
      out.write('\n');
    }

    if (hasMembers) {
      var indent2 = '$indent  ';
      // Enhanced/rich enum: `;` then the class members (fields, the `const`
      // constructor, methods) — reusing the class member generators.
      out.write('$indent  ;\n');

      for (var field in clazz.fields) {
        generateASTClassField(field, out: out, indent: indent2);
      }

      for (var constructor in clazz.constructors) {
        for (var c in constructor.functions) {
          // Dart enum constructors must be `const`.
          var cCode = generateASTClassConstructorDeclaration(
            c,
            indent: indent2,
          ).toString();
          out.write(indent2);
          out.write('const ');
          out.write(cCode.substring(indent2.length));
        }
      }

      for (var set in clazz.functions) {
        for (var f in set.functions) {
          if (f is ASTClassFunctionDeclaration) {
            generateASTClassFunctionDeclaration(f, out: out, indent: indent2);
          }
        }
      }
    }

    out.write('$indent}\n');

    return out;
  }

  /// Generates a single enum entry: a bare name, an explicit value (`Red = 1`),
  /// or rich constructor arguments (`earth(5.97, 6371)`).
  void _generateEnumEntry(ASTEnumEntry entry, StringBuffer out) {
    out.write(entry.name);

    var value = entry.value;
    var arguments = entry.arguments;

    if (value != null) {
      out.write(' = ');
      generateASTExpression(value, out: out, headIndented: false);
    } else if (arguments != null) {
      out.write('(');
      for (var i = 0; i < arguments.length; ++i) {
        if (i > 0) out.write(', ');
        generateASTExpression(arguments[i], out: out, headIndented: false);
      }
      out.write(')');
    }
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

    if (field.modifiers.isStatic) {
      out.write('static ');
    }

    if (field.finalValue) {
      out.write('final ');
    }

    out.write(typeCode);
    out.write(' ');
    out.write(field.name);

    if (field is ASTClassFieldWithInitialValue) {
      var initialValueCode = generateASTExpression(field.initialValue);
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
    if (c.name.isNotEmpty) {
      out.write('.');
      out.write(c.name);
    }
    _generateFunctionParamsAndBlock(c, blockCode, out, indent);

    return out;
  }

  @override
  StringBuffer generateASTClassFunctionDeclaration(
    ASTClassFunctionDeclaration f, {
    StringBuffer? out,
    String indent = '',
  }) {
    return _generateASTFunctionDeclarationImpl(f, out, indent);
  }

  @override
  StringBuffer generateASTFunctionDeclaration(
    ASTFunctionDeclaration f, {
    StringBuffer? out,
    String indent = '',
  }) {
    return _generateASTFunctionDeclarationImpl(f, out, indent);
  }

  @override
  StringBuffer generateASTTypeFunction(
    ASTTypeFunction type, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    var generics = type.generics;
    if (generics == null || generics.isEmpty) {
      out.write('Function');
      return out;
    }

    // generics[0] is the return type; the rest are parameter types:
    // `<returnType> Function(<paramType>, ...)`. A `dynamic` return type is
    // implicit in Dart, so it is omitted: `Function(<paramType>, ...)`.
    var returnType = generics.first;
    if (returnType is! ASTTypeDynamic) {
      out.write(generateASTType(returnType));
      out.write(' ');
    }
    out.write('Function(');
    var params = generics.skip(1).toList();
    for (var i = 0; i < params.length; ++i) {
      if (i > 0) out.write(', ');
      out.write(generateASTType(params[i]));
    }
    out.write(')');
    return out;
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
    generateFunctionParametersNames(f, out: out);

    // Dart anonymous functions: `(params) => expr` or `(params) { body }`
    // (no `=>` before a block body, unlike JavaScript).
    var single = singleReturnExpression(f);
    if (single != null) {
      out.write(' => ');
      generateASTExpression(single, out: out, headIndented: false);
    } else {
      out.write(' ');
      var blockCode = generateASTBlock(f, indent: indent, withBrackets: false);
      out.write('{\n');
      out.write(blockCode);
      out.write(indent);
      out.write('}');
    }

    return out;
  }

  StringBuffer _generateASTFunctionDeclarationImpl(
    ASTFunctionDeclaration f,
    StringBuffer? out,
    String indent,
  ) {
    out ??= newOutput();

    var typeCode = generateASTType(f.returnType);

    var blockCode = generateASTBlock(f, indent: indent, withBrackets: false);

    out.write(indent);

    if (f is ASTClassFunctionDeclaration) {
      if (f.modifiers.isStatic) {
        out.write('static ');
      }
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
    out.write(')');

    if (f is ASTFunctionDeclaration && f.modifiers.isAsync) {
      out.write(' async');
    }

    var blockStr = blockCode.toString();
    var emptyBlock = blockStr.trim().isEmpty;

    // Abstract/interface methods have no body.
    var isAbstractMethod =
        f is ASTFunctionDeclaration && f.modifiers.isAbstract;

    if (isAbstractMethod ||
        (emptyBlock && f is ASTClassConstructorDeclaration)) {
      out.write(';\n\n');
    } else {
      out.write(' {\n');
      out.write(blockCode);
      out.write(indent);
      out.write('}\n\n');
    }
  }

  @override
  StringBuffer generateASTParametersDeclaration(
    ASTParametersDeclaration parameters, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    var wrote = 0;

    var positionalParameters = parameters.positionalParameters;
    if (positionalParameters != null) {
      for (var i = 0; i < positionalParameters.length; ++i) {
        var p = positionalParameters[i];
        if (wrote > 0) out.write(', ');
        generateASTParameterDeclaration(p, out: out);
        ++wrote;
      }
    }

    var optionalParameters = parameters.optionalParameters;
    if (optionalParameters != null && optionalParameters.isNotEmpty) {
      if (wrote > 0) out.write(', ');
      out.write('[');
      for (var i = 0; i < optionalParameters.length; ++i) {
        var p = optionalParameters[i];
        if (i > 0) out.write(', ');
        generateASTParameterDeclaration(p, out: out);
      }
      out.write(']');
      ++wrote;
    }

    var namedParameters = parameters.namedParameters;
    if (namedParameters != null && namedParameters.isNotEmpty) {
      if (wrote > 0) out.write(', ');
      out.write('{');
      for (var i = 0; i < namedParameters.length; ++i) {
        var p = namedParameters[i];
        if (i > 0) out.write(', ');
        generateASTParameterDeclaration(p, out: out);
      }
      out.write('}');
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
  String resolveASTExpressionOperatorText(
    ASTExpressionOperator operator,
    ASTNumType aNumType,
    ASTNumType bNumType,
  ) {
    return getASTExpressionOperatorText(operator);
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

    var strRaw = value.value;

    var containsSingleQuote = strRaw.contains("'");
    var containsDoubleQuote = strRaw.contains('"');
    var containsBackslash = strRaw.contains('\\');

    var escapedBackslashCount = 0;

    var strEscaped = strRaw
        .replaceAllMapped('\\', (m) {
          escapedBackslashCount++;
          return r'\\';
        })
        .replaceAll('\t', r'\t')
        .replaceAll('\r', r'\r')
        .replaceAll('\n', r'\n')
        .replaceAll('\$', r'\$')
        .replaceAll('\b', r'\b');

    var noEscapedChar =
        (strEscaped.length - escapedBackslashCount) == strRaw.length;

    if (noEscapedChar && containsBackslash) {
      if (containsSingleQuote) {
        if (!containsDoubleQuote) {
          out.write('r"$strRaw"');
          return out;
        }
      } else if (containsDoubleQuote) {
        if (!containsSingleQuote) {
          out.write("r'$strRaw'");
          return out;
        }
      } else {
        out.write("r'$strRaw'");
        return out;
      }
    }

    if (containsSingleQuote) {
      if (containsDoubleQuote) strEscaped = strEscaped.replaceAll('"', r'\"');
      out.write('"$strEscaped"');
    } else {
      out.write("'$strEscaped'");
    }

    return out;
  }

  @override
  StringBuffer generateASTValueStringConcatenation(
    ASTValueStringConcatenation value, {
    StringBuffer? out,
    String indent = '',
  }) {
    var list = <dynamic>[];

    var prevString = '';
    for (var v in value.values) {
      if (v is ASTValueStringVariable) {
        var prevDoubleQuote = prevString.endsWith('"');
        var s2 = generateASTValueStringVariable(
          v,
          precededByString: false,
          prevDoubleQuote: prevDoubleQuote,
        );
        list.add(prevString = s2.toString());
      } else if (v is ASTValueStringExpression) {
        var prevDoubleQuote = prevString.endsWith('"');
        var s2 = generateASTValueStringExpression(
          v,
          prevDoubleQuote: prevDoubleQuote,
        );
        list.add(prevString = s2.toString());
      } else if (v is ASTValueStringConcatenation) {
        var s2 = generateASTValueStringConcatenation(v);
        list.add(prevString = s2.toString());
      } else if (v is ASTValueString) {
        var s2 = generateASTValueString(v);
        list.add(prevString = s2.toString());
      }
    }

    var generatedStrings = list.whereType<String>().toList();

    out ??= newOutput();

    void writeAllStrings(List list, {bool raw = false}) {
      var skip = raw ? 2 : 1;
      for (var e in list) {
        if (e is String) {
          out!.write(e.substring(skip, e.length - 1));
        } else {
          var s2 = e.toString();
          out!.write(s2.substring(skip, s2.length - 1));
        }
      }
    }

    if (generatedStrings.every((s) => s.startsWith("'''")) ||
        generatedStrings.every((s) => s.startsWith('"""'))) {
      // will generate concatenation at end...
    } else if (generatedStrings.every((s) => s.startsWith("'"))) {
      out.write("'");
      writeAllStrings(list);
      out.write("'");
      return out;
    } else if (generatedStrings.every((s) => s.startsWith("r'"))) {
      out.write("r'");
      writeAllStrings(list, raw: true);
      out.write("'");
      return out;
    } else if (generatedStrings.every((s) => s.startsWith('"'))) {
      out.write('"');
      writeAllStrings(list);
      out.write('"');
      return out;
    } else if (generatedStrings.every((s) => s.startsWith('r"'))) {
      out.write('r"');
      writeAllStrings(list, raw: true);
      out.write('"');
      return out;
    }

    var strings = list.map((e) => e is String ? e : e.toString()).toList();

    const stringOpenersMultiline = ["'''", '"""', "r'''", 'r"""'];
    const stringOpeners = ["'", '"', "r'", 'r"'];

    var stringsBlocks = strings.splitBetween((a, b) {
      for (var o in stringOpenersMultiline) {
        // a is multiline `o`:
        if (a.startsWith(o)) {
          // split if b is NOT multiline `o`:
          return !b.startsWith(o);
        }
        // a is NOT multiline `o` AND b IS multiline `o`, split:
        else if (b.startsWith(o)) {
          return true;
        }
      }

      for (var o in stringOpeners) {
        // a is string `o`:
        if (a.startsWith(o)) {
          // split if b is NOT string `o`:
          return !b.startsWith(o);
        }
        // a is NOT string `o` AND b IS string `o`, split:
        else if (b.startsWith(o)) {
          return true;
        }
      }

      return false;
    }).toList();

    var stringsMerged = stringsBlocks
        .map(
          (l) => l.reduce((a, b) {
            if (a.startsWith('"""') || a.startsWith("'''")) {
              return a.substring(0, a.length - 3) + b.substring(3);
            } else if (a.startsWith('r"""') || a.startsWith("r'''")) {
              return a.substring(0, a.length - 3) + b.substring(4);
            } else if (a.startsWith('"') || a.startsWith("'")) {
              return a.substring(0, a.length - 1) + b.substring(1);
            } else if (a.startsWith('r"') || a.startsWith("r'")) {
              return a.substring(0, a.length - 1) + b.substring(2);
            } else {
              return a + b;
            }
          }),
        )
        .toList();

    for (var i = 0; i < stringsMerged.length; ++i) {
      var e = stringsMerged[i];

      var multiline =
          e.startsWith("'''") ||
          e.startsWith('"""') ||
          e.startsWith("r'''") ||
          e.startsWith('r"""');

      if (multiline && i > 0) {
        out.write('\n');
      }

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
    bool prevDoubleQuote = false,
  }) {
    out ??= newOutput();

    if (prevDoubleQuote) {
      out.write(r'"$');
      out.write(value.variable.name);
      out.write('"');
    } else {
      out.write(r"'$");
      out.write(value.variable.name);
      out.write("'");
    }

    return out;
  }

  @override
  StringBuffer generateASTValueStringExpression(
    ASTValueStringExpression value, {
    StringBuffer? out,
    String indent = '',
    bool prevDoubleQuote = false,
  }) {
    out ??= newOutput();

    var exp = generateASTExpression(value.expression).toString();

    if (exp.contains("'") && prevDoubleQuote) {
      out.write('"');
      out.write(r'${');
      out.write(exp);
      out.write(r'}');
      out.write('"');
    } else {
      out.write("'");
      out.write(r'${');
      out.write(exp);
      out.write(r'}');
      out.write("'");
    }

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

  @override
  StringBuffer generateASTExpressionOperation(
    ASTExpressionOperation expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    final expression1 = expression.expression1;
    final expression2 = expression.expression2;
    final operator = expression.operator;

    var groupComplexExpressions = true;

    // Merge into string template:
    if (operator == ASTExpressionOperator.add) {
      if (expression2.isVariableAccess) {
        var s1 = generateASTExpression(expression1).toString();
        var s2 = generateASTExpression(expression2).toString();

        if (expression1.isLiteralString ||
            expression1.hasDescendantLiteralString) {
          groupComplexExpressions = false;
        }

        if ((_isSingleQuoteString(s1) || _isDoubleQuoteString(s1)) &&
            _isVariable(s2)) {
          var s1End = s1.length - 1;
          var sMerge = '${s1.substring(0, s1End)}\$$s2${s1.substring(s1End)}';
          out.write(sMerge);
          return out;
        }
      } else if (expression2.isLiteralString) {
        groupComplexExpressions = false;

        var s1 = generateASTExpression(expression1).toString();
        var s2 = generateASTExpression(expression2).toString();

        var s1SingleQuote = _isSingleQuoteString(s1);
        var s1DoubleQuote = _isDoubleQuoteString(s1);

        var s2SingleQuote = _isSingleQuoteString(s2);
        var s2DoubleQuote = _isDoubleQuoteString(s2);

        if ((s1SingleQuote && s2SingleQuote) ||
            (s1DoubleQuote && s2DoubleQuote)) {
          var merged = _mergeQuotedStrings(s1, s2);
          out.write(merged);
          return out;
        } else if ((s1SingleQuote || s1DoubleQuote) &&
            (s2SingleQuote || s2DoubleQuote)) {
          final merged = _tryMergeQuotedStrings(s1, s2);
          if (merged != null) {
            out.write(merged);
            return out;
          }
        }

        if (_isVariable(s1) && (s2SingleQuote || s2DoubleQuote)) {
          var sMerge = '${s2.substring(0, 1)}\$$s1${s2.substring(1)}';
          out.write(sMerge);
          return out;
        }
      } else if (expression1.isLiteralString) {
        groupComplexExpressions = false;
      } else if (expression1.hasDescendantLiteralString ||
          expression2.hasDescendantLiteralString) {
        groupComplexExpressions = false;
      }
    }

    var op = resolveASTExpressionOperatorText(
      operator,
      expression1.literalNumType,
      expression2.literalNumType,
    );

    var exp1 = generateASTExpression(expression1);
    var exp2 = generateASTExpression(expression2);

    var group1 = groupComplexExpressions && expression1.isComplex;
    var group2 = groupComplexExpressions && expression2.isComplex;

    if (group1) out.write('(');
    out.write(exp1);
    if (group1) out.write(')');

    out.write(' ');
    out.write(op);
    out.write(' ');

    if (group2) out.write('(');
    out.write(exp2);
    if (group2) out.write(')');

    return out;
  }

  static final RegExp _regexpWORD = RegExp(r'^[a-zA-Z]\w*$');

  static bool _isVariable(String s) {
    return _regexpWORD.hasMatch(s);
  }

  static bool _isDoubleQuoteString(String s) => _isQuotedString(s, '"');

  static bool _isSingleQuoteString(String s) => _isQuotedString(s, "'");

  static bool _isQuotedString(String s, String quote) {
    if (quote != '"' && quote != "'") return false;

    final triple = quote * 3;

    // Basic shape: "..." or '...'
    if (!(s.startsWith(quote) &&
        !s.startsWith(triple) &&
        s.endsWith(quote) &&
        !s.endsWith(triple))) {
      return false;
    }

    // Scan for unescaped inner quotes
    for (int i = 1; i < s.length - 1; i++) {
      if (s[i] == quote) {
        int backslashCount = 0;
        int j = i - 1;

        while (j >= 0 && s[j] == r'\') {
          backslashCount++;
          j--;
        }

        // Even number of backslashes → not escaped
        if (backslashCount % 2 == 0) {
          return false;
        }
      }
    }

    return true;
  }

  static bool _canConvertQuote(String s, String fromQuote, String toQuote) {
    if (!_isQuotedString(s, fromQuote)) return false;

    // Check if there is any UNESCAPED target quote inside
    for (int i = 1; i < s.length - 1; i++) {
      if (s[i] == toQuote) {
        int backslashCount = 0;
        int j = i - 1;

        while (j >= 0 && s[j] == r'\') {
          backslashCount++;
          j--;
        }

        // Even → not escaped → would need escaping → reject
        if (backslashCount % 2 == 0) {
          return false;
        }
      }
    }

    return true;
  }

  static String _convertQuote(String s, String fromQuote, String toQuote) {
    final inner = s.substring(1, s.length - 1);

    // Remove escapes from the original quote type
    final unescaped = inner.replaceAll('\\$fromQuote', fromQuote);

    return '$toQuote$unescaped$toQuote';
  }

  String _mergeQuotedStrings(String a, String b) =>
      a.substring(0, a.length - 1) + b.substring(1);

  String? _tryMergeQuotedStrings(String s1, String s2) {
    final q1 = s1[0];
    final q2 = s2[0];

    // only handle simple quoted strings
    if ((q1 != '"' && q1 != "'") || (q2 != '"' && q2 != "'")) {
      return null;
    }

    // same quote → direct merge
    if (q1 == q2) {
      return _mergeQuotedStrings(s1, s2);
    }

    // try converting s2 → q1
    if (_canConvertQuote(s2, q2, q1)) {
      final s2c = _convertQuote(s2, q2, q1);
      return _mergeQuotedStrings(s1, s2c);
    }

    // try converting s1 → q2
    if (_canConvertQuote(s1, q1, q2)) {
      final s1c = _convertQuote(s1, q1, q2);
      return _mergeQuotedStrings(s1c, s2);
    }

    return null;
  }
}
