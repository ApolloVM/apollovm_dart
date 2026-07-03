import 'package:apollovm/apollovm.dart';
import 'package:apollovm/apollovm_pub.dart';

/// Demonstrates the OPTIONAL Dart package importer: `main.dart` imports a
/// `package:greeter/greeter.dart` library, which is fetched by a
/// [PackageProvider] and loaded into the VM before resolution/execution.
///
/// This example uses an in-memory provider so it runs offline. In a real
/// project you would use `PackageConfigProvider()` (resolves `package:` imports
/// from `.dart_tool/package_config.json`, i.e. your pubspec dependencies) or
/// `PubDevProvider(host: 'https://pub.dev')` (downloads from a pub host).
void main() async {
  var vm = ApolloVM();

  await vm.loadCodeUnit(
    SourceCodeUnit('dart', r'''
import 'package:greeter/greeter.dart';

void run() {
  var g = Greeter('bob');
  print(g.hi());
}
''', id: 'main.dart'),
  );

  // Install the package importer and fetch/load all `package:` imports.
  var loader = DartPackageLoader(vm, _InMemoryProvider());
  vm.moduleLoader = loader;

  var provisionDiagnostics = await loader.provision();
  print('--- provisioning ---');
  print(
    provisionDiagnostics.isEmpty
        ? 'All package: imports fetched.'
        : provisionDiagnostics.join('\n'),
  );

  print('--- resolving ---');
  var diagnostics = vm.resolve(language: 'dart');
  print(diagnostics.isEmpty ? 'No diagnostics.' : diagnostics.join('\n'));

  print('--- running main.run() ---');
  var runner = vm.createRunner('dart')!;
  runner.externalPrintFunction = (o) => print('» $o');
  await runner.executeFunction('', 'run', positionalParameters: []);
}

/// A minimal in-memory [PackageProvider] serving one package (offline demo).
/// Swap for `PackageConfigProvider()` / `PubDevProvider()` for real packages.
class _InMemoryProvider implements PackageProvider {
  static const _greeter = r'''
class Greeter {
  String name;
  Greeter(this.name);
  String hi() {
    return 'Hi ' + name;
  }
}
''';

  @override
  FutureOr<PackageSource?> resolvePackage(String pkg, String libPath) {
    if (pkg == 'greeter' && libPath == 'greeter.dart') {
      return PackageSource('package:greeter/greeter.dart', _greeter);
    }
    return null;
  }

  @override
  FutureOr<PackageSource?> resolvePackageUri(PackageUri uri) =>
      resolvePackage(uri.package, uri.libPath);

  @override
  FutureOr<Set<String>> availablePackages() => {'greeter'};
}

/////////////
// OUTPUT: //
/////////////
// --- provisioning ---
// All package: imports fetched.
// --- resolving ---
// No diagnostics.
// --- running main.run() ---
// » Hi bob
