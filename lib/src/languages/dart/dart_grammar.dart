// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:petitparser/petitparser.dart';

import '../../apollovm_base.dart';
import '../../ast/apollovm_ast_base.dart';
import '../../ast/apollovm_ast_expression.dart';
import '../../ast/apollovm_ast_statement.dart';
import '../../ast/apollovm_ast_toplevel.dart';
import '../../ast/apollovm_ast_type.dart';
import '../../ast/apollovm_ast_value.dart';
import '../../ast/apollovm_ast_variable.dart';
import 'dart_grammar_lexer.dart';

/// Dart grammar definition.
class DartGrammarDefinition extends DartGrammarLexer {
  static ASTType getTypeByName(String name) {
    switch (name) {
      case 'Object':
        return ASTTypeObject.instance;
      case 'void':
        return ASTTypeVoid.instance;
      case 'bool':
        return ASTTypeBool.instance;
      case 'int':
        return ASTTypeInt.instance;
      case 'double':
        return ASTTypeDouble.instance;
      case 'num':
        return ASTTypeNum.instance;
      case 'String':
        return ASTTypeString.instance;
      case 'dynamic':
        return ASTTypeDynamic.instance;
      case 'List':
        return ASTTypeArray.instanceOfDynamic;
      case 'Map':
        return ASTTypeMap.instanceOfDynamicOfDynamic;
      case 'var':
        return ASTTypeVar();
      case 'final':
      case 'const':
        return ASTTypeVar(unmodifiable: true);
      default:
        return ASTType(name);
    }
  }

  @override
  Parser start() => ref0(compilationUnit).trim().end();

  Parser<ASTRoot> compilationUnit() =>
      (ref0(hashbangLexicalToken).optional() &
              //ref0(libraryDirective).optional() &
              ref0(topLevelDirective).star() &
              ref0(topLevelDefinition).star())
          .map((v) {
            var directives = v[1] as List;
            var topDef = v[2] as List;

            var root = ASTRoot();

            for (var directive in directives) {
              if (directive is ASTStatementImport) {
                root.addImport(directive);
              } else if (directive is ASTStatementExport) {
                root.addExport(directive);
              }
            }

            for (var defList in topDef) {
              for (var def in defList) {
                if (def is ASTFunctionDeclaration) {
                  root.addFunction(def);
                } else if (def is ASTClassNormal) {
                  root.addClass(def);
                } else if (def is ASTExtension) {
                  root.addExtension(def);
                } else if (def is ASTTypeAlias) {
                  root.addTypeAlias(def);
                } else if (def is ASTStatementVariableDeclaration) {
                  root.addStatement(def);
                }
              }
            }

            root.resolveNode(null);

            return root;
          });

  /// A top-level directive: `import` or `export`.
  Parser<ASTStatement> topLevelDirective() =>
      (ref0(statementImport) | ref0(statementExport)).cast<ASTStatement>();

  Parser topLevelDefinition() =>
      (typeAliasDeclaration() |
              enumDeclaration() |
              extensionDeclaration() |
              classDeclaration() |
              functionDeclaration() |
              statementVariableDeclaration())
          .plus();

  Parser<ASTFunctionDeclaration> functionDeclaration() =>
      (type().optional() &
              identifier() &
              functionParametersDeclaration() &
              asyncToken().optional() &
              (arrowBody() | codeBlock()))
          .map((v) {
            var returnType = v[0] as ASTType? ?? ASTTypeDynamic.instance;
            var parameters = v[2];
            var name = v[1];
            var isAsync = v[3] != null;
            var block = v[4];
            return ASTFunctionDeclaration(
              name,
              parameters,
              returnType,
              block: block,
              modifiers: ASTModifiers(isStatic: true, isAsync: isAsync),
            );
          });

  Parser<ASTStatementImport> statementImport() =>
      (importToken().trimHidden() &
              stringLexicalToken() &
              (asToken().trimHidden() & identifier()).optional() &
              (ref0(importShow) | ref0(importHide)).star() &
              char(';').trimHidden())
          .map((v) {
            var parsedPath = v[1] as ParsedString;
            var path =
                parsedPath.literalString ??
                (throw StateError("Invalid import parsed path: $parsedPath"));

            var asOpt = v[2] as List?;
            var prefix = asOpt != null ? asOpt[1] as String : null;

            var combinators = (v[3] as List).cast<ASTImportCombinator>();

            // A `show` clause also feeds the canonical named-symbol allow-list
            // (used by the resolver for scoping and missing-symbol diagnostics).
            var namedSymbols = <ASTImportedSymbol>[
              for (var c in combinators)
                if (c.isShow) ...c.names.map((n) => ASTImportedSymbol(n)),
            ];

            return ASTStatementImport(
              path,
              prefix: prefix,
              combinators: combinators,
              namedSymbols: namedSymbols,
            );
          });

  Parser<ASTStatementExport> statementExport() =>
      (exportToken().trimHidden() &
              stringLexicalToken() &
              (ref0(importShow) | ref0(importHide)).star() &
              char(';').trimHidden())
          .map((v) {
            var parsedPath = v[1] as ParsedString;
            var path =
                parsedPath.literalString ??
                (throw StateError("Invalid export parsed path: $parsedPath"));
            var combinators = (v[2] as List).cast<ASTImportCombinator>();
            return ASTStatementExport(path: path, combinators: combinators);
          });

  Parser<ASTImportCombinator> importShow() =>
      (showToken().trimHidden() & ref0(importIdentifierList)).map(
        (v) => ASTImportCombinator(
          ASTImportCombinatorKind.show,
          v[1] as List<String>,
        ),
      );

  Parser<ASTImportCombinator> importHide() =>
      (hideToken().trimHidden() & ref0(importIdentifierList)).map(
        (v) => ASTImportCombinator(
          ASTImportCombinatorKind.hide,
          v[1] as List<String>,
        ),
      );

  Parser<List<String>> importIdentifierList() =>
      (identifier() & (char(',').trimHidden() & identifier()).star()).map((v) {
        var first = v[0] as String;
        var rest = (v[1] as List).map((e) => (e as List)[1] as String);
        return <String>[first, ...rest];
      });

  Parser<ASTTypeAlias> typeAliasDeclaration() =>
      (typedefToken().trimHidden() &
              identifier() &
              char('=').trimHidden() &
              type() &
              char(';').trimHidden())
          .map((v) => ASTTypeAlias(v[1] as String, v[3] as ASTType));

  /// `extension [Name] on Type { <methods and getters> }`.
  ///
  /// The name is optional (Dart allows unnamed extensions). Members reuse the
  /// class-member parsers, so an extension method is an ordinary
  /// [ASTClassFunctionDeclaration] whose `clazz` is bound to the extended class
  /// by [ASTExtension.resolveNode].
  Parser<ASTExtension> extensionDeclaration() =>
      (extensionToken().trimHidden() &
              extensionName() &
              onToken().trimHidden() &
              type() &
              char('{').trimHidden() &
              (ref0(classFunctionDeclaration) | ref0(getterDeclaration))
                  .star() &
              char('}').trimHidden())
          .map((v) {
            var name = v[1] as String?;
            var targetType = v[3] as ASTType;

            var extension = ASTExtension(name, targetType);

            for (var member in (v[5] as List)) {
              if (member is ASTClassGetterDeclaration) {
                extension.addGetter(member);
              } else if (member is ASTFunctionDeclaration) {
                extension.addFunction(member);
              }
            }

            return extension;
          });

  /// The optional name of an extension. Only consumed when followed by `on`,
  /// otherwise `extension on int {}` would read `on` as the name.
  Parser<String?> extensionName() =>
      (identifier().trimHidden() & onToken().and())
          .map((v) => v[0] as String)
          .optional();

