abstract class ApolloCodeStorage {
  List<String> getNamespaces();

  List<String>? getNamespaceCodeUnits(String namespace);

  String? getNamespaceCodeUnitSource(String namespace, String codeUnitID);

  StringBuffer writeAllSources(
      {String commentPrefix = '<<<<',
      String commentSuffix = '>>>>',
      String nsSeparator = '/'}) {
    var s = StringBuffer();

    s.write(commentPrefix);
    s.write(' [SOURCES BEGIN] ');
    s.write(commentSuffix);
    s.write('\n');

    for (var ns in getNamespaces()) {
      s.write(commentPrefix);
      s.write(' NAMESPACE="$ns" ');
      s.write(commentSuffix);
      s.write('\n');

      for (var cu in getNamespaceCodeUnits(ns)!) {
        var fullCU = '$nsSeparator$cu';

        s.write(commentPrefix);
        s.write(' CODE_UNIT_START="$fullCU" ');
        s.write(commentSuffix);
        s.write('\n');

        var source = getNamespaceCodeUnitSource(ns, cu);
        s.write(source);

        s.write(commentPrefix);
        s.write(' CODE_UNIT_END="$fullCU" ');
        s.write(commentSuffix);
        s.write('\n');
      }
    }

    s.write(commentPrefix);
    s.write(' [SOURCES END] ');
    s.write(commentSuffix);
    s.write('\n');

    return s;
  }

  void addSource(String namespace, String codeUnitID, String codeUnitSource);
}

class ApolloCodeStorageMemory extends ApolloCodeStorage {
  final Map<String, Map<String, String>> _namespaces = {};

  @override
  List<String> getNamespaces() => _namespaces.keys.toList();

  @override
  List<String>? getNamespaceCodeUnits(String namespace) {
    var ns = _namespaces[namespace];
    return ns != null ? ns.keys.toList() : null;
  }

  @override
  String? getNamespaceCodeUnitSource(String namespace, String codeUnitID) {
    var ns = _namespaces[namespace];
    return ns != null ? ns[codeUnitID] : null;
  }

  @override
  void addSource(String namespace, String codeUnitID, String codeUnitSource) {
    var ns = _namespaces.putIfAbsent(namespace, () => <String, String>{});
    ns[codeUnitID] = codeUnitSource;
  }
}