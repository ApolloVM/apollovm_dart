// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:async_extension/async_extension.dart';
import 'package:collection/collection.dart'
    show equalsIgnoreAsciiCase, ListEquality;

import '../apollovm_base.dart';
import 'apollovm_ast_base.dart';
import 'apollovm_ast_expression.dart';
import 'apollovm_ast_toplevel.dart';
import 'apollovm_ast_type.dart';
import 'apollovm_ast_value.dart';
import 'apollovm_ast_variable.dart';

/// An AST Statement.
abstract class ASTStatement with ASTNode implements ASTCodeRunner {
  ASTNode? _parentNode;

  @override
  ASTNode? get parentNode => _parentNode;

  @override
  void resolveNode(ASTNode? parentNode) {
    _parentNode = parentNode;

    cacheDescendantChildren();
  }

  @override
  ASTNode? getNodeIdentifier(String name, {ASTNode? requester}) =>
      parentNode?.getNodeIdentifier(name, requester: requester);

  @override
  VMContext defineRunContext(VMContext parentContext) {
    return parentContext;
  }

  @override
  FutureOr<ASTType> resolveRuntimeType(VMContext context, ASTNode? node) =>
      resolveType(context);

  @override
  void associateToType(ASTTypedNode node) {}
}

/// The kind of an [ASTImportCombinator]: a `show` (allow-list) or `hide`
/// (deny-list) clause on an import/export.
enum ASTImportCombinatorKind { show, hide }

/// A `show`/`hide` clause on an import or export, e.g. `show User, Role` or
/// `hide Internal`. Language-agnostic: Dart `show`/`hide`, and the effect of
/// TS/Python selective imports, normalize into this.
class ASTImportCombinator {
  final ASTImportCombinatorKind kind;
  final List<String> names;

  const ASTImportCombinator(this.kind, this.names);

  bool get isShow => kind == ASTImportCombinatorKind.show;

  bool get isHide => kind == ASTImportCombinatorKind.hide;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ASTImportCombinator &&
          kind == other.kind &&
          const ListEquality<String>().equals(names, other.names);

  @override
  int get hashCode => kind.hashCode ^ const ListEquality<String>().hash(names);

  @override
  String toString() =>
      '${isShow ? 'show' : 'hide'} ${names.join(', ')}';
}

/// A single imported/exported symbol with an optional local alias, e.g.
/// `User as U` (TS `{ User as U }`, Dart `show User`, Python
/// `from x import User as U`). [localName] is the name the symbol is bound to
/// in the importing module.
class ASTImportedSymbol {
  /// The original exported name in the source module.
  final String name;

  /// The local binding name (`null` means same as [name]).
  final String? alias;

  const ASTImportedSymbol(this.name, {this.alias});

  String get localName => alias ?? name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ASTImportedSymbol && name == other.name && alias == other.alias;

  @override
  int get hashCode => Object.hash(name, alias);

  @override
  String toString() => alias != null ? '$name as $alias' : name;
}

/// [ASTStatement] to import a package/library/module.
///
/// This is the canonical, language-agnostic import node. Each language's
/// syntax normalizes into these fields:
/// - Dart `import 'user.dart' show User;` → [namedSymbols] `[User]` (+ [combinators]).
/// - TypeScript `import { User } from './user';` → [namedSymbols] `[User]`.
/// - Python `from user import User` → [namedSymbols] `[User]`.
/// - `import 'x' as p;` / `import * as p` → [prefix] `p` (+ [wildcard]).
class ASTStatementImport extends ASTStatement {
  final String path;

  /// Whole-module alias/prefix (`import 'x' as p`, `import * as p`).
  final String? prefix;

  /// Whole-namespace/wildcard import (`import foo.bar.*`, TS `import * as p`).
  final bool wildcard;

  /// `show`/`hide` clauses (order-preserving), used mainly for exact round-trip
  /// generation. The resolver treats [namedSymbols] as the authoritative
  /// selective allow-list.
  final List<ASTImportCombinator> combinators;

  /// Explicitly imported symbols with optional aliases
  /// (`{ User as U }`, `show User`, `from x import User as U`).
  final List<ASTImportedSymbol> namedSymbols;

  ASTStatementImport(
    this.path, {
    this.prefix,
    this.wildcard = false,
    this.combinators = const [],
    this.namedSymbols = const [],
  });

  /// `true` if this import selects a subset of the target's exported symbols
  /// (via `show`/named). A plain import (or a `hide`-only import) is not
  /// selective in this sense.
  bool get isSelective => namedSymbols.isNotEmpty || combinators.any((c) => c.isShow);

  /// Whether [exported] (a symbol name in the target module) is visible through
  /// this import, applying [namedSymbols] (allow-list) then `show`/`hide`
  /// combinators.
  bool importsSymbol(String exported) {
    if (namedSymbols.isNotEmpty) {
      return namedSymbols.any((s) => s.name == exported);
    }

    var visible = true;
    for (var c in combinators) {
      if (c.isShow) {
        visible = c.names.contains(exported);
      } else {
        if (c.names.contains(exported)) visible = false;
      }
    }
    return visible;
  }

  /// The local binding name for an [exported] symbol (applies per-symbol
  /// aliases from [namedSymbols]); defaults to [exported].
  String localNameOf(String exported) {
    for (var s in namedSymbols) {
      if (s.name == exported) return s.localName;
    }
    return exported;
  }

  @override
  Iterable<ASTNode> get children => [];

  @override
  FutureOr<ASTValueVoid> run(VMContext parentContext, ASTRunStatus runStatus) {
    // Core packages (e.g. `dart:math`) register their functions at runtime via
    // `context.import`. Cross-module imports are linked statically by the
    // module resolver, so they have no runtime effect here — a path that
    // resolves to neither is reported by the resolver as a `missingModule`
    // diagnostic rather than thrown at run time.
    return parentContext.import(path).resolveMapped((_) => ASTValueVoid.instance);
  }