  /// An instance getter: `int get twice => this * 2;` or `int get twice { … }`.
  /// Valid in a class body and in an extension body. Setters are not supported.
  Parser<ASTClassGetterDeclaration> getterDeclaration() =>
      (type().optional() &
              getToken().trimHidden() &
              identifier() &
              (arrowBody() | codeBlock()))
          .map((v) {
            var returnType = v[0] as ASTType? ?? ASTTypeDynamic.instance;
            var name = v[2] as String;
            var block = v[3] as ASTBlock;
            return ASTClassGetterDeclaration(
              null,
              name,
              returnType,
              block: block,
            );
          });

  /// Type-parameter names of the class currently being parsed (e.g. `T` in
  /// `class Wrapper<T>`). Used by [simpleType] to erase them to `dynamic`.
  final Set<String> _classTypeParameters = <String>{};

  Parser<ASTClassNormal> classDeclaration() =>
      (abstractToken().trimHidden().optional() &
              string('class').trimHidden().map((v) {
                // Reset at each class head; type parameters (if any) are added
                // next, before the body is parsed.
                _classTypeParameters.clear();
                return v;
              }) &
              identifier() &
              typeParameters().optional() &
              (extendsToken().trimHidden() & identifier()).optional() &
              (implementsToken().trimHidden() &
                      identifier() &
                      (char(',').trimHidden() & identifier()).star())
                  .optional() &
              classCodeBlock())
          .map((v) {
            var isAbstract = v[0] != null;
            var name = v[2] as String;

            var extendsOpt = v[4] as List?;
            var superName = extendsOpt != null ? extendsOpt[1] as String : null;

            var implementsOpt = v[5] as List?;
            var interfaces = <String>[];
            if (implementsOpt != null) {
              interfaces.add(implementsOpt[1] as String);
              for (var e in (implementsOpt[2] as List)) {
                interfaces.add(e[1] as String);
              }
            }

            var block = v[6];
            var clazz = ASTClassNormal(
              name,
              ASTType<VMObject>(name),
              null,
              kind: isAbstract
                  ? ASTClassKind.abstractClass
                  : ASTClassKind.normalClass,
              superClassName: superName,
              implementsTypes: interfaces.isEmpty ? null : interfaces,
            );
            clazz.set(block);
            _classTypeParameters.clear();
            return clazz;
          });

  /// Generic type parameters in a declaration: `<T>`, `<K, V>` (names only;
  /// bounds like `<T extends Foo>` keep just the name). Records the names so
  /// member types using them are erased to `dynamic`.
  Parser<List<String>> typeParameters() =>
      (char('<').trimHidden() &
              typeParameter() &
              (char(',').trimHidden() & typeParameter()).star() &
              char('>').trimHidden())
          .map((v) {
            var names = <String>[v[1] as String];
            for (var e in (v[2] as List)) {
              names.add((e as List)[1] as String);
            }
            _classTypeParameters.addAll(names);
            return names;
          });

  Parser<String> typeParameter() =>
      (identifier().trimHidden() &
              (extendsToken().trimHidden() & ref0(type)).optional())
          .map((v) => v[0] as String);

  /// Generic type arguments on a usage/invocation: `<int>`, `<String, int>`.
  Parser<List<ASTType>> typeArguments() =>
      (char('<').trimHidden() &
              ref0(type) &
              (char(',').trimHidden() & ref0(type)).star() &
              char('>').trimHidden())
          .map((v) {
            var list = <ASTType>[v[1] as ASTType];
            for (var e in (v[2] as List)) {
              list.add((e as List)[1] as ASTType);
            }
            return list;
          });

  Parser<ASTClassEnum> enumDeclaration() =>
      (string('enum').trimHidden() &
              identifier() &
              char('{').trimHidden() &
              enumEntry() &
              (char(',').trimHidden() & enumEntry()).star() &
              char(',').trimHidden().optional() &
              // Enhanced/rich enum body: `;` then class members (fields, a
              // `const` constructor, methods) — reusing class-member parsing.
              (char(';').trimHidden() &
                      (ref0(classConstructorDefaultDeclaration) |
                              ref0(classFunctionDeclaration) |
                              ref0(classFieldDeclaration) |
                              ref0(classFieldDeclarationWithValue))
                          .star())
                  .optional() &
              char('}').trimHidden())
          .map((v) {
            var name = v[1] as String;
            var entries = <ASTEnumEntry>[v[3] as ASTEnumEntry];
            for (var e in (v[4] as List)) {
              entries.add(e[1] as ASTEnumEntry);
            }
            var enumClass = ASTClassEnum(
              name,
              ASTType<VMObject>(name),
              null,
              entries: entries,
            );
            var membersOpt = v[6] as List?;
            if (membersOpt != null) {
              var members = membersOpt[1] as List;
              enumClass.addAllFields(
                members.whereType<ASTClassField>().toList(),
              );
              enumClass.addAllConstructors(
                members.whereType<ASTClassConstructorDeclaration>().toList(),
              );
              enumClass.addAllFunctions(
                members.whereType<ASTFunctionDeclaration>().toList(),
              );
            }
            return enumClass;
          });

  Parser<ASTEnumEntry> enumEntry() =>
      (identifier().trimHidden() &
              ((char('=').trimHidden() & ref0(expression)) |
                      (char('(').trimHidden() &
                          expressionSequence().optional() &
                          char(')').trimHidden()))
                  .optional())
          .map((v) {
            var name = v[0] as String;
            var suffix = v[1] as List?;
            ASTExpression? value;
            List<ASTExpression>? arguments;
            if (suffix != null) {
              if (suffix[0] == '=') {
                // Explicit value: `Red = 1`.
                value = suffix[1] as ASTExpression;
              } else {
                // Rich-enum constructor args: `earth(5.97, 6371)`.
                arguments =
                    (suffix[1] as List?)?.cast<ASTExpression>() ??
                    <ASTExpression>[];
              }
            }
            return ASTEnumEntry(name, value: value, arguments: arguments);
          });

  Parser<ASTBlock> classCodeBlock() =>
      (char('{').trimHidden() &
              (ref0(classConstructorDefaultDeclaration) |
                      ref0(classFunctionDeclaration) |
                      ref0(getterDeclaration) |
                      ref0(classFieldDeclaration) |
                      ref0(classFieldDeclarationWithValue))
                  .star() &
              char('}').trimHidden())
          .map((v) {
            var list = v[1] as List;
            var fields = list.whereType<ASTClassField>().toList();
            var constructors = list
                .whereType<ASTClassConstructorDeclaration>()
                .toList();
            var getters = list.whereType<ASTClassGetterDeclaration>().toList();
            var functions = list.whereType<ASTFunctionDeclaration>().toList();

            var block = ASTClassNormal('?', ASTType<VMObject>('?'), null);

            block.addAllFields(fields);
            block.addAllConstructors(constructors);
            block.addAllFunctions(functions);
            block.addAllGetters(getters);

            return block;
          });

  Parser<ASTClassField> classFieldDeclaration() =>
      (staticToken().trimHidden().optional() &
              (finalToken() | constToken()).optional() &
              type().trimHidden() &
              identifier().trimHidden() &
              char(';').trimHidden())
          .map((v) {
            var isStatic = v[0] != null;
            var finalValue = v[1] != null;
            var type = v[2] as ASTType;
            var name = v[3] as String;
            return ASTClassField(
              type,
              name,
              finalValue,
              modifiers: ASTModifiers(isStatic: isStatic, isFinal: finalValue),
            );
          });

  Parser<ASTClassField> classFieldDeclarationWithValue() =>
      (staticToken().trimHidden().optional() &
              (finalToken() | constToken()).optional() &
              type() &
              identifier() &
              char('=').trimHidden() &
              ref0(expression) &
              char(';').trimHidden())
          .map((v) {
            var isStatic = v[0] != null;
            var finalValue = v[1] != null;
            var type = v[2] as ASTType;
            var name = v[3] as String;
            var expression = v[5] as ASTExpression;
            type.associateToType(expression);
            return ASTClassFieldWithInitialValue(
              type,
              name,
              expression,
              finalValue,
              modifiers: ASTModifiers(isStatic: isStatic, isFinal: finalValue),
            );
          });

