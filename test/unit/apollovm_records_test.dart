@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:apollovm/apollovm_serialization.dart';
import 'package:test/test.dart';

/// Dart records (3.0): literals, types, field access, equality.

Future<ApolloVM> _load(String src) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', src, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source");
  return vm;
}

Future<Object?> _runVM(ApolloVM vm) async {
  var res = await vm.createRunner('dart')!.executeFunction('', 'run');
  return res.getValueNoContext();
}

Future<Object?> _run(String src) async => _runVM(await _load(src));

void main() {
  group('Record literals', () {
    test('positional fields: `\$1`, `\$2`', () async {
      expect(
        await _run(r'int run() { var r = (1, 2); return r.$1 * 10 + r.$2; }'),
        equals(12),
      );
    });

    test('named fields', () async {
      expect(
        await _run('int run() { var r = (x: 3, y: 4); return r.x * r.y; }'),
        equals(12),
      );
    });

    test('positional and named fields interleaved', () async {
      expect(
        await _run(
          r'String run() { var r = (1, name: "n", 2); '
          r'return "${r.$1} ${r.name} ${r.$2}"; }',
        ),
        equals('1 n 2'),
      );
    });

    test('a one-field record needs the trailing comma', () async {
      expect(
        await _run(r'int run() { var r = (7,); return r.$1; }'),
        equals(7),
      );
      // Without it, the parentheses only group.
      expect(await _run('int run() { return (1 + 2) * 3; }'), equals(9));
    });

    test('fields are evaluated in source order', () async {
      expect(
        await _run(
          'List<int> log = [];\n'
          'int f(int v) { log.add(v); return v; }\n'
          'String run() { var r = (f(1), b: f(2), f(3)); return "\$log"; }',
        ),
        equals('[1, 2, 3]'),
      );
    });

    test('nested records, and a call on a field', () async {
      expect(
        await _run(
          r'String run() { var r = ((1, 2), (a: "x")); '
          r'return "${r.$1.$2}" + r.$2.a.toUpperCase(); }',
        ),
        equals('2X'),
      );
    });

    test('a class instance in a field keeps its identity', () async {
      expect(
        await _run(
          'class A { int v = 5; }\n'
          r'int run() { var a = A(); var r = (a, 1); a.v = 6; return r.$1.v; }',
        ),
        equals(6),
      );
    });

    test('the host gets a `VMRecord`', () async {
      var r = await _run('Object run() { return (1, "a", flag: true); }');
      expect(r, isA<VMRecord>());
      expect('$r', equals('(1, a, flag: true)'));
      var record = r as VMRecord;
      expect(record.positional.map((v) => v.getValueNoContext()), [1, 'a']);
      expect(record.named.keys, ['flag']);
    });

    test('`toString` is Dart\'s', () async {
      expect(
        await _run(
          r'String run() { var a = (1, "a", b: true); var b = (7,); return "$a $b"; }',
        ),
        equals('(1, a, b: true) (7,)'),
      );
    });

    test('a missing field is a runtime error', () async {
      var vm = await _load(r'int run() { var r = (1, 2); return r.$3; }');
      await expectLater(
        _runVM(vm),
        throwsA(
          isA<ApolloVMRuntimeError>().having(
            (e) => e.toString(),
            'message',
            contains('has no field `\$3`'),
          ),
        ),
      );
    });

    test('a duplicate field name does not parse', () async {
      var vm = ApolloVM();
      await expectLater(
        vm.loadCodeUnit(
          SourceCodeUnit(
            'dart',
            'int run() { var r = (a: 1, a: 2); return 0; }',
            id: 'test',
          ),
        ),
        throwsA(isA<SyntaxError>()),
      );
    });
  });

  group('Equality', () {
    test('structural, positional order included', () async {
      expect(
        await _run(
          'bool run() { return (1, x: 2) == (1, x: 2) && (1, 2) != (2, 1) '
          '&& (1, x: 2) != (1, y: 2); }',
        ),
        isTrue,
      );
    });

    test('records as set elements', () async {
      expect(
        await _run(
          'int run() { var s = {(1, 2), (1, 2), (2, 1)}; return s.length; }',
        ),
        equals(2),
      );
    });
  });

  group('Record types', () {
    test('as return, parameter and variable types', () async {
      expect(
        await _run(
          '(int, String) pair() { return (1, "ab"); }\n'
          r'int size((int, String) p) { return p.$1 + p.$2.length; }'
          '\n'
          'int run() { (int, String) p = pair(); return size(p); }',
        ),
        equals(3),
      );
    });

    test('named fields, a one-field type, a nullable type', () async {
      expect(
        await _run(
          '({int x, int y}) pt() { return (x: 1, y: 2); }\n'
          '(int, int)? maybe(bool b) { return b ? (3, 4) : null; }\n'
          r'int run() { var p = pt(); (int,) one = (5,); var m = maybe(true); '
          r'var n = maybe(false); '
          r'return p.x + p.y + one.$1 + m!.$2 + (n == null ? 100 : 0); }',
        ),
        equals(1 + 2 + 5 + 4 + 100),
      );
    });

    test('a collection of records', () async {
      expect(
        await _run(
          r'int run() { List<(int, int)> l = [(1, 2), (3, 4)]; var s = 0; '
          r'for (var p in l) { s += p.$1 * p.$2; } return s; }',
        ),
        equals(14),
      );
    });

    test('a wider record type accepts a narrower record', () async {
      expect(
        await _run(
          r'int run() { (num, num) r = (1, 2); r = (3.5, 4); return 1; }',
        ),
        equals(1),
      );
    });

    test('a record of another shape or field type is rejected', () async {
      for (var value in ['(1, "a")', '(1, 2, 3)', '(a: 1, b: 2)']) {
        var vm = await _load('int run() { (int, int) r = $value; return 0; }');
        await expectLater(
          _runVM(vm),
          throwsA(isA<ApolloVMRuntimeError>()),
          reason: value,
        );
      }
    });

    test('`is` tests by shape and field types', () async {
      expect(
        await _run(
          'bool run() { Object r = (1, 2); '
          'return r is (int, int) && r is (num, num) && !(r is (int, String)) '
          '&& !(r is (int, int, int)); }',
        ),
        isTrue,
      );
    });
  });

  group('Found along the way', () {
    test('a field read after an index access: `l[0].v`', () async {
      expect(
        await _run(
          'class A { int v; A(this.v); }\n'
          "int run() { var l = [A(1), A(2)]; var m = {'k': A(5)}; "
          "return l[1].v * 10 + m['k'].v + l[0].v.abs(); }",
        ),
        equals(26),
      );
    });

    test(
      '`return null` from a nullable `String?` / `List?` is `null`',
      () async {
        expect(
          await _run(
            'String? s(bool b) { return b ? "x" : null; }\n'
            'List<int>? l(bool b) { return b ? [1] : null; }\n'
            'int run() { var t = s(true); return (s(false) == null ? 1 : 0) + '
            '(l(false) == null ? 10 : 0) + t!.length * 100; }',
          ),
          equals(111),
        );
      },
    );
  });

  group('Serialization and generation', () {
    const src =
        '(int, {String name}) make(int n) { return (n, name: "r\$n"); }\n'
        'List<(int, int)> pairs = [(1, 2)];\n'
        r'String run() { var r = make(3); (int,) one = (4,); '
        r'return "${r.$1} ${r.name} ${one.$1} ${pairs[0].$2}"; }';

    test('survives the binary AST', () async {
      var vm = await _load(src);
      var image = vm.saveCodeUnitAST(vm.allCodeUnitsAllLanguages().single);
      var vm2 = ApolloVM();
      expect(await vm2.loadCodeUnitAST(image), isTrue);
      expect(await _runVM(vm2), equals('3 r3 4 2'));
    });

    test('regenerates as Dart', () async {
      var vm = await _load(src);
      var code = (await vm
          .generateAllCodeIn('dart')
          .getNamespaceCodeUnit('', 'test'))!;
      expect(code, contains('(int, {String name}) make(int n)'));
      expect(code, contains("(n, name: 'r\$n')"));
      expect(code, contains('(int,) one = (4,);'));
      expect(await _runVM(await _load(code)), equals('3 r3 4 2'));
    });

    test('other targets refuse a record', () async {
      for (var language in ['java11', 'kotlin', 'python', 'typescript']) {
        var vm = await _load(r'int run() { var r = (1, 2); return r.$1; }');
        await expectLater(
          () async => vm.generateAllCodeIn(language),
          throwsA(isA<UnsupportedSyntaxError>()),
          reason: language,
        );
      }
    });
  });
}
