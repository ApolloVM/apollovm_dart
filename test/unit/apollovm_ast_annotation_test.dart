@TestOn('vm')
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

void main() {
  group('ASTAnnotationParameter', () {
    test('stores name/value and defaults defaultParameter to false', () {
      var p = ASTAnnotationParameter('path', '/api');
      expect(p.name, equals('path'));
      expect(p.value, equals('/api'));
      expect(p.defaultParameter, isFalse);
      expect(p.children, isEmpty);
    });

    test('defaultParameter flag can be set', () {
      var p = ASTAnnotationParameter('value', 'x', true);
      expect(p.defaultParameter, isTrue);
    });

    test('resolveNode wires up parentNode', () {
      var block = ASTBlock(null);
      var p = ASTAnnotationParameter('a', '1');
      p.resolveNode(block);
      expect(p.parentNode, same(block));
    });

    test('getNodeIdentifier delegates to parent', () {
      var p = ASTAnnotationParameter('a', '1');
      // No parent -> no identifier resolved, and does not throw.
      p.resolveNode(null);
      expect(p.getNodeIdentifier('missing'), isNull);
    });
  });

  group('ASTAnnotation', () {
    test('no-parameter annotation has empty children', () {
      var a = ASTAnnotation('Override');
      expect(a.name, equals('Override'));
      expect(a.parameters, isNull);
      expect(a.children, isEmpty);
    });

    test('children expose parameter values', () {
      var p1 = ASTAnnotationParameter('path', '/api');
      var p2 = ASTAnnotationParameter('method', 'GET');
      var a = ASTAnnotation('Route', {'path': p1, 'method': p2});
      expect(a.children, containsAll([p1, p2]));
      expect(a.children.length, equals(2));
    });

    test('resolveNode wires parentNode and does not throw', () {
      var block = ASTBlock(null);
      var a = ASTAnnotation('Route', {
        'path': ASTAnnotationParameter('path', '/api'),
      });
      a.resolveNode(block);
      expect(a.parentNode, same(block));
    });

    test('getNodeIdentifier returns null with no parent', () {
      var a = ASTAnnotation('Route');
      a.resolveNode(null);
      expect(a.getNodeIdentifier('x'), isNull);
    });
  });
}
