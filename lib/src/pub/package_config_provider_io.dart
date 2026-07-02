// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package_provider.dart';

/// A [PackageProvider] that resolves `package:` imports from a project's
/// `.dart_tool/package_config.json` — the file `dart pub get` generates from
/// the project `pubspec` (populating the local pub cache from pub.dev). This is
/// the default, dependency-free importer with exact pub semantics.
///
/// Uses `dart:io`, so it is NOT part of the web-safe core (see
/// `lib/apollovm_pub.dart`).
class PackageConfigProvider implements PackageProvider {
  /// The project directory whose `.dart_tool/package_config.json` is used.
  final String projectDir;

  /// If `true`, run `dart pub get` when the package config is missing.
  final bool runPubGetIfMissing;

  PackageConfigProvider({String? projectDir, this.runPubGetIfMissing = false})
    : projectDir = projectDir ?? Directory.current.path;

  String get _configPath =>
      p.join(projectDir, '.dart_tool', 'package_config.json');

  /// package name → the package's importable `lib/` root (absolute path).
  Map<String, String>? _libRoots;

  Map<String, String> _loadLibRoots() {
    var cached = _libRoots;
    if (cached != null) return cached;

    var file = File(_configPath);
    if (!file.existsSync() && runPubGetIfMissing) {
      _pubGet();
    }
    if (!file.existsSync()) {
      return _libRoots = <String, String>{};
    }

    var json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    var packages = (json['packages'] as List?) ?? const [];

    var roots = <String, String>{};
    for (var entry in packages.cast<Map<String, dynamic>>()) {
      var name = entry['name'] as String?;
      var rootUri = entry['rootUri'] as String?;
      var packageUri = (entry['packageUri'] as String?) ?? 'lib/';
      if (name == null || rootUri == null) continue;

      // rootUri is relative to the `.dart_tool/` dir, or an absolute file: URI.
      var rootPath = _resolveRootUri(rootUri);
      roots[name] = p.normalize(p.join(rootPath, packageUri));
    }

    return _libRoots = roots;
  }

  String _resolveRootUri(String rootUri) {
    if (rootUri.startsWith('file:')) {
      return p.fromUri(Uri.parse(rootUri));
    }
    // Relative to the `.dart_tool/` directory that holds package_config.json.
    var dartToolDir = p.join(projectDir, '.dart_tool');
    return p.normalize(p.join(dartToolDir, p.fromUri(Uri.parse(rootUri))));
  }

  void _pubGet() {
    try {
      Process.runSync('dart', ['pub', 'get'], workingDirectory: projectDir);
    } catch (_) {
      // Best-effort; resolution simply fails if the config stays missing.
    }
  }

  @override
  PackageSource? resolvePackage(String pkg, String libPath) {
    var libRoot = _loadLibRoots()[pkg];
    if (libRoot == null) return null;

    var file = File(p.join(libRoot, libPath));
    if (!file.existsSync()) return null;

    return PackageSource('package:$pkg/$libPath', file.readAsStringSync());
  }

  @override
  PackageSource? resolvePackageUri(PackageUri uri) =>
      resolvePackage(uri.package, uri.libPath);

  @override
  Set<String> availablePackages() => _loadLibRoots().keys.toSet();
}
