// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:async';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import 'package_cache.dart';
import 'package_provider.dart';

/// A [PackageProvider] that downloads Dart packages from a pub host (pub.dev by
/// default, or a custom/private/mirror host) and resolves `package:` imports
/// from the extracted archives — honoring version constraints from a project
/// `pubspec`.
///
/// **Web-compatible.** It uses only web-safe libraries (`http` — which picks a
/// browser client on the web —, `archive` in-memory decoding, `pub_semver`,
/// `yaml`) and an in-memory [PackageCache] by default, so it runs both on the
/// VM and on the web. There is no `dart:io` dependency here.
///
/// ## CORS on the web
///
/// A browser cannot fetch `https://pub.dev` cross-origin (pub.dev doesn't send
/// permissive CORS headers, and archives are served from Google Cloud Storage).
/// For a web integration, either point [host] at a CORS-enabled mirror, provide
/// a proxying [client], or set [rewriteUrl] to route every request through a
/// CORS proxy — e.g.:
///
/// ```dart
/// PubDevProvider(
///   rewriteUrl: (u) => Uri.parse('https://my-cors-proxy/${u.toString()}'),
/// );
/// ```
///
/// Transitive version resolution is best-effort (highest version satisfying the
/// declared constraint), not a full dependency solver.
class PubDevProvider implements PackageProvider {
  /// The package host base URL (e.g. `https://pub.dev`).
  final String host;

  /// Cache for downloaded archives (in-memory by default; disk on the VM).
  final PackageCache cache;

  final http.Client _client;

  final bool _ownsClient;

  /// Optional hook to rewrite every outgoing request URL — e.g. to prepend a
  /// CORS proxy on the web.
  final Uri Function(Uri url)? rewriteUrl;

  /// Version constraints by package name (from [constraints] and/or a parsed
  /// [pubspecYaml]).
  final Map<String, VersionConstraint> _constraints;

  PubDevProvider({
    this.host = 'https://pub.dev',
    http.Client? client,
    PackageCache? cache,
    Map<String, VersionConstraint>? constraints,
    String? pubspecYaml,
    this.rewriteUrl,
  }) : cache = cache ?? MemoryPackageCache(),
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _constraints = {
         if (pubspecYaml != null) ..._parsePubspecConstraints(pubspecYaml),
         ...?constraints,
       };

  /// package name → extracted `lib/` files (`libPath` → source), memoized after
  /// the first resolve (`null` = tried and unavailable).
  final Map<String, Map<String, String>?> _libFiles = {};

  Uri _uri(String url) {
    var u = Uri.parse(url);
    return rewriteUrl != null ? rewriteUrl!(u) : u;
  }

  Future<Map<String, dynamic>?> _packageMeta(String pkg) async {
    try {
      var resp = await _client.get(_uri('$host/api/packages/$pkg'));
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// Highest published version of [pkg] satisfying the declared constraint (or
  /// the highest stable version when unconstrained), with its archive URL.
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
    var constraint = _constraints[pkg];

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

  Future<PackageArchive?> _fetchArchive(String pkg) async {
    var cached = await cache.get(pkg);
    if (cached != null) return cached;

    var selected = await _selectVersion(pkg);
    if (selected == null) return null;

    http.Response resp;
    try {
      resp = await _client.get(_uri(selected.archiveUrl));
    } catch (_) {
      return null;
    }
    if (resp.statusCode != 200) return null;

    var archive = PackageArchive(pkg, selected.version, resp.bodyBytes);
    await cache.put(archive);
    return archive;
  }

  /// Extracts the `lib/` files from a gzip-compressed tarball (in memory).
  static Map<String, String> _decodeLibFiles(List<int> bytes) {
    var tar = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
    var files = <String, String>{};
    for (var file in tar) {
      if (!file.isFile) continue;
      // Pub archives place package files at the root: `lib/...`, `pubspec.yaml`.
      var name = file.name;
      if (!name.startsWith('lib/')) continue;
      var libPath = name.substring('lib/'.length);
      files[libPath] = utf8.decode(
        file.content as List<int>,
        allowMalformed: true,
      );
    }
    return files;
  }

  Future<Map<String, String>?> _ensureLibFiles(String pkg) async {
    if (_libFiles.containsKey(pkg)) return _libFiles[pkg];
    var archive = await _fetchArchive(pkg);
    var files = archive == null ? null : _decodeLibFiles(archive.bytes);
    return _libFiles[pkg] = files;
  }

  @override
  Future<PackageSource?> resolvePackage(String pkg, String libPath) async {
    var files = await _ensureLibFiles(pkg);
    var src = files?[libPath];
    if (src == null) return null;
    return PackageSource('package:$pkg/$libPath', src);
  }

  @override
  Future<PackageSource?> resolvePackageUri(PackageUri uri) =>
      resolvePackage(uri.package, uri.libPath);

  @override
  Future<Set<String>> availablePackages() async => _constraints.keys.toSet();

  /// Closes the underlying HTTP client (only if this provider created it).
  void close() {
    if (_ownsClient) _client.close();
  }

  /// Reads `dependencies`/`dev_dependencies` version constraints from a
  /// `pubspec.yaml` string (web-safe YAML parsing).
  static Map<String, VersionConstraint> _parsePubspecConstraints(String yaml) {
    var result = <String, VersionConstraint>{};
    Object? doc;
    try {
      doc = loadYaml(yaml);
    } catch (_) {
      return result;
    }
    if (doc is! YamlMap) return result;

    for (var section in const ['dependencies', 'dev_dependencies']) {
      var deps = doc[section];
      if (deps is! YamlMap) continue;
      deps.forEach((k, v) {
        String? versionStr;
        if (v is String) {
          versionStr = v;
        } else if (v is YamlMap && v['version'] is String) {
          versionStr = v['version'] as String;
        }
        if (versionStr != null && versionStr.isNotEmpty) {
          try {
            result[k.toString()] = VersionConstraint.parse(versionStr);
          } catch (_) {}
        }
      });
    }
    return result;
  }
}
