# Example workspace

Sample ApolloVM Dart sources for exercising the language server.

| File | Demonstrates |
|------|--------------|
| `models.dart` | A class with fields and a method, a top-level function, doc comments (hover). |
| `orders.dart` | An `enum` with members plus a class (document symbols / outline). |
| `.broken.dart` | A deliberate syntax error (parse diagnostics). |

Open this folder in the VS Code Extension Development Host (see `../vscode/`)
and try hover, outline, go-to-definition, and diagnostics.

`.broken.dart` keeps its leading dot on purpose: `dart format` and the Dart
analyzer skip dot-prefixed paths, so `dart format .` and `dart analyze` at the
repository root stay clean while the file remains a `.dart` source that the
editor hands to the ApolloVM language server. Don't rename it to
`broken.dart` — that breaks both commands. The `analysis_options.yaml` here
silences the remaining fixture diagnostics for the same reason.
