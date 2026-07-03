// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:io';

import 'package:path/path.dart' as p;

import 'package_cache.dart';

/// A disk-backed [PackageCache] for the VM: persists downloaded archives under
/// [directory] so packages survive across runs. Not available on the web (uses
/// `dart:io`); web builds fall back to [MemoryPackageCache].
class FilePackageCache implements PackageCache {
  final String directory;

  FilePackageCache(this.directory);

  File _archiveFile(String name) => File(p.join(directory, '$name.tar.gz'));

  File _versionFile(String name) => File(p.join(directory, '$name.version'));

  @override
  PackageArchive? get(String name) {
    var archiveFile = _archiveFile(name);
    var versionFile = _versionFile(name);
    if (!archiveFile.existsSync() || !versionFile.existsSync()) return null;
    return PackageArchive(
      name,
      versionFile.readAsStringSync().trim(),
      archiveFile.readAsBytesSync(),
    );
  }

  @override
  void put(PackageArchive archive) {
    Directory(directory).createSync(recursive: true);
    _archiveFile(archive.name).writeAsBytesSync(archive.bytes);
    _versionFile(archive.name).writeAsStringSync(archive.version);
  }
}
