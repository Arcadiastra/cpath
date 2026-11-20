#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CPATH_BIN="$ROOT_DIR/bin/cpath"

PASS_COUNT=0
FAIL_COUNT=0

TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf '  [PASS] %s\n' "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf '  [FAIL] %s\n' "$1" >&2
  if [ -n "${2:-}" ]; then
    printf '         %s\n' "$2" >&2
  fi
}

assert_eq() {
  local desc="$1"
  local expected="$2"
  local actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass "$desc"
  else
    fail "$desc" "expected=$(printf '%q' "$expected") actual=$(printf '%q' "$actual")"
  fi
}

assert_contains() {
  local desc="$1"
  local needle="$2"
  local haystack="$3"
  case "$haystack" in
    *"$needle"*)
      pass "$desc"
      ;;
    *)
      fail "$desc" "expected to contain $(printf '%q' "$needle"), got $(printf '%q' "$haystack")"
      ;;
  esac
}

assert_not_contains() {
  local desc="$1"
  local needle="$2"
  local haystack="$3"
  case "$haystack" in
    *"$needle"*)
      fail "$desc" "did not expect to contain $(printf '%q' "$needle"), got $(printf '%q' "$haystack")"
      ;;
    *)
      pass "$desc"
      ;;
  esac
}

assert_true() {
  local desc="$1"
  shift
  if "$@"; then
    pass "$desc"
  else
    fail "$desc" "condition returned non-zero: $*"
  fi
}

assert_exit_nonzero() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    fail "$desc" "expected non-zero exit code, got 0"
  else
    pass "$desc"
  fi
}

# Build a clean test fixture tree
FIXTURE="$TMP_ROOT/fixture"
REAL_DIR="$FIXTURE/releases/v1"
mkdir -p "$REAL_DIR/sub"
printf 'hello\n' > "$REAL_DIR/app.txt"
printf 'space\n' > "$REAL_DIR/my file.txt"
printf 'dash\n' > "$REAL_DIR/-leading-dash.txt"
ln -s "$REAL_DIR" "$FIXTURE/current"
ln -s "$REAL_DIR/app.txt" "$FIXTURE/app-link.txt"
ln -s "../v1/app.txt" "$FIXTURE/current/rel-link.txt"
ln -s "$REAL_DIR/app.txt" "$REAL_DIR/-short"
ln -s "$FIXTURE/loop-self" "$FIXTURE/loop-self"
ln -s "$FIXTURE/missing-mid/leaf.txt" "$FIXTURE/bad-mid-link"
ln -s "$FIXTURE/bad-mid-link/" "$FIXTURE/outer-to-bad-slash"
ln -s "$REAL_DIR/future-leaf.txt" "$FIXTURE/dangling-valid-parent"
ln -s "$REAL_DIR/future-dir/" "$FIXTURE/dangling-trailing-slash"
ln -s "$FIXTURE/missing-dot/." "$FIXTURE/link-to-missing-dot"

REAL_DIR_CANON=$(cd -P "$REAL_DIR" && pwd -P)
FIXTURE_CANON=$(cd -P "$FIXTURE" && pwd -P)

# Special filename fixtures: trailing newline, embedded newline, terminal control chars
SPECIAL_DIR="$TMP_ROOT/special"
mkdir -p "$SPECIAL_DIR"
SPECIAL_DIR_CANON=$(cd -P "$SPECIAL_DIR" && pwd -P)
printf 'plain\n' > "$SPECIAL_DIR/notes"
printf 'trailing-nl\n' > "$SPECIAL_DIR/"$'notes\n'
mkdir -p "$SPECIAL_DIR/"$'dir\nwith\nnl'
printf 'embedded-nl\n' > "$SPECIAL_DIR/"$'dir\nwith\nnl/inner\nfile\n'
printf 'ctrl\n' > "$SPECIAL_DIR/"$'evil\r\033[31mfile'

# Isolated config directory for all tests
TEST_XDG="$TMP_ROOT/xdg"
mkdir -p "$TEST_XDG"

run_cpath() {
  env -u SSH_CONNECTION -u SSH_TTY -u SSH_CLIENT -u CPATH_HOST -u LC_SSH_HOST \
    XDG_CONFIG_HOME="$TEST_XDG" "$CPATH_BIN" "$@"
}

echo "=== 1. CLI metadata & error handling ==="
assert_eq "version short flag" "cpath 0.1.0" "$(run_cpath -v)"
assert_eq "version long flag" "cpath 0.1.0" "$(run_cpath --version)"
assert_contains "help short flag" "Usage: cpath" "$(run_cpath -h)"
assert_contains "help long flag" "--set-host" "$(run_cpath --help)"
assert_exit_nonzero "unknown short flag fails" run_cpath -z
assert_exit_nonzero "unknown long flag fails" run_cpath --unknown-flag
assert_exit_nonzero "nonexistent parent fails" run_cpath -p "$FIXTURE/does-not-exist/file.txt"

echo "=== 2. Path resolution, symlinks, -d, -n, spaces & leading dash ==="
assert_eq "default cwd" "$REAL_DIR_CANON" "$(cd "$REAL_DIR" && run_cpath -p)"
assert_eq "file path" "$REAL_DIR_CANON/app.txt" "$(run_cpath -p "$REAL_DIR/app.txt")"
assert_eq "file with spaces" "$REAL_DIR_CANON/my file.txt" "$(run_cpath -p "$REAL_DIR/my file.txt")"
assert_eq "file with leading dash via --" "$REAL_DIR_CANON/-leading-dash.txt" "$(cd "$REAL_DIR" && run_cpath -p -- -leading-dash.txt)"
assert_eq "symlink dir resolved by default" "$REAL_DIR_CANON" "$(run_cpath -p "$FIXTURE/current")"
assert_eq "symlink file resolved by default" "$REAL_DIR_CANON/app.txt" "$(run_cpath -p "$FIXTURE/app-link.txt")"
assert_eq "relative symlink in symlinked dir resolved" "$REAL_DIR_CANON/app.txt" "$(run_cpath -p "$FIXTURE/current/rel-link.txt")"
assert_eq "-n preserves symlink dir" "$FIXTURE_CANON/current" "$(run_cpath -np "$FIXTURE/current")"
assert_eq "-n preserves symlink file" "$FIXTURE_CANON/app-link.txt" "$(run_cpath -np "$FIXTURE/app-link.txt")"
assert_eq "-n inside symlinked cwd preserves logical cwd" "$FIXTURE_CANON/current" "$(cd -L "$FIXTURE_CANON/current" && run_cpath -np)"
assert_eq "-d on file gives parent dir" "$REAL_DIR_CANON" "$(run_cpath -dp "$REAL_DIR/app.txt")"
assert_eq "-d on dir keeps dir" "$REAL_DIR_CANON" "$(run_cpath -dp "$REAL_DIR")"
assert_eq "-dn on file in symlink dir" "$FIXTURE_CANON/current" "$(run_cpath -dnp "$FIXTURE_CANON/current/app.txt")"
assert_eq "-dn on symlink dir keeps symlink dir" "$FIXTURE_CANON/current" "$(run_cpath -dnp "$FIXTURE_CANON/current")"

