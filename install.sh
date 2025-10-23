#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_DIR="${INSTALL_DIR:-$HOME/repos/github.com/11gather11/dotfiles}"

# Check if the git is installed
if ! command -v git &>/dev/null; then
  echo "Error: git is not installed."
  exit 1
fi

if [ -d "$INSTALL_DIR" ]; then
  echo "Updating dotfiles..."
  git -C "$INSTALL_DIR" pull || {
    echo "Failed to update dotfiles."
    exit 1
  }
else
  echo "Installing dotfiles..."
  mkdir -p "$(dirname "$INSTALL_DIR")"
  git clone https://github.com/11gather11/dotfiles "$INSTALL_DIR" || {
    echo "Failed to clone dotfiles."
    exit 1
  }
fi

if [ -f "$INSTALL_DIR/bin/setup.sh" ]; then
  /bin/bash "$INSTALL_DIR/bin/setup.sh"
else
  echo "Warning: setup script not found"
fi
