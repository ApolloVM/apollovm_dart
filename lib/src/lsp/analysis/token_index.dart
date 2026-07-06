// A small, self-contained lexical scanner over raw source. It exists purely to
// recover the source *positions* the ApolloVM AST does not carry, so the
// language server can map a cursor offset to an identifier and locate the
// source spans of declarations.
//
// This is intentionally NOT the ApolloVM grammar: it is a shallow, forgiving
// scan (identifiers, comments, strings, punctuation) plus a boundary-driven
// declaration recogniser for the common C-family shapes ApolloVM's languages
// share (class/enum bodies, `Type name(...)` members, `Type name;` fields). The
// AST remains the source of truth for *semantics*; this supplies *geometry*.

/// The lexical category of a scanned identifier occurrence.
enum IdentRole { plain }

/// An identifier occurrence in the source, with its `[start, end)` UTF-16 span.
class IdentToken {
  final String name;
  final int start;
  final int end;

  const IdentToken(this.name, this.start, this.end);
}

/// The kind of a recognised declaration site.
enum DeclKind {
  classDecl,
  enumDecl,
  function,
  method,
  constructor,
  field,
  variable,
  enumMember,
}

/// A declaration recognised in the source, carrying its name span (for
/// selection/definition) and full span (for the symbol's outer range).
class DeclSite {
  final String name;
  final DeclKind kind;
  final int nameStart;
  final int nameEnd;
  int fullStart;
  int fullEnd;

  /// Enclosing class/enum name, or null at top level.
  final String? container;

  DeclSite({
    required this.name,
    required this.kind,
    required this.nameStart,
    required this.nameEnd,
    required this.fullStart,
    required this.fullEnd,
    this.container,
  });
}

/// Keywords that begin a *statement*, so a run starting with one is never a
/// declaration (guards against reading `return foo(...)` as a function decl).
const _statementKeywords = {
  'return',
  'if',
  'else',
  'for',
  'while',
  'do',
  'switch',
  'case',
  'default',
  'break',
  'continue',
  'throw',
  'try',
  'catch',
  'finally',
  'new',
  'await',
  'yield',
  'assert',
  'import',
  'export',
  'part',
  'library',
  'package',
  'in',
  'is',
  'as',
  'super',
  'this',
};

/// Type/parameter modifier keywords that may lead a declaration run.
const _modifierKeywords = {
  'static',
  'final',
  'const',
  'var',
  'abstract',
  'public',
  'private',
  'protected',
  'external',
  'async',
  'get',
  'set',
  'late',
  'covariant',
  'fun',
  'val',
  'def',
  'function',
  'void',
};

const _classKeywords = {'class', 'interface', 'mixin'};
const _enumKeywords = {'enum'};

class _Tok {
  final int type; // 0 ident/keyword, 1 symbol, 2 string, 3 number
  final String value;
  final int start;
  final int end;
  // Whether a newline separates this token from the previous one. Used to
  // bound brace-less expression bodies (Kotlin `fun f() = expr`) to their line.
  bool nlBefore = false;
  _Tok(this.type, this.value, this.start, this.end);
  bool get isIdent => type == 0;
  bool sym(String s) => type == 1 && value == s;
}

/// The result of scanning one document: all identifier occurrences (for
/// cursor→symbol mapping) and all recognised declaration sites.
class TokenIndex {
  final List<IdentToken> identifiers;
  final List<DeclSite> declarations;

  TokenIndex._(this.identifiers, this.declarations);

