// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

/// Path/glob/line helpers shared by the [RepositoryAdapter] implementations.
/// Web-safe (no `dart:io`).
library;

import 'repository_adapter.dart';

/// Normalizes a workspace-relative [path] to POSIX form: `\` → `/`, collapse
/// `//`, strip a leading `./` and any leading/trailing `/`. Throws a
/// [RepoException] if it escapes the root via `..` or is absolute.
String normalizeRepoPath(String path) {
  var p = path.replaceAll('\\', '/').trim();
  if (p.startsWith('/')) {
    throw RepoException('Absolute paths are not allowed: $path');
  }
  final parts = <String>[];
  for (final seg in p.split('/')) {
    if (seg.isEmpty || seg == '.') continue;
    if (seg == '..') {
      throw RepoException('Path escapes the workspace root: $path');
    }
    parts.add(seg);
  }
  return parts.join('/');
}

/// Compiles a glob pattern to a [RegExp] anchored to a full workspace-relative
/// path. Supports `*` (not crossing `/`), `**` (crossing `/`), `?`, and
/// character classes `[...]`.
RegExp globToRegExp(String glob) {
  final sb = StringBuffer('^');
  final chars = glob.split('');
  for (var i = 0; i < chars.length; i++) {
    final c = chars[i];
    switch (c) {
      case '*':
        if (i + 1 < chars.length && chars[i + 1] == '*') {
          // `**` — match across path separators.
          i++;
          // Consume an optional following `/` so `**/x` also matches `x`.
          if (i + 1 < chars.length && chars[i + 1] == '/') {
            i++;
            sb.write('(?:.*/)?');
          } else {
            sb.write('.*');
          }
        } else {
          sb.write('[^/]*');
        }
      case '?':
        sb.write('[^/]');
      case '[':
        // Pass a character class through verbatim up to the closing `]`.
        final close = glob.indexOf(']', i);
        if (close == -1) {
          sb.write(r'\[');
        } else {
          sb.write(glob.substring(i, close + 1));
          i = close;
        }
      case '.':
      case '(':
      case ')':
      case '+':
      case '|':
      case '^':
      case r'$':
      case '{':
      case '}':
      case '\\':
        sb.write('\\$c');
      default:
        sb.write(c);
    }
  }
  sb.write(r'$');
  return RegExp(sb.toString());
}

/// Whether [path] matches [glob] (null glob matches everything).
bool matchesGlob(String path, String? glob) =>
    glob == null || glob.isEmpty || globToRegExp(glob).hasMatch(path);

/// Splits [content] into lines, preserving a trailing empty line only when the
/// content ends without a newline is irrelevant to callers — this returns the
/// logical lines for counting/slicing.
List<String> splitLines(String content) {
  if (content.isEmpty) return const [];
  final lines = content.split('\n');
  // A trailing newline yields a final empty element; drop it so the count is
  // the number of textual lines.
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  return lines;
}

/// Returns the 1-based inclusive [range] slice of [content] as text, or the
/// whole content when [range] is null. Clamps to the available lines.
({String text, int totalLines}) sliceLines(String content, LineRange? range) {
  final lines = splitLines(content);
  final total = lines.length;
  if (range == null) return (text: content, totalLines: total);
  final start = range.start < 1 ? 1 : range.start;
  final end = range.end == null || range.end! > total ? total : range.end!;
  if (start > total || end < start) return (text: '', totalLines: total);
  return (text: lines.sublist(start - 1, end).join('\n'), totalLines: total);
}

/// Applies a string-replacement edit to [content], honoring [atLine] (1-based)
/// and [replaceAll]. Returns the new content and the number of replacements, or
/// throws a [RepoException] on a mismatch.
({String content, int replacements, int? appliedAtLine}) applyEdit(
  String content,
  String oldString,
  String newString, {
  bool replaceAll = false,
  int? atLine,
}) {
  if (oldString.isEmpty) {
    throw const RepoException('`oldString` must not be empty.');
  }

  if (atLine != null) {
    final lines = content.split('\n');
    if (atLine < 1 || atLine > lines.length) {
      throw RepoException(
        'atLine $atLine is out of range (file has ${lines.length} lines).',
      );
    }
    final idx = atLine - 1;
    final originalLine = lines[idx];
    final onLine = _countOccurrences(originalLine, oldString);
    if (onLine == 0) {
      throw RepoException(
        'oldString does not occur on line $atLine — refusing the edit.',
      );
    }
    if (!replaceAll && onLine > 1) {
      throw RepoException(
        'oldString occurs $onLine times on line $atLine; pass replaceAll or a '
        'more specific string.',
      );
    }
    lines[idx] = replaceAll
        ? originalLine.replaceAll(oldString, newString)
        : originalLine.replaceFirst(oldString, newString);
    return (
      content: lines.join('\n'),
      replacements: replaceAll ? onLine : 1,
      appliedAtLine: atLine,
    );
  }

  final occurrences = _countOccurrences(content, oldString);
  if (occurrences == 0) {
    throw const RepoException('oldString not found in file.');
  }
  if (!replaceAll && occurrences > 1) {
    throw RepoException(
      'oldString occurs $occurrences times; pass replaceAll or a more specific '
      'string (or pin the line with atLine).',
    );
  }
  final updated = replaceAll
      ? content.replaceAll(oldString, newString)
      : content.replaceFirst(oldString, newString);
  return (
    content: updated,
    replacements: replaceAll ? occurrences : 1,
    appliedAtLine: null,
  );
}

int _countOccurrences(String haystack, String needle) {
  if (needle.isEmpty) return 0;
  var count = 0;
  var i = haystack.indexOf(needle);
  while (i != -1) {
    count++;
    i = haystack.indexOf(needle, i + needle.length);
  }
  return count;
}
