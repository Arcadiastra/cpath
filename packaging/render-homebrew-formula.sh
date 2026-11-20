#!/usr/bin/env bash
set -euo pipefail
unset CDPATH

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEMPLATE="$ROOT_DIR/packaging/homebrew/cpath.rb.tmpl"

VERSION="${1:-}"
VERSION="${VERSION#v}"
SHA256="${2:-}"
OUT_FILE="${3:-}"
REPO="${CPATH_REPO:-Arcadiastra/cpath}"

if [ -z "$VERSION" ] || [ -z "$SHA256" ]; then
  echo "Usage: $0 <version> <sha256> [output_file]" >&2
  exit 1
fi

if ! printf '%s' "$VERSION" | grep -Eq '^[0-9][A-Za-z0-9.+-]*$'; then
  echo "render-homebrew-formula: invalid version '$VERSION'" >&2
  exit 1
fi

if ! printf '%s' "$SHA256" | grep -Eq '^[0-9a-fA-F]{64}$'; then
  echo "render-homebrew-formula: invalid sha256 '$SHA256'" >&2
  exit 1
fi

if [ -n "$OUT_FILE" ]; then
  mkdir -p "$(dirname "$OUT_FILE")"
fi

VERSION="$VERSION" SHA256="$SHA256" REPO="$REPO" TEMPLATE="$TEMPLATE" OUT_FILE="$OUT_FILE" \
  python3 - <<'PY'
import os, sys

with open(os.environ["TEMPLATE"], "r", encoding="utf-8") as f:
    content = f.read()
content = content.replace("__VERSION__", os.environ["VERSION"])
content = content.replace("__SHA256__", os.environ["SHA256"].lower())
content = content.replace("__REPO__", os.environ["REPO"])
if not content.endswith("\n"):
    content += "\n"

out_file = os.environ["OUT_FILE"]
if out_file:
    with open(out_file, "w", encoding="utf-8") as f:
        f.write(content)
else:
    sys.stdout.write(content)
PY

if [ -n "$OUT_FILE" ]; then
  echo "Rendered $OUT_FILE"
fi
