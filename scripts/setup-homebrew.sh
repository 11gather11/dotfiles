#!/usr/bin/env bash

set -euxo pipefail

source "$(dirname "$0")/common.sh"

# Check if Homebrew is already installed
if command -v brew &>/dev/null; then
  log_success "Homebrew is already installed."
else
  # Install Homebrew
  log_info "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Add Homebrew to PATH for this session
  if [ -f /home/linuxbrew/.linuxbrew/bin/brew ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  fi
  log_success "Homebrew installed successfully."
fi

# Update Homebrew
log_info "Updating Homebrew..."
brew update
log_success "Homebrew updated."

# Install packages from Brewfile
log_info "Installing packages from Brewfile..."
brew bundle --file "${REPO_DIR}/config/homebrew/Brewfile" --verbose
log_success "Packages installed from Brewfile."
