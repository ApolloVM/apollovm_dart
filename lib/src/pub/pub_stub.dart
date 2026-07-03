// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

/// Web fallbacks for the IO-only members of the optional package importer.
///
/// `PubDevProvider` is web-safe and exported unconditionally from
/// `lib/apollovm_pub.dart`; only the filesystem-based `PackageConfigProvider`
/// and the disk-backed `FilePackageCache` need web stand-ins so the entrypoint
/// compiles for the web without pulling in `dart:io`.
library;

import 'package_cache.dart';
import 'package_provider.dart';

/// Web no-op stand-in for `PackageConfigProvider` (resolves nothing — there is
/// no local pub cache / `.dart_tool/package_config.json` on the web).
class PackageConfigProvider extends NoopPackageProvider {
  PackageConfigProvider({String? projectDir, bool runPubGetIfMissing = false});
}

/// Web stand-in for `FilePackageCache`: no filesystem on the web, so it behaves
/// as an in-memory cache (the [directory] argument is ignored).
class FilePackageCache extends MemoryPackageCache implements PackageCache {
  final String directory;

  FilePackageCache(this.directory);
}