  @override
  FutureOr<ASTType> resolveType(VMContext? context) => ASTTypeVoid.instance;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ASTStatementImport &&
          runtimeType == other.runtimeType &&
          path == other.path &&
          prefix == other.prefix &&
          wildcard == other.wildcard &&
          const ListEquality<ASTImportCombinator>()
              .equals(combinators, other.combinators) &&
          const ListEquality<ASTImportedSymbol>()
              .equals(namedSymbols, other.namedSymbols);

  @override
  int get hashCode =>
      path.hashCode ^
      prefix.hashCode ^
      wildcard.hashCode ^
      const ListEquality<ASTImportCombinator>().hash(combinators) ^
      const ListEquality<ASTImportedSymbol>().hash(namedSymbols);

  @override
  String toString() {
    final prefix = this.prefix;
    return [
      'import "$path"',
      if (namedSymbols.isNotEmpty)
        ' show ${namedSymbols.join(', ')}'
      else
        for (var c in combinators) ' $c',
      if (prefix != null) ' as $prefix',
      ';',
    ].join();
  }
}

/// [ASTStatement] to export (or re-export) symbols from a module.
///
/// - [path] `null`: re-export of this module's own symbols (`export { A, B };`).
/// - [path] non-null: re-export from another module (`export * from './x';`,
///   `export { A } from './x';`).
/// - [symbols] empty with a [path]: export everything from [path] (barrel).
///
/// Exports are resolved statically by the module resolver; [run] is a runtime
/// no-op so this node round-trips through generation without affecting execution.
class ASTStatementExport extends ASTStatement {
  /// Source module to re-export from (`null` = this module's own symbols).
  final String? path;

  /// Explicitly exported/renamed symbols (empty = export all, esp. with [path]).
  final List<ASTImportedSymbol> symbols;

  /// `show`/`hide` clauses applied to the re-export.
  final List<ASTImportCombinator> combinators;

  ASTStatementExport({
    this.path,
    this.symbols = const [],
    this.combinators = const [],
  });

  @override
  Iterable<ASTNode> get children => [];

  @override
  FutureOr<ASTValueVoid> run(VMContext parentContext, ASTRunStatus runStatus) =>
      ASTValueVoid.instance;

  @override
  FutureOr<ASTType> resolveType(VMContext? context) => ASTTypeVoid.instance;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ASTStatementExport &&
          runtimeType == other.runtimeType &&
          path == other.path &&
          const ListEquality<ASTImportedSymbol>().equals(symbols, other.symbols) &&
          const ListEquality<ASTImportCombinator>()
              .equals(combinators, other.combinators);

  @override
  int get hashCode =>
      path.hashCode ^
      const ListEquality<ASTImportedSymbol>().hash(symbols) ^
      const ListEquality<ASTImportCombinator>().hash(combinators);

  @override
  String toString() {
    return [
      'export',
      if (symbols.isNotEmpty) ' { ${symbols.join(', ')} }',
      for (var c in combinators) ' $c',
      if (path != null) ' "$path"',
      ';',
    ].join();
  }
}

/// An AST Block of code (statements).
class ASTBlock extends ASTStatement {
  ASTBlock? parentBlock;

  ASTBlock(this.parentBlock);

  @override
  Iterable<ASTNode> get children => [..._functions.values, ..._statements];

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    for (var e in _statements) {
      e.resolveNode(this);
    }

    for (var e in _functions.values) {
      e.resolveNode(this);
    }
  }

  @override
  ASTNode? getNodeIdentifier(String name, {ASTNode? requester}) {
    var f = _functions[name];
    if (f != null) return f;

    return parentNode?.getNodeIdentifier(name, requester: requester);
  }

  //// Getters:

  final Map<String, ASTGetterDeclaration> _getters = {};

  List<ASTGetterDeclaration> get getter => _getters.values.toList();

  List<String> get getterNames => _getters.keys.toList();

  void addGetter(ASTGetterDeclaration g) {
    var name = g.name;
    g.parentBlock = this;
    _getters[name] = g;
  }

  void addAllGetters(Iterable<ASTGetterDeclaration> gs) {
    for (var g in gs) {
      addGetter(g);
    }
  }

  ASTGetterDeclaration? getGetterWithName(
    String name, {
    bool caseInsensitive = false,
  }) {
    var g = _getters[name];

    if (g == null && caseInsensitive) {
      for (var entry in _getters.entries) {
        if (equalsIgnoreAsciiCase(entry.key, name)) {
          g = entry.value;
          break;
        }
      }
    }

    return g;
  }

  ASTGetterDeclaration? getGetter(
    String fName,
    VMContext context, {
    bool caseInsensitive = false,
  }) {
    var g = getGetterWithName(fName, caseInsensitive: caseInsensitive);
    if (g != null) return g;

    var gExternal = context.getMappedExternalGetter(fName);

    return gExternal;
  }

  //// Functions

  final Map<String, ASTFunctionSet> _functions = {};

  List<ASTFunctionSet> get functions => _functions.values.toList();

  List<String> get functionsNames => _functions.keys.toList();

  void addFunction(ASTFunctionDeclaration f) {
    var name = f.name;
    f.parentBlock = this;

    var set = _functions[name];
    if (set == null) {
      _functions[name] = ASTFunctionSetSingle(f);
    } else {
      // Idempotent: a local function declaration is re-registered on every
      // execution (see `ASTStatementFunctionDeclaration.run`); without this
      // guard the same declaration would accumulate in the set, corrupting the
      // AST and duplicating it in regenerated code.
      if (set.functions.any((e) => identical(e, f))) return;
      var set2 = set.add(f);
      if (!identical(set, set2)) {
        _functions[name] = set2;
      }
    }
  }

  void addAllFunctions(Iterable<ASTFunctionDeclaration> fs) {
    for (var f in fs) {
      addFunction(f);
    }
  }

  ASTFunctionSet? getFunctionWithName(
    String name, {
    bool caseInsensitive = false,
  }) {
    var f = _functions[name];

    if (f == null && caseInsensitive) {
      for (var entry in _functions.entries) {
        if (equalsIgnoreAsciiCase(entry.key, name)) {
          f = entry.value;
          break;
        }
      }
    }

    return f;
  }

  bool containsFunctionWithName(String name, {bool caseInsensitive = false}) {
    var set = getFunctionWithName(name, caseInsensitive: caseInsensitive);
    return set != null;
  }

  ASTInvocableDeclaration? getFunction(
    String fName,
    ASTFunctionSignature parametersSignature,
    VMContext context, {
    bool caseInsensitive = false,
  }) {
    var set = getFunctionWithName(fName, caseInsensitive: caseInsensitive);
    if (set != null) return set.get(parametersSignature, false);

    var fImported = context.getImportedFunction(fName, parametersSignature);
    if (fImported != null) return fImported;

    var fExternal = context.getMappedExternalFunction(
      fName,
      parametersSignature,
    );

    return fExternal;
  }

  ASTType<T>? getFunctionReturnType<T>(
    String name,
    ASTFunctionSignature parametersTypes,
    VMContext context,
  ) => getFunction(name, parametersTypes, context)?.returnType as ASTType<T>?;

  //// Statements

  final List<ASTStatement> _statements = [];

  List<ASTStatement> get statements => _statements.toList();

  void set(ASTBlock? other) {
    if (other == null) return;

    _functions.clear();
    addAllFunctions(other._functions.values.expand((e) => e.functions));

    _statements.clear();
    addAllStatements(other._statements);
  }

  void addStatement(ASTStatement statement) {
    _statements.add(statement);
    if (statement is ASTBlock) {
      statement.parentBlock = this;
    }
  }

  void addAllStatements(Iterable<ASTStatement> statements) {
    for (var stm in statements) {
      addStatement(stm);
    }
  }

  @override
  VMContext defineRunContext(VMContext parentContext) {
    return parentContext;
  }

  @override
  FutureOr<ASTValue> run(
    VMContext parentContext,
    ASTRunStatus runStatus,
  ) async {
    var blockContext = defineRunContext(parentContext);

    FutureOr<ASTValue> returnValue = ASTValueVoid.instance;

    for (var stm in _statements) {
      var ret = await stm.run(blockContext, runStatus);

      if (runStatus.returned) {
        return (runStatus.returnedFutureValue ?? runStatus.returnedValue)!;
      }

      // A `break`/`continue` interrupts this block and propagates up to the
      // enclosing loop/switch, which consumes the corresponding flag.
      if (runStatus.broke || runStatus.continued) {
        return ret;
      }

      returnValue = ret;
    }

    return returnValue;
  }

  @override
  ASTType resolveType(VMContext? context) => ASTTypeDynamic.instance;

  ASTClassField? getField(String name, {bool caseInsensitive = false}) =>
      parentBlock?.getField(name, caseInsensitive: caseInsensitive);

  @override
  String toString() {
    var str = StringBuffer();

    str.write('{\n');

    for (var stm in _statements) {
      str.write('$stm\n');
    }

    str.write('}');

    return str.toString();
  }
}

