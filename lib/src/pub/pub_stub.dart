// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

/// Web fallback for the optional Dart package importer.
///
/// The real providers (`PackageConfigProvider`, `PubDevProvider`) require
/// `dart:io`/`http` and are unavailable on the web; these no-op stubs keep
/// `lib/apollovm_pub.dart` compilable for web without pulling in `dart:io`.
library;

import '../../src/pub/package_provider.dart';

/// Web no-op stand-in for `PackageConfigProvider` (resolves nothing).
class PackageConfigProvider extends NoopPackageProvider {
  PackageConfigProvider({String? projectDir, bool runPubGetIfMissing = false});
}

/// Web no-op stand-in for `PubDevProvider` (resolves nothing).
class PubDevProvider extends NoopPackageProvider {
  final String host;

  PubDevProvider({
    this.host = 'https://pub.dev',
    String? cacheDir,
    String? pubspecPath,
    Object? client,
  });

  void close() {}
}
