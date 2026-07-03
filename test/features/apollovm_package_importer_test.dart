@TestOn('vm')
library;

import 'package:apollovm/apollovm.dart';
import 'package:apollovm/apollovm_pub.dart';
import 'package:test/test.dart';

/// A test [PackageProvider] serving in-memory, ApolloVM-compatible Dart sources.
class _MapPackageProvider implements PackageProvider {
  final Map<String, String> sources; // 'pkg/libPath.dart' -> source

  _MapPackageProvider(this.sources);

  @override
  FutureOr<PackageSource?> resolvePackage(String pkg, String libPath) {
    var key = '$pkg/$libPath';
    var src = sources[key];
    return src == null ? null : PackageSource('package:$key', src);
  }

  @override
  FutureOr<PackageSource?> resolvePackageUri(PackageUri uri) =>
      resolvePackage(uri.package, uri.libPath);

  @override
  FutureOr<Set<String>> availablePackages() =>
      sources.keys.map((k) => k.split('/').first).toSet();
}

void main() {
  group('PackageUri', () {
    test('parses package: URIs (quotes tolerated)', () {
      var u = PackageUri.tryParse("'package:foo/src/bar.dart'")!;
      expect(u.package, 'foo');
      expect(u.libPath, 'src/bar.dart');
      expect(u.moduleId, 'package:foo/src/bar.dart');
    });

    test('rejects non-package paths', () {
      expect(PackageUri.tryParse('./local.dart'), isNull);
      expect(PackageUri.tryParse('dart:math'), isNull);
      expect(PackageUri.tryParse('package:foo'), isNull); // no lib path
    });
  });

  group('PackageConfigProvider (real package_config.json)', () {
    test('lists available packages and fetches a real source', () async {
      var provider = PackageConfigProvider();
      var pkgs = await provider.availablePackages();
      expect(pkgs, contains('collection'));
      expect(pkgs, contains('path'));

      var src = await provider.resolvePackage('collection', 'collection.dart');
      expect(src, isNotNull);
      expect(src!.moduleId, 'package:collection/collection.dart');
      expect(src.source, isNotEmpty);

      // Unknown package / file → null.
      expect(await provider.resolvePackage('nope_pkg_x', 'x.dart'), isNull);
      expect(await provider.resolvePackage('collection', 'nope.dart'), isNull);
    });
  });

  group('DartPackageLoader + provision (end-to-end)', () {
    test('resolves and executes a package: import', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(
        SourceCodeUnit('dart', r'''
import 'package:greeter/greeter.dart';

String run() {
  var g = Greeter('bob');
  return g.hi();
}
''', id: 'main.dart'),
      );

      var loader = DartPackageLoader(
        vm,
        _MapPackageProvider({
          'greeter/greeter.dart': r'''
class Greeter {
  String name;
  Greeter(this.name);
  String hi() { return 'Hi ' + name; }
}
''',
        }),
      );
      vm.moduleLoader = loader;

      var provisionDiags = await loader.provision();
      expect(provisionDiags, isEmpty);

      // The package source is now a loaded module.
      expect(
        vm.allCodeUnits('dart').map((u) => u.id),
        contains('package:greeter/greeter.dart'),
      );

      var resolveDiags = vm.resolve(language: 'dart');
      expect(resolveDiags, isEmpty);

      var runner = vm.createRunner('dart')!;
      var r = await runner.executeFunction('', 'run', positionalParameters: []);
      expect(r.getValueNoContext(), equals('Hi bob'));
    });

    test('transitively provisions nested package: imports', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(
        SourceCodeUnit('dart', "import 'package:a/a.dart';\n", id: 'main.dart'),
      );

      var loader = DartPackageLoader(
        vm,
        _MapPackageProvider({
          'a/a.dart': "import 'package:b/b.dart';\nclass A { A(); }",
          'b/b.dart': 'class B { B(); }',
        }),
      );
      vm.moduleLoader = loader;
      await loader.provision();

      var ids = vm.allCodeUnits('dart').map((u) => u.id).toSet();
      expect(ids, containsAll(['package:a/a.dart', 'package:b/b.dart']));
    });

    test('reports a diagnostic for an unresolvable package', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(
        SourceCodeUnit(
          'dart',
          "import 'package:missing/x.dart';\n",
          id: 'main.dart',
        ),
      );

      var loader = DartPackageLoader(vm, _MapPackageProvider(const {}));
      vm.moduleLoader = loader;
      var diags = await loader.provision();
      expect(
        diags.where((d) => d.kind == ImportDiagnosticKind.missingModule),
        isNotEmpty,
      );
    });
  });

  group('CompositeModuleLoader', () {
    test('delegates to the first loader that resolves', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(
        SourceCodeUnit('dart', 'class Local { Local(); }', id: 'local.dart'),
      );

      var composite = CompositeModuleLoader([VMModuleLoader(vm)]);
      expect(composite.resolveModuleId('local.dart'), 'local.dart');
      expect(composite.loadModule('local.dart'), isNotNull);
      expect(composite.resolveModuleId('nope.dart'), isNull);
      expect(composite.resolveCorePackage('dart:math'), isNotNull);
    });
  });
}
