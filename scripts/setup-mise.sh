#!/usr/bin/env bash

set -euxo pipefail

source "$(dirname "$0")/common.sh"

# Check if mise is installed
if ! command -v mise &>/dev/null; then
  log_error "mise is not installed. Please install mise first."
  exit 1
fi

# Install tools from config.toml
log_info "Installing tools from mise config..."
mise install
log_success "mise tools installed."

# Trust the config
log_info "Trusting mise config..."
mise trust
log_success "mise config trusted."
