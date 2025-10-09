#!/usr/bin/env bash

set -euxo pipefail

source "$(dirname "$0")/common.sh"

# Check if zsh is installed
if ! command -v zsh &>/dev/null; then
  log_error "zsh is not installed. Please install zsh first."
  exit 1
fi

# Change default shell to zsh (skip in CI)
if [[ -n "${CI:-}" ]]; then
  log_info "Skipping shell change in CI environment."
else
  current_shell=$(basename "$SHELL")
  if [[ "$current_shell" != "zsh" ]]; then
    log_info "Changing default shell to zsh..."
    chsh -s "$(command -v zsh)"
    log_success "Default shell changed to zsh. Please log out and log back in for changes to take effect."
  else
    log_success "Default shell is already zsh."
  fi
fi