class ASTSingleLineStatementBlock extends ASTBlock {
  ASTSingleLineStatementBlock(super.parentBlock);

  @override
  void addStatement(ASTStatement statement) {
    if (_statements.isNotEmpty) {
      throw StateError(
        "Block already with a statement: only a single statement is allowed!",
      );
    }
    super.addStatement(statement);
  }

  @override
  String toString() {
    var stm = _statements.single;
    return stm.toString();
  }
}

abstract class ASTStatementTyped extends ASTStatement implements ASTTypedNode {}

class ASTStatementValue extends ASTStatementTyped {
  ASTValue value;

  ASTStatementValue(ASTBlock block, this.value) : super();

  @override
  Iterable<ASTNode> get children => [value];

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    value.resolveNode(parentNode);
  }

  @override
  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus) {
    var context = defineRunContext(parentContext);
    return value.getValue(context) as FutureOr<ASTValue>;
  }

  @override
  FutureOr<ASTType> resolveType(VMContext? context) =>
      value.resolveType(context);
}

enum ASTAssignmentOperator {
  set('='),
  multiply('*'),
  divide('/'),
  divideAsInt('~/'),
  sum('+'),
  subtract('-');

  final String symbol;

  const ASTAssignmentOperator(this.symbol);

  ASTExpressionOperator? get asASTExpressionOperator {
    switch (this) {
      case sum:
        return ASTExpressionOperator.add;
      case subtract:
        return ASTExpressionOperator.subtract;
      case multiply:
        return ASTExpressionOperator.multiply;
      case divide:
        return ASTExpressionOperator.divide;
      case divideAsInt:
        return ASTExpressionOperator.divideAsInt;
      default:
        return null;
    }
  }
}

ASTAssignmentOperator getASTAssignmentOperator(String op) {
  op = op.trim();

  switch (op) {
    case '=':
      return ASTAssignmentOperator.set;
    case '*=':
      return ASTAssignmentOperator.multiply;
    case '/=':
      return ASTAssignmentOperator.divide;
    case '+=':
      return ASTAssignmentOperator.sum;
    case '-=':
      return ASTAssignmentOperator.subtract;
    default:
      throw UnsupportedError(op);
  }
}

String getASTAssignmentOperatorText(ASTAssignmentOperator op) {
  switch (op) {
    case ASTAssignmentOperator.set:
      return '=';
    case ASTAssignmentOperator.multiply:
      return '*=';
    case ASTAssignmentOperator.divide:
      return '/=';
    case ASTAssignmentOperator.divideAsInt:
      return '~/=';
    case ASTAssignmentOperator.sum:
      return '+=';
    case ASTAssignmentOperator.subtract:
      return '-=';
  }
}

ASTAssignmentOperator getASTAssignmentDirectOperator(String op) {
  op = op.trim();

  switch (op) {
    case '++':
      return ASTAssignmentOperator.sum;
    case '--':
      return ASTAssignmentOperator.subtract;
    default:
      throw UnsupportedError(op);
  }
}

String getASTAssignmentDirectOperatorText(ASTAssignmentOperator op) {
  switch (op) {
    case ASTAssignmentOperator.sum:
      return '++';
    case ASTAssignmentOperator.subtract:
      return '--';
    default:
      throw UnsupportedError('$op');
  }
}

class ASTStatementExpression extends ASTStatement {
  ASTExpression expression;

  ASTStatementExpression(this.expression);

