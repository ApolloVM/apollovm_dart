@TestOn('vm')
library;

import 'dart:io';

// Serialization internals are not re-exported from the public library.
import 'package:apollovm/src/serialization/ast_binary_registry.dart';
import 'package:apollovm/src/serialization/ast_binary_tags.dart';
import 'package:test/test.dart';

/// A concrete `AST*` class as declared in the sources.
class _AstClass {
  final String name;
  final String? superName;
  final String file;

  _AstClass(this.name, this.superName, this.file);

  @override
  String toString() => '$name (in $file)';
}

/// Every concrete `class AST…` declared under `lib/src/ast/`.
///
/// Read from the sources rather than from the running program: there is no
/// `dart:mirrors` on the web, and the whole point is to fail when someone adds
/// a node class and forgets its codec — which a runtime check could not see.
List<_AstClass> _scanAstClasses() {
  var dir = Directory('lib/src/ast');
  expect(
    dir.existsSync(),
    isTrue,
    reason: 'Run this test from the package root.',
  );

  var classes = <_AstClass>[];

  // Directory listing, not a hardcoded file list, so a new AST file cannot be
  // silently missed.
  var files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  expect(files, isNotEmpty, reason: 'No AST sources found.');

  for (var file in files) {
    var source = file.readAsStringSync();
    var name = file.uri.pathSegments.last;

    // A declaration header can wrap over several lines, e.g.
    //   class ASTValueArray2D<T extends ASTType<V>, V>
    //       extends ASTValueArray<ASTTypeArray<T, V>, List<V>> {
    // so each `class …` is taken up to its opening brace and flattened.
    for (var match in RegExp(
      r'^class\s+(AST\w+)',
      multiLine: true,
    ).allMatches(source)) {
      var brace = source.indexOf('{', match.start);
      if (brace < 0) continue;

      var header = source
          .substring(match.start, brace)
          .replaceAll(RegExp(r'\s+'), ' ');

      var superMatch = RegExp(r'\bextends\s+(AST\w+)').firstMatch(header);

      classes.add(_AstClass(match.group(1)!, superMatch?.group(1), name));
    }
  }

  return classes;
}

/// Types are not node-tagged: they live in their own pool, which interns them
/// and preserves the identity of ApolloVM's `ASTType` singletons.
/// `test/unit/apollovm_ast_binary_type_pool_test.dart` covers them.
bool _isPooledType(_AstClass c) => c.file == 'apollovm_ast_type.dart';

/// Classes that are encoded as part of their parent rather than on their own,
/// or that are rebuilt from other data — with the reason in each case.
///
/// Every entry here is a deliberate, reviewed decision. Adding one is how a new
/// node kind could dodge coverage, so the count is pinned below.
const Map<String, String> _notTagged = {
  // Written inline by whichever node owns them.
  'ASTModifiers': 'a seven-flag bitfield written as one byte by its owner',
  'ASTAnnotation': 'written inline by the type or declaration carrying it',
  'ASTAnnotationParameter': 'written inline as part of its annotation',
  'ASTConstructorParametersDeclaration':
      "written inline as the declaration's three parameter groups",
  'ASTFunctionParametersDeclaration':
      "written inline as the declaration's three parameter groups",

  // Abstract in practice: only their subclasses are ever constructed.
  'ASTEntryPointBlock': 'a base class; ASTRoot and ASTClass are what exist',
  'ASTParameterDeclaration':
      'a base class; the function and constructor variants are what exist',

  // Rebuilt from the declarations themselves.
  'ASTFunctionSetSingle':
      'an overload bucket rebuilt by addFunction from the declarations',
  'ASTFunctionSetMultiple':
      'an overload bucket rebuilt by addFunction from the declarations',
  'ASTConstructorSetSingle':
      'an overload bucket rebuilt by addConstructor from the declarations',
  'ASTConstructorSetMultiple':
      'an overload bucket rebuilt by addConstructor from the declarations',
  'ASTFunctionSignature':
      'an overload-resolution key derived from a call site, not part of the tree',
};

