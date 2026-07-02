// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:pubspec/pubspec.dart';

import 'package_provider.dart';

/// A [PackageProvider] that downloads Dart packages from a pub host (pub.dev by
/// default, or a custom/private host) and resolves `package:` imports from the
/// extracted archives, honoring version constraints declared in a project
/// `pubspec`.
///
/// Opt-in and network-based; uses `dart:io` + `http` + `archive`, so it is NOT
/// part of the web-safe core (see `lib/apollovm_pub.dart`). Transitive version
/// resolution is best-effort (highest version satisfying each declared
/// constraint), not a full dependency solver.
class PubDevProvider implements PackageProvider {
  /// The package host base URL (e.g. `https://pub.dev`).
  final String host;

  /// Directory where downloaded archives are extracted/cached.
  final String cacheDir;

  /// Optional project `pubspec.yaml` path used to read version constraints.
  final String? pubspecPath;

  final http.Client _client;

  PubDevProvider({
    this.host = 'https://pub.dev',
    String? cacheDir,
    this.pubspecPath,
    http.Client? client,
  }) : cacheDir =
           cacheDir ?? p.join(Directory.systemTemp.path, 'apollovm_pub_cache'),
       _client = client ?? http.Client();

  Map<String, VersionConstraint>? _constraints;

  /// package name → extracted `lib/` root (absolute path), once fetched.
  final Map<String, String> _libRoots = <String, String>{};

  /// package name → decoded pub-host metadata JSON.
  final Map<String, Map<String, dynamic>?> _metaCache = {};

  Future<Map<String, VersionConstraint>> _loadConstraints() async {
    var cached = _constraints;
    if (cached != null) return cached;

    var constraints = <String, VersionConstraint>{};
    var path = pubspecPath;
    if (path != null && File(path).existsSync()) {
      try {
        var pubSpec = await PubSpec.loadFile(path);
        for (var entry in pubSpec.allDependencies.entries) {
          var ref = entry.value;
          if (ref is HostedReference) {
            constraints[entry.key] = ref.versionConstraint;
          } else if (ref is ExternalHostedReference) {
            constraints[entry.key] = ref.versionConstraint;
          }
        }
      } catch (_) {
        // Missing/unreadable pubspec → resolve latest versions.
      }
    }

    return _constraints = constraints;
  }

  Future<Map<String, dynamic>?> _packageMeta(String pkg) async {
    if (_metaCache.containsKey(pkg)) return _metaCache[pkg];
    Map<String, dynamic>? meta;
    try {
      var resp = await _client.get(Uri.parse('$host/api/packages/$pkg'));
      if (resp.statusCode == 200) {
        meta = jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (_) {
      meta = null;
    }
    return _metaCache[pkg] = meta;
  }

  /// Picks the highest published version of [pkg] satisfying the declared
  /// constraint (or the highest stable version when unconstrained).
  Future<({String version, String archiveUrl})?> _selectVersion(
    String pkg,
  ) async {
    var meta = await _packageMeta(pkg);
    var versionsJson = (meta?['versions'] as List?)
        ?.cast<Map<String, dynamic>>();
    if (versionsJson == null || versionsJson.isEmpty) return null;

    var byVersion = <Version, String>{};
    for (var v in versionsJson) {
      var vs = v['version'] as String?;
      var url = v['archive_url'] as String?;
      if (vs == null || url == null) continue;
      try {
        byVersion[Version.parse(vs)] = url;
      } catch (_) {}
    }
    if (byVersion.isEmpty) return null;

    var all = byVersion.keys.toList()..sort();
    var constraint = (await _loadConstraints())[pkg];

    Version? pick;
    if (constraint != null) {
      var matching = all.where(constraint.allows).toList();
      if (matching.isNotEmpty) pick = matching.last;
    }
    pick ??= () {
      var stable = all.where((v) => !v.isPreRelease).toList();
      return stable.isNotEmpty ? stable.last : all.last;
    }();

    return (version: pick.toString(), archiveUrl: byVersion[pick]!);
  }

  Future<String?> _ensurePackage(String pkg) async {
    var existing = _libRoots[pkg];
    if (existing != null) return existing;

    var selected = await _selectVersion(pkg);
    if (selected == null) return null;

    var dir = p.join(cacheDir, '$pkg-${selected.version}');
    var libDir = p.join(dir, 'lib');

    if (!Directory(libDir).existsSync()) {
      try {
        await _downloadAndExtract(selected.archiveUrl, dir);
      } catch (_) {
        return null;
      }
    }

    if (!Directory(libDir).existsSync()) return null;
    return _libRoots[pkg] = libDir;
  }

  Future<void> _downloadAndExtract(String url, String destDir) async {
    var resp = await _client.get(Uri.parse(url));
    if (resp.statusCode != 200) {
      throw HttpException('Download failed ($url): ${resp.statusCode}');
    }

    // Pub archives are gzip-compressed tarballs with files at the root.
    var tar = TarDecoder().decodeBytes(
      GZipDecoder().decodeBytes(resp.bodyBytes),
    );
    for (var file in tar) {
      if (!file.isFile) continue;
      var out = File(p.join(destDir, file.name));
      out.parent.createSync(recursive: true);
      out.writeAsBytesSync(file.content as List<int>);
    }
  }

  @override
  Future<PackageSource?> resolvePackage(String pkg, String libPath) async {
    var libDir = await _ensurePackage(pkg);
    if (libDir == null) return null;

    var file = File(p.join(libDir, libPath));
    if (!file.existsSync()) return null;

    return PackageSource('package:$pkg/$libPath', file.readAsStringSync());
  }

  @override
  Future<PackageSource?> resolvePackageUri(PackageUri uri) =>
      resolvePackage(uri.package, uri.libPath);

  @override
  Future<Set<String>> availablePackages() async =>
      (await _loadConstraints()).keys.toSet();

  /// Closes the underlying HTTP client.
  void close() => _client.close();
}