  @override
  Iterable<ASTNode> get children => [expression];

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    expression.resolveNode(parentNode);
  }

  @override
  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus) {
    var context = defineRunContext(parentContext);
    return expression.run(context, runStatus);
  }

  @override
  FutureOr<ASTType> resolveType(VMContext? context) =>
      expression.resolveType(context);

  @override
  String toString() {
    return '$expression ;';
  }
}

class ASTStatementBlock extends ASTStatement {
  ASTBlock block;

  ASTStatementBlock(this.block);

  @override
  Iterable<ASTNode> get children => block.children;

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    block.resolveNode(parentNode);
  }

  @override
  VMContext defineRunContext(VMContext parentContext) {
    return VMScopeContext(block, parent: parentContext);
  }

  @override
  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus) {
    var context = defineRunContext(parentContext);
    return block.run(context, runStatus);
  }

  @override
  FutureOr<ASTType> resolveType(VMContext? context) =>
      block.resolveType(context);

  @override
  String toString() {
    return block.toString();
  }
}

class ASTStatementFunctionDeclaration extends ASTStatement {
  ASTFunctionDeclaration functionDeclaration;

  ASTStatementFunctionDeclaration(this.functionDeclaration);

  @override
  Iterable<ASTNode> get children => functionDeclaration.children;

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    functionDeclaration.resolveNode(parentNode);
  }

  @override
  FutureOr<ASTValueFunction> run(
    VMContext parentContext,
    ASTRunStatus runStatus,
  ) {
    parentContext.block.addFunction(functionDeclaration);
    return functionDeclaration.toASTValueFunction(parentContext);
  }

  @override
  FutureOr<ASTType> resolveType(VMContext? context) => ASTTypeFunction();

  @override
  String toString() {
    return functionDeclaration.toString();
  }
}

/// [ASTStatement] to return void.
class ASTStatementReturn extends ASTStatement {
  @override
  Iterable<ASTNode> get children => [];

  @override
  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus) {
    return runStatus.returnVoid();
  }

  @override
  FutureOr<ASTType> resolveType(VMContext? context) => ASTTypeVoid.instance;

  @override
  String toString() {
    return 'return;';
  }
}

/// [ASTStatement] to return null.
class ASTStatementReturnNull extends ASTStatementReturn
    implements ASTStatementTyped {
  @override
  Iterable<ASTNode> get children => [];

  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    return runStatus.returnNull();
  }

  @override
  ASTType resolveType(VMContext? context) => ASTTypeNull.instance;

  @override
  String toString() {
    return 'return null ;';
  }
}

/// [ASTStatement] to return a [value].
class ASTStatementReturnValue extends ASTStatementReturn
    implements ASTStatementTyped {
  ASTValue value;

  ASTStatementReturnValue(this.value);

  @override
  Iterable<ASTNode> get children => [value];

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    value.resolveNode(parentNode);
  }

  @override
  ASTValue run(VMContext parentContext, ASTRunStatus runStatus) {
    return runStatus.returnValue(value);
  }

  @override
  FutureOr<ASTType> resolveType(VMContext? context) =>
      value.resolveType(context);

  @override
  String toString() {
    return 'return $value ;';
  }
}

/// [ASTStatement] to return a [variable].
class ASTStatementReturnVariable extends ASTStatementReturn
    implements ASTStatementTyped {
  ASTVariable variable;

  ASTStatementReturnVariable(this.variable);

  @override
  Iterable<ASTNode> get children => [variable];

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    variable.resolveNode(parentNode);
  }

  @override
  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus) {
    var value = variable.getValue(parentContext);
    return runStatus.returnFutureOrValue(value);
  }

  @override
  FutureOr<ASTType> resolveType(VMContext? context) =>
      variable.resolveType(context);

  @override
  String toString() {
    return 'return $variable ;';
  }
}

/// [ASTStatement] to return an [expression].
class ASTStatementReturnWithExpression extends ASTStatementReturn
    implements ASTStatementTyped {
  ASTExpression expression;

  ASTStatementReturnWithExpression(this.expression);

  @override
  Iterable<ASTNode> get children => [expression];

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    expression.resolveNode(parentNode);
  }

  @override
  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus) {
    var value = expression.run(parentContext, runStatus);
    return runStatus.returnFutureOrValue(value);
  }

  @override
  FutureOr<ASTType> resolveType(VMContext? context) =>
      expression.resolveType(context);

  @override
  String toString() {
    return 'return $expression ;';
  }
}

/// [ASTStatement] that declares a scope variable.
class ASTStatementVariableDeclaration<V> extends ASTStatementTyped {
  ASTType<V> type;

  String name;

  ASTExpression? value;

  bool unmodifiable;

  ASTStatementVariableDeclaration(
    this.type,
    this.name,
    this.value, {
    this.unmodifiable = false,
  }) {
    final value = this.value;

    if (value is ASTExpressionListLiteral) {
      var valueComponentType = value.type;
      if (valueComponentType != null) {
        // Resolve the type of the list literal:
        var valueType = value.resolveType(null);

        // If the resolved type is valid but NOT directly assignable
        // to the declared variable type, attempt to fix or reject it
        if (valueType is ASTType && !type.acceptsType(valueType)) {
          var typeGenerics = type.generics?.firstOrNull;
          if (typeGenerics != null && valueType.acceptsType(type)) {
            var value2 = ASTExpressionListLiteral(
              typeGenerics,
              value.valuesExpressions,
            );
            // Replace the original value with the adjusted one
            this.value = value2;
          } else {
            // Types are incompatible → fail fast
            throw ApolloVMCastException(
              "Can't cast value type ($valueType) to variable type ($type)",
            );
          }
        }
      }
    }
  }

