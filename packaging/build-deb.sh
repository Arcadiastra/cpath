#!/usr/bin/env bash
set -euo pipefail
unset CDPATH

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CPATH_BIN="$ROOT_DIR/bin/cpath"

extract_version() {
  sed -n 's/^VERSION="\([^"]*\)"$/\1/p' "$CPATH_BIN" | head -n 1
}

VERSION="${1:-$(extract_version)}"
VERSION="${VERSION#v}"
OUT_DIR="${2:-$ROOT_DIR/dist}"

if [ -z "$VERSION" ]; then
  echo "build-deb: failed to determine version" >&2
  exit 1
fi

case "$VERSION" in
  [0-9]*)
    ;;
  *)
    echo "build-deb: invalid Debian version '$VERSION' (must start with a digit)" >&2
    exit 1
    ;;
esac

if ! printf '%s' "$VERSION" | grep -Eq '^[0-9][A-Za-z0-9.+:~-]*$'; then
  echo "build-deb: invalid Debian version characters in '$VERSION'" >&2
  exit 1
fi

if ! command -v dpkg-deb >/dev/null 2>&1; then
  echo "build-deb: 'dpkg-deb' is required to build a .deb package" >&2
  exit 1
fi

STAGE_DIR=$(mktemp -d)
trap 'rm -rf "$STAGE_DIR"' EXIT

mkdir -p \
  "$STAGE_DIR/DEBIAN" \
  "$STAGE_DIR/usr/bin" \
  "$STAGE_DIR/usr/share/bash-completion/completions" \
  "$STAGE_DIR/usr/share/zsh/vendor-completions" \
  "$STAGE_DIR/usr/share/man/man1" \
  "$STAGE_DIR/usr/share/doc/cpath"

install -m 755 "$ROOT_DIR/bin/cpath" "$STAGE_DIR/usr/bin/cpath"
install -m 644 "$ROOT_DIR/completions/cpath.bash" "$STAGE_DIR/usr/share/bash-completion/completions/cpath"
install -m 644 "$ROOT_DIR/completions/_cpath" "$STAGE_DIR/usr/share/zsh/vendor-completions/_cpath"
install -m 644 "$ROOT_DIR/README.md" "$STAGE_DIR/usr/share/doc/cpath/README.md"
gzip -9n -c "$ROOT_DIR/man/cpath.1" > "$STAGE_DIR/usr/share/man/man1/cpath.1.gz"
chmod 644 "$STAGE_DIR/usr/share/man/man1/cpath.1.gz"

cat > "$STAGE_DIR/usr/share/doc/cpath/copyright" <<'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: cpath
Upstream-Contact: Arcadiastra <145830276+Arcadiastra@users.noreply.github.com>
Source: https://github.com/Arcadiastra/cpath

Files: *
Copyright: 2026 Arcadiastra
License: MIT
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 .
 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.
 .
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
EOF
chmod 644 "$STAGE_DIR/usr/share/doc/cpath/copyright"

# Normalize directory permissions for Debian Policy compliance
find "$STAGE_DIR" -type d -exec chmod 755 {} +

INSTALLED_SIZE=$(du -sk "$STAGE_DIR/usr" | awk '{print $1}')

cat > "$STAGE_DIR/DEBIAN/control" <<EOF
Package: cpath
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: all
Maintainer: Arcadiastra <145830276+Arcadiastra@users.noreply.github.com>
Homepage: https://github.com/Arcadiastra/cpath
Depends: bash
Recommends: coreutils
Suggests: xclip | xsel | wl-clipboard
Installed-Size: ${INSTALLED_SIZE}
Description: Copy canonical absolute paths across local shells and SSH
 Zero-dependency CLI tool that resolves files and directories to canonical
 absolute paths and copies them to the clipboard.
 .
 Automatically selects local clipboard backends (Wayland, X11, macOS, WSL)
 and switches to OSC 52 escape sequences over SSH sessions, with host-alias
 formatting for scp/rsync and Bash/Zsh tab completion.
EOF
chmod 644 "$STAGE_DIR/DEBIAN/control"

if command -v md5sum >/dev/null 2>&1; then
  (
    cd "$STAGE_DIR"
    find usr -type f | LC_ALL=C sort | xargs md5sum > DEBIAN/md5sums
  )
  chmod 644 "$STAGE_DIR/DEBIAN/md5sums"
fi

mkdir -p "$OUT_DIR"
OUT_DEB="$OUT_DIR/cpath_${VERSION}_all.deb"

dpkg-deb --root-owner-group --build "$STAGE_DIR" "$OUT_DEB" >/dev/null
echo "Built $OUT_DEB"
