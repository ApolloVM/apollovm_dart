# ApolloVM Language Server — VS Code extension

A thin LSP client that starts the ApolloVM language server via the
`apollovm lsp` subcommand (the server ships inside the `apollovm` package) and
wires it to VS Code.

## Develop / try it

Prerequisites: the [Dart SDK](https://dart.dev/get-dart) on `PATH` and Node.js.

```sh
# 1. Prepare the apollovm package (repo root).
cd ../.. && dart pub get && cd lsp/vscode

# 2. Install the client dependency.
npm install

# 3. Launch the Extension Development Host.
code .
# then press F5, and open ../example_workspace/ in the new window.
```

In the development host, open `example_workspace/models.dart` and try:

- **Diagnostics** — introduce a syntax error and watch it underline.
- **Hover** — hover `findUser` to see `User findUser(int id)` and its doc.
- **Outline** — the breadcrumb / Outline view shows classes and members.
- **Go to Definition** — F12 on a symbol jumps to its declaration.

## Configuration

| Setting | Default | Meaning |
|---|---|---|
| `apollovmLsp.dartExecutable` | `dart` | Dart SDK executable used to launch the server. |
| `apollovmLsp.serverEntrypoint` | *(repo-root `bin/apollovm.dart`)* | Path to the apollovm CLI, started as `apollovm lsp`. |

> Note: on files with the `dart` language id, VS Code's official Dart extension
> may also be active. Disable it in the dev host if you want to see only the
> ApolloVM server's contributions.