  Parser<ASTClassConstructorDeclaration> classConstructorDefaultDeclaration() =>
      (constToken().trimHidden().optional() &
              identifier() &
              constructorParametersDeclaration() &
              (char(';').trim() | codeBlock()))
          .map((v) {
            var className = v[1];
            var parameters = v[2] as ASTConstructorParametersDeclaration;
            var optionalBlock = v[3];
            var block = optionalBlock is ASTBlock ? optionalBlock : null;
            return ASTClassConstructorDeclaration(
              ASTType(className),
              '',
              parameters,
              block: block,
            );
          });

  Parser<ASTConstructorParametersDeclaration>
  constructorParametersDeclaration() =>
      (constructorEmptyParametersDeclaration() |
              constructorFullParametersDeclaration())
          .cast<ASTConstructorParametersDeclaration>();

  Parser<ASTConstructorParametersDeclaration>
  constructorEmptyParametersDeclaration() => (char('(') & char(')')).map((v) {
    return ASTConstructorParametersDeclaration(null, null, null);
  });

  /// Parses a full constructor parameters declaration: optional positional
  /// parameters, optionally followed by a trailing `{named}` or `[optional]`
  /// group — e.g. `(this.x, this.y)`, `({this.x, this.y})`, `(int x, {int y})`.
  Parser<ASTConstructorParametersDeclaration>
  constructorFullParametersDeclaration() =>
      (char('(').trimHidden() &
              constructorParametersList().optional() &
              (char(',').trimHidden().optional() & constructorParameterGroup())
                  .optional() &
              char(',').trimHidden().optional() &
              char(')').trimHidden())
          .map((v) {
            var positional = v[1] as List<ASTConstructorParameterDeclaration>?;
            var groupOpt = v[2] as List?;

            List<ASTConstructorParameterDeclaration>? named;
            List<ASTConstructorParameterDeclaration>? optional;

            if (groupOpt != null) {
              var group =
                  groupOpt[1]
                      as ({
                        bool isNamed,
                        List<ASTConstructorParameterDeclaration> params,
                      });
              if (group.isNamed) {
                named = group.params;
              } else {
                optional = group.params;
              }
            }

            return ASTConstructorParametersDeclaration(
              positional,
              optional,
              named,
            );
          });

  /// A trailing constructor parameter group: `{named}` or `[optional]`.
  Parser<({bool isNamed, List<ASTConstructorParameterDeclaration> params})>
  constructorParameterGroup() =>
      (constructorNamedParameterGroup() | constructorOptionalParameterGroup())
          .cast();

  Parser<({bool isNamed, List<ASTConstructorParameterDeclaration> params})>
  constructorNamedParameterGroup() =>
      (char('{').trimHidden() &
              constructorParametersList() &
              char('}').trimHidden())
          .map((v) {
            return (
              isNamed: true,
              params: v[1] as List<ASTConstructorParameterDeclaration>,
            );
          });

  Parser<({bool isNamed, List<ASTConstructorParameterDeclaration> params})>
  constructorOptionalParameterGroup() =>
      (char('[').trimHidden() &
              constructorParametersList() &
              char(']').trimHidden())
          .map((v) {
            return (
              isNamed: false,
              params: v[1] as List<ASTConstructorParameterDeclaration>,
            );
          });

  Parser<List<ASTConstructorParameterDeclaration>>
  constructorParametersList() =>
      (constructorParameterDeclaration() &
              (char(',') & constructorParameterDeclaration()).star() &
              char(',').optional())
          .map((v) {
            var params = _expandListDeeply(v);
            return params
                .whereType<ASTConstructorParameterDeclaration>()
                .toList();
          });

  Parser<ASTConstructorParameterDeclaration>
  constructorParameterDeclaration() =>
      (constructorThisParameterDeclaration() |
              constructorTypedParameterDeclaration())
          .map((v) => v);

  Parser<ASTConstructorParameterDeclaration>
  constructorThisParameterDeclaration() =>
      (thisToken().trim() &
              char('.') &
              identifier() &
              parameterDefaultValue().optional())
          .map((v) {
            return ASTConstructorParameterDeclaration(
              ASTTypeConstructorThis.instance,
              v[2],
              -1,
              false,
              thisParameter: true,
            )..defaultValue = v[3] as ASTExpression?;
          });

  Parser<ASTConstructorParameterDeclaration>
  constructorTypedParameterDeclaration() =>
      ((finalToken() | constToken()).trim().optional() &
              type().trim() &
              identifier() &
              parameterDefaultValue().optional())
          .map((v) {
            return ASTConstructorParameterDeclaration(v[1], v[2], -1, false)
              ..defaultValue = v[3] as ASTExpression?;
          });

  Parser<ASTFunctionDeclaration> classFunctionDeclaration() =>
      (functionModifiers().optional() &
              type().optional() &
              identifier() &
              functionParametersDeclaration() &
              asyncToken().optional() &
              (arrowBody() | char(';').trimHidden() | codeBlock()))
          .map((v) {
            var modifiers =
                (v[0] as ASTModifiers?) ?? ASTModifiers.modifiersNone;
            if (v[4] != null) {
              modifiers = modifiers.copyWith(isAsync: true);
            }
            var returnType = v[1] as ASTType? ?? ASTTypeDynamic.instance;
            var name = v[2] as String;
            var parameters = v[3] as ASTFunctionParametersDeclaration;
            // An abstract/interface method has no body (`;` instead of a block).
            var block = v[5] is ASTBlock ? v[5] as ASTBlock : null;
            if (block == null) {
              modifiers = modifiers.copyWith(isAbstract: true);
            }
            return ASTClassFunctionDeclaration(
              null,
              name,
              parameters,
              returnType,
              block: block,
              modifiers: modifiers,
            );
          });

  Parser<ASTModifiers> functionModifiers() =>
      string('static').trimHidden().flatten().map((v) {
        return ASTModifiers(isStatic: true);
      });

  Parser<ASTBlock> codeBlock() =>
      (char('{').trimHidden() & ref0(statement).star() & char('}').trimHidden())
          .map((v) {
            var statements = (v[1] as List).cast<ASTStatement>().toList();
            return ASTBlock(null)..addAllStatements(statements);
          });

  Parser<ASTBlock> codeBlockOrSingleLineBlock() =>
      ((codeBlock() | singleLineCodeBlock())).cast<ASTBlock>();

  Parser<ASTSingleLineStatementBlock> singleLineCodeBlock() =>
      (singleLineStatement().trimHidden()).map((v) {
        var statements = v;
        return ASTSingleLineStatementBlock(null)..addStatement(statements);
      });

  Parser<ASTStatement> singleLineStatement() =>
      (statementReturn() | statementExpression()).cast<ASTStatement>();

  Parser<ASTStatement> statement() =>
      (statementTryCatch() |
              statementThrow() |
              statementSwitch() |
              branch() |
              statementBreak() |
              statementContinue() |
              statementDoWhileLoop() |
              statementForLoop() |
              statementForEach() |
              statementWhileLoop() |
              statementReturn() |
              statementFunctionDeclaration() |
              statementVariableDeclaration() |
              statementBlock() |
              statementExpression())
          .cast<ASTStatement>();

  Parser<ASTStatementBreak> statementBreak() =>
      (string('break') &
              ref0(identifierPartLexicalToken).not() &
              char(';').trimHidden())
          .map((v) => ASTStatementBreak());

  Parser<ASTStatementContinue> statementContinue() =>
      (string('continue') &
              ref0(identifierPartLexicalToken).not() &
              char(';').trimHidden())
          .map((v) => ASTStatementContinue());

  Parser<ASTStatementDoWhileLoop> statementDoWhileLoop() =>
      (string('do').trimHidden() &
              codeBlock() &
              string('while').trimHidden() &
              char('(').trimHidden() &
              ref0(expression) &
              char(')').trimHidden() &
              char(';').trimHidden())
          .map((v) {
            var block = v[1] as ASTBlock;
            var cond = v[4] as ASTExpression;
            return ASTStatementDoWhileLoop(block, cond);
          });

