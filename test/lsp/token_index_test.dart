import 'package:apollovm/apollovm_lsp.dart';
import 'package:test/test.dart';

const _src = '''
/// doc
class Box {
  int width;
  String label;

  int area() {
    return width;
  }
}

int total(int n) {
  var s = "class not a decl";
  return n;
}
''';

void main() {
  group('TokenIndex.scan', () {
    final idx = TokenIndex.scan(_src);

    DeclSite decl(String name) =>
        idx.declarations.firstWhere((d) => d.name == name);

    test('recognises class, fields, method and top-level function', () {
      final kinds = {for (final d in idx.declarations) d.name: d.kind};
      expect(kinds['Box'], DeclKind.classDecl);
      expect(kinds['width'], DeclKind.field);
      expect(kinds['label'], DeclKind.field);
      expect(kinds['area'], DeclKind.method);
      expect(kinds['total'], DeclKind.function);
    });

    test('nests members under their container', () {
      expect(decl('width').container, 'Box');
      expect(decl('area').container, 'Box');
      expect(decl('total').container, isNull);
    });

    test('name spans point at the identifier', () {
      final d = decl('Box');
      expect(_src.substring(d.nameStart, d.nameEnd), 'Box');
    });

    test('does not index identifiers inside strings or comments', () {
      // "class" appears in a string literal and "doc" in a comment.
      expect(idx.identifiers.any((t) => t.name == 'doc'), isFalse);
      // The string body must not have produced identifier tokens.
      final s = _src.indexOf('not a decl');
      expect(idx.identifierAt(s), isNull);
    });

    test('identifierAt finds the token under an offset', () {
      final at = _src.indexOf('area');
      expect(idx.identifierAt(at)?.name, 'area');
    });
  });

  test('captures every enum member', () {
    final idx = TokenIndex.scan('''
enum Color { red, green, blue }
''');
    final members = idx.declarations
        .where((d) => d.kind == DeclKind.enumMember)
        .map((d) => d.name)
        .toList();
    expect(members, ['red', 'green', 'blue']);
  });

  test('recognises top-level variables (var / final) and class fields', () {
    final idx = TokenIndex.scan('''
var count = 0;
final int limit = 10;
class Config {
  static final int max = 5;
}
''');
    final kinds = {for (final d in idx.declarations) d.name: d.kind};
    expect(kinds['count'], DeclKind.variable);
    expect(kinds['limit'], DeclKind.variable);
    expect(kinds['max'], DeclKind.field);
    expect(kinds['Config'], DeclKind.classDecl);
  });

  test('handles generic return types and a constructor', () {
    final idx = TokenIndex.scan('''
class Box {
  Box(int n) {}
  List<int> items() {
    return [];
  }
}
''');
    final box = idx.declarations.firstWhere((d) => d.name == 'Box');
    // Constructor: member named like its class.
    expect(
      idx.declarations.any(
        (d) => d.name == 'Box' && d.kind == DeclKind.constructor,
      ),
      isTrue,
    );
    expect(box.kind, DeclKind.classDecl);
    final items = idx.declarations.firstWhere((d) => d.name == 'items');
    expect(items.kind, DeclKind.method);
    expect(items.container, 'Box');
  });

  test('skips annotations without losing the following declaration', () {
    final idx = TokenIndex.scan('''
class S {
  @Deprecated("x")
  int old() {
    return 0;
  }
}
''');
    expect(
      idx.declarations.any((d) => d.name == 'old' && d.container == 'S'),
      isTrue,
    );
  });
}
