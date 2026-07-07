// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

@Tags(['repository'])
library;

// Unit tests for the pure path/glob/line helpers shared by the adapters.
import 'package:apollovm/apollovm_repository.dart'
    show LineRange, RepoException;
import 'package:apollovm/src/repository/repo_paths.dart';
import 'package:test/test.dart';

void main() {
  group('normalizeRepoPath', () {
    test('collapses separators, `.`, and backslashes', () {
      expect(normalizeRepoPath('a//b/./c'), 'a/b/c');
      expect(normalizeRepoPath('a\\b\\c'), 'a/b/c');
      expect(normalizeRepoPath('./lib/main.dart'), 'lib/main.dart');
      expect(normalizeRepoPath(''), '');
      expect(normalizeRepoPath('  a/b  '), 'a/b');
    });

    test('rejects absolute paths', () {
      expect(
        () => normalizeRepoPath('/etc/passwd'),
        throwsA(isA<RepoException>()),
      );
    });

    test('rejects `..` traversal anywhere', () {
      expect(() => normalizeRepoPath('../x'), throwsA(isA<RepoException>()));
      expect(
        () => normalizeRepoPath('a/../../b'),
        throwsA(isA<RepoException>()),
      );
    });
  });

  group('globToRegExp / matchesGlob', () {
    test('`*` does not cross a path separator', () {
      expect(matchesGlob('foo.dart', '*.dart'), isTrue);
      expect(matchesGlob('a/foo.dart', '*.dart'), isFalse);
    });

    test('`**` crosses separators and `**/` is optional', () {
      expect(matchesGlob('lib/a/b/c.dart', 'lib/**/*.dart'), isTrue);
      expect(matchesGlob('lib/c.dart', 'lib/**/*.dart'), isTrue);
      expect(matchesGlob('test/c.dart', 'lib/**/*.dart'), isFalse);
    });

    test('`?` matches a single non-separator char', () {
      expect(matchesGlob('a.dart', '?.dart'), isTrue);
      expect(matchesGlob('ab.dart', '?.dart'), isFalse);
      expect(matchesGlob('/.dart', '?.dart'), isFalse);
    });

    test('character classes are honored', () {
      expect(matchesGlob('a.txt', '[abc].txt'), isTrue);
      expect(matchesGlob('d.txt', '[abc].txt'), isFalse);
    });

    test('regex metacharacters are matched literally', () {
      expect(matchesGlob('a.b', 'a.b'), isTrue);
      expect(matchesGlob('axb', 'a.b'), isFalse); // `.` is escaped, not "any"
      expect(matchesGlob('a+b', 'a+b'), isTrue);
    });

    test('null/empty glob matches everything', () {
      expect(matchesGlob('anything/at/all.x', null), isTrue);
      expect(matchesGlob('anything/at/all.x', ''), isTrue);
    });
  });

  group('splitLines / sliceLines', () {
    test('splitLines counts textual lines, dropping a trailing newline', () {
      expect(splitLines(''), isEmpty);
      expect(splitLines('a\nb\n'), ['a', 'b']);
      expect(splitLines('a\nb'), ['a', 'b']);
    });

    test('full read returns content unchanged', () {
      final r = sliceLines('a\nb\nc\n', null);
      expect(r.text, 'a\nb\nc\n');
      expect(r.totalLines, 3);
    });

    test('a range returns the inclusive 1-based slice', () {
      final r = sliceLines('a\nb\nc\nd', const LineRange(2, 3));
      expect(r.text, 'b\nc');
      expect(r.totalLines, 4);
    });

    test('a range is clamped to the available lines', () {
      final r = sliceLines('a\nb', const LineRange(1, 99));
      expect(r.text, 'a\nb');
    });

    test('a start beyond the end yields empty text', () {
      final r = sliceLines('a\nb', const LineRange(9));
      expect(r.text, '');
      expect(r.totalLines, 2);
    });
  });

  group('applyEdit', () {
    test('replaces a single unique occurrence', () {
      final r = applyEdit('int a = 1;', 'a', 'b');
      expect(r.content, 'int b = 1;');
      expect(r.replacements, 1);
      expect(r.appliedAtLine, isNull);
    });

    test('throws when oldString is empty or not found', () {
      expect(() => applyEdit('x', '', 'y'), throwsA(isA<RepoException>()));
      expect(() => applyEdit('x', 'z', 'y'), throwsA(isA<RepoException>()));
    });

    test('throws on ambiguous match unless replaceAll', () {
      expect(() => applyEdit('a a a', 'a', 'b'), throwsA(isA<RepoException>()));
      final r = applyEdit('a a a', 'a', 'b', replaceAll: true);
      expect(r.content, 'b b b');
      expect(r.replacements, 3);
    });

    test('atLine anchors the edit to a 1-based line', () {
      final r = applyEdit('x\ntarget\nx', 'target', 'Y', atLine: 2);
      expect(r.content, 'x\nY\nx');
      expect(r.appliedAtLine, 2);
    });

    test('atLine rejects an out-of-range or mismatched line', () {
      expect(
        () => applyEdit('a\nb', 'a', 'c', atLine: 9),
        throwsA(isA<RepoException>()),
      );
      expect(
        () => applyEdit('a\nb', 'a', 'c', atLine: 2), // `a` is on line 1
        throwsA(isA<RepoException>()),
      );
    });

    test('atLine with multiple hits on the line needs replaceAll', () {
      expect(
        () => applyEdit('a a', 'a', 'b', atLine: 1),
        throwsA(isA<RepoException>()),
      );
      final r = applyEdit('a a', 'a', 'b', atLine: 1, replaceAll: true);
      expect(r.content, 'b b');
      expect(r.replacements, 2);
    });
  });
}
