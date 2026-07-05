// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

// Platform-selected tool executor for `computeToolIsolated` /
// `runToolInIsolate`.
//
// On native (`dart:isolate` present) each tool runs in a spawned isolate that a
// hard timeout can kill; on the web it runs in-process with a cooperative
// timeout. Both variants expose the same API, so callers (the MCP server) are
// platform-agnostic. Mirrors the `wasm_runtime.dart` conditional-import idiom.
export 'isolate_executor_generic.dart'
    if (dart.library.io) 'isolate_executor_io.dart';
