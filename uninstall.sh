#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${CPATH_INSTALL_DIR:-$HOME/.local/bin}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/cpath"
ZSH_COMP_DIR="${CPATH_ZSH_COMPLETION_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions}"
BASH_COMP_DIR="${CPATH_BASH_COMPLETION_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions}"

removed=0

if [ -e "$INSTALL_DIR/cpath" ] || [ -L "$INSTALL_DIR/cpath" ]; then
  rm -f "$INSTALL_DIR/cpath"
  echo "Removed $INSTALL_DIR/cpath"
  removed=1
fi

if [ -e "$ZSH_COMP_DIR/_cpath" ] || [ -L "$ZSH_COMP_DIR/_cpath" ]; then
  rm -f "$ZSH_COMP_DIR/_cpath"
  echo "Removed $ZSH_COMP_DIR/_cpath"
  removed=1
fi

if [ -e "$BASH_COMP_DIR/cpath" ] || [ -L "$BASH_COMP_DIR/cpath" ]; then
  rm -f "$BASH_COMP_DIR/cpath"
  echo "Removed $BASH_COMP_DIR/cpath"
  removed=1
fi

if [ -d "$CONFIG_DIR" ]; then
  rm -rf "$CONFIG_DIR"
  echo "Removed $CONFIG_DIR"
  removed=1
fi

if [ "$removed" -eq 0 ]; then
  echo "cpath is not installed (nothing to remove)."
else
  echo "cpath has been uninstalled."
fi
