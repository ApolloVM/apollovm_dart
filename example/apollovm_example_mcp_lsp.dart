import 'dart:convert';

import 'package:apollovm/apollovm_mcp.dart';

/// Example: an AI agent inspecting code through the MCP `apollovm.lsp.*` tools.
///
/// These are the exact tool calls an MCP client (an LLM agent) makes over the
/// wire — here invoked directly via [computeTool] with a plain args map. Each is
/// stateless and web-safe: no socket, no `dart:io`, no editor.
void main() async {
  const limits = McpLimits();
  final pretty = JsonEncoder.withIndent('  ');

  const source = '''
class Account {
  double balance;

  /// Deposits [amount] into the account.
  void deposit(double amount) {
    balance = balance + amount;
  }

  void report() {
    deposit(10.0);
  }
}
''';

  Future<void> callTool(String tool, Map<String, Object?> args) async {
    final result = await computeTool(tool, args, limits);
    print('\n>>> $tool');
    print(pretty.convert(result));
  }

  // 1) Diagnostics — is the code valid? (precise LSP ranges)
  await callTool('apollovm.lsp.diagnostics', {
    'language': 'dart',
    'source': source,
  });

  // 2) Outline — what does this file define?
  await callTool('apollovm.lsp.symbols', {
    'language': 'dart',
    'source': source,
  });

  // 3) Hover — what is `deposit`? (signature + doc), at its declaration.
  await callTool('apollovm.lsp.hover', {
    'language': 'dart',
    'source': source,
    'line': 4,
    'character': 7,
  });

  // 4) References — where is `deposit` used?
  await callTool('apollovm.lsp.references', {
    'language': 'dart',
    'source': source,
    'line': 4,
    'character': 7,
  });

  // 5) Workspace symbols — search a whole (in-memory) codebase.
  await callTool('apollovm.lsp.workspaceSymbols', {
    'query': 'account',
    'files': [
      {'uri': 'file:///lib/account.dart', 'source': source},
      {
        'uri': 'file:///lib/bank.py',
        'language': 'python',
        'source': 'def open_account():\n  return 1\n',
      },
    ],
  });
}