  @override
  Iterable<ASTNode> get children => [type, ?value];

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    value?.resolveNode(this);
  }

  @override
  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus) {
    return type.resolveType(parentContext).resolveMapped((
      variableResolvedType,
    ) {
      return _runImpl(parentContext, runStatus, variableResolvedType);
    });
  }

  Future<ASTValue<dynamic>> _runImpl(
    VMContext parentContext,
    ASTRunStatus runStatus,
    ASTType variableResolvedType,
  ) async {
    var value = this.value;
    if (value != null) {
      return value.resolveRuntimeType(parentContext, value).resolveMapped((
        valueResolvedType,
      ) {
        return _runImpl2(
          parentContext,
          variableResolvedType,
          valueResolvedType,
          runStatus,
          value,
        );
      });
    } else {
      var initValue = ASTValueNull.instance;
      parentContext.declareVariableWithValue(
        variableResolvedType,
        name,
        initValue,
      );
      return initValue;
    }
  }

  Future<ASTValue<dynamic>> _runImpl2(
    VMContext parentContext,
    ASTType variableResolvedType,
    ASTType valueResolvedType,
    ASTRunStatus runStatus,
    ASTExpression value,
  ) async {
    if (valueResolvedType != ASTTypeDynamic.instance &&
        !valueResolvedType.canCastToType(variableResolvedType)) {
      throw ApolloVMRuntimeError(
        "Can't cast value type ($valueResolvedType) to variable type ($variableResolvedType).",
      );
    }

    var initValue = await value.run(parentContext, runStatus);

    if (!(await initValue.isInstanceOfAsync(variableResolvedType))) {
      throw ApolloVMRuntimeError(
        "Can't cast initial ($initValue) value to type: $variableResolvedType",
      );
    }

    parentContext.declareVariableWithValue(
      variableResolvedType,
      name,
      initValue,
    );
    return initValue;
  }

  @override
  FutureOr<ASTType> resolveType(VMContext? context) {
    final value = this.value;
    if (value != null && type is ASTTypeVar) {
      return value.resolveType(context);
    }

    return type.resolveType(context);
  }

  @override
  String toString() {
    if (value != null) {
      return '$type $name = $value ;';
    } else {
      return '$type $name;';
    }
  }
}

/// [ASTStatement] base for branches.
abstract class ASTBranch extends ASTStatement {
  FutureOr<bool> evaluateCondition(
    VMContext parentContext,
    ASTRunStatus runStatus,
    ASTExpression condition,
  ) async {
    var evaluation = await condition.run(parentContext, runStatus);
    var evalValue = await evaluation.getValue(parentContext);

    if (evalValue is! bool) {
      throw ApolloVMRuntimeError(
        'A branch condition should return a boolean: $evalValue',
      );
    }

    return evalValue;
  }

  @override
  ASTType resolveType(VMContext? context) => ASTTypeVoid.instance;
}

/// [ASTBranch] simple IF: `if (exp) {}`
class ASTBranchIfBlock extends ASTBranch {
  ASTExpression condition;
  ASTBlock block;

  ASTBranchIfBlock(this.condition, this.block);

  @override
  Iterable<ASTNode> get children => [condition, block];

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    condition.resolveNode(parentNode);
    block.resolveNode(parentNode);
  }

  @override
  FutureOr<ASTValue> run(
    VMContext parentContext,
    ASTRunStatus runStatus,
  ) async {
    var evalValue = await evaluateCondition(
      parentContext,
      runStatus,
      condition,
    );

    if (evalValue) {
      await block.run(parentContext, runStatus);
    }

    return ASTValueVoid.instance;
  }

  @override
  String toString() {
    return 'if ( $condition ) $block';
  }
}

/// [ASTBranch] IF,ELSE: `if (exp) {} else {}`
class ASTBranchIfElseBlock extends ASTBranch {
  ASTExpression condition;
  ASTBlock blockIf;
  ASTBlock? blockElse;

  ASTBranchIfElseBlock(this.condition, this.blockIf, this.blockElse);

  @override
  Iterable<ASTNode> get children => [condition, blockIf, ?blockElse];

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    condition.resolveNode(parentNode);
    blockIf.resolveNode(parentNode);
    blockElse?.resolveNode(parentNode);
  }

  @override
  FutureOr<ASTValue> run(
    VMContext parentContext,
    ASTRunStatus runStatus,
  ) async {
    var evalValue = await evaluateCondition(
      parentContext,
      runStatus,
      condition,
    );

    if (evalValue) {
      await blockIf.run(parentContext, runStatus);
    } else {
      await blockElse?.run(parentContext, runStatus);
    }

    return ASTValueVoid.instance;
  }

  @override
  String toString() {
    return 'if ( $condition ) $blockIf\nelse $blockElse';
  }
}

/// [ASTBranch] IF,ELSE IF,ELSE: `if (exp) {} else if (exp) {}* else {}`
class ASTBranchIfElseIfsElseBlock extends ASTBranch {
  ASTExpression condition;
  ASTBlock blockIf;
  List<ASTBranchIfBlock> blocksElseIf;
  ASTBlock? blockElse;

  ASTBranchIfElseIfsElseBlock(
    this.condition,
    this.blockIf,
    this.blocksElseIf,
    this.blockElse,
  );

  @override
  Iterable<ASTNode> get children => [condition, ...blocksElseIf, ?blockElse];

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    condition.resolveNode(parentNode);

    blockIf.resolveNode(parentNode);

    for (var e in blocksElseIf) {
      e.resolveNode(parentNode);
    }

    blockElse?.resolveNode(parentNode);
  }

  @override
  FutureOr<ASTValue> run(
    VMContext parentContext,
    ASTRunStatus runStatus,
  ) async {
    var evalValue = await evaluateCondition(
      parentContext,
      runStatus,
      condition,
    );
    if (evalValue) {
      await blockIf.run(parentContext, runStatus);
      return ASTValueVoid.instance;
    } else {
      for (var branch in blocksElseIf) {
        evalValue = await evaluateCondition(
          parentContext,
          runStatus,
          branch.condition,
        );

        if (evalValue) {
          await branch.block.run(parentContext, runStatus);
          return ASTValueVoid.instance;
        }
      }

      await blockElse?.run(parentContext, runStatus);
      return ASTValueVoid.instance;
    }
  }

  @override
  String toString() {
    var str = StringBuffer();
    str.write('if ( $condition ) $blockIf\n');

    for (var e in blocksElseIf) {
      str.write('else $e');
    }

    str.write('else $blockElse');

    return str.toString();
  }
}

class ASTStatementWhileLoop extends ASTStatement {
  final ASTExpression conditionExpression;

  final ASTBlock loopBlock;

