@TestOn('vm')
@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
// The core classes are not re-exported from the public library.
import 'package:apollovm/src/core/apollovm_core_base.dart';
import 'package:test/test.dart';

/// The core classes (`String`, `int`, `double`, `List`, `Map`, `Set`) behind
/// the values a program manipulates.
///
/// Two surfaces the language fixtures do not reach: the **method forms** of the
/// members that are properties in Dart (`l.length()` next to `l.length`, which
/// exist so Java-shaped source resolves), and the object machinery a core
/// container deliberately refuses.

Future<Object?> _run(String src) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', src, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source");
  var res = await vm.createRunner('dart')!.executeFunction('', 'run');
  return res.getValueNoContext();
}

/// Normalizes a [FutureOr] so `await` is always valid.
Future<T> _await<T>(FutureOr<T> v) async => await v;

VMScopeContext _scope() => VMScopeContext(ASTBlock(null));

void main() {
  group('Members that are both a property and a call', () {
    test('List: length / isEmpty / isNotEmpty', () async {
      expect(await _run('int run() { var l = [1, 2]; return l.length(); }'), 2);
      expect(
        await _run('bool run() { var l = [1]; return l.isEmpty(); }'),
        isFalse,
      );
      expect(
        await _run('bool run() { var l = <int>[]; return l.isEmpty(); }'),
        isTrue,
      );
      expect(
        await _run('bool run() { var l = [1]; return l.isNotEmpty(); }'),
        isTrue,
      );
    });

    test('List: first / last', () async {
      expect(await _run('int run() { var l = [4, 5]; return l.first(); }'), 4);
      expect(await _run('int run() { var l = [4, 5]; return l.last(); }'), 5);
    });

    test('Map: length / isEmpty / isNotEmpty', () async {
      expect(
        await _run("int run() { var m = {'a': 1}; return m.length(); }"),
        1,
      );
      expect(
        await _run("bool run() { var m = {'a': 1}; return m.isEmpty(); }"),
        isFalse,
      );
      expect(
        await _run("bool run() { var m = {'a': 1}; return m.isNotEmpty(); }"),
        isTrue,
      );
    });

    test('Set: length / isEmpty / isNotEmpty', () async {
      expect(await _run('int run() { var s = {1, 2}; return s.length(); }'), 2);
      expect(
        await _run('bool run() { var s = {1}; return s.isEmpty(); }'),
        isFalse,
      );
      expect(
        await _run('bool run() { var s = {1}; return s.isNotEmpty(); }'),
        isTrue,
      );
    });
  });

  group('Core conversions and comparisons', () {
    test('toString on int, double and String', () async {
      expect(
        await _run('String run() { var i = 3; return i.toString(); }'),
        '3',
      );
      expect(
        await _run('String run() { var d = 1.5; return d.toString(); }'),
        '1.5',
      );
      expect(
        await _run("String run() { var s = 'x'; return s.toString(); }"),
        'x',
      );
    });

    test('String.compareTo orders lexicographically', () async {
      expect(
        await _run("int run() { var a = 'a'; return a.compareTo('b'); }"),
        lessThan(0),
      );
      expect(
        await _run("int run() { var b = 'b'; return b.compareTo('a'); }"),
        greaterThan(0),
      );
      expect(
        await _run("int run() { var a = 'a'; return a.compareTo('a'); }"),
        equals(0),
      );
    });

    test('sublist, with and without an end', () async {
      expect(
        await _run(
          'int run() { var l = [1, 2, 3]; return l.sublist(1).length; }',
        ),
        2,
      );
      expect(
        await _run(
          'int run() { var l = [1, 2, 3]; return l.sublist(0, 2).length; }',
        ),
        2,
      );
    });

    test('List.valueOf wraps whatever it is given', () async {
      // The static conversion Java-shaped source uses. A `List` named in source
      // carries no element type, so resolving the core class must not depend on
      // one — it used to fail the *parse* with a null cast.
      expect(
        await _run('int run() { var l = List.valueOf(5); return l.length; }'),
        1,
        reason: 'a lone value becomes a one-element list',
      );
      expect(
        await _run(
          'int run() { var l = List.valueOf([1, 2]); return l.length; }',
        ),
        2,
        reason: 'a list is passed through',
      );
      expect(
        await _run(
          'int run() { var l = List.valueOf(null); return l.length; }',
        ),
        0,
        reason: 'null becomes an empty list',
      );
    });

    test('an element type resolves through a `dynamic` receiver', () async {
      expect(
        await _run('int run() { dynamic d = [7, 8]; return d.first; }'),
        7,
      );
      expect(
        await _run("int run() { dynamic d = {'a': 1}; return d.keys.length; }"),
        1,
      );
    });

    test('a container bound to `Object` still answers its members', () async {
      // The declared type carries no element type, so the member's type is
      // resolved from the value at run time (or falls back to `dynamic`).
      expect(await _run('int run() { Object o = [1, 2]; return o.first; }'), 1);
      expect(await _run('int run() { Object o = [1, 2]; return o.last; }'), 2);
      expect(await _run('int run() { Object o = {7, 8}; return o.first; }'), 7);
      expect(
        await _run("int run() { Object o = {'a': 1}; return o.keys.length; }"),
        1,
      );
      expect(
        await _run(
          "int run() { Object o = {'a': 1}; return o.values.length; }",
        ),
        1,
      );

      // Same, when the value arrives from a function typed `Object`.
      expect(
        await _run(
          'Object make() { return [3, 4]; }\n'
          'int run() { var o = make(); return o.first; }',
        ),
        3,
      );
    });
  });

  group('A core container is not a user class', () {
    // Every one of these is object machinery a `class` has and a core
    // container does not: refusing them keeps a `List`/`Map`/`Set` a value.
    void expectNoObjectMachinery(ASTClass clazz, ASTValue instance) {
      var context = VMClassContext(clazz, parent: _scope());
      var status = ASTRunStatus();

      expect(() => clazz.fields, throwsUnimplementedError);
      expect(() => clazz.fieldsNames, throwsUnimplementedError);
      expect(() => clazz.getFieldsMap(), throwsUnimplementedError);
      expect(
        () => clazz.createInstance(context, status),
        throwsUnimplementedError,
      );
      expect(
        () => clazz.initializeInstance(context, status, instance),
        throwsUnimplementedError,
      );
      expect(
        () => clazz.getInstanceFieldValue(context, status, instance, 'x'),
        throwsUnimplementedError,
      );
      expect(
        () => clazz.setInstanceFieldValue(
          context,
          status,
          instance,
          'x',
          ASTValueInt(1),
        ),
        throwsUnimplementedError,
      );
      expect(
        () => clazz.removeInstanceFieldValue(context, status, instance, 'x'),
        throwsUnimplementedError,
      );
      expect(
        () => clazz.setInstanceByValue(context, status, instance, instance),
        throwsUnimplementedError,
      );
      expect(
        () => clazz.setInstanceByMap(context, status, instance, const {}),
        throwsUnimplementedError,
      );
      expect(
        () => clazz.setInstanceByVMObject(
          context,
          status,
          instance,
          VMObject.createInstance(context, clazz.type),
        ),
        throwsUnimplementedError,
      );

      // It has no constructors either, but that is answered, not refused.
      expect(clazz.constructors, isEmpty);
      expect(clazz.constructorsNames, isEmpty);
      expect(clazz.getConstructor('', null, _scope()), isNull);

      // And resolving it is a no-op rather than an error.
      expect(() => clazz.resolveNodeFields(null), returnsNormally);
      expect(() => clazz.resolveNodeConstructors(null), returnsNormally);
    }

    test('List', () {
      expectNoObjectMachinery(
        CoreClassList.instanceOfInt,
        ASTValueArray(ASTTypeInt.instance, [1]),
      );
    });

    test('Map', () {
      expectNoObjectMachinery(
        CoreClassMap.instance,
        ASTValueMap(ASTTypeString.instance, ASTTypeInt.instance, {'a': 1}),
      );
    });

    test('Set', () {
      expectNoObjectMachinery(
        CoreClassSet.instance,
        ASTValueSet(ASTTypeInt.instance, {1}),
      );
    });
  });

  group('Core member lookup', () {
    test('an unknown getter or function is named in the error', () {
      var context = _scope();

      expect(
        () => CoreClassList.instanceOfInt.getGetter('nope', context),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('List.nope'),
          ),
        ),
      );
      expect(
        () => CoreClassMap.instance.getFunction(
          'nope',
          ASTFunctionSignature(null, null),
          context,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Map.nope'),
          ),
        ),
      );
      expect(
        () => CoreClassSet.instance.getGetter('nope', context),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Set.nope'),
          ),
        ),
      );
      expect(
        () => CoreClassSet.instance.getFunction(
          'nope',
          ASTFunctionSignature(null, null),
          context,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Set.nope'),
          ),
        ),
      );
    });

    test('`String.valueOf` converts anything to its text', () async {
      // Reached from Java-shaped source: it is how every target that has no
      // interpolation builds a string, and what the Java generator emits.
      Future<Object?> runJava(String type, Object arg) async {
        var vm = ApolloVM();
        var ok = await vm.loadCodeUnit(
          SourceCodeUnit(
            'java11',
            'class T { static String run($type a) '
                '{ return String.valueOf(a); } }',
            id: 'test',
          ),
        );
        expect(ok, isTrue);
        var res = await vm
            .createRunner('java11')!
            .executeClassMethod('', 'T', 'run', positionalParameters: [arg]);
        return res.getValueNoContext();
      }

      expect(await runJava('int', 5), equals('5'));
      expect(await runJava('double', 1.5), equals('1.5'));
    });

    test('`toString` is answered by every core container', () async {
      var context = _scope();
      for (var clazz in [
        CoreClassList.instanceOfInt,
        CoreClassMap.instance,
        CoreClassSet.instance,
      ]) {
        var f = clazz.getFunction(
          'toString',
          ASTFunctionSignature(null, null),
          context,
        );
        expect(f, isNotNull, reason: '$clazz should answer toString');
      }
      await _await(Future.value());
    });
  });
}
