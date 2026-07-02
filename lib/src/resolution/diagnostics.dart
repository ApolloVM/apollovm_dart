// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

/// Severity of an [ImportDiagnostic].
enum ImportDiagnosticSeverity { error, warning }

/// The category of an import/resolution diagnostic.
enum ImportDiagnosticKind {
  /// An import path could not be resolved to any module/package.
  missingModule,

  /// An imported/exported symbol is not exported by the target module.
  missingSymbol,

  /// Two imports bring the same name into scope with conflicting declarations.
  duplicateSymbol,

  /// A cycle of module imports was detected.
  circularImport,

  /// An `export` names a symbol the module does not declare.
  invalidExport,
}

/// A structured diagnostic produced during module resolution.
class ImportDiagnostic {
  final ImportDiagnosticKind kind;

  final ImportDiagnosticSeverity severity;

  final String message;

  /// The module that owns/triggered this diagnostic.
  final String moduleId;

  /// The offending import/export path, when applicable.
  final String? importPath;

  /// The offending symbol name, when applicable.
  final String? symbolName;

  const ImportDiagnostic({
    required this.kind,
    required this.moduleId,
    required this.message,
    this.severity = ImportDiagnosticSeverity.error,
    this.importPath,
    this.symbolName,
  });

  const ImportDiagnostic.missingModule(
    this.moduleId,
    String path, {
    this.severity = ImportDiagnosticSeverity.error,
  }) : kind = ImportDiagnosticKind.missingModule,
       importPath = path,
       symbolName = null,
       message = "Can't resolve import: $path";

  const ImportDiagnostic.missingSymbol(
    this.moduleId,
    String path,
    String symbol, {
    this.severity = ImportDiagnosticSeverity.error,
  }) : kind = ImportDiagnosticKind.missingSymbol,
       importPath = path,
       symbolName = symbol,
       message = "Module '$path' does not export '$symbol'";

  const ImportDiagnostic.duplicateSymbol(
    this.moduleId,
    String symbol, {
    this.severity = ImportDiagnosticSeverity.error,
  }) : kind = ImportDiagnosticKind.duplicateSymbol,
       importPath = null,
       symbolName = symbol,
       message = "Duplicate imported symbol: '$symbol'";

  const ImportDiagnostic.circularImport(
    this.moduleId,
    String cycle, {
    this.severity = ImportDiagnosticSeverity.error,
  }) : kind = ImportDiagnosticKind.circularImport,
       importPath = null,
       symbolName = null,
       message = "Circular import: $cycle";

  const ImportDiagnostic.invalidExport(
    this.moduleId,
    String symbol, {
    this.severity = ImportDiagnosticSeverity.error,
  }) : kind = ImportDiagnosticKind.invalidExport,
       importPath = null,
       symbolName = symbol,
       message = "Invalid export: '$symbol' is not declared in this module";

  bool get isError => severity == ImportDiagnosticSeverity.error;

  @override
  String toString() =>
      '[${severity.name.toUpperCase()}] ${kind.name} ($moduleId): $message';
}