echo "=== 3. Multi-file & combined flags ==="
expected_multi="$REAL_DIR_CANON/app.txt"$'\n'"$REAL_DIR_CANON/my file.txt"
assert_eq "multi-file -p joins with newline" "$expected_multi" "$(run_cpath -p "$REAL_DIR/app.txt" "$REAL_DIR/my file.txt")"
expected_multi_host="srv01:$REAL_DIR_CANON"$'\n'"srv01:$REAL_DIR_CANON/sub"
assert_eq "multi-file -sd combined flags" "$expected_multi_host" \
  "$(env -u SSH_CONNECTION -u SSH_TTY -u SSH_CLIENT -u LC_SSH_HOST CPATH_HOST=srv01 XDG_CONFIG_HOME="$TEST_XDG" "$CPATH_BIN" -sdp "$REAL_DIR/app.txt" "$REAL_DIR/sub")"

echo "=== 4. Hostname priority chain & config commands ==="
sys_host=$(hostname)
assert_eq "priority 4: fallback to hostname" "${sys_host}:${REAL_DIR_CANON}" "$(run_cpath -sp "$REAL_DIR")"
assert_eq "priority 3: LC_SSH_HOST overrides hostname" "ssh-env:${REAL_DIR_CANON}" \
  "$(env -u CPATH_HOST LC_SSH_HOST=ssh-env XDG_CONFIG_HOME="$TEST_XDG" "$CPATH_BIN" -sp "$REAL_DIR")"

assert_eq "--set-host saves alias" "Saved host alias: prod-api" "$(run_cpath --set-host prod-api)"
assert_eq "priority 2: saved alias overrides LC_SSH_HOST" "prod-api:${REAL_DIR_CANON}" \
  "$(env -u CPATH_HOST LC_SSH_HOST=ssh-env XDG_CONFIG_HOME="$TEST_XDG" "$CPATH_BIN" -sp "$REAL_DIR")"

assert_eq "priority 1: CPATH_HOST overrides saved alias" "bastion:${REAL_DIR_CANON}" \
  "$(CPATH_HOST=bastion LC_SSH_HOST=ssh-env XDG_CONFIG_HOME="$TEST_XDG" "$CPATH_BIN" -sp "$REAL_DIR")"

cur_user="${USER:-$(id -un)}"
assert_eq "-u prepends user@host" "${cur_user}@prod-api:${REAL_DIR_CANON}/app.txt" \
  "$(run_cpath -up "$REAL_DIR/app.txt")"
assert_eq "-ud combined on file" "${cur_user}@prod-api:${REAL_DIR_CANON}" \
  "$(run_cpath -udp "$REAL_DIR/app.txt")"

assert_eq "--set-host=ALIAS syntax" "Saved host alias: staging-02" "$(run_cpath --set-host=staging-02)"
assert_eq "updated saved alias active" "staging-02:${REAL_DIR_CANON}" "$(run_cpath -sp "$REAL_DIR")"
assert_exit_nonzero "--set-host rejects whitespace" run_cpath --set-host "bad host"
assert_exit_nonzero "--set-host rejects control chars" run_cpath --set-host $'bad\rhost'
assert_contains "--clear-host removes alias" "Cleared saved host alias" "$(run_cpath --clear-host)"
assert_eq "after --clear-host falls back to hostname" "${sys_host}:${REAL_DIR_CANON}" "$(run_cpath -sp "$REAL_DIR")"

echo "=== 5. SSH OSC 52 clipboard output (with PTY, without TTY, non-UTF-8 & large Python fallback) ==="
expected_b64=$(printf '%s' "$REAL_DIR_CANON/app.txt" | base64 | tr -d '\r\n')
expected_osc_seq=$'\033]52;c;'"$expected_b64"$'\a'
expected_copied_app="Copied: $(printf '%q' "$REAL_DIR_CANON/app.txt")"

# 5a. Without a controlling TTY -> OSC 52 emitted to stdout
no_tty_out=$(python3 - "$CPATH_BIN" "$TEST_XDG" "$REAL_DIR/app.txt" <<'PY'
import os, subprocess, sys
cpath_bin, xdg, target = sys.argv[1:4]
env = os.environ.copy()
for k in ("CPATH_HOST", "LC_SSH_HOST", "SSH_TTY", "SSH_CLIENT"):
    env.pop(k, None)
env["SSH_CONNECTION"] = "1.2.3.4 12345 5.6.7.8 22"
env["XDG_CONFIG_HOME"] = xdg
p = subprocess.run(
    [cpath_bin, target],
    env=env,
    stdin=subprocess.DEVNULL,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    start_new_session=True,
)
sys.exit(p.returncode) if p.returncode != 0 else sys.stdout.buffer.write(p.stdout)
PY
)
assert_contains "OSC 52 without controlling TTY emits OSC 52 payload to stdout" "$expected_osc_seq" "$no_tty_out"
assert_contains "OSC 52 without controlling TTY prints escaped Copied prompt" "$expected_copied_app" "$no_tty_out"
assert_eq "OSC 52 without controlling TTY exact stdout" "${expected_osc_seq}${expected_copied_app}" "$no_tty_out"

no_tty_ssh_tty=$(python3 - "$CPATH_BIN" "$TEST_XDG" "$REAL_DIR/app.txt" <<'PY'
import os, subprocess, sys
cpath_bin, xdg, target = sys.argv[1:4]
env = os.environ.copy()
for k in ("CPATH_HOST", "LC_SSH_HOST", "SSH_CONNECTION", "SSH_CLIENT"):
    env.pop(k, None)
env["SSH_TTY"] = "/dev/pts/0"
env["XDG_CONFIG_HOME"] = xdg
p = subprocess.run(
    [cpath_bin, target],
    env=env,
    stdin=subprocess.DEVNULL,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    start_new_session=True,
)
sys.exit(p.returncode) if p.returncode != 0 else sys.stdout.buffer.write(p.stdout)
PY
)
assert_eq "OSC 52 triggered by SSH_TTY without controlling TTY" "${expected_osc_seq}${expected_copied_app}" "$no_tty_ssh_tty"

# 5b. With a controlling PTY and stdout redirected to a log file -> OSC 52 still reaches PTY!
OSC_LOG="$TMP_ROOT/copy.log"
pty_osc_out=$(python3 - "$CPATH_BIN" "$TEST_XDG" "$REAL_DIR/app.txt" "$OSC_LOG" <<'PY'
import errno, os, pty, select, subprocess, sys
cpath_bin, xdg, target, log_path = sys.argv[1:5]
master, slave = pty.openpty()
env = os.environ.copy()
for k in ("CPATH_HOST", "LC_SSH_HOST", "SSH_TTY", "SSH_CLIENT"):
    env.pop(k, None)
env["SSH_CONNECTION"] = "1.2.3.4 12345 5.6.7.8 22"
env["XDG_CONFIG_HOME"] = xdg

def setup_ctty():
    os.setsid()
    import fcntl, termios
    fcntl.ioctl(slave, termios.TIOCSCTTY, 0)

with open(log_path, "wb") as logf:
    proc = subprocess.Popen(
        [cpath_bin, target],
        env=env,
        stdin=slave,
        stdout=logf,
        stderr=slave,
        preexec_fn=setup_ctty,
        close_fds=True,
    )
os.close(slave)

chunks = []
while True:
    r, _, _ = select.select([master], [], [], 0.2)
    if r:
        try:
            data = os.read(master, 4096)
            if not data:
                break
            chunks.append(data)
        except OSError as e:
            if e.errno == errno.EIO:
                break
            raise
    elif proc.poll() is not None:
        break

rc = proc.wait()
os.close(master)
if rc != 0:
    sys.exit(rc)
sys.stdout.buffer.write(b"".join(chunks))
PY
)
assert_eq "OSC 52 with PTY & redirected stdout writes sequence to /dev/tty" "$expected_osc_seq" "$pty_osc_out"
assert_eq "redirected stdout log receives clean Copied line without OSC 52" "$expected_copied_app" "$(cat "$OSC_LOG")"

