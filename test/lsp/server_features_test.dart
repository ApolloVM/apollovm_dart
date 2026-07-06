import 'dart:async';

import 'package:apollovm/apollovm_lsp.dart';
import 'package:test/test.dart';

const _uri = 'file:///ws/user.dart';
const _content = '''
/// A user.
class User {
  int id;
  String greet(String name) {
    return name;
  }
}

/// Builds an id.
int makeId(int seed) {
  return seed;
}
''';

/// A tiny in-process LSP client over [MessageLspEndpoint].
class _Client {
  final outgoing = <Map<String, Object?>>[];
  late final MessageLspEndpoint endpoint = MessageLspEndpoint(outgoing.add);
  var _id = 0;

  _Client() {
    LspServer(endpoint);
  }

  Future<Map<String, Object?>> request(
    String method, [
    Map<String, Object?>? params,
  ]) {
    final id = ++_id;
    endpoint.receive({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });
    return _waitFor((m) => m['id'] == id);
  }

  void notify(String method, Map<String, Object?> params) =>
      endpoint.receive({'jsonrpc': '2.0', 'method': method, 'params': params});

  Future<Map<String, Object?>> _waitFor(
    bool Function(Map<String, Object?>) pred,
  ) async {
    var seen = 0;
    for (var i = 0; i < 3000; i++) {
      while (seen < outgoing.length) {
        final m = outgoing[seen++];
        if (pred(m)) return m;
      }
      await Future<void>.delayed(Duration.zero);
    }
    throw StateError('message not received');
  }

  Future<void> open(String uri, String text) async {
    notify('textDocument/didOpen', {
      'textDocument': {'uri': uri, 'text': text},
    });
    await _waitFor(
      (m) =>
          m['method'] == 'textDocument/publishDiagnostics' &&
          (m['params'] as Map)['uri'] == uri,
    );
  }

  Map<String, Object?> pos(int line, int ch) => {'line': line, 'character': ch};
}

Map<String, Object?> _td(String uri) => {'uri': uri};

