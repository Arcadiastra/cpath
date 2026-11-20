#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

WORK=$(cd -P "$WORK" && pwd -P)
name=$'test path with spaces and a newline\n'
touch "$WORK/$name"
printf '%s' "$WORK/$name" > "$WORK/expected"

# Check that this hosted runner has a functioning native pasteboard before
# treating a missing clipboard payload as an application regression.
printf '%s' 'cpath pasteboard runner check' > "$WORK/probe"
if ! /usr/bin/pbcopy < "$WORK/probe" ||
  ! /usr/bin/pbpaste > "$WORK/probe-result" ||
  ! cmp -s "$WORK/probe" "$WORK/probe-result"; then
  echo 'macOS runner could not round-trip text through pbcopy/pbpaste.' >&2
  exit 1
fi

env -u SSH_CONNECTION -u SSH_TTY -u SSH_CLIENT \
  XDG_CONFIG_HOME="$WORK/config" "$ROOT_DIR/bin/cpath" "$WORK/$name"
/usr/bin/pbpaste > "$WORK/actual"
cmp "$WORK/expected" "$WORK/actual"
echo 'Native macOS pasteboard round-trip passed.'
