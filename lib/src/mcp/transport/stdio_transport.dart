// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:async';
import 'dart:io';

import 'package:dart_mcp/stdio.dart';

import '../../repository/repo_config.dart';
import '../../repository/repository_adapter.dart';
import '../apollo_mcp_server.dart';
import '../mcp_config.dart';

/// Starts an [ApolloMcpServer] over stdio (the standard local MCP transport),
/// reading newline-delimited JSON-RPC from [input] and writing to [output]
/// (defaulting to this process's stdin/stdout).
///
/// Pass a [repository] (with an optional [repoConfig]) to additionally expose
/// the workspace/repository tools over this transport.
///
/// Returns the running server; await its `done` to know when the peer closes.
ApolloMcpServer serveStdio({
  McpLimits limits = const McpLimits(),
  bool nullSafetyChecks = false,
  Stream<List<int>>? input,
  StreamSink<List<int>>? output,
  RepositoryAdapter? repository,
  RepoConfig repoConfig = const RepoConfig(),
}) {
  final channel = stdioChannel(input: input ?? stdin, output: output ?? stdout);
  return ApolloMcpServer(
    channel,
    limits: limits,
    nullSafetyChecks: nullSafetyChecks,
    repository: repository,
    repoConfig: repoConfig,
  );
}
