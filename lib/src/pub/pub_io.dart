// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

/// IO-only members of the optional Dart package importer (VM/desktop).
///
/// Exposes the filesystem-based [PackageConfigProvider] and the disk-backed
/// [FilePackageCache]. Selected via conditional import from
/// `lib/apollovm_pub.dart` when `dart.library.io` is available; web builds get
/// `pub_stub.dart` instead. (The `PubDevProvider` itself is web-safe and is
/// exported unconditionally.)
library;

export 'file_package_cache_io.dart';
export 'package_config_provider_io.dart';
