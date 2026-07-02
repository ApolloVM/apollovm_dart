# ApolloVM MCP Server

The ApolloVM MCP server exposes the VM's capabilities to AI agents as
[Model Context Protocol](https://modelcontextprotocol.io) tools, turning ApolloVM
into a programmable, sandboxed execution engine: parse, execute, translate,
compile, and inspect code across every supported language.

It is built on the official Dart [`dart_mcp`](https://pub.dev/packages/dart_mcp)
SDK and speaks MCP (`initialize` / `tools/list` / `tools/call`) over two
transports.

## The `mcp` command

All MCP functionality lives under the `apollovm mcp` command group:

| Subcommand | Purpose |
|------------|---------|
| `mcp serve` | Run the MCP server over stdio (default) or HTTP/SSE (`--http`). |
| `mcp list` | List the available tools (names/descriptions/input schemas) as JSON. |
| `mcp call <tool>` | Invoke one tool once and print its JSON result. |
| `mcp info` | Print server metadata (version, protocol, transports, languages, limits). |
| `mcp schema [tool]` | Print the JSON input schema(s) for one or all tools. |
| `mcp doctor` | Check the server/tools and report available capabilities. |

### `mcp serve`

```bash
# stdio (standard local transport)
apollovm mcp serve

# HTTP/SSE (networked agents) — binds 127.0.0.1:8080, SSE stream at /sse
apollovm mcp serve --http 8080 [--host 0.0.0.0]
```

Options (shared with `mcp call`):

| Option | Default | Meaning |
|--------|---------|---------|
| `--http <port>` | *(stdio)* | Serve over HTTP/SSE on this port instead of stdio. |
| `--host <host>` | `127.0.0.1` | Interface to bind for `--http`. |
| `--timeout-ms <n>` | `5000` | Per-execution wall-clock timeout. |
| `--max-output-chars <n>` | `65536` | Max captured console output per execution. |
| `--max-source-chars <n>` | `262144` | Max accepted source size. |
| `--isolate-tools <list>` | `apollo.execute` | Comma-separated tools to run in a killable isolate. |

### `mcp call`

Invoke a single tool from the shell — handy for scripting/CI without an MCP client.
Source is read from `--source`/`-s`, `--file`/`-f` (language inferred from the
extension), or stdin. Exit code is non-zero when the result `isError`.

```bash
apollovm mcp call apollo.execute --language dart \
  --source 'int main(List a){ print("hi"); return 42; }'

apollovm mcp call apollo.translate --from go --to dart --file main.go

echo 'int main(List a){ return 1; }' | apollovm mcp call apollo.parse -l dart
```

`apollo.execute` extras: `--function`, `--class-name`, `--args '<json array>'`.

### `mcp list` / `mcp schema` / `mcp info` / `mcp doctor`

```bash
apollovm mcp list                 # all tool definitions (JSON)
apollovm mcp schema apollo.wasm   # one tool's input schema (JSON)
apollovm mcp info [--json]        # server/version/protocol/languages/limits
apollovm mcp doctor               # environment & capability checks
```

### Embedding

```dart
import 'package:apollovm/apollovm_mcp.dart';

// stdio
final server = serveStdio(limits: const McpLimits(timeoutMs: 3000));
await server.done;

// HTTP/SSE
final transport = HttpSseTransport(limits: const McpLimits());
await transport.start(port: 8080);
```

You can also call the tool logic directly, without a transport, via
`computeTool(name, args, limits)` (in-process) or
`computeToolIsolated(name, args, limits)` (killable isolate).

## Tools

All tools return a single `TextContent` whose `text` is a JSON object. Every
payload includes an `isError` flag mirrored onto the MCP `CallToolResult.isError`.
Common inputs are `language` and `source` (inline source string).

Supported `language` values: `dart`, `java` (`java11`), `kotlin`, `go` (`golang`),
`csharp` (`cs`), `javascript` (`js`), `typescript` (`ts`), `lua`, `python` (`py`),
`wasm`.

### apollo.parse

Input: `{ language, source }`

Output:
```json
{
  "ok": true,
  "diagnostics": [],
  "summary": { "namespace": "", "classes": ["Foo"], "functions": ["main"], "imports": [] }
}
```

### apollo.execute

Input: `{ language, source, function?, className?, args?, timeoutMs? }`
(`function` defaults to `main`; `args` is a positional argument list.)

Output:
```json
{
  "result": 42,
  "hasResult": true,
  "output": ["hello"],
  "truncated": false,
  "diagnostics": []
}
```

`output` is the captured `print` stream. `truncated` is `true` when output hit
`maxOutputChars`. On timeout, `isError` is `true` with a "timed out" diagnostic.

### apollo.translate

Input: `{ from, to, source }`

Output: `{ "generated": "<source in the target language>", "diagnostics": [] }`

### apollo.ast

Input: `{ language, source, maxDepth? }`

Output: `{ "ast": <node> }` where each node is
`{ "node": "<runtimeType>", ...node-specific fields, "children": [...] }`.
Node-specific fields include names, `type`, `modifiers`, `returnType`,
`parameters`, class `kind`/`superClassName`/`implements`, import `path`, and
literal `value`s.

> **Note:** ApolloVM AST nodes carry no source positions (line/column), so none
> are emitted per node. Positions are available only in parse-error diagnostics.

### apollo.symbols

Input: `{ language, source }`

Output:
```json
{
  "symbols": {
    "namespace": "",
    "imports": [],
    "functions": [ { "name": "main", "returnType": {"name":"void"}, "modifiers": [], "parameters": [...] } ],
    "classes": [ { "name": "Foo", "kind": "normalClass", "fields": [...], "constructors": [...], "methods": [...] } ]
  }
}
```

### apollo.types

Input: `{ language, source }`

Output:
```json
{ "types": [ { "name": "Foo", "kind": "class" }, { "name": "int", "kind": "builtin" } ] }
```

`kind` is `class` (declared in the unit), `builtin`, or `unknown`.

### apollo.wasm

Input: `{ language, source }`

Output: `{ "modules": [ { "name": "mcp", "base64": "<wasm bytes>" } ] }`.
Each module's bytes are base64-encoded and begin with the `\0asm` magic
(`00 61 73 6D`).

## Security model

| Concern | Mechanism | Strength |
|---------|-----------|----------|
| File access | No file external is mapped; tools take inline source only | **Guaranteed** |
| Network access | No socket external is mapped | **Guaranteed** |
| Timeout / CPU | `apollo.execute` runs in a killable isolate (`Timer` + `Isolate.kill`) | **Enforced** |
| Input size | `maxSourceChars` | Enforced |
| Output size | `maxOutputChars` (truncates) | Enforced |
| Memory | Process-level only (`--old_gen_heap_size`) | **Best-effort** |

### Why isolate execution matters

ApolloVM executes CPU-bound work synchronously (its Dart dialect has no
async-yield primitive). An in-process `Future.timeout` therefore **cannot**
interrupt a runaway loop — the event loop is blocked and the timer never fires.
Running `apollo.execute` inside an isolate is the only reliable way to enforce a
hard timeout: the isolate is `kill()`-ed when the deadline passes. The pure,
bounded tools (`parse`/`ast`/`symbols`/`types`/`translate`/`wasm`) run in-process
by default; adjust with `--isolate-tools` / `McpLimits.isolateTools`.

Trade-off: on an isolate timeout/kill, console output produced before the kill is
not recovered (the result is reported as a timeout).

### HTTP/SSE exposure

The HTTP/SSE transport binds `127.0.0.1` by default. Exposing it on a public
interface grants unauthenticated code execution — front it with authentication
and TLS, and set an explicit `--host`, only in a trusted environment.

## Protocol notes

- Transport is newline-delimited JSON-RPC 2.0. Over HTTP/SSE the server follows
  the SSE transport: `GET /sse` opens the event stream and emits an
  `event: endpoint` frame naming the POST URL (`/message?sessionId=...`);
  `POST /message?sessionId=...` delivers one client→server message (returns
  `202 Accepted`) and responses stream back as `event: message` frames.
- The server advertises `serverInfo.name = "apollovm-mcp"` and
  `serverInfo.version = <ApolloVM.VERSION>`.