# 5c. Python base64 fallback (no base64 binary): non-UTF-8 byte 0xff AND >128KB multi-path payload
NO_B64_BIN="$TMP_ROOT/no-b64-bin"
mkdir -p "$NO_B64_BIN"
for tool in bash cat realpath dirname basename pwd tr hostname uname id mkdir rm python3 readlink; do
  if tool_path=$(command -v "$tool" 2>/dev/null); then
    ln -sf "$tool_path" "$NO_B64_BIN/$tool"
  fi
done

NON_UTF8_FILE="$SPECIAL_DIR/"$'raw-\xff-byte'
touch "$NON_UTF8_FILE"
py_b64_raw_ok=$(python3 - "$CPATH_BIN" "$TEST_XDG" "$NO_B64_BIN" "$NON_UTF8_FILE" "$SPECIAL_DIR_CANON" <<'PY'
import base64, os, subprocess, sys
cpath_bin, xdg, path_dir, raw_file, special_canon = sys.argv[1:6]
env = {
    "HOME": os.environ["HOME"],
    "PATH": path_dir,
    "XDG_CONFIG_HOME": xdg,
    "SSH_CONNECTION": "1.2.3.4 12345 5.6.7.8 22",
}
p = subprocess.run(
    [cpath_bin, raw_file],
    env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    start_new_session=True,
)
if p.returncode != 0:
    sys.stderr.buffer.write(p.stderr)
    sys.exit(p.returncode)
expected_bytes = os.fsencode(special_canon) + b"/raw-\xff-byte"
expected_osc = b"\x1b]52;c;" + base64.b64encode(expected_bytes) + b"\x07"
print("RAW_OK" if p.stdout.startswith(expected_osc) else "RAW_MISMATCH")
PY
)
assert_eq "Python base64 fallback encodes non-UTF-8 0xff filename" "RAW_OK" "$py_b64_raw_ok"

LARGE_DIR="$TMP_ROOT/large-paths"
mkdir -p "$LARGE_DIR"
py_b64_large_ok=$(python3 - "$CPATH_BIN" "$TEST_XDG" "$NO_B64_BIN" "$LARGE_DIR" <<'PY'
import base64, os, subprocess, sys
cpath_bin, xdg, path_dir, large_dir = sys.argv[1:5]
large_canon = os.path.realpath(large_dir)
# Build >150 KB combined payload (exceeding Linux 128 KB MAX_ARG_STRLEN)
pad = "a" * 200
files = []
expected_lines = []
for i in range(650):
    name = f"{pad}_{i:04d}.txt"
    full = os.path.join(large_dir, name)
    with open(full, "wb"):
        pass
    files.append(full)
    expected_lines.append(os.path.join(large_canon, name))

env = {
    "HOME": os.environ["HOME"],
    "PATH": path_dir,
    "XDG_CONFIG_HOME": xdg,
    "SSH_CONNECTION": "1.2.3.4 12345 5.6.7.8 22",
}
p = subprocess.run(
    [cpath_bin] + files,
    env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    start_new_session=True,
)
if p.returncode != 0:
    sys.stderr.buffer.write(p.stderr)
    sys.exit(p.returncode)
expected_payload = "\n".join(expected_lines).encode("utf-8")
expected_osc = b"\x1b]52;c;" + base64.b64encode(expected_payload) + b"\x07"
print("LARGE_OK" if p.stdout.startswith(expected_osc) else "LARGE_MISMATCH")
PY
)
assert_eq "Python base64 fallback handles >150KB multi-path payload without E2BIG" "LARGE_OK" "$py_b64_large_ok"

echo "=== 6. Local clipboard backend routing, byte-exact newlines & terminal escaping ==="
MOCK_BIN="$TMP_ROOT/mock-bin"
CLIP_OUT="$TMP_ROOT/clip.out"
mkdir -p "$MOCK_BIN"

make_mock_clip() {
  local name="$1"
  cat > "$MOCK_BIN/$name" <<EOF
#!/usr/bin/env bash
printf '%s:' "$name" > "$CLIP_OUT"
cat >> "$CLIP_OUT"
EOF
  chmod +x "$MOCK_BIN/$name"
}

make_raw_mock_clip() {
  local name="$1"
  cat > "$MOCK_BIN/$name" <<EOF
#!/usr/bin/env bash
cat > "$CLIP_OUT"
EOF
  chmod +x "$MOCK_BIN/$name"
}

# Link essential utilities into a restricted PATH so real clipboard tools are hidden
SAFE_BIN="$TMP_ROOT/safe-bin"
mkdir -p "$SAFE_BIN"
for tool in bash cat realpath dirname basename pwd tr hostname uname id mkdir rm mktemp printf base64 python3 readlink; do
  if tool_path=$(command -v "$tool" 2>/dev/null); then
    ln -sf "$tool_path" "$SAFE_BIN/$tool"
  fi
done

# 6a. pbcopy
make_mock_clip pbcopy
rm -f "$CLIP_OUT"
env -i HOME="$HOME" PATH="$MOCK_BIN:$SAFE_BIN" XDG_CONFIG_HOME="$TEST_XDG" \
  "$CPATH_BIN" "$REAL_DIR/app.txt" >/dev/null
assert_eq "local backend: pbcopy" "pbcopy:$REAL_DIR_CANON/app.txt" "$(cat "$CLIP_OUT")"
rm -f "$MOCK_BIN/pbcopy"

# 6b. wl-copy vs xclip: wl-copy skipped when WAYLAND_DISPLAY is unset
make_mock_clip wl-copy
make_mock_clip xclip
rm -f "$CLIP_OUT"
env -i HOME="$HOME" PATH="$MOCK_BIN:$SAFE_BIN" DISPLAY=":0" XDG_CONFIG_HOME="$TEST_XDG" \
  "$CPATH_BIN" "$REAL_DIR/app.txt" >/dev/null
assert_eq "local backend: xclip chosen on X11 even if wl-copy installed" "xclip:$REAL_DIR_CANON/app.txt" "$(cat "$CLIP_OUT")"

rm -f "$CLIP_OUT"
env -i HOME="$HOME" PATH="$MOCK_BIN:$SAFE_BIN" WAYLAND_DISPLAY="wayland-0" DISPLAY=":0" XDG_CONFIG_HOME="$TEST_XDG" \
  "$CPATH_BIN" "$REAL_DIR/app.txt" >/dev/null
assert_eq "local backend: wl-copy chosen on Wayland" "wl-copy:$REAL_DIR_CANON/app.txt" "$(cat "$CLIP_OUT")"
rm -f "$MOCK_BIN/wl-copy" "$MOCK_BIN/xclip"

