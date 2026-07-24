// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.
/// A portable virtual machine for Dart, web (JavaScript), and Flutter.
///
/// ApolloVM enables parsing, translation, and execution of multiple
/// programming languages, including Dart and Java. It also
/// supports on-the-fly compilation to WebAssembly (Wasm).
library;

export 'package:async_extension/async_extension.dart';

export 'src/analysis/null_safety_analyzer.dart';
export 'src/apollovm_base.dart';
export 'src/apollovm_generated_output.dart';
export 'src/apollovm_generator.dart';
export 'src/apollovm_parser.dart';
export 'src/apollovm_runner.dart';
export 'src/apollovm_utils.dart';
export 'src/ast/apollovm_ast_annotation.dart';
export 'src/ast/apollovm_ast_base.dart';
export 'src/ast/apollovm_ast_expression.dart';
export 'src/ast/apollovm_ast_statement.dart';
export 'src/ast/apollovm_ast_toplevel.dart';
export 'src/ast/apollovm_ast_type.dart';
export 'src/ast/apollovm_ast_value.dart';
export 'src/ast/apollovm_ast_variable.dart';
export 'src/languages/csharp/csharp_parser.dart';
export 'src/languages/csharp/csharp_runner.dart';
export 'src/languages/dart/dart_parser.dart';
export 'src/languages/dart/dart_runner.dart';
export 'src/languages/go/go_parser.dart';
export 'src/languages/go/go_runner.dart';
export 'src/languages/java/java11/java11_parser.dart';
export 'src/languages/java/java11/java11_runner.dart';
export 'src/languages/wasm/wasm_parser.dart';
export 'src/languages/wasm/wasm_runner.dart';
export 'src/languages/wasm/wasm_runtime.dart';
export 'src/resolution/dependency_graph.dart';
export 'src/resolution/diagnostics.dart';
export 'src/resolution/module_loader.dart';
export 'src/resolution/module_resolution_engine.dart';
export 'src/resolution/module_resolver.dart';
export 'src/resolution/resolution_cache.dart';
export 'src/resolution/symbol_table.dart';