void main() {
  test('completion returns ranked symbols and keywords', () async {
    final c = _Client();
    await c.open(_uri, _content);
    final resp = await c.request('textDocument/completion', {
      'textDocument': _td(_uri),
      'position': c.pos(4, 6),
    });
    final result = resp['result'] as Map;
    final items = (result['items'] as List).cast<Map>();
    final labels = items.map((i) => i['label']).toSet();
    // Declared symbols from the AST.
    expect(labels, containsAll(['User', 'makeId', 'greet']));
    // Identifiers harvested from the token stream — locals/params the symbol
    // table omits, e.g. the `name` parameter and `seed`.
    expect(labels, containsAll(['name', 'seed']));
    expect(labels, contains('class')); // keyword
    // A harvested identifier is a variable (kind 6), ranked after symbols
    // (0_/1_) and before keywords.
    final nameItem = items.firstWhere((i) => i['label'] == 'name');
    expect(nameItem['kind'], 6);
    expect((nameItem['sortText'] as String).startsWith('2_'), isTrue);
    // Keywords sort last.
    final kw = items.firstWhere((i) => i['label'] == 'class');
    expect((kw['sortText'] as String).startsWith('3_'), isTrue);
  });

  test('completion still works when the buffer does not parse', () async {
    final c = _Client();
    // Missing `;` — the parse fails, so there are no AST symbols; completion
    // must fall back to identifiers harvested from the raw token stream.
    const broken =
        'int run() {\n'
        '  var greeting = 1;\n'
        '  var total = greeting\n' // no `;` -> parse error
        '}\n';
    await c.open(_uri, broken);
    final resp = await c.request('textDocument/completion', {
      'textDocument': _td(_uri),
      'position': c.pos(2, 22), // end of `greeting`
    });
    final items = ((resp['result'] as Map)['items'] as List).cast<Map>();
    final labels = items.map((i) => i['label']).toSet();
    expect(labels, containsAll(['greeting', 'total', 'run']));
  });

  test('references finds all same-name occurrences in the file', () async {
    final c = _Client();
    await c.open(_uri, _content);
    final resp = await c.request('textDocument/references', {
      'textDocument': _td(_uri),
      'position': c.pos(3, 24), // the `name` parameter
      'context': {'includeDeclaration': true},
    });
    final locs = (resp['result'] as List).cast<Map>();
    // `name` appears as the parameter and in `return name;`.
    expect(locs.length, 2);
    expect(locs.every((l) => l['uri'] == _uri), isTrue);
  });

  test('rename edits every same-name occurrence', () async {
    final c = _Client();
    await c.open(_uri, _content);
    final resp = await c.request('textDocument/rename', {
      'textDocument': _td(_uri),
      'position': c.pos(3, 24),
      'newName': 'label',
    });
    final changes = (resp['result'] as Map)['changes'] as Map;
    final edits = (changes[_uri] as List).cast<Map>();
    expect(edits.length, 2);
    expect(edits.every((e) => e['newText'] == 'label'), isTrue);
  });

  test('workspace/symbol matches declarations by query', () async {
    final c = _Client();
    await c.open(_uri, _content);
    final resp = await c.request('workspace/symbol', {'query': 'make'});
    final syms = (resp['result'] as List).cast<Map>();
    expect(syms.map((s) => s['name']), contains('makeId'));
  });

  test(
    'hover on a non-symbol identifier falls back to the bare name',
    () async {
      final c = _Client();
      await c.open(_uri, _content);
      final resp = await c.request('textDocument/hover', {
        'textDocument': _td(_uri),
        'position': c.pos(3, 24), // `name` param — not a collected symbol
      });
      final value = ((resp['result'] as Map)['contents'] as Map)['value'];
      expect(value, contains('`name`'));
    },
  );

  test(
    'definition returns null when nothing declares the identifier',
    () async {
      final c = _Client();
      await c.open(_uri, _content);
      final resp = await c.request('textDocument/definition', {
        'textDocument': _td(_uri),
        'position': c.pos(3, 24), // `name` has no declaration site
      });
      expect(resp['result'], isNull);
    },
  );

  test(
    'didChange re-analyzes; a new error is published, then cleared on close',
    () async {
      final c = _Client();
      await c.open(_uri, _content);
      c.notify('textDocument/didChange', {
        'textDocument': {'uri': _uri, 'version': 2},
        'contentChanges': [
          {'text': 'int broken( {\n'},
        ],
      });
      final bad = await c._waitFor(
        (m) =>
            m['method'] == 'textDocument/publishDiagnostics' &&
            (m['params'] as Map)['uri'] == _uri &&
            ((m['params'] as Map)['diagnostics'] as List).isNotEmpty,
      );
      expect(((bad['params'] as Map)['diagnostics'] as List), isNotEmpty);

      c.notify('textDocument/didClose', {'textDocument': _td(_uri)});
      final cleared = await c._waitFor(
        (m) =>
            m['method'] == 'textDocument/publishDiagnostics' &&
            (m['params'] as Map)['uri'] == _uri &&
            ((m['params'] as Map)['diagnostics'] as List).isEmpty,
      );
      expect(((cleared['params'] as Map)['diagnostics'] as List), isEmpty);
    },
  );

  test('an unknown request method yields a methodNotFound error', () async {
    final c = _Client();
    final resp = await c.request('foo/bar');
    final error = resp['error'] as Map;
    expect(error['code'], ResponseError.methodNotFound);
  });

  test('initialize advertises the new providers', () async {
    final c = _Client();
    final resp = await c.request('initialize');
    final caps = (resp['result'] as Map)['capabilities'] as Map;
    expect(caps['documentHighlightProvider'], isTrue);
    expect((caps['renameProvider'] as Map)['prepareProvider'], isTrue);
  });

  test('documentHighlight returns read occurrences of the name', () async {
    final c = _Client();
    await c.open(_uri, _content);
    final resp = await c.request('textDocument/documentHighlight', {
      'textDocument': _td(_uri),
      'position': c.pos(3, 24), // the `name` parameter
    });
    final highlights = (resp['result'] as List).cast<Map>();
    // `name` appears as the parameter and in `return name;`.
    expect(highlights.length, 2);
    // A parameter is not a tracked declaration, so both are Read.
    expect(
      highlights.every((h) => h['kind'] == DocumentHighlightKind.read),
      isTrue,
    );
  });

  test('documentHighlight marks a declaration occurrence as write', () async {
    final c = _Client();
    await c.open(_uri, _content);
    final resp = await c.request('textDocument/documentHighlight', {
      'textDocument': _td(_uri),
      'position': c.pos(9, 5), // `makeId`, a top-level function
    });
    final highlights = (resp['result'] as List).cast<Map>();
    expect(highlights, hasLength(1));
    expect(highlights.single['kind'], DocumentHighlightKind.write);
  });

  test('documentHighlight off any identifier is empty', () async {
    final c = _Client();
    await c.open(_uri, _content);
    final resp = await c.request('textDocument/documentHighlight', {
      'textDocument': _td(_uri),
      'position': c.pos(7, 0), // blank line between the two declarations
    });
    expect(resp['result'], isEmpty);
  });

  test('prepareRename returns the target range and placeholder', () async {
    final c = _Client();
    await c.open(_uri, _content);
    final resp = await c.request('textDocument/prepareRename', {
      'textDocument': _td(_uri),
      'position': c.pos(3, 24), // the `name` parameter
    });
    final result = resp['result'] as Map;
    expect(result['placeholder'], 'name');
    final range = Range.fromJson(result['range'] as Map<String, Object?>);
    expect(range.start.line, 3);
    expect(range.end.character - range.start.character, 'name'.length);
  });

  test('prepareRename off any identifier is null', () async {
    final c = _Client();
    await c.open(_uri, _content);
    final resp = await c.request('textDocument/prepareRename', {
      'textDocument': _td(_uri),
      'position': c.pos(7, 0),
    });
    expect(resp['result'], isNull);
  });

  group('all symbol categories/kinds', () {
    // A source exercising fields, a constructor, enum members and a top-level
    // variable, so the server's category/kind mappings are all hit.
    const richUri = 'file:///ws/rich.dart';
    const rich = '''
class Dog {
  int age;
  Dog(int a) { this.age = a; }
  int bark(int n) { return n; }
}
enum Color { red, green, blue }
int topVar = 3;
int makeAge(int seed) { return seed; }
''';

    Position posOf(String needle, {int occurrence = 1}) {
      final line = LineIndex(rich);
      var index = -1;
      for (var i = 0; i < occurrence; i++) {
        index = rich.indexOf(needle, index + 1);
      }
      return line.positionAt(index);
    }

    Map<String, Object?> posMap(String needle, {int occurrence = 1}) {
      final p = posOf(needle, occurrence: occurrence);
      return {'line': p.line, 'character': p.character};
    }

    test('documentSymbol maps variable and enum-member kinds', () async {
      final c = _Client();
      await c.open(richUri, rich);
      final resp = await c.request('textDocument/documentSymbol', {
        'textDocument': _td(richUri),
      });
      final roots = (resp['result'] as List).cast<Map>();
      final byName = {for (final s in roots) s['name']: s};

      expect(byName['topVar']?['kind'], SymbolKind.variable);
      final color = byName['Color']!;
      final members = (color['children'] as List).cast<Map>();
      expect(members.map((m) => m['name']), containsAll(['red', 'green']));
      expect(members.first['kind'], SymbolKind.enumMember);
    });

    test(
      'documentSymbol range spans a member body, not just its signature',
      () async {
        final c = _Client();
        await c.open(richUri, rich);
        final resp = await c.request('textDocument/documentSymbol', {
          'textDocument': _td(richUri),
        });
        final roots = (resp['result'] as List).cast<Map>();
        final byName = {for (final s in roots) s['name']: s};

        Range rangeOf(Map sym) =>
            Range.fromJson((sym['range'] as Map).cast<String, Object?>());
        Range selOf(Map sym) => Range.fromJson(
          (sym['selectionRange'] as Map).cast<String, Object?>(),
        );

        // Top-level function: the range must reach the closing brace on its line,
        // well past the name in `selectionRange`.
        final makeAge = byName['makeAge']!;
        expect(rangeOf(makeAge).end.line, selOf(makeAge).end.line);
        expect(
          rangeOf(makeAge).end.character,
          greaterThan(selOf(makeAge).end.character),
          reason: 'range should include the { return seed; } body',
        );

        // Method inside a class: same expectation for `bark`.
        final dog = byName['Dog']!;
        final bark = (dog['children'] as List).cast<Map>().firstWhere(
          (m) => m['name'] == 'bark',
        );
        expect(
          rangeOf(bark).end.character,
          greaterThan(selOf(bark).end.character),
          reason: 'method range should include its body',
        );
      },
    );

    test(
      'documentSymbol range skips named-parameter braces to reach the body',
      () async {
        // The `{ ... }` of Dart named parameters must not be mistaken for the
        // method body; the range should extend to the real body's closing brace.
        const named = '''
class Box {
  int add({int a = 1, int b = 2}) {
    return a + b;
  }
}
''';
        const namedUri = 'file:///ws/named.dart';
        final c = _Client();
        await c.open(namedUri, named);
        final resp = await c.request('textDocument/documentSymbol', {
          'textDocument': _td(namedUri),
        });
        final roots = (resp['result'] as List).cast<Map>();
        final box = roots.firstWhere((s) => s['name'] == 'Box');
        final add = (box['children'] as List).cast<Map>().firstWhere(
          (m) => m['name'] == 'add',
        );
        final range = Range.fromJson(
          (add['range'] as Map).cast<String, Object?>(),
        );
        // `named` line 3 (0-based) is the method's closing `  }`.
        expect(
          range.end.line,
          3,
          reason: 'range must reach the body brace, not the params brace',
        );
      },
    );

    test(
      'enum members after the constant list are parsed as real members',
      () async {
        // Everything after the `;` that ends the constant list — fields,
        // constructors, methods — must be recognized like class members (with
        // real kinds and full-body ranges), not swallowed as enum constants.
        const src = '''
enum Color {
  red, green, blue;

  final int code;
  const Color(this.code);

  int doubled() {
    return code * 2;
  }
}
''';
        const uri = 'file:///ws/enum.dart';
        final c = _Client();
        await c.open(uri, src);
        final resp = await c.request('textDocument/documentSymbol', {
          'textDocument': _td(uri),
        });
        final color = (resp['result'] as List).cast<Map>().firstWhere(
          (s) => s['name'] == 'Color',
        );
        final children = (color['children'] as List).cast<Map>();
        final byName = {for (final m in children) m['name']: m};

        // The three constants stay enum members.
        for (final name in ['red', 'green', 'blue']) {
          expect(byName[name]?['kind'], SymbolKind.enumMember);
        }
        // The trailing members get their real kinds — not enumMember.
        expect(byName['code']?['kind'], SymbolKind.field);
        expect(byName['Color']?['kind'], SymbolKind.constructor);
        expect(byName['doubled']?['kind'], SymbolKind.method);

        // The method's range spans its body (line 7 is the closing `  }`).
        final doubled = Range.fromJson(
          (byName['doubled']!['range'] as Map).cast<String, Object?>(),
        );
        expect(
          doubled.end.line,
          8,
          reason: 'enum method range must include its body',
        );
      },
    );

    test(
      'documentSymbol range covers expression bodies (class and enum)',
      () async {
        // `=> expr;` and Kotlin's brace-less `= expr` members must be fully
        // selectable: the range spans the expression, not just the signature.
        const src = '''
class Foo {
  int square(int n) => n * n;
  Map<int, int> pairs() => {1: 2, 3: 4};
}
enum Sign {
  pos, neg;
  int doubled() => index * 2;
}
class Calc {
  fun sum(a: Int, b: Int) = a + b
  fun run() {
    print(sum(1, 2));
  }
}
''';
        const uri = 'file:///ws/expr.dart';
        final c = _Client();
        await c.open(uri, src);
        final resp = await c.request('textDocument/documentSymbol', {
          'textDocument': _td(uri),
        });
        final roots = (resp['result'] as List).cast<Map>();

        Map childOf(String parent, String child) =>
            ((roots.firstWhere((s) => s['name'] == parent)['children'] as List)
                    .cast<Map>())
                .firstWhere((m) => m['name'] == child);
        Range rangeOf(Map m) =>
            Range.fromJson((m['range'] as Map).cast<String, Object?>());

        // Class `=> expr;` reaches past the `;` (line 1 ends at `;`).
        final square = rangeOf(childOf('Foo', 'square'));
        expect(square.end.line, 1);
        expect(square.end.character, greaterThan(28));

        // Map-literal body: balanced braces don't corrupt the following member.
        final pairs = rangeOf(childOf('Foo', 'pairs'));
        expect(pairs.end.line, 2);

        // Enum expression-body method includes its expression.
        final doubled = rangeOf(childOf('Sign', 'doubled'));
        expect(doubled.end.line, 6);
        expect(doubled.end.character, greaterThan(18));

        // Kotlin brace-less `= expr` is bounded to its own line and does not
        // swallow the next member — `run` is recognized with its own block body.
        final sum = rangeOf(childOf('Calc', 'sum'));
        expect(
          sum.end.line,
          9,
          reason: 'brace-less body must stop at its line',
        );
        final run = rangeOf(childOf('Calc', 'run'));
        expect(run.end.line, 12, reason: 'run keeps its own block body');
      },
    );

    test('completion maps every present symbol category', () async {
      final c = _Client();
      await c.open(richUri, rich);
      final resp = await c.request('textDocument/completion', {
        'textDocument': _td(richUri),
        'position': posMap('return n'), // inside bark's body
      });
      final items = ((resp['result'] as Map)['items'] as List).cast<Map>();
      final kinds = items.map((i) => i['kind']).toSet();
      // field (age), enum member (green), method (bark), function (makeAge),
      // class (Dog), enum (Color) are all present in the document.
      expect(
        kinds,
        containsAll([
          CompletionItemKind.field,
          CompletionItemKind.enumMember,
          CompletionItemKind.method,
          CompletionItemKind.function,
        ]),
      );
    });

    test('completion after `this.` proposes only the class members', () async {
      // `this.` leaves the buffer unparseable; completion must still surface
      // the enclosing class's members (with real kinds) and nothing else.
      const memberSrc = '''
class Dog {
  int age = 0;
  int legs = 4;
  int bark(int n) {
    this.
    return n;
  }
}
''';
      const memberUri = 'file:///ws/member.dart';
      final c = _Client();
      await c.open(memberUri, memberSrc);
      final resp = await c.request('textDocument/completion', {
        'textDocument': _td(memberUri),
        'position': {'line': 4, 'character': 9}, // right after `this.`
      });
      final items = ((resp['result'] as Map)['items'] as List).cast<Map>();
      final byName = {for (final i in items) i['label']: i['kind']};

      // Exactly the members of Dog, with their real kinds — no keywords, no
      // unrelated globals.
      expect(byName.keys, unorderedEquals(['age', 'legs', 'bark']));
      expect(byName['age'], CompletionItemKind.field);
      expect(byName['legs'], CompletionItemKind.field);
      expect(byName['bark'], CompletionItemKind.method);
    });

    test('completion offers local variables and parameters', () async {
      const localSrc = '''
class Dog {
  int bark(int n) {
    var local = 1;
    var x = 0;
    return n;
  }
}
''';
      const localUri = 'file:///ws/local.dart';
      final c = _Client();
      await c.open(localUri, localSrc);
      final resp = await c.request('textDocument/completion', {
        'textDocument': _td(localUri),
        'position': {'line': 4, 'character': 4}, // start of the `return` line
      });
      final items = ((resp['result'] as Map)['items'] as List).cast<Map>();
      final labels = items.map((i) => i['label']).toSet();
      // The local variable, a second local, and the parameter are all offered.
      expect(labels, containsAll(['local', 'x', 'n']));
    });

    test('hover labels a field and an enum member', () async {
      final c = _Client();
      await c.open(richUri, rich);

      final field = await c.request('textDocument/hover', {
        'textDocument': _td(richUri),
        'position': posMap('age'), // the `int age;` field
      });
      expect(
        ((field['result'] as Map)['contents'] as Map)['value'],
        contains('Field'),
      );

      final member = await c.request('textDocument/hover', {
        'textDocument': _td(richUri),
        'position': posMap('green'),
      });
      expect(
        ((member['result'] as Map)['contents'] as Map)['value'],
        contains('Enum value'),
      );
    });

    test('completion on an unopened document is empty', () async {
      final c = _Client();
      final resp = await c.request('textDocument/completion', {
        'textDocument': _td('file:///ws/never-opened.dart'),
        'position': {'line': 0, 'character': 0},
      });
      final result = resp['result'] as Map;
      expect(result['items'], isEmpty);
      expect(result['isIncomplete'], isFalse);
    });
  });
}