# 6c. xsel
make_mock_clip xsel
rm -f "$CLIP_OUT"
env -i HOME="$HOME" PATH="$MOCK_BIN:$SAFE_BIN" DISPLAY=":0" XDG_CONFIG_HOME="$TEST_XDG" \
  "$CPATH_BIN" "$REAL_DIR/app.txt" >/dev/null
assert_eq "local backend: xsel" "xsel:$REAL_DIR_CANON/app.txt" "$(cat "$CLIP_OUT")"
rm -f "$MOCK_BIN/xsel"

# 6d. clip.exe (WSL)
make_mock_clip clip.exe
rm -f "$CLIP_OUT"
env -i HOME="$HOME" PATH="$MOCK_BIN:$SAFE_BIN" XDG_CONFIG_HOME="$TEST_XDG" \
  "$CPATH_BIN" "$REAL_DIR/app.txt" >/dev/null
assert_eq "local backend: clip.exe" "clip.exe:$REAL_DIR_CANON/app.txt" "$(cat "$CLIP_OUT")"
rm -f "$MOCK_BIN/clip.exe"

# 6e. No backend found -> exit 1 and prints fallback path to stdout
fallback_rc=0
fallback_out=$(env -i HOME="$HOME" PATH="$SAFE_BIN" XDG_CONFIG_HOME="$TEST_XDG" \
  "$CPATH_BIN" "$REAL_DIR/app.txt" 2>/dev/null) || fallback_rc=$?
assert_eq "no backend exits 1" "1" "$fallback_rc"
assert_eq "no backend prints fallback path" "$REAL_DIR_CANON/app.txt" "$fallback_out"

# 6f. Byte-exact preservation of trailing & embedded newlines (including -d and -n)
make_raw_mock_clip pbcopy
EXPECTED_BIN="$TMP_ROOT/expected.bin"

# Default realpath mode with trailing newline filename
rm -f "$CLIP_OUT"
env -i HOME="$HOME" PATH="$MOCK_BIN:$SAFE_BIN" XDG_CONFIG_HOME="$TEST_XDG" \
  "$CPATH_BIN" "$SPECIAL_DIR/"$'notes\n' >/dev/null
printf '%s' "$SPECIAL_DIR_CANON/"$'notes\n' > "$EXPECTED_BIN"
assert_true "clipboard preserves trailing newline in filename (realpath)" cmp -s "$EXPECTED_BIN" "$CLIP_OUT"

# -d preserves trailing newline in parent directory name
rm -f "$CLIP_OUT"
env -i HOME="$HOME" PATH="$MOCK_BIN:$SAFE_BIN" XDG_CONFIG_HOME="$TEST_XDG" \
  "$CPATH_BIN" -d "$SPECIAL_DIR/"$'dir\nwith\nnl/inner\nfile\n' >/dev/null
printf '%s' "$SPECIAL_DIR_CANON/"$'dir\nwith\nnl' > "$EXPECTED_BIN"
assert_true "clipboard preserves embedded newlines with -d" cmp -s "$EXPECTED_BIN" "$CLIP_OUT"

# Control characters escaped in terminal Copied: message, preserved raw in clipboard & -p
rm -f "$CLIP_OUT"
ctrl_msg=$(env -i HOME="$HOME" LC_ALL="C.UTF-8" PATH="$MOCK_BIN:$SAFE_BIN" XDG_CONFIG_HOME="$TEST_XDG" \
  "$CPATH_BIN" "$SPECIAL_DIR/"$'evil\r\033[31mfile')
printf '%s' "$SPECIAL_DIR_CANON/"$'evil\r\033[31mfile' > "$EXPECTED_BIN"
assert_true "clipboard receives raw bytes for control-char filename" cmp -s "$EXPECTED_BIN" "$CLIP_OUT"
assert_not_contains "terminal Copied message escapes raw ESC" $'\033' "$ctrl_msg"
assert_not_contains "terminal Copied message escapes raw CR" $'\r' "$ctrl_msg"
assert_contains "terminal Copied message shows escaped representation" '\E[31m' "$ctrl_msg"

# -p preserves raw bytes verbatim
env -i HOME="$HOME" PATH="$MOCK_BIN:$SAFE_BIN" XDG_CONFIG_HOME="$TEST_XDG" \
  "$CPATH_BIN" -p "$SPECIAL_DIR/"$'evil\r\033[31mfile' > "$CLIP_OUT"
printf '%s\n' "$SPECIAL_DIR_CANON/"$'evil\r\033[31mfile' > "$EXPECTED_BIN"
assert_true "-p output preserves raw control-char path" cmp -s "$EXPECTED_BIN" "$CLIP_OUT"

rm -f "$MOCK_BIN/pbcopy"

echo "=== 7. Path resolution fallbacks (BusyBox, python3 & pure Bash) ==="
# 7a. BusyBox realpath compatibility (if busybox is installed)
if command -v busybox >/dev/null 2>&1; then
  BB_BIN="$TMP_ROOT/bb-bin"
  mkdir -p "$BB_BIN"
  ln -sf "$(command -v busybox)" "$BB_BIN/realpath"
  for tool in bash cat dirname basename pwd tr hostname uname id mkdir rm readlink; do
    if tool_path=$(command -v "$tool" 2>/dev/null); then
      ln -sf "$tool_path" "$BB_BIN/$tool"
    fi
  done
  assert_eq "BusyBox realpath handles cpath -p ." "$REAL_DIR_CANON" \
    "$(cd "$REAL_DIR" && env -i HOME="$HOME" PATH="$BB_BIN" XDG_CONFIG_HOME="$TEST_XDG" "$CPATH_BIN" -p .)"
  assert_eq "BusyBox realpath handles leading-dash file" "$REAL_DIR_CANON/-leading-dash.txt" \
    "$(cd "$REAL_DIR" && env -i HOME="$HOME" PATH="$BB_BIN" XDG_CONFIG_HOME="$TEST_XDG" "$CPATH_BIN" -p -- -leading-dash.txt)"
  assert_eq "BusyBox realpath -n falls back cleanly when -s unsupported" "$FIXTURE_CANON/current" \
    "$(env -i HOME="$HOME" PATH="$BB_BIN" XDG_CONFIG_HOME="$TEST_XDG" "$CPATH_BIN" -np "$FIXTURE/current")"

  BB_DASH_S="$TMP_ROOT/bb-dash-s"
  mkdir -p "$BB_DASH_S/orig"
  touch "$BB_DASH_S/-s"
  ln -s "$BB_DASH_S/orig" "$BB_DASH_S/current"
  BB_DASH_S_CANON=$(cd -P "$BB_DASH_S" && pwd -P)
  assert_eq "BusyBox -n ignores file named '-s' in cwd" "$BB_DASH_S_CANON/current" \
    "$(cd "$BB_DASH_S" && env -i HOME="$HOME" PATH="$BB_BIN" XDG_CONFIG_HOME="$TEST_XDG" "$CPATH_BIN" -np current)"
  assert_exit_nonzero "BusyBox fails on dangling symlink to missing intermediate dir (bad)" \
    env -i HOME="$HOME" PATH="$BB_BIN" XDG_CONFIG_HOME="$TEST_XDG" "$CPATH_BIN" -p "$FIXTURE/bad-mid-link"
  assert_exit_nonzero "BusyBox fails on dangling symlink with trailing slash (bad/)" \
    env -i HOME="$HOME" PATH="$BB_BIN" XDG_CONFIG_HOME="$TEST_XDG" "$CPATH_BIN" -p "$FIXTURE/bad-mid-link/"
  assert_exit_nonzero "BusyBox fails on symlink chain containing trailing slash (outer -> bad/)" \
    env -i HOME="$HOME" PATH="$BB_BIN" XDG_CONFIG_HOME="$TEST_XDG" "$CPATH_BIN" -p "$FIXTURE/outer-to-bad-slash"
  assert_eq "BusyBox resolves dangling leaf symlink with trailing slash (ldang/)" "$REAL_DIR_CANON/future-leaf.txt" \
    "$(env -i HOME="$HOME" PATH="$BB_BIN" XDG_CONFIG_HOME="$TEST_XDG" "$CPATH_BIN" -p "$FIXTURE/dangling-valid-parent/")"
