import 'package:apollovm/apollovm_lsp.dart';

/// Example: driving the ApolloVM Language Server (LSP 3.17) with [LspClient].
///
/// `LspClient.inProcess()` spins up a client wired to a fresh [LspServer] in the
/// same isolate — no subprocess, no `dart:io` — so an editor, a web IDE or an AI
/// agent can embed the whole language server. For an out-of-process server,
/// wrap its transport instead, e.g. `LspClient(StreamLspEndpoint(out, in))`.
void main() async {
  final client = LspClient.inProcess();

  // Print diagnostics as the server publishes them.
  client.diagnostics.listen((d) {
    final where = d.uri.split('/').last;
    if (d.diagnostics.isEmpty) {
      print('[$where] no problems');
    } else {
      for (final problem in d.diagnostics) {
        print('[$where] ${problem.range.start}: ${problem.message}');
      }
    }
  });

  // 1) Handshake.
  final init = await client.initialize();
  print('Connected to ${init.serverInfo?.name} v${init.serverInfo?.version}');
  print('Capabilities: ${init.capabilities.keys.join(', ')}');
  client.initialized();

  print('---------------------------------------');

  // 2) Open a document. Diagnostics arrive on the stream above.
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
  client.didOpen(uri, source);
  await client.diagnostics.first; // wait for the first analysis

  print('---------------------------------------');

  // 3) Document outline.
  print('Symbols:');
  for (final s in await client.documentSymbol(uri)) {
    print('  • ${s.name}');
    for (final c in s.children) {
      print('      - ${c.name}  (${c.detail})');
    }
  }

  print('---------------------------------------');

  // 4) Hover over the `calc` method name. `positionOf` finds LSP
  //    {line, character} coordinates without hardcoding them.
  final hover = await client.hover(uri, positionOf(source, 'calc'));
  print('Hover at calc:\n${hover?.contents.value}');

  print('---------------------------------------');

  // 5) Go-to-definition of `calc` from its call site inside `run`.
  final def = await client.definition(
    uri,
    positionOf(source, 'calc', occurrence: 2),
  );
  print('Definition of `calc` (called in run): ${def?.range.start}');

  print('---------------------------------------');

  // 6) Completion proposals at the cursor.
  final completion = await client.completion(
    uri,
    positionOf(source, 'doubled'),
  );
  final labels = completion.items.take(6).map((i) => i.label).join(', ');
  print('Completion (${completion.items.length} items): $labels, …');

  print('---------------------------------------');

  // 7) Highlight every occurrence of `calc` (declaration = write, uses = read).
  final highlights = await client.documentHighlight(
    uri,
    positionOf(source, 'calc'),
  );
  final kinds = highlights
      .map((h) => h.kind == DocumentHighlightKind.write ? 'write' : 'read')
      .join(', ');
  print('Highlights for calc: ${highlights.length} ($kinds)');

  print('---------------------------------------');

  // 8) Validate a rename, then rename every occurrence of `calc` to `compute`.
  final prep = await client.prepareRename(uri, positionOf(source, 'calc'));
  print('prepareRename → renaming `${prep?.placeholder}` at ${prep?.range}');
  final edit = await client.rename(uri, positionOf(source, 'calc'), 'compute');
  final edits = edit?.changes[uri] ?? const [];
  print('Rename calc → compute: ${edits.length} edits');

  print('---------------------------------------');

  // 9) Break the source and watch diagnostics update.
  final broken = client.diagnostics.firstWhere((d) => d.diagnostics.isNotEmpty);
  client.didChange(uri, 'class Foo {\n  static int calc( {\n}\n', version: 2);
  await broken;

  print('---------------------------------------');

  // 10) Graceful shutdown.
  await client.shutdown();
  client.exit();
  await client.dispose();
  print('Session closed.');
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
