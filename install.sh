#!/usr/bin/env bash
set -euxo pipefail

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)" || exit 1

# Load common utilities if available
if [ -f "$SCRIPT_DIR/scripts/common.sh" ]; then
  # shellcheck source=scripts/common.sh
  source "$SCRIPT_DIR/scripts/common.sh"
else
  echo "Error: Unable to source common.sh"
  exit 1
fi

INSTALL_DIR="${INSTALL_DIR:-$HOME/repos/github.com/11gather11/dotfiles}"

# Check if git is installed
if ! command -v git &>/dev/null; then
  log_error "git is not installed"
  exit 1
fi

if [ -d "$INSTALL_DIR" ]; then
  log_info "Updating dotfiles..."
  git -C "$INSTALL_DIR" pull || {
    log_error "Failed to update dotfiles"
    exit 1
  }
  log_success "Dotfiles updated successfully"
else
  log_info "Installing dotfiles..."
  mkdir -p "$(dirname "$INSTALL_DIR")"
  git clone https://github.com/11gather11/dotfiles "$INSTALL_DIR" || {
    log_error "Failed to clone dotfiles"
    exit 1
  }
  log_success "Dotfiles installed successfully"
fi

if [ -f "$INSTALL_DIR/scripts/setup.sh" ]; then
  log_info "Running setup script..."
  /bin/bash "$INSTALL_DIR/scripts/setup.sh"
else
  log_warning "Setup script not found"
fi
