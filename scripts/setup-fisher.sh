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
if ! fish -c "type -q fisher"; then
  log_info "Installing Fisher..."
  fish -c "curl -sL https://git.io/fisher | source && fisher update"
  log_success "Fisher installed successfully."
else
  log_success "Fisher is already installed."
fi
