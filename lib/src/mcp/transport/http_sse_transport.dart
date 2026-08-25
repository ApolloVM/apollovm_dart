// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:stream_channel/stream_channel.dart';

import '../../repository/repo_config.dart';
import '../../repository/repository_adapter.dart';
import '../apollo_mcp_server.dart';
import '../mcp_config.dart';

/// A single client session: the SSE response used to push server→client
/// messages, and the incoming controller fed by the client's POSTs.
class _Session {
  final HttpResponse sseResponse;
  final StreamController<String> incoming;
  final StreamController<String> outgoing;
  final ApolloMcpServer server;

  _Session(this.sseResponse, this.incoming, this.outgoing, this.server);

  Future<void> close() async {
    await server.shutdown();
    await incoming.close();
    await outgoing.close();
  }
}

/// An MCP transport that exposes [ApolloMcpServer] over HTTP using the
/// Server-Sent Events (SSE) transport:
///
/// - `GET /sse` opens an SSE stream. The first event (`event: endpoint`) tells
///   the client which URL to POST messages to (`/message?sessionId=...`).
///   Server→client JSON-RPC messages are streamed as `event: message` frames.
/// - `POST /message?sessionId=...` delivers one client→server JSON-RPC message;
///   the server replies over the session's SSE stream. Returns `202 Accepted`.
///
/// SECURITY: binds to `127.0.0.1` by default. Exposing this on a public
/// interface grants unauthenticated code execution — front it with auth/TLS
/// and an explicit `host` only in a trusted environment.
class HttpSseTransport {
  final McpLimits limits;

  /// Server-wide default for the tools' `nullSafety` argument.
  final bool nullSafetyChecks;

  /// Optional workspace/repository backend shared by all sessions (exposes the
  /// `apollovm.fs.*`/`search.*`/`code.*`/`git.*` tools when set).
  final RepositoryAdapter? repository;
  final RepoConfig repoConfig;

  final Map<String, _Session> _sessions = {};
  HttpServer? _server;
  int _sessionCounter = 0;

  HttpSseTransport({
    this.limits = const McpLimits(),
    this.nullSafetyChecks = false,
    this.repository,
    this.repoConfig = const RepoConfig(),
  });

  /// The bound address, available after [start].
  InternetAddress? get address => _server?.address;

  /// The bound port, available after [start].
  int? get port => _server?.port;

  /// Binds an [HttpServer] on [host]:[port] and starts serving.
  Future<void> start({int port = 8080, String host = '127.0.0.1'}) async {
    final server = await HttpServer.bind(host, port);
    _server = server;
    server.listen(_handleRequest);
  }

  /// Stops the server and closes all active sessions.
  Future<void> stop() async {
    for (final session in _sessions.values.toList()) {
      await session.close();
    }
    _sessions.clear();
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;
    if (request.method == 'OPTIONS') {
      // CORS preflight: browsers send this before a cross-origin POST. Answer it
      // with the allowed methods/headers instead of a 404, which would block the
      // subsequent request.
      await _handlePreflight(request);
    } else if (request.method == 'GET' && (path == '/sse' || path == '/')) {
      _openSseSession(request);
    } else if (request.method == 'POST' &&
        (path == '/message' || path == '/sse' || path == '/')) {
      await _handlePost(request);
    } else {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }
  }

  Future<void> _handlePreflight(HttpRequest request) async {
    final response = request.response;
    response.statusCode = HttpStatus.noContent;
    response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
      ..set('Access-Control-Allow-Headers', 'Content-Type')
      ..set('Access-Control-Max-Age', '86400');
    await response.close();
  }

  void _openSseSession(HttpRequest request) {
    final response = request.response;
    response.statusCode = HttpStatus.ok;
    // Stream each SSE frame to the socket immediately (no output buffering).
    response.bufferOutput = false;
    response.headers
      ..set(HttpHeaders.contentTypeHeader, 'text/event-stream')
      ..set(HttpHeaders.cacheControlHeader, 'no-cache')
      ..set('Connection', 'keep-alive')
      ..set('Access-Control-Allow-Origin', '*');

    final sessionId = '${++_sessionCounter}';
    final incoming = StreamController<String>();
    final outgoing = StreamController<String>();

    void writeFrame(String event, String data) {
      response.add(utf8.encode('event: $event\ndata: $data\n\n'));
      response.flush();
    }

    // Each server→client JSON-RPC message becomes one SSE `message` frame.
    outgoing.stream.listen((message) => writeFrame('message', message));

    final channel = StreamChannel<String>(incoming.stream, outgoing.sink);
    final server = ApolloMcpServer(
      channel,
      limits: limits,
      nullSafetyChecks: nullSafetyChecks,
      repository: repository,
      repoConfig: repoConfig,
    );
    _sessions[sessionId] = _Session(response, incoming, outgoing, server);

    // Tell the client where to POST its messages.
    writeFrame('endpoint', '/message?sessionId=$sessionId');

    // Clean up when the client disconnects.
    response.done.whenComplete(() => _closeSession(sessionId));
  }

  Future<void> _handlePost(HttpRequest request) async {
    final sessionId = request.uri.queryParameters['sessionId'];
    final session = sessionId == null ? null : _sessions[sessionId];
    if (session == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final body = await utf8.decodeStream(request);
    if (body.trim().isNotEmpty) {
      session.incoming.add(body);
    }

    request.response.statusCode = HttpStatus.accepted;
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    await request.response.close();
  }

  Future<void> _closeSession(String sessionId) async {
    final session = _sessions.remove(sessionId);
    if (session != null) {
      await session.incoming.close();
      await session.outgoing.close();
      await session.server.shutdown();
    }
  }
}
