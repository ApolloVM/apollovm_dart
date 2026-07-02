import 'package:apollovm/apollovm.dart';

/// Demonstrates ApolloVM's language-agnostic module import system: three Dart
/// modules where `main` imports a `User` class (via `show`) and a `shout`
/// helper (via a prefix alias `h`) from sibling modules, resolved and executed
/// entirely in memory.
///
/// The sources here are inlined as strings so this example is **web-safe**
/// (no `dart:io`). To load them from disk instead (VM/desktop only), read each
/// file with `File(...).readAsString()` and pass the contents to
/// `SourceCodeUnit(..., id: '<path>')` — the `id` is the module identifier used
/// to resolve imports. See `example/import_project/*.dart` for the same code as
/// standalone files.
void main() async {
  var vm = ApolloVM();

  await vm.loadCodeUnit(SourceCodeUnit('dart', r'''
class User {
  String name;
  User(this.name);
  String greet() {
    return 'Hi ' + name;
  }
}
''', id: 'user.dart'));

  await vm.loadCodeUnit(SourceCodeUnit('dart', r'''
String shout(String s) {
  return s.toUpperCase();
}
''', id: 'helpers.dart'));

  await vm.loadCodeUnit(SourceCodeUnit('dart', r'''
import 'user.dart' show User;
import 'helpers.dart' as h;

void run() {
  var u = User('bob');
  var greeting = u.greet();
  print(greeting);
  print(h.shout(greeting));
}
''', id: 'main.dart'));

  print('--- Resolving module graph ---');
  var diagnostics = vm.resolve(language: 'dart');
  if (diagnostics.isEmpty) {
    print('No diagnostics: all imports resolved.');
  } else {
    for (var d in diagnostics) {
      print(d);
    }
  }

  print('--- Running main.run() ---');
  var runner = vm.createRunner('dart')!;
  runner.externalPrintFunction = (o) => print('» $o');
  await runner.executeFunction('', 'run', positionalParameters: []);

  print('--- Regenerated Dart (round-trip) ---');
  var sources = await vm.generateAllCodeIn('dart').writeAllSources();
  print(sources);
}

/////////////
// OUTPUT: //
/////////////
// --- Resolving module graph ---
// No diagnostics: all imports resolved.
// --- Running main.run() ---
// » Hi bob
// » HI BOB
// --- Regenerated Dart (round-trip) ---
// ... (user.dart, helpers.dart, main.dart with `import 'user.dart' show User;`
//      and `import 'helpers.dart' as h;` preserved) ...
