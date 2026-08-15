// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import '../apollovm_base.dart' show VMObject;
import '../ast/apollovm_ast_expression.dart';
import '../ast/apollovm_ast_statement.dart';
import '../ast/apollovm_ast_toplevel.dart';
import '../ast/apollovm_ast_type.dart';
import '../ast/apollovm_ast_variable.dart';
import 'ast_binary_codecs_statement.dart';
import 'ast_binary_context.dart';
import 'ast_binary_node_codec.dart';
import 'ast_binary_tags.dart';

/// Writes the three parameter groups of a declaration.
void _writeParameters(ASTBinaryWriteContext w, ASTParametersDeclaration p) {
  w.nodes(p.positionalParameters);
  w.nodes(p.optionalParameters);
  w.nodes(p.namedParameters);
}

ASTFunctionParametersDeclaration _readFunctionParameters(
  ASTBinaryReadContext r,
) {
  var positional = r.nodes<ASTFunctionParameterDeclaration>();
  var optional = r.nodes<ASTFunctionParameterDeclaration>();
  return ASTFunctionParametersDeclaration(
    positional,
    optional,
    r.nodes<ASTFunctionParameterDeclaration>(),
  );
}

ASTConstructorParametersDeclaration _readConstructorParameters(
  ASTBinaryReadContext r,
) {
  var positional = r.nodes<ASTConstructorParameterDeclaration>();
  var optional = r.nodes<ASTConstructorParameterDeclaration>();
  return ASTConstructorParametersDeclaration(
    positional,
    optional,
    r.nodes<ASTConstructorParameterDeclaration>(),
  );
}

/// Fills a declaration's own block body.
///
/// Declarations are blocks: `ASTInvocableDeclaration`, `ASTGetterDeclaration`
/// and `ASTSetterDeclaration` all extend [ASTBlock], and their statements live
/// directly in them. Their constructors take a `block` and copy it with `set`,
/// so building empty and filling afterwards produces the same shape with one
/// less throwaway object.
void _fillBlock(ASTBinaryReadContext r, ASTBlock block) =>
    readBlockBody(r, block);

