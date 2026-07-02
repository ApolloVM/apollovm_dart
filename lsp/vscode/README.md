# ApolloVM Language Server — VS Code extension

A thin LSP client that launches the ApolloVM language server
(`../apollovm_lsp/bin/apollovm_lsp.dart`) and wires it to VS Code.

## Develop / try it

Prerequisites: the [Dart SDK](https://dart.dev/get-dart) on `PATH` and Node.js.

```sh
# 1. Prepare the server package.
cd ../apollovm_lsp && dart pub get && cd ../vscode

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
| `apollovmLsp.serverEntrypoint` | *(sibling package)* | Absolute path to `bin/apollovm_lsp.dart`. |

> Note: on files with the `dart` language id, VS Code's official Dart extension
> may also be active. Disable it in the dev host if you want to see only the
> ApolloVM server's contributions.
