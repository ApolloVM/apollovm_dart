@TestOn('vm')
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

void main() {
  group('DependencyGraph', () {
    test('topological order places dependencies before dependents', () {
      var g = DependencyGraph();
      g.addEdge('main', 'user');
      g.addEdge('main', 'helpers');
      g.addEdge('user', 'base');

      var order = g.topologicalOrder();
      expect(order.toSet(), {'main', 'user', 'helpers', 'base'});
      expect(order.indexOf('base'), lessThan(order.indexOf('user')));
      expect(order.indexOf('user'), lessThan(order.indexOf('main')));
      expect(order.indexOf('helpers'), lessThan(order.indexOf('main')));
    });

    test('detects a self-loop', () {
      var g = DependencyGraph();
      g.addEdge('a', 'a');
      var cycles = g.findCycles();
      expect(cycles, hasLength(1));
      expect(cycles.first, contains('a'));
      expect(g.hasCycles, isTrue);
    });

    test('detects a 2-cycle', () {
      var g = DependencyGraph();
      g.addEdge('a', 'b');
      g.addEdge('b', 'a');
      var cycles = g.findCycles();
      expect(cycles, hasLength(1));
      expect(cycles.first.toSet(), {'a', 'b'});
    });

    test('detects a 3-node SCC and leaves acyclic nodes out', () {
      var g = DependencyGraph();
      g.addEdge('a', 'b');
      g.addEdge('b', 'c');
      g.addEdge('c', 'a');
      g.addEdge('d', 'a'); // d is acyclic
      var cycles = g.findCycles();
      expect(cycles, hasLength(1));
      expect(cycles.first.toSet(), {'a', 'b', 'c'});
    });

    test('no cycles for a DAG', () {
      var g = DependencyGraph();
      g.addEdge('a', 'b');
      g.addEdge('a', 'c');
      g.addEdge('b', 'c');
      expect(g.findCycles(), isEmpty);
      expect(g.hasCycles, isFalse);
    });

    test('affectedBy returns transitive dependents (reverse reachability)', () {
      var g = DependencyGraph();
      g.addEdge('main', 'user'); // main imports user
      g.addEdge('user', 'base'); // user imports base
      g.addEdge('other', 'base'); // other imports base

      // Changing `base` affects base + user + main + other.
      expect(g.affectedBy('base'), {'base', 'user', 'main', 'other'});
      // Changing `user` affects user + main only.
      expect(g.affectedBy('user'), {'user', 'main'});
    });
  });
}
