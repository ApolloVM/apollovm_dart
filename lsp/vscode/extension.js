// Minimal VS Code client for the ApolloVM language server. It launches the Dart
// server (`bin/apollovm_lsp.dart`) as a child process and speaks LSP over stdio.
const path = require('path');
const { workspace, window } = require('vscode');
const { LanguageClient, TransportKind } = require('vscode-languageclient/node');

let client;

const LANGUAGES = [
  'dart', 'java', 'kotlin', 'csharp',
  'javascript', 'typescript', 'lua', 'python',
];

function activate(context) {
  const config = workspace.getConfiguration('apollovmLsp');
  const dartExe = config.get('dartExecutable') || 'dart';

  // Default the server entrypoint to the sibling apollovm_lsp package.
  const packageDir = path.join(context.extensionPath, '..', 'apollovm_lsp');
  const entrypoint =
    config.get('serverEntrypoint') || path.join(packageDir, 'bin', 'apollovm_lsp.dart');

  const serverOptions = {
    run: {
      command: dartExe,
      args: ['run', entrypoint],
      transport: TransportKind.stdio,
      options: { cwd: packageDir },
    },
    debug: {
      command: dartExe,
      args: ['run', entrypoint],
      transport: TransportKind.stdio,
      options: { cwd: packageDir },
    },
  };

  const clientOptions = {
    documentSelector: LANGUAGES.map((language) => ({ scheme: 'file', language })),
    synchronize: {
      fileEvents: workspace.createFileSystemWatcher(
        '**/*.{dart,java,kt,cs,js,ts,lua,py}'
      ),
    },
  };

  client = new LanguageClient(
    'apollovmLsp',
    'ApolloVM Language Server',
    serverOptions,
    clientOptions
  );

  client.start().catch((err) => {
    window.showErrorMessage(`ApolloVM LSP failed to start: ${err}`);
  });
}

function deactivate() {
  return client ? client.stop() : undefined;
}

module.exports = { activate, deactivate };
