// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

@Tags(['repository'])
library;

import 'package:apollovm/apollovm_repository.dart';
import 'package:test/test.dart';

void main() {
  group('RepoConfig', () {
    test('defaults are the safe, read-only posture', () {
      const c = RepoConfig();
      expect(c.allowWrite, isFalse);
      expect(c.allowGitMutation, isFalse);
      expect(c.requireLineMatch, isFalse);
      expect(c.respectGitignore, isTrue);
    });

    test('copyWith overrides only the given fields', () {
      const base = RepoConfig();
      final c = base.copyWith(allowWrite: true, maxFileBytes: 10);
      expect(c.allowWrite, isTrue);
      expect(c.maxFileBytes, 10);
      expect(c.allowGitMutation, isFalse); // untouched
      expect(base.allowWrite, isFalse); // original unchanged
    });

    test('toString lists the knobs', () {
      expect(const RepoConfig().toString(), contains('allowWrite: false'));
    });
  });

  group('value types serialize to JSON', () {
    test('RepoFile includes range fields only when present', () {
      const full = RepoFile(path: 'a', content: 'x', totalLines: 1);
      expect(full.toJson().containsKey('startLine'), isFalse);
      const sliced = RepoFile(
        path: 'a',
        content: 'x',
        totalLines: 3,
        startLine: 1,
        endLine: 2,
      );
      expect(sliced.toJson()['startLine'], 1);
      expect(sliced.toJson()['endLine'], 2);
    });

    test('RepoStat omits modified when null, keeps it when set', () {
      const noMtime = RepoStat(
        path: 'a',
        exists: true,
        isDir: false,
        size: 1,
        lineCount: 1,
      );
      expect(noMtime.toJson().containsKey('modified'), isFalse);
      const withMtime = RepoStat(
        path: 'a',
        exists: true,
        isDir: false,
        size: 1,
        lineCount: 1,
        modified: '2020-01-01T00:00:00.000',
      );
      expect(withMtime.toJson()['modified'], '2020-01-01T00:00:00.000');
    });

    test('RepoEntry, RepoEdit, TextMatch, git types', () {
      expect(
        const RepoEntry(path: 'a/b', name: 'b', isDir: false, size: 3).toJson(),
        containsPair('size', 3),
      );
      expect(
        const RepoEdit(
          path: 'a',
          replacements: 2,
          appliedAtLine: 4,
        ).toJson()['appliedAtLine'],
        4,
      );
      expect(
        const TextMatch(
          path: 'a',
          line: 1,
          column: 2,
          text: 't',
          before: ['b'],
          after: ['c'],
        ).toJson(),
        allOf(containsPair('before', ['b']), containsPair('after', ['c'])),
      );
      expect(
        const GitStatusEntry(
          path: 'a',
          status: 'M ',
          staged: true,
        ).toJson()['staged'],
        isTrue,
      );
      expect(
        const GitCommit(
          hash: 'h',
          author: 'a',
          date: 'd',
          subject: 's',
        ).toJson()['subject'],
        's',
      );
      expect(
        const GitBlameLine(
          line: 1,
          hash: 'h',
          author: 'a',
          content: 'c',
        ).toJson()['line'],
        1,
      );
      expect(
        const GitResult(ok: true, output: 'o').toJson(),
        containsPair('ok', true),
      );
      expect(
        const RepoCapabilities(canWrite: true).toJson()['canWrite'],
        isTrue,
      );
    });
  });

  group('PermissionGuard', () {
    RepositoryAdapter guarded({RepoConfig config = const RepoConfig()}) =>
        PermissionGuard(
          InMemoryRepositoryAdapter({'a.txt': 'hello\nworld\n'}),
          config: config,
        );

    test('clamps capabilities to what the config permits', () {
      // Underlying InMemory reports canWrite: true; the guard masks it.
      expect(guarded().capabilities.canWrite, isFalse);
      expect(
        guarded(
          config: const RepoConfig(allowWrite: true),
        ).capabilities.canWrite,
        isTrue,
      );
    });

    test('read-only blocks every mutation', () {
      final a = guarded();
      final err = throwsA(isA<RepoPermissionException>());
      expect(() => a.write('b.txt', 'x'), err);
      expect(() => a.edit('a.txt', 'hello', 'hi'), err);
      expect(() => a.mkdir('d'), err);
      expect(() => a.move('a.txt', 'b.txt'), err);
      expect(() => a.delete('a.txt'), err);
    });

    test('reads always pass through', () async {
      final a = guarded();
      expect((await a.read('a.txt')).totalLines, 2);
      expect(await a.find(), contains('a.txt'));
    });

    test('requireLineMatch forces atLine on edits', () {
      final a = guarded(
        config: const RepoConfig(allowWrite: true, requireLineMatch: true),
      );
      expect(
        () => a.edit('a.txt', 'hello', 'hi'), // no atLine
        throwsA(isA<RepoPermissionException>()),
      );
    });

    test('git mutations gated independently of fs writes', () {
      // Writes allowed, git mutation not: the InMemory backend has no git, but
      // the guard must reject before delegating.
      final a = guarded(config: const RepoConfig(allowWrite: true));
      final err = throwsA(isA<RepoPermissionException>());
      expect(() => a.gitAdd(['a.txt']), err);
      expect(() => a.gitCommit('m'), err);
    });
  });
}