  ASTStatementWhileLoop(this.conditionExpression, this.loopBlock);

  @override
  Iterable<ASTNode> get children => [conditionExpression, loopBlock];

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    conditionExpression.resolveNode(parentNode);

    loopBlock.resolveNode(parentNode);
  }

  @override
  VMContext defineRunContext(VMContext parentContext) {
    return parentContext;
  }

  @override
  FutureOr<ASTValue> run(
    VMContext parentContext,
    ASTRunStatus runStatus,
  ) async {
    var context = VMScopeContext(parentContext.block, parent: parentContext);

    var prevContext = VMContext.setCurrent(context);
    try {
      while (true) {
        var cond = await conditionExpression.run(context, runStatus);

        if (cond is ASTValueBool) {
          if (!cond.value) break;
        } else {
          var condOK = await cond.getValue(context);

          if (condOK is bool) {
            if (!condOK) break;
          } else {
            throw ApolloVMRuntimeError(
              'Condition not returning a boolean: $condOK',
            );
          }
        }

        var loopContext = VMScopeContext(parentContext.block, parent: context);

        VMContext.setCurrent(loopContext);

        await loopBlock.run(loopContext, runStatus);

        VMContext.setCurrent(context);

        if (runStatus.returned) break;
        if (runStatus.broke) {
          runStatus.broke = false;
          break;
        }
        if (runStatus.continued) {
          runStatus.continued = false;
          continue;
        }
      }
    } finally {
      VMContext.setCurrent(prevContext);
    }

    return ASTValueVoid.instance;
  }

  @override
  ASTType resolveType(VMContext? context) => ASTTypeVoid.instance;
}

/// [ASTStatement] for a `do { } while (cond)` loop: the body runs at least once.
class ASTStatementDoWhileLoop extends ASTStatement {
  final ASTBlock loopBlock;

  final ASTExpression conditionExpression;

  ASTStatementDoWhileLoop(this.loopBlock, this.conditionExpression);

  @override
  Iterable<ASTNode> get children => [loopBlock, conditionExpression];

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    loopBlock.resolveNode(parentNode);
    conditionExpression.resolveNode(parentNode);
  }

  @override
  VMContext defineRunContext(VMContext parentContext) {
    return parentContext;
  }

  @override
  FutureOr<ASTValue> run(
    VMContext parentContext,
    ASTRunStatus runStatus,
  ) async {
    var context = VMScopeContext(parentContext.block, parent: parentContext);

    var prevContext = VMContext.setCurrent(context);
    try {
      while (true) {
        var loopContext = VMScopeContext(parentContext.block, parent: context);

        VMContext.setCurrent(loopContext);

        await loopBlock.run(loopContext, runStatus);

        VMContext.setCurrent(context);

        if (runStatus.returned) break;
        if (runStatus.broke) {
          runStatus.broke = false;
          break;
        }
        if (runStatus.continued) {
          runStatus.continued = false;
          // Falls through to the condition check below.
        }

        var cond = await conditionExpression.run(context, runStatus);

        if (cond is ASTValueBool) {
          if (!cond.value) break;
        } else {
          var condOK = await cond.getValue(context);

          if (condOK is bool) {
            if (!condOK) break;
          } else {
            throw ApolloVMRuntimeError(
              'Condition not returning a boolean: $condOK',
            );
          }
        }
      }
    } finally {
      VMContext.setCurrent(prevContext);
    }

    return ASTValueVoid.instance;
  }

  @override
  ASTType resolveType(VMContext? context) => ASTTypeVoid.instance;
}

class ASTStatementForLoop extends ASTStatement {
  final ASTStatement initStatement;

  final ASTExpression conditionExpression;

  final ASTExpression continueExpression;

  final ASTBlock loopBlock;

  ASTStatementForLoop(
    this.initStatement,
    this.conditionExpression,
    this.continueExpression,
    this.loopBlock,
  );

  @override
  Iterable<ASTNode> get children => [
    initStatement,
    conditionExpression,
    continueExpression,
    loopBlock,
  ];

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    initStatement.resolveNode(parentNode);
    conditionExpression.resolveNode(parentNode);
    continueExpression.resolveNode(parentNode);

    loopBlock.resolveNode(parentNode);
  }

  @override
  VMContext defineRunContext(VMContext parentContext) {
    return parentContext;
  }

  @override
  FutureOr<ASTValue> run(
    VMContext parentContext,
    ASTRunStatus runStatus,
  ) async {
    var context = VMScopeContext(parentContext.block, parent: parentContext);

    var prevContext = VMContext.setCurrent(context);
    try {
      await initStatement.run(context, runStatus);

      while (true) {
        var cond = await conditionExpression.run(context, runStatus);

        if (cond is ASTValueBool) {
          if (!cond.value) break;
        } else {
          var condOK = await cond.getValue(context);

          if (condOK is bool) {
            if (!condOK) break;
          } else {
            throw ApolloVMRuntimeError(
              'Condition not returning a boolean: $condOK',
            );
          }
        }

        var loopContext = VMScopeContext(parentContext.block, parent: context);

        VMContext.setCurrent(loopContext);

        await loopBlock.run(loopContext, runStatus);

        VMContext.setCurrent(context);

        if (runStatus.returned) break;
        if (runStatus.broke) {
          runStatus.broke = false;
          break;
        }
        // `continue` still runs the loop's continue/increment expression below.
        if (runStatus.continued) {
          runStatus.continued = false;
        }

        await continueExpression.run(context, runStatus);
      }
    } finally {
      VMContext.setCurrent(prevContext);
    }

    return ASTValueVoid.instance;
  }

  @override
  ASTType resolveType(VMContext? context) => ASTTypeVoid.instance;
}

class ASTStatementForEach extends ASTStatement {
  final ASTType variableType;
  final String variableName;
  final ASTExpression iterableExpression;
  final ASTBlock loopBlock;

  ASTStatementForEach(
    this.variableType,
    this.variableName,
    this.iterableExpression,
    this.loopBlock,
  );

