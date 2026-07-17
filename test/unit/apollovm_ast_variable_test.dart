@TestOn('vm')
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Normalizes a [FutureOr] into a [Future] so `await` is always valid.
Future<T> _await<T>(FutureOr<T> v) async => await v;

VMContext _ctx() => VMScopeContext(ASTBlock(null));

void main() {
  group('ASTRuntimeVariable', () {
    test('getValue / setValue round-trips a value', () {
      var v = ASTRuntimeVariable(ASTTypeInt.instance, 'x', ASTValueInt(3));
      var ctx = _ctx();
      expect(v.getValue(ctx).getValueNoContext(), equals(3));
      v.setValue(ctx, ASTValueInt(9));
      expect(v.getValue(ctx).getValueNoContext(), equals(9));
    });

    test('defaults to a null value', () {
      var v = ASTRuntimeVariable(ASTTypeInt.instance, 'x');
      expect(v.getValue(_ctx()), same(ASTValueNull.instance));
    });

    test('resolveType returns the declared type', () {
      var v = ASTRuntimeVariable(ASTTypeInt.instance, 'x', ASTValueInt(1));
      expect(v.resolveType(_ctx()), isA<ASTTypeInt>());
    });

    test('resolveType of a `var` follows the runtime value type', () {
      var v = ASTRuntimeVariable(ASTTypeVar.instance, 'x', ASTValueString('s'));
      expect(v.resolveType(_ctx()), isA<ASTTypeString>());
    });

    test('resolveVariable returns itself and exposes its value as a child', () {
      var value = ASTValueInt(7);
      var v = ASTRuntimeVariable(ASTTypeInt.instance, 'x', value);
      expect(v.resolveVariable(_ctx()), same(v));
      expect(v.children, contains(value));
    });

    test('toString', () {
      var v = ASTRuntimeVariable(ASTTypeInt.instance, 'x', ASTValueInt(1));
      expect(v.toString(), contains('ASTRuntimeVariable'));
    });
  });

  group('ASTClassField', () {
    test('resolveVariable throws when the field is absent from context', () {
      var f = ASTClassField(ASTTypeInt.instance, 'missing', false);
      expect(() => f.resolveVariable(_ctx()), throwsA(isA<StateError>()));
    });

    test('has no AST children', () {
      var f = ASTClassField(ASTTypeInt.instance, 'x', false);
      expect(f.children, isEmpty);
    });

    test('toString includes type and name', () {
      var f = ASTClassField(ASTTypeInt.instance, 'count', false);
      expect(f.toString(), contains('count'));
    });
  });

  group('ASTClassFieldWithInitialValue', () {
    ASTClassFieldWithInitialValue<int> field() =>
        ASTClassFieldWithInitialValue<int>(
          ASTTypeInt.instance,
          'x',
          ASTExpressionLiteral(ASTValueInt(5)),
          false,
        );

    test('initialValue exposes the initializer expression', () {
      expect(field().initialValue, isA<ASTExpressionLiteral>());
    });

    test('getInitialValueNoContext evaluates the initializer', () async {
      var v = await _await(field().getInitialValueNoContext());
      expect(v.getValueNoContext(), equals(5));
    });

    test('getInitialValue evaluates against a context', () async {
      var v = await _await(field().getInitialValue(_ctx(), ASTRunStatus()));
      expect(v.getValueNoContext(), equals(5));
    });
  });

  group('ASTThisVariable', () {
    test('name is "this"', () {
      expect(ASTThisVariable().name, equals('this'));
    });

    test('resolveVariable throws without an instance in scope', () {
      expect(
        () => ASTThisVariable().resolveVariable(_ctx()),
        throwsA(isA<ApolloVMRuntimeError>()),
      );
    });

    test('resolveType falls back to dynamic outside a class context', () async {
      var t = await _await(ASTThisVariable().resolveType(_ctx()));
      expect(t, isA<ASTTypeDynamic>());
    });

    test('resolveType follows an associated typed node', () async {
      var v = ASTThisVariable();
      v.associateToType(ASTValueInt(1));
      expect(await _await(v.resolveType(_ctx())), isA<ASTTypeInt>());
    });

    test('has no AST children', () {
      expect(ASTThisVariable().children, isEmpty);
    });
  });

  group('ASTScopeVariable', () {
    test('resolveVariable of "null" yields a null runtime variable', () async {
      var sv = ASTScopeVariable('null');
      var resolved = await _await(sv.resolveVariable(_ctx()));
      expect(resolved, isA<ASTRuntimeVariable>());
      expect(resolved.getValue(_ctx()), same(ASTValueNull.instance));
    });

    test('resolveType with no context/parent is dynamic', () async {
      var sv = ASTScopeVariable('x');
      expect(await _await(sv.resolveType(null)), isA<ASTTypeDynamic>());
    });

    test('resolveType follows an associated typed node', () async {
      var sv = ASTScopeVariable('x');
      sv.associateToType(ASTValueDouble(1.0));
      expect(await _await(sv.resolveType(null)), isA<ASTTypeDouble>());
    });

    test('has no AST children', () {
      expect(ASTScopeVariable('x').children, isEmpty);
    });
  });
}
