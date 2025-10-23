#!/usr/bin/env bash

set -Eeuo pipefail

source "$(dirname "$0")/lib/common.sh"

fmt_title_underline "Setting up shell"

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
    fish_path=$(command -v fish)

    # Add fish to /etc/shells if not already present
    if ! grep -q "^${fish_path}$" /etc/shells 2>/dev/null; then
      log_info "Adding ${fish_path} to /etc/shells..."
      echo "$fish_path" | sudo tee -a /etc/shells >/dev/null
      log_success "Added ${fish_path} to /etc/shells."
    fi

    chsh -s "$fish_path"
    log_success "Default shell changed to fish. Please log out and log back in for changes to take effect."
  else
    log_success "Default shell is already fish."
  fi
fi
