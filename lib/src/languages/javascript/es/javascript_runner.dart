// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import '../../../apollovm_runner.dart';

/// JavaScript implementation of an [ApolloRunner].
class ApolloRunnerJavaScript extends ApolloRunner {
  ApolloRunnerJavaScript(super.apolloVM, {super.importCorePackageMath});

  @override
  String get language => 'javascript';

  @override
  ApolloRunnerJavaScript copy() {
    return ApolloRunnerJavaScript(apolloVM);
  }
}