  Parser<ASTStatementSwitch> statementSwitch() =>
      (string('switch').trimHidden() &
              char('(').trimHidden() &
              ref0(expression) &
              char(')').trimHidden() &
              char('{').trimHidden() &
              switchCase().star() &
              char('}').trimHidden())
          .map((v) {
            var exp = v[2] as ASTExpression;
            var cases = (v[5] as List).cast<ASTSwitchCase>();
            return ASTStatementSwitch(exp, cases);
          });

  Parser<ASTSwitchCase> switchCase() =>
      (switchCaseLabel() & switchCaseBody()).map((v) {
        var value = v[0] as ASTExpression?;
        var block = v[1] as ASTBlock;
        return ASTSwitchCase(value, block);
      });

  Parser<ASTExpression?> switchCaseLabel() =>
      ((string('case').trimHidden() & ref0(expression) & char(':').trimHidden())
                  .map((v) => v[1] as ASTExpression?) |
              (string('default').trimHidden() & char(':').trimHidden()).map(
                (v) => null,
              ))
          .cast<ASTExpression?>();

  /// A `case`/`default` body: a braced block (`{ ... }`) or a bare run of
  /// statements up to the next `case`/`default`/`}`.
  Parser<ASTBlock> switchCaseBody() =>
      (codeBlock() | switchCaseStatements()).cast<ASTBlock>();

  Parser<ASTBlock> switchCaseStatements() => ref0(statement).star().map((v) {
    var statements = v.cast<ASTStatement>();
    return ASTBlock(null)..addAllStatements(statements);
  });

  Parser<ASTStatementThrow> statementThrow() =>
      (string('throw').trimHidden() & ref0(expression) & char(';').trimHidden())
          .map((v) => ASTStatementThrow(v[1] as ASTExpression));

  Parser<ASTStatementTryCatch> statementTryCatch() =>
      (string('try').trimHidden() &
              codeBlock() &
              catchClause().star() &
              (string('finally').trimHidden() & codeBlock()).optional())
          .map((v) {
            var tryBlock = v[1] as ASTBlock;
            var catches = (v[2] as List).cast<ASTCatchClause>();
            var finallyOpt = v[3] as List?;
            var finallyBlock = finallyOpt != null
                ? finallyOpt[1] as ASTBlock
                : null;
            return ASTStatementTryCatch(tryBlock, catches, finallyBlock);
          });

  Parser<ASTCatchClause> catchClause() =>
      (onCatchClause() | bareCatchClause()).cast<ASTCatchClause>();

  /// Dart `on Type [catch (e[, st])] { }`.
  Parser<ASTCatchClause> onCatchClause() =>
      (string('on').trimHidden() &
              type() &
              (string('catch').trimHidden() &
                      char('(').trimHidden() &
                      identifier().trimHidden() &
                      (char(',').trimHidden() & identifier().trimHidden())
                          .optional() &
                      char(')').trimHidden())
                  .optional() &
              codeBlock())
          .map((v) {
            var type = v[1] as ASTType;
            var catchPart = v[2] as List?;
            var varName = catchPart != null ? catchPart[2] as String : null;
            var block = v[3] as ASTBlock;
            return ASTCatchClause(type, varName, block);
          });

  /// Dart `catch (e[, st]) { }` (untyped catch-all).
  Parser<ASTCatchClause> bareCatchClause() =>
      (string('catch').trimHidden() &
              char('(').trimHidden() &
              identifier().trimHidden() &
              (char(',').trimHidden() & identifier().trimHidden()).optional() &
              char(')').trimHidden() &
              codeBlock())
          .map((v) {
            var varName = v[2] as String;
            var block = v[5] as ASTBlock;
            return ASTCatchClause(null, varName, block);
          });

  Parser<ASTStatement> statementSimple() =>
      (statementVariableDeclaration() | statementExpression())
          .cast<ASTStatement>();

  Parser<ASTStatementForLoop> statementForLoop() =>
      (string('for').trimHidden() &
              char('(').trimHidden() &
              ref0(statementSimple) &
              ref0(expression) &
              char(';').trimHidden() &
              ref0(expression) &
              char(')').trimHidden() &
              codeBlock())
          .map((v) {
            var initExp = v[2];
            var condExp = v[3];
            var contExp = v[5];
            var block = v[7];
            return ASTStatementForLoop(initExp, condExp, contExp, block);
          });

  Parser<ASTStatementForEach> statementForEach() =>
      (string('for').trimHidden() &
              char('(').trimHidden() &
              type().trimHidden() &
              ref0(identifier).trimHidden() &
              string('in').trimHidden() &
              ref0(expression) &
              char(')').trimHidden() &
              codeBlock())
          .map((v) {
            var variableType = v[2];
            var variableName = v[3];
            var iterableExp = v[5];
            var block = v[7];

            return ASTStatementForEach(
              variableType,
              variableName,
              iterableExp,
              block,
            );
          });

  Parser<ASTStatementWhileLoop> statementWhileLoop() =>
      (string('while').trimHidden() &
              char('(').trimHidden() &
              ref0(expression) &
              char(')').trimHidden() &
              codeBlock())
          .map((v) {
            var condExp = v[2];
            var block = v[4];
            return ASTStatementWhileLoop(condExp, block);
          });

  Parser<ASTStatementReturn> statementReturn() =>
      (string('return').trimHidden() &
              expression().optional() &
              char(';').trimHidden())
          .map((v) {
            var value = v[1];

            if (value == null) {
              return ASTStatementReturn();
            } else if (value is ASTExpression) {
              return _returnStatementForExpression(value);
            }

            throw UnsupportedError("Can't handle return value: $value");
          });

  /// Builds the appropriate `return <value>` statement for an expression
  /// (shared by `return …;` and the arrow body `=> …`).
  ASTStatementReturn _returnStatementForExpression(ASTExpression value) {
    if (value is ASTExpressionVariableAccess) {
      if (value.variable.name == 'null') {
        return ASTStatementReturnNull();
      } else {
        return ASTStatementReturnVariable(value.variable);
      }
    } else if (value is ASTExpressionLiteral) {
      return ASTStatementReturnValue(value.value);
    } else {
      return ASTStatementReturnWithExpression(value);
    }
  }

  /// Expression-bodied function/method body: `=> expr ;` desugars to a block
  /// with a single `return expr;`.
  Parser<ASTBlock> arrowBody() =>
      (string('=>').trimHidden() & ref0(expression) & char(';').trimHidden())
          .map((v) {
            var value = v[1] as ASTExpression;
            return ASTBlock(null)
              ..addAllStatements([_returnStatementForExpression(value)]);
          });

  Parser<ASTStatementExpression> statementExpression() =>
      (expression() & char(';').trimHidden()).map((v) {
        return ASTStatementExpression(v[0]);
      });

  /// Anonymous function / closure used as an expression: `(params) => expr` or
  /// `(params) { body }`. Parameters may be typed (`(int a)`) or untyped
  /// (`(a)`). Captures the enclosing scope at runtime.
  Parser<ASTExpression> expressionAnonymousFunction() =>
      (anonFunctionParameters() & (anonArrowBody() | codeBlock())).map((v) {
        var parameters = v[0] as ASTFunctionParametersDeclaration;
        var block = v[1] as ASTBlock;
        var f = ASTFunctionDeclaration(
          '',
          parameters,
          ASTTypeDynamic.instance,
          block: block,
          modifiers: ASTModifiers.modifierStatic,
        );
        return ASTExpressionLiteralFunction(f);
      });

  /// `=> expr` body for an anonymous function (no trailing `;`, unlike a
  /// declaration's [arrowBody]).
  Parser<ASTBlock> anonArrowBody() =>
      (string('=>').trimHidden() & ref0(expression)).map((v) {
        return ASTBlock(null)
          ..addAllStatements([_returnStatementForExpression(v[1])]);
      });

