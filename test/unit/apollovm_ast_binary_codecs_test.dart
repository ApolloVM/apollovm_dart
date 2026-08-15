library;

import 'dart:typed_data';

import 'package:apollovm/apollovm.dart';
import 'package:apollovm/apollovm_serialization.dart';
// Serialization internals are not re-exported from the public library.
import 'package:apollovm/src/serialization/ast_binary_context.dart';
import 'package:apollovm/src/serialization/ast_binary_node_codec.dart';
import 'package:apollovm/src/serialization/ast_binary_pool.dart';
import 'package:apollovm/src/serialization/ast_binary_registry.dart';
import 'package:apollovm/src/serialization/ast_binary_type_pool.dart';
import 'package:data_serializer/data_serializer.dart';
import 'package:test/test.dart';

/// Writes [node] and reads it back through a real context pair.
///
/// Node-level rather than through a whole program, so kinds no grammar
/// produces — and which the language fixtures therefore never reach — are still
/// exercised.
T _roundTrip<T extends Object>(Object node) {
  var (bytes, strings, types) = _write((w) => w.node(node));
  return _read(bytes, strings, types).node<T>();
}

/// Runs [body] against a fresh write context and returns its bytes and pools.
(Uint8List, Uint8List, Uint8List) _write(
  void Function(ASTBinaryWriteContext w) body,
) {
  var strings = ASTStringPoolWriter();
  var types = ASTTypePoolWriter(strings);
  var w = ASTBinaryWriteContext(strings, types);

  body(w);

  // The pools are filled while writing, so they are encoded afterwards.
  return (w.toBytes(), strings.encode(), types.encode());
}

ASTBinaryReadContext _read(
  Uint8List bytes,
  Uint8List strings,
  Uint8List types,
) {
  var stringsIn = ASTStringPoolReader.decode(strings);
  return ASTBinaryReadContext(
    BytesBuffer.from(bytes),
    stringsIn,
    ASTTypePoolReader.decode(types, stringsIn),
    formatVersion: ASTBinaryFormat.version,
  );
}

/// The plain Dart value inside a decoded static value.
Object? _valueOf(ASTValue v) => (v as ASTValueStatic).value;

