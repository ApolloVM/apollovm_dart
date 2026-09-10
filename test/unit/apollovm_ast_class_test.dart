@TestOn('vm')
library;

import 'package:apollovm/apollovm.dart';
// `ApolloVMCore` (the core class registry) is not re-exported.
import 'package:apollovm/src/core/apollovm_core_base.dart';
import 'package:test/test.dart';

/// The class-level AST contracts: what a *primitive* class refuses to do, how a
/// normal class reports its fields, and how constructors are looked up.
///
/// Node-level, because these are surfaces a grammar never reaches: a primitive
/// has no source form of its own, and ApolloVM parses at most one (unnamed)
/// constructor per class, so the named/overloaded lookups can only be built by
/// hand.

/// Normalizes a [FutureOr] so `await` is always valid.
Future<T> _await<T>(FutureOr<T> v) async => await v;

VMScopeContext _scope() => VMScopeContext(ASTBlock(null));

ASTExpression _lit(Object v) => ASTExpressionLiteral(ASTValue.fromValue(v));

void main() {
  group('ASTClassPrimitive: a primitive is a value, not an object', () {
    // The VM's own `int` class. Built here rather than constructed fresh: an
    // `ASTType` singleton may only ever be bound to one class, so a second
    // `ASTClassPrimitive(ASTTypeInt.instance)` would throw — and this is the
    // instance the interpreter actually uses.
    final primitive = ApolloVMCore.getClass<int>('int')! as ASTClassPrimitive;

    test('declares no constructors and no fields', () {
      expect(primitive.constructors, isEmpty);
      expect(primitive.constructorsNames, isEmpty);
      expect(primitive.fields, isEmpty);
      expect(primitive.fieldsNames, isEmpty);
      expect(primitive.getField('anything'), isNull);
      expect(
        primitive.getConstructor('', null, _scope()),
        isNull,
        reason: 'a primitive has no implicit default constructor either',
      );
    });

    test('its fields map is empty', () async {
      expect(await _await(primitive.getFieldsMap()), isEmpty);
      expect(
        await _await(
          primitive.getFieldsMap(
            context: _scope(),
            fieldOverwrite: {'x': ASTValueInt(1)},
          ),
        ),
        isEmpty,
        reason: 'there is no field for an overwrite to land on',
      );
    });

    test('creating an instance yields the type default', () async {
      var clazz = primitive;
      var context = VMClassContext(clazz, parent: _scope());

      var instance = await _await(
        clazz.createInstance(context, ASTRunStatus()),
      );
      expect(await _await(instance!.getValue(context)), equals(0));
    });

    test('every instance mutation is a no-op', () async {
      var clazz = primitive;
      var context = VMClassContext(clazz, parent: _scope());
      var status = ASTRunStatus();
      var instance = ASTValueInt(7);

      // Nothing to initialize, nothing to set, nothing to read back.
      await _await(clazz.initializeInstance(context, status, instance));
      await _await(
        clazz.setInstanceByValue(context, status, instance, ASTValueInt(9)),
      );
      await _await(
        clazz.setInstanceByMap(context, status, instance, {
          'x': ASTValueInt(1),
        }),
      );

      expect(
        await _await(
          clazz.setInstanceFieldValue(
            context,
            status,
            instance,
            'x',
            ASTValueInt(1),
          ),
        ),
        isNull,
      );
      expect(
        await _await(
          clazz.getInstanceFieldValue(context, status, instance, 'x'),
        ),
        isNull,
      );
      expect(
        await _await(
          clazz.removeInstanceFieldValue(context, status, instance, 'x'),
        ),
        isNull,
      );

      expect(instance.value, equals(7), reason: 'the value never changed');
    });

    test('resolving and describing it does not need a body', () {
      var clazz = primitive;

      clazz.set(ASTBlock(null)); // ignored: a primitive has no block to take
      clazz.addFunction(
        ASTFunctionDeclaration(
          'ignored',
          ASTFunctionParametersDeclaration(null, null, null),
          ASTTypeVoid.instance,
        ),
      );
      clazz.resolveNode(null);

      expect(clazz.name, equals('int'));
      expect(clazz.toString(), equals('ASTClass[int]@int'));
      expect(clazz.getNodeIdentifier('nothing'), isNull);
    });

    test('so is the core `String` class', () {
      var core = ApolloVMCore.getClass<String>('String')!;
      expect(core, isA<ASTClassPrimitive>());
      expect(core.fields, isEmpty);
      expect(core.getField('length'), isNull, reason: 'a getter, not a field');
    });
  });

  group('ASTClassNormal.getFieldsMap', () {
    ASTClassNormal buildClass() {
      var clazz = ASTClassNormal('P', ASTType<VMObject>('P'), null);
      clazz.addField(ASTClassField(ASTTypeInt.instance, 'bare', false));
      clazz.addField(
        ASTClassFieldWithInitialValue(
          ASTTypeInt.instance,
          'counted',
          _lit(7),
          false,
        ),
      );
      return clazz;
    }

    test('a field with an initializer reports its value', () async {
      var map = await _await(buildClass().getFieldsMap(context: _scope()));
      expect(map['counted'], equals(7));
    });

    test('a field without one reports its declared type', () async {
      var map = await _await(buildClass().getFieldsMap(context: _scope()));
      expect(map['bare'], isA<ASTTypeInt>());
    });

    test('an overwrite wins over the declared initial value', () async {
      var map = await _await(
        buildClass().getFieldsMap(
          context: _scope(),
          fieldOverwrite: {'counted': ASTValueInt(42)},
        ),
      );
      expect(map['counted'], equals(42));
    });

    test('it works without a context', () async {
      var map = await _await(buildClass().getFieldsMap());
      expect(map.keys, containsAll(['bare', 'counted']));
    });
  });

  group('ASTClassNormal constructor lookup', () {
    ASTClassConstructorDeclaration ctor(
      String name, [
      ASTConstructorParametersDeclaration? parameters,
    ]) => ASTClassConstructorDeclaration(
      ASTType<VMObject>('P'),
      name,
      parameters ?? ASTConstructorParametersDeclaration(null, null, null),
    );

    test('a class with no constructor gets an implicit default one', () {
      var clazz = ASTClassNormal('P', ASTType<VMObject>('P'), null);

      var implicit = clazz.getConstructor('', null, _scope());
      expect(implicit, isNotNull);
      expect(implicit!.name, isEmpty);
      expect(
        identical(implicit, clazz.getConstructor('', null, _scope())),
        isTrue,
        reason: 'synthesized once, then reused',
      );

      // Only the unnamed constructor is synthesized.
      expect(clazz.getConstructor('named', null, _scope()), isNull);
    });

    test('a declared constructor suppresses the implicit one', () {
      var clazz = ASTClassNormal('P', ASTType<VMObject>('P'), null);
      clazz.addConstructor(ctor('named'));

      expect(clazz.constructorsNames, equals(['named']));
      expect(clazz.getConstructor('', null, _scope()), isNull);
    });

    test('lookup by name, optionally ignoring case', () {
      var clazz = ASTClassNormal('P', ASTType<VMObject>('P'), null);
      clazz.addConstructor(ctor('fromJson'));

      expect(clazz.containsConstructorWithName('fromJson'), isTrue);
      expect(clazz.containsConstructorWithName('FROMJSON'), isFalse);
      expect(
        clazz.containsConstructorWithName('FROMJSON', caseInsensitive: true),
        isTrue,
      );
      expect(
        clazz.getConstructorWithName('fromjson', caseInsensitive: true),
        isNotNull,
      );
      expect(clazz.getConstructorWithName('missing'), isNull);
    });

    test('two constructors under one name are kept as a set', () {
      var clazz = ASTClassNormal('P', ASTType<VMObject>('P'), null);

      var noArgs = ctor('of');
      var oneArg = ctor(
        'of',
        ASTConstructorParametersDeclaration(
          [
            ASTConstructorParameterDeclaration(
              ASTTypeInt.instance,
              'n',
              0,
              false,
            ),
          ],
          null,
          null,
        ),
      );
      clazz.addAllConstructors([noArgs, oneArg]);

      // One name, both declarations.
      expect(clazz.constructorsNames, equals(['of']));

      var context = _scope();
      expect(
        identical(
          clazz.getConstructor(
            'of',
            ASTFunctionSignature.from([1], null),
            context,
          ),
          oneArg,
        ),
        isTrue,
      );
      expect(
        identical(
          clazz.getConstructor(
            'of',
            ASTFunctionSignature.from(null, null),
            context,
          ),
          noArgs,
        ),
        isTrue,
      );
      // With no signature at all, the first declaration answers.
      expect(clazz.getConstructor('of', null, context), isNotNull);
    });
  });
}
