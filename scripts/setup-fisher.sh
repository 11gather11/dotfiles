#!/usr/bin/env bash

set -euxo pipefail

source "$(dirname "$0")/common.sh"

# Check if fish is installed
if ! command -v fish &>/dev/null; then
  log_error "fish is not installed. Please install fish first."
  exit 1
fi

log_info "Setting up Fisher plugin manager..."

# Install Fisher if not already installed
if ! fish -c "type -q fisher" &>/dev/null; then
  log_info "Installing Fisher..."
  fish -c "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher"
  log_success "Fisher installed successfully."
else
  log_success "Fisher is already installed."
fi

# Install plugins from fish_plugins file
if [ -f "$HOME/.config/fish/fish_plugins" ]; then
  log_info "Installing Fisher plugins from fish_plugins..."
  fish -c "fisher update"
  log_success "Fisher plugins installed successfully."
else
  log_warning "fish_plugins file not found. Skipping plugin installation."
fi
