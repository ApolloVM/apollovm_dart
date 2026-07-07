// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

/// ApolloVM repository features — read, search, navigate, edit and
/// version-control a codebase through a pluggable [RepositoryAdapter].
///
/// This is a **standalone** feature, independent of MCP: a web IDE, a desktop
/// editor, an agent or a test can use [RepositoryService] (a typed façade) and
/// the adapters directly. The MCP `apollovm.fs.*`/`search.*`/`code.*`/`git.*`
/// tools are just a thin JSON layer over this same surface.
///
/// This library is **web-safe** (no `dart:io`): pair it with the in-memory
/// adapter in the browser, or import `package:apollovm/apollovm_repository_io.dart`
/// on the VM for the on-disk [LocalRepositoryAdapter].
///
/// ```dart
/// import 'package:apollovm/apollovm_repository.dart';
///
/// final repo = RepositoryService(
///   InMemoryRepositoryAdapter({'lib/main.dart': source}),
/// );
/// final outline = await repo.outline('lib/main.dart'); // language-aware
/// await repo.close();
/// ```
library;

export 'src/repository/in_memory_repository_adapter.dart';
export 'src/repository/permission_guard.dart';
export 'src/repository/repo_config.dart';
export 'src/repository/repository_adapter.dart';
export 'src/repository/repository_service.dart';
