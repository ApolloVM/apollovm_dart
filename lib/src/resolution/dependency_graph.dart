// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

/// A directed graph of module dependencies: an edge `from → to` means module
/// `from` imports module `to`.
///
/// Supports cycle detection (Tarjan SCC), topological ordering (Kahn), and
/// reverse-reachability for incremental invalidation.
class DependencyGraph {
  /// moduleId → set of imported moduleIds.
  final Map<String, Set<String>> _edges = <String, Set<String>>{};

  /// Ensures [moduleId] is a node in the graph.
  void addModule(String moduleId) {
    _edges.putIfAbsent(moduleId, () => <String>{});
  }

  /// Adds an import edge [from] → [to] (both nodes are created if missing).
  void addEdge(String from, String to) {
    addModule(from);
    addModule(to);
    _edges[from]!.add(to);
  }

  /// Removes a node and all edges touching it (incremental update).
  void removeModule(String moduleId) {
    _edges.remove(moduleId);
    for (var deps in _edges.values) {
      deps.remove(moduleId);
    }
  }

  /// Clears all edges out of [moduleId] (keeps the node), so its imports can be
  /// re-added after a re-parse.
  void clearEdges(String moduleId) {
    _edges[moduleId]?.clear();
  }

  bool contains(String moduleId) => _edges.containsKey(moduleId);

  List<String> get modules => _edges.keys.toList();

  /// Direct imports of [moduleId].
  Set<String> dependenciesOf(String moduleId) =>
      _edges[moduleId] ?? const <String>{};

  /// Direct importers of [moduleId] (reverse edges).
  Set<String> dependentsOf(String moduleId) {
    var result = <String>{};
    for (var entry in _edges.entries) {
      if (entry.value.contains(moduleId)) result.add(entry.key);
    }
    return result;
  }

  /// All modules transitively affected by a change to [moduleId] (itself plus
  /// every module that transitively imports it). Used to invalidate only the
  /// affected subgraph on incremental re-resolution.
  Set<String> affectedBy(String moduleId) {
    var affected = <String>{};
    var queue = <String>[moduleId];
    while (queue.isNotEmpty) {
      var m = queue.removeLast();
      if (!affected.add(m)) continue;
      queue.addAll(dependentsOf(m));
    }
    return affected;
  }

  /// Strongly-connected components with more than one node, or single nodes
  /// with a self-edge — i.e. the import cycles. Iterative Tarjan (no recursion,
  /// safe for large graphs).
  List<List<String>> findCycles() {
    var index = <String, int>{};
    var lowlink = <String, int>{};
    var onStack = <String>{};
    var stack = <String>[];
    var counter = 0;
    var sccs = <List<String>>[];

    for (var start in _edges.keys) {
      if (index.containsKey(start)) continue;

      // Iterative DFS frame: (node, iterator over its neighbors).
      var work = <List<Object>>[];
      work.add([start, dependenciesOf(start).toList()]);
      index[start] = counter;
      lowlink[start] = counter;
      counter++;
      stack.add(start);
      onStack.add(start);

      while (work.isNotEmpty) {
        var frame = work.last;
        var node = frame[0] as String;
        var neighbors = frame[1] as List<String>;

        if (neighbors.isNotEmpty) {
          var w = neighbors.removeLast();
          if (!index.containsKey(w)) {
            index[w] = counter;
            lowlink[w] = counter;
            counter++;
            stack.add(w);
            onStack.add(w);
            work.add([w, dependenciesOf(w).toList()]);
          } else if (onStack.contains(w)) {
            lowlink[node] = _min(lowlink[node]!, index[w]!);
          }
        } else {
          // Done with node: if it's an SCC root, pop the component.
          if (lowlink[node] == index[node]) {
            var component = <String>[];
            while (true) {
              var w = stack.removeLast();
              onStack.remove(w);
              component.add(w);
              if (w == node) break;
            }
            var isCycle =
                component.length > 1 || dependenciesOf(node).contains(node);
            if (isCycle) sccs.add(component);
          }
          work.removeLast();
          if (work.isNotEmpty) {
            var parent = work.last[0] as String;
            lowlink[parent] = _min(lowlink[parent]!, lowlink[node]!);
          }
        }
      }
    }

    return sccs;
  }

  bool get hasCycles => findCycles().isNotEmpty;

  /// A leaves-first topological order (dependencies before dependents) over the
  /// acyclic part of the graph, using Kahn's algorithm. Nodes participating in
  /// cycles are appended at the end (deterministic by insertion order) so the
  /// result always contains every module.
  List<String> topologicalOrder() {
    // Out-degree over a copy of the edges (dependencies must come first).
    var remaining = <String, Set<String>>{
      for (var e in _edges.entries) e.key: Set<String>.from(e.value),
    };

    var order = <String>[];
    var changed = true;
    while (changed) {
      changed = false;
      for (var m in _edges.keys) {
        if (order.contains(m)) continue;
        var deps = remaining[m]!;
        // Ready when all deps are already emitted (or are missing nodes).
        if (deps.every((d) => order.contains(d) || !_edges.containsKey(d))) {
          order.add(m);
          changed = true;
        }
      }
    }

    // Append any nodes stuck in cycles (deterministic).
    for (var m in _edges.keys) {
      if (!order.contains(m)) order.add(m);
    }

    return order;
  }

  int _min(int a, int b) => a < b ? a : b;

  @override
  String toString() {
    var edges = _edges.entries
        .map((e) => '${e.key} -> {${e.value.join(', ')}}')
        .join('; ');
    return 'DependencyGraph{$edges}';
  }
}
