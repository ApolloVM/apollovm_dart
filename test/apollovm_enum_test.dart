@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Runs the top-level `run()` of [src] and returns its value.
Future<Object?> _run(String src) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', src, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source");
  var res = await vm.createRunner('dart')!.executeFunction('', 'run');
  return res.getValueNoContext();
}

void main() {
  group('Simple enum (entries are const instances)', () {
    const head = 'enum Color { red, green, blue }\n';

    test('.index is the ordinal', () async {
      expect(
        await _run('${head}int run() { var c = Color.blue; return c.index; }'),
        equals(2),
      );
    });

    test('.name is the entry name', () async {
      expect(
        await _run(
          '${head}String run() { var c = Color.green; return c.name; }',
        ),
        equals('green'),
      );
    });

    test('entries are identity-equal singletons', () async {
      expect(
        await _run('${head}bool run() { return Color.red == Color.red; }'),
        isTrue,
      );
      expect(
        await _run('${head}bool run() { return Color.red == Color.blue; }'),
        isFalse,
      );
    });

    test('.values lists all entries in order', () async {
      expect(
        await _run(
          '${head}String run() { var s = ""; '
          'for (var c in Color.values) { s = s + c.name; } return s; }',
        ),
        equals('redgreenblue'),
      );
    });
  });

  group('Rich/enhanced enum (constructor, fields, methods)', () {
    const planet = '''
enum Planet {
  earth(5.97, 6371), mars(0.642, 3389);
  final double mass;
  final double radius;
  const Planet(this.mass, this.radius);
  double gravity() { return mass / (radius * radius); }
}
''';

    test('entry constructor arg becomes a field', () async {
      expect(
        await _run(
          '${planet}double run() { var e = Planet.earth; return e.mass; }',
        ),
        closeTo(5.97, 1e-9),
      );
      expect(
        await _run(
          '${planet}double run() { var m = Planet.mars; return m.radius; }',
        ),
        closeTo(3389, 1e-9),
      );
    });

    test('method call on an entry (direct chain)', () async {
      var g = await _run(
        '${planet}double run() { return Planet.earth.gravity(); }',
      );
      expect(g as double, closeTo(5.97 / (6371 * 6371), 1e-15));
    });

    test('.index / .name on a rich entry', () async {
      expect(
        await _run(
          '${planet}int run() { var m = Planet.mars; return m.index; }',
        ),
        equals(1),
      );
      expect(
        await _run(
          '${planet}String run() { var e = Planet.earth; return e.name; }',
        ),
        equals('earth'),
      );
    });

    test('rich entries are identity-equal', () async {
      expect(
        await _run(
          '${planet}bool run() { return Planet.earth == Planet.earth; }',
        ),
        isTrue,
      );
    });
  });

  group('Explicit-value enum (`= N`)', () {
    const head = 'enum Level { Low = 1, Medium = 5, High = 10 }\n';

    test('.value exposes the explicit value; .index is the ordinal', () async {
      expect(
        await _run(
          '${head}int run() { var m = Level.Medium; return m.value; }',
        ),
        equals(5),
      );
      expect(
        await _run(
          '${head}int run() { var m = Level.Medium; return m.index; }',
        ),
        equals(1),
      );
    });
  });
}
