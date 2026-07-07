// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

/// A tiny HTTP server that exposes a **local project** as an ApolloVM
/// repository, so a web IDE (or any [RemoteRepositoryAdapter] client) can list,
/// read, edit and version-control the files over `host:port`.
///
/// It serves the JSON contract of [RepositoryRpc] — one `POST /rpc` endpoint —
/// backed by a [LocalRepositoryAdapter] confined to the chosen workspace, and
/// adds permissive CORS so a browser app on another origin can reach it.
///
/// ## Run
///
/// ```
/// dart run tool/repository_server.dart                       # serves '.', read-only, 127.0.0.1:8090
/// dart run tool/repository_server.dart --workspace ../my_app --allow-write
/// dart run tool/repository_server.dart -w . --allow-write --allow-git-write -p 8090 -a 0.0.0.0
/// ```
///
/// The server is the real authority on permissions: `--allow-write` enables
/// `write`/`edit`/`mkdir`/`move`/`delete`, `--allow-git-write` enables
/// `add`/`commit`/`checkout`/`restore`. Without them the repository is
/// read-only regardless of what the client asks for.
///
/// ## Endpoints
///   * `GET  /`     → `{ok: true, result: <capabilities>}` (connection check)
///   * `POST /rpc`  → body `{op, ...args}` → the [RepositoryRpc] envelope
///   * `OPTIONS *`  → 204 (CORS preflight)
library;

import 'dart:convert';
import 'dart:io';

import 'package:apollovm/apollovm_repository_io.dart';
import 'package:args/args.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('port', abbr: 'p', defaultsTo: '8090', help: 'Listen port.')
    ..addOption(
      'address',
      abbr: 'a',
      defaultsTo: '127.0.0.1',
      help: 'Bind address.',
    )
    ..addOption(
      'workspace',
      abbr: 'w',
      defaultsTo: '.',
      help: 'Directory to serve as the repository root.',
    )
    ..addFlag(
      'allow-write',
      negatable: false,
      help: 'Permit mutating filesystem ops (write/edit/mkdir/move/delete).',
    )
    ..addFlag(
      'allow-git-write',
      negatable: false,
      help: 'Permit mutating git ops (add/commit/checkout/restore).',
    )
    ..addFlag(
      'require-line-match',
      negatable: false,
      help: 'Require every edit to pin its expected line via `atLine`.',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.');

  final ArgResults res;
  try {
    res = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln('\n${parser.usage}');
    exitCode = 64;
    return;
  }

  if (res['help'] as bool) {
    print('ApolloVM repository server\n');
    print('Usage: dart run tool/repository_server.dart [options]\n');
    print(parser.usage);
    return;
  }

  final port = int.tryParse(res['port'] as String) ?? 8090;
  final address = res['address'] as String;
  final workspace = res['workspace'] as String;

  final config = RepoConfig(
    allowWrite: res['allow-write'] as bool,
    allowGitMutation: res['allow-git-write'] as bool,
    requireLineMatch: res['require-line-match'] as bool,
  );

  final RepositoryRpc rpc;
  try {
    rpc = RepositoryRpc(
      RepositoryService(
        LocalRepositoryAdapter(workspace, config: config),
        config: config,
      ),
    );
  } on RepoException catch (e) {
    stderr.writeln('Cannot open workspace "$workspace": ${e.message}');
    exitCode = 66;
    return;
  }

  final caps = rpc.service.capabilities;
  final server = await HttpServer.bind(address, port);
  final base = 'http://$address:$port';

  stdout.writeln('ApolloVM repository server listening on $base');
  stdout.writeln('  workspace: ${Directory(workspace).absolute.path}');
  stdout.writeln(
    '  write: ${config.allowWrite ? 'on' : 'off'}   '
    'git: ${caps.supportsGit ? (config.allowGitMutation ? 'read+write' : 'read-only') : 'unavailable'}',
  );
  stdout.writeln('  POST $base/rpc   (GET $base/ for capabilities)');

  await for (final request in server) {
    _handle(request, rpc);
  }
}

Future<void> _handle(HttpRequest request, RepositoryRpc rpc) async {
  final response = request.response;

  // Permissive CORS on every response, including preflight.
  _setCors(request, response);

  try {
    if (request.method == 'OPTIONS') {
      response.statusCode = HttpStatus.noContent;
      return;
    }

    // Connection check: capabilities of the served repository.
    if (request.method == 'GET' && request.uri.path == '/') {
      _writeJson(response, {
        'ok': true,
        'result': rpc.service.capabilities.toJson(),
      });
      return;
    }

    if (request.method != 'POST' || request.uri.path != '/rpc') {
      response.statusCode = HttpStatus.notFound;
      _writeJson(response, _error('Not found. Use POST /rpc.'));
      return;
    }

    final raw = await utf8.decoder.bind(request).join();
    Object? decoded;
    try {
      decoded = raw.isEmpty ? const <String, Object?>{} : jsonDecode(raw);
    } catch (e) {
      response.statusCode = HttpStatus.badRequest;
      _writeJson(response, _error('Invalid JSON body: $e'));
      return;
    }
    if (decoded is! Map) {
      response.statusCode = HttpStatus.badRequest;
      _writeJson(response, _error('Request body must be a JSON object.'));
      return;
    }

    final result = await rpc.handle(decoded.cast<String, Object?>());
    _writeJson(response, result);
  } catch (e) {
    // Should not happen (RepositoryRpc never throws), but never leave the
    // socket hanging.
    response.statusCode = HttpStatus.internalServerError;
    _writeJson(response, _error('$e'));
  } finally {
    await response.close();
  }
}

/// Applies permissive CORS to [response].
///
/// Rather than answering with `*`, it *reflects* the request's `Origin` and its
/// `Access-Control-Request-Headers`. Reflection is the most compatible form: the
/// `*` wildcard is ignored for credentialed requests and is rejected by some
/// browsers for `Access-Control-Allow-Headers`, so echoing the exact values a
/// browser asked for avoids those preflight failures. `Vary: Origin` keeps the
/// per-origin response cacheable, and `Max-Age` lets the browser skip repeat
/// preflights.
void _setCors(HttpRequest request, HttpResponse response) {
  final origin = request.headers.value('origin');
  final requestedHeaders = request.headers.value(
    'access-control-request-headers',
  );
  response.headers
    ..set('Access-Control-Allow-Origin', origin ?? '*')
    ..set('Vary', 'Origin')
    ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
    ..set(
      'Access-Control-Allow-Headers',
      (requestedHeaders != null && requestedHeaders.isNotEmpty)
          ? requestedHeaders
          : 'Content-Type',
    )
    ..set('Access-Control-Max-Age', '86400');
}

void _writeJson(HttpResponse response, Map<String, Object?> body) {
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(body));
}

Map<String, Object?> _error(String message) => <String, Object?>{
  'ok': false,
  'error': {'type': 'RepoException', 'message': message},
};
