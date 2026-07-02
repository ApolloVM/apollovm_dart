// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'package:apollovm/apollovm.dart';

/// A single diagnostic (parse or runtime) as a JSON-safe map.
///
/// Shape: `{severity, message, position?, line?, column?, sourceLine?}`.
typedef Diagnostic = Map<String, Object?>;

/// Builds a diagnostic from a parser [ParseResult] that carries an error.
///
/// Surfaces the position/line/column info that only exists at parse time
/// (AST nodes themselves carry no source positions).
Diagnostic diagnosticFromParseResult(ParseResult result) {
  final lineCol = result.errorLineAndColumn;
  return <String, Object?>{
    'severity': 'error',
    'message': result.errorMessage ?? 'Parse error',
    if (result.errorPosition != null) 'position': result.errorPosition,
    if (lineCol != null && lineCol.isNotEmpty) 'line': lineCol[0],
    if (lineCol != null && lineCol.length >= 2) 'column': lineCol[1],
    if (result.errorLine != null) 'sourceLine': result.errorLine,
    'detail': result.errorMessageExtended,
  };
}

/// Builds a diagnostic from a thrown error/exception.
///
/// Unwraps a [SyntaxError]'s [ParseResult] when present so parse failures
/// raised via `loadCodeUnit` still yield line/column info.
Diagnostic diagnosticFromError(Object error, {String severity = 'error'}) {
  if (error is SyntaxError) {
    final parseResult = error.parseResult;
    if (parseResult != null) {
      return diagnosticFromParseResult(parseResult);
    }
    return <String, Object?>{'severity': severity, 'message': error.message};
  }

  return <String, Object?>{'severity': severity, 'message': '$error'};
}
