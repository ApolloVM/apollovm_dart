// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

/// Native (`dart:io`) repository extras for ApolloVM.
///
/// Re-exports the web-safe [`apollovm_repository`](apollovm_repository.dart)
/// surface and adds [LocalRepositoryAdapter] — a [RepositoryAdapter] backed by a
/// checkout on disk (filesystem via `dart:io`, git via the `git` binary).
///
/// Import this on the Dart VM / native. For the web, import
/// `package:apollovm/apollovm_repository.dart` and use an
/// `InMemoryRepositoryAdapter` (or a remote adapter) instead.
///
/// ```dart
/// import 'package:apollovm/apollovm_repository_io.dart';
///
/// final repo = RepositoryService(
///   LocalRepositoryAdapter('.'),
///   config: const RepoConfig(allowWrite: true),
/// );
/// print(await repo.gitStatus());
/// ```
library;

export 'apollovm_repository.dart';
export 'src/repository/local_repository_adapter.dart';
