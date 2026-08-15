@Tags(['dart'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:apollovm/apollovm_serialization.dart';
import 'package:test/test.dart';

/// Integer literals large enough to leave a 32-bit range.
///
/// These run on the web too, where an `int` is a JavaScript double: LEB128
/// decoding accumulates 7-bit groups, and a 32-bit accumulator silently drops
/// the high bits of anything past 2^32. A literal like a file size, a
/// millisecond timestamp or an id is exactly the sort of value that lands
/// there, so the round trip is checked at those magnitudes rather than only on
/// the small numbers a hand-written test tends to use.
void main() {
  group('large integer literals survive a binary AST round trip', () {
    Future<List<Object?>> runSource(String source) async {
      var vm = ApolloVM();
      var codeUnit = SourceCodeUnit('dart', source, id: 'big.dart');
      expect(await vm.loadCodeUnit(codeUnit), isTrue);

      var image = vm.saveCodeUnitAST(codeUnit);

      var vm2 = ApolloVM();
      expect(await vm2.loadCodeUnitAST(image), isTrue);

      var runner = vm2.createRunner('dart')!;
      var output = <Object?>[];
      runner.externalPrintFunction = output.add;

      await runner.executeClassMethod(
        '',
        'Big',
        'main',
        positionalParameters: [<String>[]],
      );

      return output;
    }

    test('positive literals from 2^28 upwards', () async {
      var output = await runSource(r'''
class Big {
  static void main(List<String> args) {
    print(268435456);
    print(4294967295);
    print(4294967296);
    print(1099511627776);
    print(1000000000000000);
  }
}
''');

      expect(
        output,
        equals([
          268435456, // 2^28
          4294967295, // 2^32 - 1
          4294967296, // 2^32
          1099511627776, // 2^40
          1000000000000000, // 10^15
        ]),
      );
    });

    test('negative literals from 2^28 downwards', () async {
      var output = await runSource(r'''
class Big {
  static void main(List<String> args) {
    print(-268435456);
    print(-4294967296);
    print(-1099511627776);
    print(-1000000000000000);
  }
}
''');

      expect(
        output,
        equals([-268435456, -4294967296, -1099511627776, -1000000000000000]),
      );
    });

    test('a large literal regenerates as itself', () async {
      var vm = ApolloVM();
      var codeUnit = SourceCodeUnit(
        'dart',
        'class Big {\n  int v = 1099511627776;\n}\n',
        id: 'big.dart',
      );
      expect(await vm.loadCodeUnit(codeUnit), isTrue);

      var expected = (await vm.generateAllCodeIn('dart').writeAllSources())
          .toString();

      var vm2 = ApolloVM();
      await vm2.loadCodeUnitAST(vm.saveCodeUnitAST(codeUnit));

      var actual = (await vm2.generateAllCodeIn('dart').writeAllSources())
          .toString();

      expect(actual, equals(expected));
      expect(actual, contains('1099511627776'));
    });
  });
}
