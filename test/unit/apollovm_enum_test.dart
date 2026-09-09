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

  group('Enum accessors (getters/setters in the enum body)', () {
    const level = '''
enum Level {
  low(1), high(10);
  final int weight;
  int extra = 0;
  const Level(this.weight);
  int get doubled => this.weight * 2;
  set boost(int x) { this.extra = x; }
}
''';

    test('a getter declared in the enum body runs on an entry', () async {
      expect(
        await _run(
          '${level}int run() { var h = Level.high; return h.doubled; }',
        ),
        equals(20),
      );
    });

    test('a setter declared in the enum body runs on an entry', () async {
      expect(
        await _run(
          '${level}int run() { var l = Level.low; l.boost = 7; return l.extra; }',
        ),
        equals(7),
      );
    });

    test('accessors survive a Dart round-trip', () async {
      var vm = ApolloVM();
      expect(
        await vm.loadCodeUnit(SourceCodeUnit('dart', level, id: 'test')),
        isTrue,
      );

      var code = (await vm.generateAllCodeIn('dart').writeAllSources())
          .toString();

      expect(code, contains('int get doubled {'));
      expect(code, contains('set boost(int x) {'));

      var vm2 = ApolloVM();
      var source = code
          .split('\n')
          .where((l) => !l.startsWith('<<<<'))
          .join('\n');
      expect(
        await vm2.loadCodeUnit(SourceCodeUnit('dart', source, id: 'test')),
        isTrue,
      );
    });

    test('Kotlin emits the getter; a target without accessors refuses', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(
        SourceCodeUnit(
          'dart',
          'enum Level { low(1), high(10); final int weight; '
              'const Level(this.weight); int get doubled => this.weight * 2; }',
          id: 'test',
        ),
      );

      var kotlin = (await vm.generateAllCodeIn('kotlin').writeAllSources())
          .toString();
      expect(kotlin, contains('val doubled: Int get()'));

      // Same refusal a *class* getter gets: dropping it would silently change
      // what the program means.
      for (var lang in ['java11', 'csharp', 'typescript', 'python']) {
        expect(
          () => vm.generateAllCodeIn(lang).writeAllSources(),
          throwsA(isA<UnsupportedSyntaxError>()),
          reason: 'Language $lang should refuse an enum getter',
        );
      }
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