  Parser<ASTFunctionParametersDeclaration> anonFunctionParameters() =>
      (functionEmptyParametersDeclaration() | anonPositionalParameters())
          .cast<ASTFunctionParametersDeclaration>();

  Parser<ASTFunctionParametersDeclaration> anonPositionalParameters() =>
      (char('(').trimHidden() &
              anonParameter() &
              (char(',').trimHidden() & anonParameter()).star() &
              char(',').optional() &
              char(')').trimHidden())
          .map((v) {
            var params = <ASTFunctionParameterDeclaration>[v[1]];
            for (var e in (v[2] as List)) {
              params.add((e as List)[1] as ASTFunctionParameterDeclaration);
            }
            return ASTFunctionParametersDeclaration(params, null, null);
          });

  /// A single anonymous-function parameter: typed (`int a`) or untyped (`a`).
  Parser<ASTFunctionParameterDeclaration> anonParameter() =>
      ((type().trim() & identifier()) | identifier().trim()).map((v) {
        if (v is List) {
          return ASTFunctionParameterDeclaration(
            v[0] as ASTType,
            v[1] as String,
            -1,
            false,
          );
        }
        return ASTFunctionParameterDeclaration(
          ASTTypeDynamic.instance,
          v as String,
          -1,
          false,
        );
      });

  Parser<ASTStatementBlock> statementBlock() =>
      (codeBlock()).map((v) => ASTStatementBlock(v));

  Parser<ASTStatementFunctionDeclaration> statementFunctionDeclaration() =>
      (type().optional() &
              identifier() &
              functionParametersDeclaration() &
              codeBlock())
          .map((v) {
            var returnType = v[0] as ASTType? ?? ASTTypeDynamic.instance;
            var parameters = v[2];
            var name = v[1];
            var block = v[3];
            return ASTStatementFunctionDeclaration(
              ASTFunctionDeclaration(
                name,
                parameters,
                returnType,
                block: block,
                modifiers: ASTModifiers.modifierStatic,
              ),
            );
          });

  Parser<ASTStatementVariableDeclaration> statementVariableDeclaration() =>
      (
          // var definition:
          (
              // final Type name:
              ((finalToken() | constToken()).trimHidden() &
                      type() &
                      identifier().trimHidden()) |
                  // final name:
                  ((finalToken() | constToken()) & identifier().trimHidden()) |
                  // Type name:
                  (type() & identifier().trimHidden())
              // end var definition
              ) &
              (char('=').trimHidden() & ref0(expression)).optional() &
              char(';').trimHidden())
          .map((v) {
            var varDef = v[0] as List;

            bool unmodifiable;
            ASTType type;
            String name;

            if (varDef.length == 3) {
              unmodifiable = true;
              assert(['final', 'const'].contains((varDef[0] as Token).value));
              type = varDef[1];
              name = varDef[2];
            } else if (varDef.length == 2) {
              final varDef0 = varDef[0];
              if (varDef0 is Token &&
                  (varDef0.value == 'final' || varDef0.value == 'const')) {
                unmodifiable = true;
                type = getTypeByName(varDef0.value);
                name = varDef[1];
              } else {
                unmodifiable = false;
                type = varDef[0];
                name = varDef[1];
              }
            } else {
              throw StateError("Invalid var definition: $varDef");
            }

            var valueOpt = v[1];
            var value = valueOpt != null ? valueOpt[1] as ASTExpression : null;
            if (value != null) type.associateToType(value);
            return ASTStatementVariableDeclaration(
              type,
              name,
              value,
              unmodifiable: unmodifiable,
            );
          });

  Parser<ASTBranch> branch() =>
      (ref0(branchIfElseIfsElseBlock) |
              ref0(branchIfElseBlock) |
              ref0(branchIfBlock))
          .cast<ASTBranch>();

  Parser<ASTBranchIfBlock> branchIfBlock() =>
      (string('if').trimHidden() &
              char('(').trimHidden() &
              ref0(expression) &
              char(')').trimHidden() &
              codeBlockOrSingleLineBlock())
          .map((v) {
            var condition = v[2];
            var block = v[4];
            return ASTBranchIfBlock(condition, block);
          });

  Parser<ASTBranchIfElseBlock> branchIfElseBlock() =>
      (string('if').trimHidden() &
              char('(').trimHidden() &
              ref0(expression) &
              char(')').trimHidden() &
              codeBlock() &
              string('else').trimHidden() &
              codeBlock())
          .map((v) {
            var condition = v[2];
            var blockIf = v[4];
            var blockElse = v[6];
            return ASTBranchIfElseBlock(condition, blockIf, blockElse);
          });

  Parser<ASTBranchIfElseIfsElseBlock> branchIfElseIfsElseBlock() =>
      (string('if').trimHidden() &
              char('(').trimHidden() &
              ref0(expression) &
              char(')').trimHidden() &
              codeBlock() &
              ref0(branchElseIfs).plus() &
              (string('else').trimHidden() & codeBlock()).optional())
          .map((v) {
            var condition = v[2];
            var blockIf = v[4];
            var blockElseIfs = v[5] as List;
            var blockElse = v[6]?[1];

            return ASTBranchIfElseIfsElseBlock(
              condition,
              blockIf,
              blockElseIfs.cast<ASTBranchIfBlock>().toList(),
              blockElse,
            );
          });

  Parser<ASTBranchIfBlock> branchElseIfs() =>
      (string('else').trimHidden() &
              string('if').trimHidden() &
              char('(').trimHidden() &
              ref0(expression) &
              char(')').trimHidden() &
              codeBlock())
          .map((v) {
            var condition = v[3];
            var blockIf = v[5];
            return ASTBranchIfBlock(condition, blockIf);
          });

  @override
  Parser<ParsedString> parseExpressionInString() =>
      expression().map((e) => ParsedString.expression(e));

  @override
  Parser<ASTExpression> expression() =>
      (ref0(expressionOperationChain) &
              (char('?').trimHidden() &
                      ref0(expression) &
                      char(':').trimHidden() &
                      ref0(expression))
                  .optional())
          .map((v) {
            var base = v[0] as ASTExpression;
            var ternary = v[1] as List?;
            if (ternary == null) return base;
            return ASTExpressionConditional(
              base,
              ternary[1] as ASTExpression,
              ternary[3] as ASTExpression,
            );
          });

  Parser<ASTExpression> expressionOperationChain() =>
      (ref0(expressionNoOperation) &
              (expressionOperator() & ref0(expressionNoOperation)).star())
          .map((v) {
            var exp1 = v[0];

            var rest = v[1] as List;
            if (rest.isEmpty) {
              return exp1;
            }

            var extra = _expandListDeeply(rest);
            var all = <dynamic>[exp1, ...extra];

            return computeFinalExpression(all);
          });

  Parser<ASTExpressionOperator> expressionOperator() =>
      (char('+') |
              char('-') |
              char('*') |
              char('/') |
              string('~/') |
              string('==') |
              string('!=') |
              string('<<') |
              string('>>') |
              string('>=') |
              string('<=') |
              char('>') |
              char('<') |
              char('%') |
              string('&&') |
              string('||') |
              char('&') |
              char('|') |
              char('^'))
          .trimHidden()
          .map((v) {
            var op = getASTExpressionOperator(v);
            if (op == ASTExpressionOperator.divide) {
              return ASTExpressionOperator.divideAsDouble;
            }
            return op;
          });

  Parser<ASTExpressionAwait> expressionAwait() =>
      (awaitToken() & (ref0(expressionNoOperation) | ref0(expressionGroup)))
          .map((v) => ASTExpressionAwait(v[1] as ASTExpression));

