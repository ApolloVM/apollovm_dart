// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import '../../apollovm_runner.dart';

/// Python implementation of an [ApolloRunner].
class ApolloRunnerPython extends ApolloRunner {
  ApolloRunnerPython(super.apolloVM, {super.importCorePackageMath});

  @override
  String get language => 'python';

  @override
  ApolloRunnerPython copy() {
    return ApolloRunnerPython(apolloVM);
  }
}