fi

# 7a-2. GNU realpath ONLY (no python3, no readlink) still resolves dangling symlink with trailing slash
GNU_ONLY_BIN="$TMP_ROOT/gnu-only-bin"
mkdir -p "$GNU_ONLY_BIN"
for tool in bash realpath; do
  if tool_path=$(command -v "$tool" 2>/dev/null); then
    ln -sf "$tool_path" "$GNU_ONLY_BIN/$tool"
  fi
done
assert_eq "GNU realpath alone resolves dangling symlink with trailing slash without readlink" \
  "$REAL_DIR_CANON/future-leaf.txt" \
  "$(env -i HOME="$HOME" PATH="$GNU_ONLY_BIN" XDG_CONFIG_HOME="$TEST_XDG" "$CPATH_BIN" -p "$FIXTURE/dangling-valid-parent/")"

# 7b. Python3 fallback (no realpath in PATH)
PY_BIN="$TMP_ROOT/py-bin"
mkdir -p "$PY_BIN"
for tool in bash cat dirname basename pwd tr hostname uname id mkdir rm python3; do
  if tool_path=$(command -v "$tool" 2>/dev/null); then
    ln -sf "$tool_path" "$PY_BIN/$tool"
  fi
done
assert_eq "python3 fallback resolves symlink" "$REAL_DIR_CANON/app.txt" \
  "$(env -i HOME="$HOME" PATH="$PY_BIN" XDG_CONFIG_HOME="$TEST_XDG" "$CPATH_BIN" -p "$FIXTURE/app-link.txt")"
assert_eq "python3 fallback -n preserves symlink" "$FIXTURE_CANON/current/app.txt" \
  "$(env -i HOME="$HOME" PATH="$PY_BIN" XDG_CONFIG_HOME="$TEST_XDG" "$CPATH_BIN" -np "$FIXTURE_CANON/current/./app.txt")"
assert_eq "python3 fallback allows dangling leaf in existing parent" "$REAL_DIR_CANON/future-leaf.txt" \
  "$(env -i HOME="$HOME" PATH="$PY_BIN" XDG_CONFIG_HOME="$TEST_XDG" "$CPATH_BIN" -p "$FIXTURE/dangling-valid-parent")"
assert_eq "python3 fallback allows symlink to missing leaf with trailing slash (link)" "$REAL_DIR_CANON/future-dir" \
  "$(env -i HOME="$HOME" PATH="$PY_BIN" XDG_CONFIG_HOME="$TEST_XDG" "$CPATH_BIN" -p "$FIXTURE/dangling-trailing-slash")"
assert_eq "python3 fallback allows symlink to missing leaf with double trailing slash (link/)" "$REAL_DIR_CANON/future-dir" \
  "$(env -i HOME="$HOME" PATH="$PY_BIN" XDG_CONFIG_HOME="$TEST_XDG" "$CPATH_BIN" -p "$FIXTURE/dangling-trailing-slash/")"
assert_exit_nonzero "python3 fallback fails on self-referential symlink loop" \
  env -i HOME="$HOME" PATH="$PY_BIN" XDG_CONFIG_HOME="$TEST_XDG" "$CPATH_BIN" -p "$FIXTURE/loop-self"
assert_exit_nonzero "python3 fallback fails on symlink to missing intermediate dir" \
  env -i HOME="$HOME" PATH="$PY_BIN" XDG_CONFIG_HOME="$TEST_XDG" "$CPATH_BIN" -p "$FIXTURE/bad-mid-link"
assert_exit_nonzero "python3 fallback fails on non-directory component" \
  env -i HOME="$HOME" PATH="$PY_BIN" XDG_CONFIG_HOME="$TEST_XDG" "$CPATH_BIN" -p "$REAL_DIR/app.txt/sub"
assert_exit_nonzero "python3 fallback fails on trailing slash of regular file" \
  env -i HOME="$HOME" PATH="$PY_BIN" XDG_CONFIG_HOME="$TEST_XDG" "$CPATH_BIN" -p "$REAL_DIR/app.txt/"
assert_exit_nonzero "python3 fallback fails on nonexistent missing/." \
  env -i HOME="$HOME" PATH="$PY_BIN" XDG_CONFIG_HOME="$TEST_XDG" "$CPATH_BIN" -p "$FIXTURE/missing-dot/."
assert_exit_nonzero "python3 fallback fails on symlink to nonexistent missing/." \
  env -i HOME="$HOME" PATH="$PY_BIN" XDG_CONFIG_HOME="$TEST_XDG" "$CPATH_BIN" -p "$FIXTURE/link-to-missing-dot"
assert_exit_nonzero "python3 fallback fails on nonexistent parent" \
  env -i HOME="$HOME" PATH="$PY_BIN" XDG_CONFIG_HOME="$TEST_XDG" "$CPATH_BIN" -p "$FIXTURE/no-such-dir/a.txt"

make_raw_mock_clip pbcopy
rm -f "$CLIP_OUT"
env -i HOME="$HOME" PATH="$MOCK_BIN:$PY_BIN" XDG_CONFIG_HOME="$TEST_XDG" \
  "$CPATH_BIN" "$SPECIAL_DIR/"$'notes\n' >/dev/null
printf '%s' "$SPECIAL_DIR_CANON/"$'notes\n' > "$EXPECTED_BIN"
assert_true "python3 fallback preserves trailing newline in filename" cmp -s "$EXPECTED_BIN" "$CLIP_OUT"
rm -f "$MOCK_BIN/pbcopy"

# 7c. Pure Bash fallback (neither realpath nor python3 in PATH)
BASH_ONLY_BIN="$TMP_ROOT/bash-only-bin"
mkdir -p "$BASH_ONLY_BIN"
for tool in bash cat dirname basename pwd tr hostname uname id mkdir rm readlink; do
  if tool_path=$(command -v "$tool" 2>/dev/null); then
    ln -sf "$tool_path" "$BASH_ONLY_BIN/$tool"
  fi
done
assert_eq "pure bash fallback resolves symlink file" "$REAL_DIR_CANON/app.txt" \
  "$(env -i HOME="$HOME" PATH="$BASH_ONLY_BIN" XDG_CONFIG_HOME="$TEST_XDG" "$CPATH_BIN" -p "$FIXTURE/app-link.txt")"
