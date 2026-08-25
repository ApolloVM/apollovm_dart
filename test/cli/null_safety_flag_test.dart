@TestOn('vm')
@Tags(['dart'])
library;

import 'dart:io';

import 'package:test/test.dart';

/// `--null-safety` on the source-file commands, exercised through the real CLI.
///
/// `CommandRun`/`CommandTranslate`/`CommandCompile` live in `bin/apollovm.dart`,
/// which a test cannot import, so these spawn the script. The contract under
/// test is user-facing anyway: the exit status and the printed report.
late Directory _tmp;

/// A nullable parameter used in arithmetic — a null-safety error.
const _bad = r'''
class Foo {
  static void main(int a, int? b) {
    print(a);
    var c = a + b;
    print(c);
  }
}
''';

const _clean = r'''
void main() {
  int? b = 7;
  print(b ?? 0);
}
''';

File _write(String name, String source) =>
    File('${_tmp.path}/$name')..writeAsStringSync(source);

Future<ProcessResult> _apollovm(List<String> args) => Process.run('dart', [
  'run',
  'bin/apollovm.dart',
  ...args,
], workingDirectory: Directory.current.path);

void main() {
  setUpAll(() {
    _tmp = Directory.systemTemp.createTempSync('apollovm_cli_ns');
  });

  tearDownAll(() {
    if (_tmp.existsSync()) _tmp.deleteSync(recursive: true);
  });

  group('--null-safety', () {
    test('is advertised by the source-file commands', () async {
      for (final command in const ['run', 'translate', 'compile']) {
        final r = await _apollovm([command, '--help']);
        expect(
          r.stdout.toString(),
          contains('--null-safety'),
          reason: '`$command --help` should list the flag',
        );
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    test(
      'rejects a null-safety error with a clean report and exit 1',
      () async {
        final file = _write('bad.dart', _bad);
        final r = await _apollovm(['run', '--null-safety', file.path]);

        expect(r.exitCode, 1);
        final out = '${r.stdout}${r.stderr}';
        expect(out, contains('NULL SAFETY'));
        expect(out, contains("The operand 'b' can be 'null'"));
        // A rejection is not a parse failure, and must not be restated as one.
        expect(out, isNot(contains("Can't parse source")));
        // Nothing ran, so nothing was printed by the program.
        expect(out, isNot(contains('\n5')));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('without the flag, the same source is not rejected', () async {
      final file = _write('bad2.dart', _bad);
      final r = await _apollovm(['run', file.path]);

      expect(r.exitCode, isNot(1));
      expect('${r.stdout}${r.stderr}', isNot(contains('NULL SAFETY')));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a clean program still runs with the flag on', () async {
      final file = _write('good.dart', _clean);
      final r = await _apollovm(['run', '--null-safety', file.path]);

      expect(r.exitCode, 0);
      expect(r.stdout.toString().trim(), '7');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('translate rejects the source too', () async {
      final file = _write('bad3.dart', _bad);
      final r = await _apollovm([
        'translate',
        '--null-safety',
        '--target=java',
        file.path,
      ]);

      expect(r.exitCode, 1);
      expect('${r.stdout}${r.stderr}', contains('NULL SAFETY'));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
