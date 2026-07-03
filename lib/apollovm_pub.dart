// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

/// Optional Dart package importer for ApolloVM.
///
/// This is an **opt-in** entrypoint, intentionally NOT re-exported from the
/// web-safe `package:apollovm/apollovm.dart`. It resolves Dart `package:`
/// imports against real pub packages — from a project's
/// `.dart_tool/package_config.json` ([PackageConfigProvider], the default,
/// dependency-free) or by downloading from a pub host ([PubDevProvider]).
///
/// Web-safe: the filesystem/network providers are pulled in only when
/// `dart:io` is available; web builds get no-op stubs.
///
/// Usage:
/// ```dart
/// import 'package:apollovm/apollovm.dart';
/// import 'package:apollovm/apollovm_pub.dart';
///
/// final vm = ApolloVM();
/// await vm.loadCodeUnit(SourceCodeUnit('dart', mainSource, id: 'main.dart'));
///
/// final loader = DartPackageLoader(vm, PackageConfigProvider());
/// vm.moduleLoader = loader;
/// await loader.provision();      // fetch/load `package:` imports
/// final diagnostics = vm.resolve(language: 'dart');
/// ```
library;

export 'src/pub/dart_package_loader.dart';
export 'src/pub/package_cache.dart';
export 'src/pub/package_provider.dart';
export 'src/pub/pubdev_provider.dart';
export 'src/resolution/composite_module_loader.dart';
// IO-only members (`PackageConfigProvider`, `FilePackageCache`); web builds get
// no-op/in-memory stubs. `PubDevProvider` above is web-safe and unconditional.
export 'src/pub/pub_stub.dart' if (dart.library.io) 'src/pub/pub_io.dart';