  /// The identifier occurrence covering [offset], or null.
  IdentToken? identifierAt(int offset) {
    // Binary search on start; identifiers are non-overlapping and ordered.
    var lo = 0, hi = identifiers.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final t = identifiers[mid];
      if (offset < t.start) {
        hi = mid - 1;
      } else if (offset > t.end) {
        lo = mid + 1;
      } else {
        return t;
      }
    }
    return null;
  }

  /// The declaration named [name], optionally within [container].
  DeclSite? findDeclaration(String name, {String? container}) {
    DeclSite? fallback;
    for (final d in declarations) {
      if (d.name != name) continue;
      if (container != null && d.container == container) return d;
      fallback ??= d;
    }
    return fallback;
  }

  static TokenIndex scan(String text) {
    final tokens = _tokenize(text);
    final identifiers = <IdentToken>[
      for (final t in tokens)
        if (t.isIdent) IdentToken(t.value, t.start, t.end),
    ];
    final declarations = _extractDeclarations(tokens);
    return TokenIndex._(identifiers, declarations);
  }

  // --- Lexer ---

  static List<_Tok> _tokenize(String text) {
    final tokens = <_Tok>[];
    final n = text.length;
    var i = 0;

    // Set when a newline has been skipped since the previous token; stamped on
    // the next emitted token (and then cleared).
    var pendingNl = false;
    void add(int type, String value, int start, int end) {
      final t = _Tok(type, value, start, end);
      t.nlBefore = pendingNl;
      pendingNl = false;
      tokens.add(t);
    }

    bool isIdentStart(int c) =>
        (c >= 0x41 && c <= 0x5a) ||
        (c >= 0x61 && c <= 0x7a) ||
        c == 0x5f ||
        c == 0x24;
    bool isDigit(int c) => c >= 0x30 && c <= 0x39;
    bool isIdentPart(int c) => isIdentStart(c) || isDigit(c);

    while (i < n) {
      final c = text.codeUnitAt(i);

      // Whitespace.
      if (c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d) {
        if (c == 0x0a) pendingNl = true;
        i++;
        continue;
      }

      // Comments.
      if (c == 0x2f && i + 1 < n) {
        final c2 = text.codeUnitAt(i + 1);
        if (c2 == 0x2f) {
          i += 2;
          while (i < n && text.codeUnitAt(i) != 0x0a) {
            i++;
          }
          continue;
        }
        if (c2 == 0x2a) {
          i += 2;
          var depth = 1;
          while (i < n && depth > 0) {
            if (text.codeUnitAt(i) == 0x0a) pendingNl = true;
            if (i + 1 < n &&
                text.codeUnitAt(i) == 0x2f &&
                text.codeUnitAt(i + 1) == 0x2a) {
              depth++;
              i += 2;
            } else if (i + 1 < n &&
                text.codeUnitAt(i) == 0x2a &&
                text.codeUnitAt(i + 1) == 0x2f) {
              depth--;
              i += 2;
            } else {
              i++;
            }
          }
          continue;
        }
      }

      // Strings ('...', "...", plus triple-quoted). Content is skipped whole.
      if (c == 0x27 || c == 0x22) {
        final start = i;
        i = _skipString(text, i);
        add(2, text.substring(start, i), start, i);
        continue;
      }

      // Identifiers / keywords.
      if (isIdentStart(c)) {
        final start = i;
        i++;
        while (i < n && isIdentPart(text.codeUnitAt(i))) {
          i++;
        }
        add(0, text.substring(start, i), start, i);
        continue;
      }

      // Numbers.
      if (isDigit(c)) {
        final start = i;
        i++;
        while (i < n) {
          final d = text.codeUnitAt(i);
          if (isDigit(d) ||
              d == 0x2e ||
              d == 0x78 ||
              (d >= 0x61 && d <= 0x66)) {
            i++;
          } else {
            break;
          }
        }
        add(3, text.substring(start, i), start, i);
        continue;
      }

      // Single-character symbol.
      add(1, text[i], i, i + 1);
      i++;
    }
    return tokens;
  }

  static int _skipString(String text, int i) {
    final n = text.length;
    final quote = text.codeUnitAt(i);
    // Triple-quoted?
    if (i + 2 < n &&
        text.codeUnitAt(i + 1) == quote &&
        text.codeUnitAt(i + 2) == quote) {
      i += 3;
      while (i < n) {
        if (text.codeUnitAt(i) == 0x5c) {
          i += 2;
          continue;
        }
        if (i + 2 < n &&
            text.codeUnitAt(i) == quote &&
            text.codeUnitAt(i + 1) == quote &&
            text.codeUnitAt(i + 2) == quote) {
          return i + 3;
        }
        i++;
      }
      return i;
    }
    // Single-line string.
    i++;
    while (i < n) {
      final c = text.codeUnitAt(i);
      if (c == 0x5c) {
        i += 2;
        continue;
      }
      if (c == quote) return i + 1;
      if (c == 0x0a) return i; // Unterminated; stop at newline.
      i++;
    }
    return i;
  }

  // --- Declaration recogniser ---

  static List<DeclSite> _extractDeclarations(List<_Tok> tokens) {
    final decls = <DeclSite>[];
    // Stack of open class/enum bodies: (name, bodyDepth, isEnum, declIndex).
    final classStack = <_ClassScope>[];
    // Stack of open function/method/constructor bodies: (declIndex, bodyDepth).
    // Lets a member's `fullEnd` be extended to its body's closing `}` (so the
    // declaration range covers the whole method, not just its signature).
    final bodyStack = <_BodyScope>[];
    var braceDepth = 0;
    var atBoundary = true;

    int enclosingBodyDepth() =>
        classStack.isEmpty ? -1 : classStack.last.bodyDepth;
    String? enclosingName() => classStack.isEmpty ? null : classStack.last.name;
    bool inEnumBody() =>
        classStack.isNotEmpty &&
        classStack.last.isEnum &&
        braceDepth == classStack.last.bodyDepth;
    // True only while scanning the enum's constant list (before the `;` that
    // ends it). After that `;`, an enum body holds ordinary members (fields,
    // constructors, methods) that must be recognised like class members.
    bool inEnumConstantList() =>
        inEnumBody() && !classStack.last.enumConstantsDone;

    _ClassScope? pendingClass;
    // Index of a member whose body brace is expected next (armed once its
    // parameter list has been consumed); `null` when no body is pending.
    int? pendingBody;

    // Expression-body tracking (`=> expr;` in Dart/C#, `= expr` in Kotlin). When
    // a member has an expression body instead of a `{ ... }` block, we extend
    // its `fullEnd` across the whole expression so the declaration is fully
    // selectable. `exprMember` is the member's decl index; `exprArrow` marks the
    // `=>` form (terminated by `;`) vs. the brace-less `=` form (bounded by the
    // end of its line); `exprDepth` balances `()[]{}` opened inside the
    // expression so the terminator/enclosing `}` is only honoured at depth 0.
    int? exprMember;
    var exprArrow = false;
    var exprDepth = 0;

    var i = 0;
    while (i < tokens.length) {
      final t = tokens[i];

      // Consume an in-progress expression body.
      if (exprMember != null) {
        if (exprDepth == 0 && (t.sym('}') || (!exprArrow && t.nlBefore))) {
          // The enclosing block's `}` or a new line (brace-less form) ends the
          // expression; do not consume this token — fall through to reprocess
          // it as the start of the next declaration.
          exprMember = null;
          atBoundary = true;
        } else if (exprDepth == 0 && t.sym(';')) {
          decls[exprMember].fullEnd = t.end;
          exprMember = null;
          atBoundary = true;
          i++;
          continue;
        } else {
          if (t.sym('(') || t.sym('[') || t.sym('{')) {
            exprDepth++;
          } else if (t.sym(')') || t.sym(']') || t.sym('}')) {
            exprDepth--;
          }
          decls[exprMember].fullEnd = t.end;
          i++;
          continue;
        }
      }

      // Annotations/metadata (`@Override`, `@Deprecated("x")`) precede a
      // declaration and must not clear the boundary flag.
      if (t.sym('@')) {
        i++; // past '@'
        if (i < tokens.length && tokens[i].isIdent) i++; // annotation name
        // Skip a qualified name (`@a.b.c`).
        while (i + 1 < tokens.length &&
            tokens[i].sym('.') &&
            tokens[i + 1].isIdent) {
          i += 2;
        }
        // Skip a balanced argument list.
        if (i < tokens.length && tokens[i].sym('(')) {
          var depth = 0;
          while (i < tokens.length) {
            if (tokens[i].sym('(')) depth++;
            if (tokens[i].sym(')')) {
              depth--;
              i++;
              if (depth == 0) break;
              continue;
            }
            i++;
          }
        }
        continue; // boundary unchanged
      }

      if (t.sym('{')) {
        braceDepth++;
        if (pendingClass != null) {
          final pc = pendingClass!;
          pc.bodyDepth = braceDepth;
          classStack.add(pc);
          pendingClass = null;
        } else if (pendingBody != null) {
          bodyStack.add(_BodyScope(pendingBody, braceDepth));
          pendingBody = null;
        }
        atBoundary = true;
        i++;
        continue;
      }
      if (t.sym('}')) {
        // Close any function/method bodies ending at this depth.
        while (bodyStack.isNotEmpty && bodyStack.last.bodyDepth == braceDepth) {
          final closed = bodyStack.removeLast();
          decls[closed.declIndex].fullEnd = t.end;
        }
        // Close any class bodies at this depth.
        while (classStack.isNotEmpty &&
            classStack.last.bodyDepth == braceDepth) {
          final closed = classStack.removeLast();
          decls[closed.declIndex].fullEnd = t.end;
        }
        pendingBody = null;
        braceDepth--;
        atBoundary = true;
        i++;
        continue;
      }
      if (t.sym(';')) {
        // A `;` directly in an enum body ends its constant list; everything
        // after it is a regular member.
        if (inEnumBody()) classStack.last.enumConstantsDone = true;
        // A `;` before the body brace means the member has no body (abstract
        // method, `=>` expression body, field): drop the pending arm.
        pendingBody = null;
        atBoundary = true;
        i++;
        continue;
      }
      if (t.sym(',')) {
        // Commas separate entries only within an enum's constant list;
        // elsewhere (e.g. parameter lists) they must not open a new boundary.
        atBoundary = inEnumConstantList();
        i++;
        continue;
      }

      // A pending member with an expression body: `=> expr` (Dart/C#) or a
      // brace-less `= expr` (Kotlin). Start consuming the expression so the
      // member's range covers it (handled at the top of the loop).
      if (pendingBody != null && t.sym('=')) {
        final arrow = i + 1 < tokens.length && tokens[i + 1].sym('>');
        exprMember = pendingBody;
        exprArrow = arrow;
        exprDepth = 0;
        pendingBody = null;
        atBoundary = false;
        i += arrow ? 2 : 1; // consume '=' (and '>' of '=>')
        continue;
      }

      // Enum constants: identifiers in the enum's constant list (before `;`).
      if (inEnumConstantList() && t.isIdent && atBoundary) {
        decls.add(
          DeclSite(
            name: t.value,
            kind: DeclKind.enumMember,
            nameStart: t.start,
            nameEnd: t.end,
            fullStart: t.start,
            fullEnd: t.end,
            container: enclosingName(),
          ),
        );
        // Skip to the next comma/brace.
        i++;
        while (i < tokens.length &&
            !tokens[i].sym(',') &&
            !tokens[i].sym('}') &&
            !tokens[i].sym('{') &&
            !tokens[i].sym(';')) {
          i++;
        }
        atBoundary = false;
        continue;
      }

      // Only recognise declarations at top level or directly in a class body.
      final atDeclLevel = braceDepth == 0 || braceDepth == enclosingBodyDepth();

      if (atBoundary && atDeclLevel && (t.isIdent)) {
        final consumed = _tryDeclaration(
          tokens,
          i,
          container: enclosingName(),
          onClass: (scope) => pendingClass = scope,
          onDecl: decls.add,
          nextDeclIndex: () => decls.length,
        );
        if (consumed > 0) {
          i += consumed;
          atBoundary = false;
          // For a function/method/constructor, `_tryDeclaration` stops before
          // the parameter list. Skip its balanced `( ... )` here (so nested
          // named-parameter braces aren't mistaken for the body) and arm body
          // tracking so the next `{` is recorded as this member's body.
          pendingBody = null;
          final added = decls.last;
          if (added.kind == DeclKind.function ||
              added.kind == DeclKind.method ||
              added.kind == DeclKind.constructor) {
            if (i < tokens.length && tokens[i].sym('(')) {
              var depth = 0;
              while (i < tokens.length) {
                if (tokens[i].sym('(')) {
                  depth++;
                } else if (tokens[i].sym(')')) {
                  depth--;
                  i++;
                  if (depth == 0) break;
                  continue;
                }
                i++;
              }
            }
            pendingBody = decls.length - 1;
          }
          continue;
        }
      }

      atBoundary = false;
      i++;
    }
    return decls;
  }

  /// Attempts to read a declaration run starting at [start]. Returns the number
  /// of tokens consumed (0 if not a declaration).
  static int _tryDeclaration(
    List<_Tok> tokens,
    int start, {
    required String? container,
    required void Function(_ClassScope) onClass,
    required void Function(DeclSite) onDecl,
    required int Function() nextDeclIndex,
  }) {
    final first = tokens[start];
    if (first.isIdent && _statementKeywords.contains(first.value)) return 0;

    // class / enum / mixin declaration.
    if (first.isIdent &&
        (_classKeywords.contains(first.value) ||
            _enumKeywords.contains(first.value))) {
      final isEnum = _enumKeywords.contains(first.value);
      // The class name is the next identifier.
      var j = start + 1;
      while (j < tokens.length && !tokens[j].isIdent) {
        if (tokens[j].sym('{') || tokens[j].sym(';')) break;
        j++;
      }
      if (j >= tokens.length || !tokens[j].isIdent) return 0;
      final nameTok = tokens[j];
      final declIndex = nextDeclIndex();
      onDecl(
        DeclSite(
          name: nameTok.value,
          kind: isEnum ? DeclKind.enumDecl : DeclKind.classDecl,
          nameStart: nameTok.start,
          nameEnd: nameTok.end,
          fullStart: first.start,
          fullEnd: nameTok.end,
          container: container,
        ),
      );
      onClass(_ClassScope(nameTok.value, isEnum, declIndex));
      return j - start + 1;
    }

    // Scan a run up to a terminator, tracking identifiers and generic depth.
    final idents = <_Tok>[];
    var j = start;
    var angle = 0;
    while (j < tokens.length) {
      final t = tokens[j];
      if (t.isIdent) {
        if (_statementKeywords.contains(t.value)) return 0;
        idents.add(t);
        j++;
        continue;
      }
      if (t.sym('<')) {
        angle++;
        j++;
        continue;
      }
      if (t.sym('>')) {
        if (angle > 0) angle--;
        j++;
        continue;
      }
      if (t.sym('.') || t.sym(',') && angle > 0) {
        j++;
        continue;
      }
      if (angle > 0) {
        j++;
        continue;
      }
      // Terminators.
      if (t.sym('(') ||
          t.sym(';') ||
          t.sym('=') ||
          t.sym('{') ||
          t.sym('}') ||
          t.sym(',') ||
          t.sym(')')) {
        break;
      }
      j++;
    }

    if (idents.isEmpty) return 0;
    final nameTok = idents.last;
    final terminator = j < tokens.length ? tokens[j] : null;

    if (terminator != null && terminator.sym('(')) {
      // Function / method / constructor.
      final isConstructor = container != null && nameTok.value == container;
      final kind = container == null
          ? DeclKind.function
          : (isConstructor ? DeclKind.constructor : DeclKind.method);
      onDecl(
        DeclSite(
          name: nameTok.value,
          kind: kind,
          nameStart: nameTok.start,
          nameEnd: nameTok.end,
          fullStart: idents.first.start,
          fullEnd: nameTok.end,
          container: container,
        ),
      );
      return j - start; // Stop before '(' so the body braces are still seen.
    }

    if (terminator != null &&
        (terminator.sym(';') || terminator.sym('=') || terminator.sym(','))) {
      // Field / variable — require a type + name (or a leading modifier).
      final hasType =
          idents.length >= 2 ||
          (start > 0 &&
              tokens[start].isIdent &&
              _modifierKeywords.contains(tokens[start].value));
      if (!hasType) return 0;
      onDecl(
        DeclSite(
          name: nameTok.value,
          kind: container == null ? DeclKind.variable : DeclKind.field,
          nameStart: nameTok.start,
          nameEnd: nameTok.end,
          fullStart: idents.first.start,
          fullEnd: nameTok.end,
          container: container,
        ),
      );
      return j - start;
    }

    return 0;
  }
}

class _ClassScope {
  final String name;
  final bool isEnum;
  final int declIndex;
  int bodyDepth = -1;
  // For enums: set once the constant list's terminating `;` is seen, after
  // which members are parsed like class members rather than enum constants.
  bool enumConstantsDone = false;
  _ClassScope(this.name, this.isEnum, this.declIndex);
}

class _BodyScope {
  final int declIndex;
  final int bodyDepth;
  _BodyScope(this.declIndex, this.bodyDepth);
}
