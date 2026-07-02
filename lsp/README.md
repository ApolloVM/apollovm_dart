# ApolloVM tooling — Language Server

The ApolloVM **Language Server (LSP 3.17)** ships **inside the `apollovm`
package**, not as a separate package:

- Library: `package:apollovm/apollovm_lsp.dart` (separate from
  `package:apollovm/apollovm.dart`, which keeps its existing exports).
- Source: `lib/src/lsp/` — transport, protocol, analysis, server.
- CLI: `apollovm lsp` (a subcommand of `bin/apollovm.dart`) speaks LSP over stdio.
- Tests: `test/lsp/`.

**Web-safe:** the `apollovm_lsp` library imports no `dart:io`, so a browser-based
IDE or an AI agent can embed the server directly (see below).

This `lsp/` directory holds only the companion assets (excluded from the
published package via `../.pubignore`):

| Directory | What it is |
|-----------|------------|
| [`vscode/`](vscode/) | A minimal VS Code client that launches `apollovm lsp`. |
| [`example_workspace/`](example_workspace/) | Sample ApolloVM sources to try it against. |
| [`benchmark/`](benchmark/) | Latency harness for the performance targets. |

## Use it

**Local editor / CLI (stdio):**

```sh
dart pub get
dart run bin/apollovm.dart lsp     # speaks LSP over stdin/stdout
```

**Web IDE / AI agent (embedded, no stdio):** drive the server with decoded
JSON-RPC messages — no byte framing, no `dart:io`:

```dart
import 'package:apollovm/apollovm_lsp.dart';

final endpoint = MessageLspEndpoint((msg) => hostPort.send(msg)); // outgoing
final server = LspServer(endpoint);
// deliver each incoming JSON-RPC object from the host:
endpoint.receive(incomingMessage);
```

`StreamLspEndpoint` (byte streams + `Content-Length` framing) is also exported
for stdio/socket hosts, and is what `apollovm lsp` uses.

## Design in one paragraph

ApolloVM's AST carries **no source positions** and its parser **discards
comments**. Rather than thread source spans through all eight grammars (invasive,
regression-prone), the server keeps the ApolloVM core **read-only** and recovers
geometry in a small, self-contained scanner (`lib/src/lsp/analysis/token_index.dart`)
that re-scans the raw text for identifier/declaration positions, correlating them
to the AST — which stays the source of truth for *semantics*. Four strictly
separated layers keep **LSP logic out of the parser**: transport (JSON-RPC 2.0,
transport-agnostic), protocol (LSP 3.17 types), analysis (parse/index/resolve),
and server (handlers).

## Feature status

**Implemented (Dart):** `initialize`/`shutdown`, incremental diagnostics (parse +
unresolvable core imports), `documentSymbol`, `hover` (kind, signature, type,
documentation), `definition`. Plus working single-file `references`, `rename`,
and a basic `completion` with local→global ranking.

**Follow-up:** a static resolution/type pass for type-error diagnostics and
cross-package definition/references/rename; a workspace import graph; and
per-language enablement for the other seven ApolloVM languages (the analysis
layer is already language-agnostic).
