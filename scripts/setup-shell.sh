#!/usr/bin/env bash

set -euxo pipefail

source "$(dirname "$0")/common.sh"

# Check if fish is installed
if ! command -v fish &>/dev/null; then
  log_error "fish is not installed. Please install fish first."
  exit 1
fi

# Change default shell to fish (skip in CI)
if [[ -n "${CI:-}" ]]; then
  log_info "Skipping shell change in CI environment."
else
  current_shell=$(basename "$SHELL")
  if [[ "$current_shell" != "fish" ]]; then
    log_info "Changing default shell to fish..."
    chsh -s "$(command -v fish)"
    log_success "Default shell changed to fish. Please log out and log back in for changes to take effect."
  else
    log_success "Default shell is already fish."
  fi
fi
