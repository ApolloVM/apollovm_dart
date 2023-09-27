import 'dart:async';
import 'dart:typed_data';

/// Base class for a code unit storage.
///
/// The implementation can be a local file system, a memory storage or a remote repository.
abstract class ApolloCodeUnitStorage<T extends Object> {
  FutureOr<List<String>> getNamespaces();

  /// Returns a list of code units IDs of a namespace.
  FutureOr<List<String>> getNamespaceCodeUnitsIDs(String namespace);

  /// Returns the source code of a [codeUnitID] in [namespace].
  FutureOr<T?> getNamespaceCodeUnit(String namespace, String codeUnitID);

  /// Adds a source code to this storage.
  FutureOr<void> add(String namespace, String codeUnitID, T codeUnitData);

  /// Returns all the entries in this storage.
  FutureOr<Map<String, Map<String, T>>> allEntries();
}

/// Base class for a binary code storage.
///
/// The implementation can be a local file system, a memory storage or a remote repository.
abstract class ApolloBinaryCodeStorage
    extends ApolloCodeUnitStorage<Uint8List> {}

/// In memory source code storage implementation.
class ApolloBinaryCodeStorageMemory extends ApolloBinaryCodeStorage {
  final Map<String, Map<String, Uint8List>> _namespaces = {};

  @override
  List<String> getNamespaces() => _namespaces.keys.toList();

  @override
  List<String> getNamespaceCodeUnitsIDs(String namespace) {
    var ns = _namespaces[namespace];
    return ns?.keys.toList() ?? [];
  }

  @override
  Uint8List? getNamespaceCodeUnit(String namespace, String codeUnitID) {
    var ns = _namespaces[namespace];
    return ns?[codeUnitID];
  }

  @override
  void add(String namespace, String codeUnitID, Uint8List codeUnitData) {
    var ns = _namespaces.putIfAbsent(namespace, () => <String, Uint8List>{});
    ns[codeUnitID] = codeUnitData;
  }

  @override
  Map<String, Map<String, Uint8List>> allEntries() {
    return _namespaces.map((k, v) => MapEntry(k, Map.from(v)));
  }
}

/// Base class for a source code storage.
///
/// The implementation can be a local file system, a memory storage or a remote repository.
abstract class ApolloSourceCodeStorage extends ApolloCodeUnitStorage<String> {
  /// Write all code unit sources.
  Future<StringBuffer> writeAllSources(
      {String commentPrefix = '<<<<',
      String commentSuffix = '>>>>',
      String nsSeparator = '/'}) async {
    var s = StringBuffer();

    s.write(commentPrefix);
    s.write(' [SOURCES_BEGIN] ');
    s.write(commentSuffix);
    s.write('\n');

    for (var ns in await getNamespaces()) {
      s.write(commentPrefix);
      s.write(' NAMESPACE="$ns" ');
      s.write(commentSuffix);
      s.write('\n');

      for (var cu in await getNamespaceCodeUnitsIDs(ns)) {
        var fullCU = '$nsSeparator$cu';

        s.write(commentPrefix);
        s.write(' CODE_UNIT_START="$fullCU" ');
        s.write(commentSuffix);
        s.write('\n');

        var source = await getNamespaceCodeUnit(ns, cu);
        s.write(source);

        s.write(commentPrefix);
        s.write(' CODE_UNIT_END="$fullCU" ');
        s.write(commentSuffix);
        s.write('\n');
      }
    }

    s.write(commentPrefix);
    s.write(' [SOURCES_END] ');
    s.write(commentSuffix);
    s.write('\n');

    return s;
  }
}

/// In memory source code storage implementation.
class ApolloSourceCodeStorageMemory extends ApolloSourceCodeStorage {
  final Map<String, Map<String, String>> _namespaces = {};

  @override
  List<String> getNamespaces() => _namespaces.keys.toList();

  @override
  List<String> getNamespaceCodeUnitsIDs(String namespace) {
    var ns = _namespaces[namespace];
    return ns?.keys.toList() ?? [];
  }

  @override
  String? getNamespaceCodeUnit(String namespace, String codeUnitID) {
    var ns = _namespaces[namespace];
    return ns?[codeUnitID];
  }

  @override
  void add(String namespace, String codeUnitID, String codeUnitData) {
    var ns = _namespaces.putIfAbsent(namespace, () => <String, String>{});
    ns[codeUnitID] = codeUnitData;
  }

  @override
  Map<String, Map<String, String>> allEntries() {
    return _namespaces.map((k, v) => MapEntry(k, Map.from(v)));
  }
}

/// In memory source code storage implementation.
class ApolloGenericCodeStorageMemory<T extends Object>
    extends ApolloCodeUnitStorage<T> {
  final Map<String, Map<String, T>> _namespaces = {};

  @override
  List<String> getNamespaces() => _namespaces.keys.toList();

  @override
  List<String> getNamespaceCodeUnitsIDs(String namespace) {
    var ns = _namespaces[namespace];
    return ns?.keys.toList() ?? [];
  }

  @override
  T? getNamespaceCodeUnit(String namespace, String codeUnitID) {
    var ns = _namespaces[namespace];
    return ns?[codeUnitID];
  }

  @override
  void add(String namespace, String codeUnitID, T codeUnitData) {
    var ns = _namespaces.putIfAbsent(namespace, () => <String, T>{});
    ns[codeUnitID] = codeUnitData;
  }

  @override
  Map<String, Map<String, T>> allEntries() {
    return _namespaces.map((k, v) => MapEntry(k, Map.from(v)));
  }
}