  @override
  Iterable<ASTNode> get children => [iterableExpression, loopBlock];

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    iterableExpression.resolveNode(parentNode);
    loopBlock.resolveNode(parentNode);
  }

  @override
  VMContext defineRunContext(VMContext parentContext) {
    return parentContext;
  }

  @override
  FutureOr<ASTValue> run(
    VMContext parentContext,
    ASTRunStatus runStatus,
  ) async {
    var context = VMScopeContext(parentContext.block, parent: parentContext);
    var prevContext = VMContext.setCurrent(context);

    try {
      var iterableValue = await iterableExpression.run(context, runStatus);

      // Resolve the underlying value so that `for-each` works over any
      // iterable, not only an `ASTValueArray` (e.g. a `List` bound to a
      // `dynamic`/`Object` variable, which resolves to a plain `ASTValueStatic`).
      var rawIterable = await iterableValue.getValue(context);

      Iterable iterable;
      if (rawIterable is Iterable) {
        iterable = rawIterable;
      } else if (rawIterable is Map) {
        iterable = rawIterable.values;
      } else {
        throw ApolloVMRuntimeError(
          "for-each target is not iterable: "
          "${iterableValue.runtimeType} (value: $rawIterable)",
        );
      }

      for (var element in iterable) {
        // Wrap each raw element into a concretely-typed `ASTValue` (passes
        // through if it is already an `ASTValue`), so the loop body sees the
        // element's real type.
        var astElement = element is ASTValue
            ? element
            : ASTValue.fromValue(element);

        var elementType = astElement.type;

        var loopContext = VMScopeContext(parentContext.block, parent: context);

        loopContext.declareVariableWithValue(
          elementType,
          variableName,
          astElement,
        );

        VMContext.setCurrent(loopContext);

        await loopBlock.run(loopContext, runStatus);

        VMContext.setCurrent(context);

        if (runStatus.returned) break;
        if (runStatus.broke) {
          runStatus.broke = false;
          break;
        }
        if (runStatus.continued) {
          runStatus.continued = false;
          continue;
        }
      }
    } finally {
      VMContext.setCurrent(prevContext);
    }

    return ASTValueVoid.instance;
  }

  @override
  ASTType resolveType(VMContext? context) => ASTTypeVoid.instance;
}

/// [ASTStatement] for `break;` — interrupts the enclosing loop or switch.
class ASTStatementBreak extends ASTStatement {
  @override
  Iterable<ASTNode> get children => [];

  @override
  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus) {
    return runStatus.markBreak();
  }

  @override
  ASTType resolveType(VMContext? context) => ASTTypeVoid.instance;

  @override
  String toString() => 'break;';
}

/// [ASTStatement] for `continue;` — skips to the next loop iteration.
class ASTStatementContinue extends ASTStatement {
  @override
  Iterable<ASTNode> get children => [];

  @override
  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus) {
    return runStatus.markContinue();
  }

  @override
  ASTType resolveType(VMContext? context) => ASTTypeVoid.instance;

  @override
  String toString() => 'continue;';
}

/// A single `case <value>:` (or `default:`) clause of an [ASTStatementSwitch].
///
/// A [value] of `null` marks the `default` clause.
class ASTSwitchCase {
  final ASTExpression? value;
  final ASTBlock block;

  ASTSwitchCase(this.value, this.block);

  bool get isDefault => value == null;

  void resolveNode(ASTNode? parentNode) {
    value?.resolveNode(parentNode);
    block.resolveNode(parentNode);
  }
}

/// [ASTStatement] for `switch (exp) { case v: ... break; default: ... }`.
///
/// With [fallThrough] (the default, C-style `switch`): once a `case` matches,
/// its block and the blocks of the following clauses run in order until a
/// `break` (or `return`). With [fallThrough] `false` (e.g. Kotlin `when`,
/// Python `match`): only the matched clause runs — there is no fall-through and
/// `break` is implicit. If no `case` matches, the `default` clause (if present)
/// runs.
class ASTStatementSwitch extends ASTStatement {
  final ASTExpression expression;
  final List<ASTSwitchCase> cases;

  /// Whether matched clauses fall through to the next clause (C-style).
  final bool fallThrough;

  ASTStatementSwitch(this.expression, this.cases, {this.fallThrough = true});

  @override
  Iterable<ASTNode> get children => [expression, ...cases.map((e) => e.block)];

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);

    expression.resolveNode(parentNode);
    for (var c in cases) {
      c.resolveNode(parentNode);
    }
  }

  @override
  VMContext defineRunContext(VMContext parentContext) => parentContext;

  @override
  FutureOr<ASTValue> run(
    VMContext parentContext,
    ASTRunStatus runStatus,
  ) async {
    var context = VMScopeContext(parentContext.block, parent: parentContext);
    var prevContext = VMContext.setCurrent(context);

    try {
      var switchValue = await expression.run(context, runStatus);
      var rawSwitch = await switchValue.getValue(context);

      // Find the matching case, or fall back to `default`.
      var startIndex = -1;
      for (var i = 0; i < cases.length; ++i) {
        var c = cases[i];
        if (c.isDefault) continue;
        var caseValue = await c.value!.run(context, runStatus);
        var rawCase = await caseValue.getValue(context);
        if (rawSwitch == rawCase) {
          startIndex = i;
          break;
        }
      }

      if (startIndex < 0) {
        startIndex = cases.indexWhere((c) => c.isDefault);
      }

      if (startIndex < 0) return ASTValueVoid.instance;

      if (!fallThrough) {
        // Only the matched clause runs (Kotlin `when` / Python `match`).
        await cases[startIndex].block.run(context, runStatus);
        // `break` is implicit here, so consume any that bubbled up.
        if (runStatus.broke) runStatus.broke = false;
        return ASTValueVoid.instance;
      }

      // Fall-through: run from the matched clause onward until break/return.
      for (var i = startIndex; i < cases.length; ++i) {
        await cases[i].block.run(context, runStatus);

        // `return`/`continue` propagate up (e.g. `continue` of an enclosing
        // loop); `break` is consumed here as it targets this switch.
        if (runStatus.returned || runStatus.continued) break;
        if (runStatus.broke) {
          runStatus.broke = false;
          break;
        }
      }
    } finally {
      VMContext.setCurrent(prevContext);
    }

    return ASTValueVoid.instance;
  }

  @override
  ASTType resolveType(VMContext? context) => ASTTypeVoid.instance;

  @override
  String toString() {
    var str = StringBuffer('switch ( $expression ) {\n');
    for (var c in cases) {
      str.write(c.isDefault ? 'default: ' : 'case ${c.value}: ');
      str.write('${c.block}\n');
    }
    str.write('}');
    return str.toString();
  }
}

