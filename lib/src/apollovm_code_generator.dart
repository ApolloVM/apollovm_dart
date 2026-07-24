// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'apollovm_code_storage.dart';
import 'apollovm_generator.dart';
import 'apollovm_parser.dart';
import 'ast/apollovm_ast_base.dart';
import 'ast/apollovm_ast_expression.dart';
import 'ast/apollovm_ast_statement.dart';
import 'ast/apollovm_ast_toplevel.dart';
import 'ast/apollovm_ast_type.dart';
import 'ast/apollovm_ast_value.dart';
import 'ast/apollovm_ast_variable.dart';

/// Base class for code generators.
///
/// An [ASTRoot] loaded in [ApolloVM] can be converted to a code in a specific language.
abstract class ApolloCodeGenerator
    extends ApolloGenerator<StringBuffer, ApolloSourceCodeStorage, String> {
  ApolloCodeGenerator(super.language, super.codeStorage);

  @override
  String toStorageData(StringBuffer out) => out.toString();

  @override
  StringBuffer newOutput() => StringBuffer();

  /// Emits any [ASTNode]. Declared here rather than on [ApolloGenerator]:
  /// only a source-code generator can render an arbitrary node standalone.
  StringBuffer generateASTNode(
    ASTNode node, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    if (node is ASTValue) {
      return generateASTValue(
        node,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (node is ASTExpression) {
      return generateASTExpression(
        node,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (node is ASTRoot) {
      return generateASTRoot(node, out: out, indent: indent);
    } else if (node is ASTClassNormal) {
      return generateASTClass(node, out: out, indent: indent);
    } else if (node is ASTExtension) {
      return generateASTExtension(node, out: out, indent: indent);
    } else if (node is ASTSingleLineStatementBlock) {
      return generateASTSingleLineStatementBlock(
        node,
        out: out,
        indent: indent,
      );
    } else if (node is ASTBlock) {
      return generateASTBlock(node, out: out, indent: indent);
    } else if (node is ASTStatement) {
      return generateASTStatement(
        node,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (node is ASTClassFunctionDeclaration) {
      return generateASTClassFunctionDeclaration(
        node,
        out: out,
        indent: indent,
      );
    } else if (node is ASTFunctionDeclaration) {
      return generateASTFunctionDeclaration(node, out: out, indent: indent);
    }

    throw UnsupportedError("Can't handle ASTNode: $node");
  }

  @override
  StringBuffer generateASTRoot(
    ASTRoot root, {
    StringBuffer? out,
    String indent = '',
    bool withBrackets = true,
  }) {
    out ??= newOutput();

    var imports = root.imports;
    if (imports.isNotEmpty) {
      for (var import in imports) {
        generateASTStatementImport(import, out: out);
      }
      out.write('\n');
    }

    var exports = root.exports;
    if (exports.isNotEmpty) {
      for (var export in exports) {
        generateASTStatementExport(export, out: out);
      }
      out.write('\n');
    }

    var typeAliases = root.typeAliases;
    if (typeAliases.isNotEmpty) {
      for (var typeAlias in typeAliases) {
        generateASTTypeAlias(typeAlias, out: out);
      }
      out.write('\n');
    }

    generateASTBlock(root, out: out, withBrackets: false);

    for (var clazz in root.classes) {
      generateASTClass(clazz, out: out);
    }

    for (var extension in root.extensions) {
      generateASTExtension(extension, out: out);
    }

    return out;
  }

  /// Emits an extension declaration.
  ///
  /// Only Dart, Kotlin and C# have a native extension construct; every other
  /// language rejects it rather than emit something that does not mean the same
  /// thing (a monkey-patched prototype or a free-standing static helper would
  /// silently change the program's semantics at the call sites).
  StringBuffer generateASTExtension(
    ASTExtension extension, {
    StringBuffer? out,
    String indent = '',
  }) {
    throw UnsupportedSyntaxError(
      "Language '$language' has no extension declaration: $extension",
    );
  }

  /// Emits an instance getter (`int get twice => …`). Default: unsupported.
  ///
  /// [receiver] is set only when the getter belongs to an extension *and* the
  /// target language qualifies the declaration by the extended type (Kotlin:
  /// `val Int.twice: Int get()`).
  StringBuffer generateASTClassGetterDeclaration(
    ASTClassGetterDeclaration getter, {
    StringBuffer? out,
    String indent = '',
    String? receiver,
  }) {
    throw UnsupportedSyntaxError(
      "Language '$language' has no getter declaration: ${getter.name}",
    );
  }

  @override
  StringBuffer generateASTBlock(
    ASTBlock block, {
    StringBuffer? out,
    String indent = '',
    bool withBrackets = true,
    bool withBlankHeadLine = false,
  }) {
    if (block is ASTSingleLineStatementBlock) {
      return generateASTSingleLineStatementBlock(
        block,
        out: out,
        indent: indent,
      );
    }

    out ??= newOutput();

    var indent2 = '$indent  ';

    if (withBrackets) out.write('$indent{\n');

    if (withBlankHeadLine) out.write('\n');

    if (block is ASTClassNormal) {
      for (var field in block.fields) {
        generateASTClassField(field, out: out, indent: indent2);
      }

      if (block.fields.isNotEmpty) {
        out.write('\n');
      }

      for (var constructor in block.constructors) {
        for (var c in constructor.functions) {
          generateASTClassConstructorDeclaration(c, out: out, indent: indent2);
        }
      }
    }

    // Local function declarations are kept as statements (and emitted in the
    // statements loop below). Executing the block also registers them in
    // `block.functions` for resolution, so skip those here to avoid emitting
    // them twice.
    var statementFunctions = block.statements
        .whereType<ASTStatementFunctionDeclaration>()
        .map((s) => s.functionDeclaration)
        .toList();

    for (var set in block.functions) {
      for (var f in set.functions) {
        if (statementFunctions.any((s) => identical(s, f))) continue;
        if (f is ASTClassFunctionDeclaration) {
          generateASTClassFunctionDeclaration(f, out: out, indent: indent2);
        } else {
          generateASTFunctionDeclaration(f, out: out, indent: indent2);
        }
      }
    }

    for (var g in block.getter) {
      if (g is ASTClassGetterDeclaration) {
        generateASTClassGetterDeclaration(g, out: out, indent: indent2);
      }
    }

    for (var stm in block.statements) {
      generateASTStatement(stm, out: out, indent: indent2);
      out.write('\n');
    }

    if (withBrackets) out.write('$indent}\n');

    return out;
  }

  @override
  StringBuffer generateASTSingleLineStatementBlock(
    ASTSingleLineStatementBlock block, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    var stm = block.statements.single;
    generateASTStatement(stm, out: out, indent: indent);
    out.write('\n');

    return out;
  }

  @override
  StringBuffer generateASTStatementImport(
    ASTStatementImport import, {
    StringBuffer? out,
    String indent = '',
  });

  /// Emits an `export`/re-export directive. Default: no-op (languages without
  /// an export concept produce no exports, so nothing is emitted).
  StringBuffer generateASTStatementExport(
    ASTStatementExport export, {
    StringBuffer? out,
    String indent = '',
  }) => out ??= newOutput();

  /// Emits a top-level type alias / `typedef`. Default: no-op.
  StringBuffer generateASTTypeAlias(
    ASTTypeAlias typeAlias, {
    StringBuffer? out,
    String indent = '',
  }) => out ??= newOutput();

  @override
  StringBuffer generateASTClass(
    ASTClassNormal clazz, {
    StringBuffer? out,
    String indent = '',
  });

  @override
  StringBuffer generateASTClassField(
    ASTClassField field, {
    StringBuffer? out,
    String indent = '',
  });

  @override
  StringBuffer generateASTClassConstructorDeclaration(
    ASTClassConstructorDeclaration constructor, {
    StringBuffer? out,
    String indent = '',
  });

  @override
  StringBuffer generateASTClassFunctionDeclaration(
    ASTClassFunctionDeclaration f, {
    StringBuffer? out,
    String indent = '',
  });

  @override
  StringBuffer generateASTFunctionDeclaration(
    ASTFunctionDeclaration f, {
    StringBuffer? out,
    String indent = '',
  });

  @override
  StringBuffer generateASTParametersDeclaration(
    ASTParametersDeclaration parameters, {
    StringBuffer? out,
    String indent = '',
  });

  @override
  StringBuffer generateASTFunctionParameterDeclaration(
    ASTFunctionParameterDeclaration parameter, {
    StringBuffer? out,
    String indent = '',
  });

  @override
  StringBuffer generateASTParameterDeclaration(
    ASTParameterDeclaration parameter, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    if (parameter is ASTConstructorParameterDeclaration &&
        parameter.thisParameter) {
      out.write('this.');
    } else {
      var typeStr = generateASTType(parameter.type);
      out.write(typeStr);
      out.write(' ');
    }

    out.write(parameter.name);

    appendParameterDefaultValue(parameter, out, indent);

    return out;
  }

  /// The separator emitted between a parameter and its default value in a
  /// declaration (e.g. ` = ` in Dart/Kotlin/C#/Java, `=` in Python).
  String get parameterDefaultValueSeparator => ' = ';

  /// Appends ` = <default>` to [out] when [parameter] has a default value.
  void appendParameterDefaultValue(
    ASTParameterDeclaration parameter,
    StringBuffer out,
    String indent,
  ) {
    var defaultValue = parameter.defaultValue;
    if (defaultValue == null) return;

    out.write(parameterDefaultValueSeparator);
    generateASTExpression(
      defaultValue,
      out: out,
      indent: indent,
      headIndented: false,
    );
  }

  /// Emits a type, dispatching on its array rank.
  /// Whether this target renders a nullable type with a trailing `?` suffix
  /// (Dart, Kotlin, TypeScript). Targets without a nullable-type syntax
  /// (Java, Go, …) leave this `false` and drop the suffix (best-effort).
  bool get supportsNullableTypeSuffix => false;

  /// Whether this target has native null-aware operators (`?.`, `?[`) that can
  /// be emitted directly (Dart, Kotlin, TypeScript). Targets without them leave
  /// this `false` and emit the plain `.`/`[` form (best-effort).
  bool get supportsNullAwareOperators => false;

  StringBuffer generateASTType(
    ASTType type, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    if (type is ASTTypeArray) {
      generateASTTypeArray(type, out: out, indent: indent);
    } else if (type is ASTTypeArray2D) {
      generateASTTypeArray2D(type, out: out, indent: indent);
    } else if (type is ASTTypeArray3D) {
      generateASTTypeArray3D(type, out: out, indent: indent);
    } else if (type is ASTTypeFunction) {
      generateASTTypeFunction(type, out: out, indent: indent);
    } else {
      generateASTTypeDefault(type, out: out, indent: indent);
    }

    // Nullable `?` suffix (`String?`, `List<int>?`, `void Function()?`) for
    // targets that support it.
    if (type.nullable && supportsNullableTypeSuffix) {
      out.write('?');
    }

    return out;
  }

  /// Renders a function type. The default drops the signature generics and
  /// emits a bare `Function` (valid as a type name in most targets); languages
  /// with a dedicated function-type syntax (e.g. Dart) override this.
  StringBuffer generateASTTypeFunction(
    ASTTypeFunction type, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();
    out.write('Function');
    return out;
  }

  @override
  StringBuffer generateASTTypeArray(
    ASTTypeArray type, {
    StringBuffer? out,
    String indent = '',
  });

  @override
  StringBuffer generateASTTypeArray2D(
    ASTTypeArray2D type, {
    StringBuffer? out,
    String indent = '',
  });

  @override
  StringBuffer generateASTTypeArray3D(
    ASTTypeArray3D type, {
    StringBuffer? out,
    String indent = '',
  });

  @override
  String normalizeTypeName(String typeName, [String? callingFunction]) =>
      typeName;

  /// Rewrites a member identifier (a field, getter, setter or method name)
  /// written after a `.` so it is legal in the target language.
  ///
  /// Default: unchanged. A language whose reserved words may not be used as
  /// identifiers (Go) overrides this to escape them, and must apply the same
  /// rewrite where it emits the matching declaration.
  String normalizeIdentifier(String name) => name;

  @override
  String normalizeTypeFunction(String typeName, String functionName) =>
      functionName;

  @override
  StringBuffer generateASTTypeDefault(
    ASTType type, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    var typeName = normalizeTypeName(type.name);

    out.write(typeName);

    if (type.generics != null) {
      var generics = type.generics!;

      out.write('<');
      for (var i = 0; i < generics.length; ++i) {
        var g = generics[i];
        if (i > 0) out.write(', ');
        out.write(generateASTType(g));
      }
      out.write('>');
    }

    return out;
  }

  @override
  StringBuffer generateASTStatement(
    ASTStatement statement, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    if (statement is ASTStatementExpression) {
      return generateASTStatementExpression(
        statement,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (statement is ASTStatementVariableDeclaration) {
      return generateASTStatementVariableDeclaration(
        statement,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (statement is ASTStatementFunctionDeclaration) {
      return generateASTStatementFunctionDeclaration(
        statement,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (statement is ASTBranch) {
      return generateASTBranch(
        statement,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (statement is ASTStatementForLoop) {
      return generateASTStatementForLoop(
        statement,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (statement is ASTStatementForEach) {
      return generateASTStatementForEach(
        statement,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (statement is ASTStatementDoWhileLoop) {
      return generateASTStatementDoWhileLoop(
        statement,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (statement is ASTStatementWhileLoop) {
      return generateASTStatementWhileLoop(
        statement,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (statement is ASTStatementSwitch) {
      return generateASTStatementSwitch(
        statement,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (statement is ASTStatementBreak) {
      return generateASTStatementBreak(
        statement,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (statement is ASTStatementContinue) {
      return generateASTStatementContinue(
        statement,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (statement is ASTStatementBlock) {
      return generateASTStatementBlock(
        statement,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (statement is ASTStatementReturnNull) {
      return generateASTStatementReturnNull(
        statement,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (statement is ASTStatementReturnValue) {
      return generateASTStatementReturnValue(
        statement,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (statement is ASTStatementReturnVariable) {
      return generateASTStatementReturnVariable(
        statement,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (statement is ASTStatementReturnWithExpression) {
      return generateASTStatementReturnWithExpression(
        statement,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (statement is ASTStatementReturn) {
      return generateASTStatementReturn(
        statement,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (statement is ASTStatementThrow) {
      return generateASTStatementThrow(
        statement,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (statement is ASTStatementTryCatch) {
      return generateASTStatementTryCatch(
        statement,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    }

    throw UnsupportedError("Can't handle statement: $statement");
  }

  @override
  StringBuffer generateASTBranch(
    ASTBranch branch, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    if (branch is ASTBranchIfBlock) {
      return generateASTBranchIfBlock(
        branch,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (branch is ASTBranchIfElseBlock) {
      return generateASTBranchIfElseBlock(
        branch,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (branch is ASTBranchIfElseIfsElseBlock) {
      return generateASTBranchIfElseIfsElseBlock(
        branch,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    }

    throw UnsupportedError("Can't handle branch: $branch");
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

    out.write('for (');
    generateASTStatement(
      forLoop.initStatement,
      out: out,
      indent: indent,
      headIndented: false,
    );
    out.write(' ');
    generateASTExpression(
      forLoop.conditionExpression,
      out: out,
      indent: indent,
      headIndented: false,
    );
    out.write(' ; ');
    generateASTExpression(
      forLoop.continueExpression,
      out: out,
      indent: indent,
      headIndented: false,
    );

    out.write(') {\n');

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

    out.write('for (');

    // assuming you used `var` (you can adjust if you support final/type)
    out.write('var ');
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
  StringBuffer generateASTStatementWhileLoop(
    ASTStatementWhileLoop whileLoop, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    out.write('while( ');

    generateASTExpression(
      whileLoop.conditionExpression,
      out: out,
      indent: indent,
      headIndented: false,
    );

    out.write(' ) {\n');

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

  StringBuffer generateASTStatementDoWhileLoop(
    ASTStatementDoWhileLoop doWhileLoop, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    out.write('do {\n');

    var blockCode = generateASTBlock(
      doWhileLoop.loopBlock,
      indent: indent,
      withBrackets: false,
    );

    out.write(blockCode);
    out.write(indent);
    out.write('} while (');

    generateASTExpression(
      doWhileLoop.conditionExpression,
      out: out,
      indent: indent,
      headIndented: false,
    );

    out.write(');');

    return out;
  }

  StringBuffer generateASTStatementSwitch(
    ASTStatementSwitch statement, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    var indent2 = '$indent  ';

    out.write('switch (');
    generateASTExpression(
      statement.expression,
      out: out,
      indent: indent,
      headIndented: false,
    );
    out.write(') {\n');

    for (var c in statement.cases) {
      out.write(indent2);
      if (c.isDefault) {
        out.write('default: {\n');
      } else {
        out.write('case ');
        generateASTExpression(c.value!, out: out, headIndented: false);
        out.write(': {\n');
      }

      out.write(
        generateASTBlock(c.block, indent: indent2, withBrackets: false),
      );
      out.write(indent2);
      out.write('}\n');
    }

    out.write(indent);
    out.write('}');

    return out;
  }

  StringBuffer generateASTStatementBreak(
    ASTStatementBreak statement, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    out.write('break;');

    return out;
  }

  StringBuffer generateASTStatementContinue(
    ASTStatementContinue statement, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    out.write('continue;');

    return out;
  }

  StringBuffer generateASTStatementThrow(
    ASTStatementThrow statement, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    out.write('throw ');
    generateASTExpression(
      statement.expression,
      out: out,
      indent: indent,
      headIndented: false,
    );
    out.write(';');

    return out;
  }

  StringBuffer generateASTStatementTryCatch(
    ASTStatementTryCatch tryCatch, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    out.write('try {\n');
    out.write(
      generateASTBlock(tryCatch.tryBlock, indent: indent, withBrackets: false),
    );
    out.write(indent);
    out.write('}');

    for (var catchClause in tryCatch.catches) {
      out.write(' ');
      out.write(generateASTCatchClauseHeader(catchClause));
      out.write(' {\n');
      out.write(
        generateASTBlock(
          catchClause.block,
          indent: indent,
          withBrackets: false,
        ),
      );
      out.write(indent);
      out.write('}');
    }

    var finallyBlock = tryCatch.finallyBlock;
    if (finallyBlock != null) {
      out.write(' finally {\n');
      out.write(
        generateASTBlock(finallyBlock, indent: indent, withBrackets: false),
      );
      out.write(indent);
      out.write('}');
    }

    return out;
  }

  /// Renders the catch-clause header (everything before the `{` block), e.g.
  /// `catch (e)` or `on T catch (e)`. The base emits an untyped `catch (e)`
  /// (used by JavaScript/TypeScript); language generators override this to
  /// emit their idiomatic, typed form.
  String generateASTCatchClauseHeader(ASTCatchClause catchClause) {
    var name = catchClause.variableName ?? 'e';
    return 'catch ($name)';
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

    out.write('if (');
    generateASTExpression(
      branch.condition,
      out: out,
      indent: indent,
      headIndented: false,
    );
    out.write(') ');

    final block = branch.block;

    if (block is ASTSingleLineStatementBlock) {
      generateASTSingleLineStatementBlock(block, out: out);
    } else {
      out.write('{\n');
      generateASTBlock(
        block,
        out: out,
        indent: '$indent  ',
        withBrackets: false,
      );
      out.write(indent);
      out.write('}\n');
    }

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

    out.write('if (');
    generateASTExpression(
      branch.condition,
      out: out,
      indent: indent,
      headIndented: false,
    );
    out.write(') {\n');
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

    out.write('if (');
    generateASTExpression(
      branch.condition,
      out: out,
      indent: indent,
      headIndented: false,
    );
    out.write(') {\n');
    generateASTBlock(
      branch.blockIf,
      out: out,
      indent: '$indent  ',
      withBrackets: false,
    );

    for (var branchElseIf in branch.blocksElseIf) {
      out.write(indent);
      out.write('} else if (');
      generateASTExpression(
        branchElseIf.condition,
        out: out,
        indent: indent,
        headIndented: false,
      );
      out.write(') {\n');
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
  StringBuffer generateASTStatementExpression(
    ASTStatementExpression statement, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);
    generateASTExpression(statement.expression, out: out);
    out.write(';');
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

    generateASTType(statement.type, out: out);

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
  StringBuffer generateASTStatementFunctionDeclaration(
    ASTStatementFunctionDeclaration statement, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    // `generateASTFunctionDeclaration` writes the leading indent itself, so
    // don't write it here too (that produced a doubled indent for nested
    // function declarations).
    return generateASTFunctionDeclaration(
      statement.functionDeclaration,
      out: out,
      indent: headIndented ? indent : '',
    );
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

    // The assignment target, captured so `??=` can repeat it when the target
    // language has no such operator (`t ??= v` -> `t = t ?? v`).
    var target = generateASTVariable(
      expression.variable,
      indent: indent,
      headIndented: false,
    ).toString();

    out.write(target);

    var value = generateASTExpression(
      expression.expression,
      indent: '$indent  ',
      headIndented: false,
    ).toString();

    _writeAssignment(out, expression.operator, target, value);

    return out;
  }

  /// Resolves the assignment operator text for the target language.
  ///
  /// Defaults to the shared spelling; a target overrides this where its own
  /// differs (e.g. Python writes integer division as `//=`, not `~/=`).
  String resolveASTAssignmentOperatorText(ASTAssignmentOperator operator) =>
      getASTAssignmentOperatorText(operator);

  /// Writes the operator and right-hand side of an assignment whose left-hand
  /// side [target] has already been written to [out].
  ///
  /// A `??=` against a target without that operator is lowered to
  /// `= target ?? value`, so only [renderNullCoalesce] has to be defined per
  /// language.
  void _writeAssignment(
    StringBuffer out,
    ASTAssignmentOperator operator,
    String target,
    String value,
  ) {
    if (operator == ASTAssignmentOperator.nullCoalesce &&
        !supportsNullCoalesceAssignment) {
      out.write(' = ');
      out.write(renderNullCoalesce(target, value));
      return;
    }

    out.write(' ');
    out.write(resolveASTAssignmentOperatorText(operator));
    out.write(' ');
    out.write(value);
  }

  @override
  StringBuffer generateASTExpressionVariableEntryAssignment(
    ASTExpressionVariableEntryAssignment expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    // The indexed write target, captured so `??=` can repeat it.
    var target = generateASTVariable(
      expression.variable,
      indent: indent,
      headIndented: false,
    );

    target.write('[');
    generateASTExpression(
      expression.keyExpression,
      out: target,
      indent: '$indent  ',
      headIndented: false,
    );
    target.write(']');
    // Chained keys for a nested write target (`m[0][1] = v`).
    for (var extra in expression.extraKeys) {
      target.write('[');
      generateASTExpression(
        extra,
        out: target,
        indent: '$indent  ',
        headIndented: false,
      );
      target.write(']');
    }

    var targetStr = target.toString();
    out.write(targetStr);

    var value = generateASTExpression(
      expression.expression,
      indent: '$indent  ',
      headIndented: false,
    ).toString();

    _writeAssignment(out, expression.operator, targetStr, value);

    return out;
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

    var op = getASTAssignmentDirectOperatorText(expression.operator);

    if (expression.preOperation) {
      out.write(op);
    }

    generateASTVariable(
      expression.variable,
      out: out,
      indent: indent,
      headIndented: headIndented,
    );

    if (!expression.preOperation) {
      out.write(op);
    }

    return out;
  }

  @override
  StringBuffer generateASTStatementBlock(
    ASTStatementBlock statement, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    return generateASTBlock(statement.block, out: out, indent: indent);
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
    out.write('return;');
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
    out.write('return null;');
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
    out.write(';');
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
    out.write(';');
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
    out.write(';');
    return out;
  }

  @override
  StringBuffer generateASTExpression(
    ASTExpression expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    if (expression is ASTExpressionNullValue) {
      return generateASTExpressionNullValue(
        expression,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (expression is ASTExpressionVariableAccess) {
      return generateASTExpressionVariableAccess(
        expression,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (expression is ASTExpressionVariableAssignment) {
      return generateASTExpressionVariableAssignment(
        expression,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (expression is ASTExpressionVariableEntryAssignment) {
      return generateASTExpressionVariableEntryAssignment(
        expression,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (expression is ASTExpressionVariableDirectOperation) {
      return generateASTExpressionVariableDirectOperation(
        expression,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (expression is ASTExpressionVariableEntryAccess) {
      return generateASTExpressionVariableEntryAccess(
        expression,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (expression is ASTExpressionLiteral) {
      return generateASTExpressionLiteral(
        expression,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (expression is ASTExpressionListLiteral) {
      return generateASTExpressionListLiteral(
        expression,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (expression is ASTExpressionMapLiteral) {
      return generateASTExpressionMapLiteral(
        expression,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (expression is ASTExpressionNullAssertion) {
      return generateASTExpressionNullAssertion(
        expression,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (expression is ASTExpressionCascade) {
      return generateASTExpressionCascade(
        expression,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (expression is ASTExpressionNegation) {
      return generateASTExpressionNegation(
        expression,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (expression is ASTExpressionNegative) {
      return generateASTExpressionNegative(
        expression,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (expression is ASTExpressionBitwiseNot) {
      return generateASTExpressionBitwiseNot(
        expression,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (expression is ASTExpressionAwait) {
      return generateASTExpressionAwait(
        expression,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (expression is ASTExpressionLocalFunctionInvocation) {
      return generateASTExpressionLocalFunctionInvocation(
        expression,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (expression is ASTExpressionObjectFunctionInvocation) {
      return generateASTExpressionFunctionInvocation(
        expression,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (expression is ASTExpressionObjectEntryFunctionInvocation) {
      return generateASTExpressionObjectEntryFunctionInvocation(
        expression,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (expression is ASTExpressionGroupFunctionInvocation) {
      return generateASTExpressionGroupFunctionInvocation(
        expression,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (expression is ASTExpressionLocalGetterAccess) {
      return generateASTExpressionLocalGetterAccess(
        expression,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (expression is ASTExpressionObjectGetterAccess) {
      return generateASTExpressionObjectGetterAccess(
        expression,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (expression is ASTExpressionObjectSetterAssignment) {
      return generateASTExpressionObjectSetterAssignment(
        expression,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (expression is ASTExpressionOperation) {
      return generateASTExpressionOperation(
        expression,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (expression is ASTExpressionConditional) {
      return generateASTExpressionConditional(
        expression,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (expression is ASTExpressionLiteralFunction) {
      return generateASTExpressionLiteralFunction(
        expression,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    }

    throw UnsupportedError("Can't generate expression: $expression");
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

    // `a ?? b` has no operator form in several targets, so it goes through a
    // dedicated hook that can desugar it into a conditional expression.
    if (operator == ASTExpressionOperator.nullCoalesce) {
      return generateASTExpressionNullCoalesce(
        expression1,
        expression2,
        out: out,
        indent: indent,
      );
    }

    var groupComplexExpressions = true;

    if (operator == ASTExpressionOperator.add) {
      if (expression1.isVariableAccess) {
        if (expression2.hasDescendantLiteralString) {
          groupComplexExpressions = false;
        }
      } else if (expression1.isLiteralString) {
        groupComplexExpressions = false;
      } else if (expression2.isLiteralString) {
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

    var exp1 = generateASTExpression(
      expression1,
      indent: '$indent  ',
      headIndented: false,
    );

    var exp2 = generateASTExpression(
      expression2,
      indent: '$indent  ',
      headIndented: false,
    );

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

  /// Renders the null-coalescing expression `a ?? b` from already-generated
  /// operand texts.
  ///
  /// The default emits the operator form, resolved through
  /// [resolveASTExpressionOperatorText] so a target with its own spelling (e.g.
  /// Kotlin's Elvis `?:`) is honoured. Targets with no null-coalescing operator
  /// (Java, Lua, Python) override this to desugar into a conditional; a target
  /// that cannot express it at all (Go) throws an [UnsupportedSyntaxError].
  ///
  /// A desugaring override repeats [a] in its output, so it is only safe for
  /// operands that can be evaluated twice — which is what `??` / `??=` targets
  /// are in practice (variables, fields and index reads).
  String renderNullCoalesce(String a, String b) {
    var op = resolveASTExpressionOperatorText(
      ASTExpressionOperator.nullCoalesce,
      ASTNumType.nan,
      ASTNumType.nan,
    );
    return '$a $op $b';
  }

  /// Whether the target language has a null-coalescing *assignment* operator
  /// (`??=`). When false, `t ??= v` is generated as `t = t ?? v`, routing the
  /// `??` through [renderNullCoalesce] so each target needs only one desugar.
  ///
  /// Dart, C#, JavaScript and TypeScript have `??=`; Kotlin, Java, Lua, Python
  /// and Go do not.
  bool get supportsNullCoalesceAssignment => true;

  /// Generates the null-coalescing expression `a ?? b`.
  StringBuffer generateASTExpressionNullCoalesce(
    ASTExpression expression1,
    ASTExpression expression2, {
    StringBuffer? out,
    String indent = '',
  }) {
    out ??= newOutput();

    var a = generateASTExpression(
      expression1,
      indent: '$indent  ',
      headIndented: false,
    ).toString();

    var b = generateASTExpression(
      expression2,
      indent: '$indent  ',
      headIndented: false,
    ).toString();

    out.write(renderNullCoalesce(a, b));

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

    var cond = generateASTExpression(
      expression.condition,
      indent: '$indent  ',
      headIndented: false,
    );
    var valueTrue = generateASTExpression(
      expression.valueIfTrue,
      indent: '$indent  ',
      headIndented: false,
    );
    var valueFalse = generateASTExpression(
      expression.valueIfFalse,
      indent: '$indent  ',
      headIndented: false,
    );

    if (expression.condition.isComplex) {
      out.write('(');
      out.write(cond);
      out.write(')');
    } else {
      out.write(cond);
    }

    out.write(' ? ');
    out.write(valueTrue);
    out.write(' : ');
    out.write(valueFalse);

    return out;
  }

  /// If [f]'s body is a single `return <expr>;`, returns that expression (used
  /// to emit concise single-expression lambdas); otherwise returns `null`.
  ASTExpression? singleReturnExpression(ASTFunctionDeclaration f) {
    var statements = f.statements;
    if (statements.length != 1) return null;
    var stm = statements.first;
    if (stm is ASTStatementReturnWithExpression) return stm.expression;
    return null;
  }

  /// Generates the comma-separated parameter names of [f] wrapped in `( )`.
  StringBuffer generateFunctionParametersNames(
    ASTFunctionDeclaration f, {
    required StringBuffer out,
  }) {
    out.write('(');
    if (f.parametersSize > 0) {
      generateASTParametersDeclaration(f.parameters, out: out);
    }
    out.write(')');
    return out;
  }

  /// Default (C-style arrow, e.g. JavaScript/TypeScript) anonymous function:
  /// `(params) => expr` or `(params) => { body }`.
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
  String resolveASTExpressionOperatorText(
    ASTExpressionOperator operator,
    ASTNumType aNumType,
    ASTNumType bNumType,
  );

  @override
  StringBuffer generateASTExpressionLiteral(
    ASTExpressionLiteral expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();
    if (headIndented) out.write(indent);
    generateASTValue(
      expression.value,
      out: out,
      indent: indent,
      headIndented: false,
    );
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

    final type = expression.type;
    if (type != null) {
      out.write('<');
      generateASTType(type, out: out);
      out.write('>');
    }

    out.write('[');

    var valuesExpressions = expression.valuesExpressions;
    for (var i = 0; i < valuesExpressions.length; ++i) {
      var e = valuesExpressions[i];

      if (i > 0) {
        out.write(', ');
      }
      generateASTExpression(e, out: out);
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

    final keyType = expression.keyType;
    final valueType = expression.valueType;

    if (keyType != null && valueType != null) {
      out.write('<');
      generateASTType(keyType, out: out);
      out.write(',');
      generateASTType(valueType, out: out);
      out.write('>');
    }

    out.write('{');

    var entriesExpressions = expression.entriesExpressions;
    for (var i = 0; i < entriesExpressions.length; ++i) {
      var e = entriesExpressions[i];

      if (i > 0) {
        out.write(', ');
      }

      generateASTExpression(e.key, out: out);
      out.write(": ");
      generateASTExpression(e.value, out: out);
    }

    out.write('}');

    return out;
  }

  /// Renders a cascade (`receiver..sel..sel`, `receiver?..sel`). Each section
  /// operates on the synthetic cascade target; rendering the section yields
  /// `<target>.sel`, so the target prefix is stripped and the cascade operator
  /// supplies the extra dot. Targets without cascades still emit valid (if less
  /// idiomatic) output for the common single-section forms.
  StringBuffer generateASTExpressionCascade(
    ASTExpressionCascade expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    generateASTExpression(
      expression.receiver,
      out: out,
      indent: indent,
      headIndented: false,
    );

    final target = expression.targetVariableName;
    final sections = expression.sections;

    for (var i = 0; i < sections.length; i++) {
      var s = generateASTExpression(
        sections[i],
        headIndented: false,
      ).toString();
      // Strip the synthetic target so `<target>.sel` becomes `.sel`.
      if (s.startsWith(target)) {
        s = s.substring(target.length);
      }
      var op = (i == 0 && expression.isNullAware && supportsNullAwareOperators)
          ? '?.'
          : '.';
      out.write(op);
      out.write(s);
    }

    return out;
  }

  /// The postfix null-assertion token for this target (`!` for Dart/TypeScript,
  /// `!!` for Kotlin). Only emitted when [supportsNullAwareOperators] is true.
  String get nullAssertionSuffix => '!';

  /// The opening token for a null-aware index access (`?[` for Dart, `?.[` for
  /// TypeScript). Only used when [supportsNullAwareOperators] is true.
  String get nullAwareIndexOpen => '?[';

  StringBuffer generateASTExpressionNullAssertion(
    ASTExpressionNullAssertion expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    final inner = expression.expression;
    final group = inner.isComplex;

    if (group) out.write('(');
    generateASTExpression(inner, out: out, indent: indent, headIndented: false);
    if (group) out.write(')');

    // Best-effort: targets without a null-assertion operator drop it.
    if (supportsNullAwareOperators) {
      out.write(nullAssertionSuffix);
    }

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

    out.write('!');

    // Parenthesize a complex operand so `!(a > b)` is not emitted as `!a > b`
    // (which would re-parse as `(!a) > b`).
    final inner = expression.expression;
    final group = inner.isComplex;

    if (group) out.write('(');
    generateASTExpression(inner, out: out, indent: indent, headIndented: false);
    if (group) out.write(')');

    return out;
  }

  StringBuffer generateASTExpressionBitwiseNot(
    ASTExpressionBitwiseNot expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    out.write('~');

    // Parenthesize a complex operand so `~(a + b)` is not emitted as `~a + b`.
    final inner = expression.expression;
    final group = inner.isComplex;

    if (group) out.write('(');
    generateASTExpression(inner, out: out, indent: indent, headIndented: false);
    if (group) out.write(')');

    return out;
  }

  @override
  StringBuffer generateASTExpressionNegative(
    ASTExpressionNegative expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    out.write('-');

    generateASTExpression(
      expression.expression,
      out: out,
      indent: indent,
      headIndented: false,
    );

    return out;
  }

  /// Generates an `await` expression. Shared by languages that use the
  /// `await` keyword (Dart, JavaScript). Languages without it (e.g. Kotlin,
  /// Wasm) should override this to fail loudly.
  @override
  StringBuffer generateASTExpressionAwait(
    ASTExpressionAwait expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    out.write('await ');

    // Parenthesize a complex operand so `await a + b` is not emitted (which
    // would re-parse as `(await a) + b`).
    final inner = expression.expression;
    final group = inner.isComplex;

    if (group) out.write('(');
    generateASTExpression(inner, out: out, indent: indent, headIndented: false);
    if (group) out.write(')');

    return out;
  }

  @override
  StringBuffer generateASTExpressionGroupFunctionInvocation(
    ASTExpressionGroupFunctionInvocation expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    out.write('(');
    generateASTExpression(
      expression.expression,
      out: out,
      indent: indent,
      headIndented: false,
    );
    out.write(')');
    out.write('.');

    final functionName = expression.name;
    final arguments = expression.arguments;

    _generateFunctionInvocation(
      functionName,
      arguments,
      out,
      indent,
      namedArguments: expression.namedArguments,
    );

    _generateChainFunctionInvocation(expression, out, indent);

    return out;
  }

  @override
  StringBuffer generateASTExpressionFunctionInvocation(
    ASTExpressionObjectFunctionInvocation expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    var functionName = expression.name;

    if (expression.variable.isTypeIdentifier) {
      var typeIdentifier = expression.variable.typeIdentifier;
      functionName = normalizeTypeFunction(typeIdentifier!.name, functionName);
    } else {
      functionName = normalizeIdentifier(functionName);
    }

    generateASTVariable(
      expression.variable,
      callingFunction: functionName,
      out: out,
      indent: indent,
      headIndented: false,
    );
    if (expression.assertReceiver && supportsNullAwareOperators) {
      out.write(nullAssertionSuffix);
    }
    out.write(
      expression.isNullAware && supportsNullAwareOperators ? '?.' : '.',
    );

    final arguments = expression.arguments;

    _generateFunctionInvocation(
      functionName,
      arguments,
      out,
      indent,
      namedArguments: expression.namedArguments,
    );

    _generateChainFunctionInvocation(expression, out, indent);

    return out;
  }

  @override
  StringBuffer generateASTExpressionObjectEntryFunctionInvocation(
    ASTExpressionObjectEntryFunctionInvocation expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    final variableAccess = expression.variableAccess;

    var functionName = expression.name;

    if (variableAccess.variable.isTypeIdentifier) {
      var typeIdentifier = variableAccess.variable.typeIdentifier;
      functionName = normalizeTypeFunction(typeIdentifier!.name, functionName);
    }

    generateASTExpressionVariableEntryAccess(variableAccess, out: out);
    out.write('.');

    final arguments = expression.arguments;

    _generateFunctionInvocation(
      functionName,
      arguments,
      out,
      indent,
      namedArguments: expression.namedArguments,
    );

    _generateChainFunctionInvocation(expression, out, indent);

    return out;
  }

  @override
  StringBuffer generateASTExpressionLocalFunctionInvocation(
    ASTExpressionLocalFunctionInvocation expression, {
    String indent = '',
    StringBuffer? out,
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    final functionName = expression.name;
    final arguments = expression.arguments;

    _generateFunctionInvocation(
      functionName,
      arguments,
      out,
      indent,
      namedArguments: expression.namedArguments,
    );

    _generateChainFunctionInvocation(expression, out, indent);

    return out;
  }

  /// The separator written between a named argument's name and value at a call
  /// site (e.g. `name: value` in Dart/Kotlin/C#, `name=value` in Python).
  String get namedArgumentSeparator => ': ';

  void _generateFunctionInvocation(
    String functionName,
    List<ASTExpression> arguments,
    StringBuffer out,
    String indent, {
    Map<String, ASTExpression>? namedArguments,
  }) {
    out.write(functionName);
    out.write('(');

    var count = 0;

    for (var i = 0; i < arguments.length; ++i) {
      var arg = arguments[i];
      if (count > 0) out.write(', ');

      generateASTExpression(
        arg,
        out: out,
        indent: '$indent  ',
        headIndented: false,
      );
      ++count;
    }

    if (namedArguments != null && namedArguments.isNotEmpty) {
      for (var entry in namedArguments.entries) {
        if (count > 0) out.write(', ');

        out.write(entry.key);
        out.write(namedArgumentSeparator);

        generateASTExpression(
          entry.value,
          out: out,
          indent: '$indent  ',
          headIndented: false,
        );
        ++count;
      }
    }

    out.write(')');
  }

  void _generateChainFunctionInvocation(
    WithCallChainFunction expression,
    StringBuffer out,
    String indent,
  ) {
    final chainFunctionInvocation = expression.chainFunctionInvocation;

    if (chainFunctionInvocation != null && chainFunctionInvocation.isNotEmpty) {
      for (var f in chainFunctionInvocation) {
        out.write('.');
        _generateFunctionInvocation(
          f.name,
          f.arguments,
          out,
          indent,
          namedArguments: f.namedArguments,
        );
      }
    }
  }

  @override
  StringBuffer generateASTExpressionObjectGetterAccess(
    ASTExpressionObjectGetterAccess expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    var getterName = expression.name;

    if (expression.variable.isTypeIdentifier) {
      var typeIdentifier = expression.variable.typeIdentifier;
      getterName = normalizeTypeFunction(typeIdentifier!.name, getterName);
    } else {
      getterName = normalizeIdentifier(getterName);
    }

    generateASTVariable(
      expression.variable,
      callingFunction: getterName,
      out: out,
      indent: indent,
      headIndented: false,
    );
    if (expression.assertReceiver && supportsNullAwareOperators) {
      out.write(nullAssertionSuffix);
    }
    out.write(
      expression.isNullAware && supportsNullAwareOperators ? '?.' : '.',
    );

    out.write(getterName);

    _generateChainFunctionInvocation(expression, out, indent);

    return out;
  }

  StringBuffer generateASTExpressionObjectSetterAssignment(
    ASTExpressionObjectSetterAssignment expression, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    // The `obj.field` write target, captured so `??=` can repeat it.
    var target = generateASTVariable(
      expression.variable,
      indent: indent,
      headIndented: false,
    );
    target.write('.');
    target.write(normalizeIdentifier(expression.name));

    var targetStr = target.toString();
    out.write(targetStr);

    var value = generateASTExpression(
      expression.expression,
      indent: '$indent  ',
      headIndented: false,
    ).toString();

    _writeAssignment(out, expression.operator, targetStr, value);

    return out;
  }

  @override
  StringBuffer generateASTExpressionLocalGetterAccess(
    ASTExpressionLocalGetterAccess expression, {
    String indent = '',
    StringBuffer? out,
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    out.write(expression.name);

    _generateChainFunctionInvocation(expression, out, indent);

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

    out.write('null');
    return out;
  }

  @override
  StringBuffer generateASTExpressionVariableAccess(
    ASTExpressionVariableAccess expression, {
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
      headIndented: false,
    );

    return out;
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
    if (expression.assertReceiver && supportsNullAwareOperators) {
      out.write(nullAssertionSuffix);
    }
    out.write(
      expression.isNullAware && supportsNullAwareOperators
          ? nullAwareIndexOpen
          : '[',
    );
    generateASTExpression(
      expression.expression,
      out: out,
      indent: indent,
      headIndented: false,
    );
    out.write(']');
    // Chained indices for nested access (`m[0][1]`).
    for (var extra in expression.extraIndices) {
      out.write('[');
      generateASTExpression(
        extra,
        out: out,
        indent: indent,
        headIndented: false,
      );
      out.write(']');
    }
    return out;
  }

  @override
  StringBuffer generateASTVariable(
    ASTVariable variable, {
    String? callingFunction,
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    if (variable is ASTExpressionVariable) {
      // A member-access chain wraps each preceding segment as a receiver
      // "variable"; generating it means generating that expression, not a name.
      out ??= newOutput();
      if (headIndented) out.write(indent);
      return generateASTExpression(
        variable.expression,
        out: out,
        indent: indent,
        headIndented: false,
      );
    } else if (variable is ASTScopeVariable) {
      return generateASTScopeVariable(
        variable,
        callingFunction: callingFunction,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else {
      return generateASTVariableGeneric(
        variable,
        callingFunction: callingFunction,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    }
  }

  @override
  StringBuffer generateASTScopeVariable(
    ASTScopeVariable variable, {
    String? callingFunction,
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    var name = variable.name;

    if (variable.isTypeIdentifier) {
      var typeIdentifier = variable.typeIdentifier;
      name = typeIdentifier!.name;
      name = normalizeTypeName(name, callingFunction);
    }

    out.write(name);

    return out;
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
    out.write(variable.name);
    return out;
  }

  @override
  StringBuffer generateASTValue(
    ASTValue value, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    if (value is ASTValueString) {
      return generateASTValueString(
        value,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (value is ASTValueInt) {
      return generateASTValueInt(
        value,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (value is ASTValueDouble) {
      return generateASTValueDouble(
        value,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (value is ASTValueNull) {
      return generateASTValueNull(
        value,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (value is ASTValueVar) {
      return generateASTValueVar(
        value,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (value is ASTValueObject) {
      return generateASTValueObject(
        value,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (value is ASTValueStatic) {
      return generateASTValueStatic(
        value,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (value is ASTValueStringVariable) {
      return generateASTValueStringVariable(value, out: out, indent: indent);
    } else if (value is ASTValueStringConcatenation) {
      return generateASTValueStringConcatenation(
        value,
        out: out,
        indent: indent,
      );
    } else if (value is ASTValueStringExpression) {
      return generateASTValueStringExpression(value, indent: indent, out: out);
    } else if (value is ASTValueArray) {
      return generateASTValueArray(
        value,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (value is ASTValueArray2D) {
      return generateASTValueArray2D(
        value,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    } else if (value is ASTValueArray3D) {
      return generateASTValueArray3D(
        value,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    }

    throw UnsupportedError("Can't generate value: $value");
  }

  @override
  StringBuffer generateASTValueStringConcatenation(
    ASTValueStringConcatenation value, {
    StringBuffer? out,
    String indent = '',
  });

  @override
  StringBuffer generateASTValueStringVariable(
    ASTValueStringVariable value, {
    StringBuffer? out,
    String indent = '',
    bool precededByString = false,
  });

  @override
  StringBuffer generateASTValueStringExpression(
    ASTValueStringExpression value, {
    StringBuffer? out,
    String indent = '',
  });

  @override
  StringBuffer generateASTValueString(
    ASTValueString value, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  });

  @override
  StringBuffer generateASTValueInt(
    ASTValueInt value, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);
    out.write(value.value);
    return out;
  }

  @override
  StringBuffer generateASTValueDouble(
    ASTValueDouble value, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);

    var v = value.value;
    var s = ASTTypeDouble.doubleToString(v);

    out.write(s);

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
    out.write('null');
    return out;
  }

  @override
  StringBuffer generateASTValueVar(
    ASTValueVar value, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);
    out.write(value.value);
    return out;
  }

  @override
  StringBuffer generateASTValueObject(
    ASTValueObject value, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    out ??= newOutput();

    if (headIndented) out.write(indent);
    out.write(value.value);
    return out;
  }

  @override
  StringBuffer generateASTValueStatic(
    ASTValueStatic value, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  }) {
    var v = value.value;

    if (v is ASTNode) {
      return generateASTNode(
        v,
        out: out,
        indent: indent,
        headIndented: headIndented,
      );
    }

    out ??= newOutput();
    out.write(value.value);
    return out;
  }

  @override
  StringBuffer generateASTValueArray(
    ASTValueArray value, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  });

  @override
  StringBuffer generateASTValueArray2D(
    ASTValueArray2D value, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  });

  @override
  StringBuffer generateASTValueArray3D(
    ASTValueArray3D value, {
    StringBuffer? out,
    String indent = '',
    bool headIndented = true,
  });
}
