// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import '../../../apollovm_base.dart';
import '../../../apollovm_runner.dart';

/// Java11 implementation of an [ApolloLanguageRunner].
class ApolloRunnerJava11 extends ApolloLanguageRunner {
  ApolloRunnerJava11(ApolloVM apolloVM) : super(apolloVM);

  @override
  String get language => 'java11';

  @override
  ApolloRunnerJava11 copy() {
    return ApolloRunnerJava11(apolloVM);
  }
}
