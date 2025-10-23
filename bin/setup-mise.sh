#!/usr/bin/env bash

set -Eeuo pipefail

source "$(dirname "$0")/lib/common.sh"

fmt_title_underline "Setting up mise"

# Check if mise is installed
if ! command -v mise &>/dev/null; then
  log_error "mise is not installed. Please install mise first."
  exit 1
fi

# Install tools from config.toml
log_info "Installing tools from mise config..."
mise install
log_success "mise tools installed."

# Trust the config (ignore if already trusted)
log_info "Trusting mise config..."
mise trust 2>/dev/null || true
log_success "mise config trusted."
