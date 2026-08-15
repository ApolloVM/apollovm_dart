@TestOn('vm')
@Tags(['dart'])
library;

import 'dart:io';

import 'package:test/test.dart';

/// `compile --target=ast` and running the resulting image, through the real CLI.
///
/// `CommandRun`/`CommandCompile` live in `bin/apollovm.dart`, which a test
/// cannot import, so these spawn the script — and the contract under test is
/// user-facing anyway: what lands on disk, and what the program prints.
late Directory _tmp;

/// A kernel snapshot of the CLI, compiled once into this suite's own temp
/// directory.
///
/// `dart run bin/apollovm.dart` compiles through a cache shared with every
/// other process doing the same, and two suites spawning it concurrently
/// contend on that cache — which shows up as an empty stdout and a non-zero
/// exit, not as a timeout. Compiling once here keeps this suite independent of
/// whatever else the runner has in flight.
late String _cliSnapshot;

const _source = r'''
class Calc {
  int sum(List<int> ns) {
    var total = 0;
    for (var n in ns) {
      total = total + n;
    }
    return total;
  }

  static void main(List<String> args) {
    var c = Calc();
    print('total: ${c.sum([1, 2, 3, 4])}');
  }
}
''';

File _write(String name, String source) =>
    File('${_tmp.path}/$name')..writeAsStringSync(source);

Future<ProcessResult> _apollovm(List<String> args) => Process.run('dart', [
  _cliSnapshot,
  ...args,
], workingDirectory: Directory.current.path);

void main() {
  setUpAll(() {
    _tmp = Directory.systemTemp.createTempSync('apollovm_cli_astb');

    _cliSnapshot = '${_tmp.path}/apollovm.dill';
    var compiled = Process.runSync('dart', [
      'compile',
      'kernel',
      'bin/apollovm.dart',
      '-o',
      _cliSnapshot,
    ], workingDirectory: Directory.current.path);

    expect(
      compiled.exitCode,
      0,
      reason: 'Could not compile the CLI: ${compiled.stderr}',
    );
  });

  tearDownAll(() {
    if (_tmp.existsSync()) _tmp.deleteSync(recursive: true);
  });

  group('compile --target=ast', () {
    test('is advertised by `compile --help`', () async {
      final r = await _apollovm(['compile', '--help']);
      expect(r.stdout.toString(), contains('wasm|ast'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('writes an image next to the source, and `run` executes it', () async {
      final source = _write('calc.dart', _source);

      final compiled = await _apollovm([
        'compile',
        '--target=ast',
        source.path,
      ]);
      expect(compiled.exitCode, 0, reason: '${compiled.stderr}');

      final image = File('${_tmp.path}/calc.avma');
      expect(image.existsSync(), isTrue, reason: 'No image was written');

      // `\0AVM`: binary, and not mistakable for text.
      expect(
        image.readAsBytesSync().sublist(0, 4),
        equals([0x00, 0x41, 0x56, 0x4D]),
      );

      // Detected by its magic rather than its extension, so the recorded
      // language is what decides the runner.
      final ran = await _apollovm(['run', '-v', image.path]);
      expect(ran.exitCode, 0, reason: '${ran.stderr}');
      expect(ran.stdout.toString(), contains('total: 10'));
      expect(ran.stdout.toString(), contains('binary AST'));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('honours -o', () async {
      final source = _write('calc2.dart', _source);
      final target = '${_tmp.path}/nested-name.bin';

      final r = await _apollovm([
        'compile',
        '--target=ast',
        '-o',
        target,
        source.path,
      ]);

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(File(target).existsSync(), isTrue);

      // Still recognized by content, whatever it was named.
      final ran = await _apollovm(['run', target]);
      expect(ran.exitCode, 0, reason: '${ran.stderr}');
      expect(ran.stdout.toString(), contains('total: 10'));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('rejects an unknown target', () async {
      final source = _write('calc3.dart', _source);
      final r = await _apollovm(['compile', '--target=nope', source.path]);

      expect(r.exitCode, isNot(0));
      expect('${r.stdout}${r.stderr}', contains('Unsupported compile target'));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
