import 'package:apollovm/apollovm_lsp.dart';

/// Example: using the ApolloVM language features purely **via API** — no socket,
/// no stdio, no JSON-RPC handshake to run by hand.
///
/// [LspService] embeds an in-process server (web-safe: no `dart:io`) and exposes
/// a small, document-oriented API. This is the shape a browser IDE or an AI
/// agent wants: construct it, hand it code, ask questions.
void main() async {
  final lsp = LspService();

  const uri = 'file:///Foo.dart';
  const source = r'''
class Foo {
  /// Doubles [x] and adds [y].
  static int calc(int x, int y) {
    var doubled = x * 2;
    return doubled + y;
  }

  static int run() {
    return calc(10, 5);
  }
}
''';

  // 1) One-shot: analyze a buffer and get diagnostics directly.
  final diagnostics = await lsp.analyze(uri, source);
  print('Diagnostics: ${diagnostics.length} (source is clean)');

  // 2) Query language features against the current buffer — plain Dart calls.
  final hover = await lsp.hover(uri, positionOf(source, 'calc'));
  print('\nHover at calc:\n${hover?.contents.value}');

  final def = await lsp.definition(
    uri,
    positionOf(source, 'calc', occurrence: 2),
  );
  print('\nDefinition of calc (called in run): ${def?.range.start}');

  final symbols = await lsp.documentSymbols(uri);
  print('\nOutline:');
  for (final s in symbols) {
    print('  • ${s.name}');
    for (final c in s.children) {
      print('      - ${c.name}');
    }
  }

  final edit = await lsp.rename(uri, positionOf(source, 'calc'), 'compute');
  print('\nRename calc → compute: ${edit?.changes[uri]?.length} edits');

  // 3) Edit the buffer and re-check — no reopen, no protocol dance.
  final broken = await lsp.analyze(uri, 'class Foo {\n  int calc( {\n}\n');
  print('\nAfter breaking the source: ${broken.length} problem(s)');
  for (final d in broken) {
    print('  ✗ ${d.range.start}: ${d.message}');
  }

  await lsp.dispose();
  print('\nDone.');
}

/// Returns the LSP `{line, character}` [Position] (both zero-based) of the
/// [occurrence]-th appearance of [needle] in [text].
Position positionOf(String text, String needle, {int occurrence = 1}) {
  var index = -1;
  for (var i = 0; i < occurrence; i++) {
    index = text.indexOf(needle, index + 1);
    if (index < 0) throw ArgumentError('Not found: $needle (#$occurrence)');
  }
  var line = 0, lineStart = 0;
  for (var i = 0; i < index; i++) {
    if (text.codeUnitAt(i) == 0x0A) {
      line++;
      lineStart = i + 1;
    }
  }
  return Position(line, index - lineStart);
}
