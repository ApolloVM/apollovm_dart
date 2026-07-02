// This file intentionally contains a syntax error so the language server
// reports a parse diagnostic. The missing `)` on `sum(` is the culprit.
int sum(int a, int b {
  return a + b;
}
