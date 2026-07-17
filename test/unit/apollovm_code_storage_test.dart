@TestOn('vm')
library;

import 'dart:typed_data';

// Not re-exported from the public library; imported directly (as other unit
// tests in this suite do for `src/` internals).
import 'package:apollovm/src/apollovm_code_storage.dart';
import 'package:test/test.dart';

void main() {
  group('ApolloBinaryCodeStorageMemory', () {
    test('add / read back / list namespaces and units', () {
      var s = ApolloBinaryCodeStorageMemory();
      expect(s.getNamespaces(), isEmpty);
      expect(s.getNamespaceCodeUnitsIDs('ns'), isEmpty);
      expect(s.getNamespaceCodeUnit('ns', 'a'), isNull);

      var data = Uint8List.fromList([1, 2, 3]);
      s.add('ns', 'a', data);

      expect(s.getNamespaces(), equals(['ns']));
      expect(s.getNamespaceCodeUnitsIDs('ns'), equals(['a']));
      expect(s.getNamespaceCodeUnit('ns', 'a'), equals(data));
    });

    test('allEntries returns a defensive copy', () {
      var s = ApolloBinaryCodeStorageMemory();
      s.add('ns', 'a', Uint8List.fromList([9]));
      var entries = s.allEntries();
      expect(entries['ns']!['a'], equals(Uint8List.fromList([9])));

      // Mutating the returned map must not affect the storage.
      entries['ns']!['b'] = Uint8List.fromList([0]);
      expect(s.getNamespaceCodeUnitsIDs('ns'), equals(['a']));
    });
  });

  group('ApolloSourceCodeStorageMemory', () {
    test('writeAllSources emits framed source for every unit', () async {
      var s = ApolloSourceCodeStorageMemory();
      s.add('pkg', 'main', 'void main() {}');

      var buf = await s.writeAllSources();
      var out = buf.toString();
      expect(out, contains('[SOURCES_BEGIN]'));
      expect(out, contains('NAMESPACE="pkg"'));
      expect(out, contains('CODE_UNIT_START="/main"'));
      expect(out, contains('void main() {}'));
      expect(out, contains('CODE_UNIT_END="/main"'));
      expect(out, contains('[SOURCES_END]'));
    });
  });

  group('ApolloGenericCodeStorageMemory', () {
    test('stores and retrieves typed payloads', () {
      var s = ApolloGenericCodeStorageMemory<int>();
      expect(s.getNamespaces(), isEmpty);
      expect(s.getNamespaceCodeUnitsIDs('n'), isEmpty);
      expect(s.getNamespaceCodeUnit('n', 'x'), isNull);

      s.add('n', 'x', 42);
      expect(s.getNamespaces(), equals(['n']));
      expect(s.getNamespaceCodeUnitsIDs('n'), equals(['x']));
      expect(s.getNamespaceCodeUnit('n', 'x'), equals(42));
      expect(s.allEntries()['n']!['x'], equals(42));
    });
  });
}
