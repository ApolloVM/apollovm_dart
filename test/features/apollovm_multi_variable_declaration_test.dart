@TestOn('vm')
@Tags(['dart', 'javascript', 'python'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Loads a single Dart [source] and runs the top-level [function], returning
/// the values captured from its `print` calls.
Future<List> runPrint(String source, [String function = 'main']) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', source, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source!");

  var runner = vm.createRunner('dart')!;
  var output = [];
  runner.externalPrintFunction = output.add;

  await runner.executeFunction('', function);
  return output;
}

/// Translates a Dart [source] to [language] and returns the generated code.
Future<String> translate(String source, String language) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', source, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source!");

  var codeStorage = vm.generateAllCodeIn(language);

  var buffer = StringBuffer();
  for (var ns in await codeStorage.getNamespaces()) {
    for (var id in await codeStorage.getNamespaceCodeUnitsIDs(ns)) {
      buffer.write(await codeStorage.getNamespaceCodeUnit(ns, id));
    }
  }
  return buffer.toString();
}

void main() {
  group('multiple declarators', () {
    test('num nr = 0.96, ng = 0.24, nb = 0.56', () async {
      var output = await runPrint('''
        void main() {
          num nr = 0.96, ng = 0.24, nb = 0.56;

          print(nr);
          print(ng);
          print(nb);
        }
      ''');

      expect(output, equals([0.96, 0.24, 0.56]));
    });

    test('declarators are independent variables', () async {
      var output = await runPrint('''
        void main() {
          int a = 1, b = 2;
          a = a + 10;
          print(a);
          print(b);
        }
      ''');

      expect(output, equals([11, 2]));
    });

    test('initialized left to right, later reads earlier', () async {
      var output = await runPrint('''
        void main() {
          int p = 1, q = p + 1, r = q * 10;
          print(p);
          print(q);
          print(r);
        }
      ''');

      expect(output, equals([1, 2, 20]));
    });

    test('a declarator may omit its initializer', () async {
      var output = await runPrint('''
        void main() {
          int a, b = 5, c;
          print(a);
          print(b);
          print(c);
        }
      ''');

      expect(output, equals([null, 5, null]));
    });

    test('`var` infers each declarator separately', () async {
      var output = await runPrint('''
        void main() {
          var a = 1, b = 'x', c = 2.5;
          print(a);
          print(b);
          print(c);
        }
      ''');

      expect(output, equals([1, 'x', 2.5]));
    });

    test('`final`, `const` and `late` cover every declarator', () async {
      var output = await runPrint('''
        void main() {
          final int f1 = 10, f2 = 20;
          const int k1 = 3, k2 = 4;
          late int z1 = 7, z2 = 8;

          print(f1 + f2);
          print(k1 * k2);
          print(z1 + z2);
        }
      ''');

      expect(output, equals([30, 12, 15]));
    });

    test('non-primitive types', () async {
      var output = await runPrint('''
        void main() {
          List<int> l1 = [1, 2], l2 = [3];
          String s1 = 'a', s2 = 'b';

          print(l1);
          print(l2);
          print(s1 + s2);
        }
      ''');

      expect(
        output,
        equals([
          [1, 2],
          [3],
          'ab',
        ]),
      );
    });

    test('declared at the top level', () async {
      var output = await runPrint('''
        int gx = 1, gy = 2;

        void main() {
          print(gx);
          print(gy);
          print(gx + gy);
        }
      ''');

      expect(output, equals([1, 2, 3]));
    });

    test('inside a nested block and a loop body', () async {
      var output = await runPrint('''
        void main() {
          for (int i = 0; i < 2; ++i) {
            int p = i, q = i * 10;
            print(p + q);
          }
          {
            int a = 1, b = 2;
            print(a + b);
          }
        }
      ''');

      expect(output, equals([0, 11, 3]));
    });

    test('each declarator is type checked against the declared type', () async {
      expect(
        () => runPrint('''
          void main() {
            int a = 1, b = 'x';
            print(a);
            print(b);
          }
        '''),
        throwsA(isA<ApolloVMRuntimeError>()),
      );
    });

    test('a `for` initializer still takes a single declarator', () async {
      // The `for` header has nowhere to put the extra declarations the multi
      // form expands into, so it is rejected at parse time rather than parsed
      // into something no target language can express.
      var vm = ApolloVM();
      expect(
        () => vm.loadCodeUnit(
          SourceCodeUnit('dart', '''
            void main() {
              for (int i = 0, j = 2; i < j; ++i) {
                print(i);
              }
            }
          ''', id: 'test'),
        ),
        throwsA(isA<SyntaxError>()),
      );
    });
  });

  group('ASTStatementVariableDeclarationList', () {
    ASTStatementVariableDeclarationList list() =>
        ASTStatementVariableDeclarationList([
          ASTStatementVariableDeclaration(
            ASTTypeInt.instance,
            'a',
            ASTExpressionLiteral(ASTValueInt(1)),
          ),
          ASTStatementVariableDeclaration(
            ASTTypeInt.instance,
            'b',
            ASTExpressionLiteral(ASTValueInt(2)),
          ),
        ]);

    test('a block expands it away instead of storing it', () {
      var block = ASTBlock(null)..addStatement(list());

      expect(block.statements, hasLength(2));
      expect(
        block.statements.map(
          (s) => (s as ASTStatementVariableDeclaration).name,
        ),
        equals(['a', 'b']),
      );
      expect(
        block.statements,
        everyElement(isA<ASTStatementVariableDeclaration>()),
      );
    });

    test('exposes the declarations as its children', () {
      var l = list();
      expect(l.children, equals(l.declarations));
    });

    test('resolveNode reaches every declaration', () {
      var block = ASTBlock(null);
      var l = list();
      l.resolveNode(block);

      expect(l.parentNode, same(block));
      for (var d in l.declarations) {
        expect(d.parentNode, same(block));
      }
    });

    test('running it declares every variable in the same context', () async {
      var l = list();
      var context = VMScopeContext(ASTBlock(null));

      var result = await l.run(context, ASTRunStatus());

      expect(result.getValueNoContext(), equals(2));
      for (var (name, value) in [('a', 1), ('b', 2)]) {
        var variable = await context.getVariable(name, false);
        expect(
          variable,
          isNotNull,
          reason: 'Variable `$name` not declared in the run context.',
        );
        expect(
          (await variable!.getValue(context)).getValueNoContext(),
          equals(value),
        );
      }
    });

    test('resolveType is void, toString lists the declarations', () {
      var l = list();
      expect(l.resolveType(null), isA<ASTTypeVoid>());
      expect(l.toString(), equals('${l.declarations[0]} ${l.declarations[1]}'));
    });
  });

  group('translation', () {
    const source = '''
      void main() {
        num nr = 0.96, ng = 0.24, nb = 0.56;

        print(nr);
        print(ng);
        print(nb);
      }
    ''';

    test('Dart emits one declaration per declarator', () async {
      var code = await translate(source, 'dart');

      expect(code, contains('num nr = 0.96;'));
      expect(code, contains('num ng = 0.24;'));
      expect(code, contains('num nb = 0.56;'));
    });

    test('JavaScript emits one declaration per declarator', () async {
      var code = await translate(source, 'javascript');

      expect(code, contains('let nr = 0.96;'));
      expect(code, contains('let ng = 0.24;'));
      expect(code, contains('let nb = 0.56;'));
    });

    test('Python emits one declaration per declarator', () async {
      var code = await translate(source, 'python');

      expect(code, contains('nr: float = 0.96'));
      expect(code, contains('ng: float = 0.24'));
      expect(code, contains('nb: float = 0.56'));
    });

    test('generated Dart parses and runs the same', () async {
      var code = await translate(source, 'dart');
      var output = await runPrint(code);

      expect(output, equals([0.96, 0.24, 0.56]));
    });
  });
}
