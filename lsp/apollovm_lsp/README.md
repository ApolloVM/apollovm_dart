# apollovm_lsp

A [Language Server Protocol](https://microsoft.github.io/language-server-protocol/)
(LSP 3.17+) server for [ApolloVM](https://pub.dev/packages/apollovm) source code.

It provides editors with diagnostics, hover, go-to-definition, and document
symbols over ApolloVM-supported languages (Dart first; more to follow).

## Architecture

The server is split into four layers with no cross-contamination — in
particular, **no LSP logic lives inside the ApolloVM parser**:

| Layer | Directory | Responsibility |
|-------|-----------|----------------|
| Transport | `lib/src/transport/` | JSON-RPC 2.0 over stdio (`Content-Length` framing). |
| Protocol | `lib/src/protocol/` | LSP 3.17 message/param data classes. |
| Analysis | `lib/src/analysis/` | Parse (via `package:apollovm`), index positions, resolve symbols. |
| Server | `lib/src/server/` | Glue: maps analysis results to protocol responses. |

### Why a separate position index?

ApolloVM's AST is built for execution/translation and carries **no source
positions**, and its parser discards comments. Rather than thread source spans
through all eight grammars (invasive, regression-prone), this package re-scans
the raw source in a small, self-contained scanner (`analysis/token_index.dart`)
and correlates identifiers/declarations back to the AST by name and scope. The
ApolloVM core is used read-only and never modified.

## Run

```sh
dart pub get
dart run bin/apollovm_lsp.dart   # speaks LSP over stdin/stdout
```

See `../vscode/` for a VS Code client, `../example_workspace/` for sample
sources, and `../benchmark/` for the performance harness.

## Status

Implemented: `initialize`/`shutdown`, incremental diagnostics (parse + import),
`documentSymbol`, `hover`, `definition`.
Scaffolded (follow-up): `completion`, `references`, `rename`, `workspaceSymbol`,
and type-error diagnostics (needs a static resolution pass — see the plan).
