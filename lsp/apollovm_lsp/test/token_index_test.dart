import 'package:apollovm_lsp/apollovm_lsp.dart';
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
}
