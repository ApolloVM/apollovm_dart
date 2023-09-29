// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import '../../apollovm_base.dart';
import '../../apollovm_runner.dart';

/// Dart implementation of an [ApolloLanguageRunner].
class ApolloRunnerDart extends ApolloLanguageRunner {
  ApolloRunnerDart(ApolloVM apolloVM) : super(apolloVM);

  @override
  String get language => 'dart';

  @override
  ApolloRunnerDart copy() {
    return ApolloRunnerDart(apolloVM);
  }
}