assert_eq "pure bash fallback resolves relative symlink in symlinked dir" "$REAL_DIR_CANON/app.txt" \
  "$(env -i HOME="$HOME" PATH="$BASH_ONLY_BIN" XDG_CONFIG_HOME="$TEST_XDG" "$CPATH_BIN" -p "$FIXTURE/current/rel-link.txt")"
assert_eq "pure bash fallback resolves leading-dash symlink (-short)" "$REAL_DIR_CANON/app.txt" \
  "$(cd "$REAL_DIR" && env -i HOME="$HOME" PATH="$BASH_ONLY_BIN" XDG_CONFIG_HOME="$TEST_XDG" "$CPATH_BIN" -p -- -short)"
assert_eq "pure bash fallback resolves symlink dir" "$REAL_DIR_CANON" \
  "$(env -i HOME="$HOME" PATH="$BASH_ONLY_BIN" XDG_CONFIG_HOME="$TEST_XDG" "$CPATH_BIN" -p "$FIXTURE/current")"
assert_eq "pure bash fallback -n normalizes .. and ." "$FIXTURE_CANON/current/app.txt" \
  "$(env -i HOME="$HOME" PATH="$BASH_ONLY_BIN" XDG_CONFIG_HOME="$TEST_XDG" "$CPATH_BIN" -np "$FIXTURE_CANON/current/sub/.././app.txt")"
assert_eq "pure bash fallback -n root" "/" \
  "$(env -i HOME="$HOME" PATH="$BASH_ONLY_BIN" XDG_CONFIG_HOME="$TEST_XDG" "$CPATH_BIN" -np "/a/../..")"
assert_exit_nonzero "pure bash fallback fails on self-referential symlink loop" \
  env -i HOME="$HOME" PATH="$BASH_ONLY_BIN" XDG_CONFIG_HOME="$TEST_XDG" "$CPATH_BIN" -p "$FIXTURE/loop-self"
assert_exit_nonzero "pure bash fallback fails on nonexistent parent" \
  env -i HOME="$HOME" PATH="$BASH_ONLY_BIN" XDG_CONFIG_HOME="$TEST_XDG" "$CPATH_BIN" -p "$FIXTURE/no-such-dir/a.txt"
assert_exit_nonzero "pure bash fallback fails on trailing slash of regular file" \
  env -i HOME="$HOME" PATH="$BASH_ONLY_BIN" XDG_CONFIG_HOME="$TEST_XDG" "$CPATH_BIN" -p "$REAL_DIR/app.txt/"

# Pure Bash CDPATH isolation
CDPATH_OTHER="$TMP_ROOT/cdpath-other"
CDPATH_LOCAL="$TMP_ROOT/cdpath-local"
mkdir -p "$CDPATH_OTHER/src" "$CDPATH_LOCAL/src"
touch "$CDPATH_OTHER/src/README" "$CDPATH_LOCAL/src/README"
CDPATH_LOCAL_CANON=$(cd -P "$CDPATH_LOCAL" && pwd -P)
assert_eq "pure bash fallback ignores CDPATH" "$CDPATH_LOCAL_CANON/src/README" \
  "$(cd "$CDPATH_LOCAL" && env -i HOME="$HOME" PATH="$BASH_ONLY_BIN" CDPATH="$CDPATH_OTHER" XDG_CONFIG_HOME="$TEST_XDG" "$CPATH_BIN" -p src/README)"

# Pure Bash newline preservation (both physical and -n logical with embedded & trailing newlines)
make_raw_mock_clip pbcopy
rm -f "$CLIP_OUT"
env -i HOME="$HOME" PATH="$MOCK_BIN:$BASH_ONLY_BIN" XDG_CONFIG_HOME="$TEST_XDG" \
  "$CPATH_BIN" "$SPECIAL_DIR/"$'dir\nwith\nnl/inner\nfile\n' >/dev/null
printf '%s' "$SPECIAL_DIR_CANON/"$'dir\nwith\nnl/inner\nfile\n' > "$EXPECTED_BIN"
assert_true "pure bash fallback preserves embedded & trailing newlines (physical)" cmp -s "$EXPECTED_BIN" "$CLIP_OUT"

rm -f "$CLIP_OUT"
env -i HOME="$HOME" PATH="$MOCK_BIN:$BASH_ONLY_BIN" XDG_CONFIG_HOME="$TEST_XDG" \
  "$CPATH_BIN" -n "$SPECIAL_DIR_CANON/"$'dir\nwith\nnl/./inner\nfile\n' >/dev/null
assert_true "pure bash fallback -n preserves embedded & trailing newlines" cmp -s "$EXPECTED_BIN" "$CLIP_OUT"
rm -f "$MOCK_BIN/pbcopy"

echo "=== 8. install.sh & uninstall.sh end-to-end (including interactive host validation) ==="
INST_HOME="$TMP_ROOT/inst-home"
INST_BIN="$INST_HOME/.local/bin"
INST_ZSH_COMP="$INST_HOME/.local/share/zsh/site-functions"
INST_BASH_COMP="$INST_HOME/.local/share/bash-completion/completions"
INST_XDG="$INST_HOME/.config"
mkdir -p "$INST_HOME"

CPATH_NONINTERACTIVE=1 \
CPATH_INSTALL_DIR="$INST_BIN" \
CPATH_ZSH_COMPLETION_DIR="$INST_ZSH_COMP" \
CPATH_BASH_COMPLETION_DIR="$INST_BASH_COMP" \
XDG_CONFIG_HOME="$INST_XDG" \
  "$ROOT_DIR/install.sh" >/dev/null

assert_true "install.sh installed executable binary" test -x "$INST_BIN/cpath"
assert_true "install.sh installed Zsh completion" test -f "$INST_ZSH_COMP/_cpath"
assert_true "install.sh installed Bash completion" test -f "$INST_BASH_COMP/cpath"
assert_eq "installed cpath works" "$REAL_DIR_CANON" "$("$INST_BIN/cpath" -p "$REAL_DIR")"

# Interactive install.sh rejects invalid alias ("bad host") then accepts valid alias on retry (fresh & update)
python3 - "$ROOT_DIR/install.sh" "$INST_BIN" "$INST_ZSH_COMP" "$INST_BASH_COMP" "$INST_XDG" <<'PY'
import errno, fcntl, os, pty, select, subprocess, sys, termios, time
install_sh, inst_bin, zsh_comp, bash_comp, xdg = sys.argv[1:6]

