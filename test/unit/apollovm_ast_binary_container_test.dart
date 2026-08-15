library;

import 'dart:typed_data';

// The serialization internals are not re-exported from the public library;
// imported directly, as other unit tests in this suite do for `src/` internals.
import 'package:apollovm/src/serialization/ast_binary_container.dart';
import 'package:apollovm/src/serialization/ast_binary_exception.dart';
import 'package:apollovm/src/serialization/ast_binary_format.dart';
import 'package:apollovm/src/serialization/ast_binary_signer.dart';
import 'package:apollovm/src/serialization/crc32.dart';
import 'package:test/test.dart';

Uint8List _bytes(List<int> l) => Uint8List.fromList(l);

/// A minimal well-formed file: one metadata section and one AST section.
Uint8List _sample({ASTBinarySigner? signer, int flags = 0}) =>
    ASTBinaryContainerCodec.encode(
      sections: [
        ASTBinarySectionData(
          ASTBinarySection.metadata.id,
          _bytes([1, 2, 3, 4]),
        ),
        ASTBinarySectionData(ASTBinarySection.astRoot.id, _bytes([9, 9, 9])),
      ],
      flags: flags,
      signer: signer,
    );

/// Recomputes the CRC of [bytes] in place, so a test can tamper with content
/// and still present a structurally valid file.
Uint8List _refreshCrc(Uint8List bytes) {
  var trailerStart =
      ASTBinaryFormat.headerSize +
      ((bytes[12] << 24) | (bytes[13] << 16) | (bytes[14] << 8) | bytes[15]);
  var crc = Crc32.compute(bytes, 0, trailerStart);
  bytes[trailerStart] = (crc >> 24) & 0xFF;
  bytes[trailerStart + 1] = (crc >> 16) & 0xFF;
  bytes[trailerStart + 2] = (crc >> 8) & 0xFF;
  bytes[trailerStart + 3] = crc & 0xFF;
  return bytes;
}