void main() {
  late List<_AstClass> astClasses;
  late Map<String, String?> superOf;

  setUpAll(() {
    astClasses = _scanAstClasses();
    superOf = {for (var c in astClasses) c.name: c.superName};
  });

  group('codec coverage', () {
    test('finds the AST classes at all', () {
      // A sanity floor: if the scan silently stopped matching, every other
      // assertion here would pass vacuously.
      expect(astClasses.length, greaterThan(100));
      expect(
        astClasses.map((e) => e.name),
        containsAll(['ASTRoot', 'ASTBlock', 'ASTClassNormal', 'ASTValueInt']),
      );
    });

    test('every AST class is registered, pooled, or explicitly accounted for', () {
      var registered = {for (var c in ASTCodecRegistry.ordered) c.className};

      var unaccounted = <_AstClass>[];
      for (var c in astClasses) {
        if (registered.contains(c.name)) continue;
        if (_isPooledType(c)) continue;
        if (_notTagged.containsKey(c.name)) continue;
        if (ASTCodecRegistry.excluded.containsKey(c.name)) continue;
        unaccounted.add(c);
      }

      expect(
        unaccounted,
        isEmpty,
        reason:
            'These AST classes have no binary encoding and no recorded reason.\n'
            'Add a codec with a new tag in `ASTNodeTag`, or record why it does '
            'not need one — in `_notTagged` here if it is written inline or '
            'rebuilt, or in `ASTCodecRegistry.excluded` if it holds live Dart '
            'state:\n  ${unaccounted.join('\n  ')}',
      );
    });

    test('every registered codec names a class that exists', () {
      var known = {for (var c in astClasses) c.name};

      for (var codec in ASTCodecRegistry.ordered) {
        expect(
          known,
          contains(codec.className),
          reason:
              'Codec ${codec.tag} names `${codec.className}`, which is not '
              'declared in lib/src/ast/. A renamed class leaves the coverage '
              'check matching nothing.',
        );
      }
    });

    test('every excluded and inline name refers to a real class', () {
      var known = {for (var c in astClasses) c.name};

      for (var name in [
        ...ASTCodecRegistry.excluded.keys,
        ..._notTagged.keys,
      ]) {
        expect(
          known,
          contains(name),
          reason:
              '`$name` is recorded as not needing a codec, but no such class '
              'is declared in lib/src/ast/.',
        );
      }
    });

    test('the exclusion list is pinned', () {
      // Both lists are how a node kind could quietly dodge coverage, so growing
      // either is a deliberate edit rather than something that drifts.
      expect(
        ASTCodecRegistry.excluded.length,
        equals(15),
        reason:
            'The set of nodes refused by the writer changed. Every entry must '
            'hold live Dart state, or be unreachable — confirm that, then '
            'update this count.',
      );
      expect(
        _notTagged.length,
        equals(12),
        reason:
            'The set of nodes encoded inline or rebuilt changed. Confirm the '
            'new entry really is covered by its parent, then update this count.',
      );
    });
  });

  group('tag hygiene', () {
    test('no tag is used twice', () {
      var seen = <int, String>{};
      for (var codec in ASTCodecRegistry.ordered) {
        var previous = seen[codec.tag];
        expect(
          previous,
          isNull,
          reason:
              'Tag ${codec.tag} is claimed by both `$previous` and '
              '`${codec.className}`.',
        );
        seen[codec.tag] = codec.className;
      }
    });

    test('no tag reuses a retired number', () {
      for (var codec in ASTCodecRegistry.ordered) {
        expect(
          ASTNodeTag.retired,
          isNot(contains(codec.tag)),
          reason:
              'Tag ${codec.tag} was retired; reusing it would make old files '
              'decode as `${codec.className}`.',
        );
      }
    });

    test('no codec claims the null-node marker', () {
      for (var codec in ASTCodecRegistry.ordered) {
        expect(codec.tag, isNot(equals(ASTNodeTag.nullNode)));
      }
    });

    test('lookup by tag finds every codec', () {
      for (var codec in ASTCodecRegistry.ordered) {
        expect(identical(ASTCodecRegistry.byTag(codec.tag), codec), isTrue);
      }
      expect(ASTCodecRegistry.byTag(0xFFFF), isNull);
    });
  });

  group('dispatch order', () {
    /// Whether [name] is [ancestor], or descends from it.
    bool descendsFrom(String name, String ancestor) {
      var current = superOf[name];
      while (current != null) {
        if (current == ancestor) return true;
        current = superOf[current];
      }
      return false;
    }

    test('a subclass is always registered before its superclass', () {
      // Writer dispatch walks the ordered list with `is` tests and takes the
      // first match, so a superclass appearing first would swallow every one of
      // its subclasses — silently encoding them with the wrong codec.
      var ordered = ASTCodecRegistry.ordered;

      for (var i = 0; i < ordered.length; ++i) {
        for (var j = i + 1; j < ordered.length; ++j) {
          expect(
            descendsFrom(ordered[j].className, ordered[i].className),
            isFalse,
            reason:
                '`${ordered[j].className}` extends `${ordered[i].className}` '
                'but is registered after it, so it would be encoded as its '
                'superclass. Move it earlier in `ASTCodecRegistry.ordered`.',
          );
        }
      }
    });

    test('the plain block codec is registered last of all', () {
      // Classes, functions, getters, setters and the root are all `ASTBlock`s.
      var last = ASTCodecRegistry.ordered.last;
      expect(last.className, equals('ASTBlock'));
    });
  });
}