def run_interactive(inputs):
    master, slave = pty.openpty()
    env = os.environ.copy()
    env.pop("CI", None)
    env.pop("CPATH_NONINTERACTIVE", None)
    env["CPATH_INSTALL_DIR"] = inst_bin
    env["CPATH_ZSH_COMPLETION_DIR"] = zsh_comp
    env["CPATH_BASH_COMPLETION_DIR"] = bash_comp
    env["XDG_CONFIG_HOME"] = xdg

    def setup_ctty():
        os.setsid()
        fcntl.ioctl(slave, termios.TIOCSCTTY, 0)

    proc = subprocess.Popen(
        [install_sh],
        env=env, stdin=slave, stdout=slave, stderr=slave,
        preexec_fn=setup_ctty, close_fds=True,
    )
    os.close(slave)

    buf = b""
    idx = 0
    deadline = time.time() + 10
    while time.time() < deadline:
        r, _, _ = select.select([master], [], [], 0.1)
        if r:
            try:
                data = os.read(master, 4096)
                if not data:
                    break
                buf += data
            except OSError as e:
                if e.errno == errno.EIO:
                    break
                raise
            if idx < len(inputs) and b"SSH host alias" in buf:
                os.write(master, (inputs[idx] + "\n").encode())
                idx += 1
                buf = b""
        elif proc.poll() is not None:
            break
    rc = proc.wait(timeout=5)
    os.close(master)
    if rc != 0:
        sys.exit(rc)

# Fresh install: reject "bad host", then save "my-box"
run_interactive(["bad host", "my-box"])
with open(os.path.join(xdg, "cpath", "host"), "r") as f:
    assert f.read().strip() == "my-box"

# Update install: reject "bad update", then save "my-box-2"
run_interactive(["bad update", "my-box-2"])
with open(os.path.join(xdg, "cpath", "host"), "r") as f:
    assert f.read().strip() == "my-box-2"
PY
assert_eq "install.sh validates alias via cpath --set-host on fresh & update" "my-box-2" "$(cat "$INST_XDG/cpath/host")"

CPATH_INSTALL_DIR="$INST_BIN" \
CPATH_ZSH_COMPLETION_DIR="$INST_ZSH_COMP" \
CPATH_BASH_COMPLETION_DIR="$INST_BASH_COMP" \
XDG_CONFIG_HOME="$INST_XDG" \
  "$ROOT_DIR/uninstall.sh" >/dev/null

assert_true "uninstall.sh removed binary" test ! -e "$INST_BIN/cpath"
assert_true "uninstall.sh removed Zsh completion" test ! -e "$INST_ZSH_COMP/_cpath"
assert_true "uninstall.sh removed Bash completion" test ! -e "$INST_BASH_COMP/cpath"
assert_true "uninstall.sh removed config dir" test ! -e "$INST_XDG/cpath"

echo "=== 9. Shell completion checks (Zsh & Bash safety + real Tab) ==="
if command -v zsh >/dev/null 2>&1; then
  if zsh -n "$ROOT_DIR/completions/_cpath"; then
    pass "completions/_cpath passes zsh -n syntax check"
  else
    fail "completions/_cpath failed zsh -n syntax check"
  fi
else
  if head -n 1 "$ROOT_DIR/completions/_cpath" | grep -qx '#compdef cpath'; then
    pass "completions/_cpath has valid #compdef header (zsh not installed)"
  else
    fail "completions/_cpath missing #compdef header"
  fi
fi

if bash -n "$ROOT_DIR/completions/cpath.bash"; then
  pass "completions/cpath.bash passes bash -n syntax check"
else
  fail "completions/cpath.bash failed bash -n syntax check"
fi

# Verify Bash completion does NOT glob local files on "Host *" and does NOT evaluate shell syntax
MOCK_SSH_HOME="$TMP_ROOT/ssh-home"
GLOB_DIR="$TMP_ROOT/glob-cwd"
INJECT_MARKER="$GLOB_DIR/injected-pwned"
mkdir -p "$MOCK_SSH_HOME/.ssh" "$GLOB_DIR/My Dir" "$GLOB_DIR/staging"
touch "$GLOB_DIR/report.txt" "$GLOB_DIR/My Notes.txt" "$GLOB_DIR/My Dir/inside.txt" \
  "$GLOB_DIR/"$'tax-report\n2026.txt' "$GLOB_DIR/\$(touch injected-pwned)"
touch "$GLOB_DIR/ends-in-quote\""
cat > "$MOCK_SSH_HOME/.ssh/config" <<'SSHCFG'
Host prod-api web-01 staging
  HostName 10.0.0.1
Host $(touch injected-pwned)
  HostName 10.0.0.2
Host *
  ServerAliveInterval 60
SSHCFG

