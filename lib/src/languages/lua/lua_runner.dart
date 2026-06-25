// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import '../../apollovm_runner.dart';

/// Lua implementation of an [ApolloRunner].
class ApolloRunnerLua extends ApolloRunner {
  ApolloRunnerLua(super.apolloVM, {super.importCorePackageMath});

  @override
  String get language => 'lua';

  @override
  ApolloRunnerLua copy() {
    return ApolloRunnerLua(apolloVM);
  }
}
