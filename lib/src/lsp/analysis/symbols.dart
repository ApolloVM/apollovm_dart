// Collects semantic symbol information from an ApolloVM [ASTRoot] and formats
// human-readable signatures for hover. The AST is the source of truth for
// *semantics* (names, types, parameters, modifiers); source *positions* come
// separately from the TokenIndex scanner.
import 'package:apollovm/apollovm.dart';

/// The semantic category of a collected symbol.
enum SymbolCategory {
  classSym,
  enumSym,
  function,
  method,
  constructor,
  getter,
  field,
  enumMember,
}

/// Semantic facts about one declaration, independent of its source position.
class SymbolInfo {
  final String name;
  final SymbolCategory category;

  /// Enclosing class/enum name, or null at top level.
  final String? container;

  /// A one-line signature, e.g. `User findUser(int id)`.
  final String signature;

  /// The declared/return type name, if meaningful.
  final String? typeName;

  final List<String> modifiers;

  const SymbolInfo({
    required this.name,
    required this.category,
    required this.signature,
    this.container,
    this.typeName,
    this.modifiers = const [],
  });
}

/// Walks [root] and returns every top-level and class-member declaration.
List<SymbolInfo> collectSymbols(ASTRoot root) {
  final out = <SymbolInfo>[];

  // Top-level functions.
  for (final set in root.functions) {
    for (final f in set.functions) {
      out.add(
        _invocable(f, container: null, category: SymbolCategory.function),
      );
    }
  }

  // Classes / enums and their members.
  for (final clazz in root.classes) {
    final isEnum = clazz is ASTClassEnum;
    out.add(
      SymbolInfo(
        name: clazz.name,
        category: isEnum ? SymbolCategory.enumSym : SymbolCategory.classSym,
        signature: _classSignature(clazz),
        typeName: clazz.name,
        modifiers: clazz.isAbstract ? const ['abstract'] : const [],
      ),
    );

    for (final field in clazz.fields) {
      out.add(
        SymbolInfo(
          name: field.name,
          category: SymbolCategory.field,
          container: clazz.name,
          signature: '${_typeName(field.type)} ${field.name}',
          typeName: _typeName(field.type),
          modifiers: field.modifiers.modifiers,
        ),
      );
    }

    for (final set in clazz.constructors) {
      for (final c in set.functions) {
        out.add(
          _invocable(
            c,
            container: clazz.name,
            category: SymbolCategory.constructor,
          ),
        );
      }
    }

    for (final set in clazz.functions) {
      for (final m in set.functions) {
        out.add(
          _invocable(m, container: clazz.name, category: SymbolCategory.method),
        );
      }
    }

    for (final g in clazz.getter) {
      out.add(
        SymbolInfo(
          name: g.name,
          category: SymbolCategory.getter,
          container: clazz.name,
          signature: '${_typeName(g.returnType)} get ${g.name}',
          typeName: _typeName(g.returnType),
          modifiers: g.modifiers.modifiers,
        ),
      );
    }

    if (clazz is ASTClassEnum) {
      for (final e in clazz.entries) {
        out.add(
          SymbolInfo(
            name: e.name,
            category: SymbolCategory.enumMember,
            container: clazz.name,
            signature: '${clazz.name}.${e.name}',
            typeName: clazz.name,
          ),
        );
      }
    }
  }

  // Extensions and their members. An unnamed extension has no symbol of its
  // own, but its members are still listed, contained by the extended type.
  for (final extension in root.extensions) {
    final targetName = extension.targetType.name;
    final container = extension.name ?? targetName;

    if (extension.name != null) {
      out.add(
        SymbolInfo(
          name: extension.name!,
          category: SymbolCategory.classSym,
          signature: 'extension ${extension.name} on $targetName',
          typeName: targetName,
        ),
      );
    }

    for (final set in extension.functions) {
      for (final m in set.functions) {
        out.add(
          _invocable(m, container: container, category: SymbolCategory.method),
        );
      }
    }

    for (final g in extension.getter) {
      out.add(
        SymbolInfo(
          name: g.name,
          category: SymbolCategory.getter,
          container: container,
          signature: '${_typeName(g.returnType)} get ${g.name}',
          typeName: _typeName(g.returnType),
          modifiers: g.modifiers.modifiers,
        ),
      );
    }
  }

  return out;
}

SymbolInfo _invocable(
  ASTInvocableDeclaration f, {
  required String? container,
  required SymbolCategory category,
}) {
  return SymbolInfo(
    name: f.name,
    category: category,
    container: container,
    signature: formatInvocable(f),
    typeName: _typeName(f.returnType),
    modifiers: f.modifiers.modifiers,
  );
}

/// Formats an invocable declaration as `Ret name(T1 a, T2 b)`.
String formatInvocable(ASTInvocableDeclaration f) {
  final params = <String>[];
  for (final p in f.parameters.allParameters) {
    params.add('${_typeName(p.type)} ${p.name}');
  }
  final ret = _typeName(f.returnType);
  final prefix = ret.isEmpty ? '' : '$ret ';
  return '$prefix${f.name}(${params.join(', ')})';
}

String _classSignature(ASTClassNormal clazz) {
  final buf = StringBuffer();
  if (clazz is ASTClassEnum) {
    buf.write('enum ');
  } else {
    if (clazz.isAbstract) buf.write('abstract ');
    buf.write(clazz.isInterface ? 'interface ' : 'class ');
  }
  buf.write(clazz.name);
  if (clazz.superClassName != null) {
    buf.write(' extends ${clazz.superClassName}');
  }
  final impls = clazz.implementsTypes;
  if (impls != null && impls.isNotEmpty) {
    buf.write(' implements ${impls.join(', ')}');
  }
  return buf.toString();
}

String _typeName(ASTType? type) {
  if (type == null) return '';
  final name = type.name;
  return name;
}
