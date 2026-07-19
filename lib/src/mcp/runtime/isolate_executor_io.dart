// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

// The native tool executor. Selected by `isolate_executor.dart` when
// `dart:isolate` is available; runs each tool in a spawned isolate so a hard
// timeout can kill runaway code. See `isolate_executor_generic.dart` for the
// in-process web variant.
import 'dart:async';
import 'dart:isolate';

import '../mcp_config.dart';
import '../tools/apollo_tools.dart';

/// A sendable description of a tool computation to run inside an isolate.
class _IsolateJob {
  final String toolName;
  final Map<String, Object?> args;
  final McpLimits limits;
  final SendPort replyPort;

  _IsolateJob(this.toolName, this.args, this.limits, this.replyPort);
}

/// Runs the tool named [toolName] inside an isolate, using
/// [McpLimits.timeoutMs] (or an override in `args['timeoutMs']`) as the hard
/// timeout. Convenience wrapper over [runToolInIsolate].
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

/// Runs [computeTool] for [toolName] inside a spawned [Isolate], enforcing a
/// hard [timeout] via `Timer` + `Isolate.kill`.
///
/// This is the only reliable way to bound CPU/wall-clock in Dart: a runaway
/// loop that ignores the event loop cannot be stopped in-process, but the
/// isolate running it can be killed. On timeout (or isolate error/premature
/// exit) an error result map is returned; captured output produced before the
/// kill is not recovered.
Future<Map<String, Object?>> runToolInIsolate(
  String toolName,
  Map<String, Object?> args,
  McpLimits limits,
  Duration timeout,
) async {
  final replyPort = ReceivePort();
  final errorPort = ReceivePort();
  final exitPort = ReceivePort();
  final completer = Completer<Map<String, Object?>>();

  Isolate? isolate;
  Timer? timer;

  void complete(Map<String, Object?> result) {
    if (!completer.isCompleted) completer.complete(result);
  }

  try {
    isolate = await Isolate.spawn(
      _isolateEntry,
      _IsolateJob(toolName, args, limits, replyPort.sendPort),
      onError: errorPort.sendPort,
      onExit: exitPort.sendPort,
      errorsAreFatal: true,
    );

    timer = Timer(timeout, () {
      isolate?.kill(priority: Isolate.immediate);
      complete(
        _errorResult('Execution timed out after ${timeout.inMilliseconds}ms'),
      );
    });

    replyPort.listen((message) {
      complete((message as Map).cast<String, Object?>());
    });

    errorPort.listen((message) {
      // message is [errorString, stackTraceString].
      final error = (message is List && message.isNotEmpty)
          ? '${message.first}'
          : '$message';
      complete(_errorResult('Isolate error: $error'));
    });

    exitPort.listen((_) {
      complete(_errorResult('Isolate exited before returning a result'));
    });

    return await completer.future;
  } finally {
    timer?.cancel();
    replyPort.close();
    errorPort.close();
    exitPort.close();
    isolate?.kill(priority: Isolate.immediate);
  }
}

Future<void> _isolateEntry(_IsolateJob job) async {
  try {
    final result = await computeTool(job.toolName, job.args, job.limits);
    job.replyPort.send(result);
  } catch (e) {
    job.replyPort.send(_errorResult('$e'));
  }
}

Map<String, Object?> _errorResult(String message) => <String, Object?>{
  'diagnostics': [
    <String, Object?>{'severity': 'error', 'message': message},
  ],
  'isError': true,
};