  Parser<ASTExpression> expressionNoOperation() =>
      (expressionAwait() |
              expressionAnonymousFunction() |
              expressionNegate() |
              expressionBitwiseNot() |
              expressionLiteral() |
              expressionGroupFunctionInvocation() |
              expressionGroup() |
              expressionListEmptyLiteral() |
              expressionListLiteral() |
              expressionMapEmptyLiteral() |
              expressionMapLiteral() |
              expressionVariableDirectOperation() |
              expressionVariableEntryAssignment() |
              expressionObjectFieldAssignment() |
              expressionVariableAssigment() |
              expressionFunctionInvocation() |
              expressionObjectEntryFunctionInvocation() |
              expressionVariableEntryAccess() |
              expressionGetterAccess() |
              expressionNullValue() |
              expressionVariableAccess() |
              expressionNegative())
          .cast<ASTExpression>();

  Parser<ASTExpressionNegation> expressionNegate() =>
      (char('!').trimHidden() &
              (ref0(expressionNoOperation) | ref0(expressionGroup)))
          .map((v) {
            var exp = v[1] as ASTExpression;
            return ASTExpressionNegation(exp);
          });

  Parser<ASTExpressionNegative> expressionNegative() =>
      (char('-').trimHidden() &
              (ref0(expressionNoOperation) | ref0(expressionGroup)))
          .map((v) {
            var exp = v[1] as ASTExpression;
            return ASTExpressionNegative(exp);
          });

  Parser<ASTExpressionBitwiseNot> expressionBitwiseNot() =>
      (char('~').trimHidden() &
              (ref0(expressionNoOperation) | ref0(expressionGroup)))
          .map((v) {
            var exp = v[1] as ASTExpression;
            return ASTExpressionBitwiseNot(exp);
          });

  Parser<ASTExpression> expressionGroup() =>
      (char('(').trimHidden() & ref0(expression) & char(')').trimHidden()).map(
        (v) => v[1] as ASTExpression,
      );

  Parser<ASTExpressionGroupFunctionInvocation>
  expressionGroupFunctionInvocation() =>
      (ref0(expressionGroup) &
              char('.') &
              identifier() &
              char('(').trimHidden() &
              ref0(callArguments).optional() &
              char(')').trimHidden() &
              expressionChainFunctionInvocation().star())
          .map((v) {
            var expression = v[0] as ASTExpression;
            var name = v[2] as String;
            var argsRec =
                v[4]
                    as ({
                      List<ASTExpression> positional,
                      Map<String, ASTExpression>? named,
                    })?;
            var args = argsRec?.positional ?? <ASTExpression>[];
            var named = argsRec?.named;
            var chainFunctions = (v[6] as List)
                .whereType<ASTExpressionChainFunctionInvocation>()
                .toList();

            return ASTExpressionGroupFunctionInvocation(
              expression,
              name,
              args,
              chainFunctions,
            )..namedArguments = named;
          });

  Parser<ASTExpressionFunctionInvocation> expressionFunctionInvocation() =>
      // Optional `new` prefix for class instantiation (`new User()`); the
      // keyword is consumed and discarded — `new User()` and `User()` both
      // resolve to the class constructor via `ASTRoot.getFunction`.
      (newToken().optional() &
              (identifier() & char('.')).optional() &
              identifier() &
              ref0(typeArguments).optional() &
              char('(').trimHidden() &
              ref0(callArguments).optional() &
              char(')').trimHidden() &
              expressionChainFunctionInvocation().star())
          .map((v) {
            var objOpt = v[1] as List?;
            var obj = objOpt != null ? objOpt[0] as String : null;
            var name = v[2] as String;
            // v[3]: optional generic type arguments (`<int>`), discarded — the
            // constructor/function resolves by name.
            var argsRec =
                v[5]
                    as ({
                      List<ASTExpression> positional,
                      Map<String, ASTExpression>? named,
                    })?;
            var args = argsRec?.positional ?? <ASTExpression>[];
            var named = argsRec?.named;
            var chainFunctions = (v[7] as List)
                .whereType<ASTExpressionChainFunctionInvocation>()
                .toList();

            if (obj != null && obj != 'this') {
              var variable = ASTScopeVariable(obj);
              return ASTExpressionObjectFunctionInvocation(
                variable,
                name,
                args,
                chainFunctions,
              )..namedArguments = named;
            } else {
              return ASTExpressionLocalFunctionInvocation(
                name,
                args,
                chainFunctions,
              )..namedArguments = named;
            }
          });

  Parser<ASTExpressionGetterAccess> expressionGetterAccess() =>
      ((identifier() & char('.')) &
              identifier().trimHidden() &
              expressionChainFunctionInvocation().star())
          .map((v) {
            var obj = v[0] as String?;
            var name = v[2] as String;
            var chainFunctions = (v[3] as List)
                .whereType<ASTExpressionChainFunctionInvocation>()
                .toList();

            // `this.field` reads from the current instance; `obj.field` from the
            // named variable's instance.
            ASTVariable variable = obj == 'this'
                ? ASTThisVariable()
                : ASTScopeVariable(obj!);
            return ASTExpressionObjectGetterAccess(
              variable,
              name,
              chainFunctions,
            );
          });

  Parser<List<ASTExpression>> expressionSequence() =>
      (ref0(expression) & (char(',').trimHidden() & ref0(expression)).star())
          .map((v) {
            var list = _expandListDeeply(v);
            var expressions = list.whereType<ASTExpression>().toList();
            return expressions;
          });

  Parser<ASTExpressionNullValue> expressionNullValue() =>
      (nullToken()).map((v) {
        return ASTExpressionNullValue();
      });

  Parser<ASTExpressionVariableAccess> expressionVariableAccess() =>
      (variable()).map((v) {
        return ASTExpressionVariableAccess(v);
      });

  Parser<ASTExpressionLiteral> expressionLiteral() => (literal()).map((v) {
    return ASTExpressionLiteral(v);
  });

  Parser<ASTExpressionVariableEntryAccess> expressionVariableEntryAccess() =>
      (variable() & char('[') & ref0(expression) & char(']')).map((v) {
        var variable = v[0];
        var expression = v[2];
        return ASTExpressionVariableEntryAccess(variable, expression);
      });

  Parser<ASTExpressionObjectEntryFunctionInvocation>
  expressionObjectEntryFunctionInvocation() =>
      (variable() &
              char('[') &
              ref0(expression) &
              char(']') &
              char('.').trimHidden() &
              identifier() &
              char('(').trimHidden() &
              ref0(callArguments).optional() &
              char(')').trimHidden() &
              expressionChainFunctionInvocation().star())
          .map((v) {
            var variable = v[0];
            var expression = v[2];
            var fName = v[5];
            var argsRec =
                v[7]
                    as ({
                      List<ASTExpression> positional,
                      Map<String, ASTExpression>? named,
                    })?;
            var args = argsRec?.positional ?? <ASTExpression>[];
            var named = argsRec?.named;
            var chainFunctions = (v[9] as List)
                .whereType<ASTExpressionChainFunctionInvocation>()
                .toList();

            return ASTExpressionObjectEntryFunctionInvocation(
              variable,
              expression,
              fName,
              args,
              chainFunctions,
            )..namedArguments = named;
          });

  Parser<ASTExpressionChainFunctionInvocation>
  expressionChainFunctionInvocation() =>
      (char('.').trimHidden() &
              identifier() &
              char('(').trimHidden() &
              ref0(callArguments).optional() &
              char(')').trimHidden())
          .map((v) {
            var fName = v[1];
            var argsRec =
                v[3]
                    as ({
                      List<ASTExpression> positional,
                      Map<String, ASTExpression>? named,
                    })?;
            var args = argsRec?.positional ?? <ASTExpression>[];
            var named = argsRec?.named;
            return ASTExpressionChainFunctionInvocation(fName, args)
              ..namedArguments = named;
          });

  Parser<ASTExpressionListLiteral> expressionListEmptyLiteral() =>
      ((char('<').trimHidden() & simpleType() & char('>').trimHidden())
                  .optional() &
              char('[').trimHidden() &
              char(']').trimHidden())
          .map((v) {
            var type = (v[0]?[1] as ASTType?) ?? ASTTypeDynamic.instance;
            return ASTExpressionListLiteral(type, []);
          });

