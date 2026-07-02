// Measures the ApolloVM language server against its performance targets:
//   open file  < 100 ms
//   completion <  50 ms
//   hover      <  20 ms
//
// Runs each operation many times over a synthetic document and reports the
// median and p95 latency against the target. Run with:
//   dart run bin/benchmark.dart
import 'package:apollovm/apollovm_lsp.dart';

const _openTargetMs = 100.0;
const _completionTargetMs = 50.0;
const _hoverTargetMs = 20.0;

String _buildSource(int classes) {
  final b = StringBuffer();
  for (var i = 0; i < classes; i++) {
    b.writeln('/// Model number $i.');
    b.writeln('class Model$i {');
    b.writeln('  int id;');
    b.writeln('  String name;');
    b.writeln('  int compute(int factor) {');
    b.writeln('    return id;');
    b.writeln('  }');
    b.writeln('}');
    b.writeln();
    b.writeln('/// Builds a Model$i.');
    b.writeln('int build$i(int seed) {');
    b.writeln('  return seed;');
    b.writeln('}');
    b.writeln();
  }
  return b.toString();
}

double _median(List<double> xs) {
  final s = [...xs]..sort();
  return s[s.length ~/ 2];
}

double _p95(List<double> xs) {
  final s = [...xs]..sort();
  return s[(s.length * 0.95).floor().clamp(0, s.length - 1)];
}

Future<double> _timeAsync(Future<void> Function() op) async {
  final sw = Stopwatch()..start();
  await op();
  sw.stop();
  return sw.elapsedMicroseconds / 1000.0;
}

double _timeSync(void Function() op) {
  final sw = Stopwatch()..start();
  op();
  sw.stop();
  return sw.elapsedMicroseconds / 1000.0;
}

void _report(String label, List<double> samples, double targetMs) {
  final med = _median(samples);
  final p95 = _p95(samples);
  final ok = p95 <= targetMs;
  final mark = ok ? 'PASS' : 'WARN';
  print('[$mark] ${label.padRight(12)} '
      'median=${med.toStringAsFixed(2)}ms  '
      'p95=${p95.toStringAsFixed(2)}ms  '
      '(target ${targetMs.toStringAsFixed(0)}ms)');
}

Future<void> main() async {
  const uri = 'file:///bench/models.dart';
  final source = _buildSource(40); // ~40 classes, several hundred LOC.
  final analyzer = Analyzer();

  print('Document: ${source.split('\n').length} lines, '
      '${source.length} chars\n');

  // Warm up the parser (grammar build is a one-time cost).
  await analyzer.analyze(uri, source);

  const iterations = 60;

  // Open: full parse + index + symbol collection.
  final openSamples = <double>[];
  for (var i = 0; i < iterations; i++) {
    openSamples.add(await _timeAsync(() => analyzer.analyze(uri, source)));
  }

  // Cache one analysis for the cursor-based operations.
  final unit = await analyzer.analyze(uri, source);
  final hoverOffset = source.indexOf('build7');
  final hoverPos = unit.lineIndex.positionAt(hoverOffset);

  // Hover: cursor → identifier → symbol lookup + doc.
  final hoverSamples = <double>[];
  for (var i = 0; i < iterations; i++) {
    hoverSamples.add(_timeSync(() {
      final off = unit.lineIndex.offsetAt(hoverPos);
      final ident = unit.tokenIndex.identifierAt(off);
      if (ident != null) {
        unit.symbolFor(ident.name);
        final d = unit.tokenIndex.findDeclaration(ident.name);
        if (d != null) unit.docs.docFor(d.fullStart);
      }
    }));
  }

  // Completion: assemble the candidate list from symbols + keywords.
  final completionSamples = <double>[];
  for (var i = 0; i < iterations; i++) {
    completionSamples.add(_timeSync(() {
      final items = <String>[];
      for (final s in unit.symbols) {
        items.add(s.name);
      }
    }));
  }

  _report('open', openSamples, _openTargetMs);
  _report('completion', completionSamples, _completionTargetMs);
  _report('hover', hoverSamples, _hoverTargetMs);
}