/// Codecs for the top-level declarations, **most derived first**.
final List<ASTNodeCodec> toplevelCodecs = [
  // --- Root -----------------------------------------------------------------
  ASTNodeCodec<ASTRoot>(
    ASTNodeTag.root,
    'ASTRoot',
    encode: (w, n) {
      w.str(n.namespace);
      w.strOrNull(n.moduleId);
      // `ASTRoot.children` lists neither its classes nor its extensions nor its
      // type aliases, so every group is written explicitly.
      w.nodes(n.imports.toList());
      w.nodes(n.exports.toList());
      w.nodes(n.typeAliases);
      w.nodes(n.classes);
      w.nodes(n.extensions);
      writeBlockBody(w, n);
    },
    decode: (r) {
      var root = ASTRoot();
      root.namespace = r.str();
      root.moduleId = r.strOrNull();

      for (var e in r.nodeList<ASTStatementImport>()) {
        root.addImport(e);
      }
      for (var e in r.nodeList<ASTStatementExport>()) {
        root.addExport(e);
      }
      for (var e in r.nodeList<ASTTypeAlias>()) {
        root.addTypeAlias(e);
      }
      for (var e in r.nodeList<ASTClassNormal>()) {
        root.addClass(e);
      }
      for (var e in r.nodeList<ASTExtension>()) {
        root.addExtension(e);
      }

      _fillBlock(r, root);
      return root;
    },
  ),

  // --- Classes (enum before normal, which it extends) -----------------------
  ASTNodeCodec<ASTClassEnum>(
    ASTNodeTag.classEnum,
    'ASTClassEnum',
    encode: (w, n) => w.inDeclaration('enum ${n.name}', () {
      _writeClassHeader(w, n);
      w.nodes(n.entries);
      _writeClassBody(w, n);
    }),
    decode: (r) {
      var name = r.str();
      var kind = r.enumByName(ASTClassKind.values);
      var superClassName = r.strOrNull();
      var implementsTypes = r.strings_();
      var entries = r.nodeList<ASTEnumEntry>();

      var clazz = ASTClassEnum(
        name,
        // A class declaration's own type is always freshly built, never taken
        // from the type pool: the `ASTClass` constructor calls `setClass` on
        // it, which must not happen to a shared instance. This mirrors what
        // every grammar does — `ASTClassNormal(name, ASTType<VMObject>(name),
        // null)`.
        ASTType<VMObject>(name),
        null,
        entries: entries,
        superClassName: superClassName,
        implementsTypes: implementsTypes,
      );
      // `kind` is not a constructor argument on `ASTClassEnum`; enums are
      // always normal classes, so nothing needs restoring when it matches.
      _assertEnumKind(kind);
      _readClassBody(r, clazz);
      return clazz;
    },
  ),

  ASTNodeCodec<ASTClassNormal>(
    ASTNodeTag.classNormal,
    'ASTClassNormal',
    encode: (w, n) => w.inDeclaration('class ${n.name}', () {
      _writeClassHeader(w, n);
      _writeClassBody(w, n);
    }),
    decode: (r) {
      var name = r.str();
      var kind = r.enumByName(ASTClassKind.values);
      var superClassName = r.strOrNull();
      var implementsTypes = r.strings_();

      var clazz = ASTClassNormal(
        name,
        ASTType<VMObject>(name),
        null,
        kind: kind,
        superClassName: superClassName,
        implementsTypes: implementsTypes,
      );
      _readClassBody(r, clazz);
      return clazz;
    },
  ),

  ASTNodeCodec<ASTEnumEntry>(
    ASTNodeTag.enumEntry,
    'ASTEnumEntry',
    encode: (w, n) {
      w.str(n.name);
      w.nodeOrNull(n.value);
      w.nodes(n.arguments);
    },
    decode: (r) {
      var name = r.str();
      var value = r.nodeOrNull<ASTExpression>();
      return ASTEnumEntry(
        name,
        value: value,
        arguments: r.nodes<ASTExpression>(),
      );
    },
  ),

  ASTNodeCodec<ASTExtension>(
    ASTNodeTag.extension,
    'ASTExtension',
    encode: (w, n) => w.inDeclaration('extension ${n.name ?? ''}', () {
      w.strOrNull(n.name);
      w.type(n.targetType);
      writeBlockBody(w, n);
    }),
    decode: (r) {
      var name = r.strOrNull();
      var targetType = r.type();
      var extension = ASTExtension(name, targetType);
      _fillBlock(r, extension);
      return extension;
    },
  ),

  ASTNodeCodec<ASTTypeAlias>(
    ASTNodeTag.typeAlias,
    'ASTTypeAlias',
    encode: (w, n) {
      w.str(n.name);
      w.type(n.targetType);
    },
    decode: (r) {
      var name = r.str();
      return ASTTypeAlias(name, r.type());
    },
  ),

  // --- Invocables (subclasses first) ----------------------------------------
  ASTNodeCodec<ASTClassFunctionDeclaration>(
    ASTNodeTag.classFunctionDeclaration,
    'ASTClassFunctionDeclaration',
    encode: (w, n) => w.inDeclaration(n.name, () {
      // `clazz` is a back-reference filled in by the enclosing class when the
      // method is added, so it is not written.
      w.str(n.name);
      _writeParameters(w, n.parameters);
      w.type(n.returnType);
      w.modifiers(n.modifiers);
      writeBlockBody(w, n);
    }),
    decode: (r) {
      var name = r.str();
      var parameters = _readFunctionParameters(r);
      var returnType = r.type();
      var modifiers = r.modifiers();
      var f = ASTClassFunctionDeclaration(
        null,
        name,
        parameters,
        returnType,
        modifiers: modifiers,
      );
      _fillBlock(r, f);
      return f;
    },
  ),

  ASTNodeCodec<ASTFunctionDeclaration>(
    ASTNodeTag.functionDeclaration,
    'ASTFunctionDeclaration',
    encode: (w, n) => w.inDeclaration(n.name, () {
      w.str(n.name);
      _writeParameters(w, n.parameters);
      w.type(n.returnType);
      w.modifiers(n.modifiers);
      writeBlockBody(w, n);
    }),
    decode: (r) {
      var name = r.str();
      var parameters = _readFunctionParameters(r);
      var returnType = r.type();
      var modifiers = r.modifiers();
      var f = ASTFunctionDeclaration(
        name,
        parameters,
        returnType,
        modifiers: modifiers,
      );
      _fillBlock(r, f);
      return f;
    },
  ),

  ASTNodeCodec<ASTClassConstructorDeclaration>(
    ASTNodeTag.classConstructorDeclaration,
    'ASTClassConstructorDeclaration',
    encode: (w, n) =>
        w.inDeclaration(n.name.isEmpty ? '<default constructor>' : n.name, () {
          w.str(n.name);
          w.type(n.classType);
          _writeParameters(w, n.parameters);
          w.modifiers(n.modifiers);
          writeBlockBody(w, n);
        }),
    decode: (r) {
      var name = r.str();
      var classType = r.type();
      var parameters = _readConstructorParameters(r);
      var modifiers = r.modifiers();
      var c = ASTClassConstructorDeclaration(
        classType,
        name,
        parameters,
        modifiers: modifiers,
      );
      _fillBlock(r, c);
      return c;
    },
  ),

  // --- Accessors (class variants first) -------------------------------------
  ASTNodeCodec<ASTClassGetterDeclaration>(
    ASTNodeTag.classGetterDeclaration,
    'ASTClassGetterDeclaration',
    encode: (w, n) => w.inDeclaration('get ${n.name}', () {
      w.str(n.name);
      w.type(n.returnType);
      w.modifiers(n.modifiers);
      writeBlockBody(w, n);
    }),
    decode: (r) {
      var name = r.str();
      var returnType = r.type();
      var modifiers = r.modifiers();
      var g = ASTClassGetterDeclaration(
        null,
        name,
        returnType,
        modifiers: modifiers,
      );
      _fillBlock(r, g);
      return g;
    },
  ),

  ASTNodeCodec<ASTGetterDeclaration>(
    ASTNodeTag.getterDeclaration,
    'ASTGetterDeclaration',
    encode: (w, n) => w.inDeclaration('get ${n.name}', () {
      w.str(n.name);
      w.type(n.returnType);
      w.modifiers(n.modifiers);
      writeBlockBody(w, n);
    }),
    decode: (r) {
      var name = r.str();
      var returnType = r.type();
      var modifiers = r.modifiers();
      var g = ASTGetterDeclaration(name, returnType, modifiers: modifiers);
      _fillBlock(r, g);
      return g;
    },
  ),

  ASTNodeCodec<ASTClassSetterDeclaration>(
    ASTNodeTag.classSetterDeclaration,
    'ASTClassSetterDeclaration',
    encode: (w, n) => w.inDeclaration('set ${n.name}', () {
      w.str(n.name);
      w.type(n.parameterType);
      w.str(n.parameterName);
      w.modifiers(n.modifiers);
      writeBlockBody(w, n);
    }),
    decode: (r) {
      var name = r.str();
      var parameterType = r.type();
      var parameterName = r.str();
      var modifiers = r.modifiers();
      var s = ASTClassSetterDeclaration(
        null,
        name,
        parameterType,
        parameterName,
        modifiers: modifiers,
      );
      _fillBlock(r, s);
      return s;
    },
  ),

  ASTNodeCodec<ASTSetterDeclaration>(
    ASTNodeTag.setterDeclaration,
    'ASTSetterDeclaration',
    encode: (w, n) => w.inDeclaration('set ${n.name}', () {
      w.str(n.name);
      w.type(n.parameterType);
      w.str(n.parameterName);
      w.modifiers(n.modifiers);
      writeBlockBody(w, n);
    }),
    decode: (r) {
      var name = r.str();
      var parameterType = r.type();
      var parameterName = r.str();
      var modifiers = r.modifiers();
      var s = ASTSetterDeclaration(
        name,
        parameterType,
        parameterName,
        modifiers: modifiers,
      );
      _fillBlock(r, s);
      return s;
    },
  ),

  // --- Parameters -----------------------------------------------------------
  ASTNodeCodec<ASTConstructorParameterDeclaration>(
    ASTNodeTag.constructorParameterDeclaration,
    'ASTConstructorParameterDeclaration',
    encode: (w, n) {
      w.type(n.type);
      w.str(n.name);
      w.uint(n.index);
      w.boolean(n.optional);
      w.boolean(n.thisParameter);
      w.boolean(n.isRequired);
      w.nodeOrNull(n.defaultValue);
    },
    decode: (r) {
      var type = r.type();
      var name = r.str();
      var index = r.uint();
      var optional = r.boolean();
      var thisParameter = r.boolean();
      var p = ASTConstructorParameterDeclaration(
        type,
        name,
        index,
        optional,
        thisParameter: thisParameter,
        isRequired: r.boolean(),
      );
      // Assigned after construction, exactly as the parsers do.
      p.defaultValue = r.nodeOrNull<ASTExpression>();
      return p;
    },
  ),

  ASTNodeCodec<ASTFunctionParameterDeclaration>(
    ASTNodeTag.functionParameterDeclaration,
    'ASTFunctionParameterDeclaration',
    encode: (w, n) {
      w.type(n.type);
      w.str(n.name);
      w.uint(n.index);
      w.boolean(n.optional);
      w.boolean(n.unmodifiable);
      w.boolean(n.isRequired);
      w.nodeOrNull(n.defaultValue);
    },
    decode: (r) {
      var type = r.type();
      var name = r.str();
      var index = r.uint();
      var optional = r.boolean();
      var unmodifiable = r.boolean();
      var p = ASTFunctionParameterDeclaration(
        type,
        name,
        index,
        optional,
        unmodifiable: unmodifiable,
        isRequired: r.boolean(),
      );
      p.defaultValue = r.nodeOrNull<ASTExpression>();
      return p;
    },
  ),
];

void _writeClassHeader(ASTBinaryWriteContext w, ASTClassNormal n) {
  w.str(n.name);
  w.enumByName(n.kind);
  w.strOrNull(n.superClassName);
  w.strings_(n.implementsTypes);
}

void _writeClassBody(ASTBinaryWriteContext w, ASTClassNormal n) {
  // `ASTClassNormal.children` lists only its methods — not its fields, not its
  // constructors — so each group is written explicitly. Constructor overload
  // sets are flattened to declarations; `addConstructor` rebuilds the split.
  w.nodes(n.fields);
  w.nodes([for (var set in n.constructors) ...set.functions]);
  writeBlockBody(w, n);
}

void _readClassBody(ASTBinaryReadContext r, ASTClassNormal clazz) {
  clazz.addAllFields(r.nodeList<ASTClassField>());
  clazz.addAllConstructors(r.nodeList<ASTClassConstructorDeclaration>());
  readBlockBody(r, clazz);
}

/// An enum's class kind is fixed by its constructor; a file claiming otherwise
/// is either corrupt or from a build where that changed.
void _assertEnumKind(ASTClassKind kind) {
  assert(
    kind == ASTClassKind.normalClass,
    'ASTClassEnum is always a normal class, got $kind',
  );
}
