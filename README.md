# cpath

**Zero-dependency CLI to copy absolute paths across local shells and SSH (OSC 52).**

English | [简体中文](README.zh-CN.md)

`cpath` is a zero-dependency standalone Bash CLI tool that copies (or prints) normalized absolute paths for files and directories. It automatically detects local clipboard backends (macOS, Linux Wayland/X11, Windows WSL) and seamlessly switches to **OSC 52** over SSH—no X11 forwarding or shell framework required.

## Features

- **Zero dependencies & shell-agnostic**: Standalone executable script (`~/.local/bin/cpath`) that works in Bash, Zsh, Fish, and subshells.
- **Local & SSH clipboard support**: Automatically uses `pbcopy`, `wl-copy`, `xclip`, `xsel`, or `clip.exe` locally, and **OSC 52** over SSH to write directly to your local clipboard.
- **Context-aware host aliases**: Output `host:/abs/path` (`-s`) or `user@host:/abs/path` (`-u`) for `scp`/`rsync`, with smart host resolution priority.
- **Minimal ergonomics**: Defaults to the current directory, supports bundled short flags (`-sd`, `-ud`, `-dn`), multi-file newline copying, and print-only mode (`-p`).
- **Symlink control**: Resolves symlinks recursively by default; pass `-n` to preserve logical symlink paths.
- **Shell completions included**: Comes with both Zsh (`completions/_cpath`) and Bash (`completions/cpath.bash`) completions for flags, paths, and `--set-host` aliases (including hosts from `~/.ssh/config`).

## Installation

### One-line install

```bash
curl -fsSL https://raw.githubusercontent.com/Arcadiastra/cpath/main/install.sh | bash
```

During interactive installation, you can optionally set a persistent host alias for the machine (press **Enter** to skip and use the dynamic hostname). In non-interactive / CI / container environments, the prompt is silently skipped.

### Debian / Ubuntu (`.deb` package)