/// [ASTStatement] for `throw <expression>;`.
class ASTStatementThrow extends ASTStatement {
  ASTExpression expression;

  ASTStatementThrow(this.expression);

  @override
  Iterable<ASTNode> get children => [expression];

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);
    expression.resolveNode(parentNode);
  }

  @override
  FutureOr<ASTValue> run(VMContext parentContext, ASTRunStatus runStatus) {
    return expression.run(parentContext, runStatus).resolveMapped((value) {
      throw ApolloVMThrownException(value);
    });
  }

  @override
  ASTType resolveType(VMContext? context) => ASTTypeVoid.instance;

  @override
  String toString() => 'throw $expression ;';
}

/// A single `catch` clause of an [ASTStatementTryCatch].
///
/// [exceptionType] is the matched type (`null` = catch-all); [variableName] is
/// the bound variable (`null` = no variable); [block] is the handler body.
class ASTCatchClause {
  final ASTType? exceptionType;
  final String? variableName;
  final ASTBlock block;

  ASTCatchClause(this.exceptionType, this.variableName, this.block);

  void resolveNode(ASTNode? parentNode) {
    exceptionType?.resolveNode(parentNode);
    block.resolveNode(parentNode);
  }

  /// Runs the handler with [caught] bound to [variableName] in a child scope.
  Future<ASTValue> run(
    VMContext parentContext,
    ASTRunStatus runStatus,
    ASTValue caught,
  ) async {
    var context = VMScopeContext(parentContext.block, parent: parentContext);
    var name = variableName;
    if (name != null) {
      context.declareVariableWithValue(
        exceptionType ?? ASTTypeDynamic.instance,
        name,
        caught,
      );
    }
    var prevContext = VMContext.setCurrent(context);
    try {
      var result = await block.run(context, runStatus);
      // Materialize any lazy returned value (e.g. a string interpolation that
      // references the bound variable) while the catch variable is still in
      // scope — otherwise it would be resolved later, after this scope is gone.
      if (runStatus.returned) {
        var returnedValue = runStatus.returnedValue;
        if (returnedValue != null) {
          var resolved = await returnedValue.resolve(context);
          runStatus.returnedValue = resolved;
          result = resolved;
        }
      }
      return result;
    } finally {
      VMContext.setCurrent(prevContext);
    }
  }
}

/// The universal "catch-all" exception supertypes across the supported
/// languages. A `catch` clause typed with one of these matches any thrown
/// value (including built-in VM errors), so that an untyped Dart/JS `catch (e)`
/// round-trips faithfully to Java `catch (Exception e)`, Kotlin
/// `catch (e: Throwable)`, etc.
const _catchAllTypeNames = {
  'Object',
  'dynamic',
  'Exception',
  'Throwable',
  'Error',
};

bool _isCatchAllType(ASTType type) => _catchAllTypeNames.contains(type.name);

/// [ASTStatement] for `try { } catch ... { } finally { }`.
///
/// Catches both user `throw`n values ([ApolloVMThrownException]) and built-in VM
/// runtime errors ([ApolloVMRuntimeError]); the latter are surfaced as a
/// `String` value (their message). A typed clause matches only when the caught
/// value is an instance of its type; a clause with a `null` type catches all.
/// The [finallyBlock] always runs, and a `return` inside it overrides.
class ASTStatementTryCatch extends ASTStatement {
  final ASTBlock tryBlock;
  final List<ASTCatchClause> catches;
  final ASTBlock? finallyBlock;

  ASTStatementTryCatch(this.tryBlock, this.catches, this.finallyBlock);

  @override
  Iterable<ASTNode> get children => [tryBlock, ?finallyBlock];

  @override
  void resolveNode(ASTNode? parentNode) {
    super.resolveNode(parentNode);
    tryBlock.resolveNode(parentNode);
    for (var c in catches) {
      c.resolveNode(parentNode);
    }
    finallyBlock?.resolveNode(parentNode);
  }

  @override
  VMContext defineRunContext(VMContext parentContext) => parentContext;

  @override
  FutureOr<ASTValue> run(
    VMContext parentContext,
    ASTRunStatus runStatus,
  ) async {
    try {
      try {
        return await tryBlock.run(parentContext, runStatus);
      } catch (error) {
        // Like Dart's `catch (e)` (which catches any `Object`): user `throw`s
        // surface their thrown value; built-in VM/runtime errors surface as a
        // `String` (their message). Control flow (return/break) uses
        // `ASTRunStatus` flags, not exceptions, so it is never caught here.
        var caught = error is ApolloVMThrownException
            ? error.value
            : ASTValueString(error.toString());

        for (var c in catches) {
          var t = c.exceptionType;
          if (t == null ||
              _isCatchAllType(t) ||
              await caught.isInstanceOfAsync(t)) {
            return await c.run(parentContext, runStatus, caught);
          }
        }
        rethrow; // no clause matched
      }
    } finally {
      var finallyBlock = this.finallyBlock;
      if (finallyBlock != null) {
        var finallyStatus = ASTRunStatus();
        await finallyBlock.run(parentContext, finallyStatus);
        // A `return` inside `finally` overrides the try/catch outcome.
        if (finallyStatus.returned) {
          runStatus.returned = true;
          runStatus.returnedValue = finallyStatus.returnedValue;
          runStatus.returnedFutureValue = finallyStatus.returnedFutureValue;
        }
      }
    }
  }

  @override
  ASTType resolveType(VMContext? context) => ASTTypeVoid.instance;

  @override
  String toString() {
    var str = StringBuffer('try $tryBlock');
    for (var c in catches) {
      str.write(' catch ${c.block}');
    }
    if (finallyBlock != null) {
      str.write(' finally $finallyBlock');
    }
    return str.toString();
  }
}
