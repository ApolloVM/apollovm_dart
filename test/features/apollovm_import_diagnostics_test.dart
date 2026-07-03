@TestOn('vm')
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

Future<ApolloVM> _loadDart(Map<String, String> sources) async {
  var vm = ApolloVM();
  for (var e in sources.entries) {
    await vm.loadCodeUnit(SourceCodeUnit('dart', e.value, id: e.key));
  }
  return vm;
}

bool _has(List<ImportDiagnostic> ds, ImportDiagnosticKind kind) =>
    ds.any((d) => d.kind == kind);

void main() {
  group('Import diagnostics', () {
    test('missingModule for an unresolvable import path', () async {
      var vm = await _loadDart({
        'main.dart': "import 'does_not_exist.dart';\n",
      });
      var ds = vm.resolve(language: 'dart');
      expect(_has(ds, ImportDiagnosticKind.missingModule), isTrue);
    });

    test('missingSymbol for a `show` of a non-exported name', () async {
      var vm = await _loadDart({
        'lib.dart': 'class A { A(); }',
        'main.dart': "import 'lib.dart' show Nope;\n",
      });
      var ds = vm.resolve(language: 'dart');
      expect(_has(ds, ImportDiagnosticKind.missingSymbol), isTrue);
    });

    test('duplicateSymbol when two imports bring the same name', () async {
      var vm = await _loadDart({
        'a.dart': 'class Dup { Dup(); }',
        'b.dart': 'class Dup { Dup(); }',
        'main.dart': "import 'a.dart';\nimport 'b.dart';\n",
      });
      var ds = vm.resolve(language: 'dart');
      expect(_has(ds, ImportDiagnosticKind.duplicateSymbol), isTrue);
    });

    test('circularImport for a 2-cycle', () async {
      var vm = await _loadDart({
        'a.dart': "import 'b.dart';\nclass A { A(); }",
        'b.dart': "import 'a.dart';\nclass B { B(); }",
      });
      var ds = vm.resolve(language: 'dart');
      expect(_has(ds, ImportDiagnosticKind.circularImport), isTrue);
    });

    test('invalidExport for exporting an undeclared symbol', () async {
      // TypeScript supports path-less own-symbol re-exports (`export { X };`).
      var vm = ApolloVM();
      await vm.loadCodeUnit(
        SourceCodeUnit('typescript', 'export { Missing };\n', id: 'main.ts'),
      );
      var ds = vm.resolve(language: 'typescript');
      expect(_has(ds, ImportDiagnosticKind.invalidExport), isTrue);
    });

    test('clean multi-file program produces no diagnostics', () async {
      var vm = await _loadDart({
        'user.dart': 'class User { User(); }',
        'main.dart': "import 'user.dart' show User;\n",
      });
      var ds = vm.resolve(language: 'dart');
      expect(ds, isEmpty);
    });
  });
}
