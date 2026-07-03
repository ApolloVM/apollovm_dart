// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

/// A small CORS proxy for using ApolloVM's `PubDevProvider` from a **web**
/// integration.
///
/// Browsers can't fetch `https://pub.dev` (or the Google-Cloud-hosted package
/// archives) cross-origin — pub.dev doesn't send permissive CORS headers. Run
/// this proxy next to your web app and point `PubDevProvider.rewriteUrl` at it;
/// the proxy forwards each request and adds `Access-Control-Allow-Origin: *`.
///
/// ## Run
///
/// ```
/// dart run tool/pub_cors_proxy.dart            # http://127.0.0.1:8080
/// dart run tool/pub_cors_proxy.dart -p 9000 -a 0.0.0.0
/// ```
///
/// ## Use from the web (Dart)
///
/// ```dart
/// import 'package:apollovm/apollovm.dart';
/// import 'package:apollovm/apollovm_pub.dart';
///
/// final proxy = 'http://127.0.0.1:8080';
/// final provider = PubDevProvider(
///   rewriteUrl: (u) =>
///       Uri.parse('$proxy/proxy?url=${Uri.encodeComponent(u.toString())}'),
/// );
/// final loader = DartPackageLoader(vm, provider);
/// vm.moduleLoader = loader;
/// await loader.provision();
/// ```
///
/// By default only pub hosts are proxied (`pub.dev`, `pub.dartlang.org`,
/// `storage.googleapis.com`); use `--allow-host` to add more, or
/// `--allow-any-host` to disable the allow-list (an open proxy — use with care).
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;

const _defaultAllowedHosts = <String>{
  'pub.dev',
  'pub.dartlang.org',
  'storage.googleapis.com',
};

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('port', abbr: 'p', defaultsTo: '8080', help: 'Listen port.')
    ..addOption(
      'address',
      abbr: 'a',
      defaultsTo: '127.0.0.1',
      help: 'Bind address.',
    )
    ..addMultiOption(
      'allow-host',
      help: 'Additional upstream host allowed to be proxied.',
    )
    ..addFlag(
      'allow-any-host',
      negatable: false,
      help: 'Allow proxying ANY host (disables the allow-list).',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.');

  final res = parser.parse(args);
  if (res['help'] as bool) {
    print('ApolloVM pub CORS proxy\n');
    print('Usage: dart run tool/pub_cors_proxy.dart [options]\n');
    print(parser.usage);
    return;
  }

  final port = int.tryParse(res['port'] as String) ?? 8080;
  final address = res['address'] as String;
  final allowAnyHost = res['allow-any-host'] as bool;
  final allowedHosts = <String>{
    ..._defaultAllowedHosts,
    ...res['allow-host'] as List<String>,
  };

  final client = http.Client();
  final server = await HttpServer.bind(address, port);

  final base = 'http://$address:$port';
  stdout.writeln('ApolloVM pub CORS proxy listening on $base');
  stdout.writeln(
    allowAnyHost
        ? '  proxying ANY host (open proxy)'
        : '  allowed hosts: ${allowedHosts.join(', ')}',
  );
  stdout.writeln('  PubDevProvider(rewriteUrl: (u) => Uri.parse(');
  stdout.writeln(
    "    '$base/proxy?url=' + Uri.encodeComponent(u.toString())));",
  );

  await for (final request in server) {
    _handle(request, client, allowedHosts, allowAnyHost);
  }
}

Future<void> _handle(
  HttpRequest request,
  http.Client client,
  Set<String> allowedHosts,
  bool allowAnyHost,
) async {
  final response = request.response;

  // Permissive CORS on every response, including preflight.
  response.headers
    ..set('Access-Control-Allow-Origin', '*')
    ..set('Access-Control-Allow-Methods', 'GET, OPTIONS')
    ..set('Access-Control-Allow-Headers', '*');

  if (request.method == 'OPTIONS') {
    response.statusCode = HttpStatus.noContent;
    await response.close();
    return;
  }

  if (request.method != 'GET') {
    response.statusCode = HttpStatus.methodNotAllowed;
    await response.close();
    return;
  }

  final target = _targetUrl(request.uri);
  if (target == null) {
    response
      ..statusCode = HttpStatus.badRequest
      ..write('Missing target url. Use /proxy?url=<encoded-url>.');
    await response.close();
    return;
  }

  Uri uri;
  try {
    uri = Uri.parse(target);
  } catch (_) {
    response
      ..statusCode = HttpStatus.badRequest
      ..write('Invalid target url: $target');
    await response.close();
    return;
  }

  if (!allowAnyHost && !allowedHosts.contains(uri.host)) {
    response
      ..statusCode = HttpStatus.forbidden
      ..write('Host not allowed: ${uri.host}');
    await response.close();
    return;
  }

  try {
    final upstream = await client.get(uri);
    response.statusCode = upstream.statusCode;
    final contentType = upstream.headers['content-type'];
    if (contentType != null) {
      try {
        response.headers.contentType = ContentType.parse(contentType);
      } catch (_) {}
    }
    response.add(upstream.bodyBytes);
  } catch (e) {
    response
      ..statusCode = HttpStatus.badGateway
      ..write('Proxy error: $e');
  }
  await response.close();
}

/// Extracts the upstream URL from `?url=<encoded>` (preferred) or a
/// `/<scheme>://…` path prefix.
String? _targetUrl(Uri requestUri) {
  final q = requestUri.queryParameters['url'];
  if (q != null && q.isNotEmpty) return q;

  var path = requestUri.path;
  if (path.startsWith('/')) path = path.substring(1);
  if (path.startsWith('http://') || path.startsWith('https://')) {
    final query = requestUri.query;
    return query.isEmpty ? path : '$path?$query';
  }
  return null;
}