  Parser<ASTExpressionListLiteral> expressionListLiteral() =>
      ((char('<').trimHidden() & simpleType() & char('>').trimHidden())
                  .optional() &
              char('[').trimHidden() &
              ref0(expression) &
              (char(',').trimHidden() & ref0(expression)).star() &
              char(',').trimHidden().optional() &
              char(']').trimHidden())
          .map((v) {
            var type = v[0]?[1] as ASTType?;
            var v0 = v[2];
            var tail = (v[3] as List?) ?? [];

            var vs = <ASTExpression>[
              v0,
              ...tail.expand((e) => e).whereType<ASTExpression>(),
            ];

            if (type == null) {
              var vsTypeResolving = vs.map((e) => e.resolveType(null)).toList();
              var vsTypes = vsTypeResolving.whereType<ASTType>().toList();
              if (vsTypes.length == vsTypeResolving.length) {
                var commonType = vsTypes.isEmpty
                    ? ASTTypeDynamic.instance
                    : vsTypes.reduce(
                        (a, b) => a.commonType(b) ?? ASTTypeDynamic.instance,
                      );
                type = commonType;
              }
            }

            return ASTExpressionListLiteral(type, vs);
          });

  Parser<ASTExpressionMapLiteral> expressionMapEmptyLiteral() =>
      ((char('<').trimHidden() &
                      simpleType() &
                      char(',').trimHidden() &
                      simpleType() &
                      char('>').trimHidden())
                  .optional() &
              char('{').trimHidden() &
              char('}').trimHidden())
          .map((v) {
            var keyType = (v[0]?[1] as ASTType?) ?? ASTTypeDynamic.instance;
            var valueType = (v[0]?[2] as ASTType?) ?? ASTTypeDynamic.instance;
            return ASTExpressionMapLiteral(keyType, valueType, []);
          });

  Parser<ASTExpressionMapLiteral> expressionMapLiteral() =>
      ((char('<').trimHidden() &
                      simpleType() &
                      char(',').trimHidden() &
                      simpleType() &
                      char('>').trimHidden())
                  .optional() &
              char('{').trimHidden() &
              (expression() & char(':').trimHidden() & expression()) &
              (char(',').trimHidden() &
                      expression() &
                      char(':').trimHidden() &
                      expression())
                  .star() &
              char(',').trimHidden().optional() &
              char('}').trimHidden())
          .map((v) {
            // Leave the types null when there's no explicit `<K,V>` prefix, so
            // the literal infers them from its entries (mirrors list literals).
            var keyType = v[0]?[1] as ASTType?;
            var valueType = v[0]?[3] as ASTType?;
            var entry0 = (v[2] as List).whereType<ASTExpression>().toList();
            var entriesTail = (v[3] as List?)
                ?.whereType<List>()
                .map((l) => l.whereType<ASTExpression>().toList())
                .toList();

            var entries = [
              MapEntry(entry0[0], entry0[1]),
              ...?entriesTail?.map((e) => MapEntry(e[0], e[1])),
            ];

            return ASTExpressionMapLiteral(keyType, valueType, entries);
          });

  Parser<ASTExpressionVariableDirectOperation>
  expressionVariableDirectOperation() =>
      (expressionVariableDirectPosOperation() |
              expressionVariableDirectPreOperation())
          .cast<ASTExpressionVariableDirectOperation>();

  Parser<ASTExpressionVariableDirectOperation>
  expressionVariableDirectPosOperation() =>
      (variable() & (string('++') | string('--'))).map((v) {
        var variable = v[0];
        var operator = getASTAssignmentDirectOperator(v[1]);
        return ASTExpressionVariableDirectOperation(variable, operator, false);
      });

  Parser<ASTExpressionVariableDirectOperation>
  expressionVariableDirectPreOperation() =>
      ((string('++') | string('--')) & variable()).map((v) {
        var operator = getASTAssignmentDirectOperator(v[0]);
        var variable = v[1];
        return ASTExpressionVariableDirectOperation(variable, operator, true);
      });

  Parser<ASTExpressionVariableAssignment> expressionVariableAssigment() =>
      (variable() & assigmentOperator() & ref0(expression)).map((v) {
        return ASTExpressionVariableAssignment(v[0], v[1], v[2]);
      });

  Parser<ASTExpressionVariableEntryAssignment>
  expressionVariableEntryAssignment() =>
      (variable() &
              char('[') &
              ref0(expression) &
              char(']').trimHidden() &
              assigmentOperator() &
              ref0(expression))
          .map((v) {
            return ASTExpressionVariableEntryAssignment(v[0], v[2], v[4], v[5]);
          });

  /// `obj.field = value` (and `this.field = value`), including `+=` etc.
  Parser<ASTExpressionObjectSetterAssignment>
  expressionObjectFieldAssignment() =>
      (identifier() &
              char('.') &
              identifier().trimHidden() &
              assigmentOperator() &
              ref0(expression))
          .map((v) {
            var obj = v[0] as String;
            var name = v[2] as String;
            var op = v[3] as ASTAssignmentOperator;
            var valueExpr = v[4] as ASTExpression;
            ASTVariable variable = obj == 'this'
                ? ASTThisVariable()
                : ASTScopeVariable(obj);
            return ASTExpressionObjectSetterAssignment(
              variable,
              name,
              op,
              valueExpr,
            );
          });

  Parser<ASTAssignmentOperator> assigmentOperator() =>
      (char('=') |
              string('+=') |
              string('-=') |
              string('*=') |
              string('/=') |
              string('~/='))
          .trimHidden()
          .map((v) {
            return getASTAssignmentOperator(v);
          });

  Parser<ASTVariable> variable() =>
      (thisVariable() | scopeVariable()).cast<ASTVariable>();

  Parser<ASTThisVariable> thisVariable() => (token('this')).map((v) {
    return ASTThisVariable();
  });

  Parser<ASTScopeVariable> scopeVariable() => (identifier()).map((v) {
    return ASTScopeVariable(v);
  });

  Parser<ASTFunctionParametersDeclaration> functionParametersDeclaration() =>
      (functionEmptyParametersDeclaration() |
              functionFullParametersDeclaration())
          .cast<ASTFunctionParametersDeclaration>();

  Parser<ASTFunctionParametersDeclaration>
  functionEmptyParametersDeclaration() => (char('(') & char(')')).map((v) {
    return ASTFunctionParametersDeclaration(null, null, null);
  });

  /// Parses a full parameters declaration: optional positional parameters,
  /// optionally followed by a trailing `{named}` or `[optional]` group, e.g.
  /// `(int a, int b)`, `({int a, int b})`, `(int a, {int b})`, `(int a, [int b])`.
  Parser<ASTFunctionParametersDeclaration>
  functionFullParametersDeclaration() =>
      (char('(').trimHidden() &
              parametersList().optional() &
              (char(',').trimHidden().optional() & parameterGroup())
                  .optional() &
              char(',').trimHidden().optional() &
              char(')').trimHidden())
          .map((v) {
            var positional = v[1] as List<ASTFunctionParameterDeclaration>?;
            var groupOpt = v[2] as List?;

            List<ASTFunctionParameterDeclaration>? named;
            List<ASTFunctionParameterDeclaration>? optional;

            if (groupOpt != null) {
              var group =
                  groupOpt[1]
                      as ({
                        bool isNamed,
                        List<ASTFunctionParameterDeclaration> params,
                      });
              if (group.isNamed) {
                named = group.params;
              } else {
                optional = group.params;
              }
            }

            return ASTFunctionParametersDeclaration(
              positional,
              optional,
              named,
            );
          });

  /// A trailing parameter group: `{named}` or `[optional]`.
  Parser<({bool isNamed, List<ASTFunctionParameterDeclaration> params})>
  parameterGroup() => (namedParameterGroup() | optionalParameterGroup()).cast();

