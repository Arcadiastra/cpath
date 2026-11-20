#!/usr/bin/env bash
set -euo pipefail
unset CDPATH

REPO_SLUG="${CPATH_REPO:-Arcadiastra/cpath}"
REPO_REF="${CPATH_REF:-main}"
REPO_RAW_BASE="https://raw.githubusercontent.com/${REPO_SLUG}/${REPO_REF}"
INSTALL_DIR="${CPATH_INSTALL_DIR:-$HOME/.local/bin}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/cpath"
HOST_FILE="$CONFIG_DIR/host"
ZSH_COMP_DIR="${CPATH_ZSH_COMPLETION_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions}"
BASH_COMP_DIR="${CPATH_BASH_COMPLETION_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions}"

SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fi

trim_whitespace() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

has_tty() {
  (exec </dev/tty >/dev/tty) 2>/dev/null
}

get_system_hostname() {
  if command -v hostname >/dev/null 2>&1; then
    hostname
  else
    uname -n
  fi
}

download_file() {
  local url="$1"
  local dest="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$dest"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$dest" "$url"
  else
    echo "Error: neither 'curl' nor 'wget' is available to download $url" >&2
    return 1
  fi
}

install_asset() {
  local rel_path="$1"
  local dest="$2"
  local mode="$3"
  local dest_dir tmp_file

  dest_dir=$(dirname "$dest")
  mkdir -p "$dest_dir"
  tmp_file=$(mktemp "${dest_dir}/.cpath-install.XXXXXX")

  if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/$rel_path" ]; then
    cp "$SCRIPT_DIR/$rel_path" "$tmp_file"
  else
    if ! download_file "${REPO_RAW_BASE}/${rel_path}" "$tmp_file"; then
      rm -f "$tmp_file"
      return 1
    fi
  fi

  chmod "$mode" "$tmp_file"
  mv -f "$tmp_file" "$dest"
}

install_binary() {
  install_asset "bin/cpath" "$INSTALL_DIR/cpath" 755
  echo "Installed cpath to $INSTALL_DIR/cpath"
}

install_completions() {
  if [ -n "${CPATH_ZSH_COMPLETION_DIR:-}" ] || command -v zsh >/dev/null 2>&1; then
    install_asset "completions/_cpath" "$ZSH_COMP_DIR/_cpath" 644
    echo "Installed Zsh completion to $ZSH_COMP_DIR/_cpath"
  fi

  if [ -n "${CPATH_BASH_COMPLETION_DIR:-}" ] || command -v bash >/dev/null 2>&1; then
    install_asset "completions/cpath.bash" "$BASH_COMP_DIR/cpath" 644
    echo "Installed Bash completion to $BASH_COMP_DIR/cpath"
  fi
}

configure_host_alias() {
  # Silently skip interactive configuration in non-TTY / CI / automated runs
  if [ -n "${CPATH_NONINTERACTIVE:-}" ] || [ -n "${CI:-}" ] || ! has_tty; then
    return 0
  fi

  local current_host existing_alias alias_input
  current_host=$(get_system_hostname)
  existing_alias=""
  alias_input=""

  if [ -s "$HOST_FILE" ]; then
    existing_alias=$(tr -d '\r\n' < "$HOST_FILE")
    existing_alias=$(trim_whitespace "$existing_alias")
  fi

  while true; do
    if [ -n "$existing_alias" ]; then
      printf "SSH host alias for this machine [current: %s] (Enter to keep, 'clear' for dynamic '%s'): " \
        "$existing_alias" "$current_host" >/dev/tty
    else
      printf "SSH host alias for this machine (Enter to use dynamic hostname '%s'): " "$current_host" >/dev/tty
    fi

    if ! IFS= read -r alias_input </dev/tty; then
      echo ""
      return 0
    fi
    alias_input=$(trim_whitespace "$alias_input")

    if [ -n "$existing_alias" ]; then
      case "$alias_input" in
        "")
          echo "Keeping existing host alias: $existing_alias"
          return 0
          ;;
        clear|CLEAR)
          "$INSTALL_DIR/cpath" --clear-host
          return 0
          ;;
      esac
    else
      case "$alias_input" in
        ""|n|N)
          rm -f "$HOST_FILE"
          echo "Using dynamic hostname (current: $current_host)"
          return 0
          ;;
      esac
    fi

    if "$INSTALL_DIR/cpath" --set-host "$alias_input"; then
      return 0
    fi
  done
}

check_path() {
  case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *)
      echo ""
      echo "Notice: '$INSTALL_DIR' is not in your PATH."
      echo "Add this line to your ~/.bashrc or ~/.zshrc:"
      echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
      ;;
  esac
}

check_zsh_fpath() {
  if [ ! -f "$ZSH_COMP_DIR/_cpath" ]; then
    return 0
  fi

  local in_fpath=0
  if command -v zsh >/dev/null 2>&1; then
    if zsh -ic 'print -l -- $fpath' 2>/dev/null | grep -Fqx "$ZSH_COMP_DIR"; then
      in_fpath=1
    fi
  fi

  if [ "$in_fpath" -eq 0 ]; then
    echo ""
    echo "Notice: To enable Zsh completion, add this before 'compinit' in ~/.zshrc:"
    echo "  fpath=(\"$ZSH_COMP_DIR\" \$fpath)"
    echo "  autoload -Uz compinit && compinit"
  fi
}

install_binary
install_completions
configure_host_alias
check_path
check_zsh_fpath
echo ""
echo "Done! Try running: cpath"
