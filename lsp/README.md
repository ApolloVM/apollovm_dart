# ApolloVM tooling — Language Server

This directory holds the ApolloVM Language Server and its companions. It is
development tooling and is excluded from the published `apollovm` package (see
`../.pubignore`).

| Directory | What it is |
|-----------|------------|
| [`apollovm_lsp/`](apollovm_lsp/) | The LSP 3.17 server (Dart). Transport, protocol, analysis, handlers. |
| [`vscode/`](vscode/) | A minimal VS Code client that launches the server. |
| [`example_workspace/`](example_workspace/) | Sample ApolloVM sources to try it against. |
| [`benchmark/`](benchmark/) | Latency harness for the performance targets. |

## Quick start

```sh
cd apollovm_lsp
dart pub get
dart analyze          # static analysis: clean
dart test             # unit + full protocol-session integration test
dart run bin/apollovm_lsp.dart   # the server, speaking LSP over stdio

cd ../benchmark && dart pub get && dart run bin/benchmark.dart
```

## Design in one paragraph

ApolloVM's AST is built for execution/translation: it carries **no source
positions** and its parser **discards comments**. Rather than thread source
spans through all eight grammars (invasive and regression-prone), the server
keeps the ApolloVM core **read-only** and recovers geometry in a small,
self-contained scanner (`apollovm_lsp/lib/src/analysis/token_index.dart`) that
re-scans the raw text for identifier and declaration positions, then correlates
them to the AST — which remains the source of truth for *semantics* (types,
signatures, modifiers). The four layers (transport / protocol / analysis /
server) are strictly separated, and **no LSP logic lives in the parser**.

## Feature status

**Implemented (Dart):** `initialize`/`shutdown`, incremental diagnostics
(parse + unresolved core imports), `documentSymbol`, `hover` (kind, signature,
type, documentation), `definition`. Plus working single-file `references`,
`rename`, and a basic `completion` with local→global ranking.

**Follow-up** (documented in the plan): a static resolution/type pass to enable
type-error diagnostics and cross-package definition/references/rename; a
workspace import graph; and per-language enablement for the other seven
ApolloVM languages (the analysis layer is already language-agnostic).
