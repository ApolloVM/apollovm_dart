// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:async';
import 'dart:typed_data';

/// A downloaded package archive (the raw `.tar.gz` bytes) plus its resolved
/// version. Cached so a package is fetched from the host only once.
class PackageArchive {
  final String name;

  final String version;

  final Uint8List bytes;

  PackageArchive(this.name, this.version, this.bytes);

  @override
  String toString() => 'PackageArchive{$name-$version, ${bytes.length} bytes}';
}

/// Caches downloaded [PackageArchive]s by package name. Web-safe by contract:
/// the default [MemoryPackageCache] holds bytes in memory; a disk-backed
/// implementation is provided for the VM (see `FilePackageCache`).
abstract class PackageCache {
  FutureOr<PackageArchive?> get(String name);

  FutureOr<void> put(PackageArchive archive);
}

/// An in-memory [PackageCache] — the default, and the only one usable on the
/// web (no filesystem).
class MemoryPackageCache implements PackageCache {
  final Map<String, PackageArchive> _archives = <String, PackageArchive>{};

  @override
  PackageArchive? get(String name) => _archives[name];

  @override
  void put(PackageArchive archive) => _archives[archive.name] = archive;

  void clear() => _archives.clear();
}
