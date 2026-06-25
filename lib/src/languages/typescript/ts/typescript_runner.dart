// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import '../../../apollovm_runner.dart';

/// TypeScript implementation of an [ApolloRunner].
class ApolloRunnerTypeScript extends ApolloRunner {
  ApolloRunnerTypeScript(super.apolloVM, {super.importCorePackageMath});

  @override
  String get language => 'typescript';

  @override
  ApolloRunnerTypeScript copy() {
    return ApolloRunnerTypeScript(apolloVM);
  }
}