bash_comp_all=$(cd "$GLOB_DIR" && HOME="$MOCK_SSH_HOME" XDG_CONFIG_HOME="$TEST_XDG" bash -c '
  source "$1"
  COMP_WORDS=(cpath "--set-host" "")
  COMP_CWORD=2
  _cpath_completions
  printf "%s\n" "${COMPREPLY[@]}"
' _ "$ROOT_DIR/completions/cpath.bash")
assert_not_contains "bash completion does not leak cwd files via Host *" "report.txt" "$bash_comp_all"
assert_true "bash completion never evaluates command substitution in candidates" test ! -e "$INJECT_MARKER"
assert_contains "bash completion includes prod-api" "prod-api" "$bash_comp_all"

mkdir "$GLOB_DIR/empty"
assert_true "legacy path completion in an empty directory preserves the caller's glob options" \
  bash -s -- "$ROOT_DIR/completions/cpath.bash" "$GLOB_DIR/empty" <<'BASH'
if type compopt >/dev/null 2>&1; then enable -n compopt; fi
source "$1"
cd "$2" || exit 1
shopt -s failglob dotglob
shopt -u nullglob
COMP_WORDS=(cpath -p absent)
COMP_CWORD=2
_cpath_completions cpath absent -p
[ "${#COMPREPLY[@]}" -eq 0 ] && shopt -q failglob && shopt -q dotglob && ! shopt -q nullglob
BASH

# Real interactive Bash PTY Tab completion for space, '=' forms, no-match host, path fallback & no-compopt fallback!
tab_results=$(python3 - "$ROOT_DIR/completions/cpath.bash" "$MOCK_SSH_HOME" "$TEST_XDG" "$GLOB_DIR" "$CPATH_BIN" <<'PY'
import errno, fcntl, os, pty, select, shlex, subprocess, sys, termios, time
comp_script, mock_home, xdg, cwd, cpath_bin = sys.argv[1:6]

def test_tab(typed, disable_compopt=False, run_enter=False):
    master, slave = pty.openpty()
    env = os.environ.copy()
    env["HOME"] = mock_home
    env["XDG_CONFIG_HOME"] = xdg
    env["PATH"] = os.path.dirname(cpath_bin) + ":" + env.get("PATH", "")
    env["PS1"] = "PROMPT> "

    def setup_ctty():
        os.setsid()
        fcntl.ioctl(slave, termios.TIOCSCTTY, 0)

    proc = subprocess.Popen(
        ["bash", "--norc", "--noprofile", "-i"],
        cwd=cwd, env=env, stdin=slave, stdout=slave, stderr=slave,
        preexec_fn=setup_ctty, close_fds=True,
    )
    os.close(slave)

    def drain(timeout=0.15):
        out = b""
        end = time.time() + timeout
        while time.time() < end:
            r, _, _ = select.select([master], [], [], 0.05)
            if not r:
                continue
            try:
                chunk = os.read(master, 4096)
                if not chunk:
                    break
                out += chunk
            except OSError as e:
                if e.errno == errno.EIO:
                    break
                raise
        return out

    drain(0.25)
    if disable_compopt:
        os.write(master, b"enable -n compopt\n")
        drain(0.15)
    os.write(master, f"source {shlex.quote(comp_script)}\n".encode())
    drain(0.25)
    os.write(master, typed.encode())
    out = drain(0.35).decode(errors="replace")
    if run_enter:
        os.write(master, b"\n")
        out += drain(0.35).decode(errors="replace")
    proc.kill()
    proc.wait()
    os.close(master)
    return out

out_space = test_tab("cpath --set-host pro\t")
out_eq_prefix = test_tab("cpath --set-host=pro\t")
out_eq_web = test_tab("cpath --set-host=web\t")
out_nomatch_space = test_tab("cpath --set-host rep\t")
out_nomatch_eq = test_tab("cpath --set-host=rep\t")
out_path_file = test_tab("cpath rep\t")
out_nocompopt_file = test_tab("cpath -p My\\ N\t", disable_compopt=True, run_enter=True)
out_nocompopt_dir = test_tab("cpath -p My\\ D\t\t", disable_compopt=True)
out_nocompopt_nomatch = test_tab("cpath --set-host rep\t", disable_compopt=True)
out_nocompopt_host_dir = test_tab("cpath --set-host sta\t", disable_compopt=True, run_enter=True)
out_nocompopt_nl_file = test_tab("cpath -p tax\t", disable_compopt=True, run_enter=True)

cwd_canon = os.path.realpath(cwd)
expected_notes = os.path.join(cwd_canon, "My Notes.txt")
home_config = os.path.realpath(os.path.join(mock_home, ".ssh", "config"))
for label, typed, expected in (
    ("DOUBLE_QUOTE", 'cpath -p "My No\t', expected_notes),
    ("SINGLE_QUOTE", "cpath -p 'My No\t", expected_notes),
    ("LITERAL_FINAL_QUOTE", 'cpath -p "ends-in\t', os.path.join(cwd_canon, 'ends-in-quote"')),
    ("BARE_HOME", "cpath -p $HOME/.ssh/con\t", home_config),
    ("QUOTED_HOME", 'cpath -p "$HOME"/.ssh/con\t', home_config),
):
    output = test_tab(typed, disable_compopt=True, run_enter=True)
    print(label + "_OK=" + ("yes" if expected in output.splitlines() else "no:" + repr(output)))
expected_nl_base = os.path.join(cwd_canon, "tax-report")
with open(os.path.join(xdg, "cpath", "host"), "r") as hf:
    saved_staging = hf.read().strip()
print("SPACE_OK=" + ("yes" if "cpath --set-host prod-api" in out_space else "no:" + repr(out_space)))
print("EQ_PRO_OK=" + ("yes" if "cpath --set-host=prod-api" in out_eq_prefix else "no:" + repr(out_eq_prefix)))
print("EQ_WEB_OK=" + ("yes" if "cpath --set-host=web-01" in out_eq_web else "no:" + repr(out_eq_web)))
print("NOMATCH_SPACE_OK=" + ("yes" if "report.txt" not in out_nomatch_space else "no:" + repr(out_nomatch_space)))
print("NOMATCH_EQ_OK=" + ("yes" if "report.txt" not in out_nomatch_eq else "no:" + repr(out_nomatch_eq)))
print("PATH_FILE_OK=" + ("yes" if "cpath report.txt" in out_path_file else "no:" + repr(out_path_file)))
print("NOCOMPOPT_SPACE_FILE_OK=" + ("yes" if expected_notes in out_nocompopt_file else "no:" + repr(out_nocompopt_file)))
print("NOCOMPOPT_SPACE_DIR_OK=" + ("yes" if "My\\ Dir/inside.txt" in out_nocompopt_dir else "no:" + repr(out_nocompopt_dir)))
print("NOCOMPOPT_NOMATCH_OK=" + ("yes" if "report.txt" not in out_nocompopt_nomatch else "no:" + repr(out_nocompopt_nomatch)))
print("NOCOMPOPT_HOST_NO_SLASH_OK=" + ("yes" if saved_staging == "staging" and "staging/" not in out_nocompopt_host_dir else "no:" + repr((saved_staging, out_nocompopt_host_dir))))
print("NOCOMPOPT_NL_FILE_OK=" + ("yes" if (expected_nl_base + "\r\n2026.txt" in out_nocompopt_nl_file or expected_nl_base + "\n2026.txt" in out_nocompopt_nl_file) else "no:" + repr(out_nocompopt_nl_file)))
PY
)
assert_contains "real Bash Tab completes 'cpath --set-host pro'" "SPACE_OK=yes" "$tab_results"
assert_contains "real Bash Tab completes 'cpath --set-host=pro'" "EQ_PRO_OK=yes" "$tab_results"
assert_contains "real Bash Tab completes 'cpath --set-host=web'" "EQ_WEB_OK=yes" "$tab_results"
assert_contains "real Bash Tab does NOT complete local file for unmatched '--set-host rep'" "NOMATCH_SPACE_OK=yes" "$tab_results"
assert_contains "real Bash Tab does NOT complete local file for unmatched '--set-host=rep'" "NOMATCH_EQ_OK=yes" "$tab_results"
assert_contains "real Bash Tab still completes local file in path position ('cpath rep')" "PATH_FILE_OK=yes" "$tab_results"
assert_contains "no-compopt fallback keeps spaced filename as one arg" "NOCOMPOPT_SPACE_FILE_OK=yes" "$tab_results"
assert_contains "no-compopt fallback continues into spaced directory" "NOCOMPOPT_SPACE_DIR_OK=yes" "$tab_results"
assert_contains "no-compopt fallback still does NOT leak file on unmatched '--set-host rep'" "NOCOMPOPT_NOMATCH_OK=yes" "$tab_results"
assert_contains "no-compopt fallback does NOT append '/' to host alias matching local dir" "NOCOMPOPT_HOST_NO_SLASH_OK=yes" "$tab_results"
assert_contains "no-compopt fallback completes filename containing newline intact" "NOCOMPOPT_NL_FILE_OK=yes" "$tab_results"
assert_contains "legacy completion of double-quoted filename" "DOUBLE_QUOTE_OK=yes" "$tab_results"
assert_contains "legacy completion of single-quoted filename" "SINGLE_QUOTE_OK=yes" "$tab_results"
assert_contains "legacy completion closes quotes after a literal quote in a filename" "LITERAL_FINAL_QUOTE_OK=yes" "$tab_results"
assert_contains "legacy completion of path under HOME" "BARE_HOME_OK=yes" "$tab_results"
assert_contains "legacy completion of path under quoted HOME" "QUOTED_HOME_OK=yes" "$tab_results"

if command -v zsh >/dev/null 2>&1; then
  zsh_comp_hosts=$(HOME="$MOCK_SSH_HOME" XDG_CONFIG_HOME="$TEST_XDG" zsh -c '
    _describe() { print -l -- "${(@P)4}"; }
    _arguments() { :; }
    source "$1"
    _cpath_host_aliases
  ' _ "$ROOT_DIR/completions/_cpath")
  assert_contains "zsh completion suggests ~/.ssh/config host prod-api" "prod-api:~/.ssh/config host" "$zsh_comp_hosts"
  assert_contains "zsh completion suggests ~/.ssh/config host web-01" "web-01:~/.ssh/config host" "$zsh_comp_hosts"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed."
[ "$FAIL_COUNT" -eq 0 ]
