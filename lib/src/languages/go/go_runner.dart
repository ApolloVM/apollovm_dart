// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import '../../apollovm_runner.dart';

/// Go implementation of an [ApolloRunner].
class ApolloRunnerGo extends ApolloRunner {
  ApolloRunnerGo(super.apolloVM, {super.importCorePackageMath});

  @override
  String get language => 'go';

  @override
  ApolloRunnerGo copy() {
    return ApolloRunnerGo(apolloVM);
  }
}
