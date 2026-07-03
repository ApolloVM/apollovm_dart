// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:async';

/// A parsed `package:` import URI: `package:<package>/<libPath>`.
///
/// Example: `package:foo/src/bar.dart` → `package` = `foo`,
/// `libPath` = `src/bar.dart` (relative to the package's `lib/` directory).
class PackageUri {
  final String package;

  final String libPath;

  const PackageUri(this.package, this.libPath);

  /// The canonical module id used when the resolved source is loaded into the
  /// VM (kept identical to the original `package:` import so the resolver
  /// matches it).
  String get moduleId => 'package:$package/$libPath';

  /// Parses a `package:foo/bar.dart` [importPath] (quotes tolerated), or `null`
  /// if it is not a `package:` URI.
  static PackageUri? tryParse(String importPath) {
    var p = importPath.trim();
    if (p.length >= 2) {
      var a = p[0], b = p[p.length - 1];
      if ((a == '"' && b == '"') || (a == "'" && b == "'")) {
        p = p.substring(1, p.length - 1);
      }
    }

    if (!p.startsWith('package:')) return null;

    var rest = p.substring('package:'.length);
    var slash = rest.indexOf('/');
    if (slash <= 0) return null;

    var package = rest.substring(0, slash);
    var libPath = rest.substring(slash + 1);
    if (package.isEmpty || libPath.isEmpty) return null;

    return PackageUri(package, libPath);
  }

  @override
  String toString() => moduleId;
}

/// A resolved package source: the [source] code and the [moduleId] it should be
/// loaded under.
class PackageSource {
  /// The canonical module id (e.g. `package:foo/bar.dart`).
  final String moduleId;

  /// The Dart source code of the resolved library file.
  final String source;

  const PackageSource(this.moduleId, this.source);

  @override
  String toString() => 'PackageSource{$moduleId, ${source.length} chars}';
}

/// Resolves a Dart `package:` import to its library source, from a package host
/// (pub.dev or another) compatible with `pubspec` dependency declarations.
///
/// Implementations that touch the filesystem or network are kept out of the
/// web-safe core (see `lib/apollovm_pub.dart`); this interface itself is pure.
abstract class PackageProvider {
  /// Resolves the source for `package:[pkg]/[libPath]`, or `null` if this
  /// provider can't serve it.
  FutureOr<PackageSource?> resolvePackage(String pkg, String libPath);

  /// Resolves a full `package:` import [uri], or `null`.
  FutureOr<PackageSource?> resolvePackageUri(PackageUri uri) =>
      resolvePackage(uri.package, uri.libPath);

  /// The set of package names this provider can serve (e.g. from a project's
  /// `pubspec`/package-config), used to pre-provision imports. May be empty if
  /// the provider resolves lazily.
  FutureOr<Set<String>> availablePackages() => const <String>{};
}

/// A [PackageProvider] that resolves nothing — the web-safe default so code
/// depending on the provider API compiles for web without pulling in `dart:io`.
class NoopPackageProvider implements PackageProvider {
  const NoopPackageProvider();

  @override
  FutureOr<PackageSource?> resolvePackage(String pkg, String libPath) => null;

  @override
  FutureOr<PackageSource?> resolvePackageUri(PackageUri uri) => null;

  @override
  FutureOr<Set<String>> availablePackages() => const <String>{};
}
