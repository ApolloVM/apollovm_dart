@TestOn('vm')
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

void main() {
  group('ASTStatementImport (canonical model)', () {
    test('plain import: not selective, imports everything', () {
      var i = ASTStatementImport('user.dart');
      expect(i.isSelective, isFalse);
      expect(i.importsSymbol('Anything'), isTrue);
      expect(i.localNameOf('Anything'), 'Anything');
      expect(i.toString(), contains('import "user.dart"'));
    });

    test('named symbols: selective, aliases applied', () {
      var i = ASTStatementImport('u.dart', namedSymbols: const [
        ASTImportedSymbol('User', alias: 'U'),
        ASTImportedSymbol('Role'),
      ]);
      expect(i.isSelective, isTrue);
      expect(i.importsSymbol('User'), isTrue);
      expect(i.importsSymbol('Role'), isTrue);
      expect(i.importsSymbol('Other'), isFalse);
      expect(i.localNameOf('User'), 'U');
      expect(i.localNameOf('Role'), 'Role');
      expect(i.toString(), contains('show User as U, Role'));
    });

    test('show combinator is selective; hide is not', () {
      var show = ASTStatementImport('x', combinators: const [
        ASTImportCombinator(ASTImportCombinatorKind.show, ['A']),
      ]);
      expect(show.isSelective, isTrue);
      expect(show.importsSymbol('A'), isTrue);
      expect(show.importsSymbol('B'), isFalse);

      var hide = ASTStatementImport('x', combinators: const [
        ASTImportCombinator(ASTImportCombinatorKind.hide, ['A']),
      ]);
      expect(hide.isSelective, isFalse);
      expect(hide.importsSymbol('A'), isFalse);
      expect(hide.importsSymbol('B'), isTrue);
      expect(hide.toString(), contains('hide A'));
    });

    test('prefix + wildcard rendering', () {
      var i = ASTStatementImport('x', prefix: 'p', wildcard: true);
      expect(i.toString(), contains('as p'));
    });

    test('equality and hashCode', () {
      var a = ASTStatementImport('x', prefix: 'p', namedSymbols: const [
        ASTImportedSymbol('A'),
      ]);
      var b = ASTStatementImport('x', prefix: 'p', namedSymbols: const [
        ASTImportedSymbol('A'),
      ]);
      var c = ASTStatementImport('x', prefix: 'q');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });

  group('ASTImportCombinator / ASTImportedSymbol', () {
    test('combinator equality, kind flags, toString', () {
      var show = const ASTImportCombinator(ASTImportCombinatorKind.show, ['A', 'B']);
      var show2 = const ASTImportCombinator(ASTImportCombinatorKind.show, ['A', 'B']);
      var hide = const ASTImportCombinator(ASTImportCombinatorKind.hide, ['A']);
      expect(show.isShow, isTrue);
      expect(show.isHide, isFalse);
      expect(hide.isHide, isTrue);
      expect(show, equals(show2));
      expect(show.hashCode, equals(show2.hashCode));
      expect(show, isNot(equals(hide)));
      expect(show.toString(), 'show A, B');
      expect(hide.toString(), 'hide A');
    });

    test('symbol localName, equality, toString', () {
      var s = const ASTImportedSymbol('User', alias: 'U');
      var plain = const ASTImportedSymbol('User');
      expect(s.localName, 'U');
      expect(plain.localName, 'User');
      expect(s.toString(), 'User as U');
      expect(plain.toString(), 'User');
      expect(s, equals(const ASTImportedSymbol('User', alias: 'U')));
      expect(s.hashCode, equals(const ASTImportedSymbol('User', alias: 'U').hashCode));
      expect(s, isNot(equals(plain)));
    });
  });

  group('ASTStatementExport', () {
    test('re-export from path with combinators', () {
      var e = ASTStatementExport(path: 'x', combinators: const [
        ASTImportCombinator(ASTImportCombinatorKind.show, ['A']),
      ]);
      expect(e.path, 'x');
      expect(e.toString(), contains('export'));
      expect(e.toString(), contains('show A'));
      expect(e.toString(), contains('"x"'));
    });

    test('own-symbol export equality/hashCode', () {
      var a = ASTStatementExport(symbols: const [ASTImportedSymbol('A')]);
      var b = ASTStatementExport(symbols: const [ASTImportedSymbol('A')]);
      var c = ASTStatementExport(symbols: const [ASTImportedSymbol('B')]);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
      expect(a.toString(), contains('{ A }'));
    });
  });

  group('SymbolTable / ResolvedSymbol', () {
    ResolvedSymbol sym(String name, {SymbolKind kind = SymbolKind.typeAlias}) =>
        ResolvedSymbol(
          name: name,
          kind: kind,
          moduleId: 'm',
          declaration: ASTTypeAlias(name, ASTTypeString.instance),
        );

    test('define/lookup/parent chain', () {
      var global = SymbolTable(SymbolScopeLevel.global);
      var module = SymbolTable(SymbolScopeLevel.module, parent: global, moduleId: 'm');
      global.define(sym('G'));
      module.define(sym('M'));

      expect(module.lookupLocal('M'), hasLength(1));
      expect(module.lookupLocal('G'), isEmpty);
      expect(module.lookup('G'), hasLength(1)); // walks to parent
      expect(module.lookupFirst('M'), isNotNull);
      expect(module.lookupFirst('missing'), isNull);
      expect(module.contains('G'), isTrue);
      expect(module.contains('nope'), isFalse);
      expect(module.names, contains('M'));
      expect(module.toString(), contains('module'));
    });

    test('define returns false on a duplicate distinct declaration', () {
      var t = SymbolTable(SymbolScopeLevel.module, moduleId: 'm');
      expect(t.define(sym('X', kind: SymbolKind.klass)), isTrue);
      expect(t.define(sym('X', kind: SymbolKind.klass)), isFalse);
    });

    test('ResolvedSymbol.withName + toString', () {
      var s = sym('A');
      var r = s.withName('B');
      expect(r.name, 'B');
      expect(r.kind, s.kind);
      expect(s.toString(), contains('A'));
    });
  });

  group('ImportScope (from a resolved module)', () {
    Future<ImportScope> scopeOf(Map<String, String> sources, String mainId) async {
      var vm = ApolloVM();
      for (var e in sources.entries) {
        await vm.loadCodeUnit(SourceCodeUnit('dart', e.value, id: e.key));
      }
      vm.resolve(language: 'dart');
      return vm.resolutionEngine.importScopeFor(mainId)!;
    }

    test('unprefixed class + type alias + function resolution', () async {
      var scope = await scopeOf({
        'lib.dart': '''
typedef Id = int;
class Widget { Widget(); }
int helper(int x) { return x; }
''',
        'main.dart': "import 'lib.dart';\n",
      }, 'main.dart');

      expect(scope.isEmpty, isFalse);
      expect(scope.resolve('Widget'), isNotNull);
      expect(scope.resolveClass('Widget'), isNotNull);
      expect(scope.resolveNode('Widget'), isNotNull);
      expect(scope.resolveFunctionSet('helper'), isNotNull);
      expect(scope.resolveTypeAlias('Id'), isNotNull);
      expect(scope.resolveClass('helper'), isNull);
      expect(scope.resolveTypeAlias('Widget'), isNull);
      expect(scope.toString(), contains('named'));
    });

    test('prefixed resolution helpers', () async {
      var scope = await scopeOf({
        'lib.dart': '''
class Widget { Widget(); }
int helper(int x) { return x; }
''',
        'main.dart': "import 'lib.dart' as p;\n",
      }, 'main.dart');

      expect(scope.hasPrefix('p'), isTrue);
      expect(scope.resolvePrefixed('p', 'Widget'), isNotNull);
      expect(scope.resolvePrefixedClass('p', 'Widget'), isNotNull);
      expect(scope.resolvePrefixedNode('p', 'Widget'), isNotNull);
      expect(scope.resolvePrefixedFunctionSet('p', 'helper'), isNotNull);
      expect(scope.resolvePrefixed('p', 'nope'), isNull);
      expect(scope.resolvePrefixedClass('p', 'helper'), isNull);
    });
  });
}
