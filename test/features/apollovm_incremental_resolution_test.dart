@TestOn('vm')
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

void main() {
  group('Incremental resolution', () {
    test('resolved modules are cached', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(
        SourceCodeUnit('dart', 'class User { User(); }', id: 'user.dart'),
      );
      await vm.loadCodeUnit(
        SourceCodeUnit('dart', "import 'user.dart';\n", id: 'main.dart'),
      );

      var engine = vm.resolutionEngine;
      var first = engine.resolveModule('main.dart');
      var second = engine.resolveModule('main.dart');
      expect(identical(first, second), isTrue, reason: 'served from cache');
      expect(engine.cache.contains('main.dart'), isTrue);
      expect(engine.cache.contains('user.dart'), isTrue);
    });

    test('reloading a module invalidates it and its dependents', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(
        SourceCodeUnit('dart', 'class User { User(); }', id: 'user.dart'),
      );
      await vm.loadCodeUnit(
        SourceCodeUnit('dart', "import 'user.dart';\n", id: 'main.dart'),
      );

      var engine = vm.resolutionEngine;
      engine.resolveModule('main.dart');
      expect(engine.cache.contains('main.dart'), isTrue);
      expect(engine.cache.contains('user.dart'), isTrue);

      // Reloading `user.dart` must invalidate user + its importer main.
      await vm.loadCodeUnit(
        SourceCodeUnit(
          'dart',
          'class User { User(); String v() { return \'v2\'; } }',
          id: 'user.dart',
        ),
      );

      expect(engine.cache.contains('user.dart'), isFalse);
      expect(engine.cache.contains('main.dart'), isFalse);
    });

    test('graph.affectedBy drives cache invalidation', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(
        SourceCodeUnit('dart', 'class Base { Base(); }', id: 'base.dart'),
      );
      await vm.loadCodeUnit(
        SourceCodeUnit(
          'dart',
          "import 'base.dart';\nclass User { User(); }",
          id: 'user.dart',
        ),
      );
      await vm.loadCodeUnit(
        SourceCodeUnit('dart', "import 'user.dart';\n", id: 'main.dart'),
      );

      var engine = vm.resolutionEngine;
      engine.resolveModule('main.dart');
      expect(engine.cache.length, greaterThanOrEqualTo(3));

      var affected = engine.invalidate('base.dart');
      expect(affected, containsAll(['base.dart', 'user.dart', 'main.dart']));
      expect(engine.cache.contains('base.dart'), isFalse);
      expect(engine.cache.contains('user.dart'), isFalse);
      expect(engine.cache.contains('main.dart'), isFalse);
    });
  });
}
