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

  group('enum constant ranges', () {
    // An enum constant is a constructor invocation, so its range must cover the
    // whole entry — like a class member's range covers its parameters and body.
    String rangeOf(String src, String name) {
      final d = TokenIndex.scan(src).declarations.firstWhere(
        (d) => d.kind == DeclKind.enumMember && d.name == name,
      );
      return src.substring(d.fullStart, d.fullEnd);
    }

    test('covers the argument list', () {
      const src = '''
enum Planet {
  earth(5.97, 6371),
  mars(0.642, 3389);

  const Planet(this.mass, this.radius);
  final double mass;
  final double radius;
}
''';
      expect(rangeOf(src, 'earth'), 'earth(5.97, 6371)');
      expect(rangeOf(src, 'mars'), 'mars(0.642, 3389)');
      // The name span stays on the name alone, for selection/definition.
      final earth = TokenIndex.scan(
        src,
      ).declarations.firstWhere((d) => d.name == 'earth');
      expect(src.substring(earth.nameStart, earth.nameEnd), 'earth');
    });

    test('covers a named constructor and type arguments', () {
      const src = '''
enum Planet {
  mars.small(0.642, 3389),
  venus<double>(4.87, 6051);

  const Planet(this.mass, this.radius);
  const Planet.small(this.mass, this.radius);
}
''';
      expect(rangeOf(src, 'mars'), 'mars.small(0.642, 3389)');
      expect(rangeOf(src, 'venus'), 'venus<double>(4.87, 6051)');
    });

    test('covers an `= value` entry', () {
      const src = 'enum Code { ok = 1, fail = 2 }';
      expect(rangeOf(src, 'ok'), 'ok = 1');
      expect(rangeOf(src, 'fail'), 'fail = 2');
    });

    test('a bare constant is still just its name', () {
      const src = 'enum Color { red, green, blue }';
      expect(rangeOf(src, 'red'), 'red');
      expect(rangeOf(src, 'blue'), 'blue');
    });

    test('nested commas and braces do not end an entry', () {
      const src = '''
enum Group {
  a(const [1, 2], {'k': 'v'}),
  b(const [3], {});

  const Group(this.list, this.map);
}
''';
      expect(rangeOf(src, 'a'), "a(const [1, 2], {'k': 'v'})");
      expect(rangeOf(src, 'b'), 'b(const [3], {})');
    });

    test('named arguments are not mistaken for constants', () {
      const src = '''
enum Planet {
  earth(mass: 5.97, radius: 6371),
  mars(mass: 0.642, radius: 3389);

  const Planet({required this.mass, required this.radius});
  final double mass;
  final double radius;
}
''';
      final members = TokenIndex.scan(src).declarations
          .where((d) => d.kind == DeclKind.enumMember)
          .map((d) => d.name)
          .toList();
      expect(members, ['earth', 'mars']);
      expect(rangeOf(src, 'earth'), 'earth(mass: 5.97, radius: 6371)');
    });

    test('members after the constant list are recognised normally', () {
      const src = '''
enum Planet {
  earth(5.97, 6371);

  const Planet(this.mass, this.radius);

  final double mass;
  final double radius;

  double gravity() {
    return mass / (radius * radius);
  }
}
''';
      final decls = TokenIndex.scan(src).declarations;
      final ctor = decls.firstWhere((d) => d.kind == DeclKind.constructor);
      expect(
        src.substring(ctor.fullStart, ctor.fullEnd),
        'const Planet(this.mass, this.radius);',
      );
      final gravity = decls.firstWhere((d) => d.name == 'gravity');
      expect(gravity.kind, DeclKind.method);
      expect(
        src.substring(gravity.fullStart, gravity.fullEnd),
        contains('radius * radius'),
      );
      // The enum's own range still closes on its final brace.
      final planet = decls.firstWhere((d) => d.kind == DeclKind.enumDecl);
      expect(src.substring(planet.fullStart, planet.fullEnd), src.trim());
    });
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

  group('field / variable ranges cover the whole declaration', () {
    String fieldRangeOf(String src, String name) {
      final d = TokenIndex.scan(src).declarations.firstWhere(
        (d) =>
            (d.kind == DeclKind.field || d.kind == DeclKind.variable) &&
            d.name == name,
      );
      return src.substring(d.fullStart, d.fullEnd);
    }

    test('a field without an initializer covers up to `;`', () {
      const src = 'class Box {\n  int width;\n}\n';
      expect(fieldRangeOf(src, 'width'), 'int width;');
    });

    test('a field with an initializer covers the initializer', () {
      const src = 'class Box {\n  int count = 5;\n}\n';
      expect(fieldRangeOf(src, 'count'), 'int count = 5;');
    });

    test('a top-level variable covers its full initializer', () {
      const src = 'var total = 1 + 2;\n';
      expect(fieldRangeOf(src, 'total'), 'var total = 1 + 2;');
    });

    test('an initializer with brackets/commas is not cut short', () {
      const src = 'final xs = [1, 2, 3];\n';
      expect(fieldRangeOf(src, 'xs'), 'final xs = [1, 2, 3];');
    });

    test('the name span still covers only the name', () {
      const src = 'class Box {\n  int width;\n}\n';
      final d = TokenIndex.scan(
        src,
      ).declarations.firstWhere((d) => d.name == 'width');
      expect(src.substring(d.nameStart, d.nameEnd), 'width');
    });
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