Download the `.deb` asset from [GitHub Releases](https://github.com/Arcadiastra/cpath/releases) and install with `apt` (includes `/usr/bin/cpath`, Bash/Zsh completions, and `man cpath`):

```bash
curl -fsSLO https://github.com/Arcadiastra/cpath/releases/download/v0.1.0/cpath_0.1.0_all.deb
sudo apt install ./cpath_0.1.0_all.deb
```

### Homebrew (macOS / Linux)

Install `cpath`, its Bash and Zsh completions, and its man page from the [Homebrew tap](https://github.com/Arcadiastra/homebrew-tap).

```bash
brew install arcadiastra/tap/cpath
```

### Install from a local clone

```bash
git clone https://github.com/Arcadiastra/cpath.git
cd cpath
./install.sh
```

### Custom install locations

| Environment Variable | Default |
| --- | --- |
| `CPATH_INSTALL_DIR` | `~/.local/bin` |
| `CPATH_ZSH_COMPLETION_DIR` | `${XDG_DATA_HOME:-~/.local/share}/zsh/site-functions` |
| `CPATH_BASH_COMPLETION_DIR` | `${XDG_DATA_HOME:-~/.local/share}/bash-completion/completions` |
| `CPATH_NONINTERACTIVE` | *(unset; set to `1` to skip host alias prompt)* |

## Usage

```text
cpath [OPTIONS] [PATH...]
```

### Options

| Option | Description | Example Output |
| --- | --- | --- |
| *(none)* | Copy canonical absolute path of current directory (`.`) | `/var/www/app` |
| `-d` | Copy parent directory if `PATH` is a file | `/var/www` |
| `-s` | Prepend host (`host:/abs/path`) | `prod-api:/var/www/app` |
| `-u` | Prepend user and host (`user@host:/abs/path`) | `alice@prod-api:/var/www/app` |
| `-n` | Do not resolve symlinks (logical path, like `realpath -s`) | `/var/www/current` |
| `-p` | Print to stdout only; do not write to clipboard | `/var/www/app` |
| `--set-host [ALIAS]` | Save persistent host alias to `~/.config/cpath/host` | — |
| `--clear-host` | Remove saved host alias (fallback to dynamic resolution) | — |
| `-h`, `--help` | Show help message | — |
| `-v`, `--version` | Show version | — |

### Examples

```bash
# Copy current directory path
cpath

# Copy canonical path of a file
cpath ./config/app.yaml

# Copy the directory containing a file
cpath -d ./config/app.yaml

# Copy host:path for scp / rsync (great with ~/.ssh/config aliases)
cpath -s ./build/release.tar.gz

# Copy user@host:parent_dir using bundled short options
cpath -ud ./logs/error.log

# Keep symlink path without dereferencing
cpath -n /var/www/current/index.html

# Copy multiple paths (separated by newlines)
cpath src/main.go src/server.go

# Print only for scripts or pipes
scp "$(cpath -sp ./artifact.tar.gz)" ./
```

## Hostname Resolution Priority

When `-s` or `-u` is used, `cpath` resolves the host name in the following order (highest to lowest):

1. **`$CPATH_HOST`** — One-off override for a single command:
   ```bash
   CPATH_HOST=bastion cpath -s ./dump.sql
   ```
2. **`~/.config/cpath/host`** — Persistent per-machine alias set during install or via `cpath --set-host prod-api`.
3. **`$LC_SSH_HOST`** — Dynamically forwarded from your local `~/.ssh/config` via `SetEnv`.
4. **`$(hostname)`** — Current system hostname fallback.

### Tip: Auto-forward SSH Config Aliases with `SetEnv`

OpenSSH servers commonly allow `LC_*` environment variables by default (`AcceptEnv LANG LC_*` in `/etc/ssh/sshd_config`). You can pass your local SSH alias automatically without storing any config on remote servers:

```sshconfig
# ~/.ssh/config (on your local machine)
Host prod-api
  HostName 10.0.1.42
  User alice
  SetEnv LC_SSH_HOST=prod-api
```

Then on the remote machine, `cpath -s app.log` automatically produces `prod-api:/path/to/app.log`—even if the server's internal hostname is `ip-10-0-1-42`.

## Clipboard & OSC 52 Compatibility

### Local Backends

When not in an SSH session, `cpath` probes clipboard utilities in this order:

| Platform | Backend | Detection |
| --- | --- | --- |
| macOS | `pbcopy` | `command -v pbcopy` |
| Linux (Wayland) | `wl-copy` | `$WAYLAND_DISPLAY` + `wl-copy` |
| Linux (X11) | `xclip` / `xsel` | `$DISPLAY` + `xclip` or `xsel` |
| Windows WSL | `clip.exe` | `command -v clip.exe` |

### SSH Remote Clipboard (OSC 52) Terminal Support

When `$SSH_CONNECTION`, `$SSH_TTY`, or `$SSH_CLIENT` is detected, `cpath` emits a standard OSC 52 escape sequence (`\033]52;c;<base64>\a`).

| Terminal | OSC 52 Support | Notes |
| --- | --- | --- |
| **WezTerm** | Built-in | Works out of the box |
| **Ghostty** | Built-in | Works out of the box |
| **Kitty** | Built-in | Works out of the box (`clipboard_control write-clipboard`) |
| **Alacritty** | Built-in | Works out of the box |
| **Foot** | Built-in | Works out of the box |
| **Windows Terminal** | Built-in | Works out of the box (v1.15+) |
| **VS Code Terminal** | Built-in | Works out of the box |
| **iTerm2** | Supported | Enable *Preferences → General → Selection → Applications in terminal may access clipboard* |
| **macOS Terminal.app** | Not supported | Use one of the modern terminals above |

### Using inside `tmux`

In modern `tmux` (3.2+), add the following line to `~/.tmux.conf` so standard OSC 52 sequences pass through to your outer terminal:

```tmux
set -s set-clipboard on
```

Then reload tmux config with `tmux source-file ~/.tmux.conf`.

## Shell Completions

`install.sh` automatically installs both Zsh and Bash completions when those shells are detected:

### Zsh

Installed to `${XDG_DATA_HOME:-~/.local/share}/zsh/site-functions/_cpath`. Ensure that directory is in your `fpath` before `compinit` in `~/.zshrc`:

```zsh
fpath=("${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions" $fpath)
autoload -Uz compinit && compinit
```

If you use **Oh My Zsh**, you can alternatively install directly into its custom completions directory:

```bash
CPATH_ZSH_COMPLETION_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/completions" ./install.sh
```

### Bash

Installed to `${XDG_DATA_HOME:-~/.local/share}/bash-completion/completions/cpath`, which is auto-loaded on demand by `bash-completion` v2+.

If you don't use `bash-completion`, source it directly in `~/.bashrc`:

```bash
source "${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions/cpath"
```

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/Arcadiastra/cpath/main/uninstall.sh | bash
```

Or from a local clone:

```bash
./uninstall.sh
```

## Development & Testing

Run the self-contained test suite (and optional `shellcheck` lint):

```bash
./tests/test_cpath.sh
shellcheck bin/cpath install.sh uninstall.sh completions/cpath.bash tests/test_cpath.sh
```

## License

[MIT](LICENSE)
