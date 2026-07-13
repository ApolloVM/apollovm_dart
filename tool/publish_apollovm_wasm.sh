#!/usr/bin/env bash
#
# Publishes the `apollovm_wasm` sub-package.
#
# `apollovm_wasm/` lives inside the `apollovm` package root, and the root
# `.pubignore` excludes it so it is not packed into the `apollovm` archive. But
# pub evaluates ignore rules from the git-repo root, so that same rule hides the
# sub-package from *its own* publish — it fails with "the pubspec is hidden".
# A nested package cannot be excluded from one archive but not the other.
#
# So: drop the rule, publish, put it back. The trap is restoring it, which is
# why this is a script and not a note in a README.
#
# Usage:  tool/publish_apollovm_wasm.sh [--dry-run|--force]
set -euo pipefail

# Absolute: the restore trap fires after `cd apollovm_wasm`, so a relative path
# would rewrite the wrong file.
readonly ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly PUBIGNORE="$ROOT/.pubignore"
readonly RULE='/apollovm_wasm/'

if ! grep -qxF "$RULE" "$PUBIGNORE"; then
  echo "error: '$RULE' not found in $PUBIGNORE — did the layout change?" >&2
  exit 1
fi

backup="$(mktemp)"
readonly backup
cp "$PUBIGNORE" "$backup"
# Restore on ANY exit path, including a failed publish or a Ctrl-C.
trap 'cp "$backup" "$PUBIGNORE"; rm -f "$backup"; echo "-- restored $PUBIGNORE"' EXIT

grep -vxF "$RULE" "$backup" > "$PUBIGNORE"
echo "-- temporarily removed '$RULE' from $PUBIGNORE"

cd "$ROOT/apollovm_wasm"
dart pub publish "$@"
