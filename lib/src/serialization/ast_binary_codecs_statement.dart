// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import '../ast/apollovm_ast_expression.dart';
import '../ast/apollovm_ast_statement.dart';
import '../ast/apollovm_ast_toplevel.dart';
import '../ast/apollovm_ast_value.dart';
import '../ast/apollovm_ast_variable.dart';
import 'ast_binary_context.dart';
import 'ast_binary_node_codec.dart';
import 'ast_binary_tags.dart';

/// Writes the contents of an [ASTBlock].
///
/// `ASTBlock.children` reports only its functions and statements — getters and
/// setters are missing from it, even though `resolveNode` walks them — so the
/// members are written explicitly rather than through a generic walk.
///
/// Overload sets (`ASTFunctionSet*`) are flattened to their declarations:
/// `addFunction` rebuilds the single/multiple split from the names, so the set
/// objects themselves are derived data and never stored.
void writeBlockBody(ASTBinaryWriteContext w, ASTBlock block) {
  w.nodes(block.statements);
  w.nodes([for (var set in block.functions) ...set.functions]);
  w.nodes(block.getter);
  w.nodes(block.setter);
}

/// Fills [block] with the members written by [writeBlockBody].
void readBlockBody(ASTBinaryReadContext r, ASTBlock block) {
  block.addAllStatements(r.nodeList<ASTStatement>());
  block.addAllFunctions(r.nodeList<ASTFunctionDeclaration>());
  block.addAllGetters(r.nodeList<ASTGetterDeclaration>());
  block.addAllSetters(r.nodeList<ASTSetterDeclaration>());
}

/// Codecs for the plain block kinds.
///
/// Kept apart from [statementCodecs] and registered **last of everything**:
/// a great many nodes extend [ASTBlock] — every class, every function, getter
/// and setter declaration, the root itself — and dispatch takes the first
/// matching codec, so a bare `ASTBlock` entry appearing earlier would claim all
/// of them.
final List<ASTNodeCodec> blockCodecs = [
  // Before `ASTBlock`, which it extends.
  ASTNodeCodec<ASTSingleLineStatementBlock>(
    ASTNodeTag.singleLineStatementBlock,
    'ASTSingleLineStatementBlock',
    encode: (w, n) => writeBlockBody(w, n),
    decode: (r) {
      // `parentBlock` is left null, exactly as the grammars leave it; the
      // parent chain is re-established by `resolveNode`.
      var block = ASTSingleLineStatementBlock(null);
      readBlockBody(r, block);
      return block;
    },
  ),

  ASTNodeCodec<ASTBlock>(
    ASTNodeTag.block,
    'ASTBlock',
    encode: (w, n) => writeBlockBody(w, n),
    decode: (r) {
      var block = ASTBlock(null);
      readBlockBody(r, block);
      return block;
    },
  ),
];

