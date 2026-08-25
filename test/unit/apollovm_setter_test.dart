@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Setter behaviour that the XML definition corpus cannot express: extension
/// setters, and the per-target *refusals* (a thrown `UnsupportedSyntaxError`
/// produces no generated source to pin with a `<source-generated>` block).

Future<ApolloVM> _load(String src) async {
  var vm = ApolloVM();
  var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', src, id: 'test'));
  expect(ok, isTrue, reason: "Can't load Dart source");
  return vm;
}

Future<Object?> _runFunction(String src, String name) async {
  var vm = await _load(src);
  var r = await vm.createRunner('dart')!.executeFunction('', name);
  return r.getValueNoContext();
}

Future<Object?> _runStatic(String src, String clazz, String name) async {
  var vm = await _load(src);
  var r = await vm.createRunner('dart')!.executeClassMethod('', clazz, name);
  return r.getValueNoContext();
}

/// Setter-only on purpose. With a getter alongside, the *getter* refusal fires
/// first for every non-Dart target and satisfies the expectation, so the setter
/// path would never be reached and the assertion would prove nothing.
const _classWithSetter = r'''
class B {
  int _v = 0;
  set value(int x) { _v = x; }
}
''';

const _classWithGetterOnly = r'''
class B {
  int _v = 21;
  int get value => _v * 2;
}
''';

void main() {
  group('extension setters', () {
    test('an extension setter runs on assignment', () async {
      expect(
        await _runFunction(r'''
class Box { int v = 0; }
extension E on Box { set doubled(int x) { v = x * 2; } }
int run() { var b = Box(); b.doubled = 21; return b.v; }
''', 'run'),
        equals(42),
      );
    });

    test('an extension getter/setter pair round-trips a value', () async {
      expect(
        await _runFunction(r'''
class Box { int v = 0; }
extension E on Box {
  int get half => v ~/ 2;
  set half(int x) { v = x * 2; }
}
int run() { var b = Box(); b.half = 10; return b.half + b.v; }
''', 'run'),
        // half = 10 -> v = 20; then half == 10, v == 20.
        equals(30),
      );
    });
  });

  group('setter semantics', () {
    test('a setter-only property cannot be read', () async {
      await expectLater(
        () => _runStatic(
          r'''
class B {
  int v = 0;
  set value(int x) { v = x; }
  static int run() { var b = B(); b.value = 5; return b.value; }
}
''',
          'B',
          'run',
        ),
        throwsA(isA<ApolloVMRuntimeError>()),
      );
    });

    test('a subclass override wins over the inherited setter', () async {
      expect(
        await _runStatic(
          r'''
class A { int v = 0; set value(int x) { v = x * 4; } }
class B extends A {
  set value(int x) { v = x + 100; }
  static int run() { var b = B(); b.value = 3; return b.v; }
}
''',
          'B',
          'run',
        ),
        equals(103),
      );
    });

    test(
      'unqualified compound assignment goes through the accessors',
      () async {
        // `value += n` with no receiver: reads via the getter, writes via the
        // setter — the unqualified mirror of `this.value += n`.
        expect(
          await _runStatic(
            r'''
class B {
  int _v = 0;
  int get value => _v;
  set value(int x) { _v = x + 1; }

  int bump() { value += 5; return this.value; }

  static int run() { var b = B(); b._v = 10; return b.bump(); }
}
''',
            'B',
            'run',
          ),
          // getter -> 10, +5 = 15, setter -> 16.
          equals(16),
        );
      },
    );

    test('unqualified `??=` short-circuits on a non-null value', () async {
      expect(
        await _runStatic(
          r'''
class B {
  int _v = 0;
  int get value => _v;
  set value(int x) { _v = x + 1; }

  int bump() { value ??= 9; return this.value; }

  static int run() { var b = B(); b._v = 4; return b.bump(); }
}
''',
          'B',
          'run',
        ),
        // 4 is not null, so the setter never runs.
        equals(4),
      );
    });

    test('the parameter shadows the property it sets', () async {
      // `value` inside the body is the parameter, not a recursive setter call.
      expect(
        await _runStatic(
          r'''
class B {
  int v = 0;
  set value(int value) { v = value * 2; }
  static int run() { var b = B(); b.value = 6; return b.v; }
}
''',
          'B',
          'run',
        ),
        equals(12),
      );
    });
  });

  group('ASTSetterDeclaration', () {
    /// The parsed `value` setter of [_classWithSetter].
    Future<ASTSetterDeclaration> loadSetter() async {
      var vm = await _load(_classWithSetter);
      var clazz = vm.getNamespace('dart', '')!.getClass('B')!;
      var setter = clazz.getSetterWithName('value');
      expect(setter, isNotNull, reason: 'setter not registered on the class');
      return setter!;
    }

    test('is registered by name on its class', () async {
      var vm = await _load(_classWithSetter);
      var clazz = vm.getNamespace('dart', '')!.getClass('B')!;

      expect(clazz.setterNames, equals(['value']));
      expect(clazz.setter, hasLength(1));

      // Lookup is exact by default and can be made case-insensitive, matching
      // the getter registry.
      expect(clazz.getSetterWithName('VALUE'), isNull);
      expect(
        clazz.getSetterWithName('VALUE', caseInsensitive: true),
        isNotNull,
      );
    });

    test('carries its parameter and renders it', () async {
      var setter = await loadSetter();

      expect(setter.name, equals('value'));
      expect(setter.parameterName, equals('x'));
      expect(setter.parameterType.name, equals('int'));
      expect('$setter', contains('set value(int x)'));
    });

    test('refuses to run as a plain block', () async {
      var setter = await loadSetter();

      // A setter needs its parameter bound, so the generic block entry point is
      // a guard: it must be invoked through `call(context, value)`.
      expect(
        () => setter.run(VMScopeContext(setter), ASTRunStatus()),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  group('accessor generation', () {
    // Only Dart emits setters; every other target must refuse rather than drop
    // the accessor and leave method bodies referencing a property that is gone.
    const refusingTargets = [
      'java11',
      'csharp',
      'javascript',
      'typescript',
      'kotlin',
      'python',
      'go',
      'lua',
    ];

    test('Dart emits a setter', () async {
      var vm = await _load(_classWithSetter);
      var storage = vm.generateAllCodeIn('dart');
      var src = (await storage.writeAllSources()).toString();
      expect(src, contains('set value(int x)'));
    });

    for (var target in refusingTargets) {
      test('$target refuses a setter', () async {
        var vm = await _load(_classWithSetter);
        expect(
          () => vm.generateAllCodeIn(target),
          throwsA(isA<UnsupportedSyntaxError>()),
        );
      });
    }

    // Regression: Python, Go and Lua never iterated the class's accessors, so a
    // getter was silently dropped while the bodies kept referencing it.
    for (var target in ['python', 'go', 'lua']) {
      test('$target refuses a getter instead of dropping it', () async {
        var vm = await _load(_classWithGetterOnly);
        expect(
          () => vm.generateAllCodeIn(target),
          throwsA(isA<UnsupportedSyntaxError>()),
        );
      });
    }

    test('Kotlin still emits getters', () async {
      var vm = await _load(_classWithGetterOnly);
      var storage = vm.generateAllCodeIn('kotlin');
      var src = (await storage.writeAllSources()).toString();
      expect(src, contains('val value'));
    });
  });
}
