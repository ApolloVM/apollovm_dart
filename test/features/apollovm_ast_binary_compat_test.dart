@Tags(['dart'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:apollovm/apollovm.dart';
import 'package:apollovm/apollovm_serialization.dart';
// The container internals are needed to synthesize files a current writer
// cannot produce — a future section, a future minimum reader version.
import 'package:apollovm/src/serialization/ast_binary_container.dart';
import 'package:apollovm/src/serialization/crc32.dart';
import 'package:test/test.dart';

/// The source [_goldenV1] was produced from.
const _goldenSource = r'''
class Golden {
  int sum(int a, int b) {
    var t = a + b;
    return t;
  }

  static void main(List<String> args) {
    print('golden: ${Golden().sum(3, 4)}');
  }
}
''';

/// A real image written by format version 1, frozen here forever.
///
/// This is the only test that can actually catch an accidental incompatible
/// change. An image synthesized by the current writer proves nothing, because
/// the current writer is exactly what a change would alter — so the bytes have
/// to come from the past and stay untouched.
///
/// Committed as base64 in the source rather than as a file under
/// `test/fixtures/`, because the Chrome test runner has no filesystem.
const _goldenV1 =
    'AEFWTQABAAEAAAAAAAAA3gEZBjIuMjguMARkYXJ0C2dvbGRlbi5kYXJ0AAI8DAAGR29s'
    'ZGVuC25vcm1hbENsYXNzA3N1bQFhAWIBdANhZGQEbWFpbgRhcmdzBXByaW50CGdvbGRl'
    'bjogAw4EAgEBAw0AAAIBEgIBDQRzZAAAAQEBAmUBAgAAAQEBA2sDA3EABAEAAAAAcQAF'
    'AQAAAAAAAAAAA0QBBiEfFAQHHxQFAEgUBgEBAWsIAnECCQEAAAAAAAADAQJDIwoCHhID'
    'BAsQIwEBAiUDAx4CAAMAHgIABAAAAAAAAQEBAQEBAQEBAe9uKjUAAEFWTQA=';

Uint8List get _golden => base64.decode(_goldenV1);

/// Rebuilds a file from [sections], so a test can present something no current
/// writer would produce.
Uint8List _rebuild(
  List<ASTBinarySectionData> sections, {
  int formatVersion = ASTBinaryFormat.version,
  int minReaderVersion = ASTBinaryFormat.version,
  int flags = 0,
}) => ASTBinaryContainerCodec.encode(
  sections: sections,
  formatVersion: formatVersion,
  minReaderVersion: minReaderVersion,
  flags: flags,
);

/// The sections of [bytes], so a test can add to or reorder them.
List<ASTBinarySectionData> _sectionsOf(Uint8List bytes) =>
    ASTBinaryContainerCodec.decode(bytes).sections;

void main() {
  group('an image written by format version 1 still loads', () {
    test('and regenerates the same source', () async {
      var vm = ApolloVM();
      expect(await vm.loadCodeUnitAST(_golden), isTrue);

      var fromImage = (await vm.generateAllCodeIn('dart').writeAllSources())
          .toString();

      // Compare against a fresh parse of the source it was made from, so this
      // stays meaningful even if the Dart generator's formatting evolves.
      var vmSource = ApolloVM();
      await vmSource.loadCodeUnit(
        SourceCodeUnit('dart', _goldenSource, id: 'golden.dart'),
      );
      var fromSource =
          (await vmSource.generateAllCodeIn('dart').writeAllSources())
              .toString();

      expect(fromImage, equals(fromSource));
    });

    test('and still runs', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnitAST(_golden);

      var runner = vm.createRunner('dart')!;
      var output = <Object?>[];
      runner.externalPrintFunction = output.add;

      await runner.executeClassMethod(
        '',
        'Golden',
        'main',
        positionalParameters: [<String>[]],
      );

      expect(output, equals(['golden: 7']));
    });

    test('and reports the version that wrote it', () {
      var info = const ASTBinaryReader().readInfo(_golden);
      expect(info.header.formatVersion, equals(1));
      expect(info.header.minReaderVersion, equals(1));
      expect(info.language, equals('dart'));
      expect(info.codeUnitId, equals('golden.dart'));
    });
  });

  group('forward tolerance', () {
    test('an unknown section is skipped', () {
      // The mechanism that lets a newer ApolloVM's output keep loading here.
      var sections = _sectionsOf(_golden);
      var withFuture = _rebuild([
        ...sections,
        ASTBinarySectionData(0x7F, Uint8List.fromList([1, 2, 3, 4, 5])),
      ]);

      var info = const ASTBinaryReader().readInfo(withFuture);
      expect(info.unknownSectionIds, equals([0x7F]));

      expect(const ASTBinaryReader().readRoot(withFuture), isNotNull);
    });

    test('a section may appear before the ones this build knows', () {
      var sections = _sectionsOf(_golden);
      var reordered = _rebuild([
        ASTBinarySectionData(0x7E, Uint8List.fromList([9])),
        ...sections,
      ]);

      expect(const ASTBinaryReader().readRoot(reordered), isNotNull);
    });

    test('a newer format version loads when it says older readers can', () {
      var bumped = _rebuild(
        _sectionsOf(_golden),
        formatVersion: 999,
        minReaderVersion: ASTBinaryFormat.version,
      );

      var info = const ASTBinaryReader().readInfo(bumped);
      expect(info.header.formatVersion, equals(999));
      expect(const ASTBinaryReader().readRoot(bumped), isNotNull);
    });

    test('a newer format version is refused when it says they cannot', () {
      // The other half of the contract: rather than mis-decoding, fail loudly
      // and name both versions.
      var bumped = _rebuild(
        _sectionsOf(_golden),
        formatVersion: 999,
        minReaderVersion: 999,
      );

      expect(
        () => const ASTBinaryReader().readRoot(bumped),
        throwsA(
          isA<ASTBinaryException>()
              .having(
                (e) => e.error,
                'error',
                ASTBinaryError.unsupportedVersion,
              )
              .having((e) => e.minReaderVersion, 'minReaderVersion', 999),
        ),
      );
    });

    test('an unknown flag bit is refused, not ignored', () {
      // Unlike a section, a flag changes how the payload must be read, so
      // ignoring one would mean mis-decoding rather than missing information.
      var flagged = _rebuild(_sectionsOf(_golden), flags: 0x40);

      expect(
        () => const ASTBinaryReader().readRoot(flagged),
        throwsA(
          isA<ASTBinaryException>().having(
            (e) => e.error,
            'error',
            ASTBinaryError.unknownFlags,
          ),
        ),
      );
    });

    test('trailing bytes in a section this build knows are ignored', () {
      // A newer writer appending a field to an existing section must not break
      // an older reader: sections are read from a bounded view.
      var sections = _sectionsOf(_golden);

      var patched = [
        for (var s in sections)
          if (s.id == ASTBinarySection.metadata.id)
            ASTBinarySectionData(
              s.id,
              Uint8List.fromList([...s.payload, 42, 42, 42]),
            )
          else
            s,
      ];

      var info = const ASTBinaryReader().readInfo(_rebuild(patched));
      expect(info.language, equals('dart'));
      expect(info.codeUnitId, equals('golden.dart'));
    });
  });

  group('malformed images fail rather than mis-decode', () {
    test('a truncated image', () {
      var truncated = _golden.sublist(0, _golden.length - 12);
      expect(
        () => const ASTBinaryReader().readRoot(truncated),
        throwsA(
          isA<ASTBinaryException>().having(
            (e) => e.error,
            'error',
            ASTBinaryError.truncated,
          ),
        ),
      );
    });

    test('an unknown node tag, even with a valid checksum', () {
      // An unknown *section* is skipped; an unknown *node* never can be — there
      // is no length prefix to skip past, and guessing would produce a wrong
      // AST rather than an incomplete one.
      var bytes = _golden;
      var container = ASTBinaryContainerCodec.decode(bytes);

      var ast = container.requirePayloadOf(ASTBinarySection.astRoot);
      var broken = Uint8List.fromList(ast);
      broken[0] = 0x7E; // A tag no build assigns.

      var rebuilt = _rebuild([
        for (var s in container.sections)
          if (s.id == ASTBinarySection.astRoot.id)
            ASTBinarySectionData(s.id, broken)
          else
            s,
      ]);

      expect(
        () => const ASTBinaryReader().readRoot(rebuilt),
        throwsA(
          isA<ASTBinaryException>().having(
            (e) => e.error,
            'error',
            ASTBinaryError.unsupportedNode,
          ),
        ),
      );
    });

    test('a corrupted string pool index', () {
      var container = ASTBinaryContainerCodec.decode(_golden);
      var strings = container.requirePayloadOf(ASTBinarySection.stringTable);

      // Claim far more strings than the section holds.
      var broken = Uint8List.fromList([0x7F, ...strings.sublist(1)]);

      var rebuilt = _rebuild([
        for (var s in container.sections)
          if (s.id == ASTBinarySection.stringTable.id)
            ASTBinarySectionData(s.id, broken)
          else
            s,
      ]);

      expect(
        () => const ASTBinaryReader().readRoot(rebuilt),
        throwsA(isA<ASTBinaryException>()),
      );
    });
  });

  group('the golden image is what it claims to be', () {
    test('its checksum verifies', () {
      var bytes = _golden;
      var sectionsSize =
          ((bytes[12] << 24) |
              (bytes[13] << 16) |
              (bytes[14] << 8) |
              bytes[15]) >>>
          0;
      var trailerStart = ASTBinaryFormat.headerSize + sectionsSize;

      var declared =
          ((bytes[trailerStart] << 24) |
              (bytes[trailerStart + 1] << 16) |
              (bytes[trailerStart + 2] << 8) |
              bytes[trailerStart + 3]) >>>
          0;

      expect(Crc32.compute(bytes, 0, trailerStart), equals(declared));
    });
  });
}
