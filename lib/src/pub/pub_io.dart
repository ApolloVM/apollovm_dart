// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

/// IO barrel for the optional Dart package importer (VM/desktop only).
///
/// Exposes the filesystem-based [PackageConfigProvider] and the network-based
/// [PubDevProvider]. Selected via conditional import from `lib/apollovm_pub.dart`
/// when `dart.library.io` is available; web builds get `pub_stub.dart` instead.
library;

export 'package_config_provider_io.dart';
export 'pubdev_provider_io.dart';
