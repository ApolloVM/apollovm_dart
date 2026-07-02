@TestOn('vm')
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

Future<String> _gen(String language, Map<String, String> sources) async {
  var vm = ApolloVM();
  for (var e in sources.entries) {
    await vm.loadCodeUnit(SourceCodeUnit(language, e.value, id: e.key));
  }
  return (await vm.generateAllCodeIn(language).writeAllSources()).toString();
}

void main() {
  group('Import/export/typedef generation', () {
    test('Dart: show/hide/prefix imports, export, typedef round-trip', () async {
      var out = await _gen('dart', {
        'lib.dart': 'class A { A(); }\nclass B { B(); }\nint f(int x) { return x; }',
        'main.dart': '''
import 'lib.dart' show A;
import 'lib.dart' as p;
export 'lib.dart' hide B;

typedef Id = int;

int run() { return p.f(1); }
''',
      });

      expect(out, contains("import 'lib.dart' show A;"));
      expect(out, contains("import 'lib.dart' as p;"));
      expect(out, contains("export 'lib.dart' hide B;"));
      expect(out, contains('typedef Id = int;'));
    });

    test('TypeScript: named import, export, type alias', () async {
      var out = await _gen('typescript', {
        'user.ts': 'class User { constructor() {} }\nclass Admin { constructor() {} }',
        'main.ts': '''
import { User as U, Admin } from './user';
export { U };
export * from './user';

type Id = number;
''',
      });

      expect(out, contains("import { User as U, Admin } from './user';"));
      expect(out, contains('export { U }'));
      expect(out, contains("export * from './user';"));
      expect(out, contains('type Id = number;'));
    });

    test('TypeScript: namespace and default import forms', () async {
      var out = await _gen('typescript', {
        'x.ts': 'class X { constructor() {} }',
        'a.ts': "import * as ns from './x';\n",
        'b.ts': "import Def from './x';\n",
      });
      expect(out, contains("import * as ns from './x';"));
      expect(out, contains("import Def from './x';"));
    });

    test('Python: from-import (alias + wildcard) and import-as', () async {
      var out = await _gen('python', {
        'helpers.py': 'def add(a, b):\n    return a + b\n',
        'a.py': 'from helpers import add as plus\n',
        'b.py': 'from helpers import *\n',
        'c.py': 'import helpers as h\n',
      });
      expect(out, contains('from helpers import add as plus'));
      expect(out, contains('from helpers import *'));
      expect(out, contains('import helpers as h'));
    });

    test('base no-op export/typedef generation for a language without support',
        () async {
      // Generating a program that has a typedef + export as Java exercises the
      // base generator's default no-op export/type-alias emission (Java has no
      // such concept) without crashing.
      var vm = ApolloVM();
      await vm.loadCodeUnit(SourceCodeUnit('dart', '''
export 'other.dart';
typedef Id = int;
class Foo {
  Foo();
  int f(int x) { return x; }
}
''', id: 'main.dart'));
      var out = (await vm.generateAllCodeIn('java11').writeAllSources()).toString();
      expect(out, contains('class Foo'));
      // Java output omits the Dart-only export/typedef directives.
      expect(out, isNot(contains('typedef')));
    });
  });
}