/// Codecs for the [ASTStatement] family, **most derived first**.
final List<ASTNodeCodec> statementCodecs = [
  // --- Simple statements ----------------------------------------------------
  ASTNodeCodec<ASTStatementExpression>(
    ASTNodeTag.statementExpression,
    'ASTStatementExpression',
    encode: (w, n) => w.node(n.expression),
    decode: (r) => ASTStatementExpression(r.node<ASTExpression>()),
  ),

  ASTNodeCodec<ASTStatementBlock>(
    ASTNodeTag.statementBlock,
    'ASTStatementBlock',
    encode: (w, n) => w.node(n.block),
    decode: (r) => ASTStatementBlock(r.node<ASTBlock>()),
  ),

  ASTNodeCodec<ASTStatementValue>(
    ASTNodeTag.statementValue,
    'ASTStatementValue',
    encode: (w, n) => w.node(n.value),
    decode: (r) =>
        // The constructor takes a block and discards it, so a throwaway one is
        // all it needs.
        ASTStatementValue(ASTBlock(null), r.node<ASTValue>()),
  ),

  ASTNodeCodec<ASTStatementFunctionDeclaration>(
    ASTNodeTag.statementFunctionDeclaration,
    'ASTStatementFunctionDeclaration',
    encode: (w, n) => w.node(n.functionDeclaration),
    decode: (r) =>
        ASTStatementFunctionDeclaration(r.node<ASTFunctionDeclaration>()),
  ),

  ASTNodeCodec<ASTStatementVariableDeclaration>(
    ASTNodeTag.statementVariableDeclaration,
    'ASTStatementVariableDeclaration',
    encode: (w, n) {
      w.type(n.type);
      w.str(n.name);
      w.nodeOrNull(n.value);
      w.boolean(n.unmodifiable);
    },
    decode: (r) {
      var type = r.type();
      var name = r.str();
      var value = r.nodeOrNull<ASTExpression>();
      // The constructor normalizes a list-literal initializer's component type.
      // It is idempotent on input that is already normalized, so replaying it
      // is safe.
      return ASTStatementVariableDeclaration(
        type,
        name,
        value,
        unmodifiable: r.boolean(),
      );
    },
  ),

  // --- Returns (subclasses before `ASTStatementReturn`) ---------------------
  ASTNodeCodec<ASTStatementReturnNull>(
    ASTNodeTag.statementReturnNull,
    'ASTStatementReturnNull',
    encode: (w, n) {},
    decode: (r) => ASTStatementReturnNull(),
  ),

  ASTNodeCodec<ASTStatementReturnValue>(
    ASTNodeTag.statementReturnValue,
    'ASTStatementReturnValue',
    encode: (w, n) => w.node(n.value),
    decode: (r) => ASTStatementReturnValue(r.node<ASTValue>()),
  ),

  ASTNodeCodec<ASTStatementReturnVariable>(
    ASTNodeTag.statementReturnVariable,
    'ASTStatementReturnVariable',
    encode: (w, n) => w.node(n.variable),
    decode: (r) => ASTStatementReturnVariable(r.node<ASTVariable>()),
  ),

  ASTNodeCodec<ASTStatementReturnWithExpression>(
    ASTNodeTag.statementReturnWithExpression,
    'ASTStatementReturnWithExpression',
    encode: (w, n) => w.node(n.expression),
    decode: (r) => ASTStatementReturnWithExpression(r.node<ASTExpression>()),
  ),

  ASTNodeCodec<ASTStatementReturn>(
    ASTNodeTag.statementReturn,
    'ASTStatementReturn',
    encode: (w, n) {},
    decode: (r) => ASTStatementReturn(),
  ),

  // --- Branches -------------------------------------------------------------
  ASTNodeCodec<ASTBranchIfElseIfsElseBlock>(
    ASTNodeTag.branchIfElseIfsElseBlock,
    'ASTBranchIfElseIfsElseBlock',
    encode: (w, n) {
      w.node(n.condition);
      w.node(n.blockIf);
      w.nodes(n.blocksElseIf);
      w.nodeOrNull(n.blockElse);
    },
    decode: (r) {
      var condition = r.node<ASTExpression>();
      var blockIf = r.node<ASTBlock>();
      var blocksElseIf = r.nodeList<ASTBranchIfBlock>();
      return ASTBranchIfElseIfsElseBlock(
        condition,
        blockIf,
        blocksElseIf,
        r.nodeOrNull<ASTBlock>(),
      );
    },
  ),

  ASTNodeCodec<ASTBranchIfElseBlock>(
    ASTNodeTag.branchIfElseBlock,
    'ASTBranchIfElseBlock',
    encode: (w, n) {
      w.node(n.condition);
      w.node(n.blockIf);
      w.nodeOrNull(n.blockElse);
    },
    decode: (r) {
      var condition = r.node<ASTExpression>();
      var blockIf = r.node<ASTBlock>();
      return ASTBranchIfElseBlock(condition, blockIf, r.nodeOrNull<ASTBlock>());
    },
  ),

  ASTNodeCodec<ASTBranchIfBlock>(
    ASTNodeTag.branchIfBlock,
    'ASTBranchIfBlock',
    encode: (w, n) {
      w.node(n.condition);
      w.node(n.block);
    },
    decode: (r) {
      var condition = r.node<ASTExpression>();
      return ASTBranchIfBlock(condition, r.node<ASTBlock>());
    },
  ),

  // --- Loops ----------------------------------------------------------------
  ASTNodeCodec<ASTStatementWhileLoop>(
    ASTNodeTag.statementWhileLoop,
    'ASTStatementWhileLoop',
    encode: (w, n) {
      w.node(n.conditionExpression);
      w.node(n.loopBlock);
    },
    decode: (r) {
      var condition = r.node<ASTExpression>();
      return ASTStatementWhileLoop(condition, r.node<ASTBlock>());
    },
  ),

  ASTNodeCodec<ASTStatementDoWhileLoop>(
    ASTNodeTag.statementDoWhileLoop,
    'ASTStatementDoWhileLoop',
    encode: (w, n) {
      w.node(n.loopBlock);
      w.node(n.conditionExpression);
    },
    decode: (r) {
      var loopBlock = r.node<ASTBlock>();
      return ASTStatementDoWhileLoop(loopBlock, r.node<ASTExpression>());
    },
  ),

  ASTNodeCodec<ASTStatementForLoop>(
    ASTNodeTag.statementForLoop,
    'ASTStatementForLoop',
    encode: (w, n) {
      w.node(n.initStatement);
      w.node(n.conditionExpression);
      w.node(n.continueExpression);
      w.node(n.loopBlock);
    },
    decode: (r) {
      var init = r.node<ASTStatement>();
      var condition = r.node<ASTExpression>();
      var continueExpression = r.node<ASTExpression>();
      return ASTStatementForLoop(
        init,
        condition,
        continueExpression,
        r.node<ASTBlock>(),
      );
    },
  ),

  ASTNodeCodec<ASTStatementForEach>(
    ASTNodeTag.statementForEach,
    'ASTStatementForEach',
    encode: (w, n) {
      // `children` omits the loop variable's type and name, so both are written
      // explicitly.
      w.type(n.variableType);
      w.str(n.variableName);
      w.node(n.iterableExpression);
      w.node(n.loopBlock);
    },
    decode: (r) {
      var variableType = r.type();
      var variableName = r.str();
      var iterable = r.node<ASTExpression>();
      return ASTStatementForEach(
        variableType,
        variableName,
        iterable,
        r.node<ASTBlock>(),
      );
    },
  ),

  ASTNodeCodec<ASTStatementBreak>(
    ASTNodeTag.statementBreak,
    'ASTStatementBreak',
    encode: (w, n) {},
    decode: (r) => ASTStatementBreak(),
  ),

  ASTNodeCodec<ASTStatementContinue>(
    ASTNodeTag.statementContinue,
    'ASTStatementContinue',
    encode: (w, n) {},
    decode: (r) => ASTStatementContinue(),
  ),

  // --- Switch ---------------------------------------------------------------
  ASTNodeCodec<ASTStatementSwitch>(
    ASTNodeTag.statementSwitch,
    'ASTStatementSwitch',
    encode: (w, n) {
      w.node(n.expression);
      w.nodes(n.cases);
      w.boolean(n.fallThrough);
    },
    decode: (r) {
      var expression = r.node<ASTExpression>();
      var cases = r.nodeList<ASTSwitchCase>();
      return ASTStatementSwitch(expression, cases, fallThrough: r.boolean());
    },
  ),

  ASTNodeCodec<ASTSwitchCase>(
    ASTNodeTag.switchCase,
    'ASTSwitchCase',
    encode: (w, n) {
      // A null value is what makes a case the `default` branch.
      w.nodeOrNull(n.value);
      w.node(n.block);
    },
    decode: (r) {
      var value = r.nodeOrNull<ASTExpression>();
      return ASTSwitchCase(value, r.node<ASTBlock>());
    },
  ),

  // --- Throw, assert, try/catch ---------------------------------------------
  ASTNodeCodec<ASTStatementThrow>(
    ASTNodeTag.statementThrow,
    'ASTStatementThrow',
    encode: (w, n) => w.node(n.expression),
    decode: (r) => ASTStatementThrow(r.node<ASTExpression>()),
  ),

  ASTNodeCodec<ASTStatementAssert>(
    ASTNodeTag.statementAssert,
    'ASTStatementAssert',
    encode: (w, n) {
      w.node(n.condition);
      w.nodeOrNull(n.message);
    },
    decode: (r) {
      var condition = r.node<ASTExpression>();
      return ASTStatementAssert(condition, r.nodeOrNull<ASTExpression>());
    },
  ),

  ASTNodeCodec<ASTStatementTryCatch>(
    ASTNodeTag.statementTryCatch,
    'ASTStatementTryCatch',
    encode: (w, n) {
      w.node(n.tryBlock);
      // `children` lists only the try and finally blocks; the catch clauses
      // would be lost by a generic walk.
      w.nodes(n.catches);
      w.nodeOrNull(n.finallyBlock);
    },
    decode: (r) {
      var tryBlock = r.node<ASTBlock>();
      var catches = r.nodeList<ASTCatchClause>();
      return ASTStatementTryCatch(tryBlock, catches, r.nodeOrNull<ASTBlock>());
    },
  ),

  ASTNodeCodec<ASTCatchClause>(
    ASTNodeTag.catchClause,
    'ASTCatchClause',
    encode: (w, n) {
      w.typeOrNull(n.exceptionType);
      w.strOrNull(n.variableName);
      w.node(n.block);
      w.strOrNull(n.stackTraceName);
    },
    decode: (r) {
      var exceptionType = r.typeOrNull();
      var variableName = r.strOrNull();
      var block = r.node<ASTBlock>();
      return ASTCatchClause(
        exceptionType,
        variableName,
        block,
        stackTraceName: r.strOrNull(),
      );
    },
  ),

  // --- Imports and exports --------------------------------------------------
  ASTNodeCodec<ASTStatementImport>(
    ASTNodeTag.statementImport,
    'ASTStatementImport',
    encode: (w, n) {
      w.str(n.path);
      w.strOrNull(n.prefix);
      w.boolean(n.wildcard);
      w.nodes(n.combinators);
      w.nodes(n.namedSymbols);
    },
    decode: (r) {
      var path = r.str();
      var prefix = r.strOrNull();
      var wildcard = r.boolean();
      var combinators = r.nodeList<ASTImportCombinator>();
      return ASTStatementImport(
        path,
        prefix: prefix,
        wildcard: wildcard,
        combinators: combinators,
        namedSymbols: r.nodeList<ASTImportedSymbol>(),
      );
    },
  ),

  ASTNodeCodec<ASTStatementExport>(
    ASTNodeTag.statementExport,
    'ASTStatementExport',
    encode: (w, n) {
      w.strOrNull(n.path);
      w.nodes(n.symbols);
      w.nodes(n.combinators);
    },
    decode: (r) {
      var path = r.strOrNull();
      var symbols = r.nodeList<ASTImportedSymbol>();
      return ASTStatementExport(
        path: path,
        symbols: symbols,
        combinators: r.nodeList<ASTImportCombinator>(),
      );
    },
  ),

  ASTNodeCodec<ASTImportCombinator>(
    ASTNodeTag.importCombinator,
    'ASTImportCombinator',
    encode: (w, n) {
      w.enumByName(n.kind);
      w.strings_(n.names);
    },
    decode: (r) {
      var kind = r.enumByName(ASTImportCombinatorKind.values);
      return ASTImportCombinator(kind, r.strings_() ?? const <String>[]);
    },
  ),

  ASTNodeCodec<ASTImportedSymbol>(
    ASTNodeTag.importedSymbol,
    'ASTImportedSymbol',
    encode: (w, n) {
      w.str(n.name);
      w.strOrNull(n.alias);
    },
    decode: (r) {
      var name = r.str();
      return ASTImportedSymbol(name, alias: r.strOrNull());
    },
  ),
];
