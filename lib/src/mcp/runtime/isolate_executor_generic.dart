// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

// The platform-generic (web/JS) tool executor. Selected by
// `isolate_executor.dart` when `dart:isolate` is unavailable (e.g. dart2js /
// DDC), where it is the only option.
import 'dart:async';

import '../mcp_config.dart';
import '../tools/apollo_tools.dart';

/// Runs the tool named [toolName] with the configured timeout. Convenience
/// wrapper over [runToolInIsolate], mirroring the native executor's API.
Future<Map<String, Object?>> computeToolIsolated(
  String toolName,
  Map<String, Object?> args,
  McpLimits limits,
) {
  final timeoutMs = mcpCoerceInt(args['timeoutMs']) ?? limits.timeoutMs;
  return runToolInIsolate(
    toolName,
    args,
    limits,
    Duration(milliseconds: timeoutMs),
  );
}

/// Runs [computeTool] for [toolName] **in-process**, bounding it with a
/// cooperative [timeout] (`Future.timeout`).
///
/// This platform has no `dart:isolate`, so — unlike the native executor — the
/// timeout cannot forcibly kill CPU-bound code that never yields to the event
/// loop; it only stops awaiting the result. Same signature and error-result
/// shape as the native `runToolInIsolate` so callers are platform-agnostic.
Future<Map<String, Object?>> runToolInIsolate(
  String toolName,
  Map<String, Object?> args,
  McpLimits limits,
  Duration timeout,
) async {
  try {
    return await computeTool(toolName, args, limits).timeout(
      timeout,
      onTimeout: () =>
          _errorResult('Execution timed out after ${timeout.inMilliseconds}ms'),
    );
  } catch (e) {
    return _errorResult('$e');
  }
}

Map<String, Object?> _errorResult(String message) => <String, Object?>{
  'diagnostics': [
    <String, Object?>{'severity': 'error', 'message': message},
  ],
  'isError': true,
};