void main() {
  group('Crc32', () {
    test('known vectors', () {
      expect(Crc32.compute(_bytes([])), equals(0x00000000));
      expect(Crc32.compute(_bytes('123456789'.codeUnits)), equals(0xCBF43926));
      expect(Crc32.compute(_bytes('a'.codeUnits)), equals(0xE8B7BE43));
      expect(Crc32.compute(_bytes('abc'.codeUnits)), equals(0x352441C2));
    });

    test('incremental update matches one-shot', () {
      var data = Uint8List.fromList(
        List.generate(4096, (i) => (i * 31 + 7) & 0xFF),
      );

      var crc = Crc32.initial;
      crc = Crc32.update(crc, data, 0, 1000);
      crc = Crc32.update(crc, data, 1000, 3096);

      expect(Crc32.finalize(crc), equals(Crc32.compute(data)));
    });

    test('stays inside 32 bits', () {
      var data = Uint8List.fromList(List.filled(1024, 0xFF));
      var crc = Crc32.compute(data);
      expect(crc, greaterThanOrEqualTo(0));
      expect(crc, lessThanOrEqualTo(0xFFFFFFFF));
    });
  });

  group('ASTBinaryFormat', () {
    test('isASTBinary sniffs the magic', () {
      expect(ASTBinaryFormat.isASTBinary(_sample()), isTrue);
      expect(ASTBinaryFormat.isASTBinary(_bytes([0, 0x41, 0x56])), isFalse);
      expect(ASTBinaryFormat.isASTBinary(_bytes([])), isFalse);
      expect(
        ASTBinaryFormat.isASTBinary(_bytes([0x01, 0x41, 0x56, 0x4D])),
        isFalse,
      );
    });

    test('constantTimeEquals', () {
      expect(ASTBinaryFormat.constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
      expect(ASTBinaryFormat.constantTimeEquals([1, 2, 3], [1, 2, 4]), isFalse);
      expect(ASTBinaryFormat.constantTimeEquals([1, 2], [1, 2, 3]), isFalse);
      expect(ASTBinaryFormat.constantTimeEquals([], []), isTrue);
    });
  });

  group('container layout', () {
    test('byte offsets are exactly as documented', () {
      var bytes = _sample();

      expect(bytes.sublist(0, 4), equals(ASTBinaryFormat.magic));
      // formatVersion @4, minReaderVersion @6, big-endian.
      expect((bytes[4] << 8) | bytes[5], equals(ASTBinaryFormat.version));
      expect((bytes[6] << 8) | bytes[7], equals(ASTBinaryFormat.version));
      // flags @8 — unsigned sample has none set.
      expect(
        (bytes[8] << 24) | (bytes[9] << 16) | (bytes[10] << 8) | bytes[11],
        equals(0),
      );

      var sectionsSize =
          (bytes[12] << 24) | (bytes[13] << 16) | (bytes[14] << 8) | bytes[15];

      // Total length is fully described by the header and the trailer.
      expect(
        bytes.length,
        equals(
          ASTBinaryFormat.headerSize +
              sectionsSize +
              ASTBinaryFormat.minTrailerSize,
        ),
      );
      expect(
        bytes.sublist(bytes.length - 4),
        equals(ASTBinaryFormat.trailerMagic),
      );
      // signatureLength is 0 for an unsigned file.
      var trailerStart = ASTBinaryFormat.headerSize + sectionsSize;
      expect((bytes[trailerStart + 4] << 8) | bytes[trailerStart + 5], 0);
    });

    test('round trips sections in order', () {
      var c = ASTBinaryContainerCodec.decode(_sample());

      expect(c.header.formatVersion, equals(ASTBinaryFormat.version));
      expect(c.header.isSigned, isFalse);
      expect(c.signature, isNull);
      expect(c.sections.length, equals(2));
      expect(c.sections[0].id, equals(ASTBinarySection.metadata.id));
      expect(c.sections[0].section, equals(ASTBinarySection.metadata));
      expect(c.sections[0].payload, equals(_bytes([1, 2, 3, 4])));
      expect(c.sections[1].payload, equals(_bytes([9, 9, 9])));
      expect(c.unknownSectionIds, isEmpty);
    });

    test('requirePayloadOf names the missing section', () {
      var c = ASTBinaryContainerCodec.decode(_sample());
      expect(c.payloadOf(ASTBinarySection.stringTable), isNull);
      expect(
        () => c.requirePayloadOf(ASTBinarySection.stringTable),
        throwsA(
          isA<ASTBinaryException>()
              .having((e) => e.error, 'error', ASTBinaryError.malformedSection)
              .having((e) => e.message, 'message', contains('stringTable')),
        ),
      );
    });

    test('handles an empty payload and a large one', () {
      var big = Uint8List.fromList(List.generate(70000, (i) => i & 0xFF));
      var bytes = ASTBinaryContainerCodec.encode(
        sections: [
          ASTBinarySectionData(ASTBinarySection.metadata.id, _bytes([])),
          ASTBinarySectionData(ASTBinarySection.astRoot.id, big),
        ],
      );

      var c = ASTBinaryContainerCodec.decode(bytes);
      expect(c.sections[0].payload, isEmpty);
      expect(c.sections[1].payload, equals(big));
    });

    test('decodes correctly from a view at a non-zero offset', () {
      // Uint8List.view into a larger buffer is the classic place a slicing bug
      // hides: reading via `bytes.buffer` without adding `offsetInBytes` would
      // silently read the padding instead of the file.
      var file = _sample();
      var padded = Uint8List(7 + file.length + 5)
        ..setRange(7, 7 + file.length, file);
      var view = Uint8List.view(padded.buffer, 7, file.length);

      expect(view.offsetInBytes, equals(7));

      var c = ASTBinaryContainerCodec.decode(view);
      expect(c.sections[0].payload, equals(_bytes([1, 2, 3, 4])));
      expect(c.sections[1].payload, equals(_bytes([9, 9, 9])));
    });

    test('output is deterministic', () {
      expect(_sample(), equals(_sample()));
    });
  });

  group('integrity', () {
    test('detects a flipped byte in a section payload', () {
      var bytes = _sample();
      // First section payload starts after the header + 2 framing bytes.
      var target = ASTBinaryFormat.headerSize + 2;
      bytes[target] = bytes[target] ^ 0xFF;

      expect(
        () => ASTBinaryContainerCodec.decode(bytes),
        throwsA(
          isA<ASTBinaryIntegrityException>().having(
            (e) => e.error,
            'error',
            ASTBinaryError.checksumMismatch,
          ),
        ),
      );
    });

    test('detects a flipped bit in the header itself', () {
      var bytes = _sample();
      // formatVersion is big-endian at offset 4; bump the low byte 1 -> 2.
      // minReaderVersion stays 1, so the version gate accepts the file and the
      // CRC is what catches the edit.
      bytes[5] = 0x02;

      expect(
        () => ASTBinaryContainerCodec.decode(bytes),
        throwsA(
          isA<ASTBinaryIntegrityException>().having(
            (e) => e.error,
            'error',
            ASTBinaryError.checksumMismatch,
          ),
        ),
      );
    });

    test('verifyChecksum: false skips the CRC check', () {
      var bytes = _sample();
      var target = ASTBinaryFormat.headerSize + 2;
      bytes[target] = bytes[target] ^ 0xFF;

      var c = ASTBinaryContainerCodec.decode(bytes, verifyChecksum: false);
      expect(c.sections.length, equals(2));
    });

    test('rejects a truncated file', () {
      var bytes = _sample();
      expect(
        () =>
            ASTBinaryContainerCodec.decode(bytes.sublist(0, bytes.length - 5)),
        throwsA(
          isA<ASTBinaryException>().having(
            (e) => e.error,
            'error',
            ASTBinaryError.truncated,
          ),
        ),
      );
    });

    test('rejects trailing garbage', () {
      var bytes = _sample();
      var padded = Uint8List(bytes.length + 3)
        ..setRange(0, bytes.length, bytes);

      expect(
        () => ASTBinaryContainerCodec.decode(padded),
        throwsA(
          isA<ASTBinaryException>().having(
            (e) => e.error,
            'error',
            ASTBinaryError.truncated,
          ),
        ),
      );
    });

    test('rejects bad magic', () {
      var bytes = _sample();
      bytes[1] = 0x42;
      expect(
        () => ASTBinaryContainerCodec.decode(bytes),
        throwsA(
          isA<ASTBinaryException>().having(
            (e) => e.error,
            'error',
            ASTBinaryError.badMagic,
          ),
        ),
      );
    });
  });

  group('signing', () {
    test('signs and verifies with the same key', () {
      var bytes = _sample(signer: HmacSha256Signer.fromString('s3cret'));

      var c = ASTBinaryContainerCodec.decode(
        bytes,
        verifier: HmacSha256Verifier.fromString('s3cret'),
      );

      expect(c.header.isSigned, isTrue);
      expect(c.signature, isNotNull);
      expect(c.signature!.length, equals(32));
      expect(c.sections.length, equals(2));
    });

    test('rejects a wrong key', () {
      var bytes = _sample(signer: HmacSha256Signer.fromString('s3cret'));

      expect(
        () => ASTBinaryContainerCodec.decode(
          bytes,
          verifier: HmacSha256Verifier.fromString('other'),
        ),
        throwsA(
          isA<ASTBinaryIntegrityException>().having(
            (e) => e.error,
            'error',
            ASTBinaryError.signatureMismatch,
          ),
        ),
      );
    });

    test('a signed file still loads without a verifier', () {
      var bytes = _sample(signer: HmacSha256Signer.fromString('s3cret'));
      var c = ASTBinaryContainerCodec.decode(bytes);
      expect(c.header.isSigned, isTrue);
      expect(c.sections.length, equals(2));
    });

    test('refuses an unsigned file when a verifier is supplied', () {
      expect(
        () => ASTBinaryContainerCodec.decode(
          _sample(),
          verifier: HmacSha256Verifier.fromString('s3cret'),
        ),
        throwsA(
          isA<ASTBinaryIntegrityException>().having(
            (e) => e.error,
            'error',
            ASTBinaryError.signatureMissing,
          ),
        ),
      );
    });

    test(
      'tampering plus a recomputed CRC still fails signature verification',
      () {
        // The decisive test for the layering: the signature covers the CRC, so
        // an attacker who edits content and fixes the checksum is still caught.
        var bytes = _sample(signer: HmacSha256Signer.fromString('s3cret'));
        var target = ASTBinaryFormat.headerSize + 2;
        bytes[target] = bytes[target] ^ 0xFF;
        _refreshCrc(bytes);

        // The CRC now passes...
        expect(
          ASTBinaryContainerCodec.decode(bytes).sections.length,
          equals(2),
        );

        // ...but the signature does not.
        expect(
          () => ASTBinaryContainerCodec.decode(
            bytes,
            verifier: HmacSha256Verifier.fromString('s3cret'),
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
  });

  group('version and forward compatibility', () {
    test('skips an unknown section id', () {
      var bytes = ASTBinaryContainerCodec.encode(
        sections: [
          ASTBinarySectionData(
            ASTBinarySection.metadata.id,
            _bytes([1, 2, 3, 4]),
          ),
          // An id from a future ApolloVM.
          ASTBinarySectionData(0x7F, _bytes([42, 42, 42, 42, 42])),
          ASTBinarySectionData(ASTBinarySection.astRoot.id, _bytes([9, 9, 9])),
        ],
      );

      var c = ASTBinaryContainerCodec.decode(bytes);

      expect(c.unknownSectionIds, equals([0x7F]));
      expect(
        c.payloadOf(ASTBinarySection.metadata),
        equals(_bytes([1, 2, 3, 4])),
      );
      expect(c.payloadOf(ASTBinarySection.astRoot), equals(_bytes([9, 9, 9])));
    });

    test('accepts a newer formatVersion when minReaderVersion allows', () {
      var bytes = ASTBinaryContainerCodec.encode(
        sections: [
          ASTBinarySectionData(ASTBinarySection.astRoot.id, _bytes([1])),
        ],
        formatVersion: 999,
        minReaderVersion: ASTBinaryFormat.version,
      );

      var c = ASTBinaryContainerCodec.decode(bytes);
      expect(c.header.formatVersion, equals(999));
    });

    test('rejects a file needing a newer reader, naming both versions', () {
      var bytes = ASTBinaryContainerCodec.encode(
        sections: [
          ASTBinarySectionData(ASTBinarySection.astRoot.id, _bytes([1])),
        ],
        formatVersion: 999,
        minReaderVersion: 999,
      );

      expect(
        () => ASTBinaryContainerCodec.decode(bytes),
        throwsA(
          isA<ASTBinaryException>()
              .having(
                (e) => e.error,
                'error',
                ASTBinaryError.unsupportedVersion,
              )
              .having((e) => e.formatVersion, 'formatVersion', 999)
              .having((e) => e.minReaderVersion, 'minReaderVersion', 999),
        ),
      );
    });

    test('rejects unknown header flags', () {
      var bytes = ASTBinaryContainerCodec.encode(
        sections: [
          ASTBinarySectionData(ASTBinarySection.astRoot.id, _bytes([1])),
        ],
        flags: 0x00000080,
      );

      expect(
        () => ASTBinaryContainerCodec.decode(bytes),
        throwsA(
          isA<ASTBinaryException>().having(
            (e) => e.error,
            'error',
            ASTBinaryError.unknownFlags,
          ),
        ),
      );
    });
  });
}
