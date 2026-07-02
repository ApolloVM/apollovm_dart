import 'package:apollovm/apollovm_lsp.dart';
import 'package:test/test.dart';

void main() {
  final analyzer = Analyzer();

  test('parses valid Dart and collects symbols', () async {
    final unit = await analyzer.analyze('file:///m.dart', '''
/// Adds two numbers.
int add(int a, int b) {
  return a + b;
}
''');
    expect(unit.ast, isNotNull);
    expect(unit.diagnostics, isEmpty);
    final add = unit.symbolFor('add');
    expect(add, isNotNull);
    expect(add!.signature, 'int add(int a, int b)');
  });

  test('reports a parse error with a position', () async {
    final unit = await analyzer.analyze('file:///bad.dart', 'class {{{ ');
    expect(unit.ast, isNull);
    expect(unit.diagnostics, isNotEmpty);
    expect(unit.diagnostics.first.severity, DiagnosticSeverity.error);
  });

  test('warns on an unresolvable core import', () async {
    final unit = await analyzer.analyze('file:///i.dart', '''
import 'dart:collection';

int one() { return 1; }
''');
    final importDiag = unit.diagnostics
        .where((d) => d.code == 'unresolved-import')
        .toList();
    expect(importDiag, hasLength(1));
    expect(importDiag.first.severity, DiagnosticSeverity.warning);
  });

  test('does not warn on a resolvable core import (dart:math)', () async {
    final unit = await analyzer.analyze('file:///ok.dart', '''
import 'dart:math';

int one() { return 1; }
''');
    expect(unit.diagnostics.where((d) => d.code == 'unresolved-import'), isEmpty);
  });

  test('detects language from extension', () {
    expect(Analyzer.languageOf('file:///a.dart'), 'dart');
    expect(Analyzer.languageOf('file:///a.java'), 'java');
    expect(Analyzer.languageOf('file:///a.unknown'), isNull);
  });
}
