// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import '../../apollovm_runner.dart';

/// Kotlin implementation of an [ApolloRunner].
class ApolloRunnerKotlin extends ApolloRunner {
  ApolloRunnerKotlin(super.apolloVM, {super.importCorePackageMath});

  @override
  String get language => 'kotlin';

  @override
  ApolloRunnerKotlin copy() {
    return ApolloRunnerKotlin(apolloVM);
  }
}