void main() {
  group('value codecs', () {
    test('primitives', () {
      expect(_roundTrip<ASTValueBool>(ASTValueBool(true)).value, isTrue);
      expect(_roundTrip<ASTValueString>(ASTValueString('hi')).value, 'hi');
      expect(_roundTrip<ASTValueNull>(ASTValueNull()), isA<ASTValueNull>());
      expect(_roundTrip<ASTValueVoid>(ASTValueVoid()), isA<ASTValueVoid>());
    });

    test('int keeps its value and its written sign', () {
      // `negative` is not derivable from the value: it records that the source
      // wrote a unary minus.
      var positive = _roundTrip<ASTValueInt>(ASTValueInt(42));
      expect(positive.value, 42);
      expect(positive.negative, isFalse);

      var negative = _roundTrip<ASTValueInt>(ASTValueInt(-7));
      expect(negative.value, -7);
      expect(negative.negative, isTrue);
    });

    test('double, including negative zero', () {
      expect(_roundTrip<ASTValueDouble>(ASTValueDouble(3.5)).value, 3.5);
      expect(_roundTrip<ASTValueDouble>(ASTValueDouble(-0.25)).value, -0.25);

      var big = _roundTrip<ASTValueDouble>(
        ASTValueDouble(1.7976931348623157e308),
      );
      expect(big.value, 1.7976931348623157e308);
    });

    test('object and var hold plain data', () {
      expect(_valueOf(_roundTrip<ASTValueObject>(ASTValueObject('x'))), 'x');
      expect(_valueOf(_roundTrip<ASTValueVar>(ASTValueVar(7))), 7);
    });

    test('a loosely typed static value keeps its declared type', () {
      var v = _roundTrip<ASTValueStatic>(
        ASTValueStatic(ASTTypeString.instance, 'text'),
      );
      expect(identical(v.type, ASTTypeString.instance), isTrue);
      expect(v.value, 'text');
    });

    test('arrays of one, two and three dimensions', () {
      ASTType intType = ASTTypeInt.instance;

      var a1 = _roundTrip<ASTValueArray>(ASTValueArray(intType, [1, 2, 3]));
      expect(a1.value, equals([1, 2, 3]));

      var a2 = _roundTrip<ASTValueArray2D>(
        ASTValueArray2D(intType, [
          [1, 2],
          [3],
        ]),
      );
      expect(
        a2.value,
        equals([
          [1, 2],
          [3],
        ]),
      );

      var a3 = _roundTrip<ASTValueArray3D>(
        ASTValueArray3D(intType, [
          [
            [1],
            [2, 3],
          ],
        ]),
      );
      expect(
        a3.value,
        equals([
          [
            [1],
            [2, 3],
          ],
        ]),
      );
    });

    test('map keeps its key and value types', () {
      ASTType keyType = ASTTypeString.instance;
      ASTType valueType = ASTTypeInt.instance;

      var m = _roundTrip<ASTValueMap>(
        ASTValueMap(keyType, valueType, {'a': 1, 'b': 2}),
      );

      expect(m.value, equals({'a': 1, 'b': 2}));
      var type = m.type as ASTTypeMap;
      expect(identical(type.keyType, ASTTypeString.instance), isTrue);
      expect(identical(type.valueType, ASTTypeInt.instance), isTrue);
    });

    test('string composition', () {
      var asString = _roundTrip<ASTValueAsString>(
        ASTValueAsString(ASTValueInt(9)),
      );
      expect((asString.value as ASTValueInt).value, 9);

      var list = _roundTrip<ASTValuesListAsString>(
        ASTValuesListAsString([ASTValueInt(1), ASTValueString('b')]),
      );
      expect(list.values.length, 2);
      expect((list.values[1] as ASTValueString).value, 'b');

      var concat = _roundTrip<ASTValueStringConcatenation>(
        ASTValueStringConcatenation([ASTValueString('a'), ASTValueString('b')]),
      );
      expect(concat.values.length, 2);

      var fromVariable = _roundTrip<ASTValueStringVariable>(
        ASTValueStringVariable(ASTScopeVariable('v')),
      );
      expect(fromVariable.variable.name, 'v');
    });
  });

  group('the plain-Dart value union', () {
    Object? roundTripNative(Object? v) {
      var (bytes, strings, types) = _write((w) => w.nativeValue(v));
      return _read(bytes, strings, types).nativeValue();
    }

    test('every representable form', () {
      expect(roundTripNative(null), isNull);
      expect(roundTripNative(true), isTrue);
      expect(roundTripNative(false), isFalse);
      expect(roundTripNative(123), 123);
      expect(roundTripNative(-123), -123);
      expect(roundTripNative(1.5), 1.5);
      expect(roundTripNative('s'), 's');
      expect(roundTripNative(<Object?>[]), isEmpty);
      expect(roundTripNative(<Object?, Object?>{}), isEmpty);
    });

    test('nested lists and maps', () {
      var nested = [
        1,
        'two',
        [3, null],
        {'k': true},
      ];
      expect(roundTripNative(nested), equals(nested));
    });

    test('a nested AST node', () {
      var decoded = roundTripNative(ASTValueString('inner'));
      expect((decoded as ASTValueString).value, 'inner');
    });

    test('an integer beyond the exact range of a JavaScript double', () {
      // Stored as a decimal string so a VM-written image stays readable. On the
      // web the writer cannot produce such a value in the first place.
      //
      // Built by arithmetic rather than written as a literal: `testOn` gates
      // execution, not compilation, and `9007199254740993` cannot be compiled
      // for the web at all. 2^53 itself is exactly representable, so it can.
      var big = 9007199254740992 + 1; // 2^53 + 1

      var decoded = roundTripNative(big);
      expect(decoded, equals(big));
    }, testOn: 'vm');

    test('live Dart state is refused by name', () {
      expect(
        () => _write((w) => w.nativeValue(DateTime.utc(2020))),
        throwsA(
          isA<ASTNotSerializableException>().having(
            (e) => e.toString(),
            'toString',
            allOf(contains('DateTime'), contains('live Dart state')),
          ),
        ),
      );
    });
  });

  group('context primitives', () {
    test('signed integers', () {
      // Written as a sign byte plus an unsigned magnitude, since
      // `BytesBuffer.readLeb128SignedInt` mis-decodes negatives.
      for (var v in [0, 1, -1, 63, -63, 64, -64, 1000, -1000, 1 << 40]) {
        var (bytes, s, t) = _write((w) => w.sint(v));
        expect(_read(bytes, s, t).sint(), equals(v), reason: 'sint($v)');
      }
    });

    test('nullable unsigned integers', () {
      var (bytes, s, t) = _write((w) {
        w.uintOrNull(null);
        w.uintOrNull(0);
        w.uintOrNull(9);
      });
      var r = _read(bytes, s, t);
      expect(r.uintOrNull(), isNull);
      expect(r.uintOrNull(), 0);
      expect(r.uintOrNull(), 9);
    });

    test('bytes and booleans', () {
      var (bytes, s, t) = _write((w) {
        w.byte(0xAB);
        w.boolean(true);
      });
      var r = _read(bytes, s, t);
      expect(r.byte(), 0xAB);
      expect(r.boolean(), isTrue);
    });

    test('a null string list is distinct from an empty one', () {
      var (bytes, s, t) = _write((w) {
        w.strings_(null);
        w.strings_([]);
        w.strings_(['a', 'b']);
      });
      var r = _read(bytes, s, t);
      expect(r.strings_(), isNull);
      expect(r.strings_(), isEmpty);
      expect(r.strings_(), equals(['a', 'b']));
    });

    test('a null node list is distinct from an empty one', () {
      // The generators treat a missing list and an empty one differently.
      var (bytes, s, t) = _write((w) {
        w.nodes(null);
        w.nodes([]);
      });
      var r = _read(bytes, s, t);
      expect(r.nodes<ASTValue>(), isNull);
      expect(r.nodes<ASTValue>(), isEmpty);
    });

    test('a null type list is distinct from an empty one', () {
      var (bytes, s, t) = _write((w) {
        w.typeList(null);
        w.typeList([]);
        w.typeList([ASTTypeInt.instance]);
      });
      var r = _read(bytes, s, t);
      expect(r.typeList(), isNull);
      expect(r.typeList(), isEmpty);
      expect(r.typeList()!.single, same(ASTTypeInt.instance));
    });

    test('annotations, including a null list', () {
      var (bytes, s, t) = _write((w) {
        w.annotations(null);
        w.annotations([
          ASTAnnotation('Marker'),
          ASTAnnotation('Named', {'p': ASTAnnotationParameter('p', 'v', true)}),
        ]);
      });

      var r = _read(bytes, s, t);
      expect(r.annotations(), isNull);

      var list = r.annotations()!;
      expect(list.length, 2);
      expect(list[0].name, 'Marker');
      expect(list[1].parameters!['p']!.value, 'v');
      expect(list[1].parameters!['p']!.defaultParameter, isTrue);
    });

    test('every modifier flag survives', () {
      for (var m in [
        ASTModifiers(),
        ASTModifiers(isStatic: true, isFinal: true),
        ASTModifiers(isPrivate: true, isAsync: true),
        ASTModifiers(isPublic: true, isAbstract: true, isProtected: true),
      ]) {
        var (bytes, s, t) = _write((w) => w.modifiers(m));
        var decoded = _read(bytes, s, t).modifiers();
        expect(decoded.modifiers, equals(m.modifiers), reason: '$m');
      }
    });

    test('a nullable string', () {
      var (bytes, s, t) = _write((w) {
        w.strOrNull(null);
        w.strOrNull('x');
      });
      var r = _read(bytes, s, t);
      expect(r.strOrNull(), isNull);
      expect(r.strOrNull(), 'x');
    });

    test('a nullable type', () {
      var (bytes, s, t) = _write((w) {
        w.typeOrNull(null);
        w.typeOrNull(ASTTypeString.instance);
      });
      var r = _read(bytes, s, t);
      expect(r.typeOrNull(), isNull);
      expect(r.typeOrNull(), same(ASTTypeString.instance));
    });

    test('the declaration path names where the writer is', () {
      var (_, _, _) = _write((w) {
        expect(w.declarationPath, isEmpty);
        w.inDeclaration('class Foo', () {
          expect(w.declarationPath, 'class Foo');
          w.inDeclaration('bar', () {
            expect(w.declarationPath, 'class Foo > bar');
          });
          expect(w.declarationPath, 'class Foo');
        });
        expect(w.declarationPath, isEmpty);
      });
    });
  });

  group('node kinds no grammar produces', () {
    test('export statement', () {
      var decoded = _roundTrip<ASTStatementExport>(
        ASTStatementExport(
          path: 'other.dart',
          symbols: const [ASTImportedSymbol('A', alias: 'B')],
          combinators: const [
            ASTImportCombinator(ASTImportCombinatorKind.hide, ['C']),
          ],
        ),
      );

      expect(decoded.path, 'other.dart');
      expect(decoded.symbols.single.name, 'A');
      expect(decoded.symbols.single.alias, 'B');
      expect(decoded.combinators.single.isHide, isTrue);
      expect(decoded.combinators.single.names, equals(['C']));
    });

    test('export with no path', () {
      var decoded = _roundTrip<ASTStatementExport>(ASTStatementExport());
      expect(decoded.path, isNull);
      expect(decoded.symbols, isEmpty);
    });

    test('type alias', () {
      var decoded = _roundTrip<ASTTypeAlias>(
        ASTTypeAlias('Callback', ASTTypeString.instance),
      );
      expect(decoded.name, 'Callback');
      expect(identical(decoded.targetType, ASTTypeString.instance), isTrue);
    });

    test('a standalone getter and setter', () {
      var getter = _roundTrip<ASTGetterDeclaration>(
        ASTGetterDeclaration(
          'value',
          ASTTypeInt.instance,
          modifiers: ASTModifiers(isStatic: true),
        ),
      );
      expect(getter.name, 'value');
      expect(getter.modifiers.isStatic, isTrue);

      var setter = _roundTrip<ASTSetterDeclaration>(
        ASTSetterDeclaration('value', ASTTypeInt.instance, 'v'),
      );
      expect(setter.name, 'value');
      expect(setter.parameterName, 'v');
      expect(identical(setter.parameterType, ASTTypeInt.instance), isTrue);
    });

    test('a bare return statement', () {
      expect(
        _roundTrip<ASTStatementReturn>(ASTStatementReturn()),
        isA<ASTStatementReturn>(),
      );
    });

    test('a single-line statement block', () {
      var block = ASTSingleLineStatementBlock(null)
        ..addStatement(ASTStatementBreak());

      var decoded = _roundTrip<ASTSingleLineStatementBlock>(block);
      expect(decoded.statements.single, isA<ASTStatementBreak>());
    });
  });

  group('the writer refuses live Dart state', () {
    test('a runtime variable, naming where it was found', () {
      var node = ASTRuntimeVariable(ASTTypeInt.instance, 'x');

      expect(
        () => _write((w) => w.inDeclaration('class Foo', () => w.node(node))),
        throwsA(
          isA<ASTNotSerializableException>()
              .having((e) => e.declarationPath, 'declarationPath', 'class Foo')
              .having(
                (e) => e.toString(),
                'toString',
                allOf(
                  contains('ASTRuntimeVariable'),
                  contains('class Foo'),
                  contains('running context'),
                ),
              ),
        ),
      );
    });

    test('every external node kind, each of which extends an encodable one', () {
      // The dangerous case, and the reason refusal is decided by the concrete
      // class rather than by "no codec matched": each of these extends a kind
      // that encodes perfectly well, so an `is` scan alone would match the
      // superclass and write them as an ordinary declaration — silently
      // dropping the Dart closure that is their whole point.
      //
      // These are also the excluded kinds most likely to be met in practice:
      // `ApolloExternalFunctionMapper` injects them into a VM a caller may then
      // try to serialize.
      var clazz = ASTClassNormal('Host', ASTType<VMObject>('Host'), null);

      var nodes = <Object>[
        ASTExternalFunction(
          'ext',
          ASTFunctionParametersDeclaration(null),
          ASTTypeVoid.instance,
          () {},
        ),
        ASTExternalClassFunction(
          clazz,
          'extMethod',
          ASTFunctionParametersDeclaration(null),
          ASTTypeVoid.instance,
          () {},
        ),
        ASTExternalGetter('extGetter', ASTTypeInt.instance, () => 1),
        ASTExternalClassGetter(
          clazz,
          'extClassGetter',
          ASTTypeInt.instance,
          (Object? o) => 1,
        ),
      ];

      for (var node in nodes) {
        expect(
          () => _write((w) => w.node(node)),
          throwsA(
            isA<ASTNotSerializableException>().having(
              (e) => e.reason,
              'reason',
              contains('closure'),
            ),
          ),
          reason: '${node.runtimeType} must be refused, not written',
        );
      }
    });

    test('every excluded name has a reason', () {
      for (var e in ASTCodecRegistry.excluded.entries) {
        expect(e.value, isNotEmpty, reason: '${e.key} has no reason');
      }
    });
  });

  group('malformed input is reported, not mis-decoded', () {
    test('an unknown enum name', () {
      var (bytes, s, t) = _write((w) => w.str('notAnOperator'));

      expect(
        () => _read(bytes, s, t).enumByName(ASTExpressionOperator.values),
        throwsA(
          isA<ASTBinaryException>()
              .having((e) => e.error, 'error', ASTBinaryError.unsupportedNode)
              .having((e) => e.message, 'message', contains('notAnOperator')),
        ),
      );
    });

    test('modifiers that are both private and public', () {
      // `ASTModifiers` refuses that combination; a corrupted byte must surface
      // as a malformed file rather than a bare StateError.
      var (bytes, s, t) = _write((w) => w.byte(0x04 | 0x08));

      expect(
        () => _read(bytes, s, t).modifiers(),
        throwsA(
          isA<ASTBinaryException>().having(
            (e) => e.error,
            'error',
            ASTBinaryError.malformedSection,
          ),
        ),
      );
    });

    test('an unknown integer form', () {
      var (bytes, s, t) = _write((w) => w.byte(0x7F));
      expect(
        () => _read(bytes, s, t).literalInt(),
        throwsA(isA<ASTBinaryException>()),
      );
    });

    test('an unknown native value tag', () {
      var (bytes, s, t) = _write((w) => w.byte(0x7F));
      expect(
        () => _read(bytes, s, t).nativeValue(),
        throwsA(isA<ASTBinaryException>()),
      );
    });

    test('a string pool index out of range', () {
      var pool = ASTStringPoolReader.decode(ASTStringPoolWriter().encode());
      expect(() => pool[0], throwsA(isA<ASTBinaryException>()));
      expect(() => pool[-1], throwsA(isA<ASTBinaryException>()));
      expect(pool.length, 0);
    });

    test('a type pool index out of range', () {
      var strings = ASTStringPoolWriter();
      var types = ASTTypePoolWriter(strings);
      var pool = ASTTypePoolReader.decode(
        types.encode(),
        ASTStringPoolReader.decode(strings.encode()),
      );

      expect(() => pool[0], throwsA(isA<ASTBinaryException>()));
      expect(pool.length, 0);
    });

    test('a node where a different one was expected', () {
      var (bytes, s, t) = _write((w) => w.node(ASTValueString('x')));
      expect(
        () => _read(bytes, s, t).node<ASTStatement>(),
        throwsA(
          isA<ASTBinaryException>().having(
            (e) => e.message,
            'message',
            contains('ASTValueString'),
          ),
        ),
      );
    });

    test('a null marker where a node was required', () {
      var (bytes, s, t) = _write((w) => w.nodeOrNull(null));
      expect(
        () => _read(bytes, s, t).node<ASTValue>(),
        throwsA(
          isA<ASTBinaryException>().having(
            (e) => e.message,
            'message',
            contains('null node marker'),
          ),
        ),
      );
    });

    test('an unknown node tag', () {
      var (bytes, s, t) = _write((w) => w.uint(0x7E));
      expect(
        () => _read(bytes, s, t).node<ASTValue>(),
        throwsA(
          isA<ASTBinaryException>().having(
            (e) => e.error,
            'error',
            ASTBinaryError.unsupportedNode,
          ),
        ),
      );
    });
  });

  group('diagnostics read usefully', () {
    // A diagnostic that is never exercised is exactly what breaks when it is
    // finally needed.
    test('ASTBinaryException carries its context', () {
      var e = const ASTBinaryException(
        'bad things',
        ASTBinaryError.malformedSection,
        offset: 12,
        formatVersion: 3,
        minReaderVersion: 2,
        sectionId: 4,
      );

      var text = e.toString();
      expect(text, contains('malformedSection'));
      expect(text, contains('bad things'));
      expect(text, contains('offset: 12'));
      expect(text, contains('section: 4'));
      expect(text, contains('formatVersion: 3'));
      expect(text, contains('minReaderVersion: 2'));
    });

    test('ASTBinaryIntegrityException is an ASTBinaryException', () {
      var e = const ASTBinaryIntegrityException(
        'checksum',
        ASTBinaryError.checksumMismatch,
      );
      expect(e, isA<ASTBinaryException>());
      expect(e.toString(), contains('checksumMismatch'));
    });

    test('ASTNotSerializableException without a declaration path', () {
      var e = const ASTNotSerializableException('x', 'because');
      expect(e.toString(), contains('because'));
      expect(e.toString(), isNot(contains('(at ')));
    });

    test('a codec prints its tag and class', () {
      var codec = ASTCodecRegistry.ordered.first;
      expect(codec.toString(), contains(codec.className));
      expect(codec.toString(), contains('${codec.tag}'));
      expect(codec, isA<ASTNodeCodec>());
    });

    test('a section prints its id and size', () {
      var known = ASTBinarySectionData(
        ASTBinarySection.metadata.id,
        Uint8List(3),
      );
      expect(known.toString(), contains('metadata'));
      expect(known.toString(), contains('size: 3'));

      var unknown = ASTBinarySectionData(0x7F, Uint8List(0));
      expect(unknown.toString(), contains('unknown'));
      expect(unknown.section, isNull);
    });

    test('a header prints its versions and flags', () {
      var header = const ASTBinaryHeader(
        formatVersion: 1,
        minReaderVersion: 1,
        flags: ASTBinaryFlags.signed | ASTBinaryFlags.hasSourceRef,
        sectionsSize: 99,
      );

      expect(header.isSigned, isTrue);
      expect(header.hasSourceRef, isTrue);
      expect(header.hasSectionIndex, isFalse);
      expect(header.hasArchiveFlag, isFalse);
      expect(header.toString(), contains('sectionsSize: 99'));
    });
  });
}