  Parser<({bool isNamed, List<ASTFunctionParameterDeclaration> params})>
  namedParameterGroup() =>
      (char('{').trimHidden() & parametersList() & char('}').trimHidden()).map((
        v,
      ) {
        return (
          isNamed: true,
          params: v[1] as List<ASTFunctionParameterDeclaration>,
        );
      });

  Parser<({bool isNamed, List<ASTFunctionParameterDeclaration> params})>
  optionalParameterGroup() =>
      (char('[').trimHidden() & parametersList() & char(']').trimHidden()).map((
        v,
      ) {
        return (
          isNamed: false,
          params: v[1] as List<ASTFunctionParameterDeclaration>,
        );
      });

  Parser<List<ASTFunctionParameterDeclaration>> parametersList() =>
      (parameterDeclaration() &
              (char(',') & parameterDeclaration()).star() &
              char(',').optional())
          .map((v) {
            var params = _expandListDeeply(v);
            return params.whereType<ASTFunctionParameterDeclaration>().toList();
          });

  Parser<ASTFunctionParameterDeclaration> parameterDeclaration() =>
      ((finalToken() | constToken()).trim().optional() &
              type().trim() &
              identifier() &
              parameterDefaultValue().optional())
          .map((v) {
            return ASTFunctionParameterDeclaration(
              v[1],
              v[2],
              -1,
              false,
              unmodifiable: v[0] != null,
            )..defaultValue = v[3] as ASTExpression?;
          });

  Parser<ASTType> type() =>
      (functionType() | typeNonFunction()).cast<ASTType>();

  /// Any type except a function type (used as the return type of a function
  /// type, and as the fallback when there is no trailing `Function(...)`).
  Parser<ASTType> typeNonFunction() =>
      (futureTyped() |
              arrayTyped() |
              arrayTypeDynamic() |
              mapTyped() |
              mapTypeDynamic() |
              simpleType())
          .cast<ASTType>();

  /// A function type: `[returnType] Function(<paramType> [name], ...)`, e.g.
  /// `int Function(int n)`, `void Function()`, or `Function(int n)` (return
  /// type omitted → `dynamic`).
  Parser<ASTType> functionType() =>
      (functionTypeWithReturn() | functionTypeNoReturn()).cast<ASTType>();

  Parser<ASTType> functionTypeWithReturn() =>
      (ref0(typeNonFunction) &
              string('Function').trim() &
              char('(').trimHidden() &
              functionTypeParameters().optional() &
              char(')').trimHidden())
          .map((v) {
            var returnType = v[0] as ASTType;
            var parameters = v[3] as List<ASTType>?;
            return ASTTypeFunction(returnType, parameters);
          });

  Parser<ASTType> functionTypeNoReturn() =>
      (string('Function').trim() &
              char('(').trimHidden() &
              functionTypeParameters().optional() &
              char(')').trimHidden())
          .map((v) {
            var parameters = v[2] as List<ASTType>?;
            return ASTTypeFunction(ASTTypeDynamic.instance, parameters);
          });

  Parser<List<ASTType>> functionTypeParameters() =>
      (functionTypeParameter() &
              (char(',').trimHidden() & functionTypeParameter()).star() &
              char(',').optional())
          .map((v) {
            var params = <ASTType>[v[0] as ASTType];
            for (var e in (v[1] as List)) {
              params.add((e as List)[1] as ASTType);
            }
            return params;
          });

  /// A single function-type parameter: a type with an optional (ignored) name,
  /// e.g. `int` or `int n`.
  Parser<ASTType> functionTypeParameter() =>
      (ref0(type) & identifier().trim().optional()).map((v) => v[0] as ASTType);

  Parser<ASTTypeFuture> futureTyped() =>
      (string('Future') &
              char('<').trimHidden() &
              ref0(type) &
              char('>').trimHidden())
          .map((v) {
            var t = v[2] as ASTType;
            return ASTTypeFuture(t);
          });

  Parser<ASTType> simpleType() =>
      // Guard against the `await` contextual keyword being read as a type name
      // (so `await x;` parses as an await expression, not a `await x` variable
      // declaration).
      (awaitToken().not() & identifier()).map((v) {
        var name = v[1] as String;
        // A class type parameter (`T`) is erased to `dynamic`.
        if (_classTypeParameters.contains(name)) {
          return ASTTypeDynamic.instance;
        }
        return getTypeByName(name);
      });

  Parser<ASTTypeArray> arrayTyped() =>
      (array3DTyped() | array2DTyped() | array1DTyped()).cast<ASTTypeArray>();

  Parser<ASTTypeArray> array1DTyped() =>
      (string('List') & char('<') & simpleType() & char('>')).map((v) {
        var t = v[2] as ASTType;
        return ASTTypeArray(t);
      });

  Parser<ASTTypeArray2D> array2DTyped() =>
      (string('List') &
              char('<') &
              string('List') &
              char('<') &
              simpleType() &
              char('>') &
              char('>'))
          .map((v) {
            var t = v[4] as ASTType;
            return ASTTypeArray2D.fromElementType(t);
          });

  Parser<ASTTypeArray3D> array3DTyped() =>
      (string('List') &
              char('<') &
              string('List') &
              char('<') &
              string('List') &
              char('<') &
              simpleType() &
              char('>') &
              char('>') &
              char('>'))
          .map((v) {
            var t = v[4] as ASTType;
            return ASTTypeArray3D.fromElementType(t);
          });

  Parser<ASTTypeArray> arrayTypeDynamic() =>
      (array3DTypeDynamic() | array2DTypeDynamic() | array1DTypeDynamic())
          .cast<ASTTypeArray>();

  Parser<ASTTypeArray> array1DTypeDynamic() => string('List').map((v) {
    return ASTTypeArray.instanceOfDynamic;
  });

  Parser<ASTTypeArray2D> array2DTypeDynamic() =>
      (string('List') & char('<').trim() & string('List') & char('>').trim())
          .map((v) {
            return ASTTypeArray2D.fromElementType(ASTTypeDynamic.instance);
          });

  Parser<ASTTypeArray3D> array3DTypeDynamic() =>
      (string('List') &
              char('<') &
              string('List') &
              char('<') &
              string('List') &
              char('>') &
              char('>'))
          .map((v) {
            return ASTTypeArray3D.fromElementType(ASTTypeDynamic.instance);
          });

  Parser<ASTTypeMap> mapTyped() =>
      (string('Map') &
              char('<').trim() &
              (arrayTyped() | simpleType()).cast<ASTType>() &
              char(',').trim() &
              (arrayTyped() | simpleType()).cast<ASTType>() &
              char('>').trim())
          .map((v) {
            var key = v[2] as ASTType;
            var val = v[4] as ASTType;
            return ASTTypeMap(key, val);
          });

  Parser<ASTTypeMap> mapTypeDynamic() => string('Map').map((v) {
    return ASTTypeMap.instanceOfDynamicOfDynamic;
  });

  Parser<ASTValue> literal() => (literalBool() | literalNum() | literalString())
      .trimHidden()
      .cast<ASTValue>();

  Parser<ASTValueBool> literalBool() =>
      (string('true') | string('false').trim()).map((v) {
        return ASTValueBool(v == 'true');
      });

  Parser<ASTValueNum> literalNum() =>
      (char('-').optional() & numberLexicalToken()).trim().map((v) {
        var negative = v[0] == '-';
        var value = v[1];
        return ASTValueNum.from(value, negative: negative);
      });

  Parser<ASTValue<String>> literalString() =>
      (stringLexicalToken()).plus().map((l) {
        if (l.length == 1) {
          var v = l[0];
          return v.asValue();
        } else {
          var values = l.map((e) => e.asValue()).toList();
          return ASTValueStringConcatenation(values);
        }
      });

  static List _expandListDeeply(List l) {
    if (l.isEmpty) return l;
    if (l.length == 1 && l[0] is! List) return l;

    final result = [];
    _expandInto(l, result);
    return result;
  }

  static void _expandInto(List source, List target) {
    for (final e in source) {
      if (e is List) {
        _expandInto(e, target);
      } else {
        target.add(e);
      }
    }
  }
}
