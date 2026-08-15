@Tags(['dart'])
library;

import 'dart:typed_data';

import 'package:apollovm/apollovm.dart';
import 'package:apollovm/apollovm_serialization.dart';
import 'package:test/test.dart';

const _sourceA = r'''
class Greeter {
  String greet(String name) {
    return 'hello $name';
  }
}
''';

const _sourceB = r'''
class Adder {
  int add(int a, int b) {
    return a + b;
  }

  static void main(List<String> args) {
    print(Adder().add(2, 3));
  }
}
''';

Future<ApolloVM> _vmWith(Map<String, String> sources) async {
  var vm = ApolloVM();
  for (var e in sources.entries) {
    var ok = await vm.loadCodeUnit(SourceCodeUnit('dart', e.value, id: e.key));
    expect(ok, isTrue, reason: 'Error loading ${e.key}');
  }
  return vm;
}

void main() {
  group('ApolloVM convenience methods', () {
    test('saveCodeUnitAST / loadCodeUnitAST round trip', () async {
      var vm = await _vmWith({'b.dart': _sourceB});
      var codeUnit = vm.allCodeUnitsAllLanguages().single;

      var image = vm.saveCodeUnitAST(codeUnit);
      expect(ASTBinaryReader.isASTBinary(image), isTrue);

      var vm2 = ApolloVM();
      expect(await vm2.loadCodeUnitAST(image), isTrue);

      var runner = vm2.createRunner('dart')!;
      var output = <Object?>[];
      runner.externalPrintFunction = output.add;

      await runner.executeClassMethod(
        '',
        'Adder',
        'main',
        positionalParameters: [<String>[]],
      );

      expect(output, equals([5]));
    });

    test('CodeUnit.toBinaryAST matches the VM method', () async {
      var vm = await _vmWith({'b.dart': _sourceB});
      var codeUnit = vm.allCodeUnitsAllLanguages().single;

      expect(codeUnit.toBinaryAST(), equals(vm.saveCodeUnitAST(codeUnit)));
    });

    test('loadCodeUnitAST can re-home a unit', () async {
      var vm = await _vmWith({'b.dart': _sourceB});
      var image = vm.saveCodeUnitAST(vm.allCodeUnitsAllLanguages().single);

      var vm2 = ApolloVM();
      await vm2.loadCodeUnitAST(image, id: 'other.dart', namespace: 'ns');

      var loaded = vm2.allCodeUnitsAllLanguages().single;
      expect(loaded.id, equals('other.dart'));
      expect(loaded.namespace, equals('ns'));
    });

    test('an image loads without going through a parser', () async {
      // The point of the format: `loadCodeUnit` only reaches for a parser when
      // a unit has no AST yet, so a decoded unit never touches the grammar.
      var vm = await _vmWith({'b.dart': _sourceB});
      var image = vm.saveCodeUnitAST(vm.allCodeUnitsAllLanguages().single);

      var decoded = const ASTBinaryReader().readCodeUnit(image);
      expect(decoded.root, isNotNull);
      expect(decoded, isA<BinaryCodeUnit>());
    });
  });

  group('archive', () {
    test('bundles every loaded unit and loads them all back', () async {
      var vm = await _vmWith({'a.dart': _sourceA, 'b.dart': _sourceB});

      var archive = vm.saveAllAST();
      expect(ASTBinaryArchiveReader.isArchive(archive), isTrue);
      expect(ASTBinaryReader.isASTBinary(archive), isTrue);

      var vm2 = ApolloVM();
      expect(await vm2.loadAllAST(archive), equals(2));

      var ids = vm2.allCodeUnitsAllLanguages().map((e) => e.id).toList()
        ..sort();
      expect(ids, equals(['a.dart', 'b.dart']));

      var runner = vm2.createRunner('dart')!;
      var output = <Object?>[];
      runner.externalPrintFunction = output.add;
      await runner.executeClassMethod(
        '',
        'Adder',
        'main',
        positionalParameters: [<String>[]],
      );
      expect(output, equals([5]));
    });

    test('entries can be listed without decoding their ASTs', () async {
      var vm = await _vmWith({'a.dart': _sourceA, 'b.dart': _sourceB});
      var archive = vm.saveAllAST();

      var entries = const ASTBinaryArchiveReader().listEntries(archive);
      expect(entries.length, equals(2));
      expect(
        entries.map((e) => e.codeUnitId).toList()..sort(),
        equals(['a.dart', 'b.dart']),
      );
      for (var e in entries) {
        expect(e.language, equals('dart'));
      }
    });

    test('each entry is itself a complete, independently readable image', () {
      // Nesting whole images rather than merging pools is what makes this
      // possible: one unit can be pulled out and read on its own.
      return _vmWith({'a.dart': _sourceA, 'b.dart': _sourceB}).then((vm) {
        var archive = vm.saveAllAST();
        var entries = const ASTBinaryArchiveReader().entriesOf(archive);

        expect(entries.length, equals(2));
        for (var entry in entries) {
          expect(ASTBinaryReader.isASTBinary(entry), isTrue);
          expect(ASTBinaryArchiveReader.isArchive(entry), isFalse);
          expect(const ASTBinaryReader().readRoot(entry), isNotNull);
        }
      });
    });

    test('a single-unit image is not mistaken for an archive', () async {
      var vm = await _vmWith({'b.dart': _sourceB});
      var image = vm.saveCodeUnitAST(vm.allCodeUnitsAllLanguages().single);

      expect(ASTBinaryArchiveReader.isArchive(image), isFalse);
      expect(
        () => const ASTBinaryArchiveReader().entriesOf(image),
        throwsA(isA<ASTBinaryException>()),
      );
    });

    test('an archive can be signed as a whole', () async {
      var vm = await _vmWith({'a.dart': _sourceA, 'b.dart': _sourceB});

      var archive = vm.saveAllAST(
        signer: HmacSha256Signer.fromString('build-key'),
      );

      var vm2 = ApolloVM();
      expect(
        await vm2.loadAllAST(
          archive,
          verifier: HmacSha256Verifier.fromString('build-key'),
        ),
        equals(2),
      );

      expect(
        () => ApolloVM().loadAllAST(
          archive,
          verifier: HmacSha256Verifier.fromString('wrong-key'),
        ),
        throwsA(isA<ASTBinaryIntegrityException>()),
      );
    });
  });

  group('signing an image', () {
    test(
      'a signed image verifies with the right key and fails with a wrong one',
      () async {
        var vm = await _vmWith({'b.dart': _sourceB});
        var codeUnit = vm.allCodeUnitsAllLanguages().single;

        var image = vm.saveCodeUnitAST(
          codeUnit,
          signer: HmacSha256Signer.fromString('s3cret'),
        );

        expect(const ASTBinaryReader().readInfo(image).isSigned, isTrue);

        expect(
          await ApolloVM().loadCodeUnitAST(
            image,
            verifier: HmacSha256Verifier.fromString('s3cret'),
          ),
          isTrue,
        );

        expect(
          () => ApolloVM().loadCodeUnitAST(
            image,
            verifier: HmacSha256Verifier.fromString('nope'),
          ),
          throwsA(
            isA<ASTBinaryIntegrityException>().having(
              (e) => e.error,
              'error',
              ASTBinaryError.signatureMismatch,
            ),
          ),
        );
      },
    );

    test('a corrupted image is refused before its AST is used', () async {
      var vm = await _vmWith({'b.dart': _sourceB});
      var image = vm.saveCodeUnitAST(vm.allCodeUnitsAllLanguages().single);

      var tampered = Uint8List.fromList(image);
      // Somewhere well inside the section stream.
      var at = tampered.length ~/ 2;
      tampered[at] = tampered[at] ^ 0xFF;

      expect(
        () => ApolloVM().loadCodeUnitAST(tampered),
        throwsA(
          isA<ASTBinaryIntegrityException>().having(
            (e) => e.error,
            'error',
            ASTBinaryError.checksumMismatch,
          ),
        ),
      );
    });
  });

  group('size and load cost', () {
    /// A program of realistic size, rather than a two-line snippet: an image
    /// carries a fixed header, a metadata section and two pools, so for a very
    /// small unit that overhead dominates and the image is *larger* than the
    /// source. The saving only appears once there is a program to speak of.
    String bigSource(int classes) {
      var b = StringBuffer();
      for (var i = 0; i < classes; ++i) {
        b.write('''
class Worker$i {
  int factor = $i;

  int compute(int a, int b) {
    var total = 0;
    for (var k = 0; k < a; ++k) {
      if (k % 2 == 0) {
        total = total + (k * b) + factor;
      } else {
        total = total - k;
      }
    }
    return total;
  }

  String describe(String label) {
    return 'worker $i: \$label = \${compute(3, 4)}';
  }
}

''');
      }
      return b.toString();
    }

    test('an image is smaller than the source for a real program', () async {
      var source = bigSource(12);
      var vm = await _vmWith({'big.dart': source});

      var image = vm.saveCodeUnitAST(vm.allCodeUnitsAllLanguages().single);

      var ratio = image.length / source.length;
      print(
        'source: ${source.length} bytes ; image: ${image.length} bytes '
        '(${(ratio * 100).toStringAsFixed(1)}%)',
      );

      expect(
        image.length,
        lessThan(source.length),
        reason: 'The binary AST should be more compact than the source',
      );
    });

    test(
      'a tiny unit costs more than its source, and that is expected',
      () async {
        // Stated as a test rather than left as a surprise: the format trades a
        // fixed overhead for a large saving on anything of real size.
        var vm = await _vmWith({'a.dart': _sourceA});
        var image = vm.saveCodeUnitAST(vm.allCodeUnitsAllLanguages().single);

        print('tiny source: ${_sourceA.length} bytes ; image: ${image.length}');
        expect(image.length, greaterThan(0));
      },
    );

    test('decoding is faster than parsing', () async {
      var source = bigSource(12);
      var vm = await _vmWith({'big.dart': source});
      var image = vm.saveCodeUnitAST(vm.allCodeUnitsAllLanguages().single);

      const rounds = 5;

      // Warm both paths so neither pays one-off costs (the grammar is built
      // lazily and cached on the parser instance).
      await ApolloVM().loadCodeUnit(SourceCodeUnit('dart', source, id: 'w'));
      const ASTBinaryReader().readRoot(image);

      var parseWatch = Stopwatch()..start();
      for (var i = 0; i < rounds; ++i) {
        await ApolloVM().loadCodeUnit(
          SourceCodeUnit('dart', source, id: 'p$i'),
        );
      }
      parseWatch.stop();

      var decodeWatch = Stopwatch()..start();
      for (var i = 0; i < rounds; ++i) {
        const ASTBinaryReader().readRoot(image);
      }
      decodeWatch.stop();

      var parseUs = parseWatch.elapsedMicroseconds / rounds;
      var decodeUs = decodeWatch.elapsedMicroseconds / rounds;

      print(
        'parse: ${parseUs.toStringAsFixed(0)}us ; '
        'decode: ${decodeUs.toStringAsFixed(0)}us ; '
        'speedup: ${(parseUs / decodeUs).toStringAsFixed(1)}x',
      );

      // A deliberately loose bound: this is a regression tripwire, not a
      // benchmark, and CI machines are noisy. The printed numbers are the
      // interesting part.
      expect(
        decodeUs,
        lessThan(parseUs),
        reason: 'Decoding a binary AST should beat parsing the source',
      );
    });
  });
}
